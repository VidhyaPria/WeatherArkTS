/*
 * Canvas text sizing.
 *
 * The trend charts draw into a Canvas whose RenderingContextSettings leave LengthMetricsUnit at
 * DEFAULT, so every coordinate, width and radius is in vp. The `font` shorthand is the one
 * exception: its `px` is parsed literally as physical pixels, and measureText reports back in
 * those same physical pixels.
 *
 * Passing the Android dp constants straight through (`'14px sans-serif'`) therefore drew the
 * labels at 14 physical pixels — about a third of the intended size on a 3.4x display, which is
 * why every chart label was far smaller than the Android app's. The size has to be scaled up on
 * the way in and the metrics scaled back down on the way out.
 */

import { APP_FONT_FAMILY } from '../../common/Typography';

/** Font shorthand for a size expressed in vp, matching the surrounding canvas geometry. */
export function canvasFont(sizeVp: number): string {
  // Roboto, registered in pages/Index.ets — the canvas labels must match the Text components.
  return vp2px(sizeVp).toString() + 'px ' + APP_FONT_FAMILY;
}

/*
 * Roboto's Android Paint.FontMetrics, as fractions of the text size.
 *
 * PolylineAndHistogramView places every chart label from `fontMetrics.top` and
 * `fontMetrics.bottom` — the full font box, not the ink box — so the low temperature clears its
 * polyline by an ascent and the high one clears its own by a descent (kt:244-253, 319-328), and
 * the histogram value drops a whole polyline text size below the chart (kt:356-363).
 *
 * These are computed rather than measured, and that is deliberate. `TextMetrics`'s
 * `fontBoundingBoxAscent` / `fontBoundingBoxDescent` on this canvas do not agree with either
 * reading of the unit: the labels came out about 2 vp off their lines whether the result was
 * passed through px2vp or not, which put every LOW temperature's baseline just under its polyline
 * and so drew the digits straight THROUGH it — the reported defect — sat the high temperatures on
 * their line, and lifted the precipitation percentages roughly 13 vp too high.
 *
 * Both are knowable without measuring. The typeface is Roboto, which the app registers itself
 * (pages/Index.ets) rather than inheriting, and the size is a constant from TrendDimens. These are
 * Roboto's own values — usWinAscent 1946 and usWinDescent 560 over 2048 units per em — so the
 * numbers are the ones Android's Paint reports for the same font at the same size.
 */
const ROBOTO_FONT_TOP: number = 0.9502;
const ROBOTO_FONT_BOTTOM: number = 0.2734;

/** |FontMetrics.top| for text drawn at `sizeVp`, in the canvas's vp coordinates. */
export function canvasFontAscent(sizeVp: number): number {
  return sizeVp * ROBOTO_FONT_TOP;
}

/** FontMetrics.bottom for text drawn at `sizeVp`. */
export function canvasFontDescent(sizeVp: number): number {
  return sizeVp * ROBOTO_FONT_BOTTOM;
}
