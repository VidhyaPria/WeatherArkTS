/*
 * The source catalogue — SourceManager.kt's `sourceList`, metadata only.
 *
 * CLAUDE.md scopes the port to ONE live source (Open-Meteo) but explicitly does NOT scope down the
 * metadata: any screen that lists sources renders the full catalogue exactly as Android does,
 * "including each source's supported features. Port the metadata table, not the clients."
 *
 * Android already draws that line for us. Almost every source is split into a metadata-only
 * `*ServiceStub.kt` under `app/src/main/kotlin/org/breezyweather/sources/` (46 files) and a client
 * under `src_freenet` / `src_nonfreenet`. This file is the ArkTS transcription of the stub layer —
 * id, display name, continent, supported features, and the two per-location predicates:
 *
 *   isFeatureSupportedForLocation   can this source answer this feature HERE (country / bbox)
 *   getFeaturePriorityForLocation   is it RECOMMENDED here, and how strongly
 *
 * ORDER MATTERS. SourceManager.kt:313 says "The order of this list is preserved in source chooser
 * dialogs", and `sourceList` (:314-330) is built as:
 *
 *   locationSourceList         (:210-214)  native, ipsb, baidu_ip
 *   locationSearchSourceList   (:217-219)  geonames
 *   reverseGeocodingSourceList (:222-226)  naturalearth, nativegeocoder, nominatim
 *   worldwideWeatherSourceList (:230-240)  openmeteo, accu, fpas, infoplaza, metno, ncei,
 *                                          openweather, pirateweather, wmosevereweather
 *   nationalWeatherSourceList  (:243-303)  sorted by localised NAME (:324-327)
 *   broadcastSourceList        (:306-309)  not FeatureSources, omitted
 *
 * DELIBERATE DEVIATIONS, all bounded and stated:
 *
 * 1. Display names are the ENGLISH forms. Every `name` that interpolates
 *    `currentLocale.getCountryName(cc)` is resolved here with the CLDR English country name, and
 *    the `.let { if (it.contains(countryName)) it else "$it ($countryName)" }` wrapper is resolved
 *    too (so "Météo-France" stays bare but "MET Éireann" gains "(Ireland)"). CLDR has variants for
 *    a few territories — HK/MO/TW/CD/TR especially — worth a side-by-side against the Android
 *    dialog when the picker screen lands.
 * 2. The Atmo regional predicates (AtmoAuraService etc.) test admin1, admin1Code, admin2 AND
 *    admin2Code. Open-Meteo's geocoding returns names but no ISO admin codes, so only the two NAME
 *    terms are modelled. This can only under-recommend a French regional air-quality source.
 * 3. `RemovedSource` and the freenet gating do not apply to this build; `ConfigurableSource` does,
 *    and is carried as `configured` (see the note on that field).
 */

import { LocationModel } from '../model/Weather';

/** BuildConfig.DEFAULT_LOCATION_SEARCH_SOURCE — app/build.gradle.kts:225-229. */
export const DEFAULT_LOCATION_SEARCH_SOURCE: string = 'openmeteo';
/** BuildConfig.DEFAULT_FORECAST_SOURCE — the source a new location starts on. */
export const DEFAULT_FORECAST_SOURCE: string = 'openmeteo';

/** domain/.../source/SourceFeature.kt:22-29. */
export enum SourceFeature {
  FORECAST,
  CURRENT,
  AIR_QUALITY,
  POLLEN,
  MINUTELY,
  ALERT,
  NORMALS,
  REVERSE_GEOCODING
}

/** domain/.../source/SourceContinent.kt:22-28. */
export enum SourceContinent {
  WORLDWIDE,
  AFRICA,
  ASIA,
  EUROPE,
  NORTH_AMERICA,
  OCEANIA,
  SOUTH_AMERICA
}

/** FeatureSource.kt:70-77. */
export const PRIORITY_HIGHEST: number = 100;
export const PRIORITY_HIGH: number = 75;
export const PRIORITY_MEDIUM: number = 50;
export const PRIORITY_LOW: number = 25;
export const PRIORITY_LOWEST: number = 0;
export const PRIORITY_NONE: number = -1;

/**
 * The row titles — `SourceFeature.resourceName` via strings.xml. Used by the weather-sources dialog
 * for its eight rows, and by nothing else.
 */
export function sourceFeatureName(feature: SourceFeature): string {
  switch (feature) {
    case SourceFeature.FORECAST:
      return 'Forecast';                 // strings.xml `forecast`
    case SourceFeature.CURRENT:
      return 'Current weather';          // `current_weather`
    case SourceFeature.AIR_QUALITY:
      return 'Air quality';              // `air_quality`
    case SourceFeature.POLLEN:
      return 'Pollen';                   // `pollen`
    case SourceFeature.MINUTELY:
      return 'Precipitation nowcasting'; // `precipitation_nowcasting`
    case SourceFeature.ALERT:
      return 'Alerts';                   // `alerts`
    case SourceFeature.NORMALS:
      return 'Temperature normals';      // `temperature_normals`
    default:
      // `location_reverse_geocoding` — the user-facing name is "Address lookup", not the
      // internal one the enum constant suggests.
      return 'Address lookup';
  }
}

/** `SourceContinent.resourceName`, plus the pseudo-group Recommended (weather_source_recommended). */
export const GROUP_RECOMMENDED: string = 'Recommended';

export function sourceContinentName(continent: SourceContinent): string {
  switch (continent) {
    case SourceContinent.WORLDWIDE:
      return 'Worldwide';
    case SourceContinent.AFRICA:
      return 'Africa';
    case SourceContinent.ASIA:
      return 'Asia';
    case SourceContinent.EUROPE:
      return 'Europe';
    case SourceContinent.NORTH_AMERICA:
      return 'North America';
    case SourceContinent.OCEANIA:
      return 'Oceania';
    default:
      return 'South America';
  }
}

/* ------------------------------------------------------------------ bounding boxes ------------ */

/**
 * `com.google.maps.android.model.LatLngBounds`, reduced to the one operation the stubs use.
 *
 * Android has two spellings — the constructor takes (southwest, northeast) as LatLng pairs, while
 * `LatLngBounds.parse` takes (west, south, east, north). Both are normalised to this one shape, and
 * each constant below is commented with the spelling it came from so it can be checked against the
 * Kotlin without re-deriving the argument order.
 */
export class Bbox {
  readonly west: number;
  readonly south: number;
  readonly east: number;
  readonly north: number;

  constructor(west: number, south: number, east: number, north: number) {
    this.west = west;
    this.south = south;
    this.east = east;
    this.north = north;
  }

  contains(latitude: number, longitude: number): boolean {
    return latitude >= this.south && latitude <= this.north &&
      longitude >= this.west && longitude <= this.east;
  }
}

/** CAMS' European pollen domain — shared by Open-Meteo and AccuWeather (OpenMeteoService.kt). */
const COPERNICUS_POLLEN_BBOX = new Bbox(-25.0, 30.0, 45.0, 72.0);
/** AccuServiceStub — LatLngBounds(LatLng(23.542547919, -125.734607238), LatLng(50.369494121, -65.977324999)). */
const CONTIGUOUS_US_STATES_BBOX = new Bbox(-125.734607238, 23.542547919, -65.977324999, 50.369494121);
/** FmiServiceStub:82-85 — LatLngBounds(LatLng(53.9, 4.88877), LatLng(72.269067, 32.931465)). */
const FMI_FORECAST_BBOX = new Bbox(4.888770, 53.900000, 32.931465, 72.269067);
/** FmiServiceStub:86-89 — the SILAM air-quality domain. */
const FMI_SILAM_BBOX = new Bbox(-24.950000, 30.050000, 45.049999, 72.049999);
/** NlscServiceStub — LatLngBounds.parse(west, south, east, north). Shared by CWA, NCDR and NLSC. */
const TAIWAN_BBOX = new Bbox(119.99690416, 21.756143532, 122.10915909, 25.633378776);
const PENGHU_BBOX = new Bbox(119.314301816, 23.186561404, 119.726986388, 23.810692086);
const KINMEN_BBOX = new Bbox(118.137979837, 24.160255444, 118.505977425, 24.534228163);
const WUQIU_BBOX = new Bbox(119.443195363, 24.97760013, 119.479213453, 24.999614154);
const MATSU_BBOX = new Bbox(119.908905081, 25.940995457, 120.511750672, 26.385275262);
/** GeoSphereAtServiceStub — parse(west, south, east, north). */
const GEOSPHERE_HOURLY_BBOX = new Bbox(5.49, 42.98, 22.1, 51.82);
const GEOSPHERE_AIR_QUALITY_9KM_BBOX = new Bbox(-53.73, 15.59, 80.33, 74.39);
const GEOSPHERE_NOWCAST_BBOX = new Bbox(8.1, 45.5, 17.74, 49.48);

function inTaiwan(location: LocationModel): boolean {
  return isCountry(location, 'TW') ||
    TAIWAN_BBOX.contains(location.latitude, location.longitude) ||
    PENGHU_BBOX.contains(location.latitude, location.longitude) ||
    KINMEN_BBOX.contains(location.latitude, location.longitude) ||
    WUQIU_BBOX.contains(location.latitude, location.longitude) ||
    MATSU_BBOX.contains(location.latitude, location.longitude);
}

/* ------------------------------------------------------------------ the predicates ------------ */

export type SupportFn = (location: LocationModel, feature: SourceFeature) => boolean;
export type PriorityFn = (location: LocationModel, feature: SourceFeature) => number;

/** `location.countryCode.equals(code, ignoreCase = true)`. */
function isCountry(location: LocationModel, code: string): boolean {
  return location.countryCode.toUpperCase() === code.toUpperCase();
}

/** `arrayOf(...).any { location.countryCode.equals(it, ignoreCase = true) }`. */
function isCountryIn(location: LocationModel, codes: string[]): boolean {
  for (let i = 0; i < codes.length; i++) {
    if (isCountry(location, codes[i])) {
      return true;
    }
  }
  return false;
}

/** The overwhelmingly common stub body: supported exactly in these countries, for every feature. */
function countriesOnly(codes: string[]): SupportFn {
  return (location: LocationModel, feature: SourceFeature) => isCountryIn(location, codes);
}

/**
 * The equally common priority body:
 *   `isFeatureSupportedForLocation(location, feature) -> PRIORITY_HIGHEST else PRIORITY_NONE`.
 * Passed the source's own support function so the two stay in step, as the Kotlin's does.
 */
function highestWhenSupported(support: SupportFn): PriorityFn {
  return (location: LocationModel, feature: SourceFeature) =>
  support(location, feature) ? PRIORITY_HIGHEST : PRIORITY_NONE;
}

/** A source that is recommended in these countries whatever its support rule says. */
function highestInCountries(codes: string[]): PriorityFn {
  return (location: LocationModel, feature: SourceFeature) =>
  isCountryIn(location, codes) ? PRIORITY_HIGHEST : PRIORITY_NONE;
}

/* ---------------------------------------------------------------------- SourceInfo ------------ */

/** The constructor payload, so the ~75 entries below read as a table rather than as argument soup. */
export interface SourceSpec {
  id: string;
  name: string;
  continent: SourceContinent;
  /** The keys of `supportedFeatures`. Empty for a pure LocationSource, which no feature row lists. */
  features: SourceFeature[];
  support?: SupportFn;
  priority?: PriorityFn;
  /** LocationSearchSource.locationSearchAttribution — only the search sources carry one. */
  searchAttribution?: string;
  /** Whether this port has a client for it. Only Open-Meteo does; see the file header. */
  implemented?: boolean;
  /**
   * ConfigurableSource.isConfigured. LocationPreferences.kt:341-344 makes a row unselectable when a
   * source is configurable and NOT configured, and `SourceExtensions.getName` renames it to
   * "%s (not configured)".
   *
   * Which sources that covers is a property of the BUILD, not of the source, so it was read off the
   * reference device rather than guessed: its Forecast picker suffixes Infoplaza, PirateWeather and
   * Met Office, and leaves AccuWeather, OpenWeather, Open-Meteo, MET Norway, DMI, Météo-France and
   * Servizio Meteo AM unsuffixed. CWA is still unchecked — no Taiwanese location to list it.
   */
  configured?: boolean;
}

export class SourceInfo {
  readonly id: string;
  readonly name: string;
  readonly continent: SourceContinent;
  readonly features: SourceFeature[];
  readonly searchAttribution: string;
  readonly implemented: boolean;
  readonly configured: boolean;
  private readonly supportFn: SupportFn | null;
  private readonly priorityFn: PriorityFn | null;

  constructor(spec: SourceSpec) {
    this.id = spec.id;
    this.name = spec.name;
    this.continent = spec.continent;
    this.features = spec.features;
    this.searchAttribution = spec.searchAttribution ?? '';
    this.implemented = spec.implemented ?? false;
    this.configured = spec.configured ?? true;
    this.supportFn = spec.support ?? null;
    this.priorityFn = spec.priority ?? null;
  }

  /** `supportedFeatures.containsKey(feature)`. */
  declares(feature: SourceFeature): boolean {
    return this.features.includes(feature);
  }

  /** LocationSearchSource — the search screen's own chooser lists exactly these. */
  isLocationSearchSource(): boolean {
    return this.searchAttribution.length > 0;
  }

  /** FeatureSource.isFeatureSupportedForLocation — default `true` (FeatureSource.kt:52-55). */
  supports(location: LocationModel, feature: SourceFeature): boolean {
    if (this.supportFn === null) {
      return true;
    }
    return this.supportFn(location, feature);
  }

  /** FeatureSource.getFeaturePriorityForLocation — default PRIORITY_NONE (kt:65-68). */
  priority(location: LocationModel, feature: SourceFeature): number {
    if (this.priorityFn === null) {
      return PRIORITY_NONE;
    }
    return this.priorityFn(location, feature);
  }

  /** Source.getGroup (Source.kt:44-54) — Recommended, else the source's continent. */
  group(location: LocationModel, feature: SourceFeature): string {
    if (this.priority(location, feature) >= 0) {
      return GROUP_RECOMMENDED;
    }
    return sourceContinentName(this.continent);
  }
}

/* ------------------------------------------------------- per-source support predicates -------- */
/*
 * Only the sources whose rule is NOT "these countries, every feature" need a named function; the
 * rest are built inline with countriesOnly(...). Each is annotated with its stub.
 */

/** AccuServiceStub:isFeatureSupportedForLocation. `portal` is the free portal on a stock build. */
const accuSupport: SupportFn = (location: LocationModel, feature: SourceFeature) => {
  if (feature === SourceFeature.POLLEN) {
    return COPERNICUS_POLLEN_BBOX.contains(location.latitude, location.longitude) ||
      (isCountry(location, 'US') &&
        CONTIGUOUS_US_STATES_BBOX.contains(location.latitude, location.longitude)) ||
      isCountry(location, 'CA');
  }
  // portal == ENTERPRISE is false on a stock build, so the remaining features are the four listed.
  return feature === SourceFeature.FORECAST || feature === SourceFeature.CURRENT ||
    feature === SourceFeature.ALERT || feature === SourceFeature.REVERSE_GEOCODING;
};

/** OpenMeteoService:isFeatureSupportedForLocation — worldwide except pollen, which is CAMS Europe. */
const openMeteoSupport: SupportFn = (location: LocationModel, feature: SourceFeature) => {
  if (feature === SourceFeature.POLLEN) {
    return COPERNICUS_POLLEN_BBOX.contains(location.latitude, location.longitude);
  }
  return true;
};

/** FmiServiceStub:66-72 — two of the five features are bbox-gated, the rest are FI/AX. */
const fmiSupport: SupportFn = (location: LocationModel, feature: SourceFeature) => {
  if (feature === SourceFeature.FORECAST) {
    return FMI_FORECAST_BBOX.contains(location.latitude, location.longitude);
  }
  if (feature === SourceFeature.AIR_QUALITY) {
    return FMI_SILAM_BBOX.contains(location.latitude, location.longitude);
  }
  return isCountryIn(location, ['FI', 'AX']);
};

/** MetNoServiceStub — worldwide forecast, everything else Nordic-gated. */
const metNoSupport: SupportFn = (location: LocationModel, feature: SourceFeature) => {
  switch (feature) {
    case SourceFeature.CURRENT:
    case SourceFeature.MINUTELY:
      return isCountryIn(location, ['NO', 'SE', 'FI', 'DK']);
    case SourceFeature.AIR_QUALITY:
      return isCountry(location, 'NO');
    case SourceFeature.ALERT:
      return isCountryIn(location, ['NO', 'SJ']);
    case SourceFeature.FORECAST:
      return true;
    default:
      return false;
  }
};

const metNoPriority: PriorityFn = (location: LocationModel, feature: SourceFeature) => {
  if (isCountry(location, 'NO')) {
    return PRIORITY_HIGHEST;
  }
  if (isCountryIn(location, ['SJ', 'SE', 'FI', 'DK']) && metNoSupport(location, feature)) {
    return PRIORITY_HIGH;
  }
  return PRIORITY_NONE;
};

/** MfServiceStub — forecast and reverse geocoding worldwide, the rest by territory. */
const MF_ALERT_COUNTRIES: string[] =
  ['FR', 'AD', 'BL', 'GF', 'GP', 'MF', 'MQ', 'NC', 'PF', 'PM', 'RE', 'WF', 'YT'];
const MF_NORMALS_COUNTRIES: string[] =
  ['FR', 'AD', 'MC', 'BL', 'GF', 'GP', 'MF', 'MQ', 'NC', 'PF', 'PM', 'RE', 'WF', 'YT'];

const mfSupport: SupportFn = (location: LocationModel, feature: SourceFeature) => {
  switch (feature) {
    case SourceFeature.CURRENT:
    case SourceFeature.MINUTELY:
      return isCountry(location, 'FR');
    case SourceFeature.ALERT:
      return isCountryIn(location, MF_ALERT_COUNTRIES);
    case SourceFeature.NORMALS:
      return isCountryIn(location, MF_NORMALS_COUNTRIES);
    case SourceFeature.FORECAST:
    case SourceFeature.REVERSE_GEOCODING:
      return true; // Main source available worldwide
    default:
      return false;
  }
};

/** kt:903-919 — forecast and reverse geocoding borrow NORMALS' criteria, since they are worldwide. */
const mfPriority: PriorityFn = (location: LocationModel, feature: SourceFeature) => {
  const effective: SourceFeature =
    (feature === SourceFeature.FORECAST || feature === SourceFeature.REVERSE_GEOCODING)
      ? SourceFeature.NORMALS
      : feature;
  return mfSupport(location, effective) ? PRIORITY_HIGHEST : PRIORITY_NONE;
};

/** DmiServiceStub — everything worldwide EXCEPT alerts, which are DK/FO/GL. */
const dmiSupport: SupportFn = (location: LocationModel, feature: SourceFeature) =>
feature !== SourceFeature.ALERT || isCountryIn(location, ['DK', 'FO', 'GL']);

/** kt:247-256 — "Always use the same criterias as alert". */
const dmiPriority: PriorityFn = (location: LocationModel, feature: SourceFeature) =>
isCountryIn(location, ['DK', 'FO', 'GL']) ? PRIORITY_HIGHEST : PRIORITY_NONE;

/** GeoSphereAtServiceStub — three bboxes and one country test. */
const geoSphereSupport: SupportFn = (location: LocationModel, feature: SourceFeature) => {
  switch (feature) {
    case SourceFeature.FORECAST:
      return GEOSPHERE_HOURLY_BBOX.contains(location.latitude, location.longitude);
    case SourceFeature.AIR_QUALITY:
      return GEOSPHERE_AIR_QUALITY_9KM_BBOX.contains(location.latitude, location.longitude);
    case SourceFeature.MINUTELY:
      return GEOSPHERE_NOWCAST_BBOX.contains(location.latitude, location.longitude);
    case SourceFeature.ALERT:
      return isCountry(location, 'AT');
    default:
      return false;
  }
};

const geoSpherePriority: PriorityFn = (location: LocationModel, feature: SourceFeature) => {
  if (isCountry(location, 'AT') && feature !== SourceFeature.FORECAST) {
    return PRIORITY_HIGHEST;
  }
  if (feature === SourceFeature.MINUTELY && geoSphereSupport(location, feature)) {
    return PRIORITY_HIGH;
  }
  return PRIORITY_NONE;
};

/** CwaServiceStub:213-225 — alerts drop to HIGH deliberately, "This makes NCDR being used in priority". */
const cwaPriority: PriorityFn = (location: LocationModel, feature: SourceFeature) => {
  if (!inTaiwan(location)) {
    return PRIORITY_NONE;
  }
  return feature === SourceFeature.ALERT ? PRIORITY_HIGH : PRIORITY_HIGHEST;
};

/** KnmiService — alerts additionally need a recognised admin1; the port has the NAME only. */
const knmiSupport: SupportFn = (location: LocationModel, feature: SourceFeature) =>
isCountry(location, 'NL');

/** PollenInfoServiceStub — supported in 13 countries but recommended only in Austria. */
const POLLEN_INFO_COUNTRIES: string[] =
  ['AT', 'CH', 'DE', 'ES', 'FR', 'GB', 'IT', 'LT', 'LV', 'PL', 'SE', 'TR', 'UA'];

const pollenInfoPriority: PriorityFn = (location: LocationModel, feature: SourceFeature) =>
(feature === SourceFeature.POLLEN && isCountry(location, 'AT')) ? PRIORITY_HIGH : PRIORITY_NONE;

/**
 * AtmoServiceStub — France AND inside the agency's own region.
 *
 * See deviation 2 in the file header: the Kotlin also accepts admin1Code / admin2Code, which
 * Open-Meteo's geocoding does not return.
 */
function atmoRegion(admin1Names: string[], admin2Names: string[]): SupportFn {
  return (location: LocationModel, feature: SourceFeature) => {
    if (feature !== SourceFeature.AIR_QUALITY || !isCountry(location, 'FR')) {
      return false;
    }
    return admin1Names.includes(location.region) || admin2Names.includes(location.admin2);
  };
}

/**
 * ClimWebService:isFeatureSupportedForLocation — one country each, and NORMALS additionally needs a
 * `cityClimatePageId`, which only six of the seventeen instances define.
 */
function climWeb(countryCode: string, hasNormals: boolean): SupportFn {
  return (location: LocationModel, feature: SourceFeature) => {
    if (feature === SourceFeature.ALERT) {
      return isCountry(location, countryCode);
    }
    if (feature === SourceFeature.NORMALS) {
      return isCountry(location, countryCode) && hasNormals;
    }
    return false;
  };
}

/** One regional Atmo agency — France plus its own departments, air quality only. */
function atmoSource(
  id: string,
  name: string,
  admin1Names: string[],
  admin2Names: string[]
): SourceInfo {
  const support: SupportFn = atmoRegion(admin1Names, admin2Names);
  return new SourceInfo({
    id: id,
    name: name,
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.AIR_QUALITY],
    support: support,
    priority: highestWhenSupported(support)
  });
}

/** Every ClimWeb instance declares both features; support is what narrows them. */
const CLIMWEB_FEATURES: SourceFeature[] = [SourceFeature.ALERT, SourceFeature.NORMALS];

function climWebSource(id: string, name: string, countryCode: string, hasNormals: boolean): SourceInfo {
  const support: SupportFn = climWeb(countryCode, hasNormals);
  return new SourceInfo({
    id: id,
    name: name,
    continent: SourceContinent.AFRICA,
    features: CLIMWEB_FEATURES,
    support: support,
    priority: highestWhenSupported(support)
  });
}

/** The plain national pattern: these countries, every declared feature, recommended when supported. */
function nationalSource(
  id: string,
  name: string,
  continent: SourceContinent,
  features: SourceFeature[],
  countries: string[]
): SourceInfo {
  const support: SupportFn = countriesOnly(countries);
  return new SourceInfo({
    id: id,
    name: name,
    continent: continent,
    features: features,
    support: support,
    priority: highestWhenSupported(support)
  });
}

/* ------------------------------------------------------------------------ the table ----------- */

/**
 * `sourceList` (SourceManager.kt:314-330), in order.
 *
 * The national block is sorted by localised name, which for English is the order below — check it
 * against the device before assuming a mismatch is a bug, since a different locale reorders it.
 */
const FIXED_ORDER_SOURCES: SourceInfo[] = [
  // ---- locationSourceList (:210-214). Not FeatureSources: no feature row ever lists them. ----
  new SourceInfo({ id: 'native', name: 'Android', continent: SourceContinent.WORLDWIDE, features: [] }),
  new SourceInfo({ id: 'ipsb', name: 'IP.SB', continent: SourceContinent.WORLDWIDE, features: [] }),
  new SourceInfo({
    id: 'baidu_ip',
    name: 'Baidu IP location (China)',
    continent: SourceContinent.ASIA,
    features: []
  }),

  // ---- locationSearchSourceList (:217-219) ----
  new SourceInfo({
    id: 'geonames',
    name: 'GeoNames',
    continent: SourceContinent.WORLDWIDE,
    features: [],
    searchAttribution: 'GeoNames (CC BY 4.0)'
  }),

  // ---- reverseGeocodingSourceList (:222-226) ----
  // naturalearth is filtered out of every feature list by SourceManager.kt:451 itself.
  new SourceInfo({
    id: 'naturalearth',
    name: 'Natural Earth',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.REVERSE_GEOCODING]
  }),
  new SourceInfo({
    id: 'nativegeocoder',
    name: 'Android',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.REVERSE_GEOCODING],
    // `Geocoder.isPresent()` — there is no platform geocoder on HarmonyOS.
    support: (location: LocationModel, feature: SourceFeature) => false
  }),
  new SourceInfo({
    id: 'nominatim',
    name: 'Nominatim',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.REVERSE_GEOCODING],
    searchAttribution:
    'Nominatim • Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright'
  }),

  // ---- worldwideWeatherSourceList (:230-240) ----
  new SourceInfo({
    id: 'openmeteo',
    name: 'Open-Meteo',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.POLLEN, SourceFeature.MINUTELY],
    support: openMeteoSupport,
    searchAttribution: 'Open-Meteo (CC BY 4.0) • GeoNames',
    implemented: true
  }),
  new SourceInfo({
    id: 'accu',
    name: 'AccuWeather',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.POLLEN, SourceFeature.MINUTELY, SourceFeature.ALERT, SourceFeature.NORMALS,
      SourceFeature.REVERSE_GEOCODING],
    support: accuSupport,
    searchAttribution: 'AccuWeather'
    // Configured on the reference build — its picker rows carry no "(not configured)" suffix.
  }),
  new SourceInfo({
    id: 'fpas',
    name: 'FOSS Public Alert Server (beta)',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.ALERT]
  }),
  new SourceInfo({
    id: 'infoplaza',
    name: 'Infoplaza',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.MINUTELY, SourceFeature.NORMALS],
    configured: false
  }),
  new SourceInfo({
    id: 'metno',
    name: 'MET Norway',
    continent: SourceContinent.WORLDWIDE, // kt:798 "The only exception here"
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.MINUTELY, SourceFeature.AIR_QUALITY, SourceFeature.ALERT],
    support: metNoSupport,
    priority: metNoPriority
  }),
  new SourceInfo({
    id: 'ncei',
    name: 'NCEI',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.NORMALS],
    priority: highestInCountries(['US', 'PR', 'VI', 'MP', 'GU'])
  }),
  new SourceInfo({
    id: 'openweather',
    name: 'OpenWeather',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY]
    // Configured on the reference build, as its unsuffixed picker row shows.
  }),
  new SourceInfo({
    id: 'pirateweather',
    name: 'PirateWeather',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.MINUTELY, SourceFeature.ALERT],
    configured: false
  }),
  new SourceInfo({
    id: 'wmosevereweather',
    name: 'WMO Severe Weather Information Centre',
    continent: SourceContinent.WORLDWIDE,
    features: [SourceFeature.ALERT]
  }),

];

/**
 * nationalWeatherSourceList (:243-303).
 *
 * Authored in the Kotlin's own declaration order and SORTED BELOW, rather than hand-ordered here,
 * because kt:324-327 sorts it at runtime with a `Collator` on the DISPLAY NAME — and the display
 * name often has nothing to do with the id. Hand-ordering got that wrong and it showed: the port
 * put Servizio Meteo AM (id `meteoam`) between Met Office and Météo-France, where the Android
 * device lists Met Office, Météo-France, Servizio Meteo AM. Sorting is both shorter and correct.
 */
const NATIONAL_SOURCES: SourceInfo[] = [
  nationalSource('aemet', 'AEMET (Spain)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.NORMALS], ['ES']),
  climWebSource('anambf', 'ANAM-BF (Burkina Faso)', 'BF', false),
  climWebSource('anamet', 'ANAMET (Togo)', 'TG', false),
  atmoSource('atmoaura', 'Atmo Auvergne-Rhône-Alpes (France)',
    ['Auvergne-Rhône-Alpes'],
    ['Ain', 'Allier', 'Ardèche', 'Cantal', 'Drôme', 'Isère', 'Loire', 'Haute-Loire',
      'Puy-de-Dôme', 'Rhône', 'Savoie', 'Haute-Savoie']),
  new SourceInfo({
    id: 'atmofrance',
    name: 'Atmo France',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.POLLEN],
    support: (location: LocationModel, feature: SourceFeature) =>
    feature === SourceFeature.POLLEN && isCountry(location, 'FR'),
    priority: (location: LocationModel, feature: SourceFeature) =>
    (feature === SourceFeature.POLLEN && isCountry(location, 'FR')) ? PRIORITY_HIGHEST : PRIORITY_NONE
  }),
  atmoSource('atmograndest', 'ATMO GrandEst (France)',
    ['Grand Est', 'Grand-Est'],
    ['Ardennes', 'Aube', 'Marne', 'Haute-Marne', 'Meurthe-et-Moselle', 'Meuse', 'Moselle',
      'Bas-Rhin', 'Haut-Rhin', 'Vosges']),
  atmoSource('atmohdf', 'Atmo Hauts-de-France (France)',
    ['Hauts-de-France', 'Hauts de France'],
    ['Aisne', 'Nord', 'North', 'Oise', 'Pas-de-Calais', 'Pas de Calais', 'Somme']),
  atmoSource('atmosud', 'AtmoSud (France)',
    ["Provence-Alpes-Côte d'Azur", "Provence Alpes Côte d'Azur"],
    ['Alpes-de-Haute-Provence', 'Hautes-Alpes', 'Alpes-Maritimes', 'Bouches-du-Rhône',
      'Var', 'Vaucluse']),
  nationalSource('bmd', 'BMD (Bangladesh)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.REVERSE_GEOCODING], ['BD']),
  nationalSource('bmkg', 'BMKG (Indonesia)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['ID']),
  nationalSource('brightsky', 'Bright Sky (DWD) (Germany)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT], ['DE']),
  // China is a LocationSearchSource as well as a weather source — the one national source that is,
  // which is why it closes the search screen's five-row chooser (ChinaServiceStub.kt:42-46).
  new SourceInfo({
    id: 'china',
    name: 'China',
    continent: SourceContinent.ASIA,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY,
      SourceFeature.MINUTELY, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING],
    support: countriesOnly(['CN']),
    priority: highestWhenSupported(countriesOnly(['CN'])),
    searchAttribution: '北京天气、彩云天气、中国环境监测总站'
  }),
  new SourceInfo({
    id: 'cwa',
    // CwaService's name is "CWA (${currentLocale.getCountryName("TW")})", and the reference device
    // renders TW as "Taiwan, China". Read off its Weather sources screen, not guessed.
    name: 'CWA (Taiwan, China)',
    continent: SourceContinent.ASIA,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.ALERT, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING],
    support: (location: LocationModel, feature: SourceFeature) => inTaiwan(location),
    priority: cwaPriority,
    configured: false
  }),
  climWebSource('dccms', 'DCCMS (Malawi)', 'MW', true),
  new SourceInfo({
    id: 'dmi',
    name: 'DMI (Denmark)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING],
    support: dmiSupport,
    priority: dmiPriority
  }),
  climWebSource('dmnne', 'DMN (Niger)', 'NE', true),
  climWebSource('dwrgm', 'DWR (Gambia)', 'GM', false),
  nationalSource('eccc', 'ECCC (Canada)', SourceContinent.NORTH_AMERICA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING], ['CA']),
  nationalSource('ekuk', 'EKUK (Estonia)', SourceContinent.EUROPE,
    [SourceFeature.AIR_QUALITY, SourceFeature.POLLEN], ['EE']),
  climWebSource('ethiomet', 'EMI (Ethiopia)', 'ET', true),
  nationalSource('epdhk', 'EPD (Hong Kong SAR China)', SourceContinent.ASIA,
    [SourceFeature.AIR_QUALITY], ['HK']),
  new SourceInfo({
    id: 'fmi',
    name: 'FMI (Finland)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.ALERT, SourceFeature.NORMALS],
    support: fmiSupport,
    priority: highestInCountries(['FI', 'AX'])
  }),
  new SourceInfo({
    id: 'geosphereat',
    name: 'GeoSphere Austria',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST, SourceFeature.AIR_QUALITY, SourceFeature.MINUTELY, SourceFeature.ALERT],
    support: geoSphereSupport,
    priority: geoSpherePriority
  }),
  climWebSource('gmet', 'GMet (Ghana)', 'GH', false),
  nationalSource('hko', 'HKO (Hong Kong SAR China)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING], ['HK']),
  climWebSource('igebu', 'IGEBU (Burundi)', 'BI', false),
  nationalSource('ilmateenistus', 'Ilmateenistus (Estonia)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.REVERSE_GEOCODING], ['EE']),
  nationalSource('imd', 'IMD (India)', SourceContinent.ASIA, [SourceFeature.FORECAST], ['IN']),
  nationalSource('ims', 'IMS (Israel)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['IL', 'PS']),
  climWebSource('inmgb', 'INM-GB (Guinea-Bissau)', 'GW', false),
  nationalSource('ipma', 'IPMA (Portugal)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['PT']),
  nationalSource('jma', 'JMA (Japan)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING], ['JP']),
  new SourceInfo({
    id: 'knmi',
    name: 'Koninklijk Nederlands Meteorologisch Instituut (Netherlands)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.NORMALS],
    support: knmiSupport,
    priority: highestWhenSupported(knmiSupport)
  }),
  nationalSource('lhmt', 'LHMT (Lithuania)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['LT']),
  nationalSource('lvgmc', 'LVĢMC (Latvia)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.REVERSE_GEOCODING], ['LV']),
  climWebSource('malimeteo', 'Mali-Météo', 'ML', false),
  nationalSource('metie', 'MET Éireann (Ireland)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['IE']),
  new SourceInfo({
    id: 'metoffice',
    name: 'Met Office (United Kingdom)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST],
    priority: highestInCountries(['GB', 'GG', 'IM', 'JE', 'GI', 'FK']),
    configured: false
  }),
  new SourceInfo({
    id: 'meteoam',
    name: 'Servizio Meteo AM (Italy)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.REVERSE_GEOCODING],
    priority: highestInCountries(['IT', 'SM', 'VA'])
  }),
  climWebSource('meteobenin', 'Météo Bénin (Benin)', 'BJ', true),
  nationalSource('meteolux', 'MeteoLux (Luxembourg)', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['LU']),
  climWebSource('meteotchad', 'Météo Tchad (Chad)', 'TD', true),
  climWebSource('mettelsat', 'Mettelsat RDC (Congo - Kinshasa)', 'CD', false),
  new SourceInfo({
    id: 'mf',
    name: 'Météo-France',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.MINUTELY, SourceFeature.ALERT, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING],
    support: mfSupport,
    priority: mfPriority
    // Configured on the reference build — it appears unsuffixed in the Europe group.
  }),
  nationalSource('mgm', 'MGM (Türkiye)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING], ['TR']),
  climWebSource('msdzw', 'MSD (Zimbabwe)', 'ZW', false),
  nationalSource('namem', 'NAMEM (Mongolia)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.NORMALS, SourceFeature.REVERSE_GEOCODING], ['MN']),
  new SourceInfo({
    id: 'ncdr',
    name: 'NCDR (Taiwan)',
    continent: SourceContinent.ASIA,
    features: [SourceFeature.ALERT],
    support: (location: LocationModel, feature: SourceFeature) => inTaiwan(location),
    priority: (location: LocationModel, feature: SourceFeature) =>
    inTaiwan(location) ? PRIORITY_HIGHEST : PRIORITY_NONE
  }),
  new SourceInfo({
    id: 'nlsc',
    name: 'NLSC (Taiwan)',
    continent: SourceContinent.ASIA,
    features: [SourceFeature.REVERSE_GEOCODING],
    support: (location: LocationModel, feature: SourceFeature) => inTaiwan(location),
    priority: (location: LocationModel, feature: SourceFeature) =>
    inTaiwan(location) ? PRIORITY_HIGHEST : PRIORITY_NONE
  }),
  nationalSource('nws', 'NWS (United States)', SourceContinent.NORTH_AMERICA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['US', 'GU', 'MP', 'PR', 'VI']),
  nationalSource('pagasa', 'PAGASA (Philippines)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT], ['PH']),
  new SourceInfo({
    id: 'polleninfo',
    name: 'Pollen Information Service (Austria)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.POLLEN],
    support: countriesOnly(POLLEN_INFO_COUNTRIES),
    priority: pollenInfoPriority
  }),
  new SourceInfo({
    id: 'recosante',
    name: 'Recosanté (France)',
    continent: SourceContinent.EUROPE,
    features: [SourceFeature.POLLEN],
    support: countriesOnly(['FR']),
    // kt:1189-1197 — MEDIUM, not HIGHEST: Atmo France outranks it.
    priority: (location: LocationModel, feature: SourceFeature) =>
    isCountry(location, 'FR') ? PRIORITY_MEDIUM : PRIORITY_NONE
  }),
  climWebSource('smasc', 'SMA (Seychelles)', 'SC', true),
  climWebSource('smasu', 'SMA (Sudan)', 'SD', false),
  nationalSource('smg', 'SMG (Macao SAR China)', SourceContinent.ASIA,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.AIR_QUALITY, SourceFeature.ALERT, SourceFeature.NORMALS], ['MO']),
  nationalSource('smhi', 'SMHI (Sweden)', SourceContinent.EUROPE, [SourceFeature.FORECAST], ['SE']),
  climWebSource('ssms', 'SSMS (South Sudan)', 'SS', false),
  nationalSource('veduris', 'Icelandic Met Office', SourceContinent.EUROPE,
    [SourceFeature.FORECAST, SourceFeature.CURRENT, SourceFeature.ALERT, SourceFeature.REVERSE_GEOCODING], ['IS'])
];

/**
 * `sourceList` (SourceManager.kt:314-330) — the fixed-order block, then the national block sorted
 * by display name, which is what kt:324-327's Collator does.
 */
export const SOURCES: SourceInfo[] = FIXED_ORDER_SOURCES.concat(
  NATIONAL_SOURCES.sort((a: SourceInfo, b: SourceInfo) => a.name.localeCompare(b.name))
);

/* --------------------------------------------------------------------- the queries ------------ */

export function getSource(id: string): SourceInfo | null {
  for (let i = 0; i < SOURCES.length; i++) {
    if (SOURCES[i].id === id) {
      return SOURCES[i];
    }
  }
  return null;
}

/**
 * SourceManager.getSupportedFeatureSources (kt:444-466).
 *
 * `naturalearth` is excluded by id upstream, and a source is kept when it declares the feature AND
 * either supports it here or the location is a current position with no fix yet (kt:460).
 * `sourceException` is the currently selected source, kept even when it no longer qualifies, so the
 * caller can render it as "(unavailable)" instead of silently dropping it.
 */
export function getSupportedFeatureSources(
  feature: SourceFeature,
  location: LocationModel,
  sourceException: string
): SourceInfo[] {
  const result: SourceInfo[] = [];
  const usable: boolean = !(location.isCurrentPosition && !isUsable(location));
  for (let i = 0; i < SOURCES.length; i++) {
    const source: SourceInfo = SOURCES[i];
    if (source.id === 'naturalearth') {
      continue;
    }
    if (source.id === sourceException) {
      result.push(source);
      continue;
    }
    if (source.declares(feature) && (!usable || source.supports(location, feature))) {
      result.push(source);
    }
  }
  return result;
}

/** Location.isUsable (Location.kt) — a current position with no fix yet has none. */
function isUsable(location: LocationModel): boolean {
  return location.latitude !== 0 || location.longitude !== 0;
}

/** One group of the picker: a heading and the sources under it. */
export class SourceGroup {
  readonly title: string;
  readonly sources: SourceInfo[];

  constructor(title: string, sources: SourceInfo[]) {
    this.title = title;
    this.sources = sources;
  }
}

/**
 * getCompatibleSources (LocationPreferences.kt:293-349).
 *
 * Grouped by `getGroup`, with the groups ordered Recommended → Worldwide → the rest collated by
 * name (kt:300-320), and the Recommended group additionally sorted by priority DESCENDING for every
 * feature except reverse geocoding (kt:329-332).
 */
export function getCompatibleSources(
  feature: SourceFeature,
  location: LocationModel,
  selectedSource: string
): SourceGroup[] {
  const supported: SourceInfo[] = getSupportedFeatureSources(feature, location, selectedSource);

  const titles: string[] = [];
  const buckets: Map<string, SourceInfo[]> = new Map<string, SourceInfo[]>();
  for (let i = 0; i < supported.length; i++) {
    const source: SourceInfo = supported[i];
    const title: string = source.group(location, feature);
    let bucket: SourceInfo[] | undefined = buckets.get(title);
    if (bucket === undefined) {
      bucket = [];
      buckets.set(title, bucket);
      titles.push(title);
    }
    bucket.push(source);
  }

  titles.sort((a: string, b: string) => compareGroups(a, b));

  const groups: SourceGroup[] = [];
  for (let i = 0; i < titles.length; i++) {
    const title: string = titles[i];
    const bucket: SourceInfo[] = buckets.get(title) ?? [];
    if (title === GROUP_RECOMMENDED && feature !== SourceFeature.REVERSE_GEOCODING) {
      bucket.sort((a: SourceInfo, b: SourceInfo) =>
      b.priority(location, feature) - a.priority(location, feature));
    }
    groups.push(new SourceGroup(title, bucket));
  }
  return groups;
}

const WORLDWIDE_TITLE: string = sourceContinentName(SourceContinent.WORLDWIDE);

/** The `groupComparator` at kt:300-320, transcribed branch for branch. */
function compareGroups(a: string, b: string): number {
  if (a === GROUP_RECOMMENDED && b === GROUP_RECOMMENDED) {
    return 0;
  }
  if (a === GROUP_RECOMMENDED) {
    return -1;
  }
  if (b === GROUP_RECOMMENDED) {
    return 1;
  }
  if (a === WORLDWIDE_TITLE && b === WORLDWIDE_TITLE) {
    return 0;
  }
  if (a === WORLDWIDE_TITLE) {
    return -1;
  }
  if (b === WORLDWIDE_TITLE) {
    return 1;
  }
  return a.localeCompare(b);
}

/* ------------------------------------------------------------- the default preset ------------- */

/**
 * SourceManager.getBestSourceForFeature (kt:470-486) — the highest-priority source that can
 * actually answer this feature here.
 *
 * `maxByOrNull` returns the FIRST maximal element, so ties keep `sourceList` order; the strict `>`
 * below does the same.
 */
export function getBestSourceForFeature(
  feature: SourceFeature,
  location: LocationModel
): SourceInfo | null {
  const candidates: SourceInfo[] = getSupportedFeatureSources(feature, location, '');
  let best: SourceInfo | null = null;
  let bestPriority: number = PRIORITY_NONE;
  for (let i = 0; i < candidates.length; i++) {
    const source: SourceInfo = candidates[i];
    // kt:474-480: not removed, supported here, actually recommended, and configured.
    if (!source.configured || !source.supports(location, feature)) {
      continue;
    }
    const priority: number = source.priority(location, feature);
    if (priority <= PRIORITY_NONE) {
      continue;
    }
    if (best === null || priority > bestPriority) {
      best = source;
      bestPriority = priority;
    }
  }
  return best;
}

/** SourceManager.getDefaultSourceForFeature (kt:498-528) — the fallback when nothing is recommended. */
export function getDefaultSourceForFeature(
  feature: SourceFeature,
  location: LocationModel
): SourceInfo | null {
  switch (feature) {
    case SourceFeature.AIR_QUALITY:
      return isCountry(location, 'IN') ? null : getSource('openmeteo');
    case SourceFeature.POLLEN: {
      const openMeteo: SourceInfo | null = getSource('openmeteo');
      if (openMeteo !== null && openMeteo.supports(location, feature)) {
        return openMeteo;
      }
      const accu: SourceInfo | null = getSource('accu');
      return accu !== null && accu.supports(location, feature) ? accu : null;
    }
    case SourceFeature.ALERT:
      return getSource('accu');
    case SourceFeature.NORMALS:
      return isCountry(location, 'CN') ? null : getSource('accu');
    case SourceFeature.REVERSE_GEOCODING:
      return getSource('nominatim');  // BuildConfig.DEFAULT_GEOCODING_SOURCE is naturalearth, but
                                      // kt:526 names nominatim explicitly for this fallback.
    default:
      return getSource('openmeteo');
  }
}

/**
 * SourceManager.getBestSourceForFeatureOrDefault (kt:488-496).
 *
 * Reverse geocoding is only preset for a current position — a saved city already has its address.
 * The Kotlin also allows `needsGeocodeRefresh`, a flag this port's LocationModel does not carry.
 */
export function getBestSourceForFeatureOrDefault(
  feature: SourceFeature,
  location: LocationModel
): SourceInfo | null {
  if (feature !== SourceFeature.REVERSE_GEOCODING || location.isCurrentPosition) {
    const best: SourceInfo | null = getBestSourceForFeature(feature, location);
    return best !== null ? best : getDefaultSourceForFeature(feature, location);
  }
  return null;
}

/**
 * Location.applyDefaultPreset (Location.kt:54-73) — what Android runs on EVERY location it creates,
 * so a new city arrives with all eight sources already chosen rather than eight "None"s.
 *
 * The current-weather line is the one that reads backwards and is transcribed as written (kt:59-64):
 * when no source is RECOMMENDED for CURRENT, the default is kept only if it equals the forecast
 * source, and is otherwise dropped to "" — which the dialog renders as "Forecast", i.e. take the
 * current conditions from the forecast source rather than pinning a second one. That is why the
 * reference device shows Current weather = Open-Meteo when the forecast is Open-Meteo.
 *
 * CONSEQUENCE, and it is deliberate: this port's `refresh()` fetches Open-Meteo plus FMI alerts
 * whatever these fields say, so a location can now display "Alerts: AccuWeather" while the alert it
 * shows came from FMI. That is Android's stored state faithfully reproduced, and it was chosen
 * knowingly over the previous all-empty rows — see PROGRESS. Honouring the fields in the refresh is
 * what closes the gap, and that needs the clients CLAUDE.md scopes out.
 */
export function applyDefaultPreset(location: LocationModel): void {
  const forecast: SourceInfo | null =
    getBestSourceForFeatureOrDefault(SourceFeature.FORECAST, location);
  location.forecastSource = forecast !== null ? forecast.id : DEFAULT_FORECAST_SOURCE;

  const bestCurrent: SourceInfo | null = getBestSourceForFeature(SourceFeature.CURRENT, location);
  if (bestCurrent !== null) {
    location.currentSource = bestCurrent.id;
  } else {
    const fallback: SourceInfo | null =
      getDefaultSourceForFeature(SourceFeature.CURRENT, location);
    location.currentSource =
      fallback !== null && fallback.id === location.forecastSource ? fallback.id : '';
  }

  location.airQualitySource = presetId(SourceFeature.AIR_QUALITY, location);
  location.pollenSource = presetId(SourceFeature.POLLEN, location);
  location.minutelySource = presetId(SourceFeature.MINUTELY, location);
  location.alertSource = presetId(SourceFeature.ALERT, location);
  location.normalsSource = presetId(SourceFeature.NORMALS, location);
  location.reverseGeocodingSource = presetId(SourceFeature.REVERSE_GEOCODING, location);
}

function presetId(feature: SourceFeature, location: LocationModel): string {
  const source: SourceInfo | null = getBestSourceForFeatureOrDefault(feature, location);
  return source !== null ? source.id : '';
}

/**
 * SearchActivityRepository.getLocationWithAppliedPreference (kt:101-186) — what a location added
 * from the SEARCH screen gets, as opposed to the plain preset the my-location FAB uses
 * (ManagementFragment.kt:241-243).
 *
 * `defaultForecastSource` is screen 3f's General row. "auto", or an id no longer in the catalogue,
 * falls through to applyDefaultPreset; anything else pins that source for the forecast and for each
 * feature it actually supports here, leaving the rest empty. It does NOT fall back per feature —
 * kt:116-181 assigns the chosen source or nothing.
 */
export function applyDefaultSourcePreference(
  location: LocationModel,
  defaultForecastSource: string
): void {
  const chosen: SourceInfo | null =
    defaultForecastSource === 'auto' ? null : getSource(defaultForecastSource);
  if (chosen === null) {
    applyDefaultPreset(location);
    return;
  }
  location.forecastSource = chosen.id;
  location.currentSource = pinned(chosen, SourceFeature.CURRENT, location);
  location.airQualitySource = pinned(chosen, SourceFeature.AIR_QUALITY, location);
  location.pollenSource = pinned(chosen, SourceFeature.POLLEN, location);
  location.minutelySource = pinned(chosen, SourceFeature.MINUTELY, location);
  location.alertSource = pinned(chosen, SourceFeature.ALERT, location);
  location.normalsSource = pinned(chosen, SourceFeature.NORMALS, location);
  /*
   * Untouched by the Kotlin's `copy(...)`, so it keeps whatever the preset left. The search flow
   * builds the location from a geocoding hit that already carries its own reverse-geocoding source.
   */
}

/** kt:116-181 — the chosen source if it declares AND supports the feature here, else empty. */
function pinned(
  source: SourceInfo,
  feature: SourceFeature,
  location: LocationModel
): string {
  return source.declares(feature) && source.supports(location, feature) ? source.id : '';
}

/* ------------------------------------------------------------- the location-search list ------- */

/**
 * getLocationSearchSources() (SourceManager.kt:364-366) — `sourceList.filterIsInstance<...>()`, so
 * the search screen's chooser shows them in the master list's order.
 *
 * Derived from SOURCES rather than hand-listed, which is what keeps the two in step: it yields
 * GeoNames, Nominatim, Open-Meteo, AccuWeather, China, confirmed against the running Android build.
 */
export const LOCATION_SEARCH_SOURCES: SourceInfo[] = SOURCES.filter(
  (source: SourceInfo) => source.isLocationSearchSource()
);

/** getLocationSearchSourceOrDefault (SourceManager.kt:371-372). */
export function locationSearchSourceOrDefault(id: string): SourceInfo {
  for (let i = 0; i < LOCATION_SEARCH_SOURCES.length; i++) {
    if (LOCATION_SEARCH_SOURCES[i].id === id) {
      return LOCATION_SEARCH_SOURCES[i];
    }
  }
  for (let i = 0; i < LOCATION_SEARCH_SOURCES.length; i++) {
    if (LOCATION_SEARCH_SOURCES[i].id === DEFAULT_LOCATION_SEARCH_SOURCE) {
      return LOCATION_SEARCH_SOURCES[i];
    }
  }
  return LOCATION_SEARCH_SOURCES[0];
}
