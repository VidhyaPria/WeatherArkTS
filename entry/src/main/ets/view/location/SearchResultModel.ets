/*
 * One row of the search results — what SearchActivity.kt:201-209 binds a ListItem to.
 *
 *   headlineContent   location.getPlace(context)      app/.../domain/location/model/Location.kt:29-43
 *   supportingContent location.administrationLevels() domain/.../location/model/Location.kt:229-259
 *
 * A search hit is deliberately NOT a LocationModel. The admin levels exist only to disambiguate two
 * cities with the same name in the picker; nothing downstream stores or displays admin2/3/4, and
 * LocationModel keeps just the `region` (admin1) that the alert matching needs. Converting happens
 * on selection, in `toLocation()`.
 */

import { LocationModel } from '../../model/Weather';
import { OpenMeteoLocationResult } from '../../data/openmeteo/OpenMeteoJson';
import { buildSearchResultLocation } from '../../data/LocationStore';
import { applyDefaultSourcePreference } from '../../data/SourceCatalogue';
import { AppSettings } from '../../data/SettingsStore';

/** Nulls and empties are the same thing to every rule below, so normalise once on the way in. */
function text(value: string | null | undefined): string {
  return value === null || value === undefined ? '' : value;
}

export class SearchResultModel {
  /** OpenMeteoLocationResult.name → LocationAddressInfo.city (OpenMeteoService.kt:670). */
  readonly city: string;
  readonly country: string;
  /** OpenMeteoLocationResult.country_code → Location.countryCode, which the source catalogue keys off. */
  readonly countryCode: string;
  readonly admin1: string;
  readonly admin2: string;
  readonly admin3: string;
  readonly admin4: string;
  readonly latitude: number;
  readonly longitude: number;
  readonly timeZone: string;

  constructor(result: OpenMeteoLocationResult) {
    this.city = result.name;
    this.country = text(result.country);
    this.countryCode = text(result.country_code);
    this.admin1 = text(result.admin1);
    this.admin2 = text(result.admin2);
    this.admin3 = text(result.admin3);
    this.admin4 = text(result.admin4);
    this.latitude = result.latitude;
    this.longitude = result.longitude;
    this.timeZone = text(result.timezone);
  }

  /**
   * getPlace (Location.kt:29-43).
   *
   * The full rule is customName → cityAndDistrict → "Current location" → "lat, lon". A geocoding
   * hit has no custom name and is not a current position, and `convertLocation`
   * (OpenMeteoService.kt:657-673) sets no district — so `cityAndDistrict` (Location.kt:261-273)
   * reduces to the city, and the coordinate fallback only fires if the API returned a nameless hit.
   */
  getPlace(): string {
    if (this.city.length > 0) {
      return this.city;
    }
    return this.latitude.toString() + ', ' + this.longitude.toString();
  }

  /**
   * administrationLevels (Location.kt:229-259) — country, then admin1..4, joined with ", ".
   *
   * admin3 and admin4 carry an extra condition each. admin4 is printed only when it differs from
   * the city; admin3 only when there IS an admin4, or when admin3 itself differs from the city.
   * Both exist to stop the row repeating the name already in the headline.
   */
  administrationLevels(): string {
    const parts: string[] = [];
    if (this.country.length > 0) {
      parts.push(this.country);
    }
    if (this.admin1.length > 0) {
      parts.push(this.admin1);
    }
    if (this.admin2.length > 0) {
      parts.push(this.admin2);
    }
    if (this.admin3.length > 0 && (this.admin4.length > 0 || this.admin3 !== this.city)) {
      parts.push(this.admin3);
    }
    if (this.admin4.length > 0 && this.admin4 !== this.city) {
      parts.push(this.admin4);
    }
    return parts.join(', ');
  }

  /**
   * The saved location this hit becomes once picked.
   *
   * `region` takes admin1, matching what LocationModel documents it as. The timezone comes from the
   * geocoding hit, and the UTC offset stays 0 until the first forecast reports the grid cell's own
   * `utc_offset_seconds` — the same starting state a seeded location has.
   *
   * countryCode and admin2 now come along too. They are what the source catalogue's compatibility
   * rules read: without a country code a saved location matches no national source, so the
   * weather-sources dialog would offer nothing but the worldwide ones.
   */
  toLocation(): LocationModel {
    /*
     * SearchActivity hands the hit to SecondarySourcesPreference already preset — Android calls
     * applyDefaultPreset on every Location it constructs (ManagementFragment.kt:242 for the
     * current position, the search flow for a hit), so the dialog opens on real sources rather
     * than eight blanks.
     */
    const location: LocationModel = buildSearchResultLocation(
      this.getPlace(),
      this.admin1,
      this.latitude,
      this.longitude,
      this.timeZone,
      false,
      this.countryCode,
      this.admin2
    );
    // Screen 3f's "Default source for new locations" decides this, not the preset alone —
    // SearchActivityRepository.kt:105-186. "auto" is what falls through to applyDefaultPreset.
    applyDefaultSourcePreference(location, AppSettings.instance.defaultForecastSource);
    return location;
  }
}
