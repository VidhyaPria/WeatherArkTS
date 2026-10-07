/*
 * Unit selection and formatting.
 *
 * Port of the weather-unit module's *Unit enums plus SettingsManager's unit preferences
 * (SettingsManager.kt:230-265 getTemperatureUnit / getSpeedUnit / getPressureUnit /
 * getDistanceUnit / getPrecipitationUnit).
 *
 * TWO LAYERS, and the order matters — it is the Kotlin's `?:`:
 *
 *   1. the STORED override for that quantity, if the user pinned one on the Units screen;
 *   2. otherwise `<Unit>.getDefaultUnit(context.currentLocale)`, the CLDR per-quantity table
 *      keyed on the locale's COUNTRY.
 *
 * Layer 2 is all this file used to be, which was correct but unconfigurable: a US-locale device
 * showed °F / mph / inHg / mi and a European one °C / m·s⁻¹ / hPa / km, with no way to say
 * otherwise. Layer 1 is what the Units screen writes.
 *
 * The conversions themselves live in `model/UnitCatalogue.ets`, one entry per unit, converting
 * through each family's reference unit exactly as the Kotlin does.
 *
 * Decimals: the blocks render UnitWidth.SHORT, and the Kotlin formatter drops trailing zeros —
 * which is why the device shows "29.97 inHg", "24.6 mi", "8 mph" and "0 in" from the same rule.
 */

import { i18n } from '@kit.LocalizationKit';
import { AppSettings, unitSetting } from '../data/SettingsStore';
import { toReference, UnitDef, UnitFamily, unitById, UNIT_AUTO } from '../model/UnitCatalogue';

/**
 * Android has no single "unit system" switch — SettingsManager keeps a separate preference per
 * quantity, and each falls back to `<Unit>.getDefaultUnit(context.currentLocale)`, which is a
 * per-quantity table keyed on the locale's COUNTRY (the CLDR unit preferences).
 *
 * The tables below are those functions verbatim:
 *   TemperatureUnit.getDefaultUnit  kt:199-214
 *   DistanceUnit.getDefaultUnit     kt:197-203
 *   PressureUnit.getDefaultUnit     kt:231-239
 *   SpeedUnit.getDefaultUnit        kt:  (CN/DK/FI/JP/KR/NO/NL/PL/RU/SE m/s, GB/US mph, else km/h)
 *
 * Note the consequence, which is Android's behaviour and not a bug: the two test phones disagree.
 * The Android device is en-US and so renders °F / mph / inHg / mi; this HarmonyOS device reports
 * region CN and so renders °C / m/s / hPa / km. Setting both phones to the same region makes them
 * agree — and the Units screen can now force either.
 */
export enum UnitSystem {
  METRIC,
  IMPERIAL
}

/** The device's region code, e.g. "US" or "CN" — Android's `locale.country`. */
function country(): string {
  try {
    const region: string = i18n.System.getSystemRegion();
    return region.toUpperCase();
  } catch (error) {
    return '';
  }
}

function inList(list: string[], value: string): boolean {
  return list.indexOf(value) >= 0;
}

/* Resolved once — the region does not change while the app is running. */
const COUNTRY: string = country();

/** TemperatureUnit.getDefaultUnit (kt:210-213). */
const USES_FAHRENHEIT: boolean = inList(['BS', 'BZ', 'KY', 'PR', 'PW', 'US'], COUNTRY);
/** DistanceUnit.getDefaultUnit (kt:199-203) — NL is metres, GB/US miles, else kilometres. */
const USES_MILES: boolean = inList(['GB', 'US'], COUNTRY);
/** PressureUnit.getDefaultUnit (kt:233-239) — only the US default is inches of mercury. */
const USES_INHG: boolean = COUNTRY === 'US';
/** SpeedUnit.getDefaultUnit — GB/US mph; a named set uses m/s; everyone else km/h. */
const USES_MPH: boolean = inList(['GB', 'US'], COUNTRY);
const USES_METRES_PER_SECOND: boolean =
  inList(['CN', 'DK', 'FI', 'JP', 'KR', 'NO', 'NL', 'PL', 'RU', 'SE'], COUNTRY);
/**
 * Precipitation has no separate CLDR table in Breezy; it follows the same imperial/metric split
 * the rest of the card uses, which in practice is the US inch.
 */
const USES_INCHES: boolean = COUNTRY === 'US';

/** Kept for callers that only need a coarse answer; derived, no longer hardcoded. */
export const UNIT_SYSTEM: UnitSystem = USES_FAHRENHEIT ? UnitSystem.IMPERIAL : UnitSystem.METRIC;

/* ------------------------------------------------------- the regional (auto) defaults ------- */

/** `<Unit>.getDefaultUnit(currentLocale)` — what "auto" resolves to on THIS device. */
export function regionalDefaultId(family: UnitFamily): string {
  if (family === UnitFamily.TEMPERATURE) {
    return USES_FAHRENHEIT ? 'f' : 'c';
  }
  if (family === UnitFamily.PRECIPITATION) {
    return USES_INCHES ? 'in' : 'mm';
  }
  if (family === UnitFamily.SPEED) {
    if (USES_MPH) {
      return 'mph';
    }
    return USES_METRES_PER_SECOND ? 'mps' : 'kph';
  }
  if (family === UnitFamily.DISTANCE) {
    return USES_MILES ? 'mi' : 'km';
  }
  return USES_INHG ? 'inhg' : 'hpa';
}

/**
 * PrecipitationUnit.getDefaultSnowfallUnit — snow is reported in the coarser unit, so a metric
 * region pairs mm with cm. It exists only so the Units screen can render the regional row as
 * "millimeters/centimeters" when the two differ (UnitSettingsScreen.kt:108-131).
 */
export function regionalDefaultSnowfallId(): string {
  return USES_INCHES ? 'in' : 'cm';
}

/** The unit actually in force for a family: the stored override, else the regional default. */
export function activeUnit(family: UnitFamily): UnitDef {
  const stored: string = unitSetting(family);
  if (stored !== UNIT_AUTO) {
    const pinned: UnitDef | null = unitById(family, stored);
    if (pinned !== null) {
      return pinned;
    }
  }
  const fallback: UnitDef | null = unitById(family, regionalDefaultId(family));
  // unitById cannot miss for an id this file produces; the guard keeps the return type honest.
  return fallback === null ? unitById(family, 'c') as UnitDef : fallback;
}

/**
 * Rounds to at most `decimals` places and strips trailing zeros, matching the Kotlin
 * NumberFormatter output ("29.97", "24.6", "8", "0").
 *
 * The integer part is GROUPED. Android formats every measure through
 * `android.icu.number.NumberFormatter` (WeatherValue.kt:20, :42-49), and ICU groups by locale
 * default — which is why the reference's pressure tile reads "1,002.8 hPa" where both ports read
 * "1002.8". Pressure is the only value in this app that reaches four digits today, but the rule
 * belongs here rather than in `formatPressure`: grouping is a property of the number formatter in
 * ICU, not of one quantity, so anything that grows past 999 later gets it for free.
 *
 * The separator is a comma because CLAUDE.md scopes this port to English. A locale-aware separator
 * would mean going through `intl`, and the rest of this file already hard-codes English decimals.
 */
function format(value: number, decimals: number): string {
  const factor: number = Math.pow(10, decimals);
  const rounded: number = Math.round(value * factor) / factor;
  const text: string = rounded.toString();
  // Exponent form never occurs for the magnitudes here; passed through rather than mis-grouped.
  if (text.indexOf('e') >= 0 || text.indexOf('E') >= 0) {
    return text;
  }
  const negative: boolean = text.charAt(0) === '-';
  const body: string = negative ? text.substring(1) : text;
  const dot: number = body.indexOf('.');
  const whole: string = dot < 0 ? body : body.substring(0, dot);
  const fraction: string = dot < 0 ? '' : body.substring(dot);
  let grouped: string = '';
  for (let i = 0; i < whole.length; i++) {
    // A separator before every digit whose distance from the end is a multiple of three.
    if (i > 0 && (whole.length - i) % 3 === 0) {
      grouped += ',';
    }
    grouped += whole.charAt(i);
  }
  return (negative ? '-' : '') + grouped + fraction;
}

/**
 * `Double.format(decimals)` for a unitless quantity — rounds to `decimals` places and DROPS a
 * trailing zero, which is why the reference's UV header reads "5" where `format(decimals = 1)`
 * was asked for (DetailsUV.kt:223).
 */
export function formatDecimals(value: number, decimals: number): string {
  return format(value, decimals);
}

/** Converts a model value into the active unit and formats it at that unit's SHORT decimals. */
function formatIn(family: UnitFamily, modelValue: number): string {
  const unit: UnitDef = activeUnit(family);
  return format(unit.fromReference(toReference(family, modelValue)), unit.decimals);
}

/**
 * The same conversion WITHOUT formatting.
 *
 * Screen 4's charts plot in the display unit — the axis bounds, the label step and the gradient
 * stops are all expressed there (BreezyLineChart's `endAxisValueFormatter` receives values already
 * converted) — so they need the number, not the string.
 */
export function valueIn(family: UnitFamily, modelValue: number): number {
  return activeUnit(family).fromReference(toReference(family, modelValue));
}

/** Rounds a converted value the way the axis labels do. */
export function formatUnitValue(family: UnitFamily, converted: number): string {
  return format(converted, activeUnit(family).decimals);
}

/**
 * Reading a @Trace field is what subscribes a builder to it, and the format helpers above read the
 * unit settings inside plain functions — where a @Trace read does NOT register a dependency, the
 * trap this port documents throughout.
 *
 * A component that renders a formatted value therefore calls this once in its build so the
 * subscription is registered where the framework can see it. Returns a number so it can be used in
 * a key or simply discarded.
 */
export function unitRevision(): number {
  const settings: AppSettings = AppSettings.instance;
  return settings.temperatureUnit.length + settings.precipitationUnit.length +
    settings.speedUnit.length + settings.distanceUnit.length + settings.pressureUnit.length;
}

/* ---------------------------------------------------------------- temperature */

/** The active temperature unit's value for a model Celsius reading. */
export function temperatureValue(celsius: number): number {
  const unit: UnitDef = activeUnit(UnitFamily.TEMPERATURE);
  return unit.fromReference(toReference(UnitFamily.TEMPERATURE, celsius));
}

/** UnitWidth.NARROW, e.g. "70°" — the big header value and every trend label. */
export function formatTemperatureNarrow(celsius: number): string {
  return Math.round(temperatureValue(celsius)).toString() + '°';
}

/** The degree unit beside the big header number (container_main_header.xml:94-106). */
export function temperatureUnitLabel(): string {
  return activeUnit(UnitFamily.TEMPERATURE).shortLabel;
}

export function formatTemperatureWithUnit(celsius: number): string {
  return Math.round(temperatureValue(celsius)).toString() + temperatureUnitLabel();
}

/**
 * The reading at the unit's SHORT decimals but with the NARROW unit — "18.2°".
 *
 * `formatMeasure(context, unit, unitWidth = UnitWidth.NARROW)` (DetailsConditions.kt:578) leaves
 * `valueWidth` at its SHORT default and overrides only the UNIT's width, so the value keeps
 * Celsius's one decimal (`UnitDecimals(narrow = 0, short = 1, long = 1)`,
 * TemperatureUnit.kt:77) while the unit collapses to a bare degree sign. Screen 4's conditions
 * header is the one place that combination appears; the trend labels and the main header pass
 * `valueWidth = NARROW` too and so round, which is what `formatTemperatureNarrow` does.
 */
export function formatTemperatureShortNarrow(celsius: number): string {
  const unit: UnitDef = activeUnit(UnitFamily.TEMPERATURE);
  return format(temperatureValue(celsius), unit.decimals) + '°';
}

/**
 * `Temperature.toDoubleDeviation` (Temperature.kt:131-133) formatted at the unit's SHORT decimals.
 *
 * A DEVIATION, not a reading: 1 °C of degree day is 1.8 °F, not 33.8 °F, so the Fahrenheit
 * conversion drops the +32 offset (TemperatureUnit.kt:92) and Kelvin is a plain divide.
 */
export function formatTemperatureDeviation(deciCelsius: number): string {
  const unit: UnitDef = activeUnit(UnitFamily.TEMPERATURE);
  const converted: number =
    unit.id === 'f' ? 9.0 / 5.0 * (deciCelsius / 10.0) : deciCelsius / 10.0;
  return format(converted, unit.decimals) + unit.shortLabel;
}

/**
 * TemperatureUnit.chartStep — 5 for Celsius and Fahrenheit, 10 for Kelvin (the reference,
 * deci-celsius, is 50). Screen 4's temperature chart rounds its bounds out to this.
 */
export function temperatureChartStep(): number {
  return activeUnit(UnitFamily.TEMPERATURE).id === 'k' ? 10 : 5;
}

/* ---------------------------------------------------------------------- speed */

export function formatSpeed(metresPerSecond: number): string {
  return formatIn(UnitFamily.SPEED, metresPerSecond);
}

/** The scale table's column heading — "meters/sec", not the "m/s" that rides beside a value. */
export function speedUnitDisplayName(): string {
  return activeUnit(UnitFamily.SPEED).displayName;
}

/** Formats a value ALREADY in the display unit, at that unit's decimals. */
export function formatSpeedValue(converted: number): string {
  return formatUnitValue(UnitFamily.SPEED, converted);
}

export function speedUnitLabel(): string {
  return activeUnit(UnitFamily.SPEED).shortLabel;
}

/** The speed in the active unit, unformatted — screen 4's wind chart. */
export function speedValue(metresPerSecond: number): number {
  return valueIn(UnitFamily.SPEED, metresPerSecond);
}

/**
 * SpeedUnit.chartStep. It is a MINIMUM spacing, not a fixed interval: Vico's
 * `VerticalAxis.ItemPlacer.step` takes the smallest multiple of it that fits the axis, which is why
 * 0.5 for metres per second does not mean thirty gridlines over a 15 m/s range.
 */
export function speedChartStep(): number {
  switch (activeUnit(UnitFamily.SPEED).id) {
    case 'mps':
      return 0.5;
    case 'kph':
    case 'ftps':
      return 15;
    case 'mph':
    case 'kn':
      return 10;
    case 'bf':
      return 2;
    default:
      return 50; // cm/s, the reference unit
  }
}

/* ------------------------------------------------------------------- pressure */

export function formatPressure(hectopascals: number): string {
  return formatIn(UnitFamily.PRESSURE, hectopascals);
}

/** The pressure in the active unit, unformatted — screen 4's chart axis. */
export function pressureValue(hectopascals: number): number {
  return valueIn(UnitFamily.PRESSURE, hectopascals);
}

export function pressureUnitLabel(): string {
  return activeUnit(UnitFamily.PRESSURE).shortLabel;
}

/* ------------------------------------------------------------------- distance */

export function formatDistance(metres: number): string {
  return formatIn(UnitFamily.DISTANCE, metres);
}

/** The distance in the active unit, unformatted — screen 4's chart axis. */
export function distanceValue(metres: number): number {
  return valueIn(UnitFamily.DISTANCE, metres);
}

export function distanceUnitLabel(): string {
  return activeUnit(UnitFamily.DISTANCE).shortLabel;
}

/** The scale table's column heading — `getDisplayName`, not the value suffix. See UnitDef. */
export function distanceUnitDisplayName(): string {
  return activeUnit(UnitFamily.DISTANCE).displayName;
}

/** UnitDecimals.short for distance — the visibility scale needs the step it implies. */
export function distanceDecimals(): number {
  return activeUnit(UnitFamily.DISTANCE).decimals;
}

/** Formats a value ALREADY in the display unit, at that unit's decimals. */
export function formatDistanceValue(converted: number): string {
  return formatUnitValue(UnitFamily.DISTANCE, converted);
}

/* -------------------------------------------------------------- precipitation */

export function formatPrecipitation(millimetres: number): string {
  return formatIn(UnitFamily.PRECIPITATION, millimetres);
}

export function precipitationUnitLabel(): string {
  return activeUnit(UnitFamily.PRECIPITATION).shortLabel;
}

/** The precipitation in the active unit, unformatted — screen 4's bar chart plots in it. */
export function precipitationValue(millimetres: number): number {
  return valueIn(UnitFamily.PRECIPITATION, millimetres);
}

/**
 * PrecipitationUnit.chartStep — 5 mm, 0.5 cm, 0.2 in, 5 L·m⁻² (PrecipitationUnit.kt:74-123).
 *
 * As everywhere else this is Vico's MINIMUM label spacing, not a fixed interval.
 */
export function precipitationChartStep(): number {
  switch (activeUnit(UnitFamily.PRECIPITATION).id) {
    case 'cm':
      return 0.5;
    case 'in':
      return 0.2;
    default:
      return 5; // mm and L·m⁻²
  }
}

/**
 * `SettingsManager.getSnowfallUnit` (kt:241-243) — the PINNED precipitation unit when there is
 * one, else `PrecipitationUnit.getDefaultSnowfallUnit(locale)`, which is the coarser member of the
 * regional pair: centimetres where rain is millimetres, inches where rain is inches.
 */
function snowfallUnit(): UnitDef {
  const stored: string = unitSetting(UnitFamily.PRECIPITATION);
  if (stored !== UNIT_AUTO) {
    const pinned: UnitDef | null = unitById(UnitFamily.PRECIPITATION, stored);
    if (pinned !== null) {
      return pinned;
    }
  }
  const fallback: UnitDef | null =
    unitById(UnitFamily.PRECIPITATION, regionalDefaultSnowfallId());
  return fallback === null ? activeUnit(UnitFamily.PRECIPITATION) : fallback;
}

/** A snow depth, in the snowfall unit — DailyPrecipitationDetail's `getSnowfallUnit` branch. */
export function formatSnowfall(millimetres: number): string {
  const unit: UnitDef = snowfallUnit();
  return format(unit.fromReference(toReference(UnitFamily.PRECIPITATION, millimetres)),
    unit.decimals);
}

export function snowfallUnitLabel(): string {
  return snowfallUnit().shortLabel;
}
