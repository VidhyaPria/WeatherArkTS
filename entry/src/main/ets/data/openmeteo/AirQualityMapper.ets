/*
 * Air quality and pollen, from the Open-Meteo air-quality endpoint.
 *
 * Ports of:
 *   PollutantIndex                     domain/weather/index/PollutantIndex.kt:31-253
 *   AirQuality.getIndex                domain/weather/model/AirQuality.kt:36-48
 *   PollenIndex                        domain/weather/index/PollenIndex.kt:34-61
 *   Pollen.getIndex / pollensWith...   domain/weather/model/Pollen.kt:34-47
 *
 * The overall AQI is the worst of the O3, NO2, PM10 and PM2.5 sub-indices (AirQuality.kt:38-44).
 * Each sub-index is a piecewise-linear interpolation of the pollutant's concentration bands onto
 * the shared aqiThresholds [0, 20, 50, 100, 150, 250] (PollutantIndex.kt:133, 191-214) — the
 * Plume 2023 scale, not the US EPA one.
 *
 * Level names: strings.xml:167-182 (air quality) and 301-305 (pollen).
 */

import { PollenEntry } from '../../model/Weather';
import { AirQualityConcentrations, levelOf, overallIndexOf } from '../../model/Pollutant';
import { OpenMeteoAirQualityHourly } from './OpenMeteoJson';

/*
 * The pollutant table, the AQI scale and every derivation off them now live in
 * `model/Pollutant.ets`, because the air-quality DETAIL screen needs the same thresholds, names
 * and colours the mapper does. A second copy here is what made the screen and the data disagree
 * about a boundary once already.
 */

/** strings.xml:301-305 */
const POLLEN_LEVEL_NAMES: string[] = ['Very low', 'Low', 'Moderate', 'High', 'Very high'];

/** Reads index i of a possibly-absent series. */
function at(series: (number | null)[] | undefined, i: number): number | null {
  if (series === undefined || i < 0 || i >= series.length) {
    return null;
  }
  const value: number | null = series[i];
  return value === undefined ? null : value;
}

/** The entry in the hourly series covering `now`, or -1. */
function currentHourIndex(times: number[], now: Date): number {
  const nowSeconds: number = Math.floor(now.getTime() / 1000);
  let best: number = -1;
  for (let i = 0; i < times.length; i++) {
    if (times[i] <= nowSeconds) {
      best = i;
    }
  }
  return best;
}

/**
 * One hour's six concentrations — OpenMeteoService.getAirQuality (kt:498-518).
 *
 * Every series is µg/m³ on the wire; carbon monoxide is divided by 1000 because Android reads it
 * in mg/m³ (AirQuality.kt getConcentration), which is the unit its thresholds are written in.
 */
function concentrationsAt(hourly: OpenMeteoAirQualityHourly, i: number): AirQualityConcentrations {
  const air = new AirQualityConcentrations();
  air.pm25 = at(hourly.pm2_5, i);
  air.pm10 = at(hourly.pm10, i);
  air.o3 = at(hourly.ozone, i);
  air.no2 = at(hourly.nitrogen_dioxide, i);
  air.so2 = at(hourly.sulphur_dioxide, i);
  const carbonMonoxide: number | null = at(hourly.carbon_monoxide, i);
  air.co = carbonMonoxide === null ? null : carbonMonoxide / 1000.0;
  return air;
}

export function currentAirQuality(
  hourly: OpenMeteoAirQualityHourly,
  now: Date
): AirQualityConcentrations | null {
  const i: number = currentHourIndex(hourly.time, now);
  return i < 0 ? null : concentrationsAt(hourly, i);
}

export function currentAirQualityIndex(hourly: OpenMeteoAirQualityHourly, now: Date): number | null {
  const air: AirQualityConcentrations | null = currentAirQuality(hourly, now);
  return air === null ? null : overallIndexOf(air);
}

/** One hour's air quality, keyed by the instant the hour starts. */
export class HourlyAirQuality {
  readonly startMs: number;
  readonly index: number | null;
  readonly concentrations: AirQualityConcentrations;

  constructor(startMs: number, index: number | null, concentrations: AirQualityConcentrations) {
    this.startMs = startMs;
    this.index = index;
    this.concentrations = concentrations;
  }
}

/**
 * The whole hourly index series — what the Air quality trend tab plots.
 *
 * The pollutant series were already being fetched for the current-conditions tile; the tab just
 * needs the same `AirQuality.getIndex` evaluated for every hour instead of only for `now`, which
 * is what HourlyAirQualityAdapter reads off `Hourly.airQuality`.
 */
export function airQualitySeries(hourly: OpenMeteoAirQualityHourly): HourlyAirQuality[] {
  const out: HourlyAirQuality[] = [];
  for (let i = 0; i < hourly.time.length; i++) {
    const air: AirQualityConcentrations = concentrationsAt(hourly, i);
    out.push(new HourlyAirQuality(hourly.time[i] * 1000, overallIndexOf(air), air));
  }
  return out;
}

/** One allergen the endpoint reports, with its Atmo France bands (PollenIndex.kt:34-61). */
class PollenSpecies {
  readonly name: string;
  readonly thresholds: number[];
  readonly series: (number | null)[] | undefined;

  constructor(name: string, thresholds: number[], series: (number | null)[] | undefined) {
    this.name = name;
    this.thresholds = thresholds;
    this.series = series;
  }
}

/**
 * Every allergen the hour REPORTS — `Pollen.validPollens` (Pollen.kt:27-30), i.e. concentration
 * not null.
 *
 * The "> 0" filter is `pollensWithConcentration` (kt:32-38) and belongs to the MAIN SCREEN's block
 * alone; the detail screen's `PollenGrid` lists the valid ones (AllergenComposables.kt:69), so a
 * species reading exactly 0 belongs there and used to be dropped by the mapper before either
 * consumer could see it.
 */
export function currentPollen(hourly: OpenMeteoAirQualityHourly, now: Date): PollenEntry[] {
  const i: number = currentHourIndex(hourly.time, now);
  if (i < 0) {
    return [];
  }
  const species: PollenSpecies[] = [
    new PollenSpecies('Alder', [0, 10, 60, 100, 500], hourly.alder_pollen),
    new PollenSpecies('Birch', [0, 10, 60, 100, 500], hourly.birch_pollen),
    new PollenSpecies('Grass', [0, 3, 30, 50, 250], hourly.grass_pollen),
    new PollenSpecies('Mugwort', [0, 3, 30, 50, 250], hourly.mugwort_pollen),
    new PollenSpecies('Olive', [0, 20, 100, 200, 500], hourly.olive_pollen),
    new PollenSpecies('Ragweed', [0, 3, 30, 50, 250], hourly.ragweed_pollen)
  ];

  const rows: PollenEntry[] = [];
  for (let s = 0; s < species.length; s++) {
    const concentration: number | null = at(species[s].series, i);
    if (concentration === null) {
      continue;
    }
    const level: number = levelOf(concentration, species[s].thresholds);
    if (level < 0) {
      continue;
    }
    const row = new PollenEntry();
    row.name = species[s].name;
    row.level = level;
    row.levelName = POLLEN_LEVEL_NAMES[level];
    row.concentration = concentration;
    rows.push(row);
  }
  return rows;
}
