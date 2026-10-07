/*
 * The little moon-phase disc beside the phase label in the Moon block.
 *
 * 1:1 port of MoonPhaseView.kt (ui/common/widgets/astro/MoonPhaseView.kt). The surface angle is
 * MoonPhase.angle — 0 is new moon, 180 full, and the terminator is drawn as a half disc plus an
 * ellipse whose half-width is the cosine/sine of the angle (kt:92-155).
 *
 * Colours come from MoonViewHolder.kt:59-63:
 *   light  = colorTextLight2nd (#999999, colors.xml:79)
 *   dark   = colorTextDark2nd  (#666666, colors.xml:75)
 *   stroke = ?attr/colorBodyText
 */

/** kt:80 */
const PADDING: number = 4;
/** kt:52 */
const LINE_WIDTH: number = 1;

const DEG_TO_RAD: number = Math.PI / 180;

/** colors.xml:75,79 */
export const MOON_LIGHT_COLOR: string = '#FF999999';
export const MOON_DARK_COLOR: string = '#FF666666';

@ComponentV2
export struct MoonPhaseCanvas {
  // Not `size`: every component already inherits a `size()` attribute method.
  @Param discSize: number = 0;
  /** 0..360, clockwise from new moon. */
  @Param surfaceAngle: number = 0;
  @Param strokeColor: string = '#FF666666';
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  @Monitor('redrawKey', 'discSize', 'surfaceAngle')
  onRedrawRequested(monitor: IMonitor): void {
    if (this.ready) {
      this.draw();
    }
  }

  build() {
    Canvas(this.ctx)
      .width(this.discSize)
      .height(this.discSize)
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }

  /**
   * Half of the disc, closed through the diameter. Android calls drawArc(rect, from, 180, true)
   * on an ellipse; the ellipse becomes a scaled circle here.
   */
  private drawHalf(centerX: number, centerY: number, halfWidth: number, radius: number, fromDegrees: number): void {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.ellipse(
      centerX,
      centerY,
      Math.abs(halfWidth),
      radius,
      0,
      fromDegrees * DEG_TO_RAD,
      (fromDegrees + 180) * DEG_TO_RAD,
      false
    );
    ctx.closePath();
    ctx.fill();
  }

  private drawDisc(centerX: number, centerY: number, radius: number, color: string): void {
    const ctx = this.ctx;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    ctx.fill();
  }

  private draw(): void {
    const ctx = this.ctx;
    const size: number = this.discSize;
    if (size <= 2 * PADDING) {
      return;
    }
    ctx.clearRect(0, 0, size, size);

    const radius: number = (size - 2 * PADDING) / 2;
    const centerX: number = size / 2;
    const centerY: number = size / 2;
    const angle: number = this.surfaceAngle % 360;

    // kt:92-155 — the eight cases of the terminator.
    if (angle === 0) {
      this.drawDisc(centerX, centerY, radius, MOON_DARK_COLOR);
    } else if (angle < 90) {
      this.drawDisc(centerX, centerY, radius, MOON_LIGHT_COLOR);
      ctx.fillStyle = MOON_DARK_COLOR;
      this.drawHalf(centerX, centerY, radius, radius, 90);
      this.drawHalf(centerX, centerY, radius * Math.cos(angle * DEG_TO_RAD), radius, 270);
    } else if (angle === 90) {
      this.drawDisc(centerX, centerY, radius, MOON_DARK_COLOR);
      ctx.fillStyle = MOON_LIGHT_COLOR;
      this.drawHalf(centerX, centerY, radius, radius, 270);
    } else if (angle < 180) {
      this.drawDisc(centerX, centerY, radius, MOON_DARK_COLOR);
      ctx.fillStyle = MOON_LIGHT_COLOR;
      this.drawHalf(centerX, centerY, radius, radius, 270);
      this.drawHalf(centerX, centerY, radius * Math.sin((angle - 90) * DEG_TO_RAD), radius, 90);
    } else if (angle === 180) {
      this.drawDisc(centerX, centerY, radius, MOON_LIGHT_COLOR);
    } else if (angle < 270) {
      this.drawDisc(centerX, centerY, radius, MOON_DARK_COLOR);
      ctx.fillStyle = MOON_LIGHT_COLOR;
      this.drawHalf(centerX, centerY, radius, radius, 90);
      this.drawHalf(centerX, centerY, radius * Math.cos((angle - 180) * DEG_TO_RAD), radius, 270);
    } else if (angle === 270) {
      this.drawDisc(centerX, centerY, radius, MOON_DARK_COLOR);
      ctx.fillStyle = MOON_LIGHT_COLOR;
      this.drawHalf(centerX, centerY, radius, radius, 90);
    } else {
      this.drawDisc(centerX, centerY, radius, MOON_LIGHT_COLOR);
      ctx.fillStyle = MOON_DARK_COLOR;
      this.drawHalf(centerX, centerY, radius, radius, 270);
      this.drawHalf(centerX, centerY, radius * Math.cos((360 - angle) * DEG_TO_RAD), radius, 90);
    }

    // kt:156-176 — the terminator line, coloured by whichever side it separates.
    ctx.lineWidth = LINE_WIDTH;
    if (angle < 90 || angle > 270) {
      ctx.strokeStyle = MOON_DARK_COLOR;
      ctx.beginPath();
      ctx.moveTo(centerX, centerY - radius);
      ctx.lineTo(centerX, centerY + radius);
      ctx.stroke();
    } else if (angle > 90 && angle < 270) {
      ctx.strokeStyle = MOON_LIGHT_COLOR;
      ctx.beginPath();
      ctx.moveTo(centerX, centerY - radius);
      ctx.lineTo(centerX, centerY + radius);
      ctx.stroke();
    }

    // kt:177-183 — the outline.
    ctx.strokeStyle = this.strokeColor;
    ctx.beginPath();
    ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI);
    ctx.stroke();
  }
}
