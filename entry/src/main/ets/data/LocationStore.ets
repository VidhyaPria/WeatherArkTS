/*
 * The saved-location list backing the main screen's Swiper.
 *
 * This stands in for Breezy's location database until the location-list screen is ported
 * (migration step 5). It carries ONLY what the database carries — id, name, coordinates,
 * timezone — and no weather: `LocationModel.weather` stays null until a real Open-Meteo refresh
 * fills it, exactly as a freshly added location behaves on Android.
 *
 * There is deliberately no seeded weather here. The port used to ship a full invented forecast
 * (temperatures, a "Rain Wednesday evening" summary, monthly normals of 23°/14°, and a "Wind
 * warning" alert on Berlin) so the cards had something to draw before the first fetch. All of it
 * has been removed:
 *
 *   - Open-Meteo returns no forecast SUMMARY, so `Current.dailyForecast` / `hourlyForecast` are
 *     null and DailyViewHolder.kt:68-73 hides the subtitle row.
 *   - Open-Meteo is not a NORMALS source. RefreshHelper.kt:884-898 fills `Weather.normals` only
 *     from a separately configured `normalsSource`, so an Open-Meteo-only build has none and the
 *     two "Normal" key lines simply do not appear.
 *   - Open-Meteo publishes no ALERTS, so `alertList` is empty and the alert card never shows.
 *
 * A card that has no data is a card Android does not draw either; that is the behaviour to match,
 * not a gap to paper over.
 */

import { LocationModel } from '../model/Weather';
import { applyDefaultPreset } from './SourceCatalogue';

function buildLocation(
  id: string,
  city: string,
  isCurrentPosition: boolean,
  timeZone: string,
  utcOffsetSeconds: number,
  latitude: number,
  longitude: number,
  region: string = '',
  countryCode: string = '',
  admin2: string = ''
): LocationModel {
  const location = new LocationModel();
  location.region = region;
  // The source catalogue's compatibility rules are almost all country comparisons, so a location
  // with no country code matches no national source at all (SourceCatalogue.ets).
  location.countryCode = countryCode;
  location.admin2 = admin2;
  location.formattedId = id;
  location.city = city;
  location.latitude = latitude;
  location.longitude = longitude;
  location.isCurrentPosition = isCurrentPosition;
  location.timeZone = timeZone;
  location.utcOffsetSeconds = utcOffsetSeconds;
  // Location.isDaylight (Location.kt:45-52) is derived from the day's sun times, so it cannot be
  // known before the first refresh. Daytime is the neutral starting assumption; the refresh
  // replaces it with the computed value.
  location.daylight = true;
  location.weather = null;
  return location;
}

/**
 * The list a brand-new install starts with.
 *
 * Now only a SEED: `LocationTable` persists whatever the user's location list becomes, and this is
 * what goes in when that table is empty. It used to be the whole story, which was honest while
 * there was no screen that could change it.
 *
 * Helsinki first, to match the location the Android build opens on. It is a saved city there,
 * not the current position, so the title carries no "⊙" prefix (HomeFragment.kt:414-417).
 * Coordinates are what Open-Meteo's own geocoding returns for each city, so the port and the
 * Android build resolve the same grid cell.
 *
 * The offsets are the standard summer values for these zones and are only a starting guess —
 * every refresh overwrites them with Open-Meteo's own `utc_offset_seconds` for the resolved grid
 * cell, which is what the display then uses.
 */
export function buildLocations(): LocationModel[] {
  return [
    seedLocation('Helsinki', 'Europe/Helsinki', 3 * 3600, 60.16952, 24.93545, 'Uusimaa', 'FI'),
    seedLocation('Berlin', 'Europe/Berlin', 2 * 3600, 52.52437, 13.41053, 'State of Berlin', 'DE'),
    seedLocation('Tokyo', 'Asia/Tokyo', 9 * 3600, 35.6895, 139.69171, 'Tokyo', 'JP')
  ];
}

/**
 * A seeded city, keyed exactly as the search screen would key it.
 *
 * The ids used to be hand-written (`saved-helsinki`), which quietly broke the duplicate check:
 * `addLocation` is a no-op for a location already saved (MainActivityViewModel, ported in
 * MainViewModel.addLocation), and it compares formattedId — so searching for Helsinki on a fresh
 * install added a SECOND Helsinki beside the seeded one. On Android that cannot happen, because
 * every saved location got its id from the same geocoding hit the search returns. Deriving the
 * seed's id from its coordinates the same way makes the two agree.
 *
 * That only works if the coordinates agree to the four decimals the id rounds to, so the three
 * seeds now carry Open-Meteo's own values verbatim — 60.16952 rather than the 60.1695 that was
 * here, which rounds to a different id than the API's 24.93545 does.
 */
function seedLocation(
  city: string,
  timeZone: string,
  utcOffsetSeconds: number,
  latitude: number,
  longitude: number,
  region: string,
  countryCode: string
): LocationModel {
  const id: string = 'openmeteo-' + latitude.toFixed(4) + ',' + longitude.toFixed(4);
  const seeded: LocationModel = buildLocation(id, city, false, timeZone, utcOffsetSeconds,
    latitude, longitude, region, countryCode);
  // A seed stands in for a location the user added, and Android presets every Location it creates.
  applyDefaultPreset(seeded);
  return seeded;
}

/**
 * A location built from an Open-Meteo geocoding hit, or from a device position fix.
 *
 * `formattedId` mirrors Breezy's own convention of a source-qualified id
 * (Location.formattedId) — a current-position entry is a singleton there, so it gets a fixed id
 * and adding it twice replaces rather than duplicates.
 */
/**
 * The current-position entry, as `Location(isCurrentPosition = true)` (ManagementFragment.kt:243).
 *
 * Deliberately coordinate-less: Android saves it that way and lets the first refresh fill it in.
 * The name is empty too, which is what makes `getPlace` fall back to "Current location"
 * (Location.kt:39-41) until the reverse geocode lands.
 */
export function buildCurrentPositionLocation(): LocationModel {
  return buildSearchResultLocation('', '', 0, 0, '', true, '', '');
}

export function buildSearchResultLocation(
  city: string,
  region: string,
  latitude: number,
  longitude: number,
  timeZone: string,
  isCurrentPosition: boolean,
  countryCode: string = '',
  admin2: string = ''
): LocationModel {
  const id: string = isCurrentPosition
    ? 'current-position'
    : 'openmeteo-' + latitude.toFixed(4) + ',' + longitude.toFixed(4);
  // The offset is a placeholder until the first refresh reports the grid cell's real one.
  return buildLocation(id, city, isCurrentPosition, timeZone, 0, latitude, longitude, region,
    countryCode, admin2);
}
