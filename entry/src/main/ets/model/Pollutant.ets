/*
 * PollutantIndex — domain/weather/index/PollutantIndex.kt:31-253.
 *
 * The six pollutants the app knows, each with its own concentration bands, and the shared Plume
 * 2023 AQI scale those bands map onto. Everything that needs a pollutant — the mapper, the air
 * quality detail screen's picker, chart, sections and scale table — reads this one table, so the
 * screen and the data can never disagree about a threshold.
 *
 * Concentrations are in µg/m³ for every pollutant EXCEPT carbon monoxide, which Android reads in
 * mg/m³ (AirQuality.kt getConcentration) because that is the unit its thresholds are written in.
 */

import { aqiLevelColor } from '../theme/AppColors';

/** `Color.TRANSPARENT` — what `getColor` returns for a pollutant with no reading (kt:151). */
const TRANSPARENT: string = '#00000000';

/** PollutantIndex.kt:133 — Plume 2023. */
export const AQI_THRESHOLDS: number[] = [0, 20, 50, 100, 150, 250];

/** strings.xml:167-182, indexed by the level from aqiThresholds. */
const AQI_LEVEL_NAMES: string[] =
  ['Excellent', 'Fair', 'Poor', 'Unhealthy', 'Very unhealthy', 'Dangerous'];

/** `air_quality_level_N_description` — the Health information card's text. */
const AQI_LEVEL_DESCRIPTIONS: string[] = [
  'The air quality is ideal for most individuals; enjoy your normal outdoor activities.',
  'The air quality is generally acceptable for most individuals. However, sensitive groups may '
  + 'experience minor to moderate symptoms from long-term exposure.',
  'The air has reached a high level of pollution and is unhealthy for sensitive groups. Reduce '
  + 'time spent outside if you are feeling symptoms such as difficulty breathing or throat '
  + 'irritation.',
  'Health effects can be immediately felt by sensitive groups. Healthy individuals may experience '
  + 'difficulty breathing and throat irritation with prolonged exposure. Limit outdoor activity.',
  'Health effects will be immediately felt by sensitive groups and should avoid outdoor activity. '
  + 'Healthy individuals are likely to experience difficulty breathing and throat irritation; '
  + 'consider staying indoors and rescheduling outdoor activities.',
  'Any exposure to the air, even for a few minutes, can lead to serious health effects on '
  + 'everybody. Avoid outdoor activities.'
];

/** `air_quality_level_N_harmless_exposure` — the scale table's middle column. */
const AQI_HARMLESS_EXPOSURES: string[] =
  ['> 1 year', '< 1 year', '< 1 day', '< 1 hour', '< a few minutes', '< 1 minute'];

/** strings.xml:275, 278 — the two particulate pollutants share one sources paragraph. */
const PM_SOURCES: string =
  'Main sources are combustion processes (e.g. power plants, indoor heating, car exhausts, '
  + 'wildfires), mechanical processes (e.g. construction, mineral dust, agriculture) and '
  + 'biological particles (e.g. pollen, mold, bacteria, viruses).';

/** One entry of the PollutantIndex enum. */
export class PollutantDef {
  /** `id`, and the value the detail screen's picker carries. "" is the AQI itself. */
  readonly id: string;
  /** The concentration bands, in this pollutant's own unit. */
  readonly thresholds: number[];
  /** `maxY` — the chart's floor for its own axis maximum. */
  readonly maxY: number;
  /** `shortName`, e.g. "PM2.5". */
  readonly shortName: string;
  /** `fullName` with its placeholder filled, e.g. "Fine particulate matter (< 2.5 mm)". */
  readonly fullName: string;
  /** `aboutPollutant`, the section heading when this pollutant is picked. */
  readonly aboutHeading: string;
  /** `aboutIndex`, the scale card's heading when this pollutant is picked. */
  readonly scaleHeading: string;
  /** `sources`, the card under the About heading. */
  readonly sources: string;
  /** CO alone is read and shown in mg/m³ (AirQuality.kt getConcentration). */
  readonly milligram: boolean;

  constructor(id: string, thresholds: number[], maxY: number, shortName: string, fullName: string,
    aboutHeading: string, scaleHeading: string, sources: string, milligram: boolean) {
    this.id = id;
    this.thresholds = thresholds;
    this.maxY = maxY;
    this.shortName = shortName;
    this.fullName = fullName;
    this.aboutHeading = aboutHeading;
    this.scaleHeading = scaleHeading;
    this.sources = sources;
    this.milligram = milligram;
  }
}

/**
 * The enum's declaration order (kt:43-128), which is also the order `validPollutants` filters and
 * therefore the order the picker offers them in — except that `validPollutants` lists NO2 and O3
 * first (AirQuality.kt:23-30). That order is applied where the list is built, not here.
 */
export const POLLUTANTS: PollutantDef[] = [
  new PollutantDef('pm25', [0, 5, 15, 30, 60, 150], 60, 'PM2.5',
    'Fine particulate matter (< 2.5 µm)', 'About fine particulate matter (PM2.5)',
    'Air quality index scale for PM2.5', PM_SOURCES, false),
  new PollutantDef('pm10', [0, 15, 45, 80, 160, 400], 160, 'PM10',
    'Inhalable particulate matter (< 10 µm)', 'About inhalable particulate matter (PM10)',
    'Air quality index scale for PM10', PM_SOURCES, false),
  new PollutantDef('o3', [0, 50, 100, 160, 240, 480], 240, 'O3', 'Ground-level ozone (O3)',
    'About ground-level ozone (O3)', 'Air quality index scale for O3',
    'Ozone is created in a chemical reaction between atmospheric oxygen, nitrogen oxides, carbon '
    + 'monoxide and organic compounds, in the presence of sunlight.', false),
  new PollutantDef('no2', [0, 10, 25, 200, 400, 1000], 200, 'NO2', 'Nitrogen dioxide (NO2)',
    'About nitrogen dioxide (NO2)', 'Air quality index scale for NO2',
    'Main sources are fuel burning processes, such as those used in industry and transportation.',
    false),
  new PollutantDef('so2', [0, 20, 40, 270, 500, 960], 270, 'SO2', 'Sulfur dioxide (SO2)',
    'About sulfur dioxide (SO2)', 'Air quality index scale for SO2',
    'Main sources are burning processes of sulfur-containing fuel in industry, transportation and '
    + 'power plants.', false),
  new PollutantDef('co', [0, 2, 4, 35, 100, 230], 35, 'CO', 'Carbon monoxide (CO)',
    'About carbon monoxide (CO)', 'Air quality index scale for CO',
    'Typically originates from incomplete combustion of carbon fuels, such as that which occurs in '
    + 'car engines and power plants.', true)
];

/** `validPollutants` order (AirQuality.kt:23-30) — NO2, O3, PM10, PM2.5, SO2, CO. */
const VALID_POLLUTANT_ORDER: string[] = ['no2', 'o3', 'pm10', 'pm25', 'so2', 'co'];

export function pollutantById(id: string): PollutantDef | null {
  for (const def of POLLUTANTS) {
    if (def.id === id) {
      return def;
    }
  }
  return null;
}

/** One reading's concentrations — the port of `AirQuality`, minus the derived accessors. */
export class AirQualityConcentrations {
  /** µg/m³ */
  pm25: number | null = null;
  /** µg/m³ */
  pm10: number | null = null;
  /** µg/m³ */
  o3: number | null = null;
  /** µg/m³ */
  no2: number | null = null;
  /** µg/m³ */
  so2: number | null = null;
  /** mg/m³ — CO alone, matching the unit its thresholds are in. */
  co: number | null = null;
}

/** `AirQuality.getConcentration` (AirQuality.kt:50-57). */
export function concentrationOf(air: AirQualityConcentrations, id: string): number | null {
  switch (id) {
    case 'pm25':
      return air.pm25;
    case 'pm10':
      return air.pm10;
    case 'o3':
      return air.o3;
    case 'no2':
      return air.no2;
    case 'so2':
      return air.so2;
    case 'co':
      return air.co;
    default:
      return null;
  }
}

/** `thresholds.indexOfLast { value >= it }` (kt:236). */
export function levelOf(value: number, thresholds: number[]): number {
  let level: number = -1;
  for (let i = 0; i < thresholds.length; i++) {
    if (value >= thresholds[i]) {
      level = i;
    }
  }
  return level;
}

/** kt:191-199 — linear interpolation between two band edges. */
function interpolate(value: number, bandLow: number, bandHigh: number,
  indexLow: number, indexHigh: number): number {
  return Math.round((indexHigh - indexLow) / (bandHigh - bandLow) * (value - bandLow) + indexLow);
}

/** `PollutantIndex.getIndex(cp)` (kt:201-214, 234-238) — one pollutant's sub-index. */
export function pollutantIndexOf(def: PollutantDef, concentration: number | null): number | null {
  if (concentration === null) {
    return null;
  }
  const level: number = levelOf(concentration, def.thresholds);
  if (level < 0) {
    return null;
  }
  if (level < def.thresholds.length - 1) {
    return interpolate(concentration, def.thresholds[level], def.thresholds[level + 1],
      AQI_THRESHOLDS[level], AQI_THRESHOLDS[level + 1]);
  }
  // kt:212 — above the last band the index keeps rising linearly.
  return Math.round(concentration * AQI_THRESHOLDS[AQI_THRESHOLDS.length - 1]
    / def.thresholds[def.thresholds.length - 1]);
}

/** `AirQuality.getIndex(null)` (AirQuality.kt:32-48) — the worst of O3, NO2, PM10 and PM2.5. */
export function overallIndexOf(air: AirQualityConcentrations): number | null {
  let worst: number | null = null;
  for (const id of ['o3', 'no2', 'pm10', 'pm25']) {
    const def: PollutantDef | null = pollutantById(id);
    if (def === null) {
      continue;
    }
    const value: number | null = pollutantIndexOf(def, concentrationOf(air, id));
    if (value !== null && (worst === null || value > worst)) {
      worst = value;
    }
  }
  return worst;
}

/** `validPollutants` — the ones this reading actually carries, in the Kotlin's order. */
export function validPollutants(air: AirQualityConcentrations | null): PollutantDef[] {
  const out: PollutantDef[] = [];
  if (air === null) {
    return out;
  }
  for (const id of VALID_POLLUTANT_ORDER) {
    const def: PollutantDef | null = pollutantById(id);
    if (def !== null && concentrationOf(air, id) !== null) {
      out.push(def);
    }
  }
  return out;
}

/** `getAqiToName` (kt:160-164). */
export function aqiLevelName(aqi: number): string {
  const level: number = levelOf(aqi, AQI_THRESHOLDS);
  return level >= 0 && level < AQI_LEVEL_NAMES.length ? AQI_LEVEL_NAMES[level] : '';
}

/** `getAqiToDescription` (kt:166-170) — the Health information card. */
export function aqiLevelDescription(aqi: number): string {
  const level: number = levelOf(aqi, AQI_THRESHOLDS);
  return level >= 0 && level < AQI_LEVEL_DESCRIPTIONS.length ? AQI_LEVEL_DESCRIPTIONS[level] : '';
}

/** `getAqiToHarmlessExposure` (kt:172-180) — the scale table's middle column, by LEVEL. */
export function aqiHarmlessExposureAt(level: number): string {
  return level >= 0 && level < AQI_HARMLESS_EXPOSURES.length ? AQI_HARMLESS_EXPOSURES[level] : '';
}

/** `getName` for a pollutant — its concentration's index, named on the shared scale. */
export function pollutantLevelName(def: PollutantDef, concentration: number | null): string {
  const index: number | null = pollutantIndexOf(def, concentration);
  return index === null ? '' : aqiLevelName(index);
}

/** `getColor` for a pollutant, or for the overall index when `def` is null. */
export function pollutantColor(def: PollutantDef | null, air: AirQualityConcentrations): string {
  const index: number | null = def === null
    ? overallIndexOf(air)
    : pollutantIndexOf(def, concentrationOf(air, def.id));
  return index === null ? TRANSPARENT : aqiLevelColor(index);
}

/** `PollutantConcentrationUnit`'s short label — "µg/m³", or "mg/m³" for carbon monoxide. */
export function concentrationUnitLabel(def: PollutantDef): string {
  return def.milligram ? 'mg/m³' : 'µg/m³';
}

/** `formatMeasure(SHORT)` — no decimals in either unit, then a space and the unit. */
export function formatConcentration(def: PollutantDef, value: number): string {
  return Math.round(value).toString() + ' ' + concentrationUnitLabel(def);
}
