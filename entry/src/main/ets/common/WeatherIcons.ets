/*
 * Static weather icons.
 *
 * The PNGs are copied verbatim from breezy-weather-6.2.1/app/src/main/res/drawable, so the
 * artwork is identical to the Android app. This is the equivalent of
 * ResourceHelper.getWeatherIcon(provider, weatherCode, daytime) with the default provider.
 *
 * Step 3 replaces these with the layered, animated variants (weather_*_1/_2/_3.png driven by
 * res/animator/weather_*.xml).
 */

import { WeatherKind } from '../model/WeatherKind';

export function getWeatherIcon(kind: WeatherKind, daytime: boolean): Resource | null {
  switch (kind) {
    case WeatherKind.CLEAR:
      return daytime ? $r('app.media.weather_clear_day') : $r('app.media.weather_clear_night');
    case WeatherKind.CLOUD:
      return daytime
        ? $r('app.media.weather_partly_cloudy_day')
        : $r('app.media.weather_partly_cloudy_night');
    case WeatherKind.CLOUDY:
      return $r('app.media.weather_cloudy');
    case WeatherKind.RAINY:
      return $r('app.media.weather_rain');
    case WeatherKind.SNOW:
      return $r('app.media.weather_snow');
    case WeatherKind.SLEET:
      return $r('app.media.weather_sleet');
    case WeatherKind.HAIL:
      return $r('app.media.weather_hail');
    case WeatherKind.FOG:
      return $r('app.media.weather_fog');
    case WeatherKind.HAZE:
      return $r('app.media.weather_haze');
    case WeatherKind.THUNDER:
      return $r('app.media.weather_thunder');
    case WeatherKind.THUNDERSTORM:
      return $r('app.media.weather_thunderstorm');
    case WeatherKind.WIND:
      return $r('app.media.weather_wind');
    default:
      return null;
  }
}

/**
 * The minimal (notification / widget) icon — `getWidgetNotificationIcon(provider, code, daytime,
 * minimal = true, darkText)` via `DefaultResourceProvider.getMinimalDarkIcon`/`getMinimalLightIcon`.
 *
 * The name is `<weather icon name>_mini_<dark|light>` (DefaultResourceProvider.kt:194-213), and
 * `darkText = !darkMode` (PreviewIconActivity.kt:81-91): a light theme wants DARK glyphs.
 *
 * Codes with no day/night artwork resolve to one file through
 * `res/xml/icon_provider_drawable_filter.xml`, which is why they ignore `daytime` here too.
 */
export function getMinimalIcon(
  kind: WeatherKind,
  daytime: boolean,
  darkMode: boolean
): Resource | null {
  return darkMode ? minimalLightIcon(kind, daytime) : minimalDarkIcon(kind, daytime);
}

function minimalDarkIcon(kind: WeatherKind, daytime: boolean): Resource | null {
  switch (kind) {
    case WeatherKind.CLEAR:
      return daytime
        ? $r('app.media.weather_clear_day_mini_dark')
        : $r('app.media.weather_clear_night_mini_dark');
    case WeatherKind.CLOUD:
      return daytime
        ? $r('app.media.weather_partly_cloudy_day_mini_dark')
        : $r('app.media.weather_partly_cloudy_night_mini_dark');
    case WeatherKind.CLOUDY:
      return $r('app.media.weather_cloudy_mini_dark');
    case WeatherKind.RAINY:
      return $r('app.media.weather_rain_mini_dark');
    case WeatherKind.SNOW:
      return $r('app.media.weather_snow_mini_dark');
    case WeatherKind.SLEET:
      return $r('app.media.weather_sleet_mini_dark');
    case WeatherKind.HAIL:
      return $r('app.media.weather_hail_mini_dark');
    case WeatherKind.FOG:
      return $r('app.media.weather_fog_mini_dark');
    case WeatherKind.HAZE:
      return $r('app.media.weather_haze_mini_dark');
    case WeatherKind.THUNDER:
      return $r('app.media.weather_thunder_mini_dark');
    case WeatherKind.THUNDERSTORM:
      return $r('app.media.weather_thunderstorm_mini_dark');
    case WeatherKind.WIND:
      return $r('app.media.weather_wind_mini_dark');
    default:
      return null;
  }
}

function minimalLightIcon(kind: WeatherKind, daytime: boolean): Resource | null {
  switch (kind) {
    case WeatherKind.CLEAR:
      return daytime
        ? $r('app.media.weather_clear_day_mini_light')
        : $r('app.media.weather_clear_night_mini_light');
    case WeatherKind.CLOUD:
      return daytime
        ? $r('app.media.weather_partly_cloudy_day_mini_light')
        : $r('app.media.weather_partly_cloudy_night_mini_light');
    case WeatherKind.CLOUDY:
      return $r('app.media.weather_cloudy_mini_light');
    case WeatherKind.RAINY:
      return $r('app.media.weather_rain_mini_light');
    case WeatherKind.SNOW:
      return $r('app.media.weather_snow_mini_light');
    case WeatherKind.SLEET:
      return $r('app.media.weather_sleet_mini_light');
    case WeatherKind.HAIL:
      return $r('app.media.weather_hail_mini_light');
    case WeatherKind.FOG:
      return $r('app.media.weather_fog_mini_light');
    case WeatherKind.HAZE:
      return $r('app.media.weather_haze_mini_light');
    case WeatherKind.THUNDER:
      return $r('app.media.weather_thunder_mini_light');
    case WeatherKind.THUNDERSTORM:
      return $r('app.media.weather_thunderstorm_mini_light');
    case WeatherKind.WIND:
      return $r('app.media.weather_wind_mini_light');
    default:
      return null;
  }
}

/**
 * The launcher-shortcut icon — `getShortcutsIcon` (DefaultResourceProvider.kt:223-236).
 *
 * `shortcuts_<name>_<day|night>` collapses to one file for every code but CLEAR and PARTLY_CLOUDY
 * through `res/xml/icon_provider_shortcut_filter.xml`.
 */
export function getShortcutIcon(kind: WeatherKind, daytime: boolean): Resource | null {
  switch (kind) {
    case WeatherKind.CLEAR:
      return daytime
        ? $r('app.media.shortcuts_clear_day')
        : $r('app.media.shortcuts_clear_night');
    case WeatherKind.CLOUD:
      return daytime
        ? $r('app.media.shortcuts_partly_cloudy_day')
        : $r('app.media.shortcuts_partly_cloudy_night');
    case WeatherKind.CLOUDY:
      return $r('app.media.shortcuts_cloudy');
    case WeatherKind.RAINY:
      return $r('app.media.shortcuts_rain');
    case WeatherKind.SNOW:
      return $r('app.media.shortcuts_snow');
    case WeatherKind.SLEET:
      return $r('app.media.shortcuts_sleet');
    case WeatherKind.HAIL:
      return $r('app.media.shortcuts_hail');
    case WeatherKind.FOG:
      return $r('app.media.shortcuts_fog');
    case WeatherKind.HAZE:
      return $r('app.media.shortcuts_haze');
    case WeatherKind.THUNDER:
      return $r('app.media.shortcuts_thunder');
    case WeatherKind.THUNDERSTORM:
      return $r('app.media.shortcuts_thunderstorm');
    case WeatherKind.WIND:
      return $r('app.media.shortcuts_wind');
    default:
      return null;
  }
}

/**
 * Wind.drawableArrow (Wind.kt:87-103) picks one of eight arrow drawables by 45° bucket, falling
 * back to ic_replay when the direction is unknown ("variable").
 *
 * This port ships a single arrow (wind_arrow.svg) plus wind_variable.svg, so the eight drawables
 * become one arrow rotated to the bucket's canonical angle. Bucketing to 45° first — rather than
 * rotating by the raw degree — keeps the same discrete set of headings the Android app shows.
 *
 * Returns null when there is no direction at all, so the caller can leave the icon slot empty.
 */
export function getWindArrowIcon(degree: number | null): Resource | null {
  if (degree === null) {
    return null;
  }
  if (degree < 0 || degree > 360) {
    // Wind.kt:101 — anything outside the compass is "variable".
    return $r('app.media.wind_variable');
  }
  return $r('app.media.wind_arrow');
}

/**
 * The rotation to apply to wind_arrow.svg, in degrees clockwise.
 *
 * wind_arrow.svg is authored pointing north, matching R.drawable.arrow_north at rotation 0.
 */
export function getWindArrowRotation(degree: number | null): number {
  if (degree === null || degree < 0 || degree > 360) {
    return 0;
  }
  if (degree <= 22.5 || degree > 337.5) {
    return 0;
  }
  if (degree <= 67.5) {
    return 45;
  }
  if (degree <= 112.5) {
    return 90;
  }
  if (degree <= 157.5) {
    return 135;
  }
  if (degree <= 202.5) {
    return 180;
  }
  if (degree <= 247.5) {
    return 225;
  }
  if (degree <= 292.5) {
    return 270;
  }
  return 315;
}
