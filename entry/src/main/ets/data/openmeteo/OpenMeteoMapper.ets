/*
 * Open-Meteo response -> our model.
 *
 * Ports of:
 *   OpenMeteoService.getCurrent          kt:379-404
 *   OpenMeteoService.getHourlyList       kt:455-496
 *   OpenMeteoService.getDailyList        kt:406-453
 *   OpenMeteoService.getWeatherText      kt:571-607
 *   OpenMeteoService.getWeatherCode      kt:609-631
 *
 * Weather text strings resolve through strings.xml — the openmeteo_weather_text_* entries are
 * aliases of common_weather_text_* (strings.xml:936-978), so the English values are inlined here.
 *
 * Two things Open-Meteo does NOT return, and which the Android app therefore computes itself in
 * CommonConverter.kt, are not filled in by this mapper:
 *   - day/night HalfDay splits, which come from completeDailyListFromHourlyList; the essential
 *     part of that (grouping the hourly series by local day and half-day) is done below
 *   - sunrise/sunset/moonrise/moonset/moon phase, which come from an astronomy calculation
 * See buildDailyList's note on what is derived versus still missing.
 */

import { WeatherKind } from '../../model/WeatherKind';
import {
  Current,
  Daily,
  HalfDay,
  Hourly,
  Minutely,
  PrecipitationProbability,
  Temperature
} from '../../model/Weather';
import { OpenMeteoCurrent, OpenMeteoDaily, OpenMeteoHourly, OpenMeteoMinutely } from './OpenMeteoJson';
import { localHours, localStartOfDay } from '../../common/LocalTime';

/** OpenMeteoService.kt:571-607 */
export function weatherText(code: number | null): string | null {
  switch (code) {
    case 0: return 'Clear sky';
    case 1: return 'Mostly clear';
    case 2: return 'Partly cloudy';
    case 3: return 'Overcast';
    case 45: return 'Fog';
    case 48: return 'Depositing rime fog';
    case 51: return 'Light drizzle';
    case 53: return 'Moderate drizzle';
    case 55: return 'Heavy drizzle';
    case 56: return 'Light freezing drizzle';
    case 57: return 'Heavy freezing drizzle';
    case 61: return 'Light rain';
    case 63: return 'Moderate rain';
    case 65: return 'Heavy rain';
    case 66: return 'Light freezing rain';
    case 67: return 'Heavy freezing rain';
    case 71: return 'Light snow';
    case 73: return 'Moderate snow';
    case 75: return 'Heavy snow';
    case 77: return 'Snow grains';
    case 80: return 'Light rain showers';
    case 81: return 'Moderate rain showers';
    case 82: return 'Heavy rain showers';
    case 85: return 'Light snow showers';
    case 86: return 'Heavy snow showers';
    case 95: return 'Thunderstorm slight or moderate';
    case 96: return 'Thunderstorm with slight hail';
    case 99: return 'Thunderstorm with heavy hail';
    default: return null;
  }
}

/** OpenMeteoService.kt:609-631 */
export function weatherKind(code: number | null): WeatherKind {
  if (code === null) {
    return WeatherKind.NULL;
  }
  if (code === 0 || code === 1) {
    return WeatherKind.CLEAR;
  }
  if (code === 2) {
    return WeatherKind.CLOUD;
  }
  if (code === 3) {
    return WeatherKind.CLOUDY;
  }
  if (code === 45 || code === 48) {
    return WeatherKind.FOG;
  }
  // 51/53/55 drizzle, 56/57 freezing drizzle, 61/63/65 rain, 66/67 freezing rain,
  // 80/81/82 rain showers (kt:618-623).
  if ((code >= 51 && code <= 57) || (code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
    return WeatherKind.RAINY;
  }
  if ((code >= 71 && code <= 75) || code === 85 || code === 86) {
    return WeatherKind.SNOW;
  }
  if (code === 77) {
    return WeatherKind.SLEET;
  }
  if (code === 95 || code === 96 || code === 99) {
    return WeatherKind.THUNDERSTORM;
  }
  return WeatherKind.NULL;
}

/** Reads index i of a possibly-absent series, collapsing undefined to null. */
function at(series: (number | null)[] | undefined, i: number): number | null {
  if (series === undefined || i < 0 || i >= series.length) {
    return null;
  }
  const value: number | null = series[i];
  return value === undefined ? null : value;
}

function orNull(value: number | null | undefined): number | null {
  return value === undefined || value === null ? null : value;
}

function temperature(value: number | null, feelsLike: number | null): Temperature | null {
  if (value === null && feelsLike === null) {
    return null;
  }
  const t = new Temperature();
  t.temperature = value;
  t.feelsLikeTemperature = feelsLike;
  return t;
}

/**
 * Kotlin's `a + b` on two nullable numbers (the `Double?.plus` the Open-Meteo service uses at
 * kt:475): null only when BOTH sides are null, otherwise the sum of the ones that are present.
 */
function sumOrNull(a: number | null, b: number | null): number | null {
  if (a === null && b === null) {
    return null;
  }
  return (a === null ? 0 : a) + (b === null ? 0 : b);
}

function probability(total: number | null): PrecipitationProbability | null {
  if (total === null) {
    return null;
  }
  const p = new PrecipitationProbability();
  p.total = total;
  return p;
}

/** OpenMeteoService.getCurrent — kt:379-404. Speeds already arrive in m·s⁻¹ (windspeed_unit=ms). */
export function buildCurrent(source: OpenMeteoCurrent): Current {
  const current = new Current();
  const code: number | null = orNull(source.weather_code);
  current.weatherText = weatherText(code);
  current.weatherKind = weatherKind(code);
  current.temperature = temperature(orNull(source.temperature_2m), orNull(source.apparent_temperature));
  current.windSpeed = orNull(source.wind_speed_10m);
  current.windDegree = orNull(source.wind_direction_10m);
  current.windGusts = orNull(source.wind_gusts_10m);
  current.uvIndex = orNull(source.uv_index);
  current.relativeHumidity = orNull(source.relative_humidity_2m);
  current.dewPoint = orNull(source.dew_point_2m);
  current.pressure = orNull(source.pressure_msl);
  current.visibility = orNull(source.visibility);
  return current;
}

/** OpenMeteoService.getHourlyList — kt:455-496. */
export function buildHourlyList(source: OpenMeteoHourly): Hourly[] {
  const list: Hourly[] = [];
  for (let i = 0; i < source.time.length; i++) {
    const hourly = new Hourly();
    // timeformat=unixtime gives epoch seconds.
    hourly.date = new Date(source.time[i] * 1000);
    const code: number | null = at(source.weather_code, i);
    hourly.weatherText = weatherText(code);
    hourly.weatherKind = weatherKind(code);
    const isDay: number | null = at(source.is_day, i);
    hourly.daylight = isDay === null ? true : isDay > 0;
    hourly.temperature = temperature(at(source.temperature_2m, i), at(source.apparent_temperature, i));
    hourly.precipitationProbability = probability(at(source.precipitation_probability, i));
    hourly.relativeHumidity = at(source.relative_humidity_2m, i);
    hourly.dewPoint = at(source.dew_point_2m, i);
    hourly.precipitationTotal = at(source.precipitation, i);
    /*
     * kt:475-476 — rain is `rain + showers` (either may be absent, and the Kotlin's nullable plus
     * yields null only when BOTH are), and snow is `snowfall` read as CENTIMETRES, so it is ×10 to
     * reach this model's millimetres.
     */
    hourly.precipitationRain = sumOrNull(at(source.rain, i), at(source.showers, i));
    const snowfallCm: number | null = at(source.snowfall, i);
    hourly.precipitationSnow = snowfallCm === null ? null : snowfallCm * 10.0;
    hourly.pressure = at(source.pressure_msl, i);
    hourly.cloudCover = at(source.cloud_cover, i);
    hourly.visibility = at(source.visibility, i);
    hourly.uvIndex = at(source.uv_index, i);
    hourly.windSpeed = at(source.wind_speed_10m, i);
    hourly.windDegree = at(source.wind_direction_10m, i);
    hourly.windGusts = at(source.wind_gusts_10m, i);
    list.push(hourly);
  }
  return list;
}

/** Midnight AT THE LOCATION for a date, used to bucket the hourly series into days. */
function startOfDay(date: Date, utcOffsetSeconds: number): number {
  return localStartOfDay(date, utcOffsetSeconds);
}

/**
 * The half-day aggregation from CommonConverter.completeDailyListFromHourlyList: Open-Meteo has
 * no day/night split, so each day's 06:00-17:59 hours become `day` and the rest `night`. The
 * representative weather code is the most severe in the window, the precipitation total is the
 * sum, and the probability and wind are the maxima.
 */
function buildHalfDay(hours: Hourly[], precipitation: number[], isDay: boolean): HalfDay | null {
  if (hours.length === 0) {
    return null;
  }
  const half = new HalfDay();
  let extremeTemp: number | null = null;
  let extremeFeels: number | null = null;
  let maxProbability: number | null = null;
  let maxWind: number | null = null;
  let windDegree: number | null = null;
  // getHalfDayWindFromHourlyList: the gust maximum is taken over the WHOLE half-day, not from the
  // hour that won the speed — `maxWind.copy(gusts = maxWindGusts)`.
  let maxGusts: number | null = null;
  let precipitationTotal: number = 0;
  /*
   * getHalfDayPrecipitationFromHourlyList (CommonConverter.kt:978-1018): each part is the SUM of
   * the hours that report it, and null when NONE of them does — which is what keeps the "Rain" and
   * "Snow" rows off the detail screen for a source that reports neither.
   */
  let rainTotal: number = 0;
  let rainCount: number = 0;
  let snowTotal: number = 0;
  let snowCount: number = 0;
  let cloudCoverTotal: number = 0;
  let cloudCoverCount: number = 0;
  let visibilityTotal: number = 0;
  let visibilityCount: number = 0;

  for (let i = 0; i < hours.length; i++) {
    const hour: Hourly = hours[i];
    if (hour.cloudCover !== null) {
      cloudCoverTotal += hour.cloudCover;
      cloudCoverCount++;
    }
    if (hour.visibility !== null) {
      visibilityTotal += hour.visibility;
      visibilityCount++;
    }
    // getHalfDayTemperatureFromHourlyList (CommonConverter.kt:921-948): the day half takes the
    // MAX of its hours, the night half the MIN — for the real and the feels-like temperature
    // alike. This used to take the max for both, which is why the header read "Night: 72°"
    // where the Android device read "Night: 65°".
    if (hour.temperature !== null && hour.temperature.temperature !== null) {
      const t: number = hour.temperature.temperature;
      if (extremeTemp === null || (isDay ? t > extremeTemp : t < extremeTemp)) {
        extremeTemp = t;
      }
    }
    if (hour.temperature !== null && hour.temperature.feelsLikeTemperature !== null) {
      const f: number = hour.temperature.feelsLikeTemperature;
      if (extremeFeels === null || (isDay ? f > extremeFeels : f < extremeFeels)) {
        extremeFeels = f;
      }
    }
    if (hour.precipitationProbability !== null && hour.precipitationProbability.total !== null) {
      if (maxProbability === null || hour.precipitationProbability.total > maxProbability) {
        maxProbability = hour.precipitationProbability.total;
      }
    }
    if (hour.windSpeed !== null && (maxWind === null || hour.windSpeed > maxWind)) {
      maxWind = hour.windSpeed;
      windDegree = hour.windDegree;
    }
    if (hour.windGusts !== null && (maxGusts === null || hour.windGusts > maxGusts)) {
      maxGusts = hour.windGusts;
    }
    precipitationTotal += precipitation[i];
    if (hour.precipitationRain !== null) {
      rainTotal += hour.precipitationRain;
      rainCount++;
    }
    if (hour.precipitationSnow !== null) {
      snowTotal += hour.precipitationSnow;
      snowCount++;
    }
  }

  half.weatherKind = halfDayWeatherKind(
    hours,
    precipitationTotal,
    maxProbability,
    maxWind,
    cloudCoverCount > 0 ? cloudCoverTotal / cloudCoverCount : null,
    visibilityCount > 0 ? visibilityTotal / visibilityCount : null
  );
  half.weatherText = weatherTextForKind(half.weatherKind);
  half.temperature = temperature(extremeTemp, extremeFeels);
  half.precipitationProbability = probability(maxProbability);
  half.precipitationTotal = precipitationTotal;
  half.precipitationRain = rainCount > 0 ? rainTotal : null;
  half.precipitationSnow = snowCount > 0 ? snowTotal : null;
  half.windSpeed = maxWind;
  half.windDegree = windDegree;
  // `maxWind` null means the half-day has no wind at all, and the Kotlin returns no Wind object —
  // so there is nothing to hang a gust on either.
  half.windGusts = maxWind === null ? null : maxGusts;
  return half;
}

/** How many of the half-day's hours carry a given kind. */
function countKind(hours: Hourly[], kind: WeatherKind): number {
  let count: number = 0;
  for (let i = 0; i < hours.length; i++) {
    if (hours[i].weatherKind === kind) {
      count++;
    }
  }
  return count;
}

/**
 * getHalfDayWeatherCodeFromHourlyList (CommonConverter.kt:794-902).
 *
 * The port used to take the SEVEREST kind found in any single hour, so one rainy hour turned the
 * whole half-day rainy — the reason the daily row showed rain icons where the Android device
 * showed sun-with-cloud. Android is far more conservative: precipitation has to clear a real
 * threshold, and even then the choice is a COUNT (more than one hour), not a single occurrence.
 *
 * Order, exactly as upstream:
 *   1. only consider precipitation at all if total >= 1 mm AND max probability > 30 %
 *      (Open-Meteo gives no per-type probabilities, so the isRain/isSnow/isIce/isThunder branch
 *      at kt:813-836 cannot fire and it falls through to the weather-code counts at kt:838-867)
 *   2. thunderstorm if more than one hour has it
 *   3. otherwise the largest of the rain / sleet / snow / hail counts, each needing > 1
 *   4. no precipitation: visibility < 1 km is fog, < 5 km is haze
 *   5. max wind > 10 m/s is windy
 *   6. otherwise by average cloud cover: > 87.5 % cloudy, > 37.5 % partly cloudy, else clear
 *   7. no data at all: the median hour's own code
 */
function halfDayWeatherKind(
  hours: Hourly[],
  totalPrecipitation: number,
  maxProbability: number | null,
  maxWind: number | null,
  averageCloudCover: number | null,
  averageVisibility: number | null
): WeatherKind {
  // kt:802-806
  const MIN_PRECIP_MM: number = 1.0;
  const MIN_PRECIP_PROBABILITY: number = 30;
  const MAX_VISIBILITY_HAZE_M: number = 5000;
  const MAX_VISIBILITY_FOG_M: number = 1000;
  const MAX_WIND_WINDY_MS: number = 10;
  // UnitExtensions.kt:408-410
  const CLOUD_COVER_FEW: number = 37.5;
  const CLOUD_COVER_BKN: number = 87.5;

  // kt:810-812 — an absent probability is treated as 100 %.
  const probabilityOrFull: number = maxProbability === null ? 100 : maxProbability;
  if (totalPrecipitation >= MIN_PRECIP_MM && probabilityOrFull > MIN_PRECIP_PROBABILITY) {
    // kt:839-841
    if (countKind(hours, WeatherKind.THUNDERSTORM) > 1) {
      return WeatherKind.THUNDERSTORM;
    }
    const rain: number = countKind(hours, WeatherKind.RAINY);
    const sleet: number = countKind(hours, WeatherKind.SLEET);
    const snow: number = countKind(hours, WeatherKind.SNOW);
    const hail: number = countKind(hours, WeatherKind.HAIL);
    if (Math.max(Math.max(rain, sleet), Math.max(snow, hail)) > 0) {
      // kt:850-863
      if (countKind(hours, WeatherKind.THUNDER) > 1) {
        return WeatherKind.THUNDERSTORM;
      }
      if (hail > 1) {
        return WeatherKind.HAIL;
      }
      if ((rain > 1 && snow > 1) || sleet > 1) {
        return WeatherKind.SLEET;
      }
      if (snow > 1) {
        return WeatherKind.SNOW;
      }
      return WeatherKind.RAINY;
    }
    // kt:864-867 — precipitation is expected but no hour says what kind.
    return WeatherKind.RAINY;
  }

  // kt:870-874 — visibility is in metres.
  if (averageVisibility !== null && averageVisibility < MAX_VISIBILITY_HAZE_M) {
    return averageVisibility < MAX_VISIBILITY_FOG_M ? WeatherKind.FOG : WeatherKind.HAZE;
  }
  // kt:876-879
  if (maxWind !== null && maxWind > MAX_WIND_WINDY_MS) {
    return WeatherKind.WIND;
  }
  // kt:881-886
  if (averageCloudCover !== null) {
    if (averageCloudCover > CLOUD_COVER_BKN) {
      return WeatherKind.CLOUDY;
    }
    if (averageCloudCover > CLOUD_COVER_FEW) {
      return WeatherKind.CLOUD;
    }
    return WeatherKind.CLEAR;
  }
  // kt:888-901 — the median hour that has a code, else partly cloudy.
  const coded: Hourly[] = hours.filter((hour: Hourly) => hour.weatherKind !== WeatherKind.NULL);
  if (coded.length === 0) {
    return WeatherKind.CLOUD;
  }
  const middle: number = coded.length % 2 === 0
    ? coded.length / 2
    : (coded.length - 1) / 2;
  return coded[middle].weatherKind;
}

/** The strings.xml label for a derived kind, so the half-day text matches its icon. */
function weatherTextForKind(kind: WeatherKind): string | null {
  switch (kind) {
    case WeatherKind.CLEAR: return 'Clear sky';
    case WeatherKind.CLOUD: return 'Partly cloudy';
    case WeatherKind.CLOUDY: return 'Cloudy';
    case WeatherKind.FOG: return 'Fog';
    case WeatherKind.HAZE: return 'Haze';
    case WeatherKind.RAINY: return 'Rain';
    case WeatherKind.SLEET: return 'Sleet';
    case WeatherKind.SNOW: return 'Snow';
    case WeatherKind.HAIL: return 'Hail';
    case WeatherKind.THUNDER: return 'Thunder';
    case WeatherKind.THUNDERSTORM: return 'Thunderstorm';
    case WeatherKind.WIND: return 'Windy';
    default: return null;
  }
}

/**
 * OpenMeteoService.getDailyList — kt:406-453 — plus the half-day derivation described above.
 * The Kotlin drops the final entry (`time.size - 1`, kt:412-413) because the last day is
 * incomplete; that is reproduced here.
 */
/** One day's hours, already split into the two half-days. */
class HalfDayBuckets {
  readonly dayHours: Hourly[] = [];
  readonly dayPrecipitation: number[] = [];
  readonly nightHours: Hourly[] = [];
  readonly nightPrecipitation: number[] = [];
}

/** Milliseconds in six hours — the half-day shift from getHourlyListByHalfDay. */
const SIX_HOURS_MS: number = 6 * 60 * 60 * 1000;

/**
 * Buckets the whole hourly series by half-day in a single pass.
 *
 * getHourlyListByHalfDay (CommonConverter.kt:634-661): every hour is shifted back by six hours
 * before being assigned to a day, so 00:00–05:59 lands on the PREVIOUS day — a day's "night" is
 * 18:00 through 05:59 the next morning, not the same calendar day's small hours. The shifted
 * hour < 12 means real 06:00–17:59, the day half; everything else is that day's night.
 *
 * The port used to bucket by unshifted calendar day, which handed each night the previous
 * morning's 00:00–05:59 instead of the coming one — the second half of the wrong night
 * temperature (the first half being max-instead-of-min, fixed in buildHalfDay).
 *
 * Single pass, one Date per hour: the nested-loop version cost ~7000 Date allocations a refresh.
 */
function bucketHoursByDay(
  hourly: Hourly[],
  hourlyPrecipitation: number[],
  utcOffsetSeconds: number
): Map<number, HalfDayBuckets> {
  const buckets: Map<number, HalfDayBuckets> = new Map();
  for (let h = 0; h < hourly.length; h++) {
    const shifted: Date = new Date(hourly[h].date.getTime() - SIX_HOURS_MS);
    const key: number = startOfDay(shifted, utcOffsetSeconds);
    let bucket: HalfDayBuckets | undefined = buckets.get(key);
    if (bucket === undefined) {
      bucket = new HalfDayBuckets();
      buckets.set(key, bucket);
    }
    if (localHours(shifted, utcOffsetSeconds) < 12) {
      bucket.dayHours.push(hourly[h]);
      bucket.dayPrecipitation.push(hourlyPrecipitation[h]);
    } else {
      bucket.nightHours.push(hourly[h]);
      bucket.nightPrecipitation.push(hourlyPrecipitation[h]);
    }
  }
  return buckets;
}

export function buildDailyList(
  source: OpenMeteoDaily,
  hourly: Hourly[],
  hourlyPrecipitation: number[],
  utcOffsetSeconds: number
): Daily[] {
  const buckets: Map<number, HalfDayBuckets> = bucketHoursByDay(hourly, hourlyPrecipitation, utcOffsetSeconds);
  const list: Daily[] = [];
  for (let i = 0; i < source.time.length - 1; i++) {
    const daily = new Daily();
    // kt:414-419 truncates to midnight in the LOCATION's zone, not the device's.
    const raw = new Date(source.time[i] * 1000);
    daily.date = new Date(startOfDay(raw, utcOffsetSeconds));
    daily.uvIndex = at(source.uv_index_max, i);
    const sunshineSeconds: number | null = at(source.sunshine_duration, i);
    daily.sunshineHours = sunshineSeconds === null ? null : sunshineSeconds / 3600;

    const bucket: HalfDayBuckets | undefined = buckets.get(daily.date.getTime());
    if (bucket !== undefined) {
      daily.day = buildHalfDay(bucket.dayHours, bucket.dayPrecipitation, true);
      daily.night = buildHalfDay(bucket.nightHours, bucket.nightPrecipitation, false);
    }
    applyDegreeDay(daily);
    list.push(daily);
  }
  return list;
}

/** HEATING_DEGREE_DAY_BASE_TEMP — 18.0 C in deci-celsius (CommonConverter.kt:473). */
const HEATING_DEGREE_DAY_BASE_TEMP: number = 180.0;
/** COOLING_DEGREE_DAY_BASE_TEMP — 21.0 C (kt:474). */
const COOLING_DEGREE_DAY_BASE_TEMP: number = 210.0;
/** DEGREE_DAY_TEMP_MARGIN — 3.0 C (kt:475), which widens the comfortable band to 15.0..24.0 C. */
const DEGREE_DAY_TEMP_MARGIN: number = 30.0;

/**
 * `getDegreeDay` (CommonConverter.kt:477-495), computed here because Open-Meteo omits it and the
 * converter fills it in whenever the source does (kt:405-413).
 *
 * The caller passes `day.temperature` as `minTemp` and `night.temperature` as `maxTemp`, which
 * reads like an upstream naming slip — but the arithmetic is a plain mean of the two half-day
 * temperatures, so the result is identical and this mirrors it rather than "fixing" it.
 */
function applyDegreeDay(daily: Daily): void {
  const day: number | null | undefined = daily.day?.temperature?.temperature;
  const night: number | null | undefined = daily.night?.temperature?.temperature;
  if (day === null || day === undefined || night === null || night === undefined) {
    return; // kt:483 — a missing half-day leaves degreeDay null, so no row.
  }
  // Android holds temperatures as a rounded deci-celsius Long, so the mean is taken there too.
  const meanTemp: number = (Math.round(day * 10) + Math.round(night * 10)) / 2.0;
  if (meanTemp >= HEATING_DEGREE_DAY_BASE_TEMP - DEGREE_DAY_TEMP_MARGIN
    && meanTemp <= COOLING_DEGREE_DAY_BASE_TEMP + DEGREE_DAY_TEMP_MARGIN) {
    daily.heatingDegreeDay = 0;
    daily.coolingDegreeDay = 0;
    return;
  }
  if (meanTemp < HEATING_DEGREE_DAY_BASE_TEMP) {
    daily.heatingDegreeDay = Math.round(HEATING_DEGREE_DAY_BASE_TEMP - meanTemp);
    daily.coolingDegreeDay = 0;
  } else {
    daily.heatingDegreeDay = 0;
    daily.coolingDegreeDay = Math.round(meanTemp - COOLING_DEGREE_DAY_BASE_TEMP);
  }
}

/**
 * The precipitation nowcast, trimmed to the coming hour.
 *
 * Open-Meteo returns 15-minute accumulations for the whole forecast range; the card only shows
 * the hour ahead, so this keeps the buckets covering [now, now + 1h). Intensity is the
 * accumulation scaled to mm/h (× 4 for a quarter-hour bucket).
 */
export function buildMinutelyList(source: OpenMeteoMinutely): Minutely[] {
  const list: Minutely[] = [];
  const now: number = new Date().getTime();
  const horizon: number = now + 60 * 60 * 1000;
  const bucketMs: number = 15 * 60 * 1000;

  for (let i = 0; i < source.time.length; i++) {
    const start: number = source.time[i] * 1000;
    const end: number = start + bucketMs;
    // Keep the bucket the current instant falls in, plus everything up to the horizon.
    if (end <= now || start >= horizon) {
      continue;
    }
    const minutely = new Minutely();
    minutely.date = new Date(start);
    minutely.endingDate = new Date(end);
    const accumulation: number | null = at(source.precipitation, i);
    minutely.precipitationIntensity = accumulation === null ? 0 : accumulation * 4;
    list.push(minutely);
  }
  return list;
}

/** The hourly precipitation series, aligned with buildHourlyList's output. */
export function hourlyPrecipitation(source: OpenMeteoHourly): number[] {
  const totals: number[] = [];
  for (let i = 0; i < source.time.length; i++) {
    const total: number | null = at(source.precipitation, i);
    totals.push(total === null ? 0 : total);
  }
  return totals;
}
