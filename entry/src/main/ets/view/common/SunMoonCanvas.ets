/*
 * SunDrawable and MoonDrawable — ui/common/images/SunDrawable.kt:32-91 and MoonDrawable.kt:33-85.
 *
 * The two Ephemeris cells of the icon preview are the only place the app draws these directly:
 * everywhere else `ResourceHelper.getSunDrawable` / `getMoonDrawable` feed an ImageView. They are
 * pure procedural shapes, so they port as Canvas paths rather than as assets.
 *
 * Sun (kt:69-91):  a square of side 2r, the same square rotated 45° about the centre, then a
 *                  filled circle of radius r on top. r = sin(45°) * min(w,h) / 2 - 2.
 * Moon (kt:70-85): a filled circle, with a second circle punched out of it — `PorterDuff.CLEAR`
 *                  inside a saved layer, which is `destination-out` on a Canvas.
 */

/** SunDrawable.kt:38 — Color.rgb(254, 214, 117). */
const SUN_CORE: string = '#FFFED675';
/** SunDrawable.kt:42-45 — only mHaloColors[0] is ever painted; [1] is declared and unused. */
const SUN_HALO: string = '#FFF9B75D';
/** MoonDrawable.kt:40 — Color.rgb(171, 202, 247). */
const MOON_CORE: string = '#FFABCAF7';

const SIN_45: number = Math.sin(Math.PI / 4);

@ComponentV2
export struct SunMoonCanvas {
  /** The drawable's bounds, square — the cell's inner box. */
  @Param boxSize: number = 48;
  @Param isSun: boolean = true;
  /** Changing this repaints; onReady fires once (see MoonPhaseCanvas for the same guard). */
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  build() {
    Canvas(this.context)
      .width(this.boxSize)
      .height(this.boxSize)
      .onReady(() => {
        this.paint();
      })
      .id('sunmoon_' + this.redrawKey)
  }

  @Monitor('redrawKey', 'boxSize', 'isSun')
  private onChange(): void {
    this.paint();
  }

  private paint(): void {
    const ctx = this.context;
    const side: number = this.boxSize;
    if (side <= 0) {
      return;
    }
    ctx.clearRect(0, 0, side, side);
    const cx: number = side / 2;
    const cy: number = side / 2;

    if (this.isSun) {
      // kt:59 — r = sin(45°) * min(w, h) / 2 - 2.
      const radius: number = SIN_45 * side / 2 - 2;
      if (radius <= 0) {
        return;
      }
      ctx.fillStyle = SUN_HALO;
      ctx.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(Math.PI / 4);
      ctx.translate(-cx, -cy);
      ctx.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);
      ctx.restore();
      ctx.fillStyle = SUN_CORE;
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.fill();
      return;
    }

    // kt:57-62 — the core, then a circle punched out of it up and to the right.
    const coreRadius: number = (SIN_45 * side / 2 + side / 2) / 2 - 2;
    if (coreRadius <= 0) {
      return;
    }
    const shaderRadius: number = coreRadius * 0.9050;
    const shaderX: number = cx + coreRadius * 0.5914;
    const shaderY: number = cy - coreRadius * 0.5932;

    ctx.fillStyle = MOON_CORE;
    ctx.beginPath();
    ctx.arc(cx, cy, coreRadius, 0, Math.PI * 2);
    ctx.fill();
    // PorterDuff.CLEAR inside saveLayer — the pixels go away rather than being painted over, so
    // the crescent shows whatever is behind the canvas.
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(shaderX, shaderY, shaderRadius, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
  }
}
