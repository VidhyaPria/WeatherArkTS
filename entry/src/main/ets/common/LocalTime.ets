/*
 * Reading instants in the LOCATION's timezone rather than the device's.
 *
 * Android threads `location.timeZone` through everything that touches a date: which day a
 * forecast entry belongs to (CommonConverter.kt:387-390 `getIsoFormattedDate(location)`), which
 * hours form a half-day (kt:634-661), the hour printed on a trend column, the sunrise label. The
 * port used the device's own timezone for all of it — `Date.getHours()` and friends — which is
 * only correct while the device and the location agree. Both test phones are on Europe/Helsinki
 * and the app opens on Helsinki, so it looked right; Berlin and Tokyo were silently rendered in
 * Finnish time.
 *
 * There is no ZonedDateTime in ArkTS, but the conversion is arithmetic: Open-Meteo already
 * returns `utc_offset_seconds` for the resolved grid cell, so shifting an instant by that offset
 * and then reading the UTC fields gives the location's wall clock. Every helper below is that one
 * trick; nothing here uses the device's zone.
 */

const MS_PER_SECOND: number = 1000;
const MS_PER_MINUTE: number = 60000;
const MS_PER_HOUR: number = 3600000;
const MS_PER_DAY: number = 86400000;

/** The instant shifted so that its UTC fields read as the location's wall clock. */
function shifted(date: Date, utcOffsetSeconds: number): Date {
  return new Date(date.getTime() + utcOffsetSeconds * MS_PER_SECOND);
}

/** Hour of day, 0..23, at the location. */
export function localHours(date: Date, utcOffsetSeconds: number): number {
  return shifted(date, utcOffsetSeconds).getUTCHours();
}

/** Minute of the hour at the location. */
export function localMinutes(date: Date, utcOffsetSeconds: number): number {
  return shifted(date, utcOffsetSeconds).getUTCMinutes();
}

/** Day of the month at the location. */
export function localDayOfMonth(date: Date, utcOffsetSeconds: number): number {
  return shifted(date, utcOffsetSeconds).getUTCDate();
}

/** Month, 0..11, at the location. */
export function localMonth(date: Date, utcOffsetSeconds: number): number {
  return shifted(date, utcOffsetSeconds).getUTCMonth();
}

/** Day of the week, 0 = Sunday, at the location. */
export function localDayOfWeek(date: Date, utcOffsetSeconds: number): number {
  return shifted(date, utcOffsetSeconds).getUTCDay();
}

/**
 * The instant of local midnight starting the day this instant falls in — the equivalent of
 * `getIsoFormattedDate(location)` as a comparable number, and what daily entries are keyed by.
 */
export function localStartOfDay(date: Date, utcOffsetSeconds: number): number {
  const local: Date = shifted(date, utcOffsetSeconds);
  const midnightLocal: number = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate()
  );
  return midnightLocal - utcOffsetSeconds * MS_PER_SECOND;
}

/** The instant of local midnight starting the hour this instant falls in. */
export function localStartOfHour(date: Date, utcOffsetSeconds: number): number {
  const local: Date = shifted(date, utcOffsetSeconds);
  const hourLocal: number = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate(),
    local.getUTCHours()
  );
  return hourLocal - utcOffsetSeconds * MS_PER_SECOND;
}

/** Milliseconds in a day, exported so callers do not re-declare it. */
export const DAY_MS: number = MS_PER_DAY;
export const HOUR_MS: number = MS_PER_HOUR;
export const MINUTE_MS: number = MS_PER_MINUTE;
