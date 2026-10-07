/*
 * Every configurable source's own settings — the data behind screen 3f (Weather sources).
 *
 * On Android each source class answers `getPreferences(context)` with its own list, and the screen
 * just renders whatever comes back (WeatherSourcesSettingsScreen.kt:196-233). There are no source
 * CLIENTS in this port, so there is nothing to ask; the lists are transcribed here instead, one
 * entry per `getPreferences` override in `src/main` + `src_nonfreenet` (the reference build is not
 * the freenet flavour).
 *
 * Only two kinds exist, and both already have a dialog from screen 3e:
 *
 *   TEXT   EditTextPreference. An API key, or an instance URL.
 *   LIST   ListPreference. Only AccuWeather has any.
 *
 * ORDER IS DATA, NOT A SORT. The Kotlin sorts the sections with
 * `Collator.getInstance(context.currentLocale)` (kt:187-190) — full ICU collation, which puts
 * "Mali-Météo" before "MET Éireann" before "Met Office" before "Météo Bénin". ArkTS could reach
 * `intl.Collator`, but the NDK port has no ICU at all, and the two ports must agree. So the order
 * below was read off the reference device (ref_screen3f_sources_top.png through the bottom of the
 * list) and is stored, not computed. 40 sections, AccuWeather through SSMS.
 *
 * Baidu IP is absent on purpose: kt:185 excludes `LocationSource`, which sends it to screen 3e.
 * GeoNames and Nominatim are geocoders rather than location sources, so they DO appear here.
 */

const API_KEY: string = 'API key'; // strings.xml:714 `settings_source_api_key`
const INSTANCE: string = 'Instance'; // :735 `settings_source_instance`
/** :713 — what an empty API key reads as. An empty INSTANCE shows its default URL instead. */
export const DEFAULT_UNCHANGED: string = 'Default (unchanged)';
/** :736 — EditTextPreference.URL_REGEX's error, shown under an instance field that fails it. */
export const INSTANCE_INVALID: string = 'Must be an https URL ending with a /';

export enum SourcePrefKind {
  TEXT = 0,
  LIST = 1
}

export class SourcePrefOption {
  readonly value: string;
  readonly name: string;

  constructor(value: string, name: string) {
    this.value = value;
    this.name = name;
  }
}

export interface SourcePrefSpec {
  /**
   * The key inside the source's own config. Android gives each source a `SourceConfigStore(id)`, so
   * these repeat across sources ("apikey" many times over); this port has one bag, so the storage
   * key is `source_<sourceId>_<key>` — the convention screen 3e already set.
   */
  key: string;
  title: string;
  kind: SourcePrefKind;
  /** LIST only, in the Kotlin array's order. */
  options?: SourcePrefOption[];
  /** LIST: the selected key on a fresh install. TEXT: always empty. */
  fallback?: string;
  /**
   * TEXT only. An instance row's placeholder is the source's baseUrl, and its summary falls back to
   * the same URL rather than to "Default (unchanged)" (ClimWebService.kt:376-382). An API-key row
   * has neither.
   */
  placeholder?: string;
  /** TEXT only — URL_REGEX applies to instance rows, so a bad value is refused (kt:383). */
  url?: boolean;
}

export interface SourcePrefSection {
  /** Keys into SourceCatalogue, which already carries the display name shown as the header. */
  sourceId: string;
  prefs: SourcePrefSpec[];
}

/** One EditTextPreference for an API key — by far the commonest shape. */
function apiKey(): SourcePrefSpec {
  return { key: 'apikey', title: API_KEY, kind: SourcePrefKind.TEXT };
}

/** ClimWebService.kt:372-391, and the same shape in Bright Sky, FPAS, KNMI, Nominatim, Pirate. */
function instance(baseUrl: string): SourcePrefSpec {
  return { key: 'instance', title: INSTANCE, kind: SourcePrefKind.TEXT, placeholder: baseUrl, url: true };
}

/** A section whose whole content is one API key. */
function apiKeySource(sourceId: string): SourcePrefSection {
  return { sourceId: sourceId, prefs: [apiKey()] };
}

/** A ClimWeb agency: one instance row, placeholder = its baseUrl. */
function climWeb(sourceId: string, baseUrl: string): SourcePrefSection {
  return { sourceId: sourceId, prefs: [instance(baseUrl)] };
}

/** AccuService.kt:894-936 — the only source with list preferences. */
const ACCU_PORTAL: SourcePrefOption[] = [
  new SourcePrefOption('developer', 'Developer'), // arrays.xml:240-247, strings.xml:412-413
  new SourcePrefOption('enterprise', 'Enterprise')
];
const ACCU_DAYS: SourcePrefOption[] = [
  new SourcePrefOption('1', '1 day'), // arrays.xml:249-260, strings.xml:415-418
  new SourcePrefOption('5', '5 days'),
  new SourcePrefOption('10', '10 days'),
  new SourcePrefOption('15', '15 days')
];
const ACCU_HOURS: SourcePrefOption[] = [
  new SourcePrefOption('1', '1 hour'), // arrays.xml:262-277, strings.xml:420-425
  new SourcePrefOption('12', '12 hours'),
  new SourcePrefOption('24', '24 hours'),
  new SourcePrefOption('72', '72 hours'),
  new SourcePrefOption('120', '120 hours'),
  new SourcePrefOption('240', '240 hours')
];

export const SOURCE_PREFERENCES: SourcePrefSection[] = [
  {
    sourceId: 'accu',
    prefs: [
      // The defaults are the reference device's: Enterprise / 15 days / 240 hours.
      { key: 'portal', title: 'Portal', kind: SourcePrefKind.LIST, options: ACCU_PORTAL, fallback: 'enterprise' },
      apiKey(),
      { key: 'days', title: 'Days', kind: SourcePrefKind.LIST, options: ACCU_DAYS, fallback: '15' },
      { key: 'hours', title: 'Hours', kind: SourcePrefKind.LIST, options: ACCU_HOURS, fallback: '240' }
    ]
  },
  apiKeySource('aemet'), // AemetService.kt:687
  climWeb('anambf', 'https://www.meteoburkina.bf/'),
  climWeb('anamet', 'https://www.anamet-togo.com/'),
  apiKeySource('atmoaura'), // the four regional Atmo agencies share AtmoService.kt:154-169
  apiKeySource('atmofrance'), // AtmoFranceService.kt:226
  apiKeySource('atmograndest'),
  apiKeySource('atmohdf'),
  apiKeySource('atmosud'),
  apiKeySource('bmkg'), // BmkgService.kt:573
  { sourceId: 'brightsky', prefs: [instance('https://api.brightsky.dev/')] }, // BrightSkyService.kt:350
  apiKeySource('cwa'), // CwaService.kt:998
  climWeb('dccms', 'https://www.metmalawi.gov.mw/'),
  climWeb('dmnne', 'https://www.niger-meteo.ne/'),
  climWeb('dwrgm', 'https://meteogambia.org/'),
  apiKeySource('eccc'), // EcccService.kt:404
  climWeb('ethiomet', 'https://www.ethiomet.gov.et/'),
  { sourceId: 'fpas', prefs: [instance('https://alerts.kde.org/')] }, // FpasService.kt:166
  apiKeySource('geonames'), // GeoNamesService.kt:134
  climWeb('gmet', 'https://www.meteo.gov.gh/'),
  climWeb('igebu', 'https://www.igebu.bi/'),
  apiKeySource('infoplaza'), // InfoplazaService.kt:346
  climWeb('inmgb', 'https://www.meteoguinebissau.org/'),
  // KnmiService.kt:601-627. Its placeholder is debugMode-conditional; this is the release value.
  { sourceId: 'knmi', prefs: [instance('https://api.app.knmi.cloud/')] },
  climWeb('malimeteo', 'https://malimeteo.ml/'),
  apiKeySource('metie'), // MetIeService.kt:435
  apiKeySource('metoffice'), // MetOfficeService.kt:230
  climWeb('meteobenin', 'https://www.meteobenin.bj/'),
  climWeb('meteotchad', 'https://www.meteotchad.org/'),
  apiKeySource('mf'), // MfService.kt:1102
  climWeb('mettelsat', 'https://www.meteordcongo.cd/'),
  climWeb('msdzw', 'https://www.weatherzw.org.zw/'),
  { sourceId: 'nominatim', prefs: [instance('https://nominatim.openstreetmap.org/')] },
  {
    sourceId: 'openmeteo', // OpenMeteoService.kt:703-748 — three instances, one per API host
    prefs: [
      { key: 'instance_forecast', title: 'Forecast instance', kind: SourcePrefKind.TEXT, placeholder: 'https://api.open-meteo.com/', url: true },
      { key: 'instance_air_quality', title: 'Air quality instance', kind: SourcePrefKind.TEXT, placeholder: 'https://air-quality-api.open-meteo.com/', url: true },
      { key: 'instance_geocoding', title: 'Geocoding instance', kind: SourcePrefKind.TEXT, placeholder: 'https://geocoding-api.open-meteo.com/', url: true }
    ]
  },
  apiKeySource('openweather'), // OpenWeatherService.kt:299
  {
    sourceId: 'pirateweather', // PirateWeatherService.kt:429-475 — instance THEN key
    prefs: [instance('https://api.pirateweather.net/'), apiKey()]
  },
  apiKeySource('polleninfo'), // PollenInfoService.kt:147
  climWeb('smasc', 'https://www.meteo.sc/'),
  climWeb('smasu', 'https://meteosudan.sd/'),
  climWeb('ssms', 'https://meteosouthsudan.com.ss/')
];

/** The one preferences key a value is stored under. See SourcePrefSpec.key. */
export function sourcePrefKey(sourceId: string, key: string): string {
  return 'source_' + sourceId + '_' + key;
}
