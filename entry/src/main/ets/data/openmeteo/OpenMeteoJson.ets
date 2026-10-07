/*
 * Wire shapes for the Open-Meteo responses.
 *
 * Field names are the JSON keys the Kotlin @SerialName annotations bind to:
 *   sources/openmeteo/json/OpenMeteoWeatherResult.kt
 *   sources/openmeteo/json/OpenMeteoWeatherCurrent.kt
 *   sources/openmeteo/json/OpenMeteoWeatherHourly.kt
 *   sources/openmeteo/json/OpenMeteoWeatherDaily.kt
 *   sources/openmeteo/json/OpenMeteoAirQualityResult.kt
 *   sources/openmeteo/json/OpenMeteoAirQualityHourly.kt
 *
 * These are interfaces, not classes: JSON.parse hands back plain objects, and ArkTS will let an
 * interface describe them without needing a constructor to have run. Every array member is
 * nullable because Open-Meteo emits `null` for gaps in a series.
 *
 * `timeformat=unixtime` means every `time` is epoch *seconds*.
 */

export interface OpenMeteoCurrent {
  time: number;
  temperature_2m?: number | null;
  apparent_temperature?: number | null;
  weather_code?: number | null;
  wind_speed_10m?: number | null;
  wind_direction_10m?: number | null;
  wind_gusts_10m?: number | null;
  uv_index?: number | null;
  relative_humidity_2m?: number | null;
  dew_point_2m?: number | null;
  pressure_msl?: number | null;
  cloud_cover?: number | null;
  visibility?: number | null;
}

export interface OpenMeteoHourly {
  time: number[];
  temperature_2m?: (number | null)[];
  apparent_temperature?: (number | null)[];
  precipitation_probability?: (number | null)[];
  precipitation?: (number | null)[];
  rain?: (number | null)[];
  showers?: (number | null)[];
  snowfall?: (number | null)[];
  weather_code?: (number | null)[];
  wind_speed_10m?: (number | null)[];
  wind_direction_10m?: (number | null)[];
  wind_gusts_10m?: (number | null)[];
  uv_index?: (number | null)[];
  /** The API returns 0/1, not a boolean — noted in the Kotlin model too. */
  is_day?: (number | null)[];
  relative_humidity_2m?: (number | null)[];
  dew_point_2m?: (number | null)[];
  pressure_msl?: (number | null)[];
  cloud_cover?: (number | null)[];
  visibility?: (number | null)[];
}

export interface OpenMeteoDaily {
  time: number[];
  temperature_2m_max?: (number | null)[];
  temperature_2m_min?: (number | null)[];
  apparent_temperature_max?: (number | null)[];
  apparent_temperature_min?: (number | null)[];
  sunshine_duration?: (number | null)[];
  uv_index_max?: (number | null)[];
  relative_humidity_2m_mean?: (number | null)[];
  dew_point_2m_mean?: (number | null)[];
  pressure_msl_mean?: (number | null)[];
  cloud_cover_mean?: (number | null)[];
  visibility_mean?: (number | null)[];
}

/** minutely_15 — 15-minute buckets, `precipitation` in mm accumulated over each bucket. */
export interface OpenMeteoMinutely {
  time: number[];
  precipitation?: (number | null)[];
}

export interface OpenMeteoWeatherResult {
  current?: OpenMeteoCurrent | null;
  hourly?: OpenMeteoHourly | null;
  daily?: OpenMeteoDaily | null;
  minutely_15?: OpenMeteoMinutely | null;
  /**
   * Seconds to add to UTC for the resolved grid cell's wall clock.
   *
   * With `timeformat=unixtime` every `time` is a UTC epoch, and Open-Meteo returns this alongside
   * so the caller can render in the LOCATION's zone — which is what Android does through
   * `location.timeZone`. Without it a Tokyo forecast printed Helsinki's hours on these devices.
   */
  utc_offset_seconds?: number | null;
  timezone?: string | null;
  /** Set when Open-Meteo rejects the request; `reason` carries the message. */
  error?: boolean | null;
  reason?: string | null;
}

export interface OpenMeteoAirQualityHourly {
  time: number[];
  pm10?: (number | null)[];
  pm2_5?: (number | null)[];
  carbon_monoxide?: (number | null)[];
  nitrogen_dioxide?: (number | null)[];
  sulphur_dioxide?: (number | null)[];
  ozone?: (number | null)[];
  alder_pollen?: (number | null)[];
  birch_pollen?: (number | null)[];
  grass_pollen?: (number | null)[];
  mugwort_pollen?: (number | null)[];
  olive_pollen?: (number | null)[];
  ragweed_pollen?: (number | null)[];
}

export interface OpenMeteoAirQualityResult {
  hourly?: OpenMeteoAirQualityHourly | null;
  error?: boolean | null;
  reason?: string | null;
}

/** json/OpenMeteoLocationResult.kt — one geocoding hit. */
export interface OpenMeteoLocationResult {
  id: number;
  name: string;
  latitude: number;
  longitude: number;
  timezone?: string | null;
  country_code?: string | null;
  country?: string | null;
  admin1?: string | null;
  admin2?: string | null;
  admin3?: string | null;
  admin4?: string | null;
}

/**
 * json/OpenMeteoLocationResults.kt.
 *
 * `results` really is absent rather than empty when nothing matches, which is why
 * `generationtime_ms` has to be consulted to tell "no hits" from "the request failed" —
 * see OpenMeteoService.kt:643-648.
 */
export interface OpenMeteoLocationResults {
  results?: OpenMeteoLocationResult[] | null;
  generationtime_ms?: number | null;
}
