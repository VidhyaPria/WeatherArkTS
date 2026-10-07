/*
 * Animated weather icon — the port of AnimatableIconView + res/animator/weather_*.xml.
 *
 * Up to three stacked Image layers, each running its own objectAnimator set, exactly as
 * CLAUDE.md specifies. Every step below is transcribed from the corresponding animator XML;
 * the file and the property are named on each spec.
 *
 * WHERE THIS IS USED: nowhere on the main weather screen. AnimatableIconView appears only in
 * DetailsConditions.kt (the per-day details screen) and AnimatableIconDialog.kt (a settings
 * dialog) — the main screen's icons are static drawables via ResourceHelper.getWeatherIcon.
 * The component is ported and ready; it gets a host when those screens are ported.
 *
 * Simplification, called out because it is a real deviation: where a `<set ordering="together">`
 * gives its members different durations (weather_rain_1's scaleX is 450 ms against scaleY's
 * 900 ms), this runs the step for the longer duration and animates both properties over it.
 * ArkUI animates a whole state change with one curve, so per-property durations inside a single
 * step cannot be expressed without splitting the state, which would desynchronise the layer.
 */

import { WeatherKind } from '../../model/WeatherKind';

/** One step of a layer's animation: where the properties should be when the step ends. */
export class IconStep {
  readonly duration: number;
  readonly translateX: number;
  readonly translateY: number;
  readonly scale: number;
  readonly rotate: number;
  readonly opacity: number;
  /** overshoot_interpolator on the Android side, Curve.Linear otherwise. */
  readonly overshoot: boolean;

  constructor(
    duration: number,
    translateX: number,
    translateY: number,
    scale: number,
    rotate: number,
    opacity: number,
    overshoot: boolean
  ) {
    this.duration = duration;
    this.translateX = translateX;
    this.translateY = translateY;
    this.scale = scale;
    this.rotate = rotate;
    this.opacity = opacity;
    this.overshoot = overshoot;
  }
}

/** A step that only moves on X, leaving everything else at rest. */
function moveX(duration: number, x: number, overshoot: boolean): IconStep {
  return new IconStep(duration, x, 0, 1, 0, 1, overshoot);
}

/** A step that only scales. */
function scaleTo(duration: number, scale: number): IconStep {
  return new IconStep(duration, 0, 0, scale, 0, 1, false);
}

/** A step that only fades. */
function fadeTo(duration: number, opacity: number): IconStep {
  return new IconStep(duration, 0, 0, 1, 0, opacity, false);
}

/** A step that only rotates. */
function rotateTo(duration: number, rotate: number): IconStep {
  return new IconStep(duration, 0, 0, 1, rotate, 1, false);
}

/* --------------------------------------------------------------- animator sets */

/** weather_clear_day_1.xml / weather_partly_cloudy_day_2.xml — pulse to 0.9 and back. */
const PULSE_90: IconStep[] = [scaleTo(900, 0.9), scaleTo(900, 1.0)];

/**
 * weather_clear_day_2.xml / weather_partly_cloudy_day_3.xml — a full overshoot rotation over
 * 1800 ms, with a 0.85 pulse running under it. The two are one `together` set of equal total
 * length, so they collapse into two steps.
 */
const SPIN_AND_PULSE: IconStep[] = [
  new IconStep(900, 0, 0, 0.85, 180, 1, true),
  new IconStep(900, 0, 0, 1.0, 360, 1, true)
];

/** weather_clear_night_1.xml / weather_partly_cloudy_night_2.xml — a damped rotational wobble. */
const WOBBLE: IconStep[] = [
  rotateTo(480, -84), rotateTo(420, 72), rotateTo(360, -60), rotateTo(300, 48),
  rotateTo(240, -36), rotateTo(180, 24), rotateTo(120, -12), rotateTo(60, 0)
];

/** weather_cloudy_1.xml — drift right 20 and overshoot back. */
const DRIFT_RIGHT_20: IconStep[] = [moveX(900, 20, false), moveX(900, 0, true)];
/** weather_cloudy_2.xml — the smaller cloud drifts 10. */
const DRIFT_RIGHT_10: IconStep[] = [moveX(900, 10, false), moveX(900, 0, true)];
/** weather_partly_cloudy_day_1.xml — drifts the other way. */
const DRIFT_LEFT_20: IconStep[] = [moveX(900, -20, false), moveX(900, 0, true)];

/** weather_fog_1.xml — drift right while fading to 0.7, hold, then back. */
const FOG_1: IconStep[] = [
  new IconStep(450, 20, 0, 1, 0, 0.7, false),
  new IconStep(900, 20, 0, 1, 0, 0.7, false),
  new IconStep(450, 0, 0, 1, 0, 1.0, false)
];
/** weather_fog_2.xml — the mirrored drift, 10 to the left. */
const FOG_2: IconStep[] = [
  new IconStep(450, -10, 0, 1, 0, 0.7, false),
  new IconStep(900, -10, 0, 1, 0, 0.7, false),
  new IconStep(450, 0, 0, 1, 0, 1.0, false)
];
/** weather_fog_3.xml — a fade to 0.3 with a hold. */
const FOG_3: IconStep[] = [fadeTo(450, 0.3), fadeTo(900, 0.3), fadeTo(450, 1.0)];

/** weather_haze_1/2/3.xml — three offset fades so the bands cross-dissolve. */
const HAZE_1: IconStep[] = [fadeTo(225, 1.0), fadeTo(675, 0.0), fadeTo(225, 0.0), fadeTo(675, 1.0)];
const HAZE_2: IconStep[] = [fadeTo(225, 0.0), fadeTo(675, 1.0), fadeTo(675, 0.0), fadeTo(225, 1.0)];
const HAZE_3: IconStep[] = [fadeTo(675, 0.0), fadeTo(225, 0.0), fadeTo(675, 1.0), fadeTo(225, 1.0)];

/** weather_rain_1.xml — the cloud breathes 1.05 then 0.95 then back. */
const RAIN_CLOUD: IconStep[] = [scaleTo(900, 1.05), scaleTo(900, 0.95), scaleTo(450, 1.0)];
/** weather_rain_2.xml — a drop parked above, then falling in while scaling up. */
const RAIN_DROP_1: IconStep[] = [
  new IconStep(1200, 0, -50, 0.0, 0, 1, false),
  new IconStep(650, 0, 0, 1.0, 0, 1, false)
];
/** weather_rain_3.xml — the second drop, offset later. */
const RAIN_DROP_2: IconStep[] = [
  new IconStep(1400, 0, -50, 0.0, 0, 1, false),
  new IconStep(450, 0, 0, 1.0, 0, 1, false)
];

/** weather_thunder_1.xml — a sharp horizontal shudder. */
const THUNDER_SHAKE: IconStep[] = [
  moveX(225, 5, false), moveX(225, -5, false), moveX(110, 10, false), moveX(115, -5, false),
  moveX(110, 10, false), moveX(115, -10, false), moveX(110, 10, false), moveX(115, -10, false),
  moveX(110, 10, false), moveX(115, 0, false)
];
/** weather_thunder_2.xml — the bolt drops in. */
const THUNDER_BOLT: IconStep[] = [
  new IconStep(450, 0, -50, 0.0, 0, 1, false),
  new IconStep(900, 0, -50, 0.0, 0, 1, false),
  new IconStep(450, 0, 0, 1.0, 0, 1, false)
];

/** weather_wind_1.xml — a gust that blows off-screen and sweeps back in. */
const WIND: IconStep[] = [
  new IconStep(100, 100, 0, 1, 0, 0.0, false),
  new IconStep(350, 100, 0, 1, 0, 0.0, false),
  new IconStep(900, -100, 0, 1, 0, 0.0, false),
  new IconStep(350, 5, 0, 0.9, 0, 1.0, false),
  new IconStep(100, 0, 0, 1.0, 0, 1.0, false)
];

/** One layer: its drawable suffix and the steps that drive it. */
export class IconLayer {
  readonly suffix: number;
  readonly steps: IconStep[];

  constructor(suffix: number, steps: IconStep[]) {
    this.suffix = suffix;
    this.steps = steps;
  }
}

/** The layer set for a weather kind, mirroring ResourceProvider's animator lookup. */
export function layersFor(kind: WeatherKind, daytime: boolean): IconLayer[] {
  switch (kind) {
    case WeatherKind.CLEAR:
      return daytime
        ? [new IconLayer(1, PULSE_90), new IconLayer(2, SPIN_AND_PULSE)]
        : [new IconLayer(1, WOBBLE)];
    case WeatherKind.CLOUD:
      return daytime
        ? [new IconLayer(1, DRIFT_LEFT_20), new IconLayer(2, PULSE_90), new IconLayer(3, SPIN_AND_PULSE)]
        : [new IconLayer(1, DRIFT_RIGHT_20), new IconLayer(2, WOBBLE)];
    case WeatherKind.CLOUDY:
      return [new IconLayer(1, DRIFT_RIGHT_20), new IconLayer(2, DRIFT_RIGHT_10)];
    case WeatherKind.FOG:
      return [new IconLayer(1, FOG_1), new IconLayer(2, FOG_2), new IconLayer(3, FOG_3)];
    case WeatherKind.HAZE:
      return [new IconLayer(1, HAZE_1), new IconLayer(2, HAZE_2), new IconLayer(3, HAZE_3)];
    case WeatherKind.RAINY:
    case WeatherKind.SLEET:
    case WeatherKind.SNOW:
    case WeatherKind.HAIL:
      return [new IconLayer(1, RAIN_CLOUD), new IconLayer(2, RAIN_DROP_1), new IconLayer(3, RAIN_DROP_2)];
    case WeatherKind.THUNDER:
      return [new IconLayer(1, THUNDER_SHAKE), new IconLayer(2, THUNDER_BOLT)];
    case WeatherKind.THUNDERSTORM:
      return [new IconLayer(1, RAIN_CLOUD), new IconLayer(2, THUNDER_BOLT), new IconLayer(3, RAIN_DROP_2)];
    case WeatherKind.WIND:
      return [new IconLayer(1, WIND)];
    default:
      return [];
  }
}

/** The drawable base name, matching the copied weather_*_1/_2/_3.png assets. */
export function iconBaseName(kind: WeatherKind, daytime: boolean): string {
  switch (kind) {
    case WeatherKind.CLEAR: return daytime ? 'weather_clear_day' : 'weather_clear_night';
    case WeatherKind.CLOUD: return daytime ? 'weather_partly_cloudy_day' : 'weather_partly_cloudy_night';
    case WeatherKind.CLOUDY: return 'weather_cloudy';
    case WeatherKind.RAINY: return 'weather_rain';
    case WeatherKind.SNOW: return 'weather_snow';
    case WeatherKind.SLEET: return 'weather_sleet';
    case WeatherKind.HAIL: return 'weather_hail';
    case WeatherKind.FOG: return 'weather_fog';
    case WeatherKind.HAZE: return 'weather_haze';
    case WeatherKind.THUNDER: return 'weather_thunder';
    case WeatherKind.THUNDERSTORM: return 'weather_thunderstorm';
    case WeatherKind.WIND: return 'weather_wind';
    default: return '';
  }
}

/** Mutable per-layer transform state, driven by animateTo. */
@ObservedV2
class LayerState {
  @Trace translateX: number = 0;
  @Trace translateY: number = 0;
  @Trace scale: number = 1;
  @Trace rotate: number = 0;
  @Trace opacity: number = 1;
}

@ComponentV2
export struct AnimatedWeatherIcon {
  @Param kind: WeatherKind = WeatherKind.NULL;
  @Param daytime: boolean = true;
  /**
   * NOT `size`: `CustomComponent` already declares a `size` attribute, so an @Param of that name
   * fails to compile with "not assignable to the same property in base type". The clash was latent
   * while this component had no call site.
   */
  @Param iconSize: number = 56;
  /** Off shows the composed icon at rest, matching isElementsAnimationEnabled = false. */
  @Param animated: boolean = true;

  @Local private states: LayerState[] = [];
  private running: boolean = false;
  private timers: number[] = [];

  aboutToAppear(): void {
    const layers: IconLayer[] = layersFor(this.kind, this.daytime);
    const states: LayerState[] = [];
    for (let i = 0; i < layers.length; i++) {
      states.push(new LayerState());
    }
    this.states = states;
    if (this.animated) {
      this.running = true;
      for (let i = 0; i < layers.length; i++) {
        this.runLayer(i, layers[i], 0);
      }
    }
  }

  aboutToDisappear(): void {
    this.stop();
  }

  private stop(): void {
    this.running = false;
    for (let i = 0; i < this.timers.length; i++) {
      clearTimeout(this.timers[i]);
    }
    this.timers = [];
  }

  /**
   * `startAnimators()` — replays the set from step 0.
   *
   * AnimatableIconView loops by itself, so this exists for the tap handlers that ask for a restart:
   * the icon's own, on the details screen (DetailsConditions.kt:744-746), and the container's, in
   * the icon-preview dialog (AnimatableIconDialog.kt:44). Every layer is put back to rest first,
   * or a layer part-way through a translate would tween from wherever it happened to be.
   */
  restart(): void {
    if (!this.animated) {
      return;
    }
    this.stop();
    const layers: IconLayer[] = layersFor(this.kind, this.daytime);
    const states: LayerState[] = [];
    for (let i = 0; i < layers.length; i++) {
      states.push(new LayerState());
    }
    this.states = states;
    this.running = true;
    for (let i = 0; i < layers.length; i++) {
      this.runLayer(i, layers[i], 0);
    }
  }

  /**
   * Runs one step, then schedules the next. AnimatableIconView restarts its set when it ends,
   * so the sequence wraps around to step 0.
   */
  private runLayer(index: number, layer: IconLayer, stepIndex: number): void {
    if (!this.running || index >= this.states.length || layer.steps.length === 0) {
      return;
    }
    const step: IconStep = layer.steps[stepIndex];
    const state: LayerState = this.states[index];

    animateTo({
      duration: step.duration,
      curve: step.overshoot ? Curve.ExtremeDeceleration : Curve.Linear
    }, () => {
      state.translateX = step.translateX;
      state.translateY = step.translateY;
      state.scale = step.scale;
      state.rotate = step.rotate;
      state.opacity = step.opacity;
    });

    const next: number = (stepIndex + 1) % layer.steps.length;
    this.timers.push(setTimeout(() => {
      this.runLayer(index, layer, next);
    }, step.duration));
  }

  build() {
    Stack() {
      ForEach(layersFor(this.kind, this.daytime), (layer: IconLayer, index: number) => {
        if (index < this.states.length) {
          Image($r('app.media.' + iconBaseName(this.kind, this.daytime) + '_' + layer.suffix.toString()))
            .width(this.iconSize)
            .height(this.iconSize)
            .objectFit(ImageFit.Contain)
            .translate({ x: this.states[index].translateX, y: this.states[index].translateY })
            .scale({ x: this.states[index].scale, y: this.states[index].scale })
            .rotate({ angle: this.states[index].rotate })
            .opacity(this.states[index].opacity)
        }
      }, (layer: IconLayer) => layer.suffix.toString())
    }
    .width(this.iconSize)
    .height(this.iconSize)
    // kt:744-746 — tapping the icon replays it. Harmless where the parent also handles the tap:
    // the dialog's container listener sits on an ancestor and still fires.
    .onClick(() => {
      this.restart();
    })
  }
}
