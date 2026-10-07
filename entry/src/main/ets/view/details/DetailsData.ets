/*
 * Screen 4's data - everything DetailsScreen draws that is not layout.
 *
 * Sources:
 *   ui/details/DetailsScreen.kt:352-518        which hours belong to the selected day
 *   ui/details/components/Details<Tag>.kt      the header of each tag ("<Tag>Header")
 *   ui/details/components/DetailsCommon.kt     the section header + card prose
 *   domain/weather/model/Daily.kt:41-80        getFullLabel
 *
 * Kept apart from the page so the NDK port (view/DetailsScreen.cpp) transcribes ONE file rather
 * than re-deriving the rules from Kotlin - the same arrangement SourcePreferences.ets has with the
 * weather-sources screen.
 *
 * WHERE THIS PORT DIFFERS FROM THE KOTLIN, AND WHY: the Kotlin's `Daily` carries DailyPressure,
 * DailyRelativeHumidity, DailyCloudCover and DailyVisibility, filled by the source or by
 * `completeDailyListFromHourlyList`. Open-Meteo publishes none of those daily, so this port has no
 * such fields at all - the day's figures are computed here from the day's hours, which is what the
 * Kotlin's completion step does with the same numbers.
 */

import { Daily, HalfDay, Hourly, LocationModel, PollenEntry } from '../../model/Weather';
import { DetailScreen } from '../../model/DetailScreen';
import { DAY_MS, localStartOfDay } from '../../common/LocalTime';
import { COLON_SEPARATOR, getClockTime, getHour, getWeek } from '../../common/Formatter';
import { LineHeights } from '../../common/Typography';
import {
  AstroPair,
  calculatedCivilTwilight,
  calculatedMoon,
  calculatedSun,
  moonPhaseAngle,
  moonPhaseName
} from '../../data/Astronomy';
import {
  distanceUnitLabel,
  distanceDecimals,
  distanceUnitDisplayName,
  distanceValue,
  formatDistance,
  formatDistanceValue,
  formatPrecipitation,
  formatPressure,
  formatDecimals,
  formatSnowfall,
  formatSpeed,
  formatSpeedValue,
  formatTemperatureDeviation,
  formatTemperatureNarrow,
  formatTemperatureShortNarrow,
  formatTemperatureWithUnit,
  precipitationChartStep,
  precipitationUnitLabel,
  precipitationValue,
  snowfallUnitLabel,
  pressureUnitLabel,
  pressureValue,
  speedChartStep,
  speedUnitDisplayName,
  speedUnitLabel,
  speedValue,
  temperatureChartStep,
  temperatureUnitLabel,
  temperatureValue
} from '../../common/Units';
import {
  AirQualityConcentrations,
  AQI_THRESHOLDS,
  aqiHarmlessExposureAt,
  aqiLevelDescription,
  aqiLevelName,
  concentrationOf,
  concentrationUnitLabel,
  formatConcentration,
  levelOf,
  overallIndexOf,
  PollutantDef,
  pollutantById,
  pollutantIndexOf,
  POLLUTANTS
} from '../../model/Pollutant';
import { AppColors, aqiLevelColor, pollenLevelColor } from '../../theme/AppColors';
import { WeatherKind } from '../../model/WeatherKind';
import {
  moonAltitudeDegrees,
  moonTimes,
  RiseSet,
  sunAltitudeDegrees,
  sunTimes
} from '../../data/Astronomy';

/** strings.xml:1299 */
const NULL_DATA_TEXT: string = 'N/A';

/**
 * One column of the summary block above the chart.
 *
 * A column is the shape every `<Tag>Item` composable draws: an optional leading dot, a labelMedium
 * label, a displaySmall value whose unit rides a size down, and an optional labelMedium line under
 * it.
 */
export class SummaryColumn {
  /** labelMedium, e.g. "Average", "Today", "Daytime". */
  label: string = '';
  /** displaySmall, e.g. "1,008.4 hPa" - the unit part is drawn a size down. */
  value: string = '';
  /** The unit tail of `value`, rendered at headlineSmall (UnitUtils.formatUnitsDifferentFontSize). */
  unit: string = '';
  /**
   * What follows the unit, back at displaySmall.
   *
   * Wind is the only tag with one: `WindItem` (DetailsWind.kt:274-302) appends `" " + arrow` to the
   * annotated string AFTER the unit span, so the arrow is the same size as the speed. The port drew
   * it as a separate line under the value instead, which is where the gusts belong.
   */
  valueSuffix: string = '';
  /**
   * The LEVEL NAME, appended to the value at headlineSmall in onSurfaceVariant.
   *
   * `AirQualityItem` (DetailsAirQuality.kt:402-433) and `UVItem` build ONE displaySmall
   * `TextFixedHeight` of "27" + " " + a `withStyle(headlineSmall, onSurfaceVariant)` span reading
   * "Fair" — so the reference's node is a single 143 px line reading "27 Fair". Both ports put the
   * level on a THIRD line instead, which made those two headers 52 px taller than Android's and
   * pushed everything below them down.
   */
  valueLevel: string = '';
  /** The third line under the value - the cloud-cover description, the gusts, "Actual: 21 deg". */
  description: string = '';
  /**
   * The third line's FIXED height in vp, or 0 when this tag has no third line at all.
   *
   * Every `<Tag>Item` is a stack of `TextFixedHeight`s, so the line is reserved whether or not it
   * has text: `WindItem`'s else-branch draws an empty one precisely so the Daytime and Nighttime
   * columns stay the same height (kt:318-324). 16 is labelMedium (cloud cover, visibility,
   * conditions); 20 is labelLarge (wind).
   */
  descriptionLine: number = 0;
  /**
   * ARGB of the leading dot, or empty for no dot. UV and air quality have one - an ic_circle tinted
   * with getUVColor / getColor (DetailsUV.kt:203-212, DetailsAirQuality.kt:388-394).
   */
  dotColor: string = '';
  /**
   * The weather icon drawn BEFORE `description`, or NULL for the columns that have none.
   *
   * `WeatherCondition` (DetailsConditions.kt:718-766) is a Row of a
   * `small_weather_icon_size` icon, a `small_margin` gap and the condition text in BOLD onSurface
   * — not the plain onSurfaceVariant line every other tag's description is. Only the Conditions
   * and Feels-like headers have it; the port used to draw the text alone.
   */
  iconKind: WeatherKind | null = null;
  /** Which half of the day the icon belongs to, so a night column gets the night variant. */
  iconDaylight: boolean = true;
}

/**
 * The summary block.
 *
 * ONE column for the scalar tags; TWO - Daytime and Nighttime - for the four that summarise a
 * half-day each (`WindSummary` kt:224-262, `PrecipitationSummary` kt:299-337,
 * `WeatherConditionSummary` kt:494-551). Empty for the two tags whose screens have no header at
 * all: Pollen and Sun & moon lead with their own card instead.
 */
export class DetailsSummary {
  columns: SummaryColumn[] = [];
}

/** One line of a card that lists rather than narrates - the ephemeris times, the pollen grid. */
export class DetailsRow {
  /** The whole line for an ephemeris row ("Sunrise at 5:21 AM"); the allergen name for pollen. */
  label: string = '';
  /** The trailing value, empty when the row is a single sentence. */
  value: string = '';
  dotColor: string = '';
  /**
   * A THIRD column between the label and the value, empty for a two-column row.
   *
   * Two scales have one: air quality is Description | Harmless exposure | AQI
   * (DetailsAirQuality.kt:725-797) and Beaufort is Bft | Description | meters/sec
   * (DetailsWind.kt:504-592). UV, cloud cover and visibility are two columns.
   */
  middle: string = '';
  /**
   * A `ListItem`'s leading icon, as a media asset name, or "" for a row that has none.
   *
   * Only the Sun & moon card has them: every one of its four rows is a Material3 `ListItem` with a
   * 24 dp leading Image (DetailsSunMoon.kt:339-558), which is why they are 56 dp tall whatever
   * their text measures.
   */
  icon: string = '';
  /**
   * `DailyMoonPhase`'s leading content is a `MoonPhaseView` at this angle, not an icon
   * (kt:534-548). -1 means the row is not the moon-phase row.
   */
  moonPhaseAngle: number = -1;

  constructor(label: string, value: string = '', dotColor: string = '', middle: string = '',
    icon: string = '', moonPhaseAngle: number = -1) {
    this.label = label;
    this.value = value;
    this.dotColor = dotColor;
    this.middle = middle;
    this.icon = icon;
    this.moonPhaseAngle = moonPhaseAngle;
  }
}

/**
 * One block under the chart: a titleLarge heading, an optional bodySmall subtitle, and a card of
 * either prose paragraphs or listed rows.
 *
 * A heading of "" is a card with no header above it, which is what DetailsSunMoon draws before its
 * About section (kt:104-126).
 */
export class DetailsSection {
  heading: string = '';
  subtitle: string = '';
  paragraphs: string[] = [];
  rows: DetailsRow[] = [];

  /**
   * A scale table's bold header row — "Description | UV index" (DetailsUV.kt:331-345). Empty when
   * the card is prose or a plain row list.
   */
  headerLabel: string = '';
  headerValue: string = '';
  /** The header cell above `DetailsRow.middle`; empty for a two-column table. */
  headerMiddle: string = '';
  /**
   * `false` for the ordinary card of prose or listed rows; `true` for `AirQualityDetails`
   * (DetailsAirQuality.kt:656-682), which is a two-per-row FlowRow of a bold pollutant name, a
   * progress bar in its colour and the concentration under it. Its rows carry the bar's fraction
   * in `middle`.
   */
  pollutantGrid: boolean = false;
  /**
   * `PollenGrid` (AllergenComposables.kt:54-95) — also two per row, but a different CELL: a
   * material-icon-sized dot in the allergen's colour, then its name in titleMedium over
   * "12/m³ – Low" in bodyMedium. The name is the row's `label`, the subtitle its `value`.
   */
  pollenGrid: boolean = false;
  /**
   * `true` for the Sun & moon card, whose rows are Material3 `ListItem`s rather than scale-table
   * lines: a fixed 56 dp tall each, 16 dp of horizontal padding of their own, and no padding on
   * the card. Measured on the reference: its card is 728 px for four rows, 182 apiece.
   */
  listItemRows: boolean = false;

  /*
   * A scale table's column weights, which are NOT the same in the four tables:
   *   UV                 2   / -   / 1     (DetailsUV.kt:336-342)
   *   cloud, visibility  1.5 / -   / 1     (kt:363-369 / kt:372-386)
   *   Beaufort           1   / 1.5 / 1.5   (DetailsWind.kt:520-535)
   *   air quality        2   / 1.5 / 1.5   (DetailsAirQuality.kt:750-769)
   * The port used to hard-code 2 / 1.5 / 1.5 for all of them and hug the value column.
   */
  labelWeight: number = 1.5;
  middleWeight: number = 1.5;
  valueWeight: number = 1;

  constructor(heading: string, paragraphs: string[], rows: DetailsRow[] = [], subtitle: string = '',
    headerLabel: string = '', headerValue: string = '', headerMiddle: string = '',
    pollutantGrid: boolean = false, pollenGrid: boolean = false,
    labelWeight: number = 1.5, middleWeight: number = 1.5, valueWeight: number = 1,
    listItemRows: boolean = false) {
    this.labelWeight = labelWeight;
    this.middleWeight = middleWeight;
    this.valueWeight = valueWeight;
    this.listItemRows = listItemRows;
    this.heading = heading;
    this.paragraphs = paragraphs;
    this.rows = rows;
    this.subtitle = subtitle;
    this.headerLabel = headerLabel;
    this.headerValue = headerValue;
    this.headerMiddle = headerMiddle;
    this.pollutantGrid = pollutantGrid;
    this.pollenGrid = pollenGrid;
  }
}

/*
 * The prose, verbatim from strings.xml. Split exactly as the Kotlin splits it - `pressure` has two
 * numbered paragraphs, the rest one - because DetailsCardText spaces its paragraphs by 16 vp and
 * concatenating them would lose that gap.
 */
const ABOUT_PRESSURE_1: string =
  'Atmospheric pressure is the downward pressure exerted by the earth’s atmosphere. This app ' +
  'uses mean sea level pressure (MSLP) to allow easier comparison of pressure from places with ' +
  'different altitudes.';
const ABOUT_PRESSURE_2: string =
  'Significant, rapid changes in pressure are used to predict changes in the weather. For example, ' +
  'a drop in pressure can mean that rain or snow is on the way, and rising pressure can mean that ' +
  'weather will improve. Abnormal atmospheric pressure may cause headaches, joint pain, fatigue ' +
  'and other effects.';
const ABOUT_HUMIDITY: string =
  'Relative humidity, more commonly known just as humidity, is the percentage of water vapour ' +
  'present in the air compared to the maximum amount that the air can hold at a given temperature.';
const ABOUT_DEW_POINT: string =
  'Dew point is what the temperature would need to be cooled to in order to achieve a relative ' +
  'humidity of 100%.';
const ABOUT_VISIBILITY: string =
  'Visibility tells you how far away you can clearly see objects like buildings and hills. ' +
  'Visibility can be affected by precipitation, fog, dust, smoke or haze.';
const ABOUT_CLOUD_COVER: string =
  'Cloud cover refers to the percentage of the sky obscured by clouds on average. The cloud cover ' +
  'is correlated to the sunshine duration.';
const ABOUT_UV: string =
  'The UV index measures the strength of the sun’s ultraviolet radiation. The higher it is, ' +
  'the greater and faster it can cause sunburn, skin cancer and eye damage.';
const ABOUT_WIND: string =
  'Wind speed is measured by averaging wind speeds over a period of time. Gusts are sudden bursts ' +
  'of wind typically lasting under 20 seconds.';
const ABOUT_AIR_QUALITY_1: string =
  'Air quality index (AQI) is a scale designed to help you understand how polluted the air is in a ' +
  'particular area, and the potential risks to your health.';
const ABOUT_AIR_QUALITY_2: string =
  'The scale used in this app is based on World Health Organization recommendations, rather than ' +
  'local regulations, to have meaningful categories, and make it easier to compare pollution ' +
  'levels between countries.';
const ABOUT_EPHEMERIS: string =
  'The rise time is when the sun or moon fully appears above the horizon.\n\n' +
  'The set time is when the sun or moon completely disappears below the horizon.\n\n' +
  'The dawn is when the first visible light of the day appears before sunrise.\n\n' +
  'The dusk is the darkest stage of twilight before the last visible light disappears.';

/**
 * The hours belonging to a day - DetailsScreen.kt:366-386.
 *
 * The window is local midnight to the NEXT local midnight, and the first index is nudged one hour
 * BACK when the first hour at or after midnight is not exactly midnight, so a 3-hourly source still
 * draws a complete chart (kt:372-376).
 */
export function hoursForDay(location: LocationModel, dayIndex: number): Hourly[] {
  const weather = location.weather;
  const out: Hourly[] = [];
  if (weather === null || dayIndex < 0 || dayIndex >= weather.dailyForecast.length) {
    return out;
  }
  const offset: number = location.utcOffsetSeconds;
  const start: number = localStartOfDay(weather.dailyForecast[dayIndex].date, offset);
  const end: number = start + DAY_MS;
  /*
   * The WHOLE series, past hours included — `DetailsScreen.kt:372-385` slices
   * `weather.hourlyForecast`, not the trimmed view.
   *
   * This used to read `nextHourlyForecast`, which begins at the current hour, so every detail
   * screen reported "no hourly data available" on Yesterday while the reference drew a full chart
   * for it. Open-Meteo is already asked for past_days=1; the hours were fetched and thrown away.
   */
  const hours: Hourly[] = weather.hourlyForecast;

  let first: number = -1;
  for (let i = 0; i < hours.length; i++) {
    if (hours[i].date.getTime() >= start) {
      first = i;
      break;
    }
  }
  /*
   * A day with no hours at all gives an EMPTY list, not the first hour of the next one — days
   * beyond the hourly window still have a daily row and a pager column.
   */
  if (first === -1 || hours[first].date.getTime() >= end) {
    return out;
  }
  if (first > 0 && hours[first].date.getTime() > start) {
    first = first - 1;
  }
  let last: number = hours.length - 1;
  for (let i = 0; i < hours.length; i++) {
    if (hours[i].date.getTime() >= end) {
      last = i;
      break;
    }
  }
  for (let i = first; i <= last && i < hours.length; i++) {
    out.push(hours[i]);
  }
  return out;
}

/**
 * Which day a given instant belongs to - the pager page a tap should open at.
 *
 * A daily trend column already knows its index; an HOURLY column does not, and Android resolves it
 * the same way (DetailsActivity's initialIndex is derived from the tapped item's date). Falls back
 * to today when nothing matches, which is what a location with no forecast for that day would give.
 */
export function dayIndexForDate(location: LocationModel, date: Date): number {
  const weather = location.weather;
  if (weather === null) {
    return 0;
  }
  const offset: number = location.utcOffsetSeconds;
  const target: number = localStartOfDay(date, offset);
  for (let i = 0; i < weather.dailyForecast.length; i++) {
    if (localStartOfDay(weather.dailyForecast[i].date, offset) === target) {
      return i;
    }
  }
  const today = weather.todayIndex;
  return today === null ? 0 : today;
}

/**
 * Daily.getFullLabel (Daily.kt:41-80) - "Yesterday" / "Today" / "Tomorrow" / a weekday, and a full
 * weekday + day + month beyond a week out.
 */
export function dayFullLabel(location: LocationModel, daily: Daily, now: Date): string {
  const offset: number = location.utcOffsetSeconds;
  const dayStart: number = localStartOfDay(daily.date, offset);
  const todayStart: number = localStartOfDay(now, offset);
  const delta: number = Math.round((dayStart - todayStart) / DAY_MS);
  if (delta === 0) {
    return 'Today';
  }
  if (delta === -1) {
    return 'Yesterday';
  }
  if (delta === 1) {
    return 'Tomorrow';
  }
  if (delta > 6) {
    // kt:45-48 - beyond a week the label carries the date as well.
    return getWeek(daily.date, offset, true);
  }
  return getWeek(daily.date, offset, true);
}

/** The values of one field across the day's hours, nulls dropped. */
function values(hours: Hourly[], field: DetailScreen): number[] {
  const out: number[] = [];
  for (const hour of hours) {
    let value: number | null = null;
    switch (field) {
      case DetailScreen.TAG_PRESSURE:
        value = hour.pressure;
        break;
      case DetailScreen.TAG_HUMIDITY:
        value = hour.relativeHumidity;
        break;
      case DetailScreen.TAG_CLOUD_COVER:
        value = hour.cloudCover;
        break;
      case DetailScreen.TAG_VISIBILITY:
        value = hour.visibility;
        break;
      case DetailScreen.TAG_UV_INDEX:
        value = hour.uvIndex;
        break;
      case DetailScreen.TAG_WIND:
        value = hour.windSpeed;
        break;
      case DetailScreen.TAG_AIR_QUALITY:
        value = hour.airQualityIndex;
        break;
      case DetailScreen.TAG_PRECIPITATION:
        value = hour.precipitationTotal;
        break;
      default:
        value = null;
        break;
    }
    if (value !== null) {
      out.push(value);
    }
  }
  return out;
}

/**
 * The temperature gradient, degrees Celsius converted to the display unit
 * (DetailsConditions.kt:853-866).
 *
 * Shared, because `DewPointChart` uses the SAME ramp — the Kotlin says so in a TODO of its own
 * ("Duplicate of temperature colors", DetailsHumidity.kt:495). One table, two callers; a private
 * second copy is this codebase's recurring bug.
 */
function pushTemperatureStops(stops: ChartStop[]): void {
  stops.push(new ChartStop(temperatureValue(47), '#FF470E00'));
  stops.push(new ChartStop(temperatureValue(30), '#FFE85319'));
  stops.push(new ChartStop(temperatureValue(21), '#FFF3B704'));
  stops.push(new ChartStop(temperatureValue(10), '#FF809318'));
  stops.push(new ChartStop(temperatureValue(1), '#FF447D63'));
  stops.push(new ChartStop(temperatureValue(0), '#FF5D85C6'));
  stops.push(new ChartStop(temperatureValue(-4), '#FF64A6BD'));
  stops.push(new ChartStop(temperatureValue(-8), '#FF6ABFB5'));
  stops.push(new ChartStop(temperatureValue(-15), '#FF9DDBD9'));
  stops.push(new ChartStop(temperatureValue(-25), '#FF8F59A9'));
  stops.push(new ChartStop(temperatureValue(-40), '#FFA24691'));
  stops.push(new ChartStop(temperatureValue(-55), '#FFCAACC3'));
  stops.push(new ChartStop(temperatureValue(-70), '#FF734669'));
}

function mean(list: number[]): number {
  let total: number = 0;
  for (const value of list) {
    total += value;
  }
  return total / list.length;
}

/* `Math.min.apply` is not available under ArkTS's strict typing, and a spread over a 24-element
 * array would allocate on every frame anyway. */
function minOf(list: number[]): number {
  let out: number = list[0];
  for (const value of list) {
    if (value < out) {
      out = value;
    }
  }
  return out;
}

function maxOf(list: number[]): number {
  let out: number = list[0];
  for (const value of list) {
    if (value > out) {
      out = value;
    }
  }
  return out;
}

/** Ratio.getCloudCoverDescription (UnitExtensions.kt) against the okta bands 12.5/37.5/62.5/87.5. */
export function cloudCoverDescription(percent: number): string {
  if (percent < 12.5) {
    return 'Clear sky';
  }
  if (percent < 37.5) {
    return 'Mostly clear';
  }
  if (percent < 62.5) {
    return 'Partly cloudy';
  }
  if (percent < 87.5) {
    return 'Mostly cloudy';
  }
  return 'Cloudy';
}

/** Distance.getVisibilityDescription - the Met Office bands 1/4/10/20/40 km. */
export function visibilityDescription(metres: number): string {
  if (metres < 1000) {
    return 'Very poor';
  }
  if (metres < 4000) {
    return 'Poor';
  }
  if (metres < 10000) {
    return 'Moderate';
  }
  if (metres < 20000) {
    return 'Good';
  }
  if (metres < 40000) {
    return 'Clear';
  }
  return 'Perfectly clear';
}

/** UV.getLevel (UV.kt:29-39). */
export function uvLevelName(index: number): string {
  if (index < 3) {
    return 'Low';
  }
  if (index < 6) {
    return 'Moderate';
  }
  if (index < 8) {
    return 'High';
  }
  if (index < 11) {
    return 'Very high';
  }
  return 'Extreme';
}

/*
 * The five level colours, colors.xml `colorLevel_1`...`colorLevel_5`. UV, air quality and pollen all
 * key off these; UV.getUVColor (app/.../domain/weather/model/UV.kt:69-77) maps its four thresholds
 * onto the first four and everything above 11 onto the fifth.
 */
export const COLOR_LEVEL_1: string = '#FF72D572';
export const COLOR_LEVEL_2: string = '#FFFFCA28';
export const COLOR_LEVEL_3: string = '#FFFFA726';
export const COLOR_LEVEL_4: string = '#FFE52F35';
export const COLOR_LEVEL_5: string = '#FF99004C';

/** UV.kt:33-36 - the four thresholds every UV band and colour is cut at. */
export const UV_INDEX_LOW: number = 3.0;
export const UV_INDEX_MIDDLE: number = 6.0;
export const UV_INDEX_HIGH: number = 8.0;
export const UV_INDEX_EXCESSIVE: number = 11.0;

/** UV.getUVColor (UV.kt:69-77). */
export function uvLevelColor(index: number): string {
  if (index < UV_INDEX_LOW) {
    return COLOR_LEVEL_1;
  }
  if (index < UV_INDEX_MIDDLE) {
    return COLOR_LEVEL_2;
  }
  if (index < UV_INDEX_HIGH) {
    return COLOR_LEVEL_3;
  }
  if (index < UV_INDEX_EXCESSIVE) {
    return COLOR_LEVEL_4;
  }
  return COLOR_LEVEL_5;
}

/* ------------------------------------------------------------------------ the chart -------- */

/** One point of the line. `x` is the instant in ms, `y` the value in the DISPLAY unit. */
export class ChartPoint {
  x: number = 0;
  y: number = 0;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

/** One `trendHorizontalLine`: a rule across the plot with a label hanging under it. */
export class ChartKeyLine {
  y: number = 0;
  label: string = '';

  constructor(y: number, label: string) {
    this.y = y;
    this.label = label;
  }
}

/** One stop of the vertical gradient: a value in the display unit and its colour. */
export class ChartStop {
  value: number = 0;
  color: string = '';

  constructor(value: number, color: string) {
    this.value = value;
    this.color = color;
  }
}

/**
 * Everything BreezyLineChart needs, resolved to display units.
 *
 * The gradient is what makes these charts unusual: `ScaleLineFill` / `ScaleAreaFill`
 * (BreezyLineChart.kt:251-325) paint BOTH the stroke and the area with one vertical
 * LinearGradientShader spanning the whole plot, whose stops are the value scale mapped through
 * `1 - (y - minY) / (maxY - minY)`. So the line's colour at any height is the colour that height
 * MEANS, not a per-series colour - and the area is the same shader at alpha 128.
 */
export class DetailsChartSpec {
  points: ChartPoint[] = [];
  /**
   * A SECOND line, drawn without an area and in a flat colour.
   *
   * Only Feels like has one: the Kotlin adds the ACTUAL temperature as a second series behind the
   * feels-like one, coloured a flat grey at alpha 160 (DetailsConditions.kt:869-872).
   */
  points2: ChartPoint[] = [];
  secondaryColor: string = '#A0808080';
  /**
   * The second series' own value scale. Non-empty makes it a FULL series — gradient stroke and
   * area, exactly like the first — instead of the flat line above.
   *
   * Only the EphemerisChart has one: it plots the moon's altitude and the sun's as two independent
   * lines, each with its own colour (DetailsSunMoon.kt:211-220). The moon is the FIRST series there
   * and the sun the second, which is the order the Kotlin adds them in (kt:182-193).
   */
  stops2: ChartStop[] = [];
  /**
   * The area's own gradient, when it differs from the line's.
   *
   * `ScaleLineFill` and `ScaleAreaFill` take separate colour maps (BreezyLineChart.kt:251-310).
   * They are the same map for every tag except the ephemeris, where the line fades to the colour at
   * 50 % below the horizon and the area fades to transparent (DetailsSunMoon.kt:107-122). Empty
   * means "use `stops`", which is what every other chart wants.
   */
  areaStops: ChartStop[] = [];
  areaStops2: ChartStop[] = [];
  /**
   * `PointConnector.cubic(curvature = (PI - 2) / PI)` — the ephemeris chart alone connects its
   * points with a spline; every other chart uses Vico's default straight segments.
   */
  curved: boolean = false;
  /**
   * A COLUMN layer rather than a line one — `BreezyBarChart` (kt:162-173) instead of
   * BreezyLineChart. Only Precipitation's quantity chart is one.
   */
  bars: boolean = false;
  /** `barColorFill` — one flat colour for every column (DetailsPrecipitation.kt:377). */
  barColor: string = '';
  /** The x range is the whole local day, fixed, not the data's extent (kt:133-140). */
  minX: number = 0;
  maxX: number = 0;
  minY: number = 0;
  maxY: number = 0;
  /** endAxisItemPlacer's step - the spacing of the right-hand labels. */
  step: number = 1;
  /**
   * `SpecificVerticalAxisItemPlacer` — label at each of THESE values instead of on a uniform step.
   *
   * Only the air-quality chart uses one: its right-hand labels sit on the AQI or the pollutant's
   * band edges (DetailsAirQuality.kt:526-538), which are not evenly spaced. Empty everywhere else,
   * and the view falls back to `step`.
   */
  axisValues: number[] = [];
  /** Appended to each right-hand label, e.g. " hPa". */
  unitLabel: string = '';
  /** Right-hand labels are whole numbers unless the step is fractional. */
  decimals: number = 0;
  stops: ChartStop[] = [];
  /**
   * The trendHorizontalLines. Empty when the tag has none; wind has TWO (a Beaufort rule at each
   * end of the scale). Gated on screen 3c's setting by the view.
   */
  keyLines: ChartKeyLine[] = [];
  /** The top axis's trend arrows - only Pressure has them (DetailsPressure.kt:298-334). */
  arrows: ChartPoint[] = [];
  /** -1 down, 0 equal, +1 up, matching the three drawables the Kotlin picks between. */
  arrowKinds: number[] = [];
  /**
   * The top axis's WEATHER ICONS — the conditions chart's equivalent of Pressure's arrows.
   *
   * `TemperatureChart` (DetailsConditions.kt:834-905) gives the chart a
   * `topAxisSize = BaseAxis.Size.fixed(23.dp)` whose every label is an 18 dp icon for that hour,
   * `ResourceHelper.getWeatherIcon(provider, it, hourly.isDaylight)`. Same `TimeTopAxisItemPlacer`
   * as the arrows, so the same thinning rule decides how many fit.
   *
   * `x` is the hour; the kind and the daylight flag ride alongside, index for index.
   */
  topIcons: ChartPoint[] = [];
  topIconKinds: WeatherKind[] = [];
  topIconDaylight: boolean[] = [];
}

/**
 * Precipitation.kt:42-45 — the hourly intensity thresholds, in millimetres per hour. They are the
 * bar chart's axis floor and its three trendHorizontalLines.
 */
const PRECIPITATION_HOURLY_LIGHT: number = 5.0;
const PRECIPITATION_HOURLY_MEDIUM: number = 10.0;
const PRECIPITATION_HOURLY_HEAVY: number = 15.0;
/** `barColorFill = Fill(Color(60, 116, 160))` — DetailsPrecipitation.kt:377, and kt:621 for the line. */
const PRECIPITATION_BAR_COLOR: string = '#FF3C74A0';

/**
 * `SunImplementor.themeColor` = rgb(253, 188, 76), and the moon's is
 * `getBrighterColor(MeteorShowerImplementor.themeColor)`: rgb(20, 28, 44) taken to HSV, saturation
 * -0.25 and value +0.25, back to RGB (MaterialWeatherThemeDelegate.kt:38-44) = rgb(76, 87, 108).
 */
const SUN_LINE_COLOR: string = '#FFFDBC4C';
const MOON_LINE_COLOR: string = '#FF4C576C';

/**
 * The ephemeris chart's pair of gradients (DetailsSunMoon.kt:107-122).
 *
 * ONE colour, but two maps: the LINE keeps the colour above the horizon and drops to it at 50 %
 * below, while the AREA keeps it above and fades to nothing below. The stops sit at ±0.1°, so on a
 * -90..90 axis the change is a hard edge at the horizon rather than a wash.
 */
function scaleFill(lineStops: ChartStop[], areaStops: ChartStop[], color: string): void {
  lineStops.push(new ChartStop(0.1, color));
  lineStops.push(new ChartStop(-0.1, '#80' + color.substring(3)));
  areaStops.push(new ChartStop(0.1, color));
  areaStops.push(new ChartStop(-0.1, '#00000000'));
}

/**
 * `getMappedAstroValues` (DetailsSunMoon.kt:226-316) — the body's altitude at every noon and nadir
 * that can show on the chart.
 *
 * The Kotlin walks two sorted lists of rise and set instants: whichever comes first decides whether
 * the next sample is a noon (halfway from a rise to the following set) or a nadir (halfway from a
 * set to the following rise), and the altitude is computed THERE. The cubic connector does the rest,
 * which is why two samples a day are enough to draw the curve.
 *
 * Android is handed the lists by the view model; here they are scanned for the two days on each
 * side of the one being shown, which is more than the bookending needs and covers the moon's
 * ~50-minute daily drift.
 */
function mappedAstroValues(location: LocationModel, isSun: boolean, startMs: number,
  endMs: number): ChartPoint[] {
  const riseTimes: number[] = [];
  const setTimes: number[] = [];
  for (let day = -2; day <= 2; day++) {
    const at = new Date(startMs + day * DAY_MS);
    const times: RiseSet = isSun
      ? sunTimes(at, location.latitude, location.longitude, location.utcOffsetSeconds)
      : moonTimes(at, location.latitude, location.longitude, location.utcOffsetSeconds);
    if (times.rise !== null) {
      riseTimes.push(times.rise.getTime());
    }
    if (times.set !== null) {
      setTimes.push(times.set.getTime());
    }
  }
  riseTimes.sort((a: number, b: number) => a - b);
  setTimes.sort((a: number, b: number) => a - b);

  // kt:252-263 - bookend each list with one extra cycle so the first and last day look complete.
  if (riseTimes.length > 1 && setTimes.length > 1) {
    riseTimes.unshift(riseTimes[0] - (riseTimes[1] - riseTimes[0]));
    setTimes.unshift(setTimes[0] - (setTimes[1] - setTimes[0]));
    riseTimes.push(riseTimes[riseTimes.length - 1]
      + (riseTimes[riseTimes.length - 1] - riseTimes[riseTimes.length - 2]));
    setTimes.push(setTimes[setTimes.length - 1]
      + (setTimes[setTimes.length - 1] - setTimes[setTimes.length - 2]));
  }
  if (riseTimes.length === 0 || setTimes.length === 0) {
    return [];
  }

  // kt:265-295 - start at the last crossing before the day and stop at the first one after it.
  let riseCounter: number = 0;
  let setCounter: number = 0;
  while (riseCounter < riseTimes.length && riseTimes[riseCounter] < startMs) {
    riseCounter++;
  }
  if (riseCounter > 0) {
    riseCounter--;
  }
  while (setCounter < setTimes.length && setTimes[setCounter] < startMs) {
    setCounter++;
  }
  if (setCounter > 0) {
    setCounter--;
  }
  let riseLimit: number = riseTimes.length - 1;
  let setLimit: number = setTimes.length - 1;
  while (riseLimit >= 0 && riseTimes[riseLimit] > endMs) {
    riseLimit--;
  }
  if (riseLimit < riseTimes.length - 1) {
    riseLimit++;
  }
  while (setLimit >= 0 && setTimes[setLimit] > endMs) {
    setLimit--;
  }
  if (setLimit < setTimes.length - 1) {
    setLimit++;
  }

  const out: ChartPoint[] = [];
  while (riseCounter <= riseLimit && setCounter <= setLimit) {
    let at: number;
    if (riseTimes[riseCounter] < setTimes[setCounter]) {
      at = riseTimes[riseCounter] + Math.floor((setTimes[setCounter] - riseTimes[riseCounter]) / 2);
      riseCounter++;
    } else {
      at = setTimes[setCounter] + Math.floor((riseTimes[riseCounter] - setTimes[setCounter]) / 2);
      setCounter++;
    }
    const when = new Date(at);
    out.push(new ChartPoint(at, isSun
      ? sunAltitudeDegrees(when, location.latitude, location.longitude)
      : moonAltitudeDegrees(when, location.latitude, location.longitude)));
  }
  return out;
}

/** `roundUpToNearestMultiplier` / `roundDownToNearestMultiplier`. */
function roundUpTo(value: number, multiple: number): number {
  return Math.ceil(value / multiple) * multiple;
}

function roundDownTo(value: number, multiple: number): number {
  return Math.floor(value / multiple) * multiple;
}

/** DistanceUnit.KILOMETER.chartStep - 5 below 4 km, 10 above. */
function distanceChartStep(maxYKm: number): number {
  return maxYKm < 4 ? 5 : 10;
}

/**
 * The chart for a tag, or null when the tag has no line chart.
 *
 * `CHART_MIN_COUNT` is 2 (DetailScreen.kt:50): with fewer points the Kotlin swaps the chart for the
 * "not enough hourly data" row, which is what a null return means here.
 *
 * Pollen and Sun & moon are null because their screens use different widgets entirely - a bar list
 * and an EphemerisChart - neither of which is this component.
 */
export function detailsChart(
  location: LocationModel,
  screen: DetailScreen,
  dayIndex: number,
  /** The air-quality screen's picked pollutant, "" for the index itself. Ignored by every other tag. */
  pollutantId: string = '',
  /**
   * Which chart of the screen this is.
   *
   * Precipitation is the one tag that draws TWO: the quantity bar chart, then, under its own
   * heading, the probability line chart (DetailsPrecipitation.kt:166-213). 0 is the first, 1 the
   * second; every other tag ignores it.
   */
  variant: number = 0
): DetailsChartSpec | null {
  const weather = location.weather;
  if (weather === null || dayIndex < 0 || dayIndex >= weather.dailyForecast.length) {
    return null;
  }
  const offset: number = location.utcOffsetSeconds;
  const hours: Hourly[] = hoursForDay(location, dayIndex);
  const spec = new DetailsChartSpec();
  spec.minX = localStartOfDay(weather.dailyForecast[dayIndex].date, offset);
  spec.maxX = spec.minX + DAY_MS;

  const raw: number[] = values(hours, screen);
  const stops: ChartStop[] = [];

  /*
   * VARIANT 1 IS THE SECOND GROUP — which chart that is depends on the tag.
   *
   * Three screens close with a second heading, header and chart. On Precipitation (kt:166-213) and
   * on CONDITIONS (DetailsConditions.kt:360-405) it is the probability group; on HUMIDITY it is the
   * DEW POINT group (DetailsHumidity.kt:176-216), which sits between the two About cards rather
   * than after them.
   */
  if (variant === 1 && screen === DetailScreen.TAG_HUMIDITY) {
    /*
     * `DewPointChart` (DetailsHumidity.kt:449-523) — a temperature line on the temperature ramp,
     * bounds rounded out to the unit's chart step, exactly like the Conditions chart. The Kotlin
     * shares the colour table with a TODO saying so.
     */
    for (const hour of hours) {
      if (hour.dewPoint !== null) {
        spec.points.push(new ChartPoint(hour.date.getTime(), temperatureValue(hour.dewPoint)));
      }
    }
    if (spec.points.length < CHART_MIN_COUNT) {
      return null;
    }
    spec.step = temperatureChartStep();
    spec.unitLabel = temperatureUnitLabel();
    const values: number[] = pointYs(spec.points);
    spec.maxY = roundUpTo(maxOf(values), spec.step);
    spec.minY = roundDownTo(minOf(values), spec.step);
    if (spec.maxY === spec.minY) {
      spec.maxY = spec.minY + spec.step;
    }
    pushTemperatureStops(stops);
    spec.stops = stops;
    return spec;
  }
  if (variant === 1) {
    /*
     * An ordinary line chart, 0-100 %, every 20 %, and the one chart in the app whose "gradient" is
     * a single colour top and bottom, which the Kotlin marks with a TODO of its own (kt:620-623).
     */
    for (const hour of hours) {
      const probability = hour.precipitationProbability;
      if (probability !== null && probability.total !== null) {
        spec.points.push(new ChartPoint(hour.date.getTime(), probability.total));
      }
    }
    if (spec.points.length < CHART_MIN_COUNT) {
      return null;
    }
    spec.step = 20;
    spec.minY = 0;
    spec.maxY = 100;
    spec.unitLabel = '%';
    stops.push(new ChartStop(100, PRECIPITATION_BAR_COLOR));
    stops.push(new ChartStop(0, PRECIPITATION_BAR_COLOR));
    spec.stops = stops;
    // The right-hand labels carry a decimal only when the step itself does; 20 does not.
    spec.decimals = 0;
    return spec;
  }

  switch (screen) {
    case DetailScreen.TAG_PRECIPITATION: {
      /*
       * PrecipitationChart (kt:339-415) — the one COLUMN chart on screen 4, and the reason
       * `BreezyBarChart` exists at all. Everything else about it is the line charts' furniture.
       */
      for (const hour of hours) {
        if (hour.precipitationTotal !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(),
            precipitationValue(hour.precipitationTotal)));
        }
      }
      if (spec.points.length === 0) {
        return null;
      }
      spec.bars = true;
      spec.barColor = PRECIPITATION_BAR_COLOR;
      spec.step = precipitationChartStep();
      spec.unitLabel = ' ' + precipitationUnitLabel();
      // kt:349-354 — a floor of PRECIPITATION_HOURLY_HEAVY so a dry day still gets a usable axis.
      const heavy: number = precipitationValue(PRECIPITATION_HOURLY_HEAVY);
      spec.minY = 0;
      spec.maxY = roundUpTo(Math.max(heavy, maxOf(pointYs(spec.points))), spec.step);
      /*
       * kt:391-411 — the "Heavy" rule always, and the "Medium" and "Light" ones only while the axis
       * has not run past twice heavy, where three labels would crowd the bottom of the plot.
       */
      spec.keyLines.push(new ChartKeyLine(heavy, 'Heavy')); // precipitation_intensity_heavy
      if (spec.maxY < precipitationValue(PRECIPITATION_HOURLY_HEAVY * 2)) {
        spec.keyLines.push(
          new ChartKeyLine(precipitationValue(PRECIPITATION_HOURLY_MEDIUM), 'Moderate'));
        spec.keyLines.push(
          new ChartKeyLine(precipitationValue(PRECIPITATION_HOURLY_LIGHT), 'Light'));
      }
      break;
    }
    case DetailScreen.TAG_SUN_MOON: {
      /*
       * EphemerisChart (EphemerisChart.kt:72-159, fed by DetailsSunMoon.kt:152-224).
       *
       * Not a weather series at all: it plots the sun's and the moon's ALTITUDE in degrees over the
       * day, sampled at each body's noon and nadir and joined by a cubic connector, on a fixed
       * -90..90 axis labelled only at 0 and 90.
       */
      const sun: ChartPoint[] = mappedAstroValues(location, true, spec.minX, spec.maxX);
      const moon: ChartPoint[] = mappedAstroValues(location, false, spec.minX, spec.maxX);
      if (sun.length < CHART_MIN_COUNT && moon.length < CHART_MIN_COUNT) {
        return null;
      }
      spec.curved = true;
      spec.minY = -90;
      spec.maxY = 90;
      // "90 is the zenith, but add a safe-zone" (kt:84-90); the labels sit at 0 and 90 only.
      spec.axisValues.push(0);
      spec.axisValues.push(90);
      spec.step = 90;
      // The formatter is TemperatureUnit.CELSIUS at NARROW width — the Kotlin calls it a hack.
      spec.unitLabel = '°';
      if (sun.length < CHART_MIN_COUNT) {
        // A body that never rises contributes no noon or nadir; the Kotlin then plots the other
        // one alone, in its own colour (kt:182-193 adds each series only when it has values).
        spec.points = moon;
        scaleFill(stops, spec.areaStops, MOON_LINE_COLOR);
      } else {
        // The sun is the LAST series the Kotlin adds, so it draws over the moon.
        spec.points = sun;
        spec.points2 = moon;
        scaleFill(stops, spec.areaStops, SUN_LINE_COLOR);
        scaleFill(spec.stops2, spec.areaStops2, MOON_LINE_COLOR);
      }
      break;
    }
    case DetailScreen.TAG_PRESSURE: {
      for (const hour of hours) {
        if (hour.pressure !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), pressureValue(hour.pressure)));
        }
      }
      // PressureUnit.HECTOPASCAL.chartStep, and STANDARD = 101325 Pa.
      spec.step = 15;
      const standard: number = 1013.25;
      spec.unitLabel = ' ' + pressureUnitLabel();
      spec.keyLines.push(new ChartKeyLine(standard, 'Standard')); // strings.xml:355
      // DetailsPressure.kt:234-245 - the standard pressure - 1.6 steps is always in range.
      const dataMax: number = spec.points.length > 0 ? maxOf(pointYs(spec.points)) : standard;
      const dataMin: number = spec.points.length > 0 ? minOf(pointYs(spec.points)) : standard;
      spec.maxY = roundUpTo(Math.max(standard + spec.step * 1.6, dataMax), spec.step);
      spec.minY = roundDownTo(Math.min(standard - spec.step * 1.6, dataMin), spec.step);
      // kt:271-291, hPa.
      stops.push(new ChartStop(1080, '#FF300818'));
      stops.push(new ChartStop(1046, '#FF6F1840'));
      stops.push(new ChartStop(1038, '#FF8E2F39'));
      stops.push(new ChartStop(1030, '#FF9F512C'));
      stops.push(new ChartStop(1024, '#FFA37443'));
      stops.push(new ChartStop(1019, '#FFA7936B'));
      stops.push(new ChartStop(1015.25, '#FFB0AE98'));
      stops.push(new ChartStop(1013.25, '#FFB6B6B6'));
      stops.push(new ChartStop(1011.25, '#FF9BB7AC'));
      stops.push(new ChartStop(1007, '#FF67A29B'));
      stops.push(new ChartStop(1002, '#FF1A8C93'));
      stops.push(new ChartStop(995, '#FF007592'));
      stops.push(new ChartStop(986, '#FF005A94'));
      stops.push(new ChartStop(976, '#FF003492'));
      stops.push(new ChartStop(950, '#FF002060'));
      stops.push(new ChartStop(900, '#FF081030'));
      buildPressureArrows(spec, hours);
      break;
    }
    case DetailScreen.TAG_HUMIDITY: {
      for (const hour of hours) {
        if (hour.relativeHumidity !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), hour.relativeHumidity));
        }
      }
      spec.step = 20; // RatioUnit.PERCENT.chartStep
      spec.maxY = 100;
      spec.minY = 0;
      spec.unitLabel = '%';
      // DetailsHumidity.kt:331-345.
      stops.push(new ChartStop(100, '#FF384672'));
      stops.push(new ChartStop(97, '#FF38629D'));
      stops.push(new ChartStop(93, '#FF387BAD'));
      stops.push(new ChartStop(90, '#FF3884AD'));
      stops.push(new ChartStop(87, '#FF3887AD'));
      stops.push(new ChartStop(83, '#FF3894AD'));
      stops.push(new ChartStop(80, '#FF389DAD'));
      stops.push(new ChartStop(75, '#FF38A0AD'));
      stops.push(new ChartStop(70, '#FF38AEAD'));
      stops.push(new ChartStop(60, '#FF38AD79'));
      stops.push(new ChartStop(50, '#FF69AD38'));
      stops.push(new ChartStop(40, '#FFAD9238'));
      stops.push(new ChartStop(30, '#FFAD6E38'));
      stops.push(new ChartStop(0, '#FFAD5538'));
      break;
    }
    case DetailScreen.TAG_CLOUD_COVER: {
      for (const hour of hours) {
        if (hour.cloudCover !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), hour.cloudCover));
        }
      }
      spec.step = 20;
      spec.maxY = 100;
      spec.minY = 0;
      spec.unitLabel = '%';
      // DetailsCloudCover.kt:288-294.
      stops.push(new ChartStop(100, '#FFD5D5CD'));
      stops.push(new ChartStop(98, '#FFC6C9C9'));
      stops.push(new ChartStop(95, '#FFABB4B3'));
      stops.push(new ChartStop(50, '#FF747474'));
      stops.push(new ChartStop(10, '#FF847746'));
      stops.push(new ChartStop(0, '#FF928246'));
      break;
    }
    case DetailScreen.TAG_VISIBILITY: {
      for (const hour of hours) {
        if (hour.visibility !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), distanceValue(hour.visibility)));
        }
      }
      // kt:288-300 - a floor of 22 850 m so the axis is at least ~75 000 ft once rounded.
      const floorKm: number = distanceValue(22850);
      const dataMax: number = spec.points.length > 0 ? maxOf(pointYs(spec.points)) : floorKm;
      const rawMax: number = Math.max(floorKm, dataMax);
      spec.step = distanceChartStep(rawMax);
      spec.maxY = roundUpTo(rawMax, spec.step);
      spec.minY = 0;
      spec.unitLabel = ' ' + distanceUnitLabel();
      // kt:327-336, metres converted to the display unit.
      stops.push(new ChartStop(distanceValue(20000), '#FF778D78'));
      stops.push(new ChartStop(distanceValue(15000), '#FF5BA763'));
      stops.push(new ChartStop(distanceValue(9000), '#FF5AA95A'));
      stops.push(new ChartStop(distanceValue(8000), '#FF627AA0'));
      stops.push(new ChartStop(distanceValue(6000), '#FF627AA0'));
      stops.push(new ChartStop(distanceValue(5000), '#FFA75B5B'));
      stops.push(new ChartStop(distanceValue(2200), '#FFA75B5B'));
      stops.push(new ChartStop(distanceValue(1600), '#FFA261A0'));
      stops.push(new ChartStop(0, '#FFA65DA5'));
      break;
    }
    case DetailScreen.TAG_UV_INDEX: {
      for (const hour of hours) {
        if (hour.uvIndex !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), hour.uvIndex));
        }
      }
      // kt:251-257 - always at least the "high" threshold, else the peak rounded up by one.
      const dataMax: number = spec.points.length > 0 ? maxOf(pointYs(spec.points)) : 0;
      spec.maxY = Math.max(UV_INDEX_HIGH, Math.round(dataMax) + 1);
      spec.minY = 0;
      spec.step = 1; // "every rounded UVI"
      spec.unitLabel = '';
      spec.keyLines.push(new ChartKeyLine(UV_INDEX_MIDDLE, 'Alert')); // `uv_alert_level`
      // kt:286-293.
      stops.push(new ChartStop(19, '#FFFFFFFF'));
      stops.push(new ChartStop(11, COLOR_LEVEL_5));
      stops.push(new ChartStop(10, COLOR_LEVEL_4));
      stops.push(new ChartStop(7, COLOR_LEVEL_3));
      stops.push(new ChartStop(5, COLOR_LEVEL_2));
      stops.push(new ChartStop(2, COLOR_LEVEL_1));
      stops.push(new ChartStop(0, '#FF6E6E6E'));
      break;
    }
    case DetailScreen.TAG_WIND: {
      /*
       * WindChart (DetailsWind.kt:336-490).
       *
       * ONE series, not two. The Kotlin adds a second for gusts (kt:359-366), but neither port's
       * `Hourly` carries gusts — only `Current` does — so there is nothing to plot. Same in both
       * ports, so the comparison stays like-for-like; it is a data-layer gap, not a chart one.
       */
      for (const hour of hours) {
        if (hour.windSpeed !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), speedValue(hour.windSpeed)));
        }
      }
      if (spec.points.length === 0) {
        return null;
      }
      spec.step = speedChartStep();
      spec.unitLabel = ' ' + speedUnitLabel();
      // kt:339-347 — a floor of 15 m/s so a calm day still gets a usable axis.
      spec.maxY = roundUpTo(Math.max(speedValue(15), maxOf(pointYs(spec.points))), spec.step);
      spec.minY = 0;
      /*
       * kt:477-485 — a Beaufort rule at each end, each labelled with its strength name. Beaufort 7
       * is 13.9 m/s and Beaufort 3 is 3.4 m/s (the WIND_SPEED_* table, held in cm/s).
       */
      const bf7: number = speedValue(13.9);
      const bf3: number = speedValue(3.4);
      if (spec.maxY > bf7) {
        spec.keyLines.push(new ChartKeyLine(bf7, 'Moderate gale')); // wind_strength_7
      }
      if (spec.maxY < speedValue(18.9)) {
        spec.keyLines.push(new ChartKeyLine(bf3, 'Gentle breeze')); // wind_strength_3
      }
      // kt:383-416, metres per second converted to the display unit; colors.xml windStrength_bf*.
      const w = (ms: number): number => speedValue(ms);
      stops.push(new ChartStop(w(104), '#FF808080'));
      stops.push(new ChartStop(w(77), '#FFCDCA70'));
      stops.push(new ChartStop(w(51), '#FFDBD487'));
      stops.push(new ChartStop(w(46), '#FFE7D7D7'));
      stops.push(new ChartStop(w(36), '#FF7D44A5'));
      stops.push(new ChartStop(w(30.5), '#FF5C9098'));
      stops.push(new ChartStop(w(26.4), '#FF44698D'));
      stops.push(new ChartStop(w(24.475), '#FF6D61A3'));
      stops.push(new ChartStop(w(22.55), '#FF754A93'));
      stops.push(new ChartStop(w(18.9), '#FFAF5088'));
      stops.push(new ChartStop(w(17.175), '#FF813A4E'));
      stops.push(new ChartStop(w(15.45), '#FFA1645C'));
      stops.push(new ChartStop(w(13.85), '#FF9F7F3A'));
      stops.push(new ChartStop(w(12.25), '#FFA79D51'));
      stops.push(new ChartStop(w(9.3), '#FF359F35'));
      stops.push(new ChartStop(w(6.7), '#FF53A553'));
      stops.push(new ChartStop(w(4.4), '#FF4D8D7B'));
      stops.push(new ChartStop(w(2.4), '#FF4A94A9'));
      stops.push(new ChartStop(w(1.0), '#FF39619F'));
      stops.push(new ChartStop(0, '#FF6271B7'));
      break;
    }
    case DetailScreen.TAG_CONDITIONS:
    case DetailScreen.TAG_FEELS_LIKE: {
      /*
       * TemperatureChart (DetailsConditions.kt:769-905). This is the screen every daily and hourly
       * trend column opens, so it is the one that most needed a chart.
       *
       * `showRealTemp` is which of the two tags it is. Feels like plots the feels-like temperature
       * AND the actual one behind it in flat grey (kt:869-872); Conditions plots one line.
       */
      const real: boolean = screen === DetailScreen.TAG_CONDITIONS;
      for (const hour of hours) {
        const temp = hour.temperature;
        if (temp === null) {
          continue;
        }
        const shown: number | null = real ? temp.temperature : temp.feelsLikeTemperature;
        if (shown !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), temperatureValue(shown)));
        }
        if (!real && temp.temperature !== null) {
          spec.points2.push(new ChartPoint(hour.date.getTime(), temperatureValue(temp.temperature)));
        }
        // kt:857-866 — the top axis is an icon per hour, the same placer as Pressure's arrows.
        if (hour.weatherKind !== WeatherKind.NULL) {
          spec.topIcons.push(new ChartPoint(hour.date.getTime(), 0));
          spec.topIconKinds.push(hour.weatherKind);
          spec.topIconDaylight.push(hour.daylight);
        }
      }
      spec.step = temperatureChartStep();
      spec.unitLabel = temperatureUnitLabel();
      /*
       * kt:781-810 pulls the bounds out to the monthly NORMALS as well. Neither port has normals:
       * ArkUIApp leaves `weather.normals` null on purpose (Open-Meteo is not a normals source,
       * WeatherRepository.ets:288) and the NDK model has no such field, so the "Normal" key lines
       * never appear in either. That is scope, not an omission — and it is why the bounds here are
       * the data's own, rounded out to the step.
       */
      const all: number[] = pointYs(spec.points).concat(pointYs(spec.points2));
      if (all.length === 0) {
        return null;
      }
      spec.maxY = roundUpTo(maxOf(all), spec.step);
      spec.minY = roundDownTo(minOf(all), spec.step);
      if (spec.maxY === spec.minY) {
        spec.maxY = spec.minY + spec.step;
      }
      pushTemperatureStops(stops);
      break;
    }
    case DetailScreen.TAG_AIR_QUALITY: {
      /*
       * AirQualityChart (DetailsAirQuality.kt:438-540). The plotted value is the INDEX with no
       * pollutant picked and that pollutant's CONCENTRATION with one, so the axis changes with the
       * selection — which is why the chart could not be ported before the picker was.
       */
      const def: PollutantDef | null = pollutantById(pollutantId);
      for (const hour of hours) {
        const air: AirQualityConcentrations | null = hour.airQuality;
        if (air === null) {
          continue;
        }
        const value: number | null = def === null
          ? overallIndexOf(air)
          : concentrationOf(air, def.id);
        if (value !== null) {
          spec.points.push(new ChartPoint(hour.date.getTime(), value));
        }
      }
      if (spec.points.length === 0) {
        return null;
      }
      const bands: number[] = def === null ? AQI_THRESHOLDS : def.thresholds;
      /*
       * kt:447-458 — the floor is the pollutant's own `maxY`, or aqiThresholds[4] = 150 for the
       * index, raised to the data's peak when that is higher. Concentrations are rounded up to a
       * whole unit first (`roundUpToNearestMultiplier(1.0)`).
       */
      const peak: number = Math.ceil(maxOf(pointYs(spec.points)));
      spec.maxY = Math.max(def === null ? AQI_THRESHOLDS[4] : def.maxY, peak);
      spec.minY = 0;
      spec.unitLabel = def === null ? '' : ' ' + concentrationUnitLabel(def);
      /*
       * `SpecificVerticalAxisItemPlacer` (kt:526-538): the labels sit on the BAND EDGES, not on a
       * uniform step, with the axis maximum appended when the data ran past the last band.
       */
      for (const band of bands) {
        if (band <= spec.maxY) {
          spec.axisValues.push(band);
        }
      }
      if (spec.maxY > bands[bands.length - 1]) {
        spec.axisValues.push(spec.maxY);
      }
      spec.step = bands.length > 1 ? bands[1] - bands[0] : 1;
      // kt:509-516 — every band edge takes its own level colour.
      for (let i = 0; i < bands.length; i++) {
        stops.push(new ChartStop(bands[i], AppColors.LEVEL_COLORS[i]));
      }
      // kt:518-521 — one rule, at the fourth band, labelled with that level's name.
      spec.keyLines.push(new ChartKeyLine(bands[3], aqiLevelName(AQI_THRESHOLDS[3])));
      break;
    }
    default:
      // Pollen is a GRID, not a chart of any kind (DetailsPollen.kt:70-77), so it has none.
      return null;
  }

  if (spec.points.length < CHART_MIN_COUNT) {
    return null;
  }
  spec.stops = stops;
  // The right-hand labels carry a decimal only when the step itself does.
  spec.decimals = spec.step < 1 ? 1 : 0;
  /*
   * There used to be a second `if (raw.length === 0) return null` here, where `raw` came from
   * `values(hours, screen)`. It was redundant with the point count above AND wrong: `values()` has
   * no case for the two conditions tags, so it returned an empty list and killed the chart on the
   * screen every trend column opens. The point count is the only guard needed.
   */
  return spec;
}

/** DetailScreen.CHART_MIN_COUNT (kt:50). */
const CHART_MIN_COUNT: number = 2;

function pointYs(points: ChartPoint[]): number[] {
  const out: number[] = [];
  for (const point of points) {
    out.push(point.y);
  }
  return out;
}

/**
 * The top axis's trend arrows (DetailsPressure.kt:298-334).
 *
 * Each label compares its hour with the PREVIOUS one and picks up / down / equal, with a dead band
 * of 0.5 in the MODEL unit - the Kotlin compares `currentValue.value - previousValue.value`, which
 * is pascals-as-stored, so the comparison happens before any unit conversion. Which hours get an
 * arrow is TimeTopAxisItemPlacer's decision, reproduced in the view because it depends on the plot
 * width.
 */
function buildPressureArrows(spec: DetailsChartSpec, hours: Hourly[]): void {
  let previous: number | null = null;
  for (const hour of hours) {
    if (hour.pressure === null) {
      continue;
    }
    if (previous !== null) {
      const delta: number = hour.pressure - previous;
      spec.arrows.push(new ChartPoint(hour.date.getTime(), 0));
      spec.arrowKinds.push(delta >= 0.5 ? 1 : (delta <= -0.5 ? -1 : 0));
    }
    previous = hour.pressure;
  }
}

/** "%1$s to %2$s" (strings.xml:341/367/382) - the range summaries collapse when min == max. */
function rangeSummary(min: string, max: string): string {
  return min === max ? max : min + ' to ' + max;
}

function percent(value: number): string {
  return Math.round(value).toString() + '%';
}


/* ---------------------------------------------------------- the per-tag header ------------- */

/** strings.xml:327 / :329 - the two half-day labels every composite header uses. */
const DAYTIME: string = 'Daytime';
const NIGHTTIME: string = 'Nighttime';

/**
 * Wind.arrow - the eight-point glyph the Kotlin appends after the speed.
 *
 * Each carries U+FE0E, the TEXT presentation selector. Without it the device picks the emoji glyph
 * for the diagonals — the north-east arrow came out as a blue rounded square, next to a plain
 * black north arrow. The selector costs nothing where the text glyph is already the default.
 */
const WIND_ARROWS: string[] = [
  '\u2193\ufe0e', '\u2199\ufe0e', '\u2190\ufe0e', '\u2196\ufe0e',
  '\u2191\ufe0e', '\u2197\ufe0e', '\u2192\ufe0e', '\u2198\ufe0e'
];

function windArrow(degree: number | null): string {
  if (degree === null) {
    return '';
  }
  const index: number = Math.round(((degree % 360) + 360) % 360 / 45) % 8;
  // The arrow points where the wind is GOING, which is the reciprocal of the reported bearing.
  return WIND_ARROWS[index];
}

function column(label: string, value: string, unit: string = '', description: string = '',
  dotColor: string = '', iconKind: WeatherKind | null = null,
  iconDaylight: boolean = true, descriptionLine: number = 0,
  valueSuffix: string = '', valueLevel: string = ''): SummaryColumn {
  const out = new SummaryColumn();
  out.label = label;
  out.value = value;
  out.unit = unit;
  out.description = description;
  out.dotColor = dotColor;
  out.iconKind = iconKind;
  out.iconDaylight = iconDaylight;
  // A tag that has a third line reserves it even when the text is empty; a tag that has none
  // leaves this 0 and the column is two lines tall.
  out.descriptionLine = descriptionLine !== 0 ? descriptionLine
    : (description.length > 0 || iconKind !== null ? LineHeights.LABEL_MEDIUM : 0);
  out.valueSuffix = valueSuffix;
  out.valueLevel = valueLevel;
  return out;
}

/**
 * The header above the chart, per tag.
 *
 * Each branch is the "<Tag>Header" composable with `activeItem` null - the port has no chart marker
 * yet, so the day's own summary is always what shows, which is the middle branch of every one of
 * them (e.g. PressureHeader's `daily.pressure?.average != null`).
 */
export function detailsSummary(
  location: LocationModel,
  screen: DetailScreen,
  dayIndex: number,
  now: Date,
  activeHourMs: number = -1,
  pollutantId: string = '',
  /** Precipitation's second header, the probability one (kt:506-524). 0 everywhere else. */
  variant: number = 0
): DetailsSummary {
  const summary = new DetailsSummary();
  const weather = location.weather;
  if (weather === null || dayIndex < 0 || dayIndex >= weather.dailyForecast.length) {
    return summary;
  }
  const daily: Daily = weather.dailyForecast[dayIndex];
  const hours: Hourly[] = hoursForDay(location, dayIndex);
  const label: string = dayFullLabel(location, daily, now);

  /*
   * The chart MARKER — every `<Tag>Header` opens with `if (activeItem != null)`, and until now this
   * port could never take that branch, so all twelve were permanently in their day-summary
   * fallback. Touching the chart now supplies the hour, and the header shows THAT hour's reading
   * labelled with its time (e.g. PressureHeader kt:172-176).
   */
  if (activeHourMs >= 0) {
    const active: SummaryColumn | null =
      activeColumn(location, screen, hours, activeHourMs, pollutantId, variant);
    if (active !== null) {
      summary.columns.push(active);
      return summary;
    }
  }

  /*
   * VARIANT 1 IS THE SECOND GROUP'S HEADER — see the same note in `detailsChart`.
   *
   * On HUMIDITY that is `DewPointSummary` (DetailsHumidity.kt:394-421): the same day label as the
   * humidity header, over the day's dew-point RANGE at displaySmall.
   */
  if (variant === 1 && screen === DetailScreen.TAG_HUMIDITY) {
    const dew: number[] = [];
    for (const hour of hours) {
      if (hour.dewPoint !== null) {
        dew.push(hour.dewPoint);
      }
    }
    summary.columns.push(dew.length > 0
      ? column(label, rangeSummary(formatTemperatureShortNarrow(minOf(dew)),
        formatTemperatureShortNarrow(maxOf(dew))))
      : column(label, ''));
    return summary;
  }

  /*
   * `PrecipitationProbabilitySummary` (DetailsPrecipitation.kt:552-585) serves the Precipitation
   * screen's second group AND the Conditions screen's closing one (DetailsConditions.kt:376-386).
   */
  if (variant === 1) {
    summary.columns.push(halfDayPrecipitationProbability(daily.day, DAYTIME));
    summary.columns.push(halfDayPrecipitationProbability(daily.night, NIGHTTIME));
    return summary;
  }

  switch (screen) {
    case DetailScreen.TAG_PRESSURE: {
      const list: number[] = values(hours, DetailScreen.TAG_PRESSURE);
      // PressureHeader (kt:177-181) labels the day's figure "Average" - chart_average, :46.
      summary.columns.push(list.length > 0
        ? column('Average', formatPressure(mean(list)), ' ' + pressureUnitLabel())
        : column('Average', ''));
      break;
    }
    case DetailScreen.TAG_HUMIDITY: {
      const list: number[] = values(hours, DetailScreen.TAG_HUMIDITY);
      summary.columns.push(list.length > 0
        ? column(label, rangeSummary(percent(minOf(list)), percent(maxOf(list))))
        : column(label, ''));
      break;
    }
    /*
     * Cloud cover and visibility are the two scalar tags with a THIRD line, and `CloudCoverItem`
     * (kt:209-233) / `VisibilityItem` (kt:205-236) stack three UNCONDITIONAL `TextFixedHeight`s —
     * so the line is 16 dp tall on a day with no reading too. The ports only reserved it when
     * there was text, which lost 52 px on an empty day.
     */
    case DetailScreen.TAG_CLOUD_COVER: {
      const list: number[] = values(hours, DetailScreen.TAG_CLOUD_COVER);
      if (list.length > 0) {
        const min: number = minOf(list);
        const max: number = maxOf(list);
        summary.columns.push(column(label, rangeSummary(percent(min), percent(max)), '',
          rangeSummary(cloudCoverDescription(min), cloudCoverDescription(max))));
      } else {
        summary.columns.push(column(label, '', '', '', '', null, true, LineHeights.LABEL_MEDIUM));
      }
      break;
    }
    case DetailScreen.TAG_VISIBILITY: {
      const list: number[] = values(hours, DetailScreen.TAG_VISIBILITY);
      if (list.length > 0) {
        const min: number = minOf(list);
        const max: number = maxOf(list);
        summary.columns.push(column(label,
          rangeSummary(formatDistance(min), formatDistance(max)), ' ' + distanceUnitLabel(),
          rangeSummary(visibilityDescription(min), visibilityDescription(max))));
      } else {
        summary.columns.push(column(label, '', '', '', '', null, true, LineHeights.LABEL_MEDIUM));
      }
      break;
    }
    case DetailScreen.TAG_UV_INDEX: {
      // UVHeader (kt:184-188) - the day's PEAK, labelled "Maximum value" (:150 -> :47).
      const peak: number | null = daily.uvIndex;
      summary.columns.push(peak !== null
        // kt:220-237 — the level rides IN the value line at headlineSmall, not on a third one.
        ? column('Maximum value', formatDecimals(peak, 1), '', '', uvLevelColor(peak), null, true,
          0, '', uvLevelName(peak))
        : column('Maximum value', ''));
      break;
    }
    case DetailScreen.TAG_AIR_QUALITY: {
      /*
       * AirQualityHeader (kt:345-374) - "Average", a dot in the reading's colour, then either the
       * index and its level name ("36 Fair") or, when a pollutant is picked, that pollutant's
       * concentration and the level THAT falls in ("14 ug/m3 Fair").
       */
      const air: AirQualityConcentrations | null = selectedAirQuality(location, dayIndex);
      summary.columns.push(airQualityColumn('Average', air, pollutantId));
      break;
    }
    case DetailScreen.TAG_WIND: {
      // WindSummary (kt:224-262) - a Daytime column and a Nighttime one, side by side.
      summary.columns.push(halfDayWind(daily.day, DAYTIME));
      summary.columns.push(halfDayWind(daily.night, NIGHTTIME));
      break;
    }
    case DetailScreen.TAG_PRECIPITATION: {
      // PrecipitationSummary (kt:299-337).
      summary.columns.push(halfDayPrecipitation(daily.day, DAYTIME));
      summary.columns.push(halfDayPrecipitation(daily.night, NIGHTTIME));
      break;
    }
    case DetailScreen.TAG_CONDITIONS:
    case DetailScreen.TAG_FEELS_LIKE: {
      // WeatherConditionSummary (kt:494-551), with `showRealTemp` being which of the two tags it is.
      const real: boolean = screen === DetailScreen.TAG_CONDITIONS;
      summary.columns.push(halfDayCondition(daily.day, DAYTIME, real, true));
      summary.columns.push(halfDayCondition(daily.night, NIGHTTIME, real, false));
      break;
    }
    case DetailScreen.TAG_POLLEN:
    case DetailScreen.TAG_SUN_MOON:
    default:
      // Neither screen has a summary header: both lead with a card of their own (kt:104-126 and
      // DetailsPollen.kt:55-77), which `detailsSections` produces.
      break;
  }
  return summary;
}

/**
 * The header for ONE hour, when the chart marker is up.
 *
 * The value is that hour's reading and the label is its time - `activeItem.first.getFormattedTime`
 * in every `<Tag>Header`. Returns null when the tag has no per-hour reading, which leaves the day
 * summary in place.
 */
function activeColumn(location: LocationModel, screen: DetailScreen, hours: Hourly[],
  activeHourMs: number, pollutantId: string = '', variant: number = 0): SummaryColumn | null {
  let hour: Hourly | null = null;
  for (const candidate of hours) {
    if (candidate.date.getTime() === activeHourMs) {
      hour = candidate;
      break;
    }
  }
  if (hour === null) {
    return null;
  }
  const at: string = getHour(hour.date, location.utcOffsetSeconds);
  // Variant 1 is the probability group's marker, on Precipitation and on Conditions alike.
  if (variant === 1) {
    const probability = hour.precipitationProbability;
    return probability === null || probability.total === null ? null
      : column(at, percent(probability.total));
  }
  switch (screen) {
    case DetailScreen.TAG_PRESSURE:
      return hour.pressure === null ? null
        : column(at, formatPressure(hour.pressure), ' ' + pressureUnitLabel());
    case DetailScreen.TAG_HUMIDITY:
      return hour.relativeHumidity === null ? null : column(at, percent(hour.relativeHumidity));
    case DetailScreen.TAG_CLOUD_COVER:
      return hour.cloudCover === null ? null
        : column(at, percent(hour.cloudCover), '', cloudCoverDescription(hour.cloudCover));
    case DetailScreen.TAG_VISIBILITY:
      return hour.visibility === null ? null
        : column(at, formatDistance(hour.visibility), ' ' + distanceUnitLabel(),
          visibilityDescription(hour.visibility));
    case DetailScreen.TAG_UV_INDEX:
      return hour.uvIndex === null ? null
        : column(at, formatDecimals(hour.uvIndex, 1), '', '', uvLevelColor(hour.uvIndex), null,
          true, 0, '', uvLevelName(hour.uvIndex));
    case DetailScreen.TAG_WIND:
      return hour.windSpeed === null ? null
        : column(at, formatSpeed(hour.windSpeed), ' ' + speedUnitLabel(),
          windArrow(hour.windDegree));
    case DetailScreen.TAG_CONDITIONS:
    case DetailScreen.TAG_FEELS_LIKE: {
      const temp = hour.temperature;
      if (temp === null) {
        return null;
      }
      const real: boolean = screen === DetailScreen.TAG_CONDITIONS;
      const shown: number | null = real ? temp.temperature : temp.feelsLikeTemperature;
      if (shown === null) {
        return null;
      }
      const description: string = real
        ? (hour.weatherText === null ? '' : hour.weatherText)
        : (temp.temperature === null ? ''
          : 'Actual' + COLON_SEPARATOR + formatTemperatureWithUnit(temp.temperature));
      /*
       * kt:220-233 — the MARKER column is the same `WeatherConditionItem`, so it carries the
       * hour's own icon and the same one-decimal narrow value as the day summary does.
       */
      const hourIcon: WeatherKind | null =
        real && hour.weatherKind !== WeatherKind.NULL ? hour.weatherKind : null;
      return column(at, formatTemperatureShortNarrow(shown), '', description, '', hourIcon,
        hour.daylight);
    }
    case DetailScreen.TAG_AIR_QUALITY:
      return hour.airQuality === null ? null
        : airQualityColumn(at, hour.airQuality, pollutantId);
    case DetailScreen.TAG_PRECIPITATION: {
      return hour.precipitationTotal === null ? null
        : column(at, formatPrecipitation(hour.precipitationTotal),
          ' ' + precipitationUnitLabel());
    }
    default:
      return null;
  }
}

/**
 * `AirQualityItem` (DetailsAirQuality.kt:376-434) — the dot, the reading and the level name, for
 * either the index or one pollutant's concentration.
 */
function airQualityColumn(
  label: string,
  air: AirQualityConcentrations | null,
  pollutantId: string
): SummaryColumn {
  if (air === null) {
    return column(label, '');
  }
  const def: PollutantDef | null = pollutantById(pollutantId);
  if (def === null) {
    const index: number | null = overallIndexOf(air);
    return index === null
      ? column(label, '')
      : column(label, Math.round(index).toString(), '', '', aqiLevelColor(index), null, true, 0,
        '', aqiLevelName(index));
  }
  const concentration: number | null = concentrationOf(air, def.id);
  const index: number | null = pollutantIndexOf(def, concentration);
  if (concentration === null || index === null) {
    return column(label, '');
  }
  // The unit rides a font size down, as `formatUnitsDifferentFontSize` renders it (kt:409-414).
  return column(label, Math.round(concentration).toString(),
    ' ' + concentrationUnitLabel(def), '', aqiLevelColor(index), null, true, 0, '',
    aqiLevelName(index));
}

/**
 * One half-day's wind column — `WindItem`, DetailsWind.kt:262-325.
 *
 * The value is speed + unit + " " + arrow, all on ONE displaySmall line (kt:274-302), and the
 * third line is the gusts at labelLarge — drawn only when there are gusts AND they exceed the
 * speed (kt:303), but the line is RESERVED either way so the two columns line up.
 * Measured on the reference: 52 + 143 + 65 px, and the port drew 46 + 137 + 46 with the arrow
 * where the gusts belong.
 */
function halfDayWind(half: HalfDay | null, label: string): SummaryColumn {
  if (half === null || half.windSpeed === null) {
    return column(label, '', '', '', '', null, true, LineHeights.LABEL_LARGE);
  }
  const gusts: string = half.windGusts !== null && half.windGusts > half.windSpeed
    ? WIND_GUSTS_SHORT + COLON_SEPARATOR + formatSpeed(half.windGusts) + ' ' + speedUnitLabel()
    : '';
  return column(label, formatSpeed(half.windSpeed), ' ' + speedUnitLabel(), gusts, '', null, true,
    LineHeights.LABEL_LARGE, ' ' + windArrow(half.windDegree));
}

function halfDayPrecipitation(half: HalfDay | null, label: string): SummaryColumn {
  if (half === null || half.precipitationTotal === null) {
    return column(label, '');
  }
  return column(label, formatPrecipitation(half.precipitationTotal), ' ' + precipitationUnitLabel());
}

/** `PrecipitationProbabilityItem` (kt:527-550) — a plain percentage, no unit beside it. */
function halfDayPrecipitationProbability(half: HalfDay | null, label: string): SummaryColumn {
  const probability = half === null ? null : half.precipitationProbability;
  if (probability === null || probability.total === null) {
    return column(label, '');
  }
  return column(label, percent(probability.total));
}

/**
 * One row of a two-column detail block: the same label with the daytime value beside the nighttime
 * one.
 *
 * `PrecipitationDetails` (kt:418-475) and its two siblings build a Daytime column and a Nighttime
 * column of `DetailsItem`s from the SAME list of labels, and draw the block at all only when that
 * list is non-empty — which is how a source that reports no snow shows no "Snow" row anywhere.
 */
export class DetailsPair {
  label: string = '';
  dayValue: string = '';
  nightValue: string = '';

  constructor(label: string, dayValue: string, nightValue: string) {
    this.label = label;
    this.dayValue = dayValue;
    this.nightValue = nightValue;
  }
}

/** strings.xml:wind_gusts_short. */
const WIND_GUSTS_SHORT: string = 'Gusts';

/* strings.xml — precipitation_rain / _snow, and the two headings. */
const PRECIPITATION_RAIN: string = 'Rain';
const PRECIPITATION_SNOW: string = 'Snow';
export const PRECIPITATION_PROBABILITY_HEADING: string = 'Precipitation probability';
/** strings.xml:dew_point — the heading of Humidity's second group (DetailsHumidity.kt:181). */
export const DEW_POINT_HEADING: string = 'Dew point';

/**
 * `PrecipitationDetails` (kt:418-475) for variant 0 and `PrecipitationProbabilityDetails`
 * (kt:632-687) for variant 1.
 *
 * Ice and thunderstorm are in the Kotlin's list too; Open-Meteo reports neither, so their `> 0`
 * gate is false and Android draws no row for them either. Rain and snow are what it does report.
 */
export function precipitationPairs(
  location: LocationModel,
  dayIndex: number,
  variant: number
): DetailsPair[] {
  const weather = location.weather;
  if (weather === null || dayIndex < 0 || dayIndex >= weather.dailyForecast.length) {
    return [];
  }
  const daily: Daily = weather.dailyForecast[dayIndex];
  const day: HalfDay | null = daily.day;
  const night: HalfDay | null = daily.night;
  const out: DetailsPair[] = [];
  if (variant === 1) {
    /*
     * The Kotlin keys these on `precipitationProbability.rain` / `.snow`, which Open-Meteo does not
     * break down - it publishes one `precipitation_probability` series. With every part null the
     * gate is false for all four and Android draws no block, which is what an empty list gives.
     */
    return out;
  }
  const dayRain: number | null = day === null ? null : day.precipitationRain;
  const nightRain: number | null = night === null ? null : night.precipitationRain;
  if ((dayRain !== null && dayRain > 0) || (nightRain !== null && nightRain > 0)) {
    out.push(new DetailsPair(PRECIPITATION_RAIN,
      dayRain === null ? NULL_DATA_TEXT : formatPrecipitation(dayRain) + ' ' + precipitationUnitLabel(),
      nightRain === null ? NULL_DATA_TEXT
        : formatPrecipitation(nightRain) + ' ' + precipitationUnitLabel()));
  }
  const daySnow: number | null = day === null ? null : day.precipitationSnow;
  const nightSnow: number | null = night === null ? null : night.precipitationSnow;
  if ((daySnow !== null && daySnow > 0) || (nightSnow !== null && nightSnow > 0)) {
    // kt:483-487 - snow alone is measured in the SNOWFALL unit, the coarser one of the pair.
    out.push(new DetailsPair(PRECIPITATION_SNOW,
      daySnow === null ? NULL_DATA_TEXT : formatSnowfall(daySnow) + ' ' + snowfallUnitLabel(),
      nightSnow === null ? NULL_DATA_TEXT : formatSnowfall(nightSnow) + ' ' + snowfallUnitLabel()));
  }
  return out;
}

/**
 * One half-day's conditions column.
 *
 * `showRealTemp` is TAG_CONDITIONS; the other tag shows the feels-like temperature large and the
 * actual one under it as "Actual: 21 deg" (kt:591-604).
 */
function halfDayCondition(half: HalfDay | null, label: string, showRealTemp: boolean,
  daylight: boolean): SummaryColumn {
  if (half === null || half.temperature === null) {
    return column(label, '');
  }
  const actual: number | null = half.temperature.temperature;
  const feelsLike: number | null = half.temperature.feelsLikeTemperature;
  const shown: number | null = showRealTemp ? actual : feelsLike;
  if (shown === null) {
    return column(label, '');
  }
  const description: string = showRealTemp
    ? (half.weatherText === null ? '' : half.weatherText)
    // strings.xml:52 `temperature_real` + the colon separator.
    : (actual === null ? '' : 'Actual' + COLON_SEPARATOR + formatTemperatureWithUnit(actual));
  /*
   * kt:630-633 — `WeatherCondition` follows the temperature on a phone, and it carries the
   * half-day's ICON as well as its text. Only the real-temperature tag shows a condition; the
   * feels-like one puts "Actual: 21°" there instead, which has no icon.
   */
  const iconKind: WeatherKind | null =
    showRealTemp && half.weatherKind !== WeatherKind.NULL ? half.weatherKind : null;
  // kt:578 passes only `unitWidth = NARROW`, so the VALUE keeps the unit's short decimals: the
  // reference reads 18.2° / 11.3° here where the trend labels and the main header read 18° / 11°.
  return column(label, formatTemperatureShortNarrow(shown), '', description, '', iconKind,
    daylight);
}

/**
 * The blocks under the chart, in the Kotlin's order.
 *
 * Only the ones it actually renders: Conditions, Precipitation and Wind's scale table are not in
 * this increment, Humidity has TWO (humidity then dew point, kt:171-215), and Pollen and Sun & moon
 * lead with a card of listed rows instead of a header (kt:55-77 and kt:104-126).
 */
export function detailsSections(screen: DetailScreen): DetailsSection[] {
  switch (screen) {
    case DetailScreen.TAG_PRESSURE:
      return [new DetailsSection('About pressure', [ABOUT_PRESSURE_1, ABOUT_PRESSURE_2])];
    case DetailScreen.TAG_HUMIDITY:
      return [
        new DetailsSection('About relative humidity', [ABOUT_HUMIDITY]),
        new DetailsSection('About dew point', [ABOUT_DEW_POINT])
      ];
    case DetailScreen.TAG_VISIBILITY:
      return [
        new DetailsSection('About visibility', [ABOUT_VISIBILITY]),
        // DetailsVisibility.kt:158-161 — the scale table follows the About block, and its value
        // column is headed with the distance unit's display name ("km"), not "Visibility".
        new DetailsSection('Visibility scale', [], visibilityScaleRows(), '',
          'Description', distanceUnitDisplayName(), '', false, false, 1.5, 1.5, 1)
      ];
    case DetailScreen.TAG_CLOUD_COVER:
      return [
        new DetailsSection('About cloud cover', [ABOUT_CLOUD_COVER]),
        // The value column is headed with the UNIT, "%", not with the quantity (kt:363-369).
        new DetailsSection('Cloud cover scale', [], cloudCoverScaleRows(), '',
          'Description', '%', '', false, false, 1.5, 1.5, 1)
      ];
    case DetailScreen.TAG_UV_INDEX:
      return [
        new DetailsSection('About UV index', [ABOUT_UV]),
        // 2 / 1 here, where cloud cover and visibility are 1.5 / 1 (DetailsUV.kt:336-342).
        new DetailsSection('UV index scale', [], uvScaleRows(), '', 'Description', 'UV index',
          '', false, false, 2, 1.5, 1)
      ];
    case DetailScreen.TAG_WIND:
      return [
        new DetailsSection('About wind speed and gusts', [ABOUT_WIND]),
        /*
         * DetailsWind.kt:177-180 — `wind_strength_scale` is "Beaufort scale", :127. THREE columns:
         * the force number under "Bft" (speed_bf_display_name_short), the strength name under
         * `wind_strength_scale_description`, and the band under the speed unit's display name.
         */
        new DetailsSection('Beaufort scale', [], beaufortScaleRows(), '',
          'Bft', speedUnitDisplayName(), 'Description', false, false, 1, 1.5, 1.5)
      ];
    case DetailScreen.TAG_AIR_QUALITY:
      // Depends on the day's reading and the picked pollutant; built by detailsSectionsFor.
      return [];
    case DetailScreen.TAG_SUN_MOON:
      return [new DetailsSection('About rise and set times', [ABOUT_EPHEMERIS])];
    default:
      return [];
  }
}

/**
 * The same blocks, plus the two screens whose content depends on the day's data.
 *
 * Kept separate from `detailsSections` so the constant half stays a pure function of the tag; the
 * page calls this one.
 */
/**
 * The Sun & moon card — `DetailsSunMoon` (kt:101-146).
 *
 * FOUR `ListItem`s, each with a 24 dp leading image and a single bodyLarge line, inside one
 * `Material3ExpressiveCardListItem`:
 *   sun       weather_clear_day_mini    "5:24 AM↑ / 9:26 PM↓ / 16h 2m"   (kt:339-403)
 *   twilight  ic_twilight               "4:30 AM↑ / 10:20 PM↓"           (kt:415-464)
 *   moon      weather_clear_night_mini  "2:25 AM↑ / 9:20 PM↓"            (kt:476-525)
 *   phase     a MoonPhaseView disc      "New moon"                       (kt:534-558)
 *
 * The port drew five bare text rows — no icons, no twilight, no duration, each hugging its text at
 * 78 px where the reference's `ListItem` is a fixed 182.
 *
 * The astro is computed for the DAY THE PAGER IS ON, not for "now": `today.sun` / `today.twilight`
 * / `today.moon` / `today.moonPhase` are per-day fields that `completeDailyListFromHourlyList`
 * fills for all sixteen days. This port computes them here, for the one day being shown, rather
 * than storing sixteen days of scans on every refresh — same values, and it keeps a refresh from
 * paying for fifteen days nobody is looking at.
 */
function sunMoonSections(location: LocationModel, dayIndex: number): DetailsSection[] {
  const out: DetailsSection[] = [];
  const weather = location.weather;
  const rows: DetailsRow[] = [];
  const daily: Daily | null = weather === null || dayIndex < 0
    || dayIndex >= weather.dailyForecast.length ? null : weather.dailyForecast[dayIndex];
  if (daily !== null) {
    const offset: number = location.utcOffsetSeconds;
    const lat: number = location.latitude;
    const lon: number = location.longitude;
    const sun: AstroPair = calculatedSun(daily.date, lat, lon, offset);
    const twilight: AstroPair = calculatedCivilTwilight(daily.date, lat, lon, offset);
    const moon: AstroPair = calculatedMoon(daily.date, lat, lon, offset);

    if (sun.rise !== null || sun.set !== null) {
      // kt:360 — the duration is appended only when there is one, as " / 16h 2m".
      const duration: string = sun.rise !== null && sun.set !== null
        ? ' / ' + formatDuration(sun.set.getTime() - sun.rise.getTime())
        : '';
      rows.push(new DetailsRow(astroLine(sun, offset) + duration, '', '', '',
        'weather_clear_day_mini'));
    }
    if (twilight.rise !== null || twilight.set !== null) {
      rows.push(new DetailsRow(astroLine(twilight, offset), '', '', '', 'ic_twilight'));
    }
    if (moon.rise !== null || moon.set !== null) {
      rows.push(new DetailsRow(astroLine(moon, offset), '', '', '', 'weather_clear_night_mini'));
    }
    const angle: number = moonPhaseAngle(daily.date, offset);
    rows.push(new DetailsRow(moonPhaseName(angle), '', '', '', '', angle));
  }
  if (rows.length > 0) {
    out.push(new DetailsSection('', [], rows, '', '', '', '', false, false, 1.5, 1.5, 1, true));
  } else {
    out.push(new DetailsSection('', [NO_DAILY_DATA]));
  }
  out.push(new DetailsSection('About rise and set times', [ABOUT_EPHEMERIS]));
  return out;
}

/** "5:24 AM↑ / 9:26 PM↓" — the shape all three rise/set rows share (kt:362-369). */
function astroLine(pair: AstroPair, utcOffsetSeconds: number): string {
  const rise: string = pair.rise === null ? NULL_DATA_TEXT : getClockTime(pair.rise, utcOffsetSeconds);
  const set: string = pair.set === null ? NULL_DATA_TEXT : getClockTime(pair.set, utcOffsetSeconds);
  return rise + '↑ / ' + set + '↓';
}

/** `Duration.formatTime` at its default smallest unit — "16h 2m". */
function formatDuration(millis: number): string {
  const totalMinutes: number = Math.round(millis / 60000);
  const hours: number = Math.floor(totalMinutes / 60);
  const minutes: number = totalMinutes - hours * 60;
  if (hours === 0) {
    return minutes.toString() + 'm';
  }
  return hours.toString() + 'h ' + minutes.toString() + 'm';
}

export function detailsSectionsFor(
  location: LocationModel,
  screen: DetailScreen,
  dayIndex: number,
  pollutantId: string = ''
): DetailsSection[] {
  const weather = location.weather;
  if (screen === DetailScreen.TAG_AIR_QUALITY) {
    return airQualitySections(selectedAirQuality(location, dayIndex), pollutantId);
  }
  if (screen === DetailScreen.TAG_SUN_MOON) {
    return sunMoonSections(location, dayIndex);
  }
  if (screen === DetailScreen.TAG_POLLEN) {
    const current = weather === null ? null : weather.current;
    const pollen = current === null ? [] : current.pollen;
    if (pollen.length === 0) {
      return [new DetailsSection('', [NO_DAILY_DATA])];
    }
    const out: DetailsSection[] = [];
    /*
     * getPollenWithMaxIndex (Pollen.kt:49-62): the allergens with an index ABOVE ZERO, worst first,
     * and nothing at all when every one of them reads zero — in which case the Kotlin's `?.let`
     * skips the whole "Primary pollen" header.
     */
    let worst: PollenEntry | null = null;
    for (const entry of pollen) {
      if (entry.level > 0 && (worst === null || entry.level > worst.level)) {
        worst = entry;
      }
    }
    if (worst !== null) {
      out.push(new DetailsSection('Primary pollen', [], [], worst.name)); // strings.xml:243
    }
    /*
     * PollenGrid (AllergenComposables.kt:63-94): `validPollens` — everything the source REPORTS,
     * not only what is in season — sorted by localised name, two per row, and each subtitle is the
     * concentration, an en dash, then the level.
     */
    const sorted: PollenEntry[] = pollen.slice();
    sorted.sort((a: PollenEntry, b: PollenEntry) => a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
    const rows: DetailsRow[] = [];
    for (const entry of sorted) {
      rows.push(new DetailsRow(entry.name,
        formatPollenConcentration(entry.concentration) + ' – ' + entry.levelName,
        pollenLevelColor(entry.level)));
    }
    out.push(new DetailsSection('Pollen details', [], rows, '', '', '', '', false, true));
    return out;
  }
  return detailsSections(screen);
}

/** strings.xml:43 */
const NO_DAILY_DATA: string = 'No data available for this day.';

/**
 * `PollenConcentrationUnit.PER_CUBIC_METER.formatMeasure` — the value at zero decimals with
 * `volume_m3_per_short` around it, which on English is "%s/m³".
 */
function formatPollenConcentration(perCubicMeter: number): string {
  return Math.round(perCubicMeter).toString() + '/m³';
}

/**
 * A `DetailsItem` row (DetailsCommon.kt:82-135): an optional leading icon, a bold bodyLarge
 * headline with an optional help affordance beside it, and a supporting line under.
 *
 * The only one on the screen so far is the degree day, which the Kotlin draws bare in the list
 * between the chart's explanation and the sections below it (DetailsConditions.kt:284-360).
 */
export class DetailsItemModel {
  headline: string = '';
  supporting: string = '';
  /** A media resource name, e.g. `ic_mode_heat`. Empty for no icon. */
  icon: string = '';
  /** The PlainTooltip's text. Empty means no help affordance and no tooltip. */
  explanation: string = '';
  /**
   * The `Spacer` the Kotlin puts ABOVE this row, in vp.
   *
   * Not the same on the two tags that have a `DetailsItem`: the degree day takes a small_margin
   * (DetailsConditions.kt:286-288) and the sunshine duration a normal_margin
   * (DetailsCloudCover.kt:145-147). Measured on the reference, cloud cover's chart ends at 1623
   * and the row starts at 1675.
   */
  spacerAbove: number = 8;

  constructor(headline: string, supporting: string, icon: string, explanation: string,
    spacerAbove: number = 8) {
    this.headline = headline;
    this.supporting = supporting;
    this.icon = icon;
    this.explanation = explanation;
    this.spacerAbove = spacerAbove;
  }
}

/* strings.xml:295-298. */
/** strings.xml:sunshine_duration — the headline of Cloud cover's one DetailsItem. */
const SUNSHINE_DURATION: string = 'Sunshine duration';
/** dimens.xml normal_margin, as a plain number — this module does not import the theme. */
const NORMAL_MARGIN_VP: number = 16;
const DEGREE_DAY_HEATING: string = 'Heating degree day';
const DEGREE_DAY_HEATING_EXPLANATION: string =
  'Difference between the outside temperature and a reference comfortable temperature used to '
  + 'estimate heating energy requirements';
const DEGREE_DAY_COOLING: string = 'Cooling degree day';
const DEGREE_DAY_COOLING_EXPLANATION: string =
  'Difference between the outside temperature and a reference comfortable temperature used to '
  + 'estimate cooling energy requirements';

/**
 * The bare `DetailsItem` rows a tag draws under its chart.
 *
 * TWO tags have one. Conditions and Feels like draw the degree day, shown when `DegreeDay.isValid`
 * — heating > 0 OR cooling > 0 (DegreeDay.kt:27); inside the comfortable band both are zero and
 * the Kotlin draws nothing at all, which is what most days give. CLOUD COVER draws the SUNSHINE
 * DURATION whenever the day has one (`SunshineItem`, DetailsCloudCover.kt:144-151), which this
 * port omitted: the reference has a 139 px row at [52,1675][622,1814] between the chart and the
 * About section, and the port went straight from one to the other.
 */
export function detailsItems(
  location: LocationModel,
  screen: DetailScreen,
  dayIndex: number
): DetailsItemModel[] {
  if (screen !== DetailScreen.TAG_CONDITIONS && screen !== DetailScreen.TAG_FEELS_LIKE
    && screen !== DetailScreen.TAG_CLOUD_COVER) {
    return [];
  }
  const weather = location.weather;
  if (weather === null || dayIndex < 0 || dayIndex >= weather.dailyForecast.length) {
    return [];
  }
  const daily = weather.dailyForecast[dayIndex];
  if (screen === DetailScreen.TAG_CLOUD_COVER) {
    // `daily.sunshineDuration?.let` — no row at all when the day has none.
    return daily.sunshineHours === null
      ? []
      // `formatTime(smallestUnit = MINUTES)`, the same call the Sun & moon card's daylight
      // duration makes — one formatter, two callers.
      : [new DetailsItemModel(SUNSHINE_DURATION,
        formatDuration(Math.round(daily.sunshineHours * 3600000)), 'ic_sunshine_duration', '',
        NORMAL_MARGIN_VP)];
  }
  const heating: number = daily.heatingDegreeDay === null ? 0 : daily.heatingDegreeDay;
  const cooling: number = daily.coolingDegreeDay === null ? 0 : daily.coolingDegreeDay;
  if (heating <= 0 && cooling <= 0) {
    return []; // DegreeDay.isValid is false — kt:285 skips the whole block.
  }
  // kt:289 / kt:328 — heating takes precedence, and only ONE of the two rows is ever drawn.
  if (heating > 0) {
    return [new DetailsItemModel(DEGREE_DAY_HEATING, formatTemperatureDeviation(heating),
      'ic_mode_heat', DEGREE_DAY_HEATING_EXPLANATION)];
  }
  return [new DetailsItemModel(DEGREE_DAY_COOLING, formatTemperatureDeviation(cooling),
    'ic_mode_cool', DEGREE_DAY_COOLING_EXPLANATION)];
}

/*
 * The scale tables. One card per tag, a bold two-column header then a coloured dot, the band's
 * name and its range — DetailsUV.kt:312-380 is the shape they all share, and each tag's bands are
 * the SAME thresholds its description function already uses, so the table and the header can never
 * disagree.
 */

/** UV.uvThresholds — 0 / 3 / 6 / 8 / 11, i.e. the four constants with 0 in front. */
function uvScaleRows(): DetailsRow[] {
  const starts: number[] = [0, UV_INDEX_LOW, UV_INDEX_MIDDLE, UV_INDEX_HIGH, UV_INDEX_EXCESSIVE];
  const out: DetailsRow[] = [];
  for (let i = 0; i < starts.length; i++) {
    const next: number = i + 1 < starts.length ? starts[i + 1] : Number.NaN;
    const range: string = Number.isNaN(next)
      ? starts[i].toString() + '+'
      : starts[i].toString() + ' – ' + (next - 1).toString();
    out.push(new DetailsRow(uvLevelName(starts[i]), range, uvLevelColor(starts[i])));
  }
  return out;
}

/**
 * The Met Office bands the visibility description already uses — 1 / 4 / 10 / 20 / 40 km.
 *
 * `VisibilityScale` (DetailsVisibility.kt:388-415) formats the BAND, not the boundary: the end of
 * a row is the next threshold LESS ONE STEP (0.1 when the unit shows a decimal, 1 when it does
 * not), and the unit itself lives in the column heading, never in the cell. Measured on the
 * reference: "0 – 0.9", "1 – 3.9", "4 – 9.9" against this port's "0 – 1 km", "1 – 4 km".
 */
function visibilityScaleRows(): DetailsRow[] {
  const starts: number[] = [0, 1000, 4000, 10000, 20000, 40000];
  const out: DetailsRow[] = [];
  const step: number = distanceDecimals() === 0 ? 1.0 : 0.1;
  for (let i = 0; i < starts.length; i++) {
    const range: string = i + 1 < starts.length
      ? formatDistance(starts[i]) + ' – ' + formatDistanceValue(distanceValue(starts[i + 1]) - step)
      : formatDistance(starts[i]) + '+';
    out.push(new DetailsRow(visibilityDescription(starts[i]), range));
  }
  return out;
}

/**
 * The Beaufort scale — the WIND_SPEED_* table (held in cm/s, so 30 is 0.3 m/s), its thirteen
 * strength names from strings.xml:118-130, and the windStrength_bf* colours.
 */
const BEAUFORT_STARTS_MS: number[] =
  [0, 0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7];
const BEAUFORT_NAMES: string[] = [
  'Calm', 'Light air', 'Light breeze', 'Gentle breeze', 'Moderate breeze', 'Fresh breeze',
  'Strong breeze', 'Moderate gale', 'Gale', 'Strong gale', 'Storm', 'Violent storm',
  'Hurricane-force'
];
const BEAUFORT_COLORS: string[] = [
  '#FF6271B7', '#FF39619F', '#FF4A94A9', '#FF4D8D7B', '#FF53A553', '#FF359F35', '#FFA79D51',
  '#FFA1645C', '#FFAF5088', '#FF754A93', '#FF44698D', '#FF5C9098', '#FF7D44A5'
];

/**
 * `BeaufortScale` (DetailsWind.kt:504-592) — THREE columns, not two: a dot with the force NUMBER,
 * the strength name, and the speed band.
 *
 * The band ends one tenth BELOW the next force's threshold (kt:547-556), and carries no unit —
 * the unit is the column heading. Measured on the reference: "0 / Calm / 0 – 0.2",
 * "1 / Light air / 0.3 – 1.5", against this port's two columns of "Calm | 0 – 0.3 m/s".
 */
function beaufortScaleRows(): DetailsRow[] {
  const out: DetailsRow[] = [];
  for (let i = 0; i < BEAUFORT_STARTS_MS.length; i++) {
    const from: string = formatSpeed(BEAUFORT_STARTS_MS[i]);
    const range: string = i + 1 < BEAUFORT_STARTS_MS.length
      ? from + ' – ' + formatSpeedValue(speedValue(BEAUFORT_STARTS_MS[i + 1]) - 0.1)
      : from + '+';
    out.push(new DetailsRow(i.toString(), range, BEAUFORT_COLORS[i], BEAUFORT_NAMES[i]));
  }
  return out;
}

/**
 * `AirQualityScale` (DetailsAirQuality.kt:725-797) — THREE columns, and the whole table changes
 * when a pollutant is picked.
 *
 * With no pollutant the rows are the AQI bands themselves. With one, the rows are that pollutant's
 * CONCENTRATION bands, each labelled with the level its own index falls in, and the last column
 * carries concentrations rather than index numbers. The end of a band is the next band's start
 * minus one (kt:764-767), and the last band is open-ended.
 */
function aqiScaleRows(def: PollutantDef | null): DetailsRow[] {
  const bands: number[] = def === null ? AQI_THRESHOLDS : def.thresholds;
  const out: DetailsRow[] = [];
  for (let i = 0; i < bands.length; i++) {
    const aqi: number | null = def === null ? bands[i] : pollutantIndexOf(def, bands[i]);
    const range: string = i + 1 < bands.length
      ? bands[i].toString() + ' – ' + (bands[i + 1] - 1).toString()
      : bands[i].toString() + '+';
    const level: number = aqi === null ? i : levelOf(aqi, AQI_THRESHOLDS);
    out.push(new DetailsRow(aqiLevelName(aqi === null ? bands[i] : aqi), range,
      aqiLevelColor(aqi === null ? bands[i] : aqi), aqiHarmlessExposureAt(level)));
  }
  return out;
}

/**
 * The Air quality screen's blocks, which depend on the picked pollutant.
 *
 * With a pollutant picked the Kotlin shows ONLY that pollutant's About card (kt:255-268); with
 * none it shows Health information, Primary pollutant and Pollutant details (kt:269-308). Both
 * then get the shared About-the-index card and the scale table, whose heading and rows also change
 * with the selection (kt:309-337).
 */
function airQualitySections(
  air: AirQualityConcentrations | null,
  pollutantId: string
): DetailsSection[] {
  const def: PollutantDef | null = pollutantById(pollutantId);
  const out: DetailsSection[] = [];

  if (def !== null) {
    out.push(new DetailsSection(def.aboutHeading, [def.sources]));
  } else if (air !== null) {
    const index: number | null = overallIndexOf(air);
    if (index !== null) {
      // air_quality_health_information (:271) - the level's own description paragraph.
      out.push(new DetailsSection('Health information', [aqiLevelDescription(index)]));
    }
    /*
     * The primary pollutant is the one with the HIGHEST sub-index (kt:216-218,
     * `detailedPollutants.maxByOrNull { it.progress }`), among the same six the details grid
     * lists. Its full name is the heading's subtitle and its sources are the card.
     */
    const worst: PollutantDef | null = primaryPollutant(air);
    if (worst !== null) {
      out.push(new DetailsSection('Primary pollutant', [worst.sources], [], worst.fullName));
    }
    out.push(new DetailsSection('Pollutant details', [], pollutantDetailRows(air), '', '', '', '',
      true));
  }

  out.push(new DetailsSection('About air quality index', [ABOUT_AIR_QUALITY_1, ABOUT_AIR_QUALITY_2]));
  out.push(new DetailsSection(def === null ? 'Air quality index scale' : def.scaleHeading, [],
    aqiScaleRows(def), '', 'Description',
    def === null ? 'AQI' : concentrationUnitLabel(def), 'Harmless exposure',
    false, false, 2, 1.5, 1.5)); // kt:750-769
  return out;
}

/**
 * `detailedPollutants` (kt:168-215) — PM2.5, PM10, O3 and NO2 whenever they are present, then SO2
 * and CO only when they read above zero.
 */
function detailedPollutants(air: AirQualityConcentrations): PollutantDef[] {
  const out: PollutantDef[] = [];
  for (const id of ['pm25', 'pm10', 'o3', 'no2']) {
    const def: PollutantDef | null = pollutantById(id);
    if (def !== null && concentrationOf(air, id) !== null) {
      out.push(def);
    }
  }
  for (const id of ['so2', 'co']) {
    const def: PollutantDef | null = pollutantById(id);
    const value: number | null = def === null ? null : concentrationOf(air, id);
    if (def !== null && value !== null && value > 0) {
      out.push(def);
    }
  }
  return out;
}

/** `primaryPollutant` — the highest sub-index among the detailed ones (kt:216-218). */
function primaryPollutant(air: AirQualityConcentrations): PollutantDef | null {
  let best: PollutantDef | null = null;
  let bestIndex: number = -1;
  for (const def of detailedPollutants(air)) {
    const index: number | null = pollutantIndexOf(def, concentrationOf(air, def.id));
    if (index !== null && index > bestIndex) {
      bestIndex = index;
      best = def;
    }
  }
  return best;
}

/**
 * `AirQualityDetails` (kt:656-682) — the two-per-row grid of a bold name, a progress bar in the
 * pollutant's own colour and the concentration under it.
 *
 * The bar's fraction is the sub-index over `indexExcessivePollution` (250), NOT the concentration
 * over its band, "for a more realistic bar" (kt:170). It rides in `value` as the formatted
 * concentration and in `middle` as the fraction, so the view needs no second model.
 */
function pollutantDetailRows(air: AirQualityConcentrations): DetailsRow[] {
  const out: DetailsRow[] = [];
  for (const def of detailedPollutants(air)) {
    const concentration: number | null = concentrationOf(air, def.id);
    if (concentration === null) {
      continue;
    }
    const index: number | null = pollutantIndexOf(def, concentration);
    const fraction: number = index === null
      ? 0
      : Math.min(1, index / AQI_THRESHOLDS[AQI_THRESHOLDS.length - 1]);
    out.push(new DetailsRow(def.shortName, formatConcentration(def, concentration),
      index === null ? '' : aqiLevelColor(index), fraction.toFixed(4)));
  }
  return out;
}

/**
 * The picker's entries: the AQI itself, then every pollutant the reading carries.
 *
 * `supportedPollutants` (DetailsScreen.kt:426-441) filters `PollutantIndex.entries` — the ENUM
 * DECLARATION order, PM2.5, PM10, O3, NO2, SO2, CO — not `validPollutants`, which puts NO2 and O3
 * first. The two orders differ and this used to take the wrong one: the reference's switcher reads
 * AQI / PM2.5 / PM10 / O3 and the ports read AQI / NO2 / O3.
 */
export function pollutantOptions(location: LocationModel, dayIndex: number): PollutantDef[] {
  const air: AirQualityConcentrations | null = selectedAirQuality(location, dayIndex);
  const out: PollutantDef[] = [];
  if (air === null) {
    return out;
  }
  for (const def of POLLUTANTS) {
    if (concentrationOf(air, def.id) !== null) {
      out.push(def);
    }
  }
  return out;
}

/**
 * `selectedAirQuality` (kt:160-166) — the day's average when it is valid, otherwise the
 * `defaultValue` the screen was opened with, which is the current hour.
 */
function selectedAirQuality(
  location: LocationModel,
  dayIndex: number
): AirQualityConcentrations | null {
  const weather = location.weather;
  if (weather === null) {
    return null;
  }
  if (dayIndex >= 0 && dayIndex < weather.dailyForecast.length) {
    const daily = weather.dailyForecast[dayIndex];
    if (daily.airQuality !== null && overallIndexOf(daily.airQuality) !== null) {
      return daily.airQuality;
    }
  }
  return weather.current === null ? null : weather.current.airQuality;
}

/**
 * The okta bands — 12.5 / 37.5 / 62.5 / 87.5 %.
 *
 * `CloudCoverScale` (DetailsCloudCover.kt:370-392) prints the boundaries themselves, unrounded and
 * WITHOUT a per-cell "%": the "%" is the column heading. Measured on the reference: "0 – 12.5",
 * "12.5 – 37.5", where this port rounded to "0% – 13%".
 */
function cloudCoverScaleRows(): DetailsRow[] {
  const starts: number[] = [0, 12.5, 37.5, 62.5, 87.5];
  const out: DetailsRow[] = [];
  for (let i = 0; i < starts.length; i++) {
    const next: number = i + 1 < starts.length ? starts[i + 1] : 100;
    // `Ratio.formatValue` — the number alone, and JS already prints 12.5 and 100 the way it does.
    out.push(new DetailsRow(cloudCoverDescription(starts[i]),
      starts[i].toString() + ' – ' + next.toString()));
  }
  return out;
}

/*
 * `pollenLevelColor` used to have a private copy HERE too, and it was keyed on the AIR-QUALITY
 * ramp (COLOR_LEVEL_1..5) rather than on `pollen_level_colors`. So a "Very low" allergen was the
 * pale green #72D572 on this screen and the teal #08C286 on the main screen's block — and the NDK,
 * which has only one table, drew the teal in both places. Same shape of bug as the duplicate AQI
 * scale: it now comes from theme/AppColors.ets, which the main screen already used.
 */

/*
 * `aqiLevelName` and `aqiLevelColor` used to have private copies here, keyed on `index <= 20`
 * rather than the Kotlin's `indexOfLast { index >= it }`. They disagreed with the shared pair on
 * every band boundary — an AQI of exactly 20 came out "Excellent" here and "Fair" everywhere else.
 * Both now come from model/Pollutant.ets and theme/AppColors.ets, which the main screen's block
 * and the mapper already use.
 */
