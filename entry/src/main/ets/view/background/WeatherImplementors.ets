/*
 * The procedural weather background painters.
 *
 * Ported 1:1 from ui-weather-view/.../materialWeatherView/implementor/, keeping every particle
 * parameter as CLAUDE.md requires:
 *   SunImplementor.kt:30-98      clear day  — three counter-rotating squares
 *   CloudImplementor.kt:34-590   cloud / cloudy / fog / haze / thunder — circles that breathe,
 *                                plus 50 twinkling stars on the clear-ish night variant
 *
 * The two rotations come from the device's gravity sensor (GravitySensor.ets), smoothed by a
 * DelayRotateController before they get here, exactly as MaterialPainterView.kt:251-283 feeds
 * them. rotation2D leans the whole scene; rotation3D parallaxes it in depth. Both are 0 when the
 * `gravity_sensor_switch` setting is off, which is what makes the shapes stand still.
 *
 * `scrollRate` is 0 at the top of the page and 1 once the cards have covered the background; at 1
 * the Kotlin skips drawing entirely, which is what keeps the effect cheap while scrolling.
 */

import { WeatherKind } from '../../model/WeatherKind';

export interface WeatherImplementor {
  /** Advance the simulation by `interval` milliseconds. */
  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void;

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void;
}

/**
 * The sentinel every falling-particle implementor starts its `lastRotation3D` at (kt:291 and
 * friends, INITIAL_ROTATION_3D = 1000f). The first frame after a scene is built has no previous
 * angle to difference against, so it moves the particles by 0 instead of by a full 1000°.
 */
const INITIAL_ROTATION_3D: number = 1000;

function randomBetween(from: number, to: number): number {
  return from + Math.random() * (to - from);
}

/**
 * CloudImplementor.getRandomFactor (kt:534-536) — `from + nextFloat() % (to - from)`. The modulo
 * on a value already in [0, 1) is upstream's, not a typo: for a range under 1 it narrows the
 * spread, which is why it is kept rather than "corrected" to a plain lerp.
 */
function randomFactor(from: number, to: number): number {
  return from + (Math.random() % (to - from));
}

/** java.util.Random.nextInt(bound) — an integer in [0, bound). */
function nextInt(bound: number): number {
  return bound <= 0 ? 0 : Math.floor(Math.random() * bound);
}

/**
 * The square canvas every falling-particle implementor works in:
 * `(viewWidth² + viewHeight²) ^ 0.5`, the view's diagonal (RainImplementor.kt:73 and friends).
 * Particles live in this space and are shifted into view coordinates when drawn, so a rotated
 * canvas never shows an empty corner.
 */
function diagonalCanvasSize(width: number, height: number): number {
  return Math.floor(Math.pow(width * width + height * height, 0.5));
}

const DEG: number = Math.PI / 180;

/** canvas.rotate(degrees, px, py) — ArkUI has no pivot form, so it is composed here. */
function rotateAbout(ctx: CanvasRenderingContext2D, degrees: number, px: number, py: number): void {
  ctx.translate(px, py);
  ctx.rotate(degrees * DEG);
  ctx.translate(-px, -py);
}

/** Canvas fillStyle from an "r,g,b" triple string plus a 0..1 alpha. */
function rgbaOf(rgb: string, alpha: number): string {
  return 'rgba(' + rgb + ',' + alpha.toString() + ')';
}

/** A rounded rectangle path, matching Canvas.drawRoundRect(rectF, rx, ry, paint). */
function roundRectPath(
  ctx: CanvasRenderingContext2D,
  left: number,
  top: number,
  right: number,
  bottom: number,
  radius: number
): void {
  const r: number = Math.max(0, Math.min(radius, Math.min((right - left) / 2, (bottom - top) / 2)));
  ctx.beginPath();
  ctx.moveTo(left + r, top);
  ctx.lineTo(right - r, top);
  ctx.arcTo(right, top, right, top + r, r);
  ctx.lineTo(right, bottom - r);
  ctx.arcTo(right, bottom, right - r, bottom, r);
  ctx.lineTo(left + r, bottom);
  ctx.arcTo(left, bottom, left, bottom - r, r);
  ctx.lineTo(left, top + r);
  ctx.arcTo(left, top, left + r, top, r);
  ctx.closePath();
}

/** Canvas fillStyle from an rgb triple plus a 0..1 alpha. */
function rgba(r: number, g: number, b: number, alpha: number): string {
  return 'rgba(' + r.toString() + ',' + g.toString() + ',' + b.toString() + ',' + alpha.toString() + ')';
}

/* ------------------------------------------------------------------ clear day */

/**
 * SunImplementor.kt:30-98.
 *
 * Three nested squares at 0.5×0.47×width, ×1.7794 and ×3.0594, each rotating a full 90° every
 * 3000/4000/5000 ms and drawn four times at 22.5° apart — which is what makes the soft rosette.
 */
export class SunImplementor implements WeatherImplementor {
  /** SunImplementor.kt:89 — moved down from the old 0.0333 to clear the toolbar icons. */
  private static readonly SUN_POSITION: number = 0.5;
  private static readonly ALPHAS: number[] = [0.16, 0.08, 0.04];

  private angles: number[] = [0, 0, 0];

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    // kt:53-55
    for (let i = 0; i < this.angles.length; i++) {
      this.angles[i] = (this.angles[i] + 90.0 / (3000 + 1000 * i) * interval) % 90;
    }
  }

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const unitSizes: number[] = [
      0.5 * 0.47 * width,
      1.7794 * 0.5 * 0.47 * width,
      3.0594 * 0.5 * 0.47 * width
    ];

    ctx.save();
    // kt:66-68 — the sun hangs off the top-right corner and slides up to 0.3 × width away from it
    // as the phone tilts. Note both deltas scale by canvasSizes[0], the width, including the
    // vertical one.
    const deltaX: number = Math.sin(rotation2D * DEG) * 0.3 * width;
    const deltaY: number = Math.sin(rotation3D * DEG) * -0.3 * width;
    ctx.translate(width + deltaX, SunImplementor.SUN_POSITION * width + deltaY);

    for (let index = 0; index < 3; index++) {
      const alpha: number = (1 - scrollRate) * SunImplementor.ALPHAS[index];
      ctx.fillStyle = rgba(255, 255, 255, alpha);
      ctx.rotate(this.angles[index] * Math.PI / 180);
      for (let i = 0; i < 4; i++) {
        ctx.fillRect(
          -unitSizes[index],
          -unitSizes[index],
          2 * unitSizes[index],
          2 * unitSizes[index]
        );
        ctx.rotate(22.5 * Math.PI / 180);
      }
      ctx.rotate((-90 - this.angles[index]) * Math.PI / 180);
    }
    ctx.restore();
  }
}

/* --------------------------------------------------------------------- clouds */

/** CloudImplementor.Cloud (kt:53-87). */
class Cloud {
  private readonly initCX: number;
  private readonly initCY: number;
  private readonly initRadius: number;
  private readonly scaleRatio: number;
  /** kt:58 — how far this cloud slides per degree of tilt. Higher bands drift further. */
  private readonly moveFactor: number;
  private readonly duration: number;
  readonly color: string;
  readonly alpha: number;

  centerX: number;
  centerY: number;
  radius: number;
  private progress: number;

  constructor(
    initCX: number,
    initCY: number,
    radius: number,
    scaleRatio: number,
    moveFactor: number,
    color: string,
    alpha: number,
    duration: number
  ) {
    this.initCX = initCX;
    this.initCY = initCY;
    this.initRadius = radius;
    this.radius = radius;
    this.scaleRatio = scaleRatio;
    this.moveFactor = moveFactor;
    this.color = color;
    this.alpha = alpha;
    this.duration = duration;
    this.centerX = initCX;
    this.centerY = initCY;
    this.progress = 0;
    this.computeRadius();
  }

  /**
   * kt:73-78 — the centre is re-derived from the initial one every frame, offset by the tilt.
   * `radius` is last frame's breathed radius, so a cloud drifts further at the top of its breath.
   */
  move(interval: number, rotation2D: number, rotation3D: number): void {
    this.centerX = this.initCX + Math.sin(rotation2D * DEG) * 0.40 * this.radius * this.moveFactor;
    this.centerY = this.initCY - Math.sin(rotation3D * DEG) * 0.50 * this.radius * this.moveFactor;
    this.progress = (this.progress + interval) % this.duration;
    this.computeRadius();
  }

  /** kt:80-86 — grow to scaleRatio over the first half, shrink back over the second. */
  private computeRadius(): void {
    const half: number = 0.5 * this.duration;
    this.radius = this.progress < half
      ? this.initRadius * (1 + (this.scaleRatio - 1) * this.progress / half)
      : this.initRadius * (this.scaleRatio - (this.scaleRatio - 1) * (this.progress - half) / half);
  }
}

/** CloudImplementor.Star (kt:89-124). */
class Star {
  readonly centerX: number;
  readonly centerY: number;
  readonly radius: number;
  readonly color: string;
  private readonly duration: number;
  alpha: number = 0;
  private progress: number = 0;

  constructor(centerX: number, centerY: number, radius: number, color: string, duration: number) {
    this.centerX = centerX;
    this.centerY = centerY;
    // kt:102 — each star keeps 70..100% of the shared radius.
    this.radius = radius * (0.7 + 0.3 * Math.random());
    this.color = color;
    this.duration = duration;
    this.computeAlpha();
  }

  shine(interval: number): void {
    this.progress = (this.progress + interval) % this.duration;
    this.computeAlpha();
  }

  /** kt:117-123 — a linear fade up then down. */
  private computeAlpha(): void {
    const half: number = 0.5 * this.duration;
    this.alpha = this.progress < half
      ? this.progress / half
      : 1 - (this.progress - half) / half;
  }
}

export enum CloudType {
  CLOUD,
  CLOUDY,
  THUNDER,
  FOG,
  HAZE
}

/** CloudImplementor.Thunder (kt:126-169) — a four-step flash, then a 2..7 s pause. */
class Thunder {
  readonly r: number = 81;
  readonly g: number = 67;
  readonly b: number = 168;
  alpha: number = 0;
  private progress: number = 0;
  private readonly duration: number = 300;
  private delay: number = 0;

  constructor() {
    this.reset();
    this.computeFrame();
  }

  private reset(): void {
    this.progress = 0;
    this.delay = Math.floor(Math.random() * 5000) + 2000;
  }

  shine(interval: number): void {
    this.progress += interval;
    if (this.progress > this.duration + this.delay) {
      this.reset();
    }
    this.computeFrame();
  }

  private computeFrame(): void {
    const d: number = this.duration;
    const p: number = this.progress;
    if (p >= d) {
      this.alpha = 0;
      return;
    }
    if (p < 0.25 * d) {
      this.alpha = p / (0.25 * d);
    } else if (p < 0.5 * d) {
      this.alpha = 1 - (p - 0.25 * d) / (0.25 * d);
    } else if (p < 0.75 * d) {
      this.alpha = (p - 0.5 * d) / (0.25 * d);
    } else {
      this.alpha = 1 - (p - 0.75 * d) / (0.25 * d);
    }
  }
}

/** CloudImplementor.kt:34-590. */
export class CloudImplementor implements WeatherImplementor {
  private clouds: Cloud[] = [];
  private stars: Star[] = [];
  private thunder: Thunder | null = null;

  constructor(width: number, height: number, type: CloudType, daylight: boolean, darkMode: boolean) {
    const lit: boolean = daylight && !darkMode;

    if (type === CloudType.FOG || type === CloudType.HAZE) {
      // kt:175-205 — one flat colour for all three bands, all at 0.3 alpha.
      const color: string = type === CloudType.FOG
        ? (lit ? '#93B9FF' : '#2A5476') // kt:178-189
        : (lit ? '#FFDDA1' : '#4D3314'); // kt:192-203
      this.clouds = CloudImplementor.threeBandClouds(width, [color, color, color], [0.3, 0.3, 0.3]);
    } else if (type === CloudType.CLOUDY || type === CloudType.THUNDER) {
      // kt:308-341
      const color: string = type === CloudType.CLOUDY
        ? (lit ? 'rgb(160,179,191)' : 'rgb(95,104,108)') // kt:313-323
        : (lit ? '#AB90DB' : '#2C1C4D'); // kt:327-337
      this.clouds = CloudImplementor.twoBandClouds(width, [color, color], [0.3, 0.3]);
    } else {
      // TYPE_CLOUD — kt:411-485
      const cloudColor: string = lit ? 'rgb(203,245,255)' : 'rgb(151,168,202)';
      this.clouds = CloudImplementor.partlyCloudyClouds(width, cloudColor);
      if (!daylight) {
        this.stars = CloudImplementor.buildStars(width, height);
      }
    }
    this.thunder = type === CloudType.THUNDER ? new Thunder() : null;
  }

  /** kt:206-306 — the nine-cloud arrangement shared by fog and haze. */
  private static threeBandClouds(width: number, colors: string[], alphas: number[]): Cloud[] {
    return [
      new Cloud(width * 1.0699, width * (1.1900 * 0.2286 + 0.11), width * (0.4694 * 0.9), 1.1, randomFactor(1.3, 1.8), colors[0], alphas[0], 9000),
      new Cloud(width * 0.4866, width * (0.4866 * 0.6064 + 0.085), width * (0.3946 * 0.9), 1.1, randomFactor(1.3, 1.8), colors[0], alphas[0], 10500),
      new Cloud(width * 0.0351, width * (0.1701 * 1.4327 + 0.11), width * (0.4627 * 0.9), 1.1, randomFactor(1.3, 1.8), colors[0], alphas[0], 9000),
      new Cloud(width * 0.8831, width * (1.0270 * 0.1671 + 0.07), width * (0.3238 * 0.9), 1.15, randomFactor(1.6, 2), colors[1], alphas[1], 7000),
      new Cloud(width * 0.4663, width * (0.4663 * 0.3520 + 0.050), width * (0.2906 * 0.9), 1.15, randomFactor(1.6, 2), colors[1], alphas[1], 8500),
      new Cloud(width * 0.1229, width * (0.0234 * 5.7648 + 0.07), width * (0.2972 * 0.9), 1.15, randomFactor(1.6, 2), colors[1], alphas[1], 7000),
      new Cloud(width * 0.9250, width * (0.9250 * 0.0249 + 0.1500), width * 0.3166, 1.15, randomFactor(1.8, 2.2), colors[2], alphas[2], 7000),
      new Cloud(width * 0.4694, width * (0.4694 * 0.0489 + 0.1500), width * 0.3166, 1.15, randomFactor(1.8, 2.2), colors[2], alphas[2], 8200),
      new Cloud(width * 0.0250, width * (0.0250 * 0.6820 + 0.1500), width * 0.3166, 1.15, randomFactor(1.8, 2.2), colors[2], alphas[2], 7700)
    ];
  }

  /** kt:342-409 — the six-cloud arrangement shared by cloudy and thunder. */
  private static twoBandClouds(width: number, colors: string[], alphas: number[]): Cloud[] {
    return [
      new Cloud(width * 1.0699, width * (1.1900 * 0.2286 + 0.11), width * (0.4694 * 0.9), 1.1, randomFactor(1.3, 1.8), colors[0], alphas[0], 9000),
      new Cloud(width * 0.4866, width * (0.4866 * 0.6064 + 0.085), width * (0.3946 * 0.9), 1.1, randomFactor(1.3, 1.8), colors[0], alphas[0], 10500),
      new Cloud(width * 0.0351, width * (0.1701 * 1.4327 + 0.11), width * (0.4627 * 0.9), 1.1, randomFactor(1.3, 1.8), colors[0], alphas[0], 9000),
      new Cloud(width * 0.8831, width * (1.0270 * 0.1671 + 0.07), width * (0.3238 * 0.9), 1.15, randomFactor(1.6, 2), colors[1], alphas[1], 7000),
      new Cloud(width * 0.4663, width * (0.4663 * 0.3520 + 0.050), width * (0.2906 * 0.9), 1.15, randomFactor(1.6, 2), colors[1], alphas[1], 8500),
      new Cloud(width * 0.1229, width * (0.0234 * 5.7648 + 0.07), width * (0.2972 * 0.9), 1.15, randomFactor(1.6, 2), colors[1], alphas[1], 7000)
    ];
  }

  /** kt:418-485 — partly cloudy: three near clouds at 0.40 alpha, three far ones at 0.10. */
  private static partlyCloudyClouds(width: number, color: string): Cloud[] {
    return [
      new Cloud(width * 0.1529, width * 0.1529 * 0.5568 + width * 0.050, width * 0.2649, 1.20, randomFactor(1.5, 1.8), color, 0.40, 7000),
      new Cloud(width * 0.4793, width * 0.4793 * 0.2185 + width * 0.050, width * 0.2426, 1.20, randomFactor(1.5, 1.8), color, 0.40, 8500),
      new Cloud(width * 0.8531, width * 0.8531 * 0.1286 + width * 0.050, width * 0.2970, 1.20, randomFactor(1.5, 1.8), color, 0.40, 7050),
      new Cloud(width * 0.0551, width * 0.0551 * 2.8600 + width * 0.050, width * 0.4125, 1.15, randomFactor(1.3, 1.5), color, 0.10, 9500),
      new Cloud(width * 0.4928, width * 0.4928 * 0.3897 + width * 0.050, width * 0.3521, 1.15, randomFactor(1.3, 1.5), color, 0.10, 10500),
      new Cloud(width * 1.0499, width * 1.0499 * 0.1875 + width * 0.050, width * 0.4186, 1.15, randomFactor(1.3, 1.5), color, 0.10, 9000)
    ];
  }

  /** kt:489-518 — 50 stars scattered over the rotated canvas bounds. */
  private static buildStars(width: number, height: number): Star[] {
    const colors: string[] = [
      'rgb(210,247,255)', 'rgb(208,233,255)', 'rgb(175,201,228)', 'rgb(164,194,220)',
      'rgb(97,171,220)', 'rgb(74,141,193)', 'rgb(54,66,119)', 'rgb(34,48,74)',
      'rgb(236,234,213)', 'rgb(240,220,151)'
    ];
    const canvasSize: number = Math.sqrt(width * width + height * height);
    const starFieldWidth: number = canvasSize;
    const starFieldHeight: number = (canvasSize - height) * 0.5 + width * 1.1111;
    const radius: number = 0.00125 * canvasSize * (0.5 + Math.random());

    const stars: Star[] = [];
    for (let i = 0; i < 50; i++) {
      const x: number = Math.random() * starFieldWidth - 0.5 * (canvasSize - width);
      const y: number = Math.random() * starFieldHeight - 0.5 * (canvasSize - height);
      const duration: number = 2500 + Math.random() * 2500;
      stars.push(new Star(x, y, radius, colors[i % colors.length], duration));
    }
    return stars;
  }

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    for (let i = 0; i < this.clouds.length; i++) {
      this.clouds[i].move(interval, rotation2D, rotation3D);
    }
    for (let i = 0; i < this.stars.length; i++) {
      this.stars[i].shine(interval);
    }
    if (this.thunder !== null) {
      this.thunder.shine(interval);
    }
  }

  /**
   * kt:553-582 — thunder wash first, then stars, then clouds. The rotations reach the clouds
   * through `move` above; this half of the scene is not rotated as a whole.
   */
  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const visibility: number = 1 - scrollRate;

    if (this.thunder !== null) {
      const t: Thunder = this.thunder;
      ctx.fillStyle = rgba(t.r, t.g, t.b, visibility * t.alpha * 0.66);
      ctx.fillRect(0, 0, width, height);
    }
    for (let i = 0; i < this.stars.length; i++) {
      const s: Star = this.stars[i];
      ctx.globalAlpha = visibility * s.alpha;
      ctx.fillStyle = s.color;
      ctx.beginPath();
      ctx.arc(s.centerX, s.centerY, s.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    for (let i = 0; i < this.clouds.length; i++) {
      const c: Cloud = this.clouds[i];
      ctx.globalAlpha = visibility * c.alpha;
      ctx.fillStyle = c.color;
      ctx.beginPath();
      ctx.arc(c.centerX, c.centerY, c.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
}

/* --------------------------------------------------------- rain / sleet / storm */

/** RainImplementor.TypeRule (kt:50-51, 292-294). */
export enum RainType {
  RAIN = 1,
  THUNDERSTORM = 3,
  SLEET = 4
}

/** RainImplementor.Rain (kt:52-116). */
class RainDrop {
  private readonly viewWidth: number;
  private readonly viewHeight: number;
  private readonly canvasSize: number;
  private readonly maxWidth: number;
  private readonly minWidth: number;
  private readonly maxHeight: number;
  private readonly minHeight: number;
  readonly colorRgb: string;
  readonly scale: number;
  private readonly speed: number;

  private x: number = 0;
  private y: number = 0;
  width: number = 0;
  private height: number = 0;
  /** left, top, right, bottom in view coordinates. */
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  constructor(viewWidth: number, viewHeight: number, colorRgb: string, scale: number, type: RainType) {
    this.viewWidth = viewWidth;
    this.viewHeight = viewHeight;
    this.colorRgb = colorRgb;
    this.scale = scale;
    this.canvasSize = diagonalCanvasSize(viewWidth, viewHeight);
    // kt:74-79 — sleet falls slower and draws fatter, shorter drops.
    const velocity: number = type === RainType.SLEET ? 3.0 : 5.0;
    this.speed = this.canvasSize / (1000.0 * (1.75 + Math.random())) * velocity;
    this.maxWidth = (type === RainType.SLEET ? 0.006 : 0.003) * this.canvasSize;
    this.minWidth = (type === RainType.SLEET ? 0.004 : 0.002) * this.canvasSize;
    this.maxHeight = this.maxWidth * 10;
    this.minHeight = this.minWidth * 6;
    this.init(true);
  }

  /** kt:83-94 */
  private init(firstTime: boolean): void {
    this.x = nextInt(this.canvasSize);
    this.y = firstTime
      ? nextInt(Math.floor(this.canvasSize - this.maxHeight)) - this.canvasSize
      : -this.maxHeight * (1 + 2 * Math.random());
    this.width = this.minWidth + Math.random() * (this.maxWidth - this.minWidth);
    this.height = this.minHeight + Math.random() * (this.maxHeight - this.minHeight);
    this.buildRect();
  }

  /** kt:96-100 — shift from the diagonal canvas into view coordinates. */
  private buildRect(): void {
    const x: number = this.x - (this.canvasSize - this.viewWidth) * 0.5;
    const y: number = this.y - (this.canvasSize - this.viewHeight) * 0.5;
    this.left = x;
    this.top = y;
    this.right = x + this.width * this.scale;
    this.bottom = y + this.height * this.scale;
  }

  /** kt:102-115. deltaRotation3D is 0 here — no gravity sensor. */
  move(interval: number, deltaRotation3D: number): void {
    this.y += this.speed * interval *
      (Math.pow(this.scale, 1.5) - 5 * Math.sin(deltaRotation3D * DEG) * Math.cos(8 * DEG));
    this.x -= this.speed * interval * 5 * Math.sin(deltaRotation3D * DEG) * Math.sin(8 * DEG);
    if (this.y >= this.canvasSize) {
      this.init(false);
    } else {
      this.buildRect();
    }
  }
}

/** RainImplementor.Thunder (kt:118-161) — the same four-step flash the cloud storm uses. */
class RainThunder {
  alpha: number = 0;
  private progress: number = 0;
  private duration: number = 0;
  private delay: number = 0;

  constructor() {
    this.reset();
    this.computeFrame();
  }

  private reset(): void {
    this.progress = 0;
    this.duration = 300;
    this.delay = nextInt(5000) + 3000;
  }

  private computeFrame(): void {
    const p: number = this.progress;
    const d: number = this.duration;
    if (p >= d) {
      this.alpha = 0;
      return;
    }
    if (p < 0.25 * d) {
      this.alpha = p / 0.25 / d;
    } else if (p < 0.5 * d) {
      this.alpha = 1 - (p - 0.25 * d) / 0.25 / d;
    } else if (p < 0.75 * d) {
      this.alpha = (p - 0.5 * d) / 0.25 / d;
    } else {
      this.alpha = 1 - (p - 0.75 * d) / 0.25 / d;
    }
  }

  shine(interval: number): void {
    this.progress += interval;
    if (this.progress > this.duration + this.delay) {
      this.reset();
    }
    this.computeFrame();
  }
}

/** RainImplementor.kt:35-308. */
export class RainImplementor implements WeatherImplementor {
  private static readonly RAIN_COUNT: number = 75;
  private static readonly SLEET_COUNT: number = 45;

  private drops: RainDrop[] = [];
  private thunder: RainThunder | null = null;

  constructor(width: number, height: number, type: RainType, daylight: boolean) {
    // kt:167-221 — three colour bands, three scales, per type and daylight.
    let colors: string[];
    let count: number = RainImplementor.RAIN_COUNT;
    if (type === RainType.SLEET) {
      count = RainImplementor.SLEET_COUNT;
      colors = daylight
        ? ['128,197,255', '185,222,255', '255,255,255']
        : ['40,102,155', '99,144,182', '255,255,255'];
    } else if (type === RainType.THUNDERSTORM) {
      this.thunder = new RainThunder();
      // kt:191 — the daylight middle band is the literal -0x93aa6e = #6C5592.
      colors = daylight
        ? ['182,142,82', '108,85,146', '255,255,255']
        : ['182,142,82', '88,92,113', '255,255,255'];
    } else {
      colors = daylight
        ? ['223,179,114', '152,175,222', '255,255,255']
        : ['182,142,82', '88,92,113', '255,255,255'];
    }
    const scales: number[] = [0.6, 0.8, 1];
    for (let i = 0; i < count; i++) {
      // kt:227-228 — `i * 3 / count` buckets the drops into the three bands.
      const band: number = Math.floor(i * 3 / count);
      this.drops.push(new RainDrop(width, height, colors[band], scales[band], type));
    }
  }

  private lastRotation3D: number = INITIAL_ROTATION_3D;

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    // kt:247-254 — the drops are pushed sideways by the CHANGE in the depth angle, not its value.
    const delta: number = this.lastRotation3D === INITIAL_ROTATION_3D
      ? 0
      : rotation3D - this.lastRotation3D;
    for (let i = 0; i < this.drops.length; i++) {
      this.drops[i].move(interval, delta);
    }
    if (this.thunder !== null) {
      this.thunder.shine(interval);
    }
    this.lastRotation3D = rotation3D;
  }

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const alpha: number = 1 - scrollRate;
    ctx.save();
    // kt:264-271 — rain always leans 8° off vertical, and tilts further with the phone.
    rotateAbout(ctx, rotation2D + 8, width * 0.5, height * 0.5);
    for (let i = 0; i < this.drops.length; i++) {
      const drop: RainDrop = this.drops[i];
      ctx.fillStyle = rgbaOf(drop.colorRgb, alpha);
      roundRectPath(ctx, drop.left, drop.top, drop.right, drop.bottom, drop.width / 2);
      ctx.fill();
    }
    ctx.restore();
    // kt:277-286 — the flash is a full-canvas wash, drawn unrotated.
    if (this.thunder !== null && this.thunder.alpha > 0) {
      ctx.fillStyle = rgbaOf('81,67,168', alpha * this.thunder.alpha * 0.66);
      ctx.fillRect(0, 0, width, height);
    }
  }
}

/* ------------------------------------------------------------------------ snow */

/** SnowImplementor.Snow (kt:45-97). */
class SnowFlake {
  private readonly viewWidth: number;
  private readonly viewHeight: number;
  private readonly canvasSize: number;
  readonly colorRgb: string;
  private readonly scale: number;
  readonly radius: number;
  private readonly speedY: number;
  private speedX: number = 0;

  private cx: number = 0;
  private cy: number = 0;
  centerX: number = 0;
  centerY: number = 0;

  constructor(viewWidth: number, viewHeight: number, colorRgb: string, scale: number) {
    this.viewWidth = viewWidth;
    this.viewHeight = viewHeight;
    this.colorRgb = colorRgb;
    this.scale = scale;
    this.canvasSize = diagonalCanvasSize(viewWidth, viewHeight);
    // kt:62-63
    this.radius = this.canvasSize * (0.005 + Math.random() * 0.007) * scale;
    this.speedY = this.canvasSize / (1000.0 * (2.5 + Math.random())) * 1.5;
    this.init(true);
  }

  /** kt:67-80 */
  private init(firstTime: boolean): void {
    this.cx = nextInt(this.canvasSize);
    this.cy = firstTime
      ? nextInt(Math.floor(this.canvasSize - this.radius)) - this.canvasSize
      : -this.radius;
    // kt:76-78 — the bound is floored at 2 so low-resolution screens cannot pass 0 to nextInt.
    this.speedX = nextInt(Math.max(Math.floor(2 * this.speedY), 2)) - this.speedY;
    this.computeCenter();
  }

  /** kt:82-85 — truncated to whole pixels upstream, which this keeps. */
  private computeCenter(): void {
    this.centerX = Math.trunc(this.cx - (this.canvasSize - this.viewWidth) * 0.5);
    this.centerY = Math.trunc(this.cy - (this.canvasSize - this.viewHeight) * 0.5);
  }

  /** kt:87-96 */
  move(interval: number, deltaRotation3D: number): void {
    this.cx += this.speedX * interval * Math.pow(this.scale, 1.5);
    this.cy += this.speedY * interval *
      (Math.pow(this.scale, 1.5) - 5 * Math.sin(deltaRotation3D * DEG));
    if (this.centerY >= this.canvasSize) {
      this.init(false);
    } else {
      this.computeCenter();
    }
  }
}

/** SnowImplementor.kt:32-168. */
export class SnowImplementor implements WeatherImplementor {
  private static readonly SNOW_COUNT: number = 50;
  private flakes: SnowFlake[] = [];

  constructor(width: number, height: number, daylight: boolean) {
    // kt:100-112
    const colors: string[] = daylight
      ? ['190,225,255', '211,233,255', '255,255,255']
      : ['111,133,155', '140,161,182', '255,255,255'];
    const scales: number[] = [0.6, 0.8, 1];
    for (let i = 0; i < SnowImplementor.SNOW_COUNT; i++) {
      const band: number = Math.floor(i * 3 / SnowImplementor.SNOW_COUNT);
      this.flakes.push(new SnowFlake(width, height, colors[band], scales[band]));
    }
  }

  private lastRotation3D: number = INITIAL_ROTATION_3D;

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    // kt:131-134
    const delta: number = this.lastRotation3D === INITIAL_ROTATION_3D
      ? 0
      : rotation3D - this.lastRotation3D;
    for (let i = 0; i < this.flakes.length; i++) {
      this.flakes[i].move(interval, delta);
    }
    this.lastRotation3D = rotation3D;
  }

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const alpha: number = 1 - scrollRate;
    ctx.save();
    // kt:145-149 — the whole snowfall leans with the phone.
    rotateAbout(ctx, rotation2D, width * 0.5, height * 0.5);
    for (let i = 0; i < this.flakes.length; i++) {
      const flake: SnowFlake = this.flakes[i];
      ctx.fillStyle = rgbaOf(flake.colorRgb, alpha);
      ctx.beginPath();
      ctx.arc(flake.centerX, flake.centerY, flake.radius, 0, 2 * Math.PI);
      ctx.fill();
    }
    ctx.restore();
  }
}

/* ------------------------------------------------------------------------ hail */

/** HailImplementor.Hail (kt:47-103). */
class HailStone {
  private readonly canvasSize: number;
  readonly colorRgb: string;
  private readonly scale: number;
  private readonly size: number;
  private readonly speedY: number;
  private speedX: number = 0;
  private speedRotation: number = 0;

  cx: number = 0;
  cy: number = 0;
  rotation: number = 0;
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  constructor(viewWidth: number, viewHeight: number, colorRgb: string, scale: number) {
    this.colorRgb = colorRgb;
    this.scale = scale;
    this.canvasSize = diagonalCanvasSize(viewWidth, viewHeight);
    // kt:67-68
    this.size = 0.0324 * Math.min(viewWidth, viewHeight) * 0.8;
    this.speedY = Math.min(viewWidth, viewHeight) / 150;
    this.init(true);
    this.buildRect();
  }

  /** kt:72-84 */
  private init(firstTime: boolean): void {
    this.cx = nextInt(this.canvasSize);
    this.cy = firstTime
      ? nextInt(Math.floor(this.canvasSize - this.size)) - this.canvasSize
      : -this.size;
    this.rotation = 360 * Math.random();
    this.speedRotation = 360 / 500 * Math.random();
    this.speedX = 0.75 * (Math.random() * this.speedY * (Math.random() < 0.5 ? 1 : -1));
  }

  private buildRect(): void {
    // kt:101 — the rect is built around cx/cy, the DIAGONAL-canvas position, and drawn there
    // too (kt:159-161). Upstream also computes a view-space centre but never draws with it, so
    // only the leftmost slice of the hail field is ever on screen. Kept as-is: the point of this
    // port is to match what the Android build renders, quirks included.
    this.left = this.cx - this.size * this.scale;
    this.top = this.cy - this.size * this.scale;
    this.right = this.cx + this.size * this.scale;
    this.bottom = this.cy + this.size * this.scale;
  }

  /** kt:91-102 */
  move(interval: number, deltaRotation3D: number): void {
    this.cx += this.speedX * interval * Math.pow(this.scale, 1.5);
    this.cy += this.speedY * interval *
      (Math.pow(this.scale, 1.5) - 5 * Math.sin(deltaRotation3D * DEG));
    this.rotation = (this.rotation + this.speedRotation * interval) % 360;
    if (this.cy - this.size >= this.canvasSize) {
      this.init(false);
    }
    this.buildRect();
  }
}

/** HailImplementor.kt:34-175. */
export class HailImplementor implements WeatherImplementor {
  private static readonly HAIL_COUNT: number = 51;
  private stones: HailStone[] = [];

  constructor(width: number, height: number, daylight: boolean) {
    // kt:106-118 — the same palette as sleet.
    const colors: string[] = daylight
      ? ['128,197,255', '185,222,255', '255,255,255']
      : ['40,102,155', '99,144,182', '255,255,255'];
    const scales: number[] = [0.6, 0.8, 1];
    for (let i = 0; i < HailImplementor.HAIL_COUNT; i++) {
      const band: number = Math.floor(i * 3 / HailImplementor.HAIL_COUNT);
      this.stones.push(new HailStone(width, height, colors[band], scales[band]));
    }
  }

  private lastRotation3D: number = INITIAL_ROTATION_3D;

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    // kt:137-140
    const delta: number = this.lastRotation3D === INITIAL_ROTATION_3D
      ? 0
      : rotation3D - this.lastRotation3D;
    for (let i = 0; i < this.stones.length; i++) {
      this.stones[i].move(interval, delta);
    }
    this.lastRotation3D = rotation3D;
  }

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const alpha: number = 1 - scrollRate;
    ctx.save();
    // kt:151-155 — the fall leans with the phone; each stone then spins about its own centre.
    rotateAbout(ctx, rotation2D, width * 0.5, height * 0.5);
    for (let i = 0; i < this.stones.length; i++) {
      const stone: HailStone = this.stones[i];
      ctx.fillStyle = rgbaOf(stone.colorRgb, alpha);
      // kt:159-161 — each square spins about its own centre.
      ctx.save();
      rotateAbout(ctx, stone.rotation, stone.cx, stone.cy);
      ctx.fillRect(stone.left, stone.top, stone.right - stone.left, stone.bottom - stone.top);
      ctx.restore();
    }
    ctx.restore();
  }
}

/* ------------------------------------------------------------------------ wind */

/** WindImplementor.Wind (kt:45-107) — the same shape as a rain drop, laid on its side. */
class WindStreak {
  private readonly viewWidth: number;
  private readonly viewHeight: number;
  private readonly canvasSize: number;
  private readonly maxWidth: number;
  private readonly minWidth: number;
  private readonly maxHeight: number;
  private readonly minHeight: number;
  readonly colorRgb: string;
  private readonly scale: number;
  private readonly speed: number;

  private x: number = 0;
  private y: number = 0;
  private width: number = 0;
  private height: number = 0;
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;

  constructor(viewWidth: number, viewHeight: number, colorRgb: string, scale: number) {
    this.viewWidth = viewWidth;
    this.viewHeight = viewHeight;
    this.colorRgb = colorRgb;
    this.scale = scale;
    this.canvasSize = diagonalCanvasSize(viewWidth, viewHeight);
    // kt:66-70 — wide and flat, and much faster than rain.
    this.speed = this.canvasSize / (1000.0 * (0.5 + Math.random())) * 6.0;
    this.maxHeight = 0.007 * this.canvasSize;
    this.minHeight = 0.005 * this.canvasSize;
    this.maxWidth = this.maxHeight * 10;
    this.minWidth = this.minHeight * 6;
    this.init(true);
  }

  /** kt:74-85 — streaks enter from the left, so x is the axis that resets. */
  private init(firstTime: boolean): void {
    this.y = nextInt(this.canvasSize);
    this.x = firstTime
      ? nextInt(Math.floor(this.canvasSize - this.maxHeight)) - this.canvasSize
      : -this.maxHeight;
    this.width = this.minWidth + Math.random() * (this.maxWidth - this.minWidth);
    this.height = this.minHeight + Math.random() * (this.maxHeight - this.minHeight);
    this.buildRect();
  }

  private buildRect(): void {
    const x: number = this.x - (this.canvasSize - this.viewWidth) * 0.5;
    const y: number = this.y - (this.canvasSize - this.viewHeight) * 0.5;
    this.left = x;
    this.top = y;
    this.right = x + this.width * this.scale;
    this.bottom = y + this.height * this.scale;
  }

  /** kt:93-106 */
  move(interval: number, deltaRotation3D: number): void {
    this.x += this.speed * interval *
      (Math.pow(this.scale, 1.5) + 5 * Math.sin(deltaRotation3D * DEG) * Math.cos(16 * DEG));
    this.y -= this.speed * interval * 5 * Math.sin(deltaRotation3D * DEG) * Math.sin(16 * DEG);
    if (this.x >= this.canvasSize) {
      this.init(false);
    } else {
      this.buildRect();
    }
  }
}

/** WindImplementor.kt:31-179. */
export class WindImplementor implements WeatherImplementor {
  private static readonly WIND_COUNT: number = 160;
  private streaks: WindStreak[] = [];

  constructor(width: number, height: number, daylight: boolean) {
    // kt:110-122 — the hex literals, not the commented-out rgb() values above them.
    const colors: string[] = daylight
      ? ['194,228,202', '178,224,186', '210,240,218']
      : ['49,62,58', '82,155,115', '99,129,112'];
    const scales: number[] = [0.6, 0.8, 1];
    for (let i = 0; i < WindImplementor.WIND_COUNT; i++) {
      const band: number = Math.floor(i * 3 / WindImplementor.WIND_COUNT);
      this.streaks.push(new WindStreak(width, height, colors[band], scales[band]));
    }
  }

  private lastRotation3D: number = INITIAL_ROTATION_3D;

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    // kt:141-144
    const delta: number = this.lastRotation3D === INITIAL_ROTATION_3D
      ? 0
      : rotation3D - this.lastRotation3D;
    for (let i = 0; i < this.streaks.length; i++) {
      this.streaks[i].move(interval, delta);
    }
    this.lastRotation3D = rotation3D;
  }

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const alpha: number = 1 - scrollRate;
    ctx.save();
    /*
     * kt:154-161 computes `rotation2Dc = rotation2D - 16f` and then rotates by the UNMODIFIED
     * rotation2D. The -16° never reaches the canvas — it is dead upstream, so this port rotates by
     * rotation2D too rather than "fixing" a lean the Android build does not have.
     */
    rotateAbout(ctx, rotation2D, width * 0.5, height * 0.5);
    for (let i = 0; i < this.streaks.length; i++) {
      const streak: WindStreak = this.streaks[i];
      ctx.fillStyle = rgbaOf(streak.colorRgb, alpha);
      ctx.fillRect(streak.left, streak.top, streak.right - streak.left, streak.bottom - streak.top);
    }
    ctx.restore();
  }
}

/* ------------------------------------------------------------- clear night sky */

/** MeteorShowerImplementor.Meteor (kt:49-122). */
class Meteor {
  private readonly canvasSize: number;
  private readonly viewWidth: number;
  private readonly viewHeight: number;
  readonly colorRgb: string;
  private readonly scale: number;
  readonly width: number;
  private readonly speed: number;
  private readonly maxHeight: number;
  private readonly minHeight: number;

  private x: number = 0;
  private y: number = 0;
  private height: number = 0;
  private progress: number = 0;
  private delay: number = 0;

  centerX: number = 0;
  top: number = 0;
  bottom: number = 0;

  constructor(viewWidth: number, viewHeight: number, colorRgb: string, scale: number) {
    this.viewWidth = viewWidth;
    this.viewHeight = viewHeight;
    this.colorRgb = colorRgb;
    this.scale = scale;
    this.canvasSize = diagonalCanvasSize(viewWidth, viewHeight);
    // kt:72-75
    this.width = viewWidth * 0.0088 * scale;
    this.speed = viewWidth / 200;
    this.maxHeight = 1.1 * viewWidth / Math.cos(60 * DEG);
    this.minHeight = this.maxHeight * 0.7;
    this.init(true);
  }

  /** kt:80-95 — METEOR_REVIVE_SEC_MIN 5 .. MAX 25 (kt:262-263). */
  private init(firstTime: boolean): void {
    this.progress = 0;
    this.delay = (nextInt(25 - 5) + 5) * 1000;
    this.x = nextInt(this.canvasSize);
    // kt:86-91 — the first generation starts far below the canvas so they do not all streak at once.
    this.y = firstTime
      ? this.canvasSize * 2
      : nextInt(this.canvasSize) - this.maxHeight - this.canvasSize;
    this.height = this.minHeight + Math.random() * (this.maxHeight - this.minHeight);
    this.buildRect();
  }

  private buildRect(): void {
    const x: number = this.x - (this.canvasSize - this.viewWidth) * 0.5;
    const y: number = this.y - (this.canvasSize - this.viewHeight) * 0.5;
    this.centerX = x + this.width / 2;
    this.top = y;
    this.bottom = y + this.height;
  }

  /** kt:103-121 — off the bottom, a meteor waits out its delay before respawning. */
  update(interval: number, deltaRotation3D: number): void {
    if (this.y > this.canvasSize) {
      this.progress += interval;
      if (this.progress > this.delay) {
        this.init(false);
      }
      return;
    }
    this.x -= this.speed * interval * 5 * Math.sin(deltaRotation3D * DEG) * Math.cos(60 * DEG);
    this.y += this.speed * interval *
      (Math.pow(this.scale, 0.5) - 5 * Math.sin(deltaRotation3D * DEG) * Math.sin(60 * DEG));
    this.buildRect();
  }
}

/** MeteorShowerImplementor.Star (kt:124-153) — a separate class from CloudImplementor's. */
class NightStar {
  readonly centerX: number;
  readonly centerY: number;
  readonly radius: number;
  readonly colorRgb: string;
  private readonly duration: number;
  private progress: number = 0;
  alpha: number = 0;

  constructor(centerX: number, centerY: number, radius: number, colorRgb: string, duration: number) {
    this.centerX = centerX;
    this.centerY = centerY;
    this.radius = radius * (0.7 + 0.3 * Math.random());
    this.colorRgb = colorRgb;
    this.duration = duration;
    this.computeAlpha();
  }

  shine(interval: number): void {
    this.progress = (this.progress + interval) % this.duration;
    this.computeAlpha();
  }

  /** kt:145-152 — a triangle wave, then compressed into 0.33..0.99 so no star fully vanishes. */
  private computeAlpha(): void {
    const half: number = 0.5 * this.duration;
    const raw: number = this.progress < half
      ? this.progress / half
      : 1 - (this.progress - half) / half;
    this.alpha = raw * 0.66 + 0.33;
  }
}

/** MeteorShowerImplementor.kt:35-269 — the clear NIGHT scene. */
export class MeteorShowerImplementor implements WeatherImplementor {
  private static readonly PALETTE: string[] = [
    '210,247,255', '208,233,255', '175,201,228', '164,194,220', '97,171,220',
    '74,141,193', '54,66,119', '34,48,74', '236,234,213', '240,220,151'
  ];

  private meteors: Meteor[] = [];
  private stars: NightStar[] = [];

  constructor(width: number, height: number) {
    // kt:172-179 — ten meteors, each a random colour and a random scale in 0..1.
    for (let i = 0; i < 10; i++) {
      this.meteors.push(new Meteor(
        width,
        height,
        MeteorShowerImplementor.PALETTE[nextInt(MeteorShowerImplementor.PALETTE.length)],
        Math.random()
      ));
    }
    // kt:180-195 — 70 stars spread over a band wider and taller than the view.
    const canvasSize: number = Math.floor(Math.pow(width * width + height * height, 0.5));
    const spreadWidth: number = canvasSize;
    const spreadHeight: number = Math.floor((canvasSize - height) * 0.5 + width * 1.1111);
    const radius: number = 0.00125 * canvasSize * (0.5 + Math.random());
    for (let i = 0; i < 70; i++) {
      const x: number = Math.trunc(nextInt(spreadWidth) - 0.5 * (canvasSize - width));
      const y: number = Math.trunc(nextInt(spreadHeight) - 0.5 * (canvasSize - height));
      this.stars.push(new NightStar(
        x,
        y,
        radius,
        MeteorShowerImplementor.PALETTE[i % MeteorShowerImplementor.PALETTE.length],
        2500 + Math.random() * 2500
      ));
    }
  }

  private lastRotation3D: number = INITIAL_ROTATION_3D;

  updateData(
    width: number,
    height: number,
    interval: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    // kt:206-214
    const delta: number = this.lastRotation3D === INITIAL_ROTATION_3D
      ? 0
      : rotation3D - this.lastRotation3D;
    for (let i = 0; i < this.meteors.length; i++) {
      this.meteors[i].update(interval, delta);
    }
    for (let i = 0; i < this.stars.length; i++) {
      this.stars[i].shine(interval);
    }
    this.lastRotation3D = rotation3D;
  }

  draw(
    ctx: CanvasRenderingContext2D,
    width: number,
    height: number,
    scrollRate: number,
    rotation2D: number,
    rotation3D: number
  ): void {
    if (scrollRate >= 1) {
      return;
    }
    const fade: number = 1 - scrollRate;
    ctx.save();
    // kt:224-237 — the star field leans with the phone. A round-capped point of stroke width 2r
    // is a filled circle of radius r.
    rotateAbout(ctx, rotation2D, width * 0.5, height * 0.5);
    for (let i = 0; i < this.stars.length; i++) {
      const star: NightStar = this.stars[i];
      ctx.fillStyle = rgbaOf(star.colorRgb, fade * star.alpha);
      ctx.beginPath();
      ctx.arc(star.centerX, star.centerY, star.radius, 0, 2 * Math.PI);
      ctx.fill();
    }
    // kt:238-256 — the meteors get a further 60° on top of the lean, which is what makes them
    // streak diagonally across the tilted star field.
    rotateAbout(ctx, 60, width * 0.5, height * 0.5);
    ctx.lineCap = 'round';
    for (let i = 0; i < this.meteors.length; i++) {
      const meteor: Meteor = this.meteors[i];
      ctx.strokeStyle = rgbaOf(meteor.colorRgb, fade);
      ctx.lineWidth = meteor.width;
      ctx.beginPath();
      ctx.moveTo(meteor.centerX, meteor.top);
      ctx.lineTo(meteor.centerX, meteor.bottom);
      ctx.stroke();
    }
    ctx.restore();
  }
}

/**
 * WeatherImplementorFactory.getWeatherImplementor (kt:37-150).
 *
 * Every kind the factory handles is now ported; only WEATHER_KIND_NULL falls through to the flat
 * themed background, exactly as upstream's `else -> null` does.
 */
export function createImplementor(
  kind: WeatherKind,
  daylight: boolean,
  darkMode: boolean,
  width: number,
  height: number
): WeatherImplementor | null {
  if (width <= 0 || height <= 0) {
    return null;
  }
  switch (kind) {
    case WeatherKind.CLEAR:
      // kt:47-57 — the sun by day, a meteor shower by night.
      return daylight ? new SunImplementor() : new MeteorShowerImplementor(width, height);
    case WeatherKind.CLOUD:
      return new CloudImplementor(width, height, CloudType.CLOUD, daylight, darkMode);
    case WeatherKind.CLOUDY:
      return new CloudImplementor(width, height, CloudType.CLOUDY, daylight, darkMode);
    case WeatherKind.FOG:
      return new CloudImplementor(width, height, CloudType.FOG, daylight, darkMode);
    case WeatherKind.HAZE:
      return new CloudImplementor(width, height, CloudType.HAZE, daylight, darkMode);
    case WeatherKind.RAINY:
      return new RainImplementor(width, height, RainType.RAIN, daylight);
    case WeatherKind.SLEET:
      return new RainImplementor(width, height, RainType.SLEET, daylight);
    case WeatherKind.SNOW:
      return new SnowImplementor(width, height, daylight);
    case WeatherKind.HAIL:
      return new HailImplementor(width, height, daylight);
    // kt:125-139 — the two thunder kinds use DIFFERENT implementors, which the port had merged:
    // a THUNDERSTORM is rain with a flash, plain THUNDER is the cloud scene with a flash.
    case WeatherKind.THUNDERSTORM:
      return new RainImplementor(width, height, RainType.THUNDERSTORM, daylight);
    case WeatherKind.THUNDER:
      return new CloudImplementor(width, height, CloudType.THUNDER, daylight, darkMode);
    case WeatherKind.WIND:
      return new WindImplementor(width, height, daylight);
    default:
      return null;
  }
}
