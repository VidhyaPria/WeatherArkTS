/*
 * Inputs to the trend chart, matching PolylineAndHistogramView.setData / setLineColors /
 * setShadowColors / setTextColors / setHistogramAlpha (PolylineAndHistogramView.kt:368-436).
 */

/**
 * Three-point polyline: [previous midpoint, this item, next midpoint].
 * A null entry means "no neighbour", which changes which segments are drawn
 * (PolylineAndHistogramView.kt:142-234).
 */
export class PolylinePoints {
  readonly values: (number | null)[];

  constructor(previous: number | null, current: number | null, next: number | null) {
    this.values = [previous, current, next];
  }

  static empty(): PolylinePoints {
    return new PolylinePoints(null, null, null);
  }
}

export class ChartColors {
  /** mLineColors[0] — the high polyline. */
  highLine: string = '#FF000000';
  /** mLineColors[1] — the low polyline and the histogram fill. */
  lowLine: string = '#FF444444';
  /** mLineColors[2] — the vertical time line. */
  subLine: string = '#FFCCCCCC';
  /** mShadowColors[0] — top of the gradient under the high polyline. */
  shadowTop: string = '#00000000';
  highText: string = '#FF000000';
  lowText: string = '#FF666666';
  histogramText: string = '#FF00668B';
  /** setHistogramAlpha — 0.2 in light theme, 0.5 in dark (DailyTemperatureAdapter.kt:166). */
  histogramAlpha: number = 0.2;
}

export class ChartData {
  /**
   * Leave highestValue/lowestValue null to draw no polyline at all. Six tabs do exactly that —
   * they instantiate PolylineAndHistogramView with all six polyline arguments null and show only
   * the histogram (e.g. HourlyWindAdapter.kt:75-82, DailyUVAdapter.kt:69-74).
   */
  highPolyline: PolylinePoints = PolylinePoints.empty();
  lowPolyline: PolylinePoints = PolylinePoints.empty();
  highText: string | null = null;
  lowText: string | null = null;
  highestValue: number | null = null;
  lowestValue: number | null = null;

  histogramValue: number | null = null;
  histogramText: string | null = null;
  highestHistogramValue: number | null = null;
  lowestHistogramValue: number | null = null;

  /*
   * Per-item overrides of the card-level ChartColors. Wind and UV recolour every bar from the
   * value itself (setLineColors is called per bind, e.g. HourlyWindAdapter.kt:83-87), which a
   * single card-level colour cannot express. Null means "use the card colour".
   */
  histogramColor: string | null = null;
  /** setHistogramAlpha — 1.0 for the histogram-only tabs, vs 0.2/0.5 for precipitation probability. */
  histogramAlpha: number | null = null;
  histogramTextColor: string | null = null;
}
