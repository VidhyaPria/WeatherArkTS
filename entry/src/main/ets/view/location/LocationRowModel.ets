/*
 * One row of the location list — the port of LocationModel.kt (ui/main/adapters/location).
 *
 * Android builds this from a `Location` plus a `selected` flag and derives the two lines of text
 * once, at bind time. The same split is kept here: the screen renders a row model, it does not
 * reach into the weather.
 */

import { getPlace, LocationModel, Weather } from '../../model/Weather';
import { WeatherKind } from '../../model/WeatherKind';
import { formatRelativeTime } from '../../common/Formatter';

/** SettingsManager.updateInterval.validity — the default refresh interval is 1.5 h. */
const UPDATE_VALIDITY_MS: number = 90 * 60 * 1000;
const DAY_MS: number = 24 * 60 * 60 * 1000;

/*
 * @ObservedV2 so a row can be REWRITTEN IN PLACE.
 *
 * The rows used to be thrown away and rebuilt on every `refreshRows()`, and the ForEach key carried
 * the row's index so that a reorder changed the key set and forced the diff to act. That made a
 * drag-drop cost 116 ms on the UI thread — `FlushLayoutTask` 97 ms, destroying and rebuilding one
 * LocationCard per moved slot at 72 ms for the first and ~10 ms for each after it. A visible stutter
 * on every drop, and it grew with the number of rows the move crossed.
 *
 * Now the array holds one stable model per SLOT and `apply` rewrites its fields. The key is the
 * index, which never changes, so no node is ever destroyed; the card re-renders because its scalar
 * @Params changed. Every field here is a primitive — this must never come to hold the LocationModel
 * again, for the reason directly below.
 */
@ObservedV2
export class LocationRowModel {
  /**
   * The id, NOT the LocationModel.
   *
   * This used to hold the whole `location`, and that was a real defect rather than a style point.
   * The rows live in a `@Local LocationRowModel[]`, so ArkUI V2 walks whatever they reference and
   * registers observation bindings for it — and a LocationModel reaches its `weather`, which is
   * ~400 hourly entries plus daily, minutely and alert objects. Four rows put several thousand
   * objects into the binding registry on every `refreshRows()`, and the registry is a dictionary
   * that `clearBinding` enumerates with `Object.keys` when a page is torn down.
   *
   * That is what froze the app: opening the location list four times in half a minute grew the
   * registry until the teardown on the next push took over six seconds and tripped THREAD_BLOCK_6S,
   * with the fault stack ending in
   * `onVSyncUpdate → UpdateElement → aboutToBeDeletedInternal → clearBinding → Object.keys`.
   * Nothing here needs the model — every value the row draws is derived once, below.
   */
  @Trace formattedId: string = '';
  @Trace selected: boolean = false;
  /** kt:41 — "⊙ " prefixes a current-position row, exactly as the toolbar title does. */
  @Trace title: string = '';
  @Trace body: string = '';
  @Trace alerts: number = 0;
  @Trace currentPosition: boolean = false;
  @Trace weatherKind: WeatherKind | null = null;
  @Trace daylight: boolean = true;

  constructor(location: LocationModel, selected: boolean, now: Date) {
    this.apply(location, selected, now);
  }

  /**
   * Rewrites this slot from `location`, leaving the object — and so the card bound to it — in place.
   *
   * Every mutation this screen makes goes through here: a reorder, a selection change, a refresh
   * landing. Only a change in the NUMBER of rows adds or drops a slot.
   */
  apply(location: LocationModel, selected: boolean, now: Date): void {
    // Guarding each write with an equality test was tried and MEASURED: it changed nothing
    // (FlushDirtyNodeUpdate stayed at 24 ms on the drop frame), so V2 already skips a @Trace write
    // that does not change the value. Plain assignment.
    this.formattedId = location.formattedId;
    this.selected = selected;
    this.currentPosition = location.isCurrentPosition;
    this.title = (location.isCurrentPosition ? '⊙ ' : '') + getPlace(location);
    this.daylight = location.daylight;

    const weather: Weather | null = location.weather;
    this.weatherKind = weather !== null && weather.current !== null
      ? weather.current.weatherKind
      : null;
    this.alerts = weather !== null ? weather.alertList.length : 0;
    this.body = LocationRowModel.buildBody(location, this.alerts, now);
  }

  /**
   * LocationModel.getWeatherText (kt:54-88), in its own order:
   *   never refreshed            → the administration levels (here, the region)
   *   alert source, stale > 24 h → "Last updated x"
   *   alert source, alerts       → "⚠ Active alert"
   *   stale past the interval    → "Last updated x"
   *   otherwise                  → the current condition
   */
  private static buildBody(location: LocationModel, alerts: number, now: Date): string {
    const weather: Weather | null = location.weather;
    const refreshTime: Date | null =
      weather !== null && weather.refreshTime !== null ? weather.refreshTime : null;
    if (refreshTime === null) {
      return location.region;
    }
    const age: number = now.getTime() - refreshTime.getTime();
    // Only Helsinki has an alert source in this build (FMI), which is what `region` marks.
    const hasAlertSource: boolean = location.region.length > 0;
    if (hasAlertSource) {
      if (age > DAY_MS) {
        return LocationRowModel.lastUpdated(refreshTime, now);
      }
      if (alerts > 0) {
        return '⚠ Active alert';  // strings.xml location_has_active_alerts
      }
    }
    if (age > UPDATE_VALIDITY_MS) {
      return LocationRowModel.lastUpdated(refreshTime, now);
    }
    const text: string | null =
      weather !== null && weather.current !== null ? weather.current.weatherText : null;
    return text !== null && text.length > 0 ? text : location.region;
  }


  /**
   * strings.xml `location_last_updated_x` = "Last updated %s", and the Kotlin uncapitalises the
   * relative time before substituting it (kt:70) — "Last updated 2 hours ago", not "… 2 Hours ago".
   */
  private static lastUpdated(refreshTime: Date, now: Date): string {
    const relative: string = formatRelativeTime(refreshTime, now);
    const lowered: string = relative.length > 0
      ? relative.charAt(0).toLowerCase() + relative.substring(1)
      : relative;
    return 'Last updated ' + lowered;
  }
}
