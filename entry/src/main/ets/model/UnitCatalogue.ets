/*
 * The five unit families the Units settings screen offers — a port of the weather-unit module's
 * enums (TemperatureUnit, PrecipitationUnit, SpeedUnit, DistanceUnit, PressureUnit).
 *
 * Each enum converts through a REFERENCE unit rather than pairwise, which is what the Kotlin does
 * and why the factors below are one per unit instead of one per pair:
 *
 *   temperature    deci-celsius   TemperatureUnit.kt:44-115
 *   precipitation  micrometre     PrecipitationUnit.kt
 *   speed          cm·s⁻¹         SpeedUnit.kt
 *   distance       metre          DistanceUnit.kt
 *   pressure       pascal         PressureUnit.kt
 *
 * Our model stores plain metric (°C, mm, m·s⁻¹, m, hPa), so `toReference` lifts that into the
 * reference unit and each unit's `fromReference` drops it into the display unit.
 *
 * THE UNITS EXCLUDED HERE ARE EXCLUDED BY THE KOTLIN, not by this port. UnitSettingsScreen.kt
 * filters one entry out of four of the five lists before building the dialog:
 *
 *   kt:70   TemperatureUnit.DECI_CELSIUS        (the reference unit itself)
 *   kt:106  PrecipitationUnit.MICROMETER        (ditto)
 *   kt:158  SpeedUnit.CENTIMETER_PER_SECOND     (ditto)
 *   kt:228  PressureUnit.PASCAL                 (ditto)
 *   kt:193  DistanceUnit — no filter, all five offered
 *
 * NAMES ARE NOT GUESSED. The long names are what the reference Android device renders in each
 * dialog, read off it with `uiautomator dump` — they come from ICU's MeasureUnit at UnitWidth.LONG
 * for most units, which is not something this port can derive. The short labels are the app's own
 * `*_display_name_short` strings where it has them (weather-unit strings.xml) and ICU's short forms
 * otherwise.
 */

/** Which quantity a preference row configures. */
export enum UnitFamily {
  TEMPERATURE = 'temperature',
  PRECIPITATION = 'precipitation',
  SPEED = 'speed',
  DISTANCE = 'distance',
  PRESSURE = 'pressure'
}

/** The sentinel SettingsManager stores when no unit is pinned (kt:"temperature_unit", "auto"). */
export const UNIT_AUTO: string = 'auto';

export class UnitDef {
  /** The id SettingsManager persists, e.g. "c", "mph", "inhg". */
  readonly id: string;
  /** UnitWidth.LONG — the dialog row and the row summary. */
  readonly longName: string;
  /** UnitWidth.SHORT — the suffix beside a value on the weather screen. */
  readonly shortLabel: string;
  /** UnitDecimals(short = …) — how many places the blocks render. */
  readonly decimals: number;
  /** Reference unit → this unit. */
  readonly fromReference: (reference: number) => number;
  /**
   * `getDisplayName(useMeasureFormat = true)` — the unit named as a COLUMN HEADING, which is not
   * the suffix that rides beside a value.
   *
   * The scale tables put it above their value column: the reference's Beaufort table is headed
   * "meters/sec" where a value reads "0.3 m/s", and its visibility table "km". That is ICU's short
   * unit display name, which is "meters/sec" for m·s⁻¹ and plain "km" for the kilometre.
   *
   * MEASURED on the reference: `mps` -> "meters/sec" and `km` -> "km", the two the device's own
   * settings select. The rest are CLDR's short display names for the same units; they are only
   * visible after changing the unit in Settings and have not been checked against the reference.
   * Empty means "same as shortLabel".
   */
  readonly displayName: string;

  constructor(
    id: string,
    longName: string,
    shortLabel: string,
    decimals: number,
    fromReference: (reference: number) => number,
    displayName: string = ''
  ) {
    this.id = id;
    this.longName = longName;
    this.shortLabel = shortLabel;
    this.decimals = decimals;
    this.fromReference = fromReference;
    this.displayName = displayName.length > 0 ? displayName : shortLabel;
  }
}

/* ------------------------------------------------------------------------ temperature */

/** TemperatureUnit.kt:62-115. DECI_CELSIUS is filtered out by UnitSettingsScreen.kt:70. */
export const TEMPERATURE_UNITS: UnitDef[] = [
  new UnitDef('c', 'degrees Celsius', '°C', 1, (r: number) => r / 10.0),
  new UnitDef('f', 'degrees Fahrenheit', '°F', 0, (r: number) => 9.0 / 5.0 * (r / 10.0) + 32.0),
  new UnitDef('k', 'kelvins', 'K', 1, (r: number) => 273.15 + r / 10.0)
];

/* ---------------------------------------------------------------------- precipitation */

/** PrecipitationUnit.kt. MICROMETER is filtered out by UnitSettingsScreen.kt:106. */
export const PRECIPITATION_UNITS: UnitDef[] = [
  new UnitDef('mm', 'millimeters', 'mm', 1, (r: number) => r / 1000.0),
  new UnitDef('cm', 'centimeters', 'cm', 2, (r: number) => r / 10000.0),
  new UnitDef('in', 'inches', 'in', 2, (r: number) => r / 25400.0),
  // Same magnitude as the millimetre — 1 mm of rain IS 1 L·m⁻², which is why they share a factor.
  new UnitDef('lpsqm', 'liters per square meter', 'L/m²', 1, (r: number) => r / 1000.0)
];

/* ------------------------------------------------------------------------------ speed */

/** SpeedUnit.kt:23-39 — the Beaufort cut-offs, in the reference unit (cm·s⁻¹). */
const BEAUFORT_THRESHOLDS: number[] =
  [30, 160, 340, 550, 800, 1080, 1390, 1720, 2080, 2450, 2850, 3270];

/** SpeedUnit.kt's `bf` branch: the first threshold the value falls under gives the force. */
function beaufort(centimetresPerSecond: number): number {
  for (let i = 0; i < BEAUFORT_THRESHOLDS.length; i++) {
    if (centimetresPerSecond < BEAUFORT_THRESHOLDS[i]) {
      return i;
    }
  }
  return 12;
}

/** SpeedUnit.kt. CENTIMETER_PER_SECOND is filtered out by UnitSettingsScreen.kt:158. */
export const SPEED_UNITS: UnitDef[] = [
  new UnitDef('mps', 'meters per second', 'm/s', 1, (r: number) => r / 100.0, 'meters/sec'),
  new UnitDef('kph', 'kilometers per hour', 'km/h', 1, (r: number) => r * 0.036, 'km/hour'),
  new UnitDef('mph', 'miles per hour', 'mph', 1, (r: number) => r / 44.704, 'miles/hour'),
  new UnitDef('kn', 'knots', 'kn', 1, (r: number) => r * 0.036 / 1.852),
  new UnitDef('ftps', 'feet per second', 'ft/s', 1, (r: number) => r / 30.48, 'feet/sec'),
  // speed_bf_display_name_short is a literal "Bft" (weather-unit strings.xml), which is also the
  // Beaufort table's FIRST column heading.
  new UnitDef('bf', 'Beaufort', 'Bft', 0, (r: number) => beaufort(r))
];

/* --------------------------------------------------------------------------- distance */

/** DistanceUnit.kt — the one list UnitSettingsScreen.kt does NOT filter (kt:193). */
export const DISTANCE_UNITS: UnitDef[] = [
  new UnitDef('m', 'meters', 'm', 0, (r: number) => r),
  new UnitDef('km', 'kilometers', 'km', 1, (r: number) => r / 1000.0),
  new UnitDef('mi', 'miles', 'mi', 1, (r: number) => r / 1609.344),
  new UnitDef('nmi', 'nautical miles', 'nmi', 1, (r: number) => r / 1852.0),
  new UnitDef('ft', 'feet', 'ft', 0, (r: number) => r * 3.28084)
];

/* --------------------------------------------------------------------------- pressure */

/** PressureUnit.kt. PASCAL is filtered out by UnitSettingsScreen.kt:228. */
export const PRESSURE_UNITS: UnitDef[] = [
  new UnitDef('hpa', 'hectopascals', 'hPa', 1, (r: number) => r / 100.0),
  new UnitDef('kpa', 'kilopascals', 'kPa', 2, (r: number) => r / 1000.0),
  new UnitDef('mb', 'millibars', 'mbar', 1, (r: number) => r / 100.0),
  new UnitDef('atm', 'atmospheres', 'atm', 2, (r: number) => r / 101325.0),
  new UnitDef('mmhg', 'millimeters of mercury', 'mmHg', 1, (r: number) => r * (760.0 / 101325.0)),
  new UnitDef('inhg', 'inches of mercury', 'inHg', 2, (r: number) => r * (760.0 / 101325.0) / 25.4)
];

export function unitsFor(family: UnitFamily): UnitDef[] {
  if (family === UnitFamily.TEMPERATURE) {
    return TEMPERATURE_UNITS;
  }
  if (family === UnitFamily.PRECIPITATION) {
    return PRECIPITATION_UNITS;
  }
  if (family === UnitFamily.SPEED) {
    return SPEED_UNITS;
  }
  if (family === UnitFamily.DISTANCE) {
    return DISTANCE_UNITS;
  }
  return PRESSURE_UNITS;
}

export function unitById(family: UnitFamily, id: string): UnitDef | null {
  const list: UnitDef[] = unitsFor(family);
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      return list[i];
    }
  }
  return null;
}

/** Lifts the value our model stores into the family's reference unit. */
export function toReference(family: UnitFamily, modelValue: number): number {
  if (family === UnitFamily.TEMPERATURE) {
    return modelValue * 10.0;      // °C  -> deci-celsius
  }
  if (family === UnitFamily.PRECIPITATION) {
    return modelValue * 1000.0;    // mm  -> µm
  }
  if (family === UnitFamily.SPEED) {
    return modelValue * 100.0;     // m/s -> cm/s
  }
  if (family === UnitFamily.DISTANCE) {
    return modelValue;             // m   -> m
  }
  return modelValue * 100.0;       // hPa -> Pa
}
