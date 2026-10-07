/*
 * The on-device weather cache.
 *
 * Android keeps every location's last forecast in its SQLDelight database, so MainActivity reads
 * a location out of storage BEFORE any network call and the screen is populated from the first
 * frame; a refresh then overwrites it, and a refresh that fails leaves the stored copy on screen
 * (RefreshHelper only replaces `location.weather` on success). CLAUDE.md maps SQLDelight to
 * relationalStore, which is what this uses.
 *
 * The port had no persistence at all, so a cold start with no network showed a completely empty
 * page — no header, no cards, nothing but the city name. That is the gap this closes.
 *
 * One table, one row per location, the weather held as JSON in a TEXT column. Breezy normalises
 * across a dozen tables because it has to query them (widgets, notifications, per-day lookups);
 * this port only ever reads a whole forecast back for one location, so a document per row is the
 * honest shape and it keeps the NDK port's job to "parse the same JSON".
 */

import { relationalStore } from '@kit.ArkData';
import { Weather } from '../model/Weather';
import { deserializeWeather, serializeWeather } from './WeatherJson';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'weather.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS weather_cache (' +
  'location_id TEXT PRIMARY KEY, ' +
  'payload TEXT NOT NULL, ' +
  'utc_offset_seconds INTEGER NOT NULL, ' +
  'daylight INTEGER NOT NULL, ' +
  'stored_at INTEGER NOT NULL)';

/** What one cached row restores: the forecast plus the two location fields refreshed with it. */
export class CachedWeather {
  readonly weather: Weather;
  readonly utcOffsetSeconds: number;
  readonly daylight: boolean;

  constructor(weather: Weather, utcOffsetSeconds: number, daylight: boolean) {
    this.weather = weather;
    this.utcOffsetSeconds = utcOffsetSeconds;
    this.daylight = daylight;
  }
}

let store: relationalStore.RdbStore | null = null;

/** Opens the store once. A failure is not fatal — the app just runs without a cache. */
async function open(context: Context): Promise<relationalStore.RdbStore | null> {
  if (store !== null) {
    return store;
  }
  try {
    const opened: relationalStore.RdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
    await opened.executeSql(CREATE_TABLE);
    store = opened;
    return store;
  } catch (error) {
    console.warn('Weather cache unavailable: ' + (error as Error).message);
    return null;
  }
}

export async function saveWeather(
  context: Context,
  locationId: string,
  weather: Weather,
  utcOffsetSeconds: number,
  daylight: boolean
): Promise<void> {
  const db: relationalStore.RdbStore | null = await open(context);
  if (db === null) {
    return;
  }
  try {
    const row: relationalStore.ValuesBucket = {
      'location_id': locationId,
      'payload': serializeWeather(weather),
      'utc_offset_seconds': utcOffsetSeconds,
      'daylight': daylight ? 1 : 0,
      'stored_at': new Date().getTime()
    };
    // REPLACE so a second refresh of the same location overwrites rather than conflicts.
    await db.insert('weather_cache', row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  } catch (error) {
    console.warn('Weather cache write failed: ' + (error as Error).message);
  }
}

export async function loadWeather(context: Context, locationId: string): Promise<CachedWeather | null> {
  const db: relationalStore.RdbStore | null = await open(context);
  if (db === null) {
    return null;
  }
  try {
    const predicates = new relationalStore.RdbPredicates('weather_cache');
    predicates.equalTo('location_id', locationId);
    const result: relationalStore.ResultSet = await db.query(predicates,
      ['payload', 'utc_offset_seconds', 'daylight']);
    let cached: CachedWeather | null = null;
    if (result.goToFirstRow()) {
      const payload: string = result.getString(result.getColumnIndex('payload'));
      const offset: number = result.getLong(result.getColumnIndex('utc_offset_seconds'));
      const daylight: number = result.getLong(result.getColumnIndex('daylight'));
      const weather: Weather | null = deserializeWeather(payload, offset);
      if (weather !== null) {
        cached = new CachedWeather(weather, offset, daylight !== 0);
      }
    }
    result.close();
    return cached;
  } catch (error) {
    console.warn('Weather cache read failed: ' + (error as Error).message);
    return null;
  }
}
