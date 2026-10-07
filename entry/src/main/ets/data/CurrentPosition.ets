/*
 * The device position, and the address that goes with it.
 *
 * This stands in for two Android pieces at once:
 *
 *   AndroidLocationService     BuildConfig.DEFAULT_LOCATION_SOURCE is "native", so the default
 *                              location source is the platform's own fused provider, not a network
 *                              one. `geoLocationManager.getCurrentLocation` is its counterpart.
 *   AndroidGeocoderService     the platform reverse geocoder, used to turn the fix into a place
 *                              name. `geoLocationManager.getAddressesFromLocation` is the same API
 *                              on the other platform.
 *
 * Neither is a weather-source client, so neither is what CLAUDE.md's source scope excludes — the
 * excluded thing is the fetch/parse client for a weather provider. What IS out of scope is
 * NaturalEarth, which is Breezy's own DEFAULT_GEOCODING_SOURCE ("naturalearth", a bundled dataset).
 * Using the platform geocoder instead is the same substitution the Android build offers as an
 * alternative, and it produces the same visible result: a named current position.
 *
 * The order of operations is RefreshHelper.updateCurrentCoordinates (kt:121-181) followed by
 * getLocation STEP 1 and STEP 2 (kt:191-243).
 */

import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * ACCESS_COARSE_LOCATION / ACCESS_FINE_LOCATION (RefreshHelper.kt:133-134).
 *
 * HarmonyOS splits the pair the same way, and `APPROXIMATELY_LOCATION` is the one that must be
 * granted first — asking for `LOCATION` alone is refused. Coarse is all the app needs: a forecast
 * grid cell is kilometres wide.
 */
const LOCATION_PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION'];

/** Long enough for a cold fix, short enough that a failed one still reports back. */
const FIX_TIMEOUT_MS: number = 15000;

/** What went wrong, mapped to the RefreshErrorType the Android app would have raised. */
export enum PositionError {
  NONE,
  /** RefreshErrorType.ACCESS_LOCATION_PERMISSION_MISSING */
  PERMISSION_MISSING,
  /** RefreshErrorType.LOCATION_ACCESS_OFF */
  LOCATION_OFF,
  /** LocationException — the provider returned nothing. */
  FIX_FAILED
}

export class PositionResult {
  readonly error: PositionError;
  readonly latitude: number;
  readonly longitude: number;

  constructor(error: PositionError, latitude: number, longitude: number) {
    this.error = error;
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

/** The address for a fix. Every field is optional; a failed lookup yields all-empty. */
export class PositionAddress {
  readonly city: string;
  /** Location.district — `Address.subLocality` on Android (AndroidGeocoderService.kt:43). */
  readonly district: string;
  readonly admin1: string;
  /**
   * The ISO 3166-1 alpha-2 code. A current position is the one location that gets its country from
   * the device rather than from a geocoding hit, and without it the source catalogue's national
   * sources cannot match — see LocationModel.countryCode.
   */
  readonly countryCode: string;
  /**
   * Where the geocoder says the ANSWER is, when it says at all — 0 when it does not.
   *
   * RefreshHelper.kt:250-255 rejects a hit further than 50 km from the point it asked about, which
   * only means anything for a source that snaps to a nearest station. Carried so the rule can be
   * ported rather than assumed away.
   */
  readonly latitude: number;
  readonly longitude: number;

  constructor(city: string, district: string, admin1: string, countryCode: string,
    latitude: number = 0, longitude: number = 0) {
    this.city = city;
    this.district = district;
    this.admin1 = admin1;
    this.countryCode = countryCode;
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

/** Metres between two points — `SphericalUtil.computeDistanceBetween` (RefreshHelper.kt:251). */
export function distanceMetres(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const earthRadius: number = 6371000;
  const toRad: number = Math.PI / 180;
  const dLat: number = (lat2 - lat1) * toRad;
  const dLon: number = (lon2 - lon1) * toRad;
  const a: number = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * earthRadius * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** RefreshHelper.kt:1478 — 50 km. */
export const REVERSE_GEOCODING_DISTANCE_LIMIT: number = 50000;

/**
 * Asks for the location permission, returning whether it ended up granted.
 *
 * Android checks the permission inside the refresh and reports a missing one as a refresh error
 * (RefreshHelper.kt:131-137), having requested it from MainActivity at launch. The port asks at the
 * moment the user taps "add current location" instead: it is the same permission for the same
 * reason, asked where the user can connect it to what they just did, and it avoids saving a
 * location that could never resolve.
 */
export async function ensureLocationPermission(context: common.UIAbilityContext): Promise<boolean> {
  const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  try {
    const result: PermissionRequestResult =
      await manager.requestPermissionsFromUser(context, LOCATION_PERMISSIONS);
    const granted: number[] = result.authResults;
    for (let i = 0; i < granted.length; i++) {
      if (granted[i] !== 0) {
        return false;
      }
    }
    return granted.length > 0;
  } catch (error) {
    console.error('location permission request failed: ' + (error as BusinessError).message);
    return false;
  }
}

/**
 * One position fix.
 *
 * `roundDecimals(6)` is the Kotlin's, with its own reason: "Some sources do not accept more than 6
 * decimals, so truncating it here" (RefreshHelper.kt:166-170).
 */
export async function requestCurrentPosition(): Promise<PositionResult> {
  try {
    if (!geoLocationManager.isLocationEnabled()) {
      // LocationManagerCompat.isLocationEnabled (RefreshHelper.kt:145-147)
      return new PositionResult(PositionError.LOCATION_OFF, 0, 0);
    }
  } catch (error) {
    console.error('isLocationEnabled failed: ' + (error as BusinessError).message);
  }

  const request: geoLocationManager.CurrentLocationRequest = {
    // The coarse permission only permits the approximate scenario.
    priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
    scenario: geoLocationManager.LocationRequestScenario.UNSET,
    maxAccuracy: 0,
    timeoutMs: FIX_TIMEOUT_MS
  };

  try {
    const fix: geoLocationManager.Location = await geoLocationManager.getCurrentLocation(request);
    return new PositionResult(
      PositionError.NONE,
      round6(fix.latitude),
      round6(fix.longitude)
    );
  } catch (error) {
    console.error('position fix failed: ' + (error as BusinessError).message);
    return new PositionResult(PositionError.FIX_FAILED, 0, 0);
  }
}

function round6(value: number): number {
  return Math.round(value * 1000000) / 1000000;
}

/**
 * STEP 2 of getLocation (RefreshHelper.kt:242-243) — the address for a fix.
 *
 * A failure is NOT an error the user has to see: Android keeps the location and records a failed
 * REVERSE_GEOCODING feature, and `getPlace` then falls back to "Current location"
 * (Location.kt:39-41). So this returns empties rather than throwing.
 */
export async function reverseGeocode(latitude: number, longitude: number): Promise<PositionAddress> {
  try {
    const request: geoLocationManager.ReverseGeoCodeRequest = {
      latitude: latitude,
      longitude: longitude,
      maxItems: 1,
      // English only, per CLAUDE.md.
      locale: 'en'
    };
    const addresses: geoLocationManager.GeoAddress[] =
      await geoLocationManager.getAddressesFromLocation(request);
    if (addresses.length === 0) {
      return new PositionAddress('', '', '', '');
    }
    const address: geoLocationManager.GeoAddress = addresses[0];
    // placeName is the locality on this platform; administrativeArea is admin1, which is the level
    // LocationModel.region carries. subLocality is the district Android's geocoder returns as
    // `Address.subLocality` (AndroidGeocoderService.kt:43) — the "Kotkavuori" of
    // "Helsinki, Kotkavuori".
    const city: string = text(address.locality) !== '' ? text(address.locality) : text(address.placeName);
    return new PositionAddress(city, text(address.subLocality), text(address.administrativeArea),
      text(address.countryCode), number(address.latitude), number(address.longitude));
  } catch (error) {
    console.error('reverse geocoding failed: ' + (error as BusinessError).message);
    return new PositionAddress('', '', '', '');
  }
}

function text(value: string | undefined): string {
  return value === undefined ? '' : value;
}

/** GeoAddress's coordinates are optional; 0 means "the platform did not say". */
function number(value: number | undefined): number {
  return value === undefined ? 0 : value;
}
