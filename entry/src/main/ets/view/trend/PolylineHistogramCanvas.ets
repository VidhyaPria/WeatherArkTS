/*
 * Port of PolylineAndHistogramView (ui/common/widgets/trend/chart/PolylineAndHistogramView.kt).
 *
 * Draw order and geometry follow onDraw (kt:101-122) exactly:
 *   1. vertical time line          drawTimeLine        kt:124-137
 *   2. histogram (rounded bar)     drawHistogram       kt:332-365
 *   3. high polyline + shadow      drawHighPolyLine    kt:139-255
 *   4. low polyline                drawLowPolyline     kt:257-330
 *
 * All sizes come from the companion object (kt:513-524) via TrendDimens.
 */

import { TrendDimens } from '../../theme/Dimens';
import { withAlpha } from '../../theme/AppColors';
import { ChartColors, ChartData } from './ChartData';
import { canvasFont, canvasFontAscent, canvasFontDescent } from './CanvasText';

/**
 * A painter, not a component. It used to be its own @ComponentV2 struct, swapped in and out of
 * TrendItem against DoubleHistogramCanvas whenever a tab changed the chart kind — and swapping
 * custom components destroys one and builds the other, ~9 ms build + up to 20 ms destroy per
 * column, which the trace showed as the 130-270 ms dirty-node flush behind every remaining
 * tab-tap hitch. TrendChartCanvas now owns the one persistent Canvas and calls whichever painter
 * the current kind needs. The draw bodies below are unchanged.
 */
export class PolylineHistogramPainter {
  private data: ChartData = new ChartData();
  private colors: ChartColors = new ChartColors();
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private ctx!: CanvasRenderingContext2D;

  paint(
    ctx: CanvasRenderingContext2D,
    data: ChartData,
    colors: ChartColors,
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

  private marginTop(): number {
    return TrendDimens.CHART_MARGIN_TOP;
  }

  private marginBottom(): number {
    return TrendDimens.CHART_MARGIN_BOTTOM;
  }

  /** kt:500-507 — computeSingleCoordinate. */
  private computeY(value: number, max: number, min: number): number {
    const usableHeight: number = this.canvasHeight - this.marginTop() - this.marginBottom();
    if (max === min) {
      return this.canvasHeight - this.marginBottom();
    }
    return this.canvasHeight - this.marginBottom() - (usableHeight * (value - min) / (max - min));
  }

  private computePolylineY(values: (number | null)[], max: number, min: number): number[] {
    const out: number[] = [0, 0, 0];
    for (let i = 0; i < values.length; i++) {
      const v: number | null = values[i];
      out[i] = v === null ? 0 : this.computeY(v, max, min);
    }
    return out;
  }

  private draw(): void {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);

    this.drawTimeLine();

    const d: ChartData = this.data;

    // kt:106-113 — the histogram is drawn when it has a value, and either that value is
    // non-zero or there is no polyline at all.
    const hasPolyline: boolean = d.highestValue !== null && d.lowestValue !== null;
    if (
      d.histogramValue !== null &&
      (d.histogramValue !== 0 || !hasPolyline) &&
      d.histogramText !== null &&
      d.highestHistogramValue !== null &&
      d.lowestHistogramValue !== null
    ) {
      this.drawHistogram(d.histogramValue, d.histogramText, d.highestHistogramValue, d.lowestHistogramValue);
    }

    if (!hasPolyline) {
      return;
    }
    const max: number = d.highestValue as number;
    const min: number = d.lowestValue as number;
    const highY: number[] = this.computePolylineY(d.highPolyline.values, max, min);
    const lowY: number[] = this.computePolylineY(d.lowPolyline.values, max, min);

    if (d.highText !== null) {
      this.drawHighPolyline(d.highPolyline.values, highY, lowY, d.highText);
    }
    if (d.lowText !== null) {
      this.drawLowPolyline(d.lowPolyline.values, highY, lowY, d.lowText);
    }
  }

  /** kt:124-137 */
  private drawTimeLine(): void {
    const ctx = this.ctx;
    ctx.beginPath();
    ctx.lineCap = 'round';
    ctx.lineWidth = TrendDimens.CHART_LINE_SIZE;
    ctx.strokeStyle = this.colors.subLine;
    ctx.moveTo(this.canvasWidth / 2, this.marginTop());
    ctx.lineTo(this.canvasWidth / 2, this.canvasHeight - this.marginBottom());
    ctx.stroke();
  }

  /** kt:332-365 */
  private drawHistogram(value: number, text: string, highest: number, lowest: number): void {
    const ctx = this.ctx;
    const y: number = this.computeY(value, highest, lowest);
    const halfWidth: number = TrendDimens.HISTOGRAM_WIDTH;
    const left: number = this.canvasWidth / 2 - halfWidth;
    const right: number = this.canvasWidth / 2 + halfWidth;
    const bottom: number = this.canvasHeight - this.marginBottom();

    const d: ChartData = this.data;
    const barColor: string = d.histogramColor !== null ? d.histogramColor : this.colors.lowLine;
    const barAlpha: number = d.histogramAlpha !== null ? d.histogramAlpha : this.colors.histogramAlpha;

    ctx.fillStyle = withAlpha(barColor, barAlpha);
    ctx.beginPath();
    // drawRoundRect with rx = ry = mHistogramWidth.
    this.roundRectPath(left, y, right, bottom, halfWidth);
    ctx.fill();

    ctx.fillStyle = d.histogramTextColor !== null ? d.histogramTextColor : this.colors.histogramText;
    ctx.textAlign = 'center';
    ctx.font = canvasFont(TrendDimens.HISTOGRAM_TEXT_SIZE);
    const ascent: number = canvasFontAscent(TrendDimens.HISTOGRAM_TEXT_SIZE);
    // kt:356-363: baseline sits below the chart area by 2 * textMargin + the polyline text size.
    const textY: number =
      (bottom + ascent) + 2 * TrendDimens.CHART_TEXT_MARGIN + TrendDimens.POLYLINE_TEXT_SIZE;
    ctx.fillText(text, this.canvasWidth / 2, textY);
  }

  private roundRectPath(left: number, top: number, right: number, bottom: number, radius: number): void {
    const ctx = this.ctx;
    const height: number = bottom - top;
    const r: number = Math.min(radius, height / 2);
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

  /** kt:139-255 */
  private drawHighPolyline(values: (number | null)[], highY: number[], lowY: number[], text: string): void {
    const ctx = this.ctx;
    const w: number = this.canvasWidth;
    const bottom: number = this.canvasHeight - this.marginBottom();

    const hasPrevious: boolean = values[0] !== null;
    const hasNext: boolean = values[2] !== null;

    // Shadow — a vertical gradient from the theme colour to transparent (kt:438-456).
    const gradient = ctx.createLinearGradient(0, this.marginTop(), 0, bottom);
    gradient.addColorStop(0, this.colors.shadowTop);
    gradient.addColorStop(1, '#00000000');
    ctx.fillStyle = gradient;
    ctx.beginPath();
    if (hasPrevious && hasNext) {
      ctx.moveTo(0, highY[0]);
      ctx.lineTo(w / 2, highY[1]);
      ctx.lineTo(w, highY[2]);
      ctx.lineTo(w, bottom);
      ctx.lineTo(0, bottom);
    } else if (!hasPrevious) {
      ctx.moveTo(w / 2, highY[1]);
      ctx.lineTo(w, highY[2]);
      ctx.lineTo(w, bottom);
      ctx.lineTo(w / 2, bottom);
    } else {
      ctx.moveTo(0, highY[0]);
      ctx.lineTo(w / 2, highY[1]);
      ctx.lineTo(w / 2, bottom);
      ctx.lineTo(0, bottom);
    }
    ctx.closePath();
    ctx.fill();

    // Line.
    ctx.beginPath();
    ctx.lineCap = 'round';
    ctx.lineWidth = TrendDimens.POLYLINE_SIZE;
    ctx.strokeStyle = this.colors.highLine;
    if (hasPrevious && hasNext) {
      ctx.moveTo(0, highY[0]);
      ctx.lineTo(w / 2, highY[1]);
      ctx.lineTo(w, highY[2]);
    } else if (!hasPrevious) {
      ctx.moveTo(w / 2, highY[1]);
      ctx.lineTo(w, highY[2]);
    } else {
      ctx.moveTo(0, highY[0]);
      ctx.lineTo(w / 2, highY[1]);
    }
    ctx.stroke();

    // Text (kt:236-254).
    ctx.fillStyle = this.colors.highText;
    ctx.textAlign = 'center';
    ctx.font = canvasFont(TrendDimens.POLYLINE_TEXT_SIZE);
    const ascent: number = canvasFontAscent(TrendDimens.POLYLINE_TEXT_SIZE);
    const descent: number = canvasFontDescent(TrendDimens.POLYLINE_TEXT_SIZE);
    const y: number = highY[1] > lowY[1]
      ? highY[1] + ascent + TrendDimens.CHART_TEXT_MARGIN
      : highY[1] - descent - TrendDimens.CHART_TEXT_MARGIN;
    ctx.fillText(text, w / 2, y);
  }

  /** kt:257-330 — same shapes as the high polyline but with no shadow fill. */
  private drawLowPolyline(values: (number | null)[], highY: number[], lowY: number[], text: string): void {
    const ctx = this.ctx;
    const w: number = this.canvasWidth;

    const hasPrevious: boolean = values[0] !== null;
    const hasNext: boolean = values[2] !== null;

    ctx.beginPath();
    ctx.lineCap = 'round';
    ctx.lineWidth = TrendDimens.POLYLINE_SIZE;
    ctx.strokeStyle = this.colors.lowLine;
    if (hasPrevious && hasNext) {
      ctx.moveTo(0, lowY[0]);
      ctx.lineTo(w / 2, lowY[1]);
      ctx.lineTo(w, lowY[2]);
    } else if (!hasPrevious) {
      ctx.moveTo(w / 2, lowY[1]);
      ctx.lineTo(w, lowY[2]);
    } else {
      ctx.moveTo(0, lowY[0]);
      ctx.lineTo(w / 2, lowY[1]);
    }
    ctx.stroke();

    ctx.fillStyle = this.colors.lowText;
    ctx.textAlign = 'center';
    ctx.font = canvasFont(TrendDimens.POLYLINE_TEXT_SIZE);
    const ascent: number = canvasFontAscent(TrendDimens.POLYLINE_TEXT_SIZE);
    const descent: number = canvasFontDescent(TrendDimens.POLYLINE_TEXT_SIZE);
    const y: number = highY[1] > lowY[1]
      ? lowY[1] - descent - TrendDimens.CHART_TEXT_MARGIN
      : lowY[1] + ascent + TrendDimens.CHART_TEXT_MARGIN;
    ctx.fillText(text, w / 2, y);
  }

}
