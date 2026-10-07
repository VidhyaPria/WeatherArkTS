/*
 * Minimal typed weather model covering what the main screen needs.
 *
 * Shapes follow the Kotlin domain classes so that step 4 (Open-Meteo) can fill them
 * without changing the views:
 *   domain/src/main/kotlin/breezyweather/domain/weather/model/{Weather,Daily,HalfDay,Hourly,Current}.kt
 *
 * Temperatures are stored in Celsius; unit conversion happens at format time.
 */

import { WeatherKind } from './WeatherKind';
import { AirQualityConcentrations } from './Pollutant';
import { localStartOfHour } from '../common/LocalTime';

/**
 * Weather.nextHourlyForecast â€” everything from the start of the current hour onwards.
 *
 * Lives beside the model rather than in the repository because the CACHE reload has to apply the
 * same rule: what is persisted is the full `hourlyForecast`, and the trimmed view is derived from
 * it every time it is read back.
 */
export function trimHourlyFromNow(hourly: Hourly[], utcOffsetSeconds: number): Hourly[] {
  const currentHourStart: number = localStartOfHour(new Date(), utcOffsetSeconds);
  const out: Hourly[] = [];
  for (let i = 0; i < hourly.length; i++) {
    if (hourly[i].date.getTime() >= currentHourStart) {
      out.push(hourly[i]);
    }
  }
  return out;
}

export class Temperature {
  temperature: number | null = null;
  feelsLikeTemperature: number | null = null;
}

export class PrecipitationProbability {
  /** 0..100 */
  total: number | null = null;
}

/** Daily.day / Daily.night — HalfDay.kt */
export class HalfDay {
  weatherText: string | null = null;
  weatherKind: WeatherKind = WeatherKind.NULL;
  temperature: Temperature | null = null;
  precipitationProbability: PrecipitationProbability | null = null;
  /** mm over the half day — drives the daily Precipitation bars. */
  precipitationTotal: number | null = null;
  /**
   * The rain and snow parts of the half-day total — `Precipitation.rain` / `.snow`, which
   * `getHalfDayPrecipitationFromHourlyList` (CommonConverter.kt:978-1018) SUMS from the hours that
   * carry one, and leaves null when none does.
   *
   * Both in MILLIMETRES, the model unit for every precipitation quantity here. Snow arrives from
   * Open-Meteo in centimetres and is multiplied by 10 on the way in; it is DISPLAYED in the
   * snowfall unit, which is the coarser one of the pair (`getSnowfallUnit`, SettingsManager.kt:241).
   * Ice and thunderstorm are absent because Open-Meteo reports neither, so Android shows no row
   * for them either.
   */
  precipitationRain: number | null = null;
  precipitationSnow: number | null = null;
  /** m/s — drives the daily Wind bars. */
  windSpeed: number | null = null;
  windDegree: number | null = null;
  /**
   * m/s — the half-day's MAXIMUM gust, which `getHalfDayWindFromHourlyList`
   * (CommonConverter.kt) takes independently of the hour that won the speed:
   * `maxWind.copy(gusts = maxWindGusts)`.
   *
   * Wind's header prints it as its third line ("Gusts: 11.6 m/s", DetailsWind.kt:303-317).
   */
  windGusts: number | null = null;
}

export class Daily {
  date: Date = new Date();
  day: HalfDay | null = null;
  night: HalfDay | null = null;
  /**
   * The day's AQI — Daily.airQuality, what DailyAirQualityAdapter plots. Null when the air-quality
   * request failed or the day is outside its 7-day range.
   */
  airQualityIndex: number | null = null;
  /**
   * Daily.airQuality — the MEAN of the day's hourly concentrations, which is what
   * `getDailyAirQualityFromHourlyList` (CommonConverter.kt:520-542) computes, and needs at least
   * 18 of the day's hours to be produced at all.
   */
  airQuality: AirQualityConcentrations | null = null;
  /** Peak UV index for the day — daily UV tab. */
  uvIndex: number | null = null;
  /** Hours of sunshine — daily Sunshine tab. */
  sunshineHours: number | null = null;
  /**
   * Daily.degreeDay, in DECI-CELSIUS — the storage unit Android's `Temperature` uses, kept so the
   * display conversion is the same plain deviation divide (CommonConverter.kt:473-495).
   *
   * Open-Meteo does not supply these; `CommonConverter` computes them from the two half-day
   * temperatures whenever the source omits them (kt:405-413), so Android shows the row and the
   * port has to compute them too. Both are 0 inside the comfortable band, which is `isValid`
   * false and no row at all.
   */
  heatingDegreeDay: number | null = null;
  coolingDegreeDay: number | null = null;
}

export class Hourly {
  date: Date = new Date();
  weatherText: string | null = null;
  weatherKind: WeatherKind = WeatherKind.NULL;
  daylight: boolean = true;
  /** European AQI for this hour — Hourly.airQuality, the hourly Air quality tab. */
  airQualityIndex: number | null = null;
  /** The hour's pollutant concentrations, which the air-quality chart plots per pollutant. */
  airQuality: AirQualityConcentrations | null = null;
  temperature: Temperature | null = null;
  precipitationProbability: PrecipitationProbability | null = null;
  relativeHumidity: number | null = null;
  /**
   * °C. The hourly Humidity tab draws dew point as its polyline and relative humidity as the
   * histogram behind it (HourlyHumidityAdapter.kt:85-101), so both are needed.
   */
  dewPoint: number | null = null;
  /** mm in this hour — the hourly Precipitation tab's histogram (HourlyPrecipitationAdapter.kt:81-89). */
  precipitationTotal: number | null = null;
  /**
   * `Precipitation.rain` — Open-Meteo's `rain` PLUS its `showers`, which is how OpenMeteoService
   * builds it (kt:475). Millimetres.
   */
  precipitationRain: number | null = null;
  /** `Precipitation.snow` — Open-Meteo's `snowfall`, centimetres on the wire, held here in mm. */
  precipitationSnow: number | null = null;
  /** hPa */
  pressure: number | null = null;
  /** 0..100 */
  cloudCover: number | null = null;
  /** metres */
  visibility: number | null = null;
  uvIndex: number | null = null;
  /** m/s */
  windSpeed: number | null = null;
  windDegree: number | null = null;
  /** m/s — `wind_gusts_10m`, already requested. The half-day maximum is Wind's third header line. */
  windGusts: number | null = null;
}

export class Current {
  weatherText: string | null = null;
  weatherKind: WeatherKind = WeatherKind.NULL;
  temperature: Temperature | null = null;
  /* Values behind the half-size detail blocks (MainAdapter.kt:138-170 gates each card on these). */
  /** 0..100 */
  relativeHumidity: number | null = null;
  dewPoint: number | null = null;
  /** hPa */
  pressure: number | null = null;
  /** metres */
  visibility: number | null = null;
  uvIndex: number | null = null;
  /** m/s */
  windSpeed: number | null = null;
  /** m/s — shown as the wind block's secondary line ("Gusts: 8 mph"). */
  windGusts: number | null = null;
  windDegree: number | null = null;
  /** mm over the current half-day */
  precipitationTotal: number | null = null;
  /** European AQI */
  airQualityIndex: number | null = null;
  /** The current hour's concentrations — the fallback header when the day has no average. */
  airQuality: AirQualityConcentrations | null = null;
  /** Allergen rows for the pollen block; empty means no pollen card. */
  pollen: PollenEntry[] = [];
  sun: Astro | null = null;
  moon: Astro | null = null;
  /** Short sentence under the "Daily forecast" title (DailyViewHolder.kt:68-73). */
  dailyForecast: string | null = null;
  /** Short sentence under the "Hourly forecast" title (HourlyViewHolder.kt:66-71). */
  hourlyForecast: string | null = null;
}

/** One allergen row in the pollen block (PollenViewHolder lists them with a coloured dot). */
export class PollenEntry {
  name: string = '';
  /** 0..5, colours come from colors.xml:49-54 pollenLevel_*. */
  level: number = 0;
  levelName: string = '';
  /**
   * Grains per cubic metre — `PollenConcentration.inPerCubicMeter`.
   *
   * The MAIN screen's block lists `pollensWithConcentration` (> 0) and shows the level alone, but
   * the detail screen's `PollenGrid` lists `validPollens` (not null) and its subtitle is
   * "12/m³ – Low" (AllergenComposables.kt:83-85). So the entry has to carry the number, and the
   * "> 0" rule belongs to the consumer, not to the mapper.
   */
  concentration: number = 0;
}

/** Sun/moon times for the astro blocks (container_main_astro.xml). */
export class Astro {
  riseTime: string = '';
  setTime: string = '';
  /** Moon only — e.g. "Last quarter". */
  phase: string = '';
  /**
   * Absolute rise/set instants. SunMoonView draws the elapsed part of the arc from these
   * (AstroViewHolder.ensureTime, kt:178-193), so the display strings alone are not enough.
   * For the moon these are already the "validated" pair: when now is before tonight's
   * moonrise, AstroViewHolder.kt:103-115 falls back to yesterday's moon if it has not set yet.
   */
  riseDate: Date | null = null;
  setDate: Date | null = null;
  /**
   * Moon only — MoonPhase.angle, 0..360 clockwise from new moon. Drives MoonPhaseView
   * (MoonViewHolder.kt:136, MoonPhaseView.setSurfaceAngle).
   */
  phaseAngle: number = 0;

  /**
   * Elapsed fraction of the arc, 0..1, or -1 when the block has no valid pair.
   * Mirrors SunMoonView.ensureProgress (kt:184-189): a non-positive span draws nothing,
   * which is what the Android device shows for a moon whose set time precedes its rise.
   */
  progressAt(now: Date): number {
    if (this.riseDate === null || this.setDate === null) {
      return -1;
    }
    const max: number = this.setDate.getTime() - this.riseDate.getTime();
    if (max <= 0) {
      return -1;
    }
    const elapsed: number = now.getTime() - this.riseDate.getTime();
    return Math.max(0, Math.min(1, elapsed / max));
  }
}

/**
 * A weather alert (Alert.kt).
 *
 * Open-Meteo publishes no alerts, so with the only source this port supports `alertList` is
 * always empty and the alert card never appears — MainAdapter.kt:107-109 gates it the same way.
 * The model and the card are here so a source that does carry alerts drops straight in.
 */
export class Alert {
  alertId: string = '';
  headline: string = '';
  description: string = '';
  /** CAP `<instruction>` — what to do about it. Shown under the description on the alert screen. */
  instruction: string = '';
  /** CAP `<senderName>` — printed as "Source: %s" (strings.xml `alert_source`). */
  source: string = '';
  startDate: Date | null = null;
  endDate: Date | null = null;
  /** Severity colour, already resolved — Alert.color on the Kotlin side. */
  color: string = '#FFE52F35';

  /** AlertViewHolder.kt:77 — an alert counts as live while it has no end, or ends in the future. */
  isActive(now: Date): boolean {
    return this.endDate === null || this.endDate.getTime() > now.getTime();
  }

  /** Weather.currentAlertList — started already and not yet finished. */
  isCurrent(now: Date): boolean {
    if (!this.isActive(now)) {
      return false;
    }
    return this.startDate === null || this.startDate.getTime() <= now.getTime();
  }
}

/**
 * One bucket of the precipitation nowcast (Minutely.kt).
 *
 * Android's source gives 5-minute buckets with a radar `dbz`; Open-Meteo's `minutely_15` gives
 * 15-minute buckets of accumulated millimetres and no radar reflectivity at all. So the buckets
 * here are 15 minutes wide and `precipitationIntensity` is derived (mm per 15 min × 4 = mm/h),
 * and everywhere the Kotlin tests `dbz > 0` this port tests `precipitationIntensity > 0`.
 */
export class Minutely {
  date: Date = new Date();
  endingDate: Date = new Date();
  /** mm/h */
  precipitationIntensity: number = 0;
}

/** Monthly normals — used to draw the trend key lines (DailyTemperatureAdapter.kt:278-311). */
export class Normals {
  daytimeTemperature: number | null = null;
  nighttimeTemperature: number | null = null;
}

export class Weather {
  refreshTime: Date | null = null;
  current: Current | null = null;
  dailyForecast: Daily[] = [];
  /**
   * Weather.hourlyForecast â€” the WHOLE series the source returned, past hours included.
   *
   * Open-Meteo is asked for `past_days=1` (OpenMeteoService.kt:267 and this port's
   * OpenMeteoApi.PAST_DAYS), so this reaches back over yesterday. Keeping it is not optional:
   * `DetailsScreen.kt:372-385` slices THIS list to the day the pager is on, so a port that stored
   * only the trimmed one reported "no hourly data" on every past day of every detail screen.
   */
  hourlyForecast: Hourly[] = [];
  /** Already trimmed to "from now on", like Weather.nextHourlyForecast. */
  nextHourlyForecast: Hourly[] = [];
  /** Precipitation nowcast buckets, already trimmed to the coming hour. */
  minutelyForecast: Minutely[] = [];
  alertList: Alert[] = [];
  normals: Normals | null = null;

  /** AlertViewHolder.kt:77 — the card shows only when at least one alert has not expired. */
  hasActiveAlerts(now: Date): boolean {
    for (let i = 0; i < this.alertList.length; i++) {
      if (this.alertList[i].isActive(now)) {
        return true;
      }
    }
    return false;
  }

  /** Weather.currentAlertList — the alerts in force right now. */
  currentAlerts(now: Date): Alert[] {
    const out: Alert[] = [];
    for (let i = 0; i < this.alertList.length; i++) {
      if (this.alertList[i].isCurrent(now)) {
        out.push(this.alertList[i]);
      }
    }
    return out;
  }

  /** Weather.hasMinutelyPrecipitation — any bucket carrying precipitation. */
  hasMinutelyPrecipitation(): boolean {
    for (let i = 0; i < this.minutelyForecast.length; i++) {
      if (this.minutelyForecast[i].precipitationIntensity > 0) {
        return true;
      }
    }
    return false;
  }
  /** Index of today inside dailyForecast, or null when unknown. */
  todayIndex: number | null = null;
}

/**
 * strings.xml `location_current` — the name a current position carries until it has a real one.
 *
 * getPlace (app/.../domain/location/model/Location.kt:29-43) returns this when a current-position
 * location has no city yet, which is exactly the state one is saved in: ManagementFragment adds
 * `Location(isCurrentPosition = true)` with nothing filled in, and the reverse geocode only lands
 * after the first refresh.
 */
export const CURRENT_LOCATION_NAME: string = 'Current location';

/**
 * `Location.cityAndDistrict` (Location.kt:261-274) — the city, then the district after a comma when
 * there is one and it differs from the city.
 */
export function cityAndDistrict(city: string, district: string): string {
  let out: string = city;
  if (district.length > 0 && district !== city) {
    if (out.length > 0) {
      out += ', ';
    }
    out += district;
  }
  return out;
}

/** getPlace (Location.kt:29-43), for the fields this port carries. */
export function getPlace(location: LocationModel): string {
  // kt:33-35 — the user's own name wins over everything the geocoder produced. Checked before
  // cityAndDistrict and before the current-position fallback, exactly as the Kotlin orders it.
  if (location.customName.length > 0) {
    return location.customName;
  }
  const place: string = cityAndDistrict(location.city, location.district);
  if (place.length > 0) {
    return place;
  }
  if (location.isCurrentPosition) {
    return CURRENT_LOCATION_NAME;
  }
  // The coordinate fallback of kt:42 — reached only by a saved location with no name at all.
  return location.latitude.toString() + ', ' + location.longitude.toString();
}

/**
 * OBSERVED, and only in the four fields a refresh settles.
 *
 * This is what lets a location page update IN PLACE instead of being destroyed and rebuilt. The
 * Swiper's ForEach used to carry a version counter in its key purely to force a rebuild when
 * `refresh()` replaced `weather` — a plain object mutation the framework cannot see. Rebuilding one
 * page costs a 4.6 s frame on this device (traced: 60 custom-node destroys, 39 builds, 149 canvas
 * passes, 38 image decodes), and because the frame that rebuilds the page is also the frame that
 * paints the new toolbar title, selecting a location left the previous one on screen for seconds.
 *
 * ArkUI V2 re-executes exactly the UI update functions that READ a @Trace field, so marking these
 * four means `locationPage`'s own fragments — `location.weather !== null`, the daily/hourly guards,
 * `hasAlerts`, `hasNowcast` — refresh themselves, and the ForEach key can go back to being pure
 * identity.
 *
 * Deliberately NOT deep: `Weather` is a plain class, so assigning a new one is observed but its
 * ~400 hourly entries are never proxied. That distinction matters — putting big graphs under
 * observation is what caused the THREAD_BLOCK_6S freeze earlier in this screen's history.
 */
@ObservedV2
export class LocationModel {
  formattedId: string = '';
  @Trace city: string = '';
  /**
   * Location.district — the sub-locality inside `city`, e.g. "Kotkavuori" inside Helsinki.
   *
   * Only the reverse geocoder fills it (`AndroidGeocoderService.kt:43` maps it from
   * `Address.subLocality`), so a searched location has none and a current position usually does.
   * `getPlace` prints "city, district", which is why Android's toolbar reads "Helsinki, Kotkavuori"
   * where this port used to read "Helsinki".
   */
  @Trace district: string = '';
  /**
   * Location.needsGeocodeRefresh — this row's address has to be looked up again.
   *
   * Android carries the same flag (Location.kt:45) and RefreshHelper's STEP 2 clears it once the
   * address is settled. Here it exists because the geocode guard is "city is empty", which cannot
   * tell a row that was never geocoded from one that was geocoded before a FIELD existed: a
   * current position saved before `district` shipped keeps a city, so it would never be asked
   * again and could never gain its district. The stored column defaults to 1, which marks exactly
   * those rows.
   */
  needsGeocodeRefresh: boolean = false;
  /** Coordinates the forecast is fetched for — Location.latitude / .longitude. */
  latitude: number = 0;
  longitude: number = 0;
  isCurrentPosition: boolean = false;
  timeZone: string = '';
  /**
   * The admin area the city sits in — Location.admin1 on Android, which is what FMI's CAP
   * warnings name in their <areaDesc>. Empty for a location no alert source covers.
   */
  @Trace region: string = '';
  /**
   * Location.countryCode — the ISO 3166-1 alpha-2 code, from the geocoding hit's `country_code`.
   *
   * This is what the whole source catalogue keys off: nearly every national source answers
   * `isFeatureSupportedForLocation` with a country comparison (SourceCatalogue.ets). Empty until a
   * location has been geocoded, which for a current position is until its first refresh.
   */
  @Trace countryCode: string = '';
  /**
   * Location.admin2 — the department/county below `region`. Carried for exactly one reason: the
   * four regional Atmo air-quality sources test it (AtmoHdfService.isLocationInRegion and friends).
   */
  admin2: string = '';
  /**
   * Location.customName (Location.kt:47) — the name the user typed over this location's own.
   *
   * Written by the "Location preferences" dialog reached from the main screen's edit icon, and read
   * FIRST by `getPlace` (Location.kt:33-35), ahead of `cityAndDistrict`. Empty means "no override",
   * which is Android's null: the edit field seeds itself with `cityAndDistrict` and clearing it back
   * to the city stores "" rather than the city, so a later geocode can still move the name.
   *
   * @Trace because the toolbar title and every location row read it through `getPlace`.
   */
  @Trace customName: string = '';
  /**
   * The Open-Meteo weather models this location is fetched with — `parameters["openmeteo"]
   * ["weatherModels"]` on Android (OpenMeteoService.kt:764-773), a comma-joined list of model ids.
   *
   * Android keeps a generic per-source `parameters` map because it has forty-odd sources that each
   * define their own keys. This port has ONE source with a per-location preference screen, so the
   * map would be a dictionary with a single well-known key in it; the field is that key, typed.
   * Empty means the default, which is `best_match` alone (kt:772) — not "no models".
   */
  weatherModels: string = '';

  /*
   * The per-feature source selection — Location.forecastSource / currentSource / … on Android,
   * written by the weather-sources dialog (LocationPreferences.kt:848-877).
   *
   * The forecast source always has a value; the other seven are "" when the feature is switched
   * off, which is the `settings_weather_source_none` entry — except `currentSource`, whose ""
   * means "take it from the forecast source" (`forecast`, LocationPreferences.kt:589-595).
   *
   * Only Open-Meteo has a client in this port, so these all hold 'openmeteo' or '' today; they are
   * real fields rather than constants because the dialog can write any id, and because
   * `locationExists` compares the forecast source as part of a location's identity.
   */
  forecastSource: string = 'openmeteo';
  currentSource: string = '';
  airQualitySource: string = '';
  pollenSource: string = '';
  minutelySource: string = '';
  alertSource: string = '';
  normalsSource: string = '';
  reverseGeocodingSource: string = '';
  /**
   * Seconds to add to UTC to get this location's wall-clock time — Open-Meteo's
   * `utc_offset_seconds`, refreshed with the forecast.
   *
   * Android reads every date through `location.timeZone`: the day a forecast entry belongs to,
   * which hours make up a half-day, the hour printed on a trend column, the sunrise time. The
   * port used the DEVICE's timezone for all of it, which is only right while the device and the
   * location happen to agree — true for Helsinki on the reference phones, wrong for Berlin and
   * Tokyo. `common/LocalTime.ets` does the conversion from this offset.
   */
  @Trace utcOffsetSeconds: number = 0;
  /**
   * Location.isDaylight (Location.kt:45-52) — true when now falls strictly between today's
   * sunrise and sunset. Computed from the calculated sun times on every refresh; it selects the
   * day or night theme, background gradient and icon set.
   */
  @Trace daylight: boolean = true;
  @Trace weather: Weather | null = null;
}
