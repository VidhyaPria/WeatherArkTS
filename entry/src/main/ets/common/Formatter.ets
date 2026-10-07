/*
 * Text formatting matching the Android app.
 *
 * Sources:
 *   common/extensions/DateExtensions.kt:139-209
 *     getFormattedShortDayAndMonth -> "MM-dd" (best pattern, "MM/dd" for English)
 *     getWeek                      -> "E" short / "EEEE" full, capitalized
 *     getHour                      -> "h a" when the system uses 12-hour time, else "H:mm"
 *     getHourIn24Format            -> "H"
 *   res/values/strings.xml:1300-1301 (colon and dot separators)
 */

/*
 * Every function that reads a calendar field takes the location's UTC offset. Android passes
 * `location.timeZone` into each of these (DateExtensions.kt's helpers all take a Location), so a
 * forecast for Tokyo prints Tokyo's hours no matter where the phone is. The port used the device's
 * own zone, which only looked right because both test phones sit in Europe/Helsinki and the app
 * opens on Helsinki.
 */

import { i18n } from '@kit.LocalizationKit';
import { localDayOfMonth, localDayOfWeek, localHours, localMinutes, localMonth } from './LocalTime';

/** strings.xml:1301 — a bullet padded with spaces. */
export const DOT_SEPARATOR: string = ' • ';
/** strings.xml:1300 */
export const COLON_SEPARATOR: string = ': ';

const WEEKDAYS_SHORT: string[] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const WEEKDAYS_FULL: string[] =
  ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** DateExtensions.kt:193-196 */
export function getWeek(date: Date, utcOffsetSeconds: number, full: boolean = false): string {
  const day: number = localDayOfWeek(date, utcOffsetSeconds);
  return full ? WEEKDAYS_FULL[day] : WEEKDAYS_SHORT[day];
}

/** DateExtensions.kt:139-144 — "MM-dd" rendered with the English best pattern "MM/dd". */
export function getFormattedShortDayAndMonth(date: Date, utcOffsetSeconds: number): string {
  return pad2(localMonth(date, utcOffsetSeconds) + 1) + '/' + pad2(localDayOfMonth(date, utcOffsetSeconds));
}

function is24Hour(): boolean {
  try {
    return i18n.System.is24HourClock();
  } catch (error) {
    return true;
  }
}

/** DateExtensions.kt:198-205 */
export function getHour(date: Date, utcOffsetSeconds: number): string {
  const hours: number = localHours(date, utcOffsetSeconds);
  if (is24Hour()) {
    return hours.toString() + ':' + pad2(localMinutes(date, utcOffsetSeconds));
  }
  const suffix: string = hours < 12 ? 'AM' : 'PM';
  let h12: number = hours % 12;
  if (h12 === 0) {
    h12 = 12;
  }
  return h12.toString() + ' ' + suffix;
}

/** DateExtensions.kt:207-209 */
export function getHourIn24Format(date: Date, utcOffsetSeconds: number): string {
  return localHours(date, utcOffsetSeconds).toString();
}

/**
 * A wall-clock time including minutes, e.g. "5:09 AM" or "05:09" — the sun/moon rise and set
 * labels (container_main_astro.xml). Unlike getHour, these always show minutes.
 */
export function getClockTime(date: Date, utcOffsetSeconds: number): string {
  const hours: number = localHours(date, utcOffsetSeconds);
  const minutes: string = pad2(localMinutes(date, utcOffsetSeconds));
  if (is24Hour()) {
    return pad2(hours) + ':' + minutes;
  }
  const suffix: string = hours < 12 ? 'AM' : 'PM';
  let h12: number = hours % 12;
  if (h12 === 0) {
    h12 = 12;
  }
  return h12.toString() + ':' + minutes + ' ' + suffix;
}

/*
 * Temperature formatting moved to Units.ets so it honours the selected unit system; these
 * re-exports keep the existing call sites working.
 */
export { formatTemperatureNarrow, formatTemperatureWithUnit, temperatureUnitLabel } from './Units';

/** Percentages, e.g. "40%". */
export function formatPercent(value: number): string {
  return Math.round(value).toString() + '%';
}

/** Abbreviated month names — the `MMM` of a medium date skeleton, English only for now. */
const SHORT_MONTHS: string[] =
  ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * `getFormattedMediumDayAndMonth` — "Aug 7", the leading half of an alert's date range
 * (Alert.getFormattedDates). Printed in the LOCATION's zone, like every other time on this screen.
 */
export function getMediumDayAndMonth(date: Date, utcOffsetSeconds: number): string {
  const shifted = new Date(date.getTime() + utcOffsetSeconds * 1000);
  return SHORT_MONTHS[shifted.getUTCMonth()] + ' ' + shifted.getUTCDate().toString();
}

/** `locale_separator` — ", " in English. */
export const LOCALE_SEPARATOR: string = ', ';

/**
 * TextRelativeClock — the "x minutes ago" line at the top of the header.
 * Source: ui/main/widgets/TextRelativeClock.kt
 */
export function formatRelativeTime(date: Date, now: Date): string {
  const deltaMs: number = now.getTime() - date.getTime();
  const minutes: number = Math.floor(deltaMs / 60000);
  if (minutes < 1) {
    return 'Just now';
  }
  if (minutes < 60) {
    return minutes === 1 ? '1 minute ago' : minutes.toString() + ' minutes ago';
  }
  const hours: number = Math.floor(minutes / 60);
  if (hours < 24) {
    return hours === 1 ? '1 hour ago' : hours.toString() + ' hours ago';
  }
  const days: number = Math.floor(hours / 24);
  return days === 1 ? '1 day ago' : days.toString() + ' days ago';
}
