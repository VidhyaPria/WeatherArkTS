/*
 * Assembles a Weather from the Open-Meteo responses.
 *
 * Stands in for RefreshHelper + WeatherRepository on the Android side: it issues the requests,
 * maps them, then does the post-processing the views depend on —
 *   todayIndex          Weather.kt — the index of today within dailyForecast
 *   nextHourlyForecast  Weather.kt — the hourly series trimmed to "from this hour on"
 *   refreshTime         drives the "x min. ago" line in the header
 *
 * Not yet sourced from the network, and carried over from the previous mock so the cards keep
 * rendering (each is a separate port, called out in the handover):
 *   - sun/moon times and moon phase: Open-Meteo does not return them; the Android app computes
 *     them locally in CommonConverter.kt and needs that astronomy code ported
 *   - air quality index and pollen levels: the second endpoint is already fetched below, but the
 *     European AQI banding and the pollen level thresholds are their own conversion
 *   - normals (the "Normal" key lines) come from a different source entirely on Android
 */

import { Astro, Current, Daily, Hourly, trimHourlyFromNow, Weather } from '../model/Weather';
import { AstroPair, calculatedMoon, calculatedSun, moonPhaseAngle, moonPhaseName } from './Astronomy';
import { getClockTime } from '../common/Formatter';
import { DAY_MS, localHours, localStartOfDay, localStartOfHour } from '../common/LocalTime';
import { fetchAirQuality, fetchForecast } from './openmeteo/OpenMeteoApi';
import { OpenMeteoAirQualityResult, OpenMeteoWeatherResult } from './openmeteo/OpenMeteoJson';
import {
  buildCurrent,
  buildDailyList,
  buildHourlyList,
  buildMinutelyList,
  hourlyPrecipitation
} from './openmeteo/OpenMeteoMapper';
import {
  airQualitySeries,
  currentAirQuality,
  currentAirQualityIndex,
  currentPollen,
  HourlyAirQuality
} from './openmeteo/AirQualityMapper';
import { AirQualityConcentrations, overallIndexOf } from '../model/Pollutant';

/**
 * Helsinki, matching the location the Android build opens on. Coordinates are what Open-Meteo's
 * own geocoding returns for the city, so both apps resolve the same grid cell.
 */
export class Coordinates {
  readonly latitude: number;
  readonly longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

export const HELSINKI = new Coordinates(60.1695, 24.9354);

/** Weather.kt — the index within dailyForecast whose date is today AT THE LOCATION. */
function findTodayIndex(daily: Daily[], utcOffsetSeconds: number): number | null {
  const todayStart: number = localStartOfDay(new Date(), utcOffsetSeconds);
  for (let i = 0; i < daily.length; i++) {
    if (daily[i].date.getTime() === todayStart) {
      return i;
    }
  }
  return null;
}

// Weather.nextHourlyForecast's rule lives on the model as `trimHourlyFromNow`, because the cache
// reload has to apply the same one to the full series it persists.

/**
 * MainAdapter.kt:122-137 — the precipitation card shows the total for the half-day the current
 * hour falls in: before 05:00 yesterday's night, before 17:00 today's day, otherwise tonight.
 */
function currentHalfDayPrecipitation(
  daily: Daily[],
  todayIndex: number | null,
  utcOffsetSeconds: number
): number | null {
  if (todayIndex === null) {
    return null;
  }
  const today: Daily | undefined = daily[todayIndex];
  if (today === undefined) {
    return null;
  }
  const hour: number = localHours(new Date(), utcOffsetSeconds);
  if (hour < 5) {
    const yesterday: Daily | undefined = daily[todayIndex - 1];
    return yesterday !== undefined && yesterday.night !== null ? yesterday.night.precipitationTotal : null;
  }
  if (hour < 17) {
    return today.day !== null ? today.day.precipitationTotal : null;
  }
  return today.night !== null ? today.night.precipitationTotal : null;
}

/** getCalculatedAstroSun (kt:503-560) turned into the Astro the astro block renders. */
function buildSunAstro(coordinates: Coordinates, now: Date, utcOffsetSeconds: number): Astro {
  const pair: AstroPair =
    calculatedSun(now, coordinates.latitude, coordinates.longitude, utcOffsetSeconds);
  const astro = new Astro();
  astro.riseDate = pair.rise;
  astro.setDate = pair.set;
  astro.riseTime = pair.rise === null ? '' : getClockTime(pair.rise, utcOffsetSeconds);
  astro.setTime = pair.set === null ? '' : getClockTime(pair.set, utcOffsetSeconds);
  return astro;
}

/**
 * getCalculatedAstroMoon (kt:562-616) plus the "validated" pick AstroViewHolder.kt:103-115 makes:
 * before tonight's moonrise the card shows YESTERDAY's moon, provided it has not set yet — which
 * is why an evening screen reads "10:14 PM → 2:44 PM" with the set time earlier than the rise.
 */
function buildMoonAstro(coordinates: Coordinates, now: Date, utcOffsetSeconds: number): Astro {
  let pair: AstroPair =
    calculatedMoon(now, coordinates.latitude, coordinates.longitude, utcOffsetSeconds);
  if (pair.rise === null || now.getTime() < pair.rise.getTime()) {
    const yesterday = new Date(now.getTime() - DAY_MS);
    const previousPair: AstroPair =
      calculatedMoon(yesterday, coordinates.latitude, coordinates.longitude, utcOffsetSeconds);
    if (previousPair.rise !== null && previousPair.set !== null &&
      previousPair.set.getTime() > now.getTime()) {
      pair = previousPair;
    }
  }
  const astro = new Astro();
  astro.riseDate = pair.rise;
  astro.setDate = pair.set;
  astro.riseTime = pair.rise === null ? '' : getClockTime(pair.rise, utcOffsetSeconds);
  astro.setTime = pair.set === null ? '' : getClockTime(pair.set, utcOffsetSeconds);
  // kt:621-632 — the phase belongs to today regardless of which day's rise/set won above.
  astro.phaseAngle = moonPhaseAngle(now, utcOffsetSeconds);
  astro.phase = moonPhaseName(astro.phaseAngle);
  return astro;
}

/** getDailyAirQualityFromHourlyList (CommonConverter.kt:520-542) needs 18 hours to answer. */
const DAILY_AIR_QUALITY_MIN_HOURS: number = 18;

/** The mean of the readings that HAVE this pollutant, or null when none of them do (kt:527-541). */
function meanOf(values: number[]): number | null {
  if (values.length === 0) {
    return null;
  }
  let total: number = 0;
  for (const value of values) {
    total += value;
  }
  return total / values.length;
}

/**
 * Spreads the hourly air quality onto the forecast, so the Air quality trend tabs have a series to
 * plot and the detail screen has per-pollutant concentrations.
 *
 * `Hourly.airQuality` comes straight from the matching hour. `Daily.airQuality` is
 * `getDailyAirQualityFromHourlyList` (kt:424-427, 520-542): the MEAN of the day's hourly
 * concentrations, pollutant by pollutant, and only when the day has at least 18 of them. The day's
 * index is then that averaged reading's index, NOT the worst hour — which is what this used to
 * compute, and it read high on any day with one bad hour.
 *
 * The air-quality endpoint only covers 7 days against the forecast's 16, so later days stay null
 * and their columns simply have no bar, exactly as they do on Android.
 */
function applyAirQualitySeries(
  weather: Weather,
  series: HourlyAirQuality[],
  utcOffsetSeconds: number
): void {
  const byHour: Map<number, HourlyAirQuality> = new Map();
  for (let i = 0; i < series.length; i++) {
    byHour.set(series[i].startMs, series[i]);
  }

  for (let i = 0; i < weather.nextHourlyForecast.length; i++) {
    const hour: Hourly = weather.nextHourlyForecast[i];
    const entry: HourlyAirQuality | undefined = byHour.get(hour.date.getTime());
    if (entry !== undefined) {
      hour.airQualityIndex = entry.index;
      hour.airQuality = entry.concentrations;
    }
  }

  // The daily average has to consider every hour of the day, not just the ones from now on.
  const hoursByDay: Map<number, AirQualityConcentrations[]> = new Map();
  byHour.forEach((entry: HourlyAirQuality, startMs: number) => {
    const day: number = localStartOfDay(new Date(startMs), utcOffsetSeconds);
    const bucket: AirQualityConcentrations[] | undefined = hoursByDay.get(day);
    if (bucket === undefined) {
      hoursByDay.set(day, [entry.concentrations]);
    } else {
      bucket.push(entry.concentrations);
    }
  });

  for (let i = 0; i < weather.dailyForecast.length; i++) {
    const daily: Daily = weather.dailyForecast[i];
    const bucket: AirQualityConcentrations[] | undefined = hoursByDay.get(daily.date.getTime());
    if (bucket === undefined || bucket.length < DAILY_AIR_QUALITY_MIN_HOURS) {
      continue;
    }
    const pm25: number[] = [];
    const pm10: number[] = [];
    const o3: number[] = [];
    const no2: number[] = [];
    const so2: number[] = [];
    const co: number[] = [];
    for (const air of bucket) {
      if (air.pm25 !== null) {
        pm25.push(air.pm25);
      }
      if (air.pm10 !== null) {
        pm10.push(air.pm10);
      }
      if (air.o3 !== null) {
        o3.push(air.o3);
      }
      if (air.no2 !== null) {
        no2.push(air.no2);
      }
      if (air.so2 !== null) {
        so2.push(air.so2);
      }
      if (air.co !== null) {
        co.push(air.co);
      }
    }
    const average = new AirQualityConcentrations();
    average.pm25 = meanOf(pm25);
    average.pm10 = meanOf(pm10);
    average.o3 = meanOf(o3);
    average.no2 = meanOf(no2);
    average.so2 = meanOf(so2);
    average.co = meanOf(co);
    daily.airQuality = average;
    daily.airQualityIndex = overallIndexOf(average);
  }
}

/** Everything one refresh produces: the weather, plus the two location fields it updates. */
export class RefreshResult {
  readonly weather: Weather;
  /** Open-Meteo's `utc_offset_seconds` for the resolved grid cell. */
  readonly utcOffsetSeconds: number;
  /** Location.isDaylight (Location.kt:45-52) — now between today's sunrise and sunset. */
  readonly daylight: boolean;

  constructor(weather: Weather, utcOffsetSeconds: number, daylight: boolean) {
    this.weather = weather;
    this.utcOffsetSeconds = utcOffsetSeconds;
    this.daylight = daylight;
  }
}

/**
 * Location.isDaylight (Location.kt:45-52): `0 < getRiseProgress(today.sun) < 1`, i.e. now falls
 * strictly between today's sunrise and sunset.
 *
 * The port used to fake this with `hour >= 7 && hour < 20` from the seeded mock, which is why the
 * day/night theme, the background gradient and the icon set could all disagree with reality —
 * most visibly in a Nordic summer, where 7 pm is broad daylight and Helsinki's sun sets at 21:39.
 */
function isDaylightNow(sun: Astro, now: Date): boolean {
  if (sun.riseDate === null || sun.setDate === null) {
    return true;
  }
  const at: number = now.getTime();
  return at > sun.riseDate.getTime() && at < sun.setDate.getTime();
}

/** Fetches and maps everything for one location, leaving the caller to swap it in. */
export async function fetchWeather(
  coordinates: Coordinates,
  previous: Weather | null,
  /**
   * The location's Open-Meteo model selection, already resolved to ids. '' takes the source's own
   * default (`best_match`), which is what a location that has never been through the per-location
   * preferences dialog stores.
   */
  models: string = ''
): Promise<RefreshResult> {
  // The two calls hit different hosts and neither depends on the other, so they go out together.
  // OpenMeteoService.kt:180-330 does the same thing — the Rx chain zips the two Observables rather
  // than chaining them, so Android pays one round trip, not two. Awaiting them in sequence was
  // adding the air-quality latency (~0.4 s) to every refresh for nothing.
  //
  // The air-quality leg is caught here rather than at the Promise.all, so a failure there cannot
  // reject the pair and lose the forecast with it (kt:327-330 records a failed feature and keeps
  // going). It resolves to null instead.
  const forecastPromise: Promise<OpenMeteoWeatherResult> =
    fetchForecast(coordinates.latitude, coordinates.longitude, models);
  const airQualityPromise: Promise<OpenMeteoAirQualityResult | null> =
    fetchAirQuality(coordinates.latitude, coordinates.longitude)
      .then((result: OpenMeteoAirQualityResult) => result as OpenMeteoAirQualityResult | null)
      .catch((error: Error) => {
        // A failed air-quality call must not lose the forecast — Android records it as a failed
        // feature and still shows what it has (OpenMeteoService.kt:327-330). The two cards simply
        // drop out, exactly as MainAdapter.kt:141-148 does when the values are absent.
        console.warn('Open-Meteo air quality request failed: ' + error.message);
        return null;
      });

  const forecast: OpenMeteoWeatherResult = await forecastPromise;

  const weather = new Weather();
  const now = new Date();
  weather.refreshTime = now;

  // Every date below is interpreted in the LOCATION's zone, which is what Open-Meteo reports for
  // the grid cell it resolved — not the device's.
  const utcOffsetSeconds: number = forecast.utc_offset_seconds !== null &&
    forecast.utc_offset_seconds !== undefined
    ? forecast.utc_offset_seconds
    : 0;

  if (forecast.hourly !== null && forecast.hourly !== undefined) {
    const hourly: Hourly[] = buildHourlyList(forecast.hourly);
    const precipitation: number[] = hourlyPrecipitation(forecast.hourly);
    weather.hourlyForecast = hourly;
    weather.nextHourlyForecast = trimHourlyFromNow(hourly, utcOffsetSeconds);
    if (forecast.daily !== null && forecast.daily !== undefined) {
      weather.dailyForecast = buildDailyList(forecast.daily, hourly, precipitation, utcOffsetSeconds);
    }
  }
  weather.todayIndex = findTodayIndex(weather.dailyForecast, utcOffsetSeconds);

  if (forecast.minutely_15 !== null && forecast.minutely_15 !== undefined) {
    weather.minutelyForecast = buildMinutelyList(forecast.minutely_15);
  }

  // Sun and moon are computed locally, exactly as completeDailyListFromHourlyList does for every
  // day (kt:402-423) — Open-Meteo returns none of it.
  const sun: Astro = buildSunAstro(coordinates, now, utcOffsetSeconds);
  const moon: Astro = buildMoonAstro(coordinates, now, utcOffsetSeconds);

  if (forecast.current !== null && forecast.current !== undefined) {
    const current: Current = buildCurrent(forecast.current);
    current.precipitationTotal =
      currentHalfDayPrecipitation(weather.dailyForecast, weather.todayIndex, utcOffsetSeconds);
    current.sun = sun;
    current.moon = moon;
    weather.current = current;
  }

  // `weather.normals` is deliberately left null. Open-Meteo is not a NORMALS source: Android fills
  // it only from a separately configured `normalsSource` (RefreshHelper.kt:884-898), so an
  // Open-Meteo-only build has none and DailyTemperatureAdapter simply draws no "Normal" key lines.
  // The port used to carry a fabricated 23 °C / 14 °C pair forward from the seeded mock.

  const airQuality: OpenMeteoAirQualityResult | null = await airQualityPromise;
  if (airQuality !== null && airQuality.hourly !== null && airQuality.hourly !== undefined) {
    if (weather.current !== null) {
      weather.current.airQualityIndex = currentAirQualityIndex(airQuality.hourly, now);
      weather.current.airQuality = currentAirQuality(airQuality.hourly, now);
      weather.current.pollen = currentPollen(airQuality.hourly, now);
    }
    applyAirQualitySeries(weather, airQualitySeries(airQuality.hourly), utcOffsetSeconds);
  }

  return new RefreshResult(weather, utcOffsetSeconds, isDaylightNow(sun, now));
}
