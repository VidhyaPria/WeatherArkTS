/*
 * Port of DoubleHistogramView (ui/common/widgets/trend/chart/DoubleHistogramView.kt).
 *
 * Used by the daily Wind and daily Precipitation tabs (DailyWindAdapter.kt:51,
 * DailyPrecipitationAdapter.kt:56). Two bars grow outwards from the vertical centre:
 * the high bar upwards, the low bar downwards.
 *
 * Geometry from onDraw (kt:80-189), computeCoordinates (kt:228-241) and the companion
 * object (kt:243-250).
 */

import { withAlpha } from '../../theme/AppColors';
import { canvasFont, canvasFontAscent, canvasFontDescent } from './CanvasText';

/** DoubleHistogramView companion constants (kt:243-250). */
class DoubleHistogramDimens {
  static readonly MARGIN: number = 24;
  static readonly MARGIN_CENTER: number = 4;
  static readonly HISTOGRAM_WIDTH: number = 8;
  static readonly HISTOGRAM_TEXT_SIZE: number = 14;
  static readonly CHART_LINE_SIZE: number = 1;
  static readonly TEXT_MARGIN: number = 2;
}

export class DoubleHistogramData {
  highValue: number | null = null;
  lowValue: number | null = null;
  highText: string | null = null;
  lowText: string | null = null;
  /** Scale reference — both bars are drawn relative to this (kt:228-241). */
  highestValue: number | null = null;
  /*
   * Per-bar colours. Both double-histogram tabs recolour every bar from its own value —
   * Beaufort band for wind (DailyWindAdapter.kt:87-91) and precipitation band for rain
   * (DailyPrecipitationAdapter.kt:107-108). Null means "use the card colour".
   */
  highColor: string | null = null;
  lowColor: string | null = null;
}

export class DoubleHistogramColors {
  /** mLineColors[0] */
  highBar: string = '#FF000000';
  /** mLineColors[1] */
  lowBar: string = '#FF444444';
  /** mLineColors[2] */
  subLine: string = '#FFCCCCCC';
  text: string = '#FF000000';
  /** setHistogramAlphas(high, low) */
  highAlpha: number = 1;
  lowAlpha: number = 1;
}

/** A painter, not a component — see PolylineHistogramPainter for why. Draw bodies unchanged. */
export class DoubleHistogramPainter {
  private data: DoubleHistogramData = new DoubleHistogramData();
  private colors: DoubleHistogramColors = new DoubleHistogramColors();
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private ctx!: CanvasRenderingContext2D;

  paint(
    ctx: CanvasRenderingContext2D,
    data: DoubleHistogramData,
    colors: DoubleHistogramColors,
    canvasWidth: number,
    canvasHeight: number
  ): void {
    this.ctx = ctx;
    this.data = data;
    this.colors = colors;
    this.canvasWidth = canvasWidth;
    this.canvasHeight = canvasHeight;
    this.draw();
  }

  private draw(): void {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);

    this.drawTimeLine();

    const d: DoubleHistogramData = this.data;
    if (d.highestValue === null || d.highestValue === 0) {
      return;
    }
    // kt:84-91 — zero-valued bars are skipped entirely.
    if (d.highValue !== null && d.highValue !== 0 && d.highText !== null) {
      this.drawHighHistogram(d.highValue, d.highText, d.highestValue);
    }
    if (d.lowValue !== null && d.lowValue !== 0 && d.lowText !== null) {
      this.drawLowHistogram(d.lowValue, d.lowText, d.highestValue);
    }
  }

  /** kt:94-105 */
  private drawTimeLine(): void {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.lineCap = 'round';
    ctx.lineWidth = DoubleHistogramDimens.CHART_LINE_SIZE;
    ctx.strokeStyle = this.colors.subLine;
    ctx.moveTo(this.canvasWidth / 2, DoubleHistogramDimens.MARGIN);
    ctx.lineTo(this.canvasWidth / 2, this.canvasHeight - DoubleHistogramDimens.MARGIN);
    ctx.stroke();
  }

  /** Half the height available to one bar (kt:229). */
  private barAreaHeight(): number {
    return (this.canvasHeight - DoubleHistogramDimens.MARGIN * 2 - DoubleHistogramDimens.MARGIN_CENTER) / 2;
  }

  /** kt:107-147 */
  private drawHighHistogram(value: number, text: string, highest: number): void {
    const ctx = this.ctx;
    const cx: number = this.canvasWidth / 2;
    const cy: number = this.canvasHeight / 2 - DoubleHistogramDimens.MARGIN_CENTER / 2;
    const y: number = this.canvasHeight / 2 - DoubleHistogramDimens.MARGIN_CENTER / 2 -
      this.barAreaHeight() * value / highest;
    const halfWidth: number = DoubleHistogramDimens.HISTOGRAM_WIDTH / 2;

    const barColor: string = this.data.highColor !== null ? this.data.highColor : this.colors.highBar;
    ctx.fillStyle = withAlpha(barColor, this.colors.highAlpha);
    ctx.beginPath();
    this.roundRectPath(cx - halfWidth, y, cx + halfWidth, cy, halfWidth);
    ctx.fill();

    ctx.fillStyle = this.colors.text;
    ctx.textAlign = 'center';
    ctx.font = canvasFont(DoubleHistogramDimens.HISTOGRAM_TEXT_SIZE);
    ctx.fillText(text, cx, y - canvasFontDescent(DoubleHistogramDimens.HISTOGRAM_TEXT_SIZE) - DoubleHistogramDimens.TEXT_MARGIN);
  }

  /** kt:149-189 */
  private drawLowHistogram(value: number, text: string, highest: number): void {
    const ctx = this.ctx;
    const cx: number = this.canvasWidth / 2;
    const cy: number = this.canvasHeight / 2 + DoubleHistogramDimens.MARGIN_CENTER / 2;
    const y: number = this.canvasHeight / 2 + DoubleHistogramDimens.MARGIN_CENTER / 2 +
      this.barAreaHeight() * value / highest;
    const halfWidth: number = DoubleHistogramDimens.HISTOGRAM_WIDTH / 2;

    const barColor: string = this.data.lowColor !== null ? this.data.lowColor : this.colors.lowBar;
    ctx.fillStyle = withAlpha(barColor, this.colors.lowAlpha);
    ctx.beginPath();
    this.roundRectPath(cx - halfWidth, cy, cx + halfWidth, y, halfWidth);
    ctx.fill();

    ctx.fillStyle = this.colors.text;
    ctx.textAlign = 'center';
    ctx.font = canvasFont(DoubleHistogramDimens.HISTOGRAM_TEXT_SIZE);
    ctx.fillText(text, cx, y + canvasFontAscent(DoubleHistogramDimens.HISTOGRAM_TEXT_SIZE) + DoubleHistogramDimens.TEXT_MARGIN);
  }

  private roundRectPath(left: number, top: number, right: number, bottom: number, radius: number): void {
    const ctx = this.ctx;
    const r: number = Math.min(radius, (bottom - top) / 2);
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

}
