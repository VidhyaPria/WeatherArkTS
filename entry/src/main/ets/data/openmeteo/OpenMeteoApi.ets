/*
 * The two Open-Meteo requests, byte-for-byte the ones the Android app makes.
 *
 * Retrofit interfaces ported:
 *   sources/openmeteo/OpenMeteoForecastApi.kt:28-40
 *   sources/openmeteo/OpenMeteoAirQualityApi.kt
 * Parameter lists and the fixed arguments come from OpenMeteoService.getWeather
 * (OpenMeteoService.kt:180-268) — including forecast_days=16, past_days=1 and
 * windspeed_unit=ms, which is why every speed in the model is already m·s⁻¹.
 *
 * Base URLs: OpenMeteoService.kt:944-946.
 *
 * Retrofit/OkHttp maps to @ohos.net.http and kotlinx-serialization to JSON.parse, per CLAUDE.md.
 */

import { http } from '@kit.NetworkKit';
import {
  OpenMeteoAirQualityResult,
  OpenMeteoLocationResult,
  OpenMeteoLocationResults,
  OpenMeteoWeatherResult
} from './OpenMeteoJson';

/** OpenMeteoService.kt:946 */
const FORECAST_BASE_URL: string = 'https://api.open-meteo.com/';
/** OpenMeteoService.kt:944 */
const AIR_QUALITY_BASE_URL: string = 'https://air-quality-api.open-meteo.com/';
/** OpenMeteoService.kt:945 */
const GEOCODING_BASE_URL: string = 'https://geocoding-api.open-meteo.com/';

/** OpenMeteoService.kt:640 — the geocoding request asks for 20 hits. */
const SEARCH_RESULT_COUNT: number = 20;

/** OpenMeteoWeatherModel.BEST_MATCH.id — the default `models` argument (ForecastApi.kt:32). */
const MODEL_BEST_MATCH: string = 'best_match';

/** OpenMeteoService.kt:180-202 */
const DAILY_FIELDS: string[] = [
  'temperature_2m_max',
  'temperature_2m_min',
  'apparent_temperature_max',
  'apparent_temperature_min',
  'sunshine_duration',
  'uv_index_max',
  'relative_humidity_2m_mean',
  'relative_humidity_2m_max',
  'relative_humidity_2m_min',
  'dew_point_2m_mean',
  'dew_point_2m_max',
  'dew_point_2m_min',
  'pressure_msl_mean',
  'pressure_msl_max',
  'pressure_msl_min',
  'cloud_cover_mean',
  'cloud_cover_max',
  'cloud_cover_min',
  'visibility_mean',
  'visibility_max',
  'visibility_min'
];

/** OpenMeteoService.kt:203-222 */
const HOURLY_FIELDS: string[] = [
  'temperature_2m',
  'apparent_temperature',
  'precipitation_probability',
  'precipitation',
  'rain',
  'showers',
  'snowfall',
  'weather_code',
  'wind_speed_10m',
  'wind_direction_10m',
  'wind_gusts_10m',
  'uv_index',
  'is_day',
  'relative_humidity_2m',
  'dew_point_2m',
  'pressure_msl',
  'cloud_cover',
  'visibility'
];

/** OpenMeteoService.kt:223-236 */
const CURRENT_FIELDS: string[] = [
  'temperature_2m',
  'apparent_temperature',
  'weather_code',
  'wind_speed_10m',
  'wind_direction_10m',
  'wind_gusts_10m',
  'uv_index',
  'relative_humidity_2m',
  'dew_point_2m',
  'pressure_msl',
  'cloud_cover',
  'visibility'
];

/** OpenMeteoService.kt:237-240 — precipitation_probability is commented out upstream too. */
const MINUTELY_FIELDS: string[] = ['precipitation'];

/** OpenMeteoService.kt:298-304 */
const AIR_QUALITY_FIELDS: string[] = [
  'pm10',
  'pm2_5',
  'carbon_monoxide',
  'nitrogen_dioxide',
  'sulphur_dioxide',
  'ozone'
];

/** OpenMeteoService.kt:310-316 */
const POLLEN_FIELDS: string[] = [
  'alder_pollen',
  'birch_pollen',
  'grass_pollen',
  'mugwort_pollen',
  'olive_pollen',
  'ragweed_pollen'
];

/** OpenMeteoService.kt:266 */
const FORECAST_DAYS: number = 16;
/**
 * OpenMeteoService.kt:325 — the air-quality endpoint asks for **7**, not 16.
 *
 * This is not a stylistic difference: air-quality-api.open-meteo.com caps forecast_days at 7 and
 * answers anything larger with HTTP 400 `{"error":true,"reason":"Forecast days is invalid.
 * Allowed range 0 to 7."}`. The port sent 16, so every air-quality request failed, fetchWeather
 * swallowed it as a "failed feature", and the air quality + pollen tiles silently dropped out of
 * every build — the discrepancy recorded against the Android side-by-side.
 */
const AIR_QUALITY_FORECAST_DAYS: number = 7;
/** OpenMeteoService.kt:267 — yesterday is fetched so today's night half-day is complete. */
const PAST_DAYS: number = 1;

const TIMEOUT_MS: number = 20000;

/** Thrown for a transport failure or an `error: true` body, so the caller can surface it. */
export class OpenMeteoError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OpenMeteoError';
  }
}

/**
 * common/exceptions/LocationSearchException.kt — thrown when the geocoding endpoint answers with
 * neither results nor a generation time, which is how it reports a failure.
 */
export class LocationSearchError extends Error {
  constructor() {
    super('Location search failed');
    this.name = 'LocationSearchError';
  }
}

async function getJson(url: string): Promise<string> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'application/json' } as Record<string, string>,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200) {
      throw new OpenMeteoError('HTTP ' + response.responseCode.toString() + ' from ' + url);
    }
    return response.result as string;
  } finally {
    // The handle owns a native socket; ArkTS will not reclaim it for us.
    request.destroy();
  }
}

/**
 * OpenMeteoForecastApi.kt:28-40. `timezone=auto` and `timeformat=unixtime` are baked into the
 * @GET path upstream, so they are fixed here too.
 */
export async function fetchForecast(
  latitude: number,
  longitude: number,
  /**
   * `getWeatherModels(location).joinToString(",")` (OpenMeteoService.kt:245) — the location's own
   * model selection. Defaulted rather than required so the one caller that has no location in hand
   * still gets Android's behaviour for a location that has never been configured.
   */
  models: string = MODEL_BEST_MATCH
): Promise<OpenMeteoWeatherResult> {
  const url: string = FORECAST_BASE_URL + 'v1/forecast' +
    '?timezone=auto&timeformat=unixtime' +
    '&latitude=' + latitude.toString() +
    '&longitude=' + longitude.toString() +
    '&models=' + (models.length > 0 ? models : MODEL_BEST_MATCH) +
    '&daily=' + DAILY_FIELDS.join(',') +
    '&hourly=' + HOURLY_FIELDS.join(',') +
    '&minutely_15=' + MINUTELY_FIELDS.join(',') +
    '&current=' + CURRENT_FIELDS.join(',') +
    '&forecast_days=' + FORECAST_DAYS.toString() +
    '&past_days=' + PAST_DAYS.toString() +
    '&windspeed_unit=ms';

  const body: string = await getJson(url);
  const result: OpenMeteoWeatherResult = JSON.parse(body) as OpenMeteoWeatherResult;
  if (result.error === true) {
    throw new OpenMeteoError(result.reason !== null && result.reason !== undefined ? result.reason : 'Open-Meteo error');
  }
  return result;
}

/** OpenMeteoAirQualityApi.kt — air quality and pollen share one hourly request. */
export async function fetchAirQuality(
  latitude: number,
  longitude: number
): Promise<OpenMeteoAirQualityResult> {
  const fields: string[] = AIR_QUALITY_FIELDS.concat(POLLEN_FIELDS);
  const url: string = AIR_QUALITY_BASE_URL + 'v1/air-quality' +
    '?timezone=auto&timeformat=unixtime' +
    '&latitude=' + latitude.toString() +
    '&longitude=' + longitude.toString() +
    '&hourly=' + fields.join(',') +
    '&forecast_days=' + AIR_QUALITY_FORECAST_DAYS.toString() +
    '&past_days=' + PAST_DAYS.toString();

  const body: string = await getJson(url);
  const result: OpenMeteoAirQualityResult = JSON.parse(body) as OpenMeteoAirQualityResult;
  if (result.error === true) {
    throw new OpenMeteoError(result.reason !== null && result.reason !== undefined ? result.reason : 'Open-Meteo error');
  }
  return result;
}

/**
 * OpenMeteoGeocodingApi.getLocations + OpenMeteoService.requestLocationSearch (kt:634-655).
 *
 * Two rules from the Kotlin that are easy to lose and both matter:
 *
 *  - A missing `results` array does NOT mean "no matches". :643-648 distinguishes the two by
 *    `generationtime_ms`: present and positive means the search genuinely found nothing, absent
 *    means the request failed and a LocationSearchException is thrown. Collapsing both into an
 *    empty list would show "can't find X" for what is really a network error.
 *  - :651 drops every hit whose `country_code` is empty, before conversion. `convertLocation`
 *    (:657-673) then force-unwraps that field, so the filter is what keeps it safe.
 *
 * `format=json` is baked into the @GET path upstream, so it is fixed here too.
 */
export async function fetchLocationSearch(
  query: string,
  language: string
): Promise<OpenMeteoLocationResult[]> {
  const url: string = GEOCODING_BASE_URL + 'v1/search?format=json' +
    '&name=' + encodeURIComponent(query) +
    '&count=' + SEARCH_RESULT_COUNT.toString() +
    '&language=' + encodeURIComponent(language);

  const body: string = await getJson(url);
  const parsed: OpenMeteoLocationResults = JSON.parse(body) as OpenMeteoLocationResults;

  const results: OpenMeteoLocationResult[] | null | undefined = parsed.results;
  if (results === null || results === undefined) {
    const generated: number | null | undefined = parsed.generationtime_ms;
    if (generated !== null && generated !== undefined && generated > 0) {
      return [];
    }
    throw new LocationSearchError();
  }

  const kept: OpenMeteoLocationResult[] = [];
  for (let i = 0; i < results.length; i++) {
    const code: string | null | undefined = results[i].country_code;
    if (code !== null && code !== undefined && code.length > 0) {
      kept.push(results[i]);
    }
  }
  return kept;
}
