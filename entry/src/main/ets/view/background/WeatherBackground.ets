/*
 * The animated weather background.
 *
 * Port of MaterialWeatherView.kt â€” a full-bleed canvas behind the card list, repainted every
 * frame. CLAUDE.md maps this to "ArkUI Canvas + displaySync frame loop".
 *
 * The Kotlin drives the loop from the view's own choreographer and feeds each frame's elapsed
 * milliseconds to the implementor (IntervalComputer.kt). displaySync gives the same thing here:
 * onFrame carries a timestamp, and the delta between frames is the interval.
 *
 * The flat themed colour stays underneath: the implementors paint translucent shapes over it, and
 * the kinds without an implementor yet simply show the colour on its own.
 */

import { displaySync } from '@kit.ArkGraphics2D';
import { WeatherKind } from '../../model/WeatherKind';
import { BackgroundGradient, getWeatherBackgroundGradient } from '../../theme/AppColors';
import { createImplementor, WeatherImplementor } from './WeatherImplementors';
import { DelayRotateController, GravitySensor } from './GravitySensor';

@ComponentV2
export struct WeatherBackground {
  @Param kind: WeatherKind = WeatherKind.NULL;
  @Param daylight: boolean = true;
  @Param darkMode: boolean = false;
  /**
   * The flat theme colour the shapes are painted over. Named `sceneColor` rather than
   * `backgroundColor` because every component already inherits a `backgroundColor` attribute and
   * a @Param may not shadow it.
   */
  @Param sceneColor: string = '#FF000000';
  /**
   * MaterialWeatherView.scrollRate â€” 0 at the top of the page, 1 once the cards have covered the
   * background. At 1 the implementors skip drawing altogether.
   */
  @Param scrollRate: number = 0;
  /** SettingsManager.isBackgroundAnimationEnabled â€” animations off still draw one static frame. */
  @Param animate: boolean = true;
  /**
   * screen 3c's `main_screen_background` â€” MaterialWeatherView drawn at all, or not
   * (MainScreenSettingsScreen.kt:127-138, `mainScreenBackgroundEnabled`).
   *
   * Off skips BOTH the particle scene and the sky gradient, leaving the page on its flat surface
   * colour. It is checked inside `drawFrame` rather than by dropping the Canvas from the tree: the
   * Canvas is what the whole page is laid out over, and removing it would re-layout the page
   * instead of just changing what is painted on it.
   */
  @Param sceneEnabled: boolean = true;
  /**
   * screen 3c's `gravity_sensor_switch` — HomeFragment.kt:179-181 passes it straight into the
   * weather view. Off means no subscription and both rotations pinned at 0, which is what
   * ContextExtensions.kt:80-85 achieves by handing back a null SensorManager.
   */
  @Param gravitySensorEnabled: boolean = true;

  @Local private canvasWidth: number = 0;
  @Local private canvasHeight: number = 0;

  /* ----------------------------------------------------------------- gravity */

  private gravity: GravitySensor = new GravitySensor();
  /** MaterialPainterView.rotators (kt:56) — [0] is the 2D lean, [1] the 3D depth. */
  private rotator2D: DelayRotateController = new DelayRotateController(0);
  private rotator3D: DelayRotateController = new DelayRotateController(0);
  /** The smoothed angles the last frame drew at, so out-of-loop repaints stay put. */
  private smooth2D: number = 0;
  private smooth3D: number = 0;
  /**
   * MaterialPainterView.hasDrawn (kt:94, 256-262). With animations off the scene is advanced by a
   * real interval exactly once and by 0 thereafter — but the loop keeps running, because the
   * gravity parallax is not an animation and still has to track the phone.
   */
  private hasDrawn: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private implementor: WeatherImplementor | null = null;
  private sync: displaySync.DisplaySync | null = null;
  private lastTimestampNs: number = 0;
  /** MaterialPainterView.lastScrollRate (kt:66) â€” the rate the previous frame was drawn at. */
  private lastScrollRate: number = 0;

  /**
   * MaterialPainterView.kt:286-296 â€” the Android loop is self-scheduling: `onDraw` ends with
   * `postInvalidate()`, EXCEPT when the background has been fully covered for two consecutive
   * frames, in which case it returns without rescheduling and the animation simply stops. The
   * `scrollRate` setter (kt:69-76) restarts it the moment the rate drops back below 1.
   *
   * The port had no equivalent, so the displaySync loop ran forever. A trace taken while scrolled
   * down to the detail grid showed 430 canvas render tasks at 39 draw ops each â€” the sun/cloud
   * shapes being redrawn at 30 fps underneath cards that completely hide them, competing with the
   * drag for the UI thread. This app exists to be measured, so that cost is not acceptable either.
   */
  @Monitor('scrollRate')
  onScrollRateChanged(monitor: IMonitor): void {
    if (this.lastScrollRate >= 1 && this.scrollRate < 1) {
      this.startLoop();
    }
    // Covered but still running (e.g. the rate jumped straight to 1): let the next frame settle it.
  }

  /** True once the cards have covered the background for a second consecutive frame. */
  private isCovered(): boolean {
    return this.lastScrollRate >= 1 && this.scrollRate >= 1;
  }

  /* ------------------------------------------------------------------ cross-fade */

  /**
   * MaterialWeatherView.setWeather (kt:127-175) does NOT swap the scene. It keeps two
   * MaterialPainterViews, moves the current one to `mPreviousView`, builds the new one, and runs
   * an AnimatorSet over `SWITCH_ANIMATION_DURATION` fading the new one 0â†’1 while the old one goes
   * to 0. The port replaced the implementor outright, so swiping to another location snapped
   * straight to its theme â€” a screenshot taken mid-swipe caught Tokyo's night scene behind
   * Helsinki's daytime data.
   *
   * One canvas draws both: the outgoing scene is painted first, then the incoming scene over it at
   * the animated alpha, which is what the two stacked views amount to visually.
   */
  private previous: WeatherImplementor | null = null;
  private previousGradient: BackgroundGradient | null = null;
  private previousSceneColor: string = '';
  /** 1 once the incoming scene has fully replaced the outgoing one. */
  @Local private switchProgress: number = 1;

  /** MaterialWeatherView.SWITCH_ANIMATION_DURATION. */
  private static readonly SWITCH_DURATION_MS: number = 300;

  /** Rebuild the implementor whenever the weather, the theme or the size changes. */
  @Monitor('kind', 'daylight', 'darkMode', 'canvasWidth', 'canvasHeight')
  onSceneChanged(monitor: IMonitor): void {
    // Only a real scene change cross-fades; a resize just rebuilds in place.
    const sizeOnly: boolean = monitor.dirty.length > 0 &&
      monitor.dirty.every((name: string) => name === 'canvasWidth' || name === 'canvasHeight');
    if (!sizeOnly && this.implementor !== null) {
      this.previous = this.implementor;
      this.previousGradient = this.currentGradient;
      this.previousSceneColor = this.sceneColor;
      this.switchProgress = 0;
      animateTo({
        duration: WeatherBackground.SWITCH_DURATION_MS,
        curve: Curve.EaseInOut,
        onFinish: () => {
          // Drop the outgoing scene so it stops being drawn and can be collected.
          this.previous = null;
          this.previousGradient = null;
        }
      }, () => {
        this.switchProgress = 1;
      });
    }
    this.rebuild();
  }

  /** The gradient the incoming scene is painted on, cached so the fade can hold the old one. */
  private currentGradient: BackgroundGradient | null = null;

  /**
   * The fade drives its own frames. `drawFrame` is otherwise only called from the displaySync
   * loop, which is stopped whenever the cards cover the background â€” and a location switch can
   * happen in exactly that state, leaving the cross-fade frozen half-way.
   */
  @Monitor('switchProgress')
  onSwitchProgress(monitor: IMonitor): void {
    this.drawFrame();
  }

  @Monitor('sceneEnabled')
  onEnabledChanged(monitor: IMonitor): void {
    // Repaint immediately: the setting is changed on another page, so nothing else redraws this.
    this.drawFrame();
  }

  @Monitor('animate')
  onAnimateChanged(monitor: IMonitor): void {
    this.hasDrawn = false;
    if (this.needsLoop()) {
      this.startLoop();
    } else {
      this.stopLoop();
      this.drawFrame();
    }
  }

  @Monitor('gravitySensorEnabled')
  onGravityChanged(monitor: IMonitor): void {
    this.gravity.setEnabled(this.gravitySensorEnabled);
    if (this.needsLoop()) {
      // The rotators still have to chase back down to 0 after the setting is turned off, so the
      // loop runs either way until they have settled — stopping it here would freeze the lean.
      this.startLoop();
    } else {
      this.stopLoop();
      this.drawFrame();
    }
  }

  aboutToAppear(): void {
    this.gravity.setEnabled(this.gravitySensorEnabled);
    this.rebuild();
  }

  aboutToDisappear(): void {
    this.stopLoop();
    this.gravity.stop();
  }

  /**
   * The scene keeps repainting while either the shapes are animating or the sensor can still move
   * them. kt:286-296 has no such condition because upstream always reschedules; this port stops
   * the loop when nothing can change, which is what keeps the idle cost measurable.
   */
  private needsLoop(): boolean {
    return this.animate || this.gravitySensorEnabled;
  }

  private rebuild(): void {
    this.implementor = createImplementor(
      this.kind,
      this.daylight,
      this.darkMode,
      this.canvasWidth,
      this.canvasHeight
    );
    this.lastTimestampNs = 0;
    // kt:327-343 — a new implementor gets new rotators, seeded at the angle the phone is at now
    // so the scene does not swing in from level.
    this.hasDrawn = false;
    this.rotator2D = new DelayRotateController(this.gravity.rotation2D);
    this.rotator3D = new DelayRotateController(this.gravity.rotation3D);
    this.smooth2D = this.rotator2D.rotation;
    this.smooth3D = this.rotator3D.rotation;
    if (this.implementor === null || !this.needsLoop()) {
      this.stopLoop();
      this.drawFrame();
      return;
    }
    this.startLoop();
  }

  private startLoop(): void {
    if (this.sync !== null || this.implementor === null || !this.ready) {
      return;
    }
    const sync: displaySync.DisplaySync = displaySync.create();
    /*
     * 60, to MATCH THE OTHER PORT — measured, not assumed.
     *
     * This asked for 30 on the reasoning that "the background is decorative and 30 fps is plenty",
     * which halved the loop's cost. That reasoning is wrong for this project specifically: the NDK
     * drives its own `OH_NativeVSync` loop and was measured composing the same idle scene at
     * 60.3 fps against this port's 30.5. So the cheaper loop was not a shared choice — it was one
     * port animating at half the other's rate, which shows in a side-by-side recording AND biases
     * the CPU half of the very comparison the comment invoked to justify it.
     *
     * `max` stays 60 rather than the panel's 120: matching the two ports is the point, and neither
     * needs a decorative gradient at 120.
     */
    sync.setExpectedFrameRateRange({ expected: 60, min: 30, max: 60 });
    sync.on('frame', (frameInfo: displaySync.IntervalInfo) => {
      this.onFrame(frameInfo.timestamp);
    });
    sync.start();
    this.sync = sync;
  }

  private stopLoop(): void {
    if (this.sync === null) {
      return;
    }
    this.sync.stop();
    this.sync.off('frame');
    this.sync = null;
  }

  /** IntervalComputer.kt â€” the implementor is advanced by the real elapsed time, not a fixed step. */
  private onFrame(timestampNs: number): void {
    if (this.implementor === null) {
      return;
    }
    let interval: number = 0;
    if (this.lastTimestampNs > 0) {
      interval = (timestampNs - this.lastTimestampNs) / 1000000;
    }
    this.lastTimestampNs = timestampNs;
    // A backgrounded app can return with a huge gap; clamp so the shapes do not jump.
    if (interval < 0 || interval > 200) {
      interval = 0;
    }
    // kt:286-296 â€” fully covered for two frames running: stop, and reset the interval computer so
    // the first frame after it resumes does not advance the shapes by the whole idle period.
    if (this.isCovered()) {
      this.lastScrollRate = this.scrollRate;
      this.lastTimestampNs = 0;
      this.stopLoop();
      return;
    }
    this.lastScrollRate = this.scrollRate;

    // kt:251-253 — the rotators are advanced by the real interval whatever the animation setting
    // says, then read back as the angles this frame is drawn at.
    this.rotator2D.updateRotation(this.gravity.rotation2D, interval);
    this.rotator3D.updateRotation(this.gravity.rotation3D, interval);
    this.smooth2D = this.rotator2D.rotation;
    this.smooth3D = this.rotator3D.rotation;

    // kt:255-262 — animations off: advance the shapes once, then hold them.
    let dataInterval: number = interval;
    if (!this.animate) {
      if (this.hasDrawn) {
        dataInterval = 0;
      } else {
        this.hasDrawn = true;
      }
    }

    this.implementor.updateData(
      this.canvasWidth,
      this.canvasHeight,
      dataInterval,
      this.smooth2D,
      this.smooth3D
    );
    this.drawFrame();
  }

  private drawFrame(): void {
    if (!this.ready || this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return;
    }
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    /*
     * screen 3c's `main_screen_background`, off: the canvas is cleared and nothing else is drawn,
     * so the page shows its own surface colour through it. The cards keep their own backgrounds,
     * which is what the Android build looks like with the setting off.
     */
    if (!this.sceneEnabled) {
      return;
    }
    this.currentGradient = getWeatherBackgroundGradient(this.kind, this.daylight, this.darkMode);

    // The outgoing scene underneath, at full opacity â€” the incoming one fades in over it, which
    // is what MaterialWeatherView's two stacked painter views produce.
    if (this.previous !== null && this.switchProgress < 1) {
      this.paintScene(this.previousGradient, this.previousSceneColor, this.previous, 1);
    }
    this.paintScene(this.currentGradient, this.sceneColor, this.implementor, this.switchProgress);
  }

  /** One full-bleed scene: its gradient, then its particles, at `alpha`. */
  private paintScene(
    gradient: BackgroundGradient | null,
    sceneColor: string,
    implementor: WeatherImplementor | null,
    alpha: number
  ): void {
    if (alpha <= 0) {
      return;
    }
    const ctx = this.ctx;
    ctx.save();
    ctx.globalAlpha = alpha;
    // MaterialPainterView.kt:203 â€” the scene sits on a three-stop vertical gradient, not a flat
    // colour. `sceneColor` remains the fallback for WEATHER_KIND_NULL, whose Android drawable
    // (weather_background_default) is transparent.
    if (gradient === null) {
      ctx.fillStyle = sceneColor;
    } else {
      // angle="270" puts startColor at the top and endColor at the bottom.
      const fill: CanvasGradient = ctx.createLinearGradient(0, 0, 0, this.canvasHeight);
      fill.addColorStop(0, gradient.top);
      fill.addColorStop(0.5, gradient.middle);
      fill.addColorStop(1, gradient.bottom);
      ctx.fillStyle = fill;
    }
    ctx.fillRect(0, 0, this.canvasWidth, this.canvasHeight);
    if (implementor !== null) {
      implementor.draw(
        ctx,
        this.canvasWidth,
        this.canvasHeight,
        this.scrollRate,
        this.smooth2D,
        this.smooth3D
      );
    }
    ctx.restore();
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.ready = true;
        this.rebuild();
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const width: number = Number(newValue.width);
        const height: number = Number(newValue.height);
        // `Context.isLandscape`, which the device-orientation mapping branches on. The background
        // is full-bleed, so its own aspect is the same predicate.
        this.gravity.setLandscape(width > height);
        if (Math.abs(width - this.canvasWidth) > 0.5 || Math.abs(height - this.canvasHeight) > 0.5) {
          this.canvasWidth = width;
          this.canvasHeight = height;
        }
      })
  }
}
