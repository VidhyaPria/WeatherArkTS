/*
 * Open-Meteo's weather models — OpenMeteoWeatherModel.kt:30-123.
 *
 * The enum's `id` is what goes on the wire as `&models=`; the display names are the parallel
 * `open_meteo_weather_models` string-array (arrays.xml:280-326), which is why the two lists have to
 * stay in the same ORDER — Android pairs them by index through `UnitUtils.getName`, so a name
 * inserted in one array without the other silently renames forty-four models.
 *
 * Transcribed rather than fetched: Android hard-codes the list too ("Up-to-date as of 2025-10-10",
 * kt:28), because Open-Meteo publishes no models endpoint.
 *
 * Two names are RE-WRITTEN after the array lookup (kt:105-114): the literal words "Best match" and
 * "Seamless" are replaced with their own translatable strings. In English both replacements are
 * identity, so the names below are already final — the substitution is kept in the comment rather
 * than the code because there is nothing for it to do in an English-only port.
 */

/** One entry of the catalogue. */
export class WeatherModelInfo {
  /** The `id` — what `&models=` carries. */
  readonly id: string;
  /** `open_meteo_weather_models[i]`. */
  readonly name: string;
  /**
   * `getDescription` (kt:116-122): the two combining models explain themselves, everything else
   * has none. Empty string rather than null, so the row can test `.length`.
   */
  readonly description: string;

  constructor(id: string, name: string, description: string = '') {
    this.id = id;
    this.name = name;
    this.description = description;
  }
}

/** strings.xml:768 — only `best_match` carries it. */
const BEST_MATCH_DESCRIPTION: string = 'Combines the best weather models for this location';
/** strings.xml:770 — every id ending `_seamless` carries it (kt:118-119). */
const SEAMLESS_DESCRIPTION: string =
  'Combines all weather models from this provider into a seamless prediction';

/** The id Android falls back to when a location has no stored selection (kt:772). */
export const MODEL_BEST_MATCH: string = 'best_match';

/**
 * The catalogue, in the enum's declaration order — which is the order the dialog lists them in,
 * because Android's `mutableStateListOf` is built from `OpenMeteoWeatherModel.entries` (kt:790-800)
 * and never sorted. (The SUMMARY line on the row IS sorted, by collated name; see `modelsSummary`.)
 */
export const WEATHER_MODELS: WeatherModelInfo[] = [
  new WeatherModelInfo('best_match', 'Best match', BEST_MATCH_DESCRIPTION),

  new WeatherModelInfo('ecmwf_ifs', 'ECMWF IFS HRES 9 km'),
  new WeatherModelInfo('ecmwf_ifs025', 'ECMWF IFS 0.25\u00B0'),
  new WeatherModelInfo('ecmwf_aifs025_single', 'ECMWF AIFS 0.25\u00B0 Single'),
  new WeatherModelInfo('cma_grapes_global', 'CMA GRAPES Global'),
  new WeatherModelInfo('bom_access_global', 'BOM ACCESS Global'),

  new WeatherModelInfo('gfs_seamless', 'NCEP GFS Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('gfs_global', 'NCEP GFS Global 0.11\u00B0 / 0.25\u00B0'),
  new WeatherModelInfo('gfs_hrrr', 'NCEP HRRR U.S. Conus'),
  new WeatherModelInfo('ncep_nbm_conus', 'NCEP NBM U.S. Conus'),
  new WeatherModelInfo('ncep_nam_conus', 'NCEP NAM U.S. Conus'),
  new WeatherModelInfo('gfs_graphcast025', 'GFS GraphCast'),

  new WeatherModelInfo('jma_seamless', 'JMA Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('jma_msm', 'JMA MSM'),
  new WeatherModelInfo('jma_gsm', 'JMA GSM'),

  new WeatherModelInfo('kma_seamless', 'KMA Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('kma_ldps', 'KMA LDPS'),
  new WeatherModelInfo('kma_gdps', 'KMA GDPS'),

  new WeatherModelInfo('icon_seamless', 'DWD ICON Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('icon_global', 'DWD ICON Global'),
  new WeatherModelInfo('icon_eu', 'DWD ICON EU'),
  new WeatherModelInfo('icon_d2', 'DWD ICON D2'),

  new WeatherModelInfo('gem_seamless', 'GEM Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('gem_global', 'GEM Global'),
  new WeatherModelInfo('gem_regional', 'GEM Regional'),
  new WeatherModelInfo('gem_hrdps_continental', 'GEM HRDPS Continental'),

  new WeatherModelInfo('meteofrance_seamless', 'M\u00E9t\u00E9o-France Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('meteofrance_arpege_world', 'M\u00E9t\u00E9o-France ARPEGE World'),
  new WeatherModelInfo('meteofrance_arpege_europe', 'M\u00E9t\u00E9o-France ARPEGE Europe'),
  new WeatherModelInfo('meteofrance_arome_france', 'M\u00E9t\u00E9o-France AROME France'),
  new WeatherModelInfo('meteofrance_arome_france_hd', 'M\u00E9t\u00E9o-France AROME France HD'),

  new WeatherModelInfo('italia_meteo_arpae_icon_2i', 'ItaliaMeteo ARPAE ICON 2I'),

  new WeatherModelInfo('metno_seamless', 'MET Norway Nordic (with ECMWF) Seamless',
    SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('metno_nordic', 'MET Norway Nordic'),

  new WeatherModelInfo('knmi_seamless', 'KNMI (with ECMWF) Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('knmi_harmonie_arome_europe', 'KNMI HARMONIE-AROME Europe'),
  new WeatherModelInfo('knmi_harmonie_arome_netherlands', 'KNMI HARMONIE-AROME Netherlands'),

  new WeatherModelInfo('dmi_seamless', 'DMI (with ECMWF) Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('dmi_harmonie_arome_europe', 'DMI HARMONIE-AROME Europe'),

  new WeatherModelInfo('ukmo_seamless', 'UK Met Office Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('ukmo_global_deterministic_10km', 'UK Met Office Global 10 km'),
  new WeatherModelInfo('ukmo_uk_deterministic_2km', 'UK Met Office UK 2 km'),

  new WeatherModelInfo('meteoswiss_icon_seamless', 'MeteoSwiss ICON Seamless', SEAMLESS_DESCRIPTION),
  new WeatherModelInfo('meteoswiss_icon_ch1', 'MeteoSwiss ICON CH1'),
  new WeatherModelInfo('meteoswiss_icon_ch2', 'MeteoSwiss ICON CH2')
];

/** `OpenMeteoWeatherModel.getInstance` (kt:95-99) — null for an id this build does not know. */
export function findWeatherModel(id: string): WeatherModelInfo | null {
  for (let i = 0; i < WEATHER_MODELS.length; i++) {
    if (WEATHER_MODELS[i].id === id) {
      return WEATHER_MODELS[i];
    }
  }
  return null;
}

/**
 * `getWeatherModels` (kt:764-773) — the stored list, dropping ids this build does not know, and
 * falling back to `best_match` alone when the result would be empty.
 *
 * The fallback covers three cases with one rule, as the Kotlin's `?:` does: never configured, and
 * a stored list whose every id has since been removed from the catalogue.
 */
export function selectedWeatherModels(stored: string): string[] {
  const out: string[] = [];
  const parts: string[] = stored.split(',');
  for (let i = 0; i < parts.length; i++) {
    const id: string = parts[i].trim();
    if (id.length > 0 && findWeatherModel(id) !== null) {
      out.push(id);
    }
  }
  return out.length > 0 ? out : [MODEL_BEST_MATCH];
}

/**
 * The row's summary — the enabled models' names, collated, joined by `locale_separator`.
 *
 * kt:805-815 sorts with a `Collator` "because there are now a lot of sources". `localeCompare` is
 * the ArkTS equivalent; on the English locale both order the ASCII names identically, and it is
 * the accented "Météo-France" entries that make the difference visible at all.
 */
export function modelsSummary(stored: string): string {
  const ids: string[] = selectedWeatherModels(stored);
  const names: string[] = [];
  for (let i = 0; i < ids.length; i++) {
    const model: WeatherModelInfo | null = findWeatherModel(ids[i]);
    if (model !== null) {
      names.push(model.name);
    }
  }
  names.sort((a: string, b: string): number => a.localeCompare(b));
  // `locale_separator` is ", " in English.
  return names.join(', ');
}
