/*
 * Builds the per-item chart data for each trend tab — the ArkTS equivalent of the
 * DailyHourly* adapter family under ui/main/adapters/trend/.
 *
 * The reference implementation is DailyTemperatureAdapter.kt:
 *   - kt:195-237  a "doubled" series: real values at even indices, the midpoint between two
 *                 neighbours at odd indices, so each column can draw an entering and a leaving
 *                 segment that meets its neighbour exactly halfway.
 *   - kt:177-192  buildTemperatureArrayForItem slices [previous, current, next] out of it.
 *   - kt:238-259  highest/lowest span the whole series *and* the monthly normals.
 *   - kt:278-311  bindBackgroundForHost turns the normals into the two key lines.
 *
 * Chart widget per tab (verified by which view each adapter instantiates):
 *   PolylineAndHistogramView — every hourly tab, and daily Conditions / UV / Sunshine / Feels like
 *   DoubleHistogramView      — daily Wind (DailyWindAdapter.kt:51) and
 *                              daily Precipitation (DailyPrecipitationAdapter.kt:56)
 *
 * Instantiating PolylineAndHistogramView does NOT imply a polyline. Six tabs pass all six
 * polyline arguments as null and render a histogram only — daily UV (DailyUVAdapter.kt:69-74) and
 * Sunshine (DailySunshineAdapter.kt:80-91); hourly Wind (HourlyWindAdapter.kt:75-82), UV
 * (HourlyUVAdapter.kt:68-74), Precipitation (HourlyPrecipitationAdapter.kt:81-89) and Cloud cover
 * (HourlyCloudCoverAdapter.kt:64-75). Those bars are opaque (setHistogramAlpha(1f)) and labelled
 * below the bar in colorTitleText, unlike the translucent precipitation-probability histogram that
 * sits behind the temperature curves. Here that is expressed by leaving highest/lowestValue null.
 */

import { Daily, HalfDay, Hourly, LocationModel, Weather } from '../../model/Weather';
import { TrendTab, TrendTabId } from '../../model/TrendTab';
import { ChartData, PolylinePoints } from './ChartData';
import { DoubleHistogramData } from './DoubleHistogramCanvas';
import { getWeatherIcon, getWindArrowIcon, getWindArrowRotation } from '../../common/WeatherIcons';
import {
  AppColors,
  aqiLevelColor,
  cloudCoverColor,
  halfDayPrecipitationColor,
  hourlyPrecipitationColor,
  uvColor,
  windColor
} from '../../theme/AppColors';
import { formatDistance, formatPrecipitation, formatPressure, formatSpeed } from '../../common/Units';
import {
  formatPercent,
  formatTemperatureNarrow,
  getFormattedShortDayAndMonth,
  getHour,
  getHourIn24Format,
  getWeek
} from '../../common/Formatter';

export enum ChartKind {
  POLYLINE,
  DOUBLE_HISTOGRAM
}

/** TrendRecyclerView.KeyLine (TrendRecyclerView.kt:58-68). */
export class KeyLine {
  value: number = 0;
  contentLeft: string = '';
  contentRight: string = '';
  /** ContentPosition.ABOVE_LINE when true, BELOW_LINE otherwise. */
  above: boolean = true;
}

/**
 * Observable on purpose: a tab switch REBINDS the live columns instead of rebuilding them.
 *
 * The trace history that forced this: LazyForEach's reload destroys and recreates every visible
 * column, and one column costs ~16 ms to measure (canvas mount included — and the number is the
 * same with the fontFamily removed, so it is structural, not the font). Six columns per list per
 * tab tap was the 150 ms+ "chip feels delayed" report. RecyclerView never pays this: it rebinds
 * recycled views. @ObservedV2 + @Trace is the ArkUI equivalent — MainScreen copies fresh values
 * into the SAME instances and the bound Texts/Images/Canvases update in place, no nodes touched.
 */
@ObservedV2
export class TrendItemModel {
  @Trace key: string = '';
  /** Week name (daily) or hour (hourly). */
  @Trace topLabel: string = '';
  /** Date line, daily only. */
  @Trace subLabel: string | null = null;
  /** AbsDailyTrendAdapter.kt:76-80 / AbsHourlyTrendAdapter.kt:56-59 — today and future use the accent colour. */
  @Trace accent: boolean = false;
  /**
   * False on the tabs whose adapter never sets an icon — daily UV and Sunshine, hourly UV and
   * Cloud cover (and air quality, which this port omits). Those columns are label + chart only.
   */
  @Trace hasIcons: boolean = true;
  @Trace dayIcon: Resource | null = null;
  @Trace nightIcon: Resource | null = null;
  /** Wind tabs replace the weather icon with a tinted, rotated direction arrow. */
  @Trace dayIconIsArrow: boolean = false;
  @Trace nightIconIsArrow: boolean = false;
  @Trace dayIconTint: string = '#FF000000';
  @Trace nightIconTint: string = '#FF000000';
  @Trace dayIconRotation: number = 0;
  @Trace nightIconRotation: number = 0;
  @Trace chartKind: ChartKind = ChartKind.POLYLINE;
  @Trace polyline: ChartData = new ChartData();
  @Trace doubleHistogram: DoubleHistogramData = new DoubleHistogramData();
}

/**
 * Copies every CHANGED field of `source` into `target` — the rebind step.
 *
 * Every field here is @Trace, so an assignment is not a store: it fires V2 change notification,
 * which walks the observers and allocates. Sixteen of them per item, twenty-four items per hourly
 * card, two cards per page and a page per location is tens of thousands of notifications for one
 * re-sync, and the app froze in exactly that: `copyTrendItem` -> set -> fireChange -> runIdleTasks
 * -> PartialGC, THREAD_BLOCK_6S at 589 MB (2026-08-08 22:40).
 *
 * The guards matter because most re-syncs change almost nothing. The series cache key carries the
 * title colour, which comes from the CURRENT location's daylight — so selecting a night location
 * from a daytime one invalidates every page's series, and re-syncs thirteen locations whose values
 * are identical apart from a tint. Guarded, those become no writes at all.
 *
 * `polyline` and `doubleHistogram` are compared by reference on purpose: the builder allocates a
 * fresh one each time, so they are genuinely new objects whenever a rebuild happened, and a deep
 * comparison would cost more than the notification it saves.
 *
 * NOTE: the same guarding was tried on LocationRowModel.apply for screen 2 and measured as making
 * no difference, so it was reverted there. That was thirteen rows of a handful of fields; this is
 * three orders of magnitude more writes, and the fault log puts the stall inside this function.
 */
export function copyTrendItem(target: TrendItemModel, source: TrendItemModel): void {
  if (target.key !== source.key) {
    target.key = source.key;
  }
  if (target.topLabel !== source.topLabel) {
    target.topLabel = source.topLabel;
  }
  if (target.subLabel !== source.subLabel) {
    target.subLabel = source.subLabel;
  }
  if (target.accent !== source.accent) {
    target.accent = source.accent;
  }
  if (target.hasIcons !== source.hasIcons) {
    target.hasIcons = source.hasIcons;
  }
  if (target.dayIcon !== source.dayIcon) {
    target.dayIcon = source.dayIcon;
  }
  if (target.nightIcon !== source.nightIcon) {
    target.nightIcon = source.nightIcon;
  }
  if (target.dayIconIsArrow !== source.dayIconIsArrow) {
    target.dayIconIsArrow = source.dayIconIsArrow;
  }
  if (target.nightIconIsArrow !== source.nightIconIsArrow) {
    target.nightIconIsArrow = source.nightIconIsArrow;
  }
  if (target.dayIconTint !== source.dayIconTint) {
    target.dayIconTint = source.dayIconTint;
  }
  if (target.nightIconTint !== source.nightIconTint) {
    target.nightIconTint = source.nightIconTint;
  }
  if (target.dayIconRotation !== source.dayIconRotation) {
    target.dayIconRotation = source.dayIconRotation;
  }
  if (target.nightIconRotation !== source.nightIconRotation) {
    target.nightIconRotation = source.nightIconRotation;
  }
  if (target.chartKind !== source.chartKind) {
    target.chartKind = source.chartKind;
  }
  if (target.polyline !== source.polyline) {
    target.polyline = source.polyline;
  }
  if (target.doubleHistogram !== source.doubleHistogram) {
    target.doubleHistogram = source.doubleHistogram;
  }
}

export class TrendSeries {
  items: TrendItemModel[] = [];
  keyLines: KeyLine[] = [];
}

/**
 * Everything a trend card needs for one tab, pulled through its series provider. The card owns
 * the selected-tab state (as Android's per-card adapter does) and calls the provider at build
 * time, so a tab tap re-renders one card — not the whole MainScreen with all three location
 * pages, which is what a shared @Local selection forced.
 */
export class SeriesBundle {
  items: TrendItemModel[] = [];
  itemsVersion: number = 0;
  itemCountChanged: boolean = false;
  keyLines: KeyLine[] = [];
  highestValue: number | null = null;
  lowestValue: number | null = null;
}

/**
 * Rebinds `target`'s retained items from a freshly built series — same instances, new values.
 * Only a count change (a refresh with a different number of hours) grows or trims the array;
 * the caller reloads its LazyForEach only in that case.
 */
export function syncSeries(target: TrendSeries, fresh: TrendSeries): boolean {
  const countChanged: boolean = target.items.length !== fresh.items.length;
  for (let i = 0; i < fresh.items.length; i++) {
    if (i < target.items.length) {
      copyTrendItem(target.items[i], fresh.items[i]);
    } else {
      target.items.push(fresh.items[i]);
    }
  }
  if (target.items.length > fresh.items.length) {
    target.items.splice(fresh.items.length, target.items.length - fresh.items.length);
  }
  target.keyLines = fresh.keyLines;
  return countChanged;
}

/* ------------------------------------------------------------------ helpers */

/** DailyTemperatureAdapter.kt:197-237 — real values at even indices, midpoints at odd ones. */
function buildDoubledSeries(values: (number | null)[]): (number | null)[] {
  const size: number = Math.max(0, values.length * 2 - 1);
  const out: (number | null)[] = new Array<number | null>(size);
  for (let i = 0; i < size; i++) {
    out[i] = null;
  }
  for (let i = 0; i < size; i += 2) {
    out[i] = values[i / 2];
  }
  for (let i = 1; i < size; i += 2) {
    const before: number | null = out[i - 1];
    const after: number | null = out[i + 1];
    out[i] = before !== null && after !== null ? (before + after) * 0.5 : null;
  }
  return out;
}

/** DailyTemperatureAdapter.kt:177-192 */
function sliceForItem(doubled: (number | null)[], position: number): PolylinePoints {
  const centre: number = 2 * position;
  const previous: number | null = centre - 1 < 0 ? null : doubled[centre - 1];
  const next: number | null = centre + 1 >= doubled.length ? null : doubled[centre + 1];
  return new PolylinePoints(previous, doubled[centre], next);
}

/** aqiLevelColor takes a number; the histogram helpers pass a nullable value. */
function aqiLevelColorOrNull(value: number | null): string | null {
  return value === null ? null : aqiLevelColor(value);
}

/** DailyAirQualityAdapter.kt:143-162 — one key line per band boundary, label on the right. */
function aqiKeyLine(value: number, label: string, above: boolean): KeyLine {
  const line = new KeyLine();
  line.value = value;
  line.contentLeft = formatIndex(value);
  line.contentRight = label;
  line.above = above;
  return line;
}

class Bounds {
  highest: number | null = null;
  lowest: number | null = null;
}

function extend(bounds: Bounds, value: number | null): void {
  if (value === null) {
    return;
  }
  if (bounds.highest === null || value > bounds.highest) {
    bounds.highest = value;
  }
  if (bounds.lowest === null || value < bounds.lowest) {
    bounds.lowest = value;
  }
}

function halfDayTemperature(half: HalfDay | null): number | null {
  return half !== null && half.temperature !== null ? half.temperature.temperature : null;
}

function halfDayFeelsLike(half: HalfDay | null): number | null {
  return half !== null && half.temperature !== null ? half.temperature.feelsLikeTemperature : null;
}

function halfDayProbability(half: HalfDay | null): number | null {
  return half !== null && half.precipitationProbability !== null ? half.precipitationProbability.total : null;
}

/* -------------------------------------------------------------------- daily */

/** AbsDailyTrendAdapter.kt:59-75 — "Today" replaces the weekday name for today's column. */
function dailyTopLabel(daily: Daily, position: number, todayIndex: number | null, utcOffsetSeconds: number): string {
  if (todayIndex !== null && position === todayIndex) {
    return 'Today'; // strings.xml:39 daily_today_short
  }
  return getWeek(daily.date, utcOffsetSeconds);
}

/** AbsDailyTrendAdapter.kt:76 — today and anything in the future use the accent colour. */
function dailyIsAccent(daily: Daily, position: number, todayIndex: number | null): boolean {
  if (todayIndex !== null && position === todayIndex) {
    return true;
  }
  return daily.date.getTime() > new Date().getTime();
}

function buildDailyPolyline(
  weather: Weather,
  tab: TrendTab,
  highValues: (number | null)[],
  lowValues: (number | null)[],
  formatValue: (value: number) => string,
  bounds: Bounds,
  withPrecipitationHistogram: boolean,
  utcOffsetSeconds: number
): TrendItemModel[] {
  const highDoubled: (number | null)[] = buildDoubledSeries(highValues);
  const lowDoubled: (number | null)[] = buildDoubledSeries(lowValues);
  const items: TrendItemModel[] = [];

  for (let i = 0; i < weather.dailyForecast.length; i++) {
    const daily: Daily = weather.dailyForecast[i];
    const item = new TrendItemModel();
    item.key = tab.id + '-' + i.toString();
    item.topLabel = dailyTopLabel(daily, i, weather.todayIndex, utcOffsetSeconds);
    item.subLabel = getFormattedShortDayAndMonth(daily.date, utcOffsetSeconds);
    item.accent = dailyIsAccent(daily, i, weather.todayIndex);
    item.dayIcon = daily.day !== null ? getWeatherIcon(daily.day.weatherKind, true) : null;
    item.nightIcon = daily.night !== null ? getWeatherIcon(daily.night.weatherKind, false) : null;
    item.chartKind = ChartKind.POLYLINE;

    const chart = new ChartData();
    chart.highPolyline = sliceForItem(highDoubled, i);
    chart.lowPolyline = sliceForItem(lowDoubled, i);
    const highValue: number | null = highValues[i];
    const lowValue: number | null = lowValues[i];
    chart.highText = highValue !== null ? formatValue(highValue) : null;
    chart.lowText = lowValue !== null ? formatValue(lowValue) : null;
    chart.highestValue = bounds.highest;
    chart.lowestValue = bounds.lowest;

    if (withPrecipitationHistogram) {
      // DailyTemperatureAdapter.kt:116-141 — the larger of the two half-day probabilities,
      // only when it is above zero, on a fixed 0..100 scale.
      const dayP: number | null = halfDayProbability(daily.day);
      const nightP: number | null = halfDayProbability(daily.night);
      let peak: number | null = null;
      if (dayP !== null && nightP !== null) {
        peak = Math.max(dayP, nightP);
      } else if (dayP !== null) {
        peak = dayP;
      } else if (nightP !== null) {
        peak = nightP;
      }
      if (peak !== null && peak > 0) {
        chart.histogramValue = peak;
        chart.histogramText = formatPercent(peak);
        chart.highestHistogramValue = 100;
        chart.lowestHistogramValue = 0;
      }
    }

    item.polyline = chart;
    items.push(item);
  }
  return items;
}

/**
 * The two-bars-from-the-centre tabs: daily Wind and daily Precipitation.
 *
 * `floor` is the minimum the scale never drops below — 15 m/s for wind
 * (DailyWindAdapter.kt:48) and PRECIPITATION_HALF_DAY_HEAVY for rain
 * (DailyPrecipitationAdapter.kt:56). Without it a calm week would scale a 1 m/s breeze to a
 * full-height bar.
 *
 * `colorOf` recolours each bar from its own value; `withArrows` swaps the day/night weather icons
 * for tinted direction arrows, which is what makes the Wind tab look unlike every other tab.
 */
function buildDailyDoubleHistogram(
  weather: Weather,
  tab: TrendTab,
  highValues: (number | null)[],
  lowValues: (number | null)[],
  formatValue: (value: number) => string,
  floor: number,
  colorOf: (value: number | null) => string | null,
  withArrows: boolean,
  utcOffsetSeconds: number
): TrendItemModel[] {
  const all: (number | null)[] = [];
  for (let i = 0; i < highValues.length; i++) {
    all.push(highValues[i]);
    all.push(lowValues[i]);
  }
  const highest: number = highestOf(all, floor);

  const items: TrendItemModel[] = [];
  for (let i = 0; i < weather.dailyForecast.length; i++) {
    const daily: Daily = weather.dailyForecast[i];
    const item = new TrendItemModel();
    item.key = tab.id + '-' + i.toString();
    item.topLabel = dailyTopLabel(daily, i, weather.todayIndex, utcOffsetSeconds);
    item.subLabel = getFormattedShortDayAndMonth(daily.date, utcOffsetSeconds);
    item.accent = dailyIsAccent(daily, i, weather.todayIndex);
    item.chartKind = ChartKind.DOUBLE_HISTOGRAM;

    const dayColor: string | null = colorOf(highValues[i]);
    const nightColor: string | null = colorOf(lowValues[i]);

    if (withArrows) {
      // DailyWindAdapter.kt:71-75 / :101-105 — arrow drawable tinted with the half-day's colour.
      const dayDegree: number | null = daily.day !== null ? (daily.day as HalfDay).windDegree : null;
      const nightDegree: number | null = daily.night !== null ? (daily.night as HalfDay).windDegree : null;
      item.dayIcon = getWindArrowIcon(dayDegree);
      item.nightIcon = getWindArrowIcon(nightDegree);
      item.dayIconIsArrow = true;
      item.nightIconIsArrow = true;
      item.dayIconRotation = getWindArrowRotation(dayDegree);
      item.nightIconRotation = getWindArrowRotation(nightDegree);
      if (dayColor !== null) {
        item.dayIconTint = dayColor;
      }
      if (nightColor !== null) {
        item.nightIconTint = nightColor;
      }
    } else {
      // DailyPrecipitationAdapter.kt:95-98 / :115-118 — ordinary weather icons.
      item.dayIcon = daily.day !== null ? getWeatherIcon(daily.day.weatherKind, true) : null;
      item.nightIcon = daily.night !== null ? getWeatherIcon(daily.night.weatherKind, false) : null;
    }

    const chart = new DoubleHistogramData();
    chart.highValue = highValues[i];
    chart.lowValue = lowValues[i];
    chart.highText = highValues[i] !== null ? formatValue(highValues[i] as number) : null;
    chart.lowText = lowValues[i] !== null ? formatValue(lowValues[i] as number) : null;
    chart.highestValue = highest;
    chart.highColor = dayColor;
    chart.lowColor = nightColor;
    item.doubleHistogram = chart;

    items.push(item);
  }
  return items;
}

/** Daily UV and Sunshine: one opaque bar, no polyline, and no icons at all. */
function buildDailyHistogramOnly(
  weather: Weather,
  tab: TrendTab,
  values: (number | null)[],
  formatValue: (value: number) => string,
  floor: number,
  colorOf: (value: number | null) => string | null,
  titleTextColor: string,
  utcOffsetSeconds: number
): TrendItemModel[] {
  const highest: number = highestOf(values, floor);
  const items: TrendItemModel[] = [];
  for (let i = 0; i < weather.dailyForecast.length; i++) {
    const daily: Daily = weather.dailyForecast[i];
    const item = new TrendItemModel();
    item.key = tab.id + '-' + i.toString();
    item.topLabel = dailyTopLabel(daily, i, weather.todayIndex, utcOffsetSeconds);
    item.subLabel = getFormattedShortDayAndMonth(daily.date, utcOffsetSeconds);
    item.accent = dailyIsAccent(daily, i, weather.todayIndex);
    // DailyUVAdapter / DailySunshineAdapter never call setDayIconDrawable.
    item.hasIcons = false;
    item.chartKind = ChartKind.POLYLINE;

    const value: number | null = values[i];
    item.polyline = histogramOnlyChart(
      value,
      value !== null ? formatValue(value) : null,
      highest,
      colorOf(value),
      titleTextColor
    );
    items.push(item);
  }
  return items;
}

function formatIndex(value: number): string {
  return Math.round(value).toString();
}

function formatHours(value: number): string {
  return (Math.round(value * 10) / 10).toString() + 'h';
}

/**
 * A histogram-only chart: no polyline, an opaque bar in the value's own colour, and the label
 * below the bar in colorTitleText (setHistogramAlpha(1f) + setTextColors(..., colorTitleText),
 * e.g. HourlyWindAdapter.kt:83-94).
 *
 * Leaving highest/lowestValue null is what suppresses the polyline, matching the six null
 * arguments the Kotlin adapters pass.
 */
function histogramOnlyChart(
  value: number | null,
  text: string | null,
  highest: number | null,
  barColor: string | null,
  titleTextColor: string
): ChartData {
  const chart = new ChartData();
  chart.histogramValue = value;
  chart.histogramText = text;
  chart.highestHistogramValue = highest;
  chart.lowestHistogramValue = 0;
  chart.histogramColor = barColor;
  chart.histogramAlpha = 1;
  chart.histogramTextColor = titleTextColor;
  return chart;
}

/** DailySunshineAdapter.kt:~95 — one flat colour for every bar, R.color.sunshine. */
function sunshineColor(value: number | null): string | null {
  return value === null ? null : AppColors.SUNSHINE;
}

/** The largest observed value, floored at a minimum the Android adapters impose. */
function highestOf(values: (number | null)[], floor: number): number {
  let highest: number = floor;
  for (let i = 0; i < values.length; i++) {
    const v: number | null = values[i];
    if (v !== null && v > highest) {
      highest = v;
    }
  }
  return highest;
}

/**
 * @param titleTextColor colorTitleText resolved for the current theme — the label colour the
 *        histogram-only tabs use (the polyline tabs colour their precipitation-probability text
 *        with colorPrecipitationProbability instead, which stays a card-level colour).
 */
export function buildDailySeries(
  location: LocationModel,
  tab: TrendTab,
  titleTextColor: string
): TrendSeries {
  const series = new TrendSeries();
  const weather: Weather | null = location.weather;
  if (weather === null) {
    return series;
  }
  // Every label below is the LOCATION's wall clock, as Android's adapters read it through
  // location.timeZone.
  const utcOffsetSeconds: number = location.utcOffsetSeconds;
  const days: Daily[] = weather.dailyForecast;

  if (tab.id === TrendTabId.TEMPERATURE || tab.id === TrendTabId.FEELS_LIKE) {
    const isFeelsLike: boolean = tab.id === TrendTabId.FEELS_LIKE;
    const highValues: (number | null)[] = [];
    const lowValues: (number | null)[] = [];
    for (let i = 0; i < days.length; i++) {
      highValues.push(isFeelsLike ? halfDayFeelsLike(days[i].day) : halfDayTemperature(days[i].day));
      lowValues.push(isFeelsLike ? halfDayFeelsLike(days[i].night) : halfDayTemperature(days[i].night));
    }

    const bounds = new Bounds();
    // kt:238-241 — the normals participate in the bounds so the key lines stay inside the chart.
    if (weather.normals !== null) {
      extend(bounds, weather.normals.daytimeTemperature);
      extend(bounds, weather.normals.nighttimeTemperature);
    }
    for (let i = 0; i < highValues.length; i++) {
      extend(bounds, highValues[i]);
      extend(bounds, lowValues[i]);
    }

    series.items = buildDailyPolyline(
      weather, tab, highValues, lowValues, formatTemperatureNarrow, bounds, true, utcOffsetSeconds
    );

    // kt:278-311 — two normals key lines, the daytime one above its line, night below.
    if (
      !isFeelsLike &&
      weather.normals !== null &&
      weather.normals.daytimeTemperature !== null &&
      weather.normals.nighttimeTemperature !== null
    ) {
      const dayLine = new KeyLine();
      dayLine.value = weather.normals.daytimeTemperature;
      dayLine.contentLeft = formatTemperatureNarrow(weather.normals.daytimeTemperature);
      dayLine.contentRight = 'Normal'; // strings.xml:68 temperature_normal_short
      dayLine.above = true;

      const nightLine = new KeyLine();
      nightLine.value = weather.normals.nighttimeTemperature;
      nightLine.contentLeft = formatTemperatureNarrow(weather.normals.nighttimeTemperature);
      nightLine.contentRight = 'Normal';
      nightLine.above = false;

      series.keyLines = [dayLine, nightLine];
    }
    return series;
  }

  if (tab.id === TrendTabId.WIND) {
    const highValues: (number | null)[] = [];
    const lowValues: (number | null)[] = [];
    for (let i = 0; i < days.length; i++) {
      highValues.push(days[i].day !== null ? (days[i].day as HalfDay).windSpeed : null);
      lowValues.push(days[i].night !== null ? (days[i].night as HalfDay).windSpeed : null);
    }
    // DailyWindAdapter.kt:48 — the scale never falls below 15 m/s.
    series.items = buildDailyDoubleHistogram(
      weather, tab, highValues, lowValues, formatSpeed, 15, windColor, true, utcOffsetSeconds
    );
    return series;
  }

  if (tab.id === TrendTabId.PRECIPITATION) {
    const highValues: (number | null)[] = [];
    const lowValues: (number | null)[] = [];
    for (let i = 0; i < days.length; i++) {
      highValues.push(days[i].day !== null ? (days[i].day as HalfDay).precipitationTotal : null);
      lowValues.push(days[i].night !== null ? (days[i].night as HalfDay).precipitationTotal : null);
    }
    // DailyPrecipitationAdapter.kt:56 — floored at PRECIPITATION_HALF_DAY_HEAVY.
    series.items = buildDailyDoubleHistogram(
      weather, tab, highValues, lowValues, formatPrecipitation, 57.75, halfDayPrecipitationColor, false, utcOffsetSeconds
    );
    return series;
  }

  if (tab.id === TrendTabId.AIR_QUALITY) {
    // DailyAirQualityAdapter.kt:137-163 — histogram only, bars coloured by the AQI band, the
    // scale floored at the "excessive" threshold, and three key lines at the band boundaries.
    const values: (number | null)[] = [];
    for (let i = 0; i < days.length; i++) {
      values.push(days[i].airQualityIndex);
    }
    series.items = buildDailyHistogramOnly(
      weather, tab, values, formatIndex, AppColors.AQI_THRESHOLDS[4],
      aqiLevelColorOrNull, titleTextColor, utcOffsetSeconds
    );
    series.keyLines = [
      aqiKeyLine(AppColors.AQI_THRESHOLDS[1], 'Fresh air', true),
      aqiKeyLine(AppColors.AQI_THRESHOLDS[2], 'High pollution', true),
      aqiKeyLine(AppColors.AQI_THRESHOLDS[3], 'Excessive pollution', true)
    ];
    return series;
  }

  if (tab.id === TrendTabId.UV_INDEX) {
    const values: (number | null)[] = [];
    for (let i = 0; i < days.length; i++) {
      values.push(days[i].uvIndex);
    }
    // DailyUVAdapter.kt:47 — floored at UV_INDEX_HIGH (8).
    series.items = buildDailyHistogramOnly(weather, tab, values, formatIndex, 8, uvColor, titleTextColor, utcOffsetSeconds);
    // DailyUVAdapter.kt:134-141 — one key line at UV_INDEX_MIDDLE.
    const alertLine = new KeyLine();
    alertLine.value = 6;
    alertLine.contentLeft = formatIndex(6);
    alertLine.contentRight = 'Alert level'; // strings.xml uv_alert_level
    alertLine.above = true;
    series.keyLines = [alertLine];
    return series;
  }

  // Sunshine — DailySunshineAdapter.kt:80-91, a fixed #fdbc4c bar and no key lines.
  const values: (number | null)[] = [];
  for (let i = 0; i < days.length; i++) {
    values.push(days[i].sunshineHours);
  }
  series.items = buildDailyHistogramOnly(
    weather,
    tab,
    values,
    formatHours,
    0,
    sunshineColor,
    titleTextColor, utcOffsetSeconds
  );
  return series;
}

/* ------------------------------------------------------------------- hourly */

/**
 * Which hourly tabs draw a polyline at all.
 *
 * Wind, UV, Precipitation and Cloud cover pass six nulls to setData and render only a histogram;
 * the rest draw a single (high) line. This split is the whole of the hourly half of the bug: the
 * port previously drew a polyline for all nine.
 */
function hourlyIsHistogramOnly(tab: TrendTab): boolean {
  return tab.id === TrendTabId.WIND ||
    tab.id === TrendTabId.UV_INDEX ||
    tab.id === TrendTabId.PRECIPITATION ||
    tab.id === TrendTabId.CLOUD_COVER ||
    // HourlyAirQualityAdapter passes six nulls too — bars only, no polyline.
    tab.id === TrendTabId.AIR_QUALITY;
}

/** The value a polyline tab plots. Humidity plots dew point, not the humidity itself. */
function hourlyPolylineValue(hour: Hourly, tab: TrendTab): number | null {
  switch (tab.id) {
    case TrendTabId.TEMPERATURE:
      return hour.temperature !== null ? hour.temperature.temperature : null;
    case TrendTabId.FEELS_LIKE:
      return hour.temperature !== null ? hour.temperature.feelsLikeTemperature : null;
    // HourlyHumidityAdapter.kt:85-101 — the line is dew point; humidity is the histogram behind it.
    case TrendTabId.HUMIDITY:
      return hour.dewPoint;
    case TrendTabId.PRESSURE:
      return hour.pressure;
    case TrendTabId.VISIBILITY:
      return hour.visibility;
    default:
      return null;
  }
}

function hourlyPolylineFormatter(tab: TrendTab): (value: number) => string {
  switch (tab.id) {
    case TrendTabId.TEMPERATURE:
      return formatTemperatureNarrow;
    case TrendTabId.FEELS_LIKE:
      return formatTemperatureNarrow;
    // Dew point is a temperature, so it formats like one.
    case TrendTabId.HUMIDITY:
      return formatTemperatureNarrow;
    case TrendTabId.PRESSURE:
      return formatPressure;
    case TrendTabId.VISIBILITY:
      return formatDistance;
    default:
      return formatIndex;
  }
}

/** The value a histogram-only tab bars, with its scale floor and per-bar colour. */
function hourlyHistogramValue(hour: Hourly, tab: TrendTab): number | null {
  switch (tab.id) {
    case TrendTabId.WIND:
      return hour.windSpeed;
    case TrendTabId.UV_INDEX:
      return hour.uvIndex;
    case TrendTabId.AIR_QUALITY:
      return hour.airQualityIndex;
    // HourlyPrecipitationAdapter.kt:81-89 bars the precipitation TOTAL, not the probability.
    case TrendTabId.PRECIPITATION:
      return hour.precipitationTotal;
    case TrendTabId.CLOUD_COVER:
      return hour.cloudCover;
    default:
      return null;
  }
}

function hourlyHistogramFormatter(tab: TrendTab): (value: number) => string {
  switch (tab.id) {
    case TrendTabId.WIND:
      return formatSpeed;
    case TrendTabId.UV_INDEX:
    case TrendTabId.AIR_QUALITY:
      return formatIndex;
    case TrendTabId.PRECIPITATION:
      return formatPrecipitation;
    default:
      return formatPercent;
  }
}

function hourlyHistogramColor(tab: TrendTab): (value: number | null) => string | null {
  switch (tab.id) {
    case TrendTabId.WIND:
      return windColor;
    case TrendTabId.UV_INDEX:
      return uvColor;
    case TrendTabId.AIR_QUALITY:
      return aqiLevelColorOrNull;
    case TrendTabId.PRECIPITATION:
      return hourlyPrecipitationColor;
    default:
      return cloudCoverColor;
  }
}

/**
 * The floor under each histogram-only scale:
 *   wind          15 m/s                      HourlyWindAdapter.kt:48
 *   UV            UV_INDEX_HIGH = 8           HourlyUVAdapter.kt
 *   precipitation PRECIPITATION_HOURLY_HEAVY  HourlyPrecipitationAdapter.kt:51
 *   cloud cover   fixed 100                   HourlyCloudCoverAdapter.kt:64-75
 */
function hourlyHistogramFloor(tab: TrendTab): number {
  switch (tab.id) {
    case TrendTabId.WIND:
      return 15;
    case TrendTabId.UV_INDEX:
      return 8;
    // HourlyAirQualityAdapter.kt — floored at the "excessive" threshold, aqiThresholds[4] = 150.
    case TrendTabId.AIR_QUALITY:
      return 150;
    case TrendTabId.PRECIPITATION:
      return 15;
    default:
      return 100;
  }
}

/** See buildDailySeries for titleTextColor. */
export function buildHourlySeries(
  location: LocationModel,
  tab: TrendTab,
  titleTextColor: string
): TrendSeries {
  const series = new TrendSeries();
  const weather: Weather | null = location.weather;
  if (weather === null) {
    return series;
  }
  // Every label below is the LOCATION's wall clock, as Android's adapters read it through
  // location.timeZone.
  const utcOffsetSeconds: number = location.utcOffsetSeconds;
  const hours: Hourly[] = weather.nextHourlyForecast;
  const histogramOnly: boolean = hourlyIsHistogramOnly(tab);

  /* ---- the histogram-only tabs: Wind, UV, Precipitation, Cloud cover ---- */
  if (histogramOnly) {
    const values: (number | null)[] = [];
    for (let i = 0; i < hours.length; i++) {
      values.push(hourlyHistogramValue(hours[i], tab));
    }
    const format: (value: number) => string = hourlyHistogramFormatter(tab);
    const colorOf: (value: number | null) => string | null = hourlyHistogramColor(tab);
    const highest: number = highestOf(values, hourlyHistogramFloor(tab));

    for (let i = 0; i < hours.length; i++) {
      const hour: Hourly = hours[i];
      const item = new TrendItemModel();
      item.key = tab.id + '-' + i.toString();
      item.topLabel = getHour(hour.date, utcOffsetSeconds);
      item.subLabel = null;
      item.accent = i === 0 || getHourIn24Format(hour.date, utcOffsetSeconds) === '0';
      item.chartKind = ChartKind.POLYLINE;

      const value: number | null = values[i];
      const barColor: string | null = colorOf(value);

      if (tab.id === TrendTabId.WIND) {
        // HourlyWindAdapter.kt:69-73 — a single arrow above the chart, tinted with the bar colour.
        item.dayIcon = getWindArrowIcon(hour.windDegree);
        item.dayIconIsArrow = true;
        item.dayIconRotation = getWindArrowRotation(hour.windDegree);
        if (barColor !== null) {
          item.dayIconTint = barColor;
        }
      } else if (tab.id === TrendTabId.PRECIPITATION) {
        // HourlyPrecipitationAdapter keeps the weather icon.
        item.dayIcon = getWeatherIcon(hour.weatherKind, hour.daylight);
      } else {
        // UV and Cloud cover show no icon at all.
        item.hasIcons = false;
      }

      item.polyline = histogramOnlyChart(
        value,
        value !== null ? format(value) : null,
        highest,
        barColor,
        titleTextColor
      );
      series.items.push(item);
    }
    return series;
  }

  /* ---- the polyline tabs: Conditions, Feels like, Humidity, Pressure, Visibility ---- */
  const values: (number | null)[] = [];
  for (let i = 0; i < hours.length; i++) {
    values.push(hourlyPolylineValue(hours[i], tab));
  }
  const format: (value: number) => string = hourlyPolylineFormatter(tab);

  const bounds = new Bounds();
  for (let i = 0; i < values.length; i++) {
    extend(bounds, values[i]);
  }
  // A flat series would divide by zero when mapping values to pixels.
  if (bounds.highest !== null && bounds.lowest !== null && bounds.highest === bounds.lowest) {
    bounds.highest = bounds.highest + 1;
    bounds.lowest = bounds.lowest - 1;
  }

  const doubled: (number | null)[] = buildDoubledSeries(values);

  for (let i = 0; i < hours.length; i++) {
    const hour: Hourly = hours[i];
    const item = new TrendItemModel();
    item.key = tab.id + '-' + i.toString();
    item.topLabel = getHour(hour.date, utcOffsetSeconds);
    item.subLabel = null;
    // AbsHourlyTrendAdapter.kt:56 — the first column and every midnight use the accent colour.
    item.accent = i === 0 || getHourIn24Format(hour.date, utcOffsetSeconds) === '0';
    item.dayIcon = getWeatherIcon(hour.weatherKind, hour.daylight);
    item.nightIcon = null;
    item.chartKind = ChartKind.POLYLINE;

    const chart = new ChartData();
    chart.highPolyline = sliceForItem(doubled, i);
    chart.lowPolyline = PolylinePoints.empty();
    const value: number | null = values[i];
    chart.highText = value !== null ? format(value) : null;
    chart.lowText = null;
    chart.highestValue = bounds.highest;
    chart.lowestValue = bounds.lowest;

    // HourlyTemperatureAdapter.kt:91-107 shows precipitation probability behind the curve.
    if (tab.id === TrendTabId.TEMPERATURE && hour.precipitationProbability !== null) {
      const p: number | null = hour.precipitationProbability.total;
      if (p !== null && p > 0) {
        chart.histogramValue = p;
        chart.histogramText = formatPercent(p);
        chart.highestHistogramValue = 100;
        chart.lowestHistogramValue = 0;
      }
    }

    // HourlyHumidityAdapter.kt:85-101 puts relative humidity behind the dew-point line, on the
    // same fixed 0..100 scale the probability histogram uses.
    if (tab.id === TrendTabId.HUMIDITY && hour.relativeHumidity !== null) {
      const h: number = hour.relativeHumidity;
      chart.histogramValue = h;
      chart.histogramText = formatPercent(h);
      chart.highestHistogramValue = 100;
      chart.lowestHistogramValue = 0;
    }

    item.polyline = chart;
    series.items.push(item);
  }
  return series;
}
