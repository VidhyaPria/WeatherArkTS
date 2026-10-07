/*
 * Main screen state, mirroring MainActivityViewModel's surface for the parts step 1 needs.
 *
 * Source: ui/main/MainActivityViewModel.kt (currentLocation / indicator / loading /
 * offsetLocation / updateWithUpdatingChecking) and HomeFragment.kt's use of them.
 */

import { Alert, LocationModel, Weather } from '../model/Weather';
import { buildCurrentPositionLocation, buildLocations } from '../data/LocationStore';
import {
  distanceMetres,
  PositionAddress,
  PositionError,
  PositionResult,
  requestCurrentPosition,
  REVERSE_GEOCODING_DISTANCE_LIMIT,
  reverseGeocode
} from '../data/CurrentPosition';
import { deleteCachedWeather, loadLocations, saveLocations } from '../data/LocationTable';
import { Coordinates, fetchWeather, RefreshResult } from '../data/WeatherRepository';
import { fetchAlerts } from '../data/fmi/FmiAlerts';
import { selectedWeatherModels } from '../model/OpenMeteoModels';
import { COLON_SEPARATOR, DOT_SEPARATOR, formatTemperatureNarrow } from '../common/Formatter';
import { localHours } from '../common/LocalTime';
import { CachedWeather, loadWeather, saveWeather } from '../data/WeatherCache';
import { fetchLocationSearch } from '../data/openmeteo/OpenMeteoApi';
import { OpenMeteoLocationResult } from '../data/openmeteo/OpenMeteoJson';
import { AppSettings, updateIntervalMs } from '../data/SettingsStore';

/** Nulls and empties are the same thing to the geocoding fields below. */
function optional(value: string | null | undefined): string {
  return value === null || value === undefined ? '' : value;
}

/**
 * The same forecast with an alert list attached, as a NEW object.
 *
 * `Weather` is a plain class, so mutating a field on one that has already been assigned to the
 * @Trace'd `LocationModel.weather` is invisible to the framework. Replacing the reference is what
 * makes the change observable — see the call site.
 *
 * SHALLOW by design: every array is carried across by reference, so this costs one object and does
 * not put the ~400-entry hourly graph under observation.
 *
 * If a field is ever added to `Weather`, it MUST be added here too — a missing line would silently
 * drop that field the moment an alert lands.
 */
function withAlerts(source: Weather, alertList: Alert[]): Weather {
  const copy = new Weather();
  copy.refreshTime = source.refreshTime;
  copy.current = source.current;
  copy.dailyForecast = source.dailyForecast;
  copy.hourlyForecast = source.hourlyForecast;
  copy.nextHourlyForecast = source.nextHourlyForecast;
  copy.minutelyForecast = source.minutelyForecast;
  copy.normals = source.normals;
  copy.todayIndex = source.todayIndex;
  copy.alertList = alertList;
  return copy;
}

/**
 * What `addLocation` did, because the two outcomes are user-visible and differently reported.
 *
 * MainActivityViewModel.addLocation (kt:526-531) checks `locationExists` first and shows
 * `location_message_already_exists` instead of adding; only the other branch reaches
 * `location_message_added`. The port used to swallow the duplicate case and return the existing
 * index, so searching for a city that was already saved looked like a successful add.
 */
export class AddLocationResult {
  /** Where the location sits now — its existing slot on a duplicate, the new last slot otherwise. */
  readonly index: number;
  /** False when the list already contained it and nothing was written. */
  readonly added: boolean;

  constructor(index: number, added: boolean) {
    this.index = index;
    this.added = added;
  }
}

/** MainActivityViewModel.kt:733 — `10.seconds.inWholeMilliseconds`. */
const DELAY_BEFORE_NEXT_MANUAL_REFRESH: number = 10 * 1000;

/** Mirrors MainActivityViewModel.indicator (index within total). */
export class LocationIndicator {
  readonly index: number;
  readonly total: number;

  constructor(index: number, total: number) {
    this.index = index;
    this.total = total;
  }
}

/**
 * RefreshErrorType.getRefreshErrorType (RefreshErrorType.kt:225-232) — the exception is mapped to
 * one short user-facing message. Only the cases Open-Meteo can produce are ported: an unresolved
 * host is NETWORK_UNAVAILABLE (kt:227 maps UnknownHostException there, with the comment that it
 * "most of the time" means the network), a timeout is SERVER_TIMEOUT.
 */
function refreshErrorMessage(message: string): string {
  const lower: string = message.toLowerCase();
  if (lower.includes('resolve') || lower.includes('host') || lower.includes('unreachable') ||
    lower.includes('network')) {
    return 'Network unavailable'; // strings.xml message_network_unavailable
  }
  if (lower.includes('timeout') || lower.includes('timed out')) {
    return 'Request timed out'; // strings.xml message_server_timeout
  }
  return 'Server unavailable'; // strings.xml message_server_unavailable_title
}

/**
 * The one instance both screens share.
 *
 * On Android `MainActivityViewModel` is scoped to MainActivity, and HomeFragment and
 * ManagementFragment are two views onto it — the list screen mutates the very list the home
 * screen's pager reads. The port's screens are separate pages rather than fragments, so the
 * sharing has to be explicit; a per-page instance would mean the list screen editing a copy.
 */
/**
 * Bumped by every change the location list screen makes.
 *
 * The list is a plain array on a plain object, so ArkUI V2 has no dependency edge to it — a screen
 * that adds, deletes or reorders a location changes nothing the framework can observe.
 *
 * This counter is a CHANGE STAMP, not a render dependency. Reading `version` from a helper method
 * called out of `build()` does NOT register a dependency the way reading it in `build()` itself
 * would: after a reorder the counter advanced and the list screen never rebuilt, so the rows stayed
 * in their old order. Screens rebuild their own state explicitly instead (LocationList.refreshRows);
 * what this is still good for is answering "has the list changed since I last looked".
 */
@ObservedV2
export class LocationRevision {
  static readonly instance: LocationRevision = new LocationRevision();
  @Trace version: number = 0;
}

let sharedViewModel: MainViewModel | null = null;

export function getMainViewModel(): MainViewModel {
  if (sharedViewModel === null) {
    sharedViewModel = new MainViewModel();
  }
  return sharedViewModel;
}

export class MainViewModel {
  private locations: LocationModel[] = [];
  private index: number = 0;
  /** Needed to open the cache; supplied by the screen once it has a UIContext. */
  private context: Context | null = null;

  /**
   * Restores every location's stored forecast, so the first frame after launch already has data —
   * MainActivity reads locations (weather included) out of the database before any network call.
   * Returns true when at least one location was restored, so the caller can re-render.
   */
  async loadCached(context: Context): Promise<boolean> {
    this.context = context;
    /*
     * The saved list comes out of the database first — it is what the location screen writes to,
     * so it is the authority, and `buildLocations()` is now only the seed for a fresh install.
     * Android does the same: MainActivityViewModel reads the location table, and only a first run
     * has nothing in it.
     */
    const stored: LocationModel[] = await loadLocations(context);
    if (stored.length > 0) {
      /*
       * MERGED into the existing instances, not assigned over them.
       *
       * `this.locations = stored` looks harmless and was not: the Swiper's ForEach is keyed on
       * `formattedId`, and a stored row has the SAME id as the seed it replaces. ForEach therefore
       * saw unchanged keys, kept the children it already had, and those children went on holding
       * the ORIGINAL LocationModel objects — the ones this line had just thrown away. The weather
       * loaded a moment later was written to the new objects, which nothing was rendering, so
       * Berlin and Tokyo drew an empty page for the whole session while their rows in the location
       * list showed a forecast.
       *
       * Copying field-by-field keeps object identity, which is what both the ForEach key and the
       * @ObservedV2 @Trace on `weather` depend on.
       */
      const merged: LocationModel[] = [];
      for (let i = 0; i < stored.length; i++) {
        const row: LocationModel = stored[i];
        const existingIndex: number = this.indexOf(row.formattedId);
        if (existingIndex < 0) {
          merged.push(row);
          continue;
        }
        const kept: LocationModel = this.locations[existingIndex];
        kept.city = row.city;
        kept.district = row.district;
        kept.needsGeocodeRefresh = row.needsGeocodeRefresh;
        kept.latitude = row.latitude;
        kept.longitude = row.longitude;
        kept.isCurrentPosition = row.isCurrentPosition;
        kept.timeZone = row.timeZone;
        kept.region = row.region;
        kept.countryCode = row.countryCode;
        kept.admin2 = row.admin2;
        kept.utcOffsetSeconds = row.utcOffsetSeconds;
        kept.forecastSource = row.forecastSource;
        kept.currentSource = row.currentSource;
        kept.airQualitySource = row.airQualitySource;
        kept.pollenSource = row.pollenSource;
        kept.minutelySource = row.minutelySource;
        kept.alertSource = row.alertSource;
        kept.normalsSource = row.normalsSource;
        kept.reverseGeocodingSource = row.reverseGeocodingSource;
        kept.customName = row.customName;
        kept.weatherModels = row.weatherModels;
        /*
         * EVERY STORED FIELD HAS TO BE LISTED HERE.
         *
         * This copies field-by-field to keep object identity (see above), which means a field added
         * to LocationModel and to the table but not to this list is written on save and silently
         * dropped on load. `customName` was exactly that: the row reached the database, the toolbar
         * showed the new name until a restart, and then read the city again while `sqlite3` still
         * showed the override. Add to all three, or the round trip only looks like it works.
         */
        merged.push(kept);
      }
      this.locations = merged;
      this.setCurrentIndex(this.index);
    } else {
      await saveLocations(context, this.locations);
    }
    let restored: boolean = false;
    for (let i = 0; i < this.locations.length; i++) {
      const location: LocationModel = this.locations[i];
      const cached: CachedWeather | null = await loadWeather(context, location.formattedId);
      if (cached !== null) {
        location.weather = cached.weather;
        location.utcOffsetSeconds = cached.utcOffsetSeconds;
        location.daylight = cached.daylight;
        restored = true;
      }
    }
    await this.backfillCountryCodes();
    return restored;
  }

  /**
   * Gives a stored location the country code it was saved without.
   *
   * On Android every `Location` carries a countryCode because every one of them came out of the
   * location search. Here the column arrived with the weather-sources work, so rows saved by an
   * earlier build migrated with an empty one — and that is not cosmetic: nearly every national
   * source's `isFeatureSupportedForLocation` is a country comparison, so those locations matched no
   * national source at all and their pickers showed only the worldwide ones. It was visible on
   * device as Helsinki offering no FMI while a freshly added Oulu did.
   *
   * Resolved the same way the location was added in the first place — a geocoding search on the
   * stored city, matched back on coordinates at the four decimals `formattedId` rounds to. Runs
   * once: after the first success there is nothing left with an empty code. A failure is silent and
   * simply leaves the row for the next launch, because being offline must not cost the cached
   * forecast this method is called alongside.
   *
   * A current position is skipped — its country comes from the reverse geocode in
   * `updateCurrentPosition`, which runs on its refresh.
   */
  private async backfillCountryCodes(): Promise<void> {
    let changed: boolean = false;
    for (let i = 0; i < this.locations.length; i++) {
      const location: LocationModel = this.locations[i];
      if (location.isCurrentPosition || location.countryCode.length > 0 ||
        location.city.length === 0) {
        continue;
      }
      try {
        const hits: OpenMeteoLocationResult[] = await fetchLocationSearch(location.city, 'en');
        for (let h = 0; h < hits.length; h++) {
          const hit: OpenMeteoLocationResult = hits[h];
          if (hit.latitude.toFixed(4) === location.latitude.toFixed(4) &&
            hit.longitude.toFixed(4) === location.longitude.toFixed(4)) {
            location.countryCode = optional(hit.country_code);
            location.admin2 = optional(hit.admin2);
            changed = true;
            break;
          }
        }
      } catch (error) {
        console.warn('Country backfill failed for ' + location.city + ': ' +
          (error as Error).message);
      }
    }
    if (changed) {
      await this.persist();
    }
  }

  constructor() {
    this.locations = buildLocations();
  }

  getLocations(): LocationModel[] {
    return this.locations;
  }

  getCurrentIndex(): number {
    return this.index;
  }

  setCurrentIndex(index: number): void {
    if (this.locations.length === 0) {
      this.index = 0;
      return;
    }
    let next: number = index % this.locations.length;
    if (next < 0) {
      next += this.locations.length;
    }
    this.index = next;
    // The list screen selects a location by calling this, and the main screen has to notice.
    LocationRevision.instance.version++;
  }

  /**
   * MainActivityViewModel.locationExists (kt:582-588) — longitude AND latitude AND forecastSource.
   *
   * A real three-term comparison now, where it used to lean on `formattedId`. The id encodes only
   * `openmeteo-<lat>,<lon>`, which WAS the same test while Open-Meteo was the only forecast source
   * a location could carry; the weather-sources dialog makes that a variable, and two saved copies
   * of one city on different forecast sources are legal on Android.
   */
  private indexOfSame(location: LocationModel): number {
    for (let i = 0; i < this.locations.length; i++) {
      const saved: LocationModel = this.locations[i];
      if (saved.latitude === location.latitude &&
        saved.longitude === location.longitude &&
        saved.forecastSource === location.forecastSource) {
        return i;
      }
    }
    return -1;
  }

  locationExists(location: LocationModel): boolean {
    return this.indexOfSame(location) >= 0;
  }

  /**
   * The same test taken as three scalars.
   *
   * The weather-sources dialog asks it while the user is still choosing, and passing a LocationModel
   * across that boundary is what dragged the whole weather graph into ArkUI V2's state management.
   */
  locationExistsAt(latitude: number, longitude: number, forecastSource: string): boolean {
    for (let i = 0; i < this.locations.length; i++) {
      const saved: LocationModel = this.locations[i];
      if (saved.latitude === latitude && saved.longitude === longitude &&
        saved.forecastSource === forecastSource) {
        return true;
      }
    }
    return false;
  }

  /**
   * MainActivityViewModel.addLocation (kt:526-554) — a new city goes on the END of the list.
   *
   * A location that is already saved is NOT added, and the caller is told so: Android checks
   * `locationExists` first and refuses with `location_message_already_exists` (kt:529) rather than
   * silently succeeding. The index of the existing row still comes back, so a caller that wants to
   * jump to it can.
   */
  async addLocation(location: LocationModel): Promise<AddLocationResult> {
    // A current position is a singleton and carries no coordinates until its first fix, so it is
    // matched by id; everything else by the Kotlin's coordinate + forecast-source triple.
    const existing: number = location.isCurrentPosition
      ? this.indexOf(location.formattedId)
      : this.indexOfSame(location);
    if (existing >= 0) {
      return new AddLocationResult(existing, false);
    }
    this.locations.push(location);
    await this.persist();
    return new AddLocationResult(this.locations.length - 1, true);
  }

  /**
   * The "add current location" FAB (ManagementFragment.kt:236-252).
   *
   * Android builds `Location(isCurrentPosition = true)` with NO coordinates and saves that; the
   * position fix happens later, on the first refresh (RefreshHelper.getLocation STEP 1). The port
   * does the same, so a current-position row exists immediately and resolves when it is refreshed.
   *
   * There can only ever be one, which is why `buildSearchResultLocation` gives it the fixed id
   * `current-position` — and why the FAB itself disappears once one exists (kt:236).
   */
  async addCurrentPosition(): Promise<AddLocationResult> {
    return await this.addLocation(buildCurrentPositionLocation());
  }

  /** Whether a current-position entry is already saved — kt:236's `firstOrNull { it.isCurrentPosition }`. */
  hasCurrentPosition(): boolean {
    for (let i = 0; i < this.locations.length; i++) {
      if (this.locations[i].isCurrentPosition) {
        return true;
      }
    }
    return false;
  }

  /**
   * RefreshHelper.updateCurrentCoordinates + getLocation STEP 1/STEP 2, for one location.
   *
   * Returns false when the fix failed, so `refresh` can stop rather than fetch a forecast for
   * 0°N 0°E. On a coordinate CHANGE the Kotlin clears the address it had cached (kt:215-233) —
   * "Don't keep old data as the user can have changed position" — and that is what makes the
   * geocode below authoritative rather than additive.
   */
  private async updateCurrentPosition(location: LocationModel): Promise<boolean> {
    const fix: PositionResult = await requestCurrentPosition();
    if (fix.error !== PositionError.NONE) {
      this.lastError = fix.error === PositionError.PERMISSION_MISSING
        ? 'Location permission is required'
        : (fix.error === PositionError.LOCATION_OFF
          ? 'Location access is off'
          : 'Could not determine your position');
      return false;
    }

    const moved: boolean = location.latitude !== fix.latitude || location.longitude !== fix.longitude;
    location.latitude = fix.latitude;
    location.longitude = fix.longitude;
    if (moved) {
      location.city = '';
      location.district = '';
      location.region = '';
      // kt:215-233 — the address goes with the coordinates, so the next step has to look it up.
      location.needsGeocodeRefresh = true;
      // The country code goes with the address it came from — a position fix that has crossed a
      // border must not keep matching the old country's national sources.
      location.countryCode = '';
      // kt:220 resets the zone to GMT; the forecast reply replaces it a moment later anyway.
      location.utcOffsetSeconds = 0;
    }
    /*
     * A reverse geocode that has already failed for these coordinates is not retried.
     *
     * It is not free to retry: the platform geocoder is a service EXTENSION, so each attempt starts
     * `com.huawei.hmos.location/GeocodeServiceExtensionAbility` before failing with
     * `BussinessError 3301300` on this device. Because the failure leaves `city` empty, the old
     * condition retried on EVERY refresh, for ever — a permanent per-refresh cost buying nothing.
     *
     * Android does not re-geocode every refresh either: it tracks `needsGeocodeRefresh` and clears
     * it once the address is settled (RefreshHelper STEP 2). Keying on the coordinates means a real
     * move still triggers a fresh attempt, which is the case that matters.
     *
     * `needsGeocodeRefresh` is the same flag, ported for the case an empty city cannot express: a
     * row geocoded before a FIELD existed. Without it a current position saved before `district`
     * shipped keeps its city for ever and can never gain its district.
     */
    const fixKey: string = fix.latitude.toString() + ',' + fix.longitude.toString();
    const wantsAddress: boolean = location.city.length === 0 || location.needsGeocodeRefresh;
    if (wantsAddress && this.geocodeFailedFor !== fixKey) {
      const address: PositionAddress = await reverseGeocode(fix.latitude, fix.longitude);
      location.city = address.city;
      location.district = address.district;
      location.region = address.admin1;
      location.countryCode = address.countryCode;
      // Settled either way: a failure is recorded below and must not re-arm the flag.
      location.needsGeocodeRefresh = false;
      if (address.city.length === 0) {
        // getPlace (Location.kt:39-41) then keeps showing "Current location", which is what Android
        // shows too when it has no address — the row is unhelpful, not wrong.
        this.geocodeFailedFor = fixKey;
        console.warn('reverse geocoding unavailable for ' + fixKey + '; keeping "Current location"');
      }
    }
    return true;
  }

  /**
   * RefreshHelper STEP 2 for a location that is NOT the current position (kt:242-294).
   *
   * The step is gated on `needsGeocodeRefresh` ALONE. The doc comment above `getLocation` says
   * "Reverse geocoding (if current location) / On non-current location, just returns the location",
   * and that comment is what both ports were built from — but the CODE at kt:243 tests only the
   * flag, and STEP 1 is the part that is current-position-only. So Android reverse-geocodes a SAVED
   * location too whenever its address needs refreshing, which is how a saved Helsinki gains the
   * "Kotkavuori" that makes the reference toolbar read "Helsinki, Kotkavuori" where both ports read
   * "Helsinki". Open-Meteo's geocoding never fills `district` (it is not among the sources that
   * do), so the reverse geocode is the ONLY way any location gets one.
   *
   * Returns true when something changed and the row should be written back.
   */
  private async geocodeSavedLocation(location: LocationModel): Promise<boolean> {
    if (!location.needsGeocodeRefresh) {
      return false;
    }
    const key: string = location.latitude.toString() + ',' + location.longitude.toString();
    // Same non-retry rule as the current position's: the platform geocoder is a service extension
    // and a failed attempt is not free.
    if (this.geocodeFailedFor === key) {
      return false;
    }
    const address: PositionAddress = await reverseGeocode(location.latitude, location.longitude);
    if (address.city.length === 0) {
      // kt:295-305's catch — the location is kept and the failure recorded, not surfaced.
      this.geocodeFailedFor = key;
      return false;
    }
    /*
     * kt:250-266 — a hit further than REVERSE_GEOCODING_DISTANCE_LIMIT (50 km, kt:1478) from the
     * requested point is REJECTED and the old address kept.
     *
     * It cannot fire with this port's geocoder, which answers about the point it was given rather
     * than snapping to a nearest station the way IMS and NaturalEarth do. Ported anyway, and
     * skipped when the platform returns no coordinates to compare.
     */
    if (address.latitude !== 0 && address.longitude !== 0 &&
      distanceMetres(location.latitude, location.longitude, address.latitude, address.longitude) >
        REVERSE_GEOCODING_DISTANCE_LIMIT) {
      console.warn('Nearest location found is too far away from the user-provided location');
      location.needsGeocodeRefresh = false;
      return true;
    }
    location.city = address.city;
    location.district = address.district;
    location.region = address.admin1;
    if (address.countryCode.length > 0) {
      location.countryCode = address.countryCode;
    }
    location.needsGeocodeRefresh = false;
    return true;
  }

  /** The coordinates whose reverse geocode already failed this session. */
  private geocodeFailedFor: string = '';

  /**
   * MainActivityViewModel.deleteLocation (LocationItemTouchCallback.kt:110). The caller is
   * responsible for refusing when only one is left — the Kotlin does that in the swipe handler
   * (:100) so it can show its own message, and the message is the screen's, not the model's.
   *
   * Returns the removed location so the Undo action can put it back where it was.
   */
  async deleteLocation(index: number): Promise<LocationModel | null> {
    if (index < 0 || index >= this.locations.length || this.locations.length <= 1) {
      return null;
    }
    const removed: LocationModel = this.locations.splice(index, 1)[0];
    // Its stored forecast goes too, so re-adding the city does not restore a stale one.
    if (this.context !== null) {
      await deleteCachedWeather(this.context, removed.formattedId);
    }
    this.setCurrentIndex(this.index >= this.locations.length ? this.locations.length - 1 : this.index);
    await this.persist();
    return removed;
  }

  /**
   * MainActivityViewModel.updateLocation (kt:467) — replaces a saved location in place.
   *
   * Matched by formattedId, which the weather-sources dialog cannot change in this port: the id is
   * `openmeteo-<lat>,<lon>`, and a pick that would move the forecast source off Open-Meteo is
   * answered with the "not yet ported" placeholder instead of being applied. Upstream the id
   * carries the source, so a forecast-source change there is a delete plus an insert.
   */
  async updateLocation(location: LocationModel): Promise<void> {
    const index: number = this.indexOf(location.formattedId);
    if (index < 0) {
      return;
    }
    this.locations[index] = location;
    await this.persist();
  }

  /** Puts an undone deletion back at the position it came from (CancelDeleteListener, kt:138). */
  async restoreLocation(location: LocationModel, index: number): Promise<void> {
    const at: number = Math.max(0, Math.min(index, this.locations.length));
    this.locations.splice(at, 0, location);
    await this.persist();
  }

  /** ManagementFragment.reorderByDrag (kt:608) — a move, not a swap. */
  async moveLocation(from: number, to: number): Promise<void> {
    if (from === to || from < 0 || to < 0 ||
      from >= this.locations.length || to >= this.locations.length) {
      return;
    }
    const current: string = this.locations[this.index].formattedId;
    const moved: LocationModel = this.locations.splice(from, 1)[0];
    this.locations.splice(to, 0, moved);
    // The selected location follows its row rather than its old index.
    this.setCurrentIndex(this.indexOf(current));
    await this.persist();
  }

  indexOf(formattedId: string): number {
    for (let i = 0; i < this.locations.length; i++) {
      if (this.locations[i].formattedId === formattedId) {
        return i;
      }
    }
    return -1;
  }

  /**
   * Writes the list back after a caller edited a location IN PLACE.
   *
   * The add/delete/reorder paths all persist themselves, because they own the mutation. The edit
   * dialog does not: it hands back a value object that the screen applies to the live model, so
   * the write has to be asked for. Public for that one reason — everything else uses `persist`.
   */
  async persistLocations(): Promise<void> {
    await this.persist();
  }

  private async persist(): Promise<void> {
    // Every caller has just changed the list, so this is the one place the signal has to fire.
    LocationRevision.instance.version++;
    if (this.context !== null) {
      await saveLocations(this.context, this.locations);
    }
  }

  getCurrentLocation(): LocationModel | null {
    if (this.locations.length === 0) {
      return null;
    }
    return this.locations[this.index];
  }

  getIndicator(): LocationIndicator {
    return new LocationIndicator(this.index, this.locations.length);
  }

  /** HomeFragment.kt:489-496 — swiping switches to the neighbouring location. */
  offsetLocation(offset: number): void {
    this.setCurrentIndex(this.index + offset);
  }

  /**
   * `Weather.isValid(pollingIntervalHours)` (Weather.kt) — the stored forecast is still good when
   * its refresh time is in the past and less than one update interval ago. A `refresh_rate` of
   * "never" makes every forecast valid for ever, exactly as `pollingIntervalHours == null` does.
   */
  private weatherIsValid(location: LocationModel): boolean {
    const weather = location.weather;
    if (weather === null || weather.refreshTime === null) {
      return false;
    }
    const validityMs: number = updateIntervalMs(AppSettings.instance.refreshRate);
    if (validityMs < 0) {
      return true; // UpdateInterval.INTERVAL_NEVER — `pollingIntervalHours == null`.
    }
    const age: number = new Date().getTime() - weather.refreshTime.getTime();
    return age >= 0 && age < validityMs;
  }

  /**
   * updateWithUpdatingChecking (HomeFragment.kt:222-227) — pulls the current location's weather
   * from Open-Meteo. A failure leaves the previous weather in place, which is what the Android
   * app does when a source errors (it records a failed feature and keeps the cached data).
   */
  async refresh(triggeredByUser: boolean = false): Promise<boolean> {
    const location: LocationModel | null = this.getCurrentLocation();
    if (location === null) {
      return false;
    }
    /*
     * `checkToUpdateCurrentLocation` (MainActivityViewModel.kt:279-283) returns AT ONCE when the
     * selected location's stored weather is still valid — "if already valid, just return" — and
     * only a stale one reaches `updateWithUpdatingChecking`. Validity is
     * `Weather.isValid(updateInterval.validity)`: the refresh time within the background update
     * interval, 1:30 by default (Weather.kt, UpdateInterval.kt).
     *
     * The port had no such test, so EVERY return from the location list started a network round
     * trip. Picking a city whose forecast was minutes old still showed the cached page and then sat
     * there for a couple of seconds before anything changed, which is what "clicking a new location
     * feels too slow" was. Measured on the device before the fix: cached content up at ~0.6 s,
     * fresh numbers only at ~3 s, on every single switch.
     *
     * The pull-to-refresh gesture is `triggeredByUser` and skips this: MainActivity.kt:733 calls
     * `updateWithUpdatingChecking` directly, bypassing the validity check.
     */
    if (!triggeredByUser && this.weatherIsValid(location)) {
      return false;
    }
    /*
     * MainActivityViewModel.kt:332-345 — the same location is not re-fetched within
     * DELAY_BEFORE_NEXT_MANUAL_REFRESH (kt:733, ten seconds).
     *
     * Ported because it is Android's behaviour, and because without it every return from the
     * location list refetched and then bumped `dataVersion`, which re-keys the Swiper's ForEach and
     * so destroys and rebuilds all four location pages. That was ~29 MB of ArkTS heap per trip and
     * ended in a THREAD_BLOCK_6S kill. Android toasts `weather_message_too_frequent_refreshes` when
     * it refuses, but only on the explicit pull-to-refresh; a refusal on resume is silent there and
     * here.
     */
    const now: number = new Date().getTime();
    if (this.lastRefreshLocationId === location.formattedId &&
      this.lastRefreshAt + DELAY_BEFORE_NEXT_MANUAL_REFRESH > now) {
      return false;
    }
    this.lastRefreshLocationId = location.formattedId;
    this.lastRefreshAt = now;
    this.refreshing = true;
    try {
      /*
       * A current-position location has no usable coordinates until the device is asked, so the fix
       * comes FIRST — RefreshHelper calls updateCurrentCoordinates before the weather request and
       * returns early when it fails (kt:196-199), rather than fetching a forecast for 0°N 0°E.
       */
      if (location.isCurrentPosition) {
        const located: boolean = await this.updateCurrentPosition(location);
        if (!located) {
          return false;
        }
        await this.persist();
      } else if (await this.geocodeSavedLocation(location)) {
        await this.persist();
      }
      /*
       * Alerts are started BEFORE the forecast is awaited, so the two run together.
       *
       * They were sequential, which put a whole extra round trip on the critical path of every
       * refresh — the same mistake, and the same fix, as the forecast and air-quality pair that
       * session (b) put in parallel. `fetchAlerts` swallows its own failures, so starting it early
       * cannot reject the pair.
       */
      const alerts: Promise<Alert[]> =
        fetchAlerts(location.latitude, location.longitude, location.region);
      // Each location carries its own coordinates; this used to fetch Helsinki's for all three,
      // so Berlin and Tokyo silently showed Helsinki's forecast.
      const result: RefreshResult = await fetchWeather(
        new Coordinates(location.latitude, location.longitude),
        location.weather,
        // OpenMeteoService.kt:245 — the model list is per LOCATION, not per app, so it is read
        // here rather than baked into the API module.
        selectedWeatherModels(location.weatherModels).join(',')
      );
      location.weather = result.weather;
      // The refresh also settles the two location fields that depend on it: the zone every date
      // is rendered in, and Location.isDaylight (Location.kt:45-52), which selects the day or
      // night theme. Both used to be guesses seeded by the mock.
      location.utcOffsetSeconds = result.utcOffsetSeconds;
      location.daylight = result.daylight;
      // Alerts come from a SECOND source: Open-Meteo declares no SourceFeature.ALERT, so the
      // alert card is fed by FMI, exactly as the reference Android install is. fetchAlerts
      // yields an empty list on failure rather than throwing, so a warning outage cannot cost
      // the forecast that has already arrived.
      /*
       * The alerts arrive AFTER `location.weather` has already been assigned, and `Weather` is a
       * plain class — so mutating `alertList` on it is a change ArkUI V2 cannot see. LocationPage
       * gates its alert card on `weatherStamp`, a @Computed that re-evaluates only when the @Trace'd
       * `weather` is REPLACED, so the card never appeared however many alerts were in the model.
       *
       * Publishing them through a fresh `Weather` is what makes the assignment observable. The copy
       * is SHALLOW on purpose: the hourly and daily arrays are shared by reference, so this costs
       * one object rather than proxying a ~400-entry graph — putting big graphs under observation is
       * what caused the THREAD_BLOCK_6S freeze earlier in this project's history.
       *
       * The NDK never had this: it redraws imperatively every frame and simply reads the list.
       */
      const alertList: Alert[] = await alerts;
      if (location.weather !== null && alertList.length > 0) {
        location.weather = withAlerts(location.weather, alertList);
      }
      this.lastError = '';
      // Android writes every successful refresh to its database; that stored copy is what makes a
      // cold start show a forecast before any network call finishes, and what stays on screen when
      // the next refresh fails.
      if (this.context !== null) {
        saveWeather(this.context, location.formattedId, result.weather,
          result.utcOffsetSeconds, result.daylight);
      }
      return true;
    } catch (error) {
      const message: string = (error as Error).message;
      console.error('Open-Meteo refresh failed: ' + message);
      // RefreshErrorType (ui/main/utils/RefreshErrorType.kt:57-68, 225-229) maps the exception to
      // a short message that MainActivityViewModel shows in a snackbar. Android keeps whatever
      // weather it already had — it reads the location out of its database, so a failed refresh
      // still leaves the previous forecast on screen.
      //
      // This port has no persistence yet (CLAUDE.md defers it), so a failure on the FIRST refresh
      // leaves `weather` null and the page genuinely has nothing to draw. Reporting the error is
      // then the whole of the user-visible behaviour, and without it the screen just sits blank —
      // which is exactly what it did when the device dropped off Wi-Fi.
      this.lastError = refreshErrorMessage(message);
      if (location.weather !== null) {
        location.weather.refreshTime = new Date();
      }
      return false;
    } finally {
      // `finally`, not a line at the end of each branch: the current-position path returns early
      // from inside the `try` when the fix fails, and that return must not leave the flag stuck on.
      this.refreshing = false;
    }
  }

  /**
   * MainActivityViewModel._loading (kt:101-102) — true while a refresh is in flight.
   *
   * The location list screen refuses to reorder or swipe a row while this is set and says
   * `message_please_wait_refresh` (LocationItemTouchCallback.kt:52-62, 77, 93, 106). It is read
   * imperatively from gesture handlers and never rendered from, so a plain field is right here —
   * making it @Trace would invite the stale-read trap this codebase has hit three times, since a
   * value walked out of a plain object registers no dependency anyway.
   */
  private refreshing: boolean = false;

  /**
   * SettingsManager.weatherManualUpdateLastLocationId / …LastTimestamp (MainActivityViewModel.kt:
   * 332-336) — the pair the ten-second refusal window is measured against.
   */
  private lastRefreshLocationId: string = '';
  private lastRefreshAt: number = 0;

  isRefreshing(): boolean {
    return this.refreshing;
  }

  /** The error surfaced by the last refresh, or empty. Cleared by the next success. */
  private lastError: string = '';

  getLastError(): string {
    return this.lastError;
  }

  clearLastError(): void {
    this.lastError = '';
  }
}

/**
 * Weather.kt:94-160 — getTemperatureRangeSummary.
 * Before 06:00 shows yesterday night then today day; before 18:00 today day then night;
 * otherwise today night then tomorrow day. Labels are strings.xml:328/330.
 */
export function getTemperatureRangeSummary(location: LocationModel): string | null {
  const weather = location.weather;
  if (weather === null || weather.todayIndex === null) {
    return null;
  }
  const todayIndex: number = weather.todayIndex;
  const today = weather.dailyForecast[todayIndex];
  if (today === undefined) {
    return null;
  }

  // The 06:00 / 18:00 boundaries are the LOCATION's, as Weather.kt reads them off a Calendar in
  // location.timeZone.
  const currentHour: number = localHours(new Date(), location.utcOffsetSeconds);
  let isDayFirst: boolean;
  let first: number | null = null;
  let second: number | null = null;

  if (currentHour < 6) {
    isDayFirst = false;
    const yesterday = weather.dailyForecast[todayIndex - 1];
    first = yesterday !== undefined && yesterday.night !== null && yesterday.night.temperature !== null
      ? yesterday.night.temperature.temperature
      : null;
    second = today.day !== null && today.day.temperature !== null ? today.day.temperature.temperature : null;
  } else if (currentHour < 18) {
    isDayFirst = true;
    first = today.day !== null && today.day.temperature !== null ? today.day.temperature.temperature : null;
    second = today.night !== null && today.night.temperature !== null ? today.night.temperature.temperature : null;
  } else {
    isDayFirst = false;
    first = today.night !== null && today.night.temperature !== null ? today.night.temperature.temperature : null;
    const tomorrow = weather.dailyForecast[todayIndex + 1];
    second = tomorrow !== undefined && tomorrow.day !== null && tomorrow.day.temperature !== null
      ? tomorrow.day.temperature.temperature
      : null;
  }

  const parts: string[] = [];
  if (first !== null) {
    parts.push((isDayFirst ? 'Day' : 'Night') + COLON_SEPARATOR + formatTemperatureNarrow(first));
  }
  if (second !== null) {
    parts.push((isDayFirst ? 'Night' : 'Day') + COLON_SEPARATOR + formatTemperatureNarrow(second));
  }
  return parts.length > 0 ? parts.join(DOT_SEPARATOR) : null;
}
