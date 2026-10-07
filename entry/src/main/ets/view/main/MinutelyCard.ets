/*
 * The precipitation nowcast card.
 *
 * Port of PrecipitationNowcastViewHolder.kt:79-254 plus the title/description rules in
 * Weather.kt:46-92. MainAdapter.kt:110-115 only adds this card when the weather actually has
 * minutely precipitation and at least three buckets, which MainScreen mirrors.
 *
 * The Android build draws the chart with Vico (a ColumnCartesianLayer plus HorizontalLine
 * decorations). There is no Vico on ArkUI, so the same picture is drawn directly on a Canvas:
 *   - one rounded column per bucket, rainy-theme colour, corner radius 15% of the column
 *     (kt:189-208)
 *   - the light/medium/heavy threshold lines with their labels, subject to the same
 *     "don't show some thresholds when max precipitation is very high" rule (kt:113-136)
 *   - three time labels on the bottom axis: start, midpoint, end (kt:107, 209-223)
 *
 * The MARKER (kt:163-183) is here too: touch or drag the chart and the bucket under the finger gets
 * a vertical guideline and a pill label reading "9:05 AM-9:10 AM: Light". Vico draws it from a
 * `DefaultCartesianMarker`; there is no Vico here, so it is the same three primitives as the rest of
 * the chart — a line, a rounded rect with a shadow, and centred text.
 */

import { Dimens } from '../../theme/Dimens';
import { Minutely } from '../../model/Weather';
import { canvasFont } from '../trend/CanvasText';
import { getHour } from '../../common/Formatter';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** Precipitation.kt:42-45 — the hourly intensity thresholds, in mm/h. */
const PRECIPITATION_HOURLY_LIGHT: number = 5;
const PRECIPITATION_HOURLY_MEDIUM: number = 10;
const PRECIPITATION_HOURLY_HEAVY: number = 15;

/**
 * `nowcasting_chart_height` (dimens.xml) — the WHOLE chart box, not just the plot.
 *
 * The layout is not a stack. The chart is constrained `Top_toTopOf="nowcasting_block_subtitle"`
 * (container_main_precipitation_nowcast_card.xml), so its 150 dp box STARTS at the subtitle's top
 * and the subtitle sits over its first rows; the axis labels and a `large_margin` bottom padding are
 * inside those 150 dp too.
 *
 * Both ports used to stack title, subtitle, a 160 dp plot and a 24 dp axis strip one under the
 * other, which made the card 261 vp against the reference's 193 — measured off ref_main_cardorder.png
 * and ref_screen3_mainscreen.png. The card is the single tallest thing on the page, so 68 vp of it
 * pushed everything below the fold sooner than Android does.
 */
const CHART_BOX_HEIGHT: number = 150;
/** The chart's own bottom padding, inside the box (layout `paddingBottom="@dimen/large_margin"`). */
const CHART_BOTTOM_PADDING: number = 20;
const AXIS_LABEL_HEIGHT: number = 24;
/**
 * The band at the top of the box the SUBTITLE occupies, since the chart starts at the subtitle's
 * top. Content text plus the 2 dp the layout puts above it.
 */
const CHART_TOP_PADDING: number = Dimens.CONTENT_TEXT_SIZE + 8;
/** The plot proper — what is left of the box once the subtitle band, axis and padding are out. */
const CHART_HEIGHT: number = CHART_BOX_HEIGHT - AXIS_LABEL_HEIGHT - CHART_BOTTOM_PADDING;

/** `TextComponent.MinWidth.fixed(40f)` — the marker pill never narrower than this (kt:179). */
const MARKER_MIN_WIDTH: number = 40;
/** LABEL_BACKGROUND_SHADOW_RADIUS_DP / _DY_DP (kt:297-298). */
const MARKER_SHADOW_RADIUS: number = 4;
const MARKER_SHADOW_DY: number = 2;

class ThresholdLine {
  readonly value: number;
  readonly label: string;

  constructor(value: number, label: string) {
    this.value = value;
    this.label = label;
  }
}

@ComponentV2
export struct MinutelyCard {
  @Param minutely: Minutely[] = [];
  /** The location's UTC offset — the time labels print in ITS zone, as Android does. */
  @Param utcOffsetSeconds: number = 0;
  @Param cardBackground: string = '#FFFCFCFF';
  @Param onSurfaceInverse: string = '#FF191C1E';
  @Param bodyTextColor: string = '#FF666666';
  /** colorOutline — the axis and threshold lines (kt:148). */
  @Param lineColor: string = '#10000000';
  /** colorTextGrey / colorTextGrey2nd (kt:149-156). */
  @Param labelColor: string = '#FF4D4D4D';
  /** getThemeColors(WEATHER_KIND_RAINY, ...)[0] — the column fill (kt:193-202). */
  @Param columnColor: string = '#FF4A87D6';
  /** `colorPrimary` / `colorOnPrimary` — the marker pill and its text (kt:165-167). */
  @Param markerBackground: string = '#FF00639B';
  @Param markerTextColor: string = '#FFFFFFFF';
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  @Local private chartWidth: number = 0;
  /** Which bucket the finger is on, or -1. The marker exists only while a touch is down. */
  @Local private markerIndex: number = -1;

  @Monitor('redrawKey', 'chartWidth', 'columnColor', 'lineColor', 'labelColor', 'markerIndex')
  onRedrawRequested(monitor: IMonitor): void {
    if (this.ready) {
      this.draw();
    }
  }

  /** Weather.kt:46-64. `dbz > 0` becomes `precipitationIntensity > 0` — see Minutely. */
  private title(): string {
    if (this.minutely.length === 0) {
      return 'Precipitation'; // strings.xml:76
    }
    const startsWet: boolean = this.minutely[0].precipitationIntensity > 0;
    const endsWet: boolean = this.minutely[this.minutely.length - 1].precipitationIntensity > 0;
    if (!startsWet) {
      return 'Precipitation soon'; // strings.xml:903
    }
    return endsWet
      ? 'Precipitation' // strings.xml:906 notification_precipitation_continuing
      : 'Precipitation stopping soon'; // strings.xml:909
  }

  /** Weather.kt:66-92 — the description names the time the precipitation starts or stops. */
  private subtitle(): string {
    if (this.minutely.length === 0) {
      return 'No precipitation'; // strings.xml:98
    }
    const startsWet: boolean = this.minutely[0].precipitationIntensity > 0;
    const endsWet: boolean = this.minutely[this.minutely.length - 1].precipitationIntensity > 0;

    if (!startsWet) {
      for (let i = 0; i < this.minutely.length; i++) {
        if (this.minutely[i].precipitationIntensity > 0) {
          // strings.xml:905
          return 'Expected to start at ' + getHour(this.minutely[i].date, this.utcOffsetSeconds);
        }
      }
      return 'No precipitation';
    }

    let lastWet: Minutely | null = null;
    for (let i = 0; i < this.minutely.length; i++) {
      if (this.minutely[i].precipitationIntensity > 0) {
        lastWet = this.minutely[i];
      }
    }
    if (lastWet === null) {
      return 'No precipitation';
    }
    return endsWet
      // strings.xml:908
      ? 'Expected to continue until at least ' + getHour(lastWet.endingDate, this.utcOffsetSeconds)
      // strings.xml:911
      : 'Expected to stop at ' + getHour(lastWet.endingDate, this.utcOffsetSeconds);
  }

  private peakIntensity(): number {
    let peak: number = 0;
    for (let i = 0; i < this.minutely.length; i++) {
      const value: number = this.minutely[i].precipitationIntensity;
      if (value > peak) {
        peak = value;
      }
    }
    return peak;
  }

  /** kt:109-112 — the scale never drops below the heavy threshold. */
  private maxY(): number {
    const peak: number = this.peakIntensity();
    return peak > PRECIPITATION_HOURLY_HEAVY ? peak : PRECIPITATION_HOURLY_HEAVY;
  }

  /**
   * kt:113-136 — which threshold lines to draw:
   *   below heavy               all three
   *   heavy .. 2 × heavy        light and heavy
   *   above 2 × heavy           heavy only
   */
  private thresholds(): ThresholdLine[] {
    const max: number = this.maxY();
    const lines: ThresholdLine[] = [];
    if (max < PRECIPITATION_HOURLY_HEAVY * 2) {
      lines.push(new ThresholdLine(PRECIPITATION_HOURLY_LIGHT, 'Light')); // strings.xml:95
    }
    if (max <= PRECIPITATION_HOURLY_HEAVY) {
      lines.push(new ThresholdLine(PRECIPITATION_HOURLY_MEDIUM, 'Medium')); // strings.xml:96
    }
    lines.push(new ThresholdLine(PRECIPITATION_HOURLY_HEAVY, 'Heavy')); // strings.xml:97
    return lines;
  }

  build() {
    // Outer wrapper carries the card's 8dp margin. Putting .margin() on the .width('100%') card
    // itself makes it 100% + 16vp wide and pushes the margin off-screen — the same trap
    // TrendCard documents.
    Column() {
      this.card()
    }
    .width('100%')
    .padding(Dimens.SMALL_MARGIN)
  }

  @Builder
  card() {
    Column() {
      // container_main_precipitation_nowcast_card — title then subtitle, both start-aligned.
      Text(this.title())
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontColor(this.onSurfaceInverse)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      /*
       * The chart's box starts at the SUBTITLE's top and the subtitle is drawn over it — the
       * layout's `Top_toTopOf="nowcasting_block_subtitle"`. A Stack reproduces that; stacking them
       * instead is what made the card 68 vp too tall.
       */
      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.ctx)
          .width('100%')
          .height(CHART_BOX_HEIGHT)
          .onReady(() => {
            this.ready = true;
            this.draw();
          })
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            const width: number = Number(newValue.width);
            if (width > 0 && Math.abs(width - this.chartWidth) > 0.5) {
              this.chartWidth = width;
            }
          })
          /*
           * The marker follows the finger and disappears with it, which is what Vico's does — its
           * marker is bound to the chart's touch handler, not to a selection that persists.
           *
           * Raw onTouch rather than a gesture: this Canvas lives inside a vertical Scroll and a
           * horizontal Swiper, and a PanGesture here would have to win an arena against both. A
           * touch handler reads the position without claiming the gesture, so a drag that started
           * as a scroll still scrolls — the marker simply tracks it, and Android behaves the same
           * way because Vico's chart is not scrollable on this card.
           */
          .onTouch((event: TouchEvent) => {
            const type: TouchType = event.type;
            if (type === TouchType.Up || type === TouchType.Cancel) {
              this.markerIndex = -1;
              return;
            }
            const x: number = event.touches[0].x;
            this.markerIndex = this.bucketAt(x);
          })

        Text(this.subtitle())
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(this.bodyTextColor)
          .width('100%')
          .margin({ top: 2 })
      }
      .width('100%')
    }
    .width('100%')
    /*
     * The layout insets the title by `large_margin` and gives the chart its own bottom padding
     * inside the 150 dp box, so the card itself has NO bottom padding — that is where the last of
     * the 68 vp went.
     */
    .padding({
      left: Dimens.LARGE_MARGIN,
      right: Dimens.LARGE_MARGIN,
      top: Dimens.LARGE_MARGIN,
      bottom: 0
    })
    .backgroundColor(this.cardBackground)
    .borderRadius(Dimens.CARD_CORNER_RADIUS)
  }

  private draw(): void {
    const ctx = this.ctx;
    const width: number = this.chartWidth;
    if (width <= 0) {
      return;
    }
    ctx.clearRect(0, 0, width, CHART_BOX_HEIGHT);
    if (this.minutely.length === 0) {
      return;
    }

    const baseline: number = CHART_HEIGHT;
    const usable: number = CHART_HEIGHT - CHART_TOP_PADDING;
    const max: number = this.maxY();

    // Threshold lines first, so the columns sit on top of them.
    const thresholds: ThresholdLine[] = this.thresholds();
    ctx.font = canvasFont(Dimens.SUBTITLE_TEXT_SIZE);
    for (let i = 0; i < thresholds.length; i++) {
      const line: ThresholdLine = thresholds[i];
      const y: number = baseline - usable * line.value / max;

      ctx.beginPath();
      ctx.lineWidth = 1;
      ctx.strokeStyle = this.lineColor;
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();

      // Position.Vertical.Bottom (kt:228) — the label hangs under its line, at the start edge.
      ctx.fillStyle = this.labelColor;
      ctx.textAlign = 'left';
      ctx.fillText(line.label, 0, y + Dimens.SUBTITLE_TEXT_SIZE);
    }

    // Columns. thicknessDp is 500 in the Kotlin, i.e. "as wide as the slot allows", so each
    // bucket simply fills its share of the width with a small gap.
    const slot: number = width / this.minutely.length;
    const columnWidth: number = Math.max(2, slot * 0.8);
    ctx.fillStyle = this.columnColor;
    for (let i = 0; i < this.minutely.length; i++) {
      const intensity: number = this.minutely[i].precipitationIntensity;
      if (intensity <= 0) {
        continue;
      }
      const height: number = usable * intensity / max;
      const left: number = slot * i + (slot - columnWidth) / 2;
      // CorneredShape.rounded(allPercent = 15) — 15% of the column width.
      const radius: number = Math.min(columnWidth * 0.15, height / 2);
      ctx.beginPath();
      this.roundRectPath(left, baseline - height, left + columnWidth, baseline, radius);
      ctx.fill();
    }

    // Bottom axis line and the three time labels (start, midpoint, end).
    ctx.beginPath();
    ctx.lineWidth = 1;
    ctx.strokeStyle = this.lineColor;
    ctx.moveTo(0, baseline);
    ctx.lineTo(width, baseline);
    ctx.stroke();

    const first: Minutely = this.minutely[0];
    const last: Minutely = this.minutely[this.minutely.length - 1];
    const midMs: number = first.date.getTime() + (last.endingDate.getTime() - first.date.getTime()) / 2;

    ctx.fillStyle = this.labelColor;
    ctx.font = canvasFont(Dimens.SUBTITLE_TEXT_SIZE);
    const labelY: number = baseline + AXIS_LABEL_HEIGHT - 4;

    ctx.textAlign = 'left';
    ctx.fillText(getHour(first.date, this.utcOffsetSeconds), 0, labelY);
    ctx.textAlign = 'center';
    ctx.fillText(getHour(new Date(midMs), this.utcOffsetSeconds), width / 2, labelY);
    ctx.textAlign = 'right';
    ctx.fillText(getHour(last.endingDate, this.utcOffsetSeconds), width, labelY);

    this.drawMarker(width, baseline);
  }

  /** Which bucket a touch at `x` falls in, or -1 when the chart is empty. */
  private bucketAt(x: number): number {
    if (this.minutely.length === 0 || this.chartWidth <= 0) {
      return -1;
    }
    const slot: number = this.chartWidth / this.minutely.length;
    const index: number = Math.floor(x / slot);
    if (index < 0) {
      return 0;
    }
    return index >= this.minutely.length ? this.minutely.length - 1 : index;
  }

  /**
   * kt:137-145 — true when every bucket is exactly 0 or one of the three thresholds.
   *
   * Open-Meteo reports real accumulations, so this is normally false and the label prints a
   * quantity. It is still ported: a source that only ever reports the three levels would otherwise
   * have its label read "5 mm/h" where Android reads "Light".
   */
  private hasOnlyThresholdValues(): boolean {
    for (let i = 0; i < this.minutely.length; i++) {
      const value: number = this.minutely[i].precipitationIntensity;
      if (value !== 0 && value !== PRECIPITATION_HOURLY_LIGHT &&
        value !== PRECIPITATION_HOURLY_MEDIUM && value !== PRECIPITATION_HOURLY_HEAVY) {
        return false;
      }
    }
    return true;
  }

  /** `MarkerLabelFormatterMinutelyDecorator.format` (kt:264-294). */
  private markerLabel(index: number): string {
    const bucket: Minutely = this.minutely[index];
    const start: string = getHour(bucket.date, this.utcOffsetSeconds);
    const end: string = getHour(bucket.endingDate, this.utcOffsetSeconds);
    const value: number = bucket.precipitationIntensity;
    let quantity: string;
    if (this.hasOnlyThresholdValues()) {
      // kt:274-281 — the four exact cases, then the measured fallback.
      if (value === 0) {
        quantity = 'None'; // strings.xml precipitation_none
      } else if (value === PRECIPITATION_HOURLY_LIGHT) {
        quantity = 'Light';
      } else if (value === PRECIPITATION_HOURLY_MEDIUM) {
        quantity = 'Medium';
      } else if (value === PRECIPITATION_HOURLY_HEAVY) {
        quantity = 'Heavy';
      } else {
        quantity = this.formatIntensity(value);
      }
    } else {
      quantity = this.formatIntensity(value);
    }
    // `colon_separator` is ": " in English (kt:291).
    return start + '-' + end + ': ' + quantity;
  }

  /** `formatMeasureIntensity` — the value at one decimal, with the unit. */
  private formatIntensity(value: number): string {
    return value.toFixed(1) + ' mm/h';
  }

  /**
   * `DefaultCartesianMarker` (kt:163-183): a guideline down the marked bucket and a pill label
   * above it.
   *
   * The pill is `CorneredShape.Pill` filled `colorPrimary`, with `normal_margin` horizontal and
   * `small_margin` vertical padding, a 40 dp minimum width, and a 4 dp shadow offset 2 dp down
   * (kt:169-172, 174-179). It is clamped inside the chart rather than allowed to run off the edge,
   * which is what Vico does with a marker near either end.
   */
  private drawMarker(width: number, baseline: number): void {
    const index: number = this.markerIndex;
    if (index < 0 || index >= this.minutely.length) {
      return;
    }
    const ctx = this.ctx;
    const slot: number = width / this.minutely.length;
    const centre: number = slot * index + slot / 2;

    // The guideline, in the axis colour (kt:181's LineComponent takes `labelColor`).
    ctx.beginPath();
    ctx.lineWidth = 1;
    ctx.strokeStyle = this.labelColor;
    ctx.moveTo(centre, CHART_TOP_PADDING);
    ctx.lineTo(centre, baseline);
    ctx.stroke();

    const label: string = this.markerLabel(index);
    ctx.font = canvasFont(Dimens.SUBTITLE_TEXT_SIZE);
    const textWidth: number = ctx.measureText(label).width;
    const pillWidth: number =
      Math.max(MARKER_MIN_WIDTH, textWidth + Dimens.NORMAL_MARGIN * 2);
    const pillHeight: number = Dimens.SUBTITLE_TEXT_SIZE + Dimens.SMALL_MARGIN * 2;
    let left: number = centre - pillWidth / 2;
    if (left < 0) {
      left = 0;
    } else if (left + pillWidth > width) {
      left = width - pillWidth;
    }
    const top: number = 0;

    ctx.save();
    ctx.shadowBlur = MARKER_SHADOW_RADIUS;
    ctx.shadowOffsetY = MARKER_SHADOW_DY;
    ctx.shadowColor = '#40000000';
    ctx.fillStyle = this.markerBackground;
    ctx.beginPath();
    // A pill: the radius is half the height, so the ends are semicircles.
    this.roundRectPath(left, top, left + pillWidth, top + pillHeight, pillHeight / 2);
    ctx.fill();
    ctx.restore();

    ctx.fillStyle = this.markerTextColor;
    ctx.textAlign = 'center';
    ctx.fillText(label, left + pillWidth / 2, top + pillHeight - Dimens.SMALL_MARGIN - 1);
    ctx.textAlign = 'left';
  }

  private roundRectPath(left: number, top: number, right: number, bottom: number, radius: number): void {
    const ctx = this.ctx;
    const r: number = Math.max(0, Math.min(radius, (bottom - top) / 2));
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
