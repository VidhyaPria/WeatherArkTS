/*
 * Detail screens a trend item or a half-size block can navigate to.
 *
 * Source: common/options/appearance/DetailScreen.kt:28-92, referenced from every trend adapter's
 * onItemClicked call, e.g. DailyTemperatureAdapter.kt:172-174.
 *
 * Display names resolve through res/values/strings.xml, which alias the tag_* names onto the real
 * labels. NOTE the two that do NOT match the trend tab's label: TAG_HUMIDITY is `humidity`
 * ("Humidity", :334) even though the hourly tab reads "Humidity / Dew point", and TAG_SUN_MOON is
 * `ephemeris` ("Sun & moon", :17).
 */

import { LocationModel } from './Weather';

export enum DetailScreen {
  TAG_CONDITIONS = 'conditions',
  TAG_FEELS_LIKE = 'feels_like',
  TAG_WIND = 'wind',
  TAG_AIR_QUALITY = 'air_quality',
  TAG_POLLEN = 'pollen',
  TAG_UV_INDEX = 'uv_index',
  TAG_PRECIPITATION = 'precipitation',
  TAG_HUMIDITY = 'humidity',
  TAG_PRESSURE = 'pressure',
  TAG_CLOUD_COVER = 'cloud_cover',
  TAG_VISIBILITY = 'visibility',
  TAG_SUN_MOON = 'sun_moon'
}

/**
 * Declaration order, which is what `entries` iterates and therefore the order the FAB menu lists
 * (DetailScreen.kt:34-45). Kept as data because ArkTS has no equivalent of Kotlin's `entries`.
 */
export const DETAIL_SCREEN_ENTRIES: DetailScreen[] = [
  DetailScreen.TAG_CONDITIONS,
  DetailScreen.TAG_FEELS_LIKE,
  DetailScreen.TAG_WIND,
  DetailScreen.TAG_AIR_QUALITY,
  DetailScreen.TAG_POLLEN,
  DetailScreen.TAG_UV_INDEX,
  DetailScreen.TAG_PRECIPITATION,
  DetailScreen.TAG_HUMIDITY,
  DetailScreen.TAG_PRESSURE,
  DetailScreen.TAG_CLOUD_COVER,
  DetailScreen.TAG_VISIBILITY,
  DetailScreen.TAG_SUN_MOON
];

/** English label for a detail screen — the enum's `nameId` (strings.xml lines noted per entry). */
export function detailScreenName(screen: DetailScreen): string {
  switch (screen) {
    case DetailScreen.TAG_CONDITIONS:
      return 'Conditions'; // strings.xml:49
    case DetailScreen.TAG_FEELS_LIKE:
      return 'Conditions'; // kt:35 — TAG_FEELS_LIKE shares R.string.conditions
    case DetailScreen.TAG_WIND:
      return 'Wind'; // strings.xml:102
    case DetailScreen.TAG_AIR_QUALITY:
      return 'Air quality'; // strings.xml:12
    case DetailScreen.TAG_POLLEN:
      return 'Pollen'; // strings.xml:16
    case DetailScreen.TAG_UV_INDEX:
      return 'UV index'; // strings.xml:142
    case DetailScreen.TAG_PRECIPITATION:
      return 'Precipitation'; // strings.xml:76
    case DetailScreen.TAG_HUMIDITY:
      return 'Humidity'; // strings.xml:334
    case DetailScreen.TAG_PRESSURE:
      return 'Pressure'; // strings.xml:350
    case DetailScreen.TAG_CLOUD_COVER:
      return 'Cloud cover'; // strings.xml:376
    case DetailScreen.TAG_VISIBILITY:
      return 'Visibility'; // strings.xml:361
    case DetailScreen.TAG_SUN_MOON:
      return 'Sun & moon'; // strings.xml:17 `ephemeris`
    default:
      return '';
  }
}

/**
 * The enum's `iconId` (kt:34-45).
 *
 * Two of them are Android vector drawables this port does not carry — `weather_haze_mini_xml` for
 * air quality and `weather_clear_night_mini_xml` for sun & moon. Both are the *mini* variants of
 * the animated weather icons, and the port already has a single-glyph stand-in for each
 * (`ic_air_quality`, `ic_weather_night`), so those are used rather than a new asset. Named here so
 * the substitution is visible instead of silent; both ports use the same two files.
 */
export function detailScreenIconName(screen: DetailScreen): string {
  switch (screen) {
    case DetailScreen.TAG_CONDITIONS:
    case DetailScreen.TAG_FEELS_LIKE:
      return 'ic_device_thermostat';
    case DetailScreen.TAG_WIND:
      return 'ic_wind';
    case DetailScreen.TAG_AIR_QUALITY:
      return 'ic_air_quality';
    case DetailScreen.TAG_POLLEN:
      return 'ic_allergy';
    case DetailScreen.TAG_UV_INDEX:
      return 'ic_uv';
    case DetailScreen.TAG_PRECIPITATION:
      return 'ic_precipitation';
    case DetailScreen.TAG_HUMIDITY:
      return 'ic_humidity_percentage';
    case DetailScreen.TAG_PRESSURE:
      return 'ic_gauge';
    case DetailScreen.TAG_CLOUD_COVER:
      return 'ic_cloud';
    case DetailScreen.TAG_VISIBILITY:
      return 'ic_eye';
    case DetailScreen.TAG_SUN_MOON:
    default:
      return 'ic_weather_night';
  }
}

/** The same icon as an ArkUI resource. `$r` needs a literal, so the names are spelled out again. */
export function detailScreenIcon(screen: DetailScreen): Resource {
  switch (detailScreenIconName(screen)) {
    case 'ic_device_thermostat':
      return $r('app.media.ic_device_thermostat');
    case 'ic_wind':
      return $r('app.media.ic_wind');
    case 'ic_air_quality':
      return $r('app.media.ic_air_quality');
    case 'ic_allergy':
      return $r('app.media.ic_allergy');
    case 'ic_uv':
      return $r('app.media.ic_uv');
    case 'ic_precipitation':
      return $r('app.media.ic_precipitation');
    case 'ic_humidity_percentage':
      return $r('app.media.ic_humidity_percentage');
    case 'ic_gauge':
      return $r('app.media.ic_gauge');
    case 'ic_cloud':
      return $r('app.media.ic_cloud');
    case 'ic_eye':
      return $r('app.media.ic_eye');
    default:
      return $r('app.media.ic_weather_night');
  }
}

/**
 * DetailScreen.toDetailScreenList (kt:52-92) — which detail screens this location has data for.
 *
 * TAG_FEELS_LIKE is never in the list: it is a sub-menu of TAG_CONDITIONS (kt:59). Every other
 * entry is gated on the location actually carrying the value, which is why a source that gives no
 * pollen leaves the pollen entry out entirely rather than opening an empty screen.
 */
export function toDetailScreenList(location: LocationModel): DetailScreen[] {
  const weather = location.weather;
  const out: DetailScreen[] = [];
  for (const screen of DETAIL_SCREEN_ENTRIES) {
    let keep: boolean = false;
    switch (screen) {
      case DetailScreen.TAG_CONDITIONS:
      case DetailScreen.TAG_PRECIPITATION:
        keep = true; // kt:58, kt:60 — always displayed
        break;
      case DetailScreen.TAG_FEELS_LIKE:
        keep = false; // kt:59
        break;
      case DetailScreen.TAG_WIND:
        keep = anyDaily(location, 'wind') || anyHourly(location, 'wind');
        break;
      /*
       * kt:65-66 gates these on `location.airQualitySource` / `pollenSource` being set. A location
       * restored from this port's table can have those columns empty while its forecast still
       * carries both — the seed rows predate the per-feature source columns — and the Kotlin rule
       * alone then hides two entries whose TILES are on the main screen, since MainAdapter gates a
       * tile on the VALUE. So the data counts as well: the entry appears when either the source is
       * configured or the value is actually there, which is the union of the two rules Android
       * applies in the two places.
       */
      case DetailScreen.TAG_AIR_QUALITY:
        keep = location.airQualitySource.length > 0 ||
          (weather !== null && weather.current !== null && weather.current.airQualityIndex !== null);
        break;
      case DetailScreen.TAG_POLLEN:
        keep = location.pollenSource.length > 0 ||
          (weather !== null && weather.current !== null && weather.current.pollen.length > 0);
        break;
      case DetailScreen.TAG_UV_INDEX:
        keep = anyDaily(location, 'uv') || anyHourly(location, 'uv');
        break;
      case DetailScreen.TAG_HUMIDITY:
        keep = anyHourly(location, 'humidity');
        break;
      case DetailScreen.TAG_PRESSURE:
        keep = anyHourly(location, 'pressure');
        break;
      case DetailScreen.TAG_CLOUD_COVER:
        keep = anyHourly(location, 'cloud_cover');
        break;
      case DetailScreen.TAG_VISIBILITY:
        keep = anyHourly(location, 'visibility');
        break;
      case DetailScreen.TAG_SUN_MOON:
        keep = true; // kt:89 — always computed
        break;
      default:
        keep = false;
        break;
    }
    if (keep && weather !== null) {
      out.push(screen);
    }
  }
  return out;
}

/**
 * The daily half of each gate.
 *
 * This port's `Daily` carries fewer fields than the Kotlin's — there is no DailyRelativeHumidity,
 * DailyPressure, DailyCloudCover or DailyVisibility, because Open-Meteo publishes those only
 * hourly and the port derives the day's figures from the hours. So only wind and UV can be answered
 * from the daily list; the rest fall through to the hourly test, which is the same question asked of
 * the same data.
 */
function anyDaily(location: LocationModel, field: string): boolean {
  const weather = location.weather;
  if (weather === null) {
    return false;
  }
  for (const daily of weather.dailyForecast) {
    if (field === 'wind') {
      const day = daily.day;
      const night = daily.night;
      if ((day !== null && day.windSpeed !== null) || (night !== null && night.windSpeed !== null)) {
        return true;
      }
    } else if (field === 'uv' && daily.uvIndex !== null && daily.uvIndex > 0) {
      return true;
    }
  }
  return false;
}

function anyHourly(location: LocationModel, field: string): boolean {
  const weather = location.weather;
  if (weather === null) {
    return false;
  }
  // DetailScreen.kt:61-88 tests `location.weather?.hourlyForecast`, the whole series — a tag whose
  // only readings are in the past still gets a menu entry, because its past day still has a chart.
  for (const hour of weather.hourlyForecast) {
    switch (field) {
      case 'wind':
        if (hour.windSpeed !== null) {
          return true;
        }
        break;
      case 'uv':
        if (hour.uvIndex !== null && hour.uvIndex > 0) {
          return true;
        }
        break;
      case 'humidity':
        if (hour.relativeHumidity !== null || hour.dewPoint !== null) {
          return true;
        }
        break;
      case 'pressure':
        if (hour.pressure !== null) {
          return true;
        }
        break;
      case 'cloud_cover':
        if (hour.cloudCover !== null) {
          return true;
        }
        break;
      case 'visibility':
        if (hour.visibility !== null) {
          return true;
        }
        break;
      default:
        break;
    }
  }
  return false;
}
