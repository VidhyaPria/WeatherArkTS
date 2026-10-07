/*
 * Screen 4's line chart — the port of BreezyLineChart.kt:100-246 and its two custom fills.
 *
 * The thing that makes this chart unlike the trend-card charts is its colouring. `ScaleLineFill`
 * and `ScaleAreaFill` (kt:251-325) build ONE vertical LinearGradientShader across the whole plot
 * from the tag's value scale — stops at `1 - (y - minY) / (maxY - minY)` — and paint the STROKE
 * with it as well as the area. So the line's colour at any height is the colour that height means,
 * and the area is the same shader at alpha 128 (kt:283).
 *
 * Everything else is Vico's default cartesian furniture, reproduced: an end axis with a line, ticks,
 * dashed guidelines and labels; a bottom axis whose labels sit at local 06:00, 12:00 and 18:00
 * (TimeHorizontalAxisItemPlacer, AxisItemPlacer.kt:37-65); an optional top axis of trend arrows
 * placed by TimeTopAxisItemPlacer (kt:70-124); and the trendHorizontalLine, which is gated on
 * screen 3c's `trend_horizontal_line_switch` exactly as kt:223-235 gates it.
 */

import { ChartKeyLine, ChartPoint, ChartStop, DetailsChartSpec } from './DetailsData';
import { AppColors } from '../../theme/AppColors';
import { Dimens } from '../../theme/Dimens';
import { APP_FONT_FAMILY } from '../../common/Typography';
import { getHour } from '../../common/Formatter';
import { HOUR_MS } from '../../common/LocalTime';
import { WeatherKind } from '../../model/WeatherKind';
import { getWeatherIcon } from '../../common/WeatherIcons';

/** One placed top-axis weather icon: where it goes and which icon it is. */
class TopIconSlot {
  x: number = 0;
  kind: WeatherKind = WeatherKind.NULL;
  daylight: boolean = true;
  /** Identity for the ForEach — the hour plus what is drawn there. */
  key: string = '';
}

/** True when two placements would render identically, so the @Local need not be replaced. */
function sameSlots(a: TopIconSlot[], b: TopIconSlot[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i].key !== b[i].key || Math.abs(a[i].x - b[i].x) > 0.5) {
      return false;
    }
  }
  return true;
}

/** BreezyLineChart.kt:327-330. */
const LINE_CHART_HEIGHT_MIN: number = 100;
const LINE_THICKNESS: number = 5;
/** Vico's axis furniture, in vp. */
const AXIS_LABEL_SIZE: number = 12;
const AXIS_LABEL_PADDING: number = 4;
const TICK_LENGTH: number = 4;
const GUIDELINE_DASH: number = 4;
/** DetailsPressure.kt:269 — the top axis is a fixed 23 dp band. */
const TOP_AXIS_HEIGHT: number = 23;
const ARROW_SIZE: number = 18;
/** The conditions chart's top-axis icons — the same 18 dp box the arrows use (kt:861). */
const TOP_ICON_SIZE: number = 18;
/**
 * `PointConnector.cubic(curvature = ((PI - 2) / PI))` — DetailsSunMoon.kt:123-125, the one chart
 * that curves.
 */
const CUBIC_CURVATURE: number = (Math.PI - 2) / Math.PI;

@ComponentV2
export struct DetailsChartCanvas {
  @Require @Param spec: DetailsChartSpec;
  @Param utcOffsetSeconds: number = 0;
  @Param isDark: boolean = false;
  /** screen 3c's `trend_horizontal_line_switch`; the key line is not drawn when it is off. */
  @Param keyLinesEnabled: boolean = true;
  /** The window height in vp, which is what sets the chart's own height (kt:244). */
  @Param windowHeightVp: number = 800;
  /** Bumped by the caller when anything the chart draws changes, so the canvas repaints. */
  @Param revision: string = '';
  /** The hour the marker is on, or -1. Drives the header through the page. */
  @Param activeHourMs: number = -1;
  @Event onActiveHourChange: (at: number) => void = () => {};

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  /**
   * The repaint trigger. `onReady` fires ONCE, and an `.id()` that changes with the params does
   * NOT re-run it — which is why the marker never appeared and why the Actual/Feels-like switcher
   * left the previous tag's plot on screen. Same mechanism TrendChartCanvas already uses.
   */
  @Monitor('revision', 'activeHourMs', 'isDark', 'keyLinesEnabled', 'windowHeightVp')
  onRedrawRequested(monitor: IMonitor): void {
    if (this.ready) {
      this.draw();
    }
  }

  private chartHeight(): number {
    return Math.max(LINE_CHART_HEIGHT_MIN, this.windowHeightVp / 4);
  }

  /** The plot's left/right in vp, stashed by the draw so a touch can be mapped back to an hour. */
  private plotLeftPx: number = 0;
  private plotRightPx: number = 0;

  /**
   * The top axis's weather icons, in vp, published by the draw.
   *
   * They are PNGs, and an ArkUI `Canvas` can only paint one through an `ImageBitmap` that has to
   * be constructed and decoded before `drawImage` — on a chart that repaints on every marker move.
   * Laying them out as ordinary `Image` components over the canvas costs one node each and lets
   * the framework own the decode and the cache, which is also what the rest of this port does with
   * weather icons. The POSITIONS still come from the draw, because the plot's left and right edges
   * depend on `measureText` of the end-axis labels and nothing outside the canvas knows them.
   */
  @Local private iconSlots: TopIconSlot[] = [];

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.canvas()
      ForEach(this.iconSlots, (slot: TopIconSlot) => {
        Image(getWeatherIcon(slot.kind, slot.daylight))
          .width(TOP_ICON_SIZE)
          .height(TOP_ICON_SIZE)
          // The icon is centred on its hour, inside the 23 vp band the top axis reserves.
          .position({ x: slot.x - TOP_ICON_SIZE / 2, y: (TOP_AXIS_HEIGHT - TOP_ICON_SIZE) / 2 })
          // The canvas below owns the marker gesture; the icons must not steal it.
          .hitTestBehavior(HitTestMode.None)
      }, (slot: TopIconSlot) => slot.key)
    }
    .width('100%')
    .height(this.chartHeight())
  }

  @Builder
  private canvas() {
    Canvas(this.context)
      .width('100%')
      .height(this.chartHeight())
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
      /*
       * The marker (BreezyLineChart's `marker` + `markerVisibilityListener`, kt:145-174). A touch
       * anywhere over the plot snaps to the nearest plotted hour and the header switches to that
       * hour's reading; lifting clears it, which is `onHidden`.
       */
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.onActiveHourChange(-1);
          return;
        }
        const x: number = event.touches[0].x;
        this.onActiveHourChange(this.hourAt(x));
      })
      .id('detailsChart')
  }

  /** The plotted hour nearest a touch, or -1 when the chart has no points. */
  private hourAt(x: number): number {
    if (this.spec.points.length === 0 || this.plotRightPx <= this.plotLeftPx) {
      return -1;
    }
    const span: number = this.spec.maxX - this.spec.minX;
    const ratio: number =
      (x - this.plotLeftPx) / (this.plotRightPx - this.plotLeftPx);
    const wanted: number = this.spec.minX + Math.max(0, Math.min(1, ratio)) * span;
    let best: number = this.spec.points[0].x;
    let bestGap: number = Math.abs(best - wanted);
    for (const point of this.spec.points) {
      const gap: number = Math.abs(point.x - wanted);
      if (gap < bestGap) {
        bestGap = gap;
        best = point.x;
      }
    }
    return best;
  }

  private draw(): void {
    const ctx = this.context;
    const width: number = ctx.width;
    const height: number = ctx.height;
    if (width <= 0 || height <= 0 || this.spec.points.length < 2) {
      return;
    }
    ctx.clearRect(0, 0, width, height);

    const labelColor: string = this.isDark ? AppColors.TEXT_GREY_2ND : AppColors.TEXT_GREY;
    const lineColor: string = AppColors.COMPOSE_OUTLINE.resolve(this.isDark);

    ctx.font = AXIS_LABEL_SIZE + 'vp ' + APP_FONT_FAMILY;

    /* ---- the plot rectangle: the end axis takes the right, the two horizontal axes the ends --- */
    let widestLabel: number = 0;
    const labels: string[] = this.endAxisLabels();
    for (const label of labels) {
      widestLabel = Math.max(widestLabel, ctx.measureText(label).width);
    }
    // Pressure reserves the band for its arrows; the conditions chart reserves it for its icons.
    const hasTopAxis: boolean = this.spec.arrows.length > 0 || this.spec.topIcons.length > 0;
    const plotLeft: number = 0;
    const plotRight: number = width - widestLabel - AXIS_LABEL_PADDING * 2 - TICK_LENGTH;
    /*
     * Without a top axis the plot still needs half a label of headroom, or the TOPMOST end-axis
     * label is centred on y = 0 and half of it is cut off — which is what "25 °C" did on the
     * conditions chart, the only ported chart with no arrow row above it.
     */
    const plotTop: number = hasTopAxis ? TOP_AXIS_HEIGHT : AXIS_LABEL_SIZE / 2 + AXIS_LABEL_PADDING;
    const plotBottom: number = height - AXIS_LABEL_SIZE - AXIS_LABEL_PADDING * 2;
    if (plotRight <= plotLeft || plotBottom <= plotTop) {
      return;
    }

    const xAt = (value: number): number =>
      plotLeft + (value - this.spec.minX) / (this.spec.maxX - this.spec.minX) * (plotRight - plotLeft);
    const yAt = (value: number): number =>
      plotBottom - (value - this.spec.minY) / (this.spec.maxY - this.spec.minY) * (plotBottom - plotTop);

    /* ---- the end axis: guideline, tick and label per step ---- */
    ctx.strokeStyle = lineColor;
    ctx.fillStyle = labelColor;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    for (const value of this.axisTicks(plotBottom - plotTop)) {
      const y: number = yAt(value);
      ctx.setLineDash([GUIDELINE_DASH, GUIDELINE_DASH]);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(plotLeft, y);
      ctx.lineTo(plotRight, y);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.beginPath();
      ctx.moveTo(plotRight, y);
      ctx.lineTo(plotRight + TICK_LENGTH, y);
      ctx.stroke();
      ctx.fillText(this.formatAxisValue(value), plotRight + TICK_LENGTH + AXIS_LABEL_PADDING, y);
    }
    // The axis line itself, down the right of the plot.
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(plotRight, plotTop);
    ctx.lineTo(plotRight, plotBottom);
    ctx.stroke();

    /* ---- the bottom axis: 06:00, 12:00, 18:00 local ---- */
    ctx.beginPath();
    ctx.moveTo(plotLeft, plotBottom);
    ctx.lineTo(plotRight, plotBottom);
    ctx.stroke();
    ctx.textAlign = 'center';
    for (let hour = 6; hour <= 18; hour += 6) {
      const at: number = this.spec.minX + hour * HOUR_MS;
      const x: number = xAt(at);
      ctx.beginPath();
      ctx.moveTo(x, plotBottom);
      ctx.lineTo(x, plotBottom + TICK_LENGTH);
      ctx.stroke();
      ctx.setLineDash([GUIDELINE_DASH, GUIDELINE_DASH]);
      ctx.beginPath();
      ctx.moveTo(x, plotTop);
      ctx.lineTo(x, plotBottom);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillText(getHour(new Date(at), this.utcOffsetSeconds), x,
        plotBottom + TICK_LENGTH + AXIS_LABEL_PADDING + AXIS_LABEL_SIZE / 2);
    }

    /*
     * Vico paints its layer inside `layerBounds` and nothing outside it. That only started to
     * matter with the ephemeris chart, whose curve runs from before the day's first sample to after
     * its last — without the clip the spline crosses the end axis and draws over its labels.
     */
    ctx.save();
    ctx.beginPath();
    ctx.rect(plotLeft, plotTop - LINE_THICKNESS, plotRight - plotLeft,
      plotBottom - plotTop + LINE_THICKNESS * 2);
    ctx.clip();

    if (this.spec.bars) {
      /*
       * `BreezyBarChart`'s ColumnCartesianLayer (kt:162-173): one rounded column per point, in one
       * flat colour, thickness 500 dp — far more than a slot is wide, so Vico clamps it to the slot
       * and the columns end up touching. The slot here is one hour of the fixed 24-hour x range.
       */
      const slot: number = (plotRight - plotLeft) * HOUR_MS / (this.spec.maxX - this.spec.minX);
      ctx.fillStyle = this.spec.barColor;
      for (const point of this.spec.points) {
        const centre: number = xAt(point.x);
        const top: number = yAt(point.y);
        const height: number = plotBottom - top;
        if (height <= 0) {
          continue;
        }
        // CorneredShape.rounded(allPercent = 15) — 15 % of the shorter side, on all four corners.
        const radius: number = Math.min(slot, height) * 0.15;
        this.roundedBar(ctx, centre - slot / 2, top, slot, height, radius);
      }
    } else {
      /*
       * The second series FIRST, so the primary one draws over it.
       *
       * Two shapes: Feels like puts the actual temperature behind its own line as a flat grey
       * stroke with no area (DetailsConditions.kt:869-872), while the ephemeris chart's second
       * series is a full one — its own gradient, its own area (DetailsSunMoon.kt:182-193).
       */
      if (this.spec.points2.length > 1) {
        if (this.spec.stops2.length > 0) {
          this.drawSeries(ctx, this.spec.points2, this.spec.stops2, this.spec.areaStops2,
            plotTop, plotBottom, xAt, yAt);
        } else {
          ctx.save();
          ctx.strokeStyle = this.spec.secondaryColor;
          ctx.lineWidth = LINE_THICKNESS;
          ctx.lineJoin = 'round';
          ctx.lineCap = 'round';
          ctx.stroke(this.linePath(this.spec.points2, xAt, yAt));
          ctx.restore();
        }
      }
      this.drawSeries(ctx, this.spec.points, this.spec.stops, this.spec.areaStops,
        plotTop, plotBottom, xAt, yAt);
    }
    ctx.restore();

    /* ---- the trendHorizontalLine, gated on screen 3c ---- */
    if (this.keyLinesEnabled) {
      for (const keyLine of this.spec.keyLines) {
        if (keyLine.y < this.spec.minY || keyLine.y > this.spec.maxY) {
          continue;
        }
        const y: number = yAt(keyLine.y);
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(plotLeft, y);
        ctx.lineTo(plotRight, y);
        ctx.stroke();
        // Position.Vertical.Bottom — the label hangs under its line, at the start.
        ctx.fillStyle = labelColor;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'top';
        ctx.fillText(keyLine.label, plotLeft + AXIS_LABEL_PADDING, y + AXIS_LABEL_PADDING);
      }
    }

    /* ---- the marker: a guideline at the touched hour, with a dot on the line ---- */
    this.plotLeftPx = plotLeft;
    this.plotRightPx = plotRight;
    if (this.activeHourMs >= 0) {
      for (const point of this.spec.points) {
        if (point.x !== this.activeHourMs) {
          continue;
        }
        const x: number = xAt(point.x);
        // rememberDefaultCartesianMarker's `guideline` is a plain rule in the label colour.
        ctx.strokeStyle = labelColor;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x, plotTop);
        ctx.lineTo(x, plotBottom);
        ctx.stroke();
        ctx.fillStyle = labelColor;
        ctx.beginPath();
        ctx.arc(x, yAt(point.y), LINE_THICKNESS, 0, Math.PI * 2);
        ctx.fill();
        break;
      }
    }

    /* ---- the top axis: Pressure's trend arrows, or the conditions chart's weather icons ---- */
    if (this.spec.arrows.length > 0) {
      this.drawArrows(ctx, plotLeft, plotRight, xAt, labelColor);
    }
    this.publishTopIcons(plotLeft, plotRight, xAt);
  }

  /**
   * The surviving top-axis icons and where they land, handed to the overlay above the canvas.
   *
   * The thinning is `TimeTopAxisItemPlacer`'s, the same rule `drawArrows` applies — see the note
   * there. Only reassigns when the result actually changed: this runs inside the draw, and a
   * @Local written on every repaint would drive the repaint.
   */
  private publishTopIcons(plotLeft: number, plotRight: number,
    xAt: (value: number) => number): void {
    const slots: TopIconSlot[] = [];
    if (this.spec.topIcons.length > 0) {
      const hoursDisplayed: number = Math.round((this.spec.maxX - this.spec.minX) / HOUR_MS);
      const labelWidth: number = TOP_ICON_SIZE + AXIS_LABEL_PADDING * 2;
      const maxLabels: number = Math.floor((plotRight - plotLeft) / labelWidth);
      if (maxLabels > 0) {
        const skip: number = Math.max(1, Math.ceil(hoursDisplayed / maxLabels));
        const edge: number = Math.max(1, skip - 1) * HOUR_MS;
        const firstAllowed: number = this.spec.minX + edge;
        const lastAllowed: number = this.spec.maxX - edge;
        let previous: number = 0;
        for (let i = 0; i < this.spec.topIcons.length; i++) {
          const at: number = this.spec.topIcons[i].x;
          if (at < firstAllowed || at > lastAllowed || at < previous + skip * HOUR_MS) {
            continue;
          }
          previous = at;
          const slot = new TopIconSlot();
          slot.x = xAt(at);
          slot.kind = this.spec.topIconKinds[i];
          slot.daylight = this.spec.topIconDaylight[i];
          slot.key = at.toString() + ':' + slot.kind.toString() + ':' + (slot.daylight ? 'd' : 'n');
          slots.push(slot);
        }
      }
    }
    if (sameSlots(this.iconSlots, slots)) {
      return;
    }
    this.iconSlots = slots;
  }

  /**
   * The polyline through a series, or the cubic spline through it when the spec asks for one.
   *
   * `PointConnector.cubic(curvature)` puts each segment's control points on the horizontal at the
   * two ends, `curvature × dx` in from each — the classic monotone-ish connector Vico uses. Only
   * the ephemeris chart sets it; every other chart is straight segments, which is Vico's default.
   */
  private linePath(points: ChartPoint[], xAt: (value: number) => number,
    yAt: (value: number) => number): Path2D {
    const path = new Path2D();
    if (points.length === 0) {
      return path;
    }
    path.moveTo(xAt(points[0].x), yAt(points[0].y));
    for (let i = 1; i < points.length; i++) {
      const x0: number = xAt(points[i - 1].x);
      const y0: number = yAt(points[i - 1].y);
      const x1: number = xAt(points[i].x);
      const y1: number = yAt(points[i].y);
      if (this.spec.curved) {
        const grip: number = (x1 - x0) * CUBIC_CURVATURE;
        path.bezierCurveTo(x0 + grip, y0, x1 - grip, y1, x1, y1);
      } else {
        path.lineTo(x1, y1);
      }
    }
    return path;
  }

  /** The vertical shader of a value scale — `getShader` (BreezyLineChart.kt:315-325). */
  private gradientFor(ctx: CanvasRenderingContext2D, stops: ChartStop[], plotTop: number,
    plotBottom: number): CanvasGradient {
    const gradient = ctx.createLinearGradient(0, plotTop, 0, plotBottom);
    const sorted: ChartStop[] = this.sortedStops(stops);
    for (const stop of sorted) {
      // kt:323 — a stop's OFFSET is where its value falls in the axis, flipped because a canvas
      // gradient runs top-down while the value axis runs bottom-up.
      const offset: number =
        1 - (stop.value - this.spec.minY) / (this.spec.maxY - this.spec.minY);
      gradient.addColorStop(Math.max(0, Math.min(1, offset)), stop.color);
    }
    return gradient;
  }

  /**
   * One line series: the area at alpha 128 first (ScaleAreaFill, kt:283), then the stroke painted
   * with the SAME kind of shader (ScaleLineFill, kt:251-268).
   *
   * `areaStops` is the area's own scale when it has one — the ephemeris chart's area fades to
   * transparent below the horizon where its line only fades to 50 % — and falls back to the line's.
   */
  private drawSeries(ctx: CanvasRenderingContext2D, points: ChartPoint[], stops: ChartStop[],
    areaStops: ChartStop[], plotTop: number, plotBottom: number,
    xAt: (value: number) => number, yAt: (value: number) => number): void {
    if (points.length < 2) {
      return;
    }
    const path: Path2D = this.linePath(points, xAt, yAt);
    const area = new Path2D();
    area.addPath(path);
    area.lineTo(xAt(points[points.length - 1].x), plotBottom);
    area.lineTo(xAt(points[0].x), plotBottom);
    area.closePath();

    ctx.save();
    ctx.globalAlpha = 128 / 255;  // kt:283
    ctx.fillStyle =
      this.gradientFor(ctx, areaStops.length > 0 ? areaStops : stops, plotTop, plotBottom);
    ctx.fill(area);
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = this.gradientFor(ctx, stops, plotTop, plotBottom);
    ctx.lineWidth = LINE_THICKNESS;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.stroke(path);
    ctx.restore();
  }

  /** One `CorneredShape.rounded` column, filled with the layer's single colour. */
  private roundedBar(ctx: CanvasRenderingContext2D, left: number, top: number, width: number,
    height: number, radius: number): void {
    const r: number = Math.max(0, Math.min(radius, Math.min(width, height) / 2));
    const right: number = left + width;
    const bottom: number = top + height;
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
    ctx.fill();
  }

  /**
   * TimeTopAxisItemPlacer.getLabelValues (AxisItemPlacer.kt:77-108).
   *
   * How many arrows fit is a function of the plot width, so it cannot be decided in the data layer:
   * divide the plot by the label width, divide the day by that, and step through the hours that
   * survive. On this device that gives seven arrows over a 24-hour chart, which is what the
   * reference capture shows.
   */
  private drawArrows(ctx: CanvasRenderingContext2D, plotLeft: number, plotRight: number,
    xAt: (value: number) => number, color: string): void {
    const hoursDisplayed: number = Math.round((this.spec.maxX - this.spec.minX) / HOUR_MS);
    const labelWidth: number = ARROW_SIZE + AXIS_LABEL_PADDING * 2;
    const maxLabels: number = Math.floor((plotRight - plotLeft) / labelWidth);
    if (maxLabels <= 0) {
      return;
    }
    const skip: number = Math.max(1, Math.ceil(hoursDisplayed / maxLabels));
    const edge: number = Math.max(1, skip - 1) * HOUR_MS;
    const firstAllowed: number = this.spec.minX + edge;
    const lastAllowed: number = this.spec.maxX - edge;

    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    ctx.lineWidth = 2;
    let previous: number = 0;
    for (let i = 0; i < this.spec.arrows.length; i++) {
      const at: number = this.spec.arrows[i].x;
      if (at < firstAllowed || at > lastAllowed) {
        continue;
      }
      if (at < previous + skip * HOUR_MS) {
        continue;
      }
      previous = at;
      this.drawArrow(ctx, xAt(at), TOP_AXIS_HEIGHT / 2, this.spec.arrowKinds[i]);
    }
  }

  /** The three drawables the Kotlin picks between: ic_arrow_upward_alt / _downward_alt / ic_equal. */
  private drawArrow(ctx: CanvasRenderingContext2D, x: number, y: number, kind: number): void {
    const half: number = ARROW_SIZE / 2;
    ctx.beginPath();
    if (kind === 0) {
      ctx.moveTo(x - half * 0.6, y - 3);
      ctx.lineTo(x + half * 0.6, y - 3);
      ctx.moveTo(x - half * 0.6, y + 3);
      ctx.lineTo(x + half * 0.6, y + 3);
      ctx.stroke();
      return;
    }
    const sign: number = kind > 0 ? -1 : 1;
    ctx.moveTo(x, y - half * sign);
    ctx.lineTo(x, y + half * sign);
    ctx.moveTo(x, y + half * sign);
    ctx.lineTo(x - half * 0.5, y + half * sign - half * 0.5 * sign);
    ctx.moveTo(x, y + half * sign);
    ctx.lineTo(x + half * 0.5, y + half * sign - half * 0.5 * sign);
    ctx.stroke();
  }

  /**
   * `VerticalAxis.ItemPlacer.step` treats the tag's chartStep as a MINIMUM, not a fixed interval:
   * it takes the smallest multiple of it whose labels still fit the axis.
   *
   * Without this, metres per second (chartStep 0.5) would draw thirty gridlines over a 15 m/s
   * range. Pressure at 15 hPa and UV at 1 already fit, so they are unaffected — which is why the
   * pressure chart still comes out at exactly the reference's 1,050 / 1,035 / … spacing.
   */
  /**
   * The values the right-hand labels sit on.
   *
   * `SpecificVerticalAxisItemPlacer` wins when the spec supplies one — the air-quality chart's
   * labels are its band edges, which are not evenly spaced. Otherwise it is the uniform, thinned
   * step every other chart uses.
   */
  private axisTicks(plotHeight: number): number[] {
    if (this.spec.axisValues.length > 0) {
      return this.spec.axisValues;
    }
    const out: number[] = [];
    const step: number = this.axisStep(plotHeight);
    for (let value = this.spec.minY; value <= this.spec.maxY + 1e-6; value += step) {
      out.push(value);
    }
    return out;
  }

  private axisStep(plotHeight: number): number {
    const span: number = this.spec.maxY - this.spec.minY;
    if (span <= 0 || this.spec.step <= 0) {
      return this.spec.step;
    }
    const minSpacing: number = AXIS_LABEL_SIZE * 2.2;
    for (let multiple = 1; multiple <= 64; multiple++) {
      const step: number = this.spec.step * multiple;
      if (step / span * plotHeight >= minSpacing) {
        return step;
      }
    }
    return span;
  }

  private endAxisLabels(): string[] {
    const out: string[] = [];
    if (this.spec.axisValues.length > 0) {
      for (const value of this.spec.axisValues) {
        out.push(this.formatAxisValue(value));
      }
      return out;
    }
    // Measured against the UNTHINNED step so the widest possible label still reserves its gutter.
    for (let value = this.spec.minY; value <= this.spec.maxY + 1e-6; value += this.spec.step) {
      out.push(this.formatAxisValue(value));
    }
    return out;
  }

  /** `endAxisValueFormatter` — the value in the display unit with its unit appended. */
  private formatAxisValue(value: number): string {
    const rounded: number = this.spec.decimals > 0
      ? Math.round(value * 10) / 10
      : Math.round(value);
    return groupThousands(rounded, this.spec.decimals) + this.spec.unitLabel;
  }

  private sortedStops(stops: ChartStop[]): ChartStop[] {
    const out: ChartStop[] = [];
    for (const stop of stops) {
      out.push(stop);
    }
    // A canvas gradient needs its stops in increasing OFFSET order, which is decreasing value.
    out.sort((a: ChartStop, b: ChartStop) => b.value - a.value);
    return out;
  }
}

/**
 * "1,050" — the reference's axis labels are grouped, which is the NumberFormatter's doing on an
 * English locale. Written out because ArkTS has no toLocaleString with a guaranteed grouping.
 */
function groupThousands(value: number, decimals: number): string {
  const negative: boolean = value < 0;
  const magnitude: number = Math.abs(value);
  const whole: number = Math.floor(magnitude);
  const fraction: number = magnitude - whole;
  let text: string = whole.toString();
  let grouped: string = '';
  while (text.length > 3) {
    grouped = ',' + text.substring(text.length - 3) + grouped;
    text = text.substring(0, text.length - 3);
  }
  grouped = text + grouped;
  if (decimals > 0) {
    grouped = grouped + '.' + Math.round(fraction * 10).toString();
  }
  return negative ? '-' + grouped : grouped;
}
