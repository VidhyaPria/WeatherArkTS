/*
 * The saved-location list, persisted.
 *
 * Breezy keeps its locations in the same SQLDelight database as the weather, and the list screen
 * (ManagementFragment) adds to, deletes from and reorders that table — `MainActivityViewModel`
 * only ever reads it back. CLAUDE.md maps SQLDelight to relationalStore, so this is a second table
 * in the store WeatherCache already opens.
 *
 * Until now the list was three hardcoded cities in `LocationStore.buildLocations()`, which was
 * honest while there was no way to change it. A location list screen that cannot outlive a restart
 * would not be a port of anything, so the table comes first and the screen is built on it.
 *
 * `sort_order` is stored rather than derived: Android's list order is user-controlled (drag to
 * reorder), it is what the main screen's Swiper pages through, and it has to survive a restart.
 * The row keeps only what Breezy's `Location` carries and the refresh settles — no weather; that
 * stays in `weather_cache`, keyed by the same `formattedId`.
 */

import { relationalStore } from '@kit.ArkData';
import { LocationModel } from '../model/Weather';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'weather.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS locations (' +
  'formatted_id TEXT PRIMARY KEY, ' +
  'city TEXT NOT NULL, ' +
  'region TEXT NOT NULL, ' +
  'latitude REAL NOT NULL, ' +
  'longitude REAL NOT NULL, ' +
  'time_zone TEXT NOT NULL, ' +
  'utc_offset_seconds INTEGER NOT NULL, ' +
  'is_current_position INTEGER NOT NULL, ' +
  'sort_order INTEGER NOT NULL)';

/**
 * Columns added after the table shipped, as `ALTER TABLE` statements.
 *
 * `CREATE TABLE IF NOT EXISTS` does nothing to a table that already exists, so a device that has
 * run an earlier build keeps the old six-column schema and every read of a new column fails. Each
 * statement is run on its own and its "duplicate column name" error swallowed, which is the
 * cheapest migration that is correct both on a fresh install and on an upgraded one.
 *
 * The country code and admin2 feed the source catalogue's compatibility rules; the eight source
 * columns are the per-feature selection the weather-sources dialog writes.
 */
const MIGRATIONS: string[] = [
  "ALTER TABLE locations ADD COLUMN country_code TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN admin2 TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN forecast_source TEXT NOT NULL DEFAULT 'openmeteo'",
  "ALTER TABLE locations ADD COLUMN current_source TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN air_quality_source TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN pollen_source TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN minutely_source TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN alert_source TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN normals_source TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE locations ADD COLUMN reverse_geocoding_source TEXT NOT NULL DEFAULT ''",
  // Location.district — the sub-locality `getPlace` prints after the city.
  "ALTER TABLE locations ADD COLUMN district TEXT NOT NULL DEFAULT ''",
  /*
   * Location.needsGeocodeRefresh, DEFAULT 1 on purpose.
   *
   * Every row that already exists when this column is added was geocoded before `district` did,
   * so it has a city and no district and the "city is empty" guard would never ask again. The
   * default marks exactly those rows; anything written afterwards carries the model's own value,
   * which a fresh geocode sets to 0.
   */
  'ALTER TABLE locations ADD COLUMN needs_geocode_refresh INTEGER NOT NULL DEFAULT 1',
  // Location.customName — the name typed over this location's own, written by the per-location
  // preferences dialog. '' is Android's null: no override.
  "ALTER TABLE locations ADD COLUMN custom_name TEXT NOT NULL DEFAULT ''",
  // parameters["openmeteo"]["weatherModels"] — a comma-joined model id list. '' is the default,
  // which the fetch turns into `best_match`.
  "ALTER TABLE locations ADD COLUMN weather_models TEXT NOT NULL DEFAULT ''"
];

let store: relationalStore.RdbStore | null = null;

/** Opens the store once. A failure is not fatal — the app falls back to the default list. */
async function open(context: Context): Promise<relationalStore.RdbStore | null> {
  if (store !== null) {
    return store;
  }
  try {
    const opened: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await opened.executeSql(CREATE_TABLE);
    for (let i = 0; i < MIGRATIONS.length; i++) {
      try {
        await opened.executeSql(MIGRATIONS[i]);
      } catch (error) {
        // Already applied on this device. Any other cause shows up as a failed read below.
      }
    }
    store = opened;
    return store;
  } catch (error) {
    console.warn('Location table unavailable: ' + (error as Error).message);
    return null;
  }
}

function toRow(location: LocationModel, order: number): relationalStore.ValuesBucket {
  return {
    'formatted_id': location.formattedId,
    'city': location.city,
    'district': location.district,
    'needs_geocode_refresh': location.needsGeocodeRefresh ? 1 : 0,
    'region': location.region,
    'latitude': location.latitude,
    'longitude': location.longitude,
    'time_zone': location.timeZone,
    'utc_offset_seconds': location.utcOffsetSeconds,
    'is_current_position': location.isCurrentPosition ? 1 : 0,
    'sort_order': order,
    'country_code': location.countryCode,
    'admin2': location.admin2,
    'custom_name': location.customName,
    'weather_models': location.weatherModels,
    'forecast_source': location.forecastSource,
    'current_source': location.currentSource,
    'air_quality_source': location.airQualitySource,
    'pollen_source': location.pollenSource,
    'minutely_source': location.minutelySource,
    'alert_source': location.alertSource,
    'normals_source': location.normalsSource,
    'reverse_geocoding_source': location.reverseGeocodingSource
  };
}

/**
 * A column that may predate the migration above.
 *
 * `getColumnIndex` answers -1 for a name the result set does not carry, and `getString(-1)` throws.
 * Reading through this keeps a partially-migrated database readable instead of emptying the list.
 */
function optionalString(
  result: relationalStore.ResultSet,
  column: string,
  fallback: string
): string {
  try {
    const index: number = result.getColumnIndex(column);
    if (index < 0) {
      return fallback;
    }
    const value: string = result.getString(index);
    return value.length > 0 ? value : fallback;
  } catch (error) {
    return fallback;
  }
}

function fromRow(result: relationalStore.ResultSet): LocationModel {
  const location = new LocationModel();
  location.formattedId = result.getString(result.getColumnIndex('formatted_id'));
  location.city = result.getString(result.getColumnIndex('city'));
  location.district = result.getString(result.getColumnIndex('district'));
  location.needsGeocodeRefresh =
    result.getLong(result.getColumnIndex('needs_geocode_refresh')) !== 0;
  location.region = result.getString(result.getColumnIndex('region'));
  location.latitude = result.getDouble(result.getColumnIndex('latitude'));
  location.longitude = result.getDouble(result.getColumnIndex('longitude'));
  location.timeZone = result.getString(result.getColumnIndex('time_zone'));
  location.utcOffsetSeconds = result.getLong(result.getColumnIndex('utc_offset_seconds'));
  location.isCurrentPosition = result.getLong(result.getColumnIndex('is_current_position')) !== 0;
  location.countryCode = optionalString(result, 'country_code', '');
  location.admin2 = optionalString(result, 'admin2', '');
  location.customName = optionalString(result, 'custom_name', '');
  location.weatherModels = optionalString(result, 'weather_models', '');
  // The forecast source is the one that always has a value — it is part of a location's identity
  // (locationExists), so an empty one would make two saved cities collide.
  location.forecastSource = optionalString(result, 'forecast_source', 'openmeteo');
  location.currentSource = optionalString(result, 'current_source', '');
  location.airQualitySource = optionalString(result, 'air_quality_source', '');
  location.pollenSource = optionalString(result, 'pollen_source', '');
  location.minutelySource = optionalString(result, 'minutely_source', '');
  location.alertSource = optionalString(result, 'alert_source', '');
  location.normalsSource = optionalString(result, 'normals_source', '');
  location.reverseGeocodingSource = optionalString(result, 'reverse_geocoding_source', '');
  // Neither of these is stored: `daylight` is derived from the day's sun times and `weather` is
  // the cache's business, so both start where a never-refreshed location starts.
  location.daylight = true;
  location.weather = null;
  return location;
}

/** Every saved location in the user's order, or an empty list when there is nothing stored yet. */
export async function loadLocations(context: Context): Promise<LocationModel[]> {
  const db: relationalStore.RdbStore | null = await open(context);
  if (db === null) {
    return [];
  }
  try {
    const predicates = new relationalStore.RdbPredicates('locations');
    predicates.orderByAsc('sort_order');
    const result: relationalStore.ResultSet = await db.query(predicates);
    const locations: LocationModel[] = [];
    while (result.goToNextRow()) {
      locations.push(fromRow(result));
    }
    result.close();
    return locations;
  } catch (error) {
    console.warn('Location read failed: ' + (error as Error).message);
    return [];
  }
}

/**
 * Writes the whole list back in its current order.
 *
 * A whole-list write rather than per-row updates because every mutation this screen performs —
 * add, delete, reorder — changes `sort_order` for an arbitrary number of rows, and the list is a
 * handful of entries. One transaction is simpler than three code paths and cannot leave a gap in
 * the ordering.
 */
export async function saveLocations(context: Context, locations: LocationModel[]): Promise<void> {
  const db: relationalStore.RdbStore | null = await open(context);
  if (db === null) {
    return;
  }
  try {
    await db.executeSql('DELETE FROM locations');
    for (let i = 0; i < locations.length; i++) {
      await db.insert('locations', toRow(locations[i], i),
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  } catch (error) {
    console.warn('Location write failed: ' + (error as Error).message);
  }
}

/** Drops a deleted location's cached forecast, so a re-added city does not show stale weather. */
export async function deleteCachedWeather(context: Context, formattedId: string): Promise<void> {
  const db: relationalStore.RdbStore | null = await open(context);
  if (db === null) {
    return;
  }
  try {
    const predicates = new relationalStore.RdbPredicates('weather_cache');
    predicates.equalTo('location_id', formattedId);
    await db.delete(predicates);
  } catch (error) {
    console.warn('Cached weather delete failed: ' + (error as Error).message);
  }
}
