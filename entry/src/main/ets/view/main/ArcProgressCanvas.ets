/*
 * Port of ArcProgress (ui/common/widgets/ArcProgress.kt) — the ring gauge behind the
 * air-quality and pressure blocks.
 *
 * Geometry from ArcProgress.onDraw (kt:127-136):
 *   startAngle = 270 - arcAngle / 2
 *   background arc swept over arcAngle
 *   progress arc swept over (progress / max) * arcAngle
 *
 * Both layouts pin app:arc_angle="270" (container_main_air_quality.xml,
 * container_main_pressure.xml), so the ring is open at the bottom: it starts at 135°
 * (bottom-left) and sweeps 270° clockwise to 45° (bottom-right).
 *
 * Callers supply the colours:
 *   air quality  progress = AQI, max = 250 (PollutantIndex.aqiThresholds.last()),
 *                colour = the level colour, background = that colour at 10% alpha
 *                (AirQualityViewHolder.kt:81-91)
 *   pressure     progress = hPa - 963, max = 100, colour = colorPrimary,
 *                background = colorPrimary at 10% alpha (PressureViewHolder.kt:59-68)
 */

const ARC_ANGLE: number = 270;
/** ArcProgress default stroke, scaled to the block. */
const STROKE_RATIO: number = 0.075;

@ComponentV2
export struct ArcProgressCanvas {
  @Param progress: number = 0;
  @Param max: number = 100;
  @Param progressColor: string = '#FF00668B';
  /**
   * Named trackColor, not backgroundColor: every @Component inherits a backgroundColor
   * attribute method from CustomComponent, so a member of that name collides with it.
   */
  @Param trackColor: string = '#1A00668B';
  @Param side: number = 0;
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  @Monitor('redrawKey')
  onRedrawRequested(monitor: IMonitor): void {
    if (this.ready) {
      this.draw();
    }
  }

  build() {
    Canvas(this.ctx)
      .width(this.side)
      .height(this.side)
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }

  private draw(): void {
    const ctx = this.ctx;
    if (this.side <= 0) {
      return;
    }
    ctx.clearRect(0, 0, this.side, this.side);

    const stroke: number = this.side * STROKE_RATIO;
    const radius: number = (this.side - stroke) / 2;
    const centre: number = this.side / 2;

    // Canvas angles are in radians and already measured from 3 o'clock clockwise,
    // matching Android's drawArc convention.
    const startAngle: number = (270 - ARC_ANGLE / 2) * Math.PI / 180;
    const fullSweep: number = ARC_ANGLE * Math.PI / 180;

    ctx.lineCap = 'round';
    ctx.lineWidth = stroke;

    ctx.beginPath();
    ctx.strokeStyle = this.trackColor;
    ctx.arc(centre, centre, radius, startAngle, startAngle + fullSweep);
    ctx.stroke();

    if (this.progress > 0 && this.max > 0) {
      const ratio: number = Math.min(1, this.progress / this.max);
      ctx.beginPath();
      ctx.strokeStyle = this.progressColor;
      ctx.arc(centre, centre, radius, startAngle, startAngle + fullSweep * ratio);
      ctx.stroke();
    }
  }
}
