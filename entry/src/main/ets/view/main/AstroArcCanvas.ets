/*
 * The arc in the Sun and Moon blocks.
 *
 * 1:1 port of SunMoonView.kt (ui/common/widgets/astro/SunMoonView.kt). It is a 135° slice of a
 * circle, not a bezier dome: onMeasure (kt:214-232) derives the radius from the available width
 * so the arc's two ends land exactly on the left and right insets.
 *
 *   deltaRadians = toRadians((180 - ARC_ANGLE) / 2)      kt:216
 *   radius       = width / 2 / cos(deltaRadians)          kt:217
 *   height       = radius - width / 2 * tan(deltaRadians) kt:218
 *
 * onDraw (kt:234-274) layers four things:
 *   1. the gradient shadow under the elapsed part (drawShadow, kt:276-306)
 *   2. the dashed 135° track plus the dashed baseline (kt:246-257)
 *   3. the solid elapsed arc (drawPathLine, kt:308-321)
 *   4. the sun/moon icon at the head of the elapsed arc (kt:266-273)
 *
 * Nothing but the track is drawn when mProgress <= 0 (kt:267, 277, 313) — that is what the
 * Android device shows for a moon whose set time precedes its rise.
 *
 * The icon is an overlaid Image rather than a canvas drawImage: the resource is a PNG and
 * positioning it as a sibling avoids an ImageBitmap load on every redraw.
 */

import { withAlpha } from '../../theme/AppColors';

/** SunMoonView.kt:330-338 */
const ICON_SIZE: number = 24;
const LINE_SIZE: number = 5;
const DOTTED_LINE_SIZE: number = 1;
const MARGIN: number = 16;
const ARC_ANGLE: number = 135;
/** kt:336-337 — the shadow is the line colour at this alpha, blended twice over the card. */
const SHADOW_ALPHA_FACTOR_LIGHT: number = 0.1;
const SHADOW_ALPHA_FACTOR_DARK: number = 0.2;
/** kt:95-101 — DashPathEffect(3dp, 2 * 3dp). */
const DASH_ON: number = 3;
const DASH_OFF: number = 6;

const DEG_TO_RAD: number = Math.PI / 180;

/** Geometry shared by the draw pass and the icon placement. */
class ArcGeometry {
  radius: number = 0;
  centerX: number = 0;
  centerY: number = 0;
  height: number = 0;
}

@ComponentV2
export struct AstroArcCanvas {
  /** Width the arc gets to fill, in vp. */
  @Param side: number = 0;
  /** Elapsed fraction, 0..1. Negative or zero leaves the arc unstarted. */
  @Param progress: number = -1;
  /** themeColors[0] — AstroViewHolder.kt:126-131. */
  @Param lineColor: string = '#FFFFFFFF';
  /** themeColors[1] at 66% alpha in a light theme, themeColors[2] at 50% in a dark one. */
  @Param backgroundLineColor: string = '#66FFFFFF';
  @Param lightTheme: boolean = true;
  /** ResourceHelper.getSunDrawable / getMoonDrawable (AstroViewHolder.kt:122-124). */
  @Param icon: Resource | null = null;
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  @Monitor('redrawKey', 'side', 'progress', 'lineColor')
  onRedrawRequested(monitor: IMonitor): void {
    if (this.ready) {
      this.draw();
    }
  }

  /** kt:214-232 */
  private geometry(): ArcGeometry {
    const geometry = new ArcGeometry();
    const width: number = this.side - 2 * MARGIN;
    if (width <= 0) {
      return geometry;
    }
    const deltaRadians: number = (180 - ARC_ANGLE) / 2 * DEG_TO_RAD;
    geometry.radius = width / 2 / Math.cos(deltaRadians);
    geometry.height = geometry.radius - width / 2 * Math.tan(deltaRadians);
    geometry.centerX = this.side / 2;
    geometry.centerY = MARGIN + geometry.radius;
    return geometry;
  }

  private canvasHeight(): number {
    return this.geometry().height + 2 * MARGIN;
  }

  /** kt:191-212 — where the icon's top-left corner lands for the current progress. */
  private iconOffsetX(): number {
    const geometry: ArcGeometry = this.geometry();
    const progressEndAngle: number = this.progressEndAngle();
    const deltaAngle: number = progressEndAngle - 180;
    const deltaWidth: number = Math.abs(geometry.radius * Math.cos(deltaAngle * DEG_TO_RAD));
    return progressEndAngle < 270
      ? geometry.centerX - deltaWidth - ICON_SIZE / 2
      : geometry.centerX + deltaWidth - ICON_SIZE / 2;
  }

  private iconOffsetY(): number {
    const geometry: ArcGeometry = this.geometry();
    const deltaAngle: number = this.progressEndAngle() - 180;
    const deltaHeight: number = Math.abs(geometry.radius * Math.sin(deltaAngle * DEG_TO_RAD));
    return geometry.centerY - deltaHeight - ICON_SIZE / 2;
  }

  private clampedProgress(): number {
    return Math.max(0, Math.min(1, this.progress));
  }

  private startAngle(): number {
    return 270 - ARC_ANGLE / 2;
  }

  private progressEndAngle(): number {
    return this.startAngle() + this.clampedProgress() * ARC_ANGLE;
  }

  private hasProgress(): boolean {
    return this.progress > 0 && this.side > 2 * MARGIN;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width(this.side)
        .height(this.canvasHeight())
        .hitTestBehavior(HitTestMode.Transparent)
        .onReady(() => {
          this.ready = true;
          this.draw();
        })

      // kt:266-273 — the icon is skipped entirely while progress is still zero.
      if (this.icon !== null && this.hasProgress()) {
        Image(this.icon)
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .hitTestBehavior(HitTestMode.Transparent)
          .margin({ left: this.iconOffsetX(), top: this.iconOffsetY() })
      }
    }
    .width(this.side)
    .height(this.canvasHeight())
  }

  private draw(): void {
    const ctx = this.ctx;
    const geometry: ArcGeometry = this.geometry();
    const height: number = this.canvasHeight();
    if (geometry.radius <= 0 || height <= 0) {
      return;
    }
    ctx.clearRect(0, 0, this.side, height);

    const start: number = this.startAngle();

    // 1. shadow — kt:243, 276-306.
    this.drawShadow(geometry, height);

    // 2. dashed track and baseline — kt:245-257.
    ctx.setLineDash([DASH_ON, DASH_OFF]);
    ctx.lineWidth = DOTTED_LINE_SIZE;
    ctx.strokeStyle = this.backgroundLineColor;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.arc(
      geometry.centerX,
      geometry.centerY,
      geometry.radius,
      start * DEG_TO_RAD,
      (start + ARC_ANGLE) * DEG_TO_RAD
    );
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(MARGIN, height - MARGIN);
    ctx.lineTo(this.side - MARGIN, height - MARGIN);
    ctx.stroke();
    ctx.setLineDash([]);

    // 3. elapsed arc — kt:259-264, 308-321.
    if (this.hasProgress()) {
      ctx.beginPath();
      ctx.lineWidth = LINE_SIZE;
      ctx.strokeStyle = this.lineColor;
      ctx.lineCap = 'round';
      ctx.arc(
        geometry.centerX,
        geometry.centerY,
        geometry.radius,
        start * DEG_TO_RAD,
        this.progressEndAngle() * DEG_TO_RAD
      );
      ctx.stroke();
    }
  }

  /**
   * kt:276-306. The Android version fills the whole chord-closed arc with a vertical gradient
   * into a saved layer, then punches out everything past the progress head with a CLEAR
   * xfermode. Clipping to the same rectangle before filling gives the identical result without
   * needing an offscreen layer.
   *
   * mX2ShaderColors (kt:145-146) is the line colour blended over the card background twice, so
   * on a transparent canvas that is the line colour at roughly twice the shadow alpha, fading
   * to fully transparent at the baseline.
   */
  private drawShadow(geometry: ArcGeometry, height: number): void {
    if (!this.hasProgress()) {
      return;
    }
    const ctx = this.ctx;
    const start: number = this.startAngle();
    const alpha: number = this.lightTheme ? SHADOW_ALPHA_FACTOR_LIGHT : SHADOW_ALPHA_FACTOR_DARK;
    const top: number = geometry.centerY - geometry.radius;

    const gradient = ctx.createLinearGradient(0, top, 0, height - MARGIN);
    gradient.addColorStop(0, withAlpha(this.lineColor, alpha * 2));
    gradient.addColorStop(1, '#00000000');

    // kt:297 — the punch-out starts at the x of the progress head.
    const cutX: number = geometry.centerX + geometry.radius * Math.cos(this.progressEndAngle() * DEG_TO_RAD);

    ctx.save();
    ctx.beginPath();
    // kt:278-284 — the layer only ever covers the top half of the circle's bounding box.
    ctx.rect(
      geometry.centerX - geometry.radius,
      top,
      cutX - (geometry.centerX - geometry.radius),
      geometry.radius
    );
    ctx.clip();

    ctx.beginPath();
    ctx.arc(
      geometry.centerX,
      geometry.centerY,
      geometry.radius,
      start * DEG_TO_RAD,
      (start + ARC_ANGLE) * DEG_TO_RAD
    );
    // useCenter = false (kt:291): the region closes along the chord, not through the centre.
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();
    ctx.restore();
  }
}
