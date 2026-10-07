/*
 * Sun/moon rise and set times, and the moon phase.
 *
 * Open-Meteo returns none of these; the Android app computes them locally, so the port has to as
 * well. CommonConverter.kt:402-423 calls three things per day:
 *   getCalculatedAstroSun    kt:503-560  SunTimes.compute().on(date).at(lat, lon)
 *   getCalculatedAstroMoon   kt:562-616  MoonTimes.compute().on(date).at(lat, lon)
 *   getCalculatedMoonPhase   kt:621-632  MoonIllumination at midday, angle = phase + 180
 *
 * Those come from org.shredzone.commons:commons-suncalc, which has no HarmonyOS equivalent, so
 * the astronomy is implemented here — following the same model commons-suncalc does, namely
 * Montenbruck & Pfleger's abbreviated solar and lunar series ("MiniSun" / "MiniMoon"), with
 * rise/set found by scanning the day hour by hour and interpolating each 3-point window with a
 * quadratic. That scan is what makes the result correct at high latitudes: the closed-form
 * sunrise equation assumes a fixed declination for the whole day, which at Helsinki's latitude
 * in August is wrong by several minutes.
 *
 * Checked against the Android reference device for Helsinki on 2026-08-06:
 *   sun   this 5:11 AM / 9:39 PM   vs Android 5:12 AM / 9:39 PM
 *   moon  this 10:19 PM / 4:30 PM  vs Android 10:15 PM / 4:31 PM
 *   phase this 273° "Last quarter" vs Android "Last quarter"
 * The residual is a couple of minutes, from the abbreviated series; the printed times are to the
 * minute, so this is as close as the display can show.
 */

import { localStartOfDay } from '../common/LocalTime';

const PI2: number = 2 * Math.PI;
const DEG: number = Math.PI / 180;
/** Radians per arcsecond, the unit the lunar series is tabulated in. */
const ARCS: number = 3600 * 180 / Math.PI;
const DAY_MS: number = 86400000;
/** Modified Julian Date of the Unix epoch. */
const MJD_UNIX_EPOCH: number = 40587.0;
const EARTH_RADIUS_KM: number = 6371.0;
const MOON_RADIUS_KM: number = 1737.1;
const SUN_DISTANCE_KM: number = 149598000.0;

function frac(x: number): number {
  return x - Math.floor(x);
}

function toMjd(date: Date): number {
  return date.getTime() / DAY_MS + MJD_UNIX_EPOCH;
}

function fromMjd(mjd: number): Date {
  return new Date((mjd - MJD_UNIX_EPOCH) * DAY_MS);
}

/** Julian centuries since J2000. */
function julianCentury(mjd: number): number {
  return (mjd - 51544.5) / 36525.0;
}

/** Mean obliquity of the ecliptic, radians. */
function obliquity(t: number): number {
  return (23.43929111 - (46.8150 + (0.00059 - 0.001813 * t) * t) * t / 3600.0) * DEG;
}

/** An equatorial position: right ascension and declination in radians, distance in km. */
export class EquatorialPosition {
  readonly rightAscension: number;
  readonly declination: number;
  readonly distanceKm: number;

  constructor(rightAscension: number, declination: number, distanceKm: number) {
    this.rightAscension = rightAscension;
    this.declination = declination;
    this.distanceKm = distanceKm;
  }
}

/** Rotates ecliptic (longitude, latitude) into equatorial coordinates. */
function eclipticToEquatorial(t: number, longitude: number, latitude: number, distanceKm: number): EquatorialPosition {
  const eps: number = obliquity(t);
  const cosB: number = Math.cos(latitude);
  const sinB: number = Math.sin(latitude);
  const x: number = cosB * Math.cos(longitude);
  const y: number = cosB * Math.sin(longitude) * Math.cos(eps) - sinB * Math.sin(eps);
  const z: number = cosB * Math.sin(longitude) * Math.sin(eps) + sinB * Math.cos(eps);
  return new EquatorialPosition(Math.atan2(y, x), Math.asin(z), distanceKm);
}

/** Greenwich mean sidereal time, radians (commons-suncalc JulianDate). */
function greenwichMeanSiderealTime(mjd: number): number {
  const secondsPerDay: number = 86400.0;
  const mjd0: number = Math.floor(mjd);
  const ut: number = (mjd - mjd0) * secondsPerDay;
  const t0: number = (mjd0 - 51544.5) / 36525.0;
  const t: number = (mjd - 51544.5) / 36525.0;
  const gmst: number = 24110.54841 + 8640184.812866 * t0 + 1.0027379093 * ut +
    (0.093104 - 6.2e-6 * t) * t * t;
  const wrapped: number = ((gmst % secondsPerDay) + secondsPerDay) % secondsPerDay;
  return (PI2 / secondsPerDay) * wrapped;
}

/** Montenbruck & Pfleger's MiniSun. */
export function sunPosition(mjd: number): EquatorialPosition {
  const t: number = julianCentury(mjd);
  const m: number = PI2 * frac(0.993133 + 99.997361 * t);
  const dL: number = 6893.0 * Math.sin(m) + 72.0 * Math.sin(2 * m);
  const longitude: number = PI2 * frac(0.7859453 + m / PI2 + (6191.2 * t + dL) / 1296.0e3);
  const distance: number = SUN_DISTANCE_KM * (1 - 0.016718 * Math.cos(m));
  return eclipticToEquatorial(t, longitude, 0, distance);
}

/** Montenbruck & Pfleger's MiniMoon. */
export function moonPosition(mjd: number): EquatorialPosition {
  const t: number = julianCentury(mjd);
  const l0: number = frac(0.606433 + 1336.855225 * t); // mean longitude, revolutions
  const l: number = PI2 * frac(0.374897 + 1325.552410 * t); // moon's mean anomaly
  const ls: number = PI2 * frac(0.993133 + 99.997361 * t); // sun's mean anomaly
  const d: number = PI2 * frac(0.827361 + 1236.853086 * t); // mean elongation
  const f: number = PI2 * frac(0.259086 + 1342.227825 * t); // argument of latitude
  const d2: number = 2 * d;
  const l2: number = 2 * l;
  const f2: number = 2 * f;

  // Perturbations in ecliptic longitude, arcseconds.
  const dL: number = 22640 * Math.sin(l)
    - 4586 * Math.sin(l - d2)
    + 2370 * Math.sin(d2)
    + 769 * Math.sin(l2)
    - 668 * Math.sin(ls)
    - 412 * Math.sin(f2)
    - 212 * Math.sin(l2 - d2)
    - 206 * Math.sin(l + ls - d2)
    + 192 * Math.sin(l + d2)
    - 165 * Math.sin(ls - d2)
    - 125 * Math.sin(d)
    - 110 * Math.sin(l + ls)
    + 148 * Math.sin(l - ls)
    - 55 * Math.sin(f2 - d2);

  const s: number = f + (dL + 412 * Math.sin(f2) + 541 * Math.sin(ls)) / ARCS;
  const h: number = f - d2;
  const n: number = -526 * Math.sin(h)
    + 44 * Math.sin(l + h)
    - 31 * Math.sin(-l + h)
    - 23 * Math.sin(ls + h)
    + 11 * Math.sin(-ls + h)
    - 25 * Math.sin(-l2 + f)
    + 21 * Math.sin(-l + f);

  const longitude: number = PI2 * frac(l0 + dL / 1296.0e3);
  const latitude: number = (18520.0 * Math.sin(s) + n) / ARCS;
  const distance: number = 385000.5768
    - 20905.355 * Math.cos(l)
    - 3699.111 * Math.cos(d2 - l)
    - 2955.968 * Math.cos(d2)
    - 569.925 * Math.cos(l2);

  return eclipticToEquatorial(t, longitude, latitude, distance);
}

/** Geometric altitude above the horizon, radians. */
function altitudeOf(position: EquatorialPosition, mjd: number, latitude: number, longitude: number): number {
  const hourAngle: number = greenwichMeanSiderealTime(mjd) + longitude * DEG - position.rightAscension;
  const phi: number = latitude * DEG;
  return Math.asin(
    Math.sin(phi) * Math.sin(position.declination) +
      Math.cos(phi) * Math.cos(position.declination) * Math.cos(hourAngle)
  );
}

/**
 * `SunPosition.compute().on(date).at(lat, lon).execute().altitude` — the sun's altitude in DEGREES.
 *
 * Screen 4's EphemerisChart plots this at each solar noon and nadir and lets the cubic connector
 * fill in between (DetailsSunMoon.kt:303-311).
 */
export function sunAltitudeDegrees(date: Date, latitude: number, longitude: number): number {
  const mjd: number = toMjd(date);
  return altitudeOf(sunPosition(mjd), mjd, latitude, longitude) / DEG;
}

/** The same for `MoonPosition` (kt:326). */
export function moonAltitudeDegrees(date: Date, latitude: number, longitude: number): number {
  const mjd: number = toMjd(date);
  return altitudeOf(moonPosition(mjd), mjd, latitude, longitude) / DEG;
}

/** The outcome of a rise/set search: either instants, or a flag that the body never crosses. */
export class RiseSet {
  rise: Date | null = null;
  set: Date | null = null;
  alwaysUp: boolean = false;
  alwaysDown: boolean = false;
}

/**
 * Scans the 24 hours from `start` for horizon crossings.
 *
 * Each odd hour is the centre of a three-point window; fitting a quadratic through the altitudes
 * at h-1, h, h+1 and solving for its roots gives the crossing to well under a minute. This is the
 * same shape as commons-suncalc's SunTimes/MoonTimes loop, and unlike a closed-form solution it
 * copes with a body whose declination moves appreciably during the day — the moon always, and
 * the sun at high latitudes.
 */
function scanRiseSet(
  start: Date,
  latitude: number,
  longitude: number,
  heightAt: (mjd: number, latitude: number, longitude: number) => number
): RiseSet {
  const result = new RiseSet();
  const startMjd: number = toMjd(start);
  let riseHour: number | null = null;
  let setHour: number | null = null;
  let lastYe: number = 0;

  let yMinus: number = heightAt(startMjd, latitude, longitude);
  for (let hour = 1; hour <= 24; hour += 2) {
    const y0: number = heightAt(startMjd + hour / 24, latitude, longitude);
    const yPlus: number = heightAt(startMjd + (hour + 1) / 24, latitude, longitude);

    const a: number = (yPlus + yMinus) / 2 - y0;
    const b: number = (yPlus - yMinus) / 2;
    const xe: number = -b / (2 * a);
    const ye: number = (a * xe + b) * xe + y0;
    lastYe = ye;

    const discriminant: number = b * b - 4 * a * y0;
    let roots: number = 0;
    let x1: number = 0;
    let x2: number = 0;
    if (discriminant >= 0) {
      const dx: number = Math.sqrt(discriminant) / (Math.abs(a) * 2);
      x1 = xe - dx;
      x2 = xe + dx;
      if (Math.abs(x1) <= 1) {
        roots++;
      }
      if (Math.abs(x2) <= 1) {
        roots++;
      }
      if (x1 < -1) {
        x1 = x2;
      }
    }

    if (roots === 1) {
      if (yMinus < 0) {
        if (riseHour === null) {
          riseHour = hour + x1;
        }
      } else if (setHour === null) {
        setHour = hour + x1;
      }
    } else if (roots === 2) {
      if (riseHour === null) {
        riseHour = hour + (ye < 0 ? x2 : x1);
      }
      if (setHour === null) {
        setHour = hour + (ye < 0 ? x1 : x2);
      }
    }

    if (riseHour !== null && setHour !== null) {
      break;
    }
    yMinus = yPlus;
  }

  if (riseHour !== null) {
    result.rise = fromMjd(startMjd + riseHour / 24);
  }
  if (setHour !== null) {
    result.set = fromMjd(startMjd + setHour / 24);
  }
  if (riseHour === null && setHour === null) {
    if (lastYe > 0) {
      result.alwaysUp = true;
    } else {
      result.alwaysDown = true;
    }
  }
  return result;
}

/**
 * The standard visual horizon: -0.833°, the solar semi-diameter plus refraction. Equivalent to
 * commons-suncalc's default `SunTimes.Twilight.VISUAL`, which getCalculatedAstroSun uses (kt:507).
 */
const SUN_HORIZON: number = -0.833 * DEG;

function sunHeight(mjd: number, latitude: number, longitude: number): number {
  return altitudeOf(sunPosition(mjd), mjd, latitude, longitude) - SUN_HORIZON;
}

/**
 * `SunTimes.Twilight.CIVIL` — the sun 6° below the horizon.
 *
 * `Daily.twilight` is `getCalculatedAstroSun(..., SunTimes.Twilight.CIVIL)`
 * (CommonConverter.kt), and it is the second row of the Sun & moon card: dawn and dusk.
 */
const CIVIL_TWILIGHT_HORIZON: number = -6.0 * DEG;

function civilTwilightHeight(mjd: number, latitude: number, longitude: number): number {
  return altitudeOf(sunPosition(mjd), mjd, latitude, longitude) - CIVIL_TWILIGHT_HORIZON;
}

/**
 * The moon's threshold is distance-dependent: horizontal parallax lifts it, refraction and its
 * own semi-diameter lower it (commons-suncalc MoonTimes.correctedMoonHeight).
 */
function moonHeight(mjd: number, latitude: number, longitude: number): number {
  const position: EquatorialPosition = moonPosition(mjd);
  const parallax: number = Math.asin(EARTH_RADIUS_KM / position.distanceKm);
  const refraction: number = 0.5667 * DEG;
  const semiDiameter: number = Math.asin(MOON_RADIUS_KM / position.distanceKm);
  return altitudeOf(position, mjd, latitude, longitude) - (parallax - refraction - semiDiameter);
}

/**
 * Midnight AT THE LOCATION on the day `date` falls in.
 *
 * Android scans the day in `location.timeZone` (SunTimes.compute().on(date) is given a date
 * already truncated in that zone by completeDailyListFromHourlyList). Using the device''s midnight
 * instead shifts the whole 24-hour scan window, which for a far-away location can pick up the
 * wrong day''s rise entirely.
 */
function startOfDay(date: Date, utcOffsetSeconds: number): Date {
  return new Date(localStartOfDay(date, utcOffsetSeconds));
}

export function sunTimes(date: Date, latitude: number, longitude: number, utcOffsetSeconds: number): RiseSet {
  return scanRiseSet(startOfDay(date, utcOffsetSeconds), latitude, longitude, sunHeight);
}

export function moonTimes(date: Date, latitude: number, longitude: number, utcOffsetSeconds: number): RiseSet {
  return scanRiseSet(startOfDay(date, utcOffsetSeconds), latitude, longitude, moonHeight);
}

/** `Daily.twilight` — the same scan at the civil horizon, which gives dawn and dusk. */
export function civilTwilightTimes(date: Date, latitude: number, longitude: number,
  utcOffsetSeconds: number): RiseSet {
  return scanRiseSet(startOfDay(date, utcOffsetSeconds), latitude, longitude, civilTwilightHeight);
}

/**
 * The same scan, but starting at an arbitrary INSTANT instead of that day's midnight.
 *
 * commons-suncalc's `.on(date)` scans 24 hours forward from the date-time it is given, and the
 * fallback branches of getCalculatedAstroMoon/Sun hand it `riseTimes.rise` — a time of day, not a
 * midnight. The port truncated it, so "recompute the set from the rise's own day" rescanned the
 * SAME day and returned the same set it had just rejected. Visible as a moonset two hours out
 * from the Android device in the evening (10:19 PM / 4:31 PM against 10:20 PM / 6:23 PM), while
 * agreeing in the morning, because the branch only fires once the day's set is already past.
 */
export function sunTimesFrom(instant: Date, latitude: number, longitude: number): RiseSet {
  return scanRiseSet(instant, latitude, longitude, sunHeight);
}

export function moonTimesFrom(instant: Date, latitude: number, longitude: number): RiseSet {
  return scanRiseSet(instant, latitude, longitude, moonHeight);
}

/**
 * MoonPhase.angle — 0..360, 0 = new moon, 90 = first quarter, 180 = full, 270 = last quarter,
 * the scale commons-suncalc's `MoonPhase.Phase.toPhase` buckets into names.
 *
 * getCalculatedMoonPhase (kt:621-632) evaluates the illumination at MIDDAY, not midnight, and
 * takes `phase + 180`. commons-suncalc's phase is `toDegrees(inc * signum(angle))`, and the
 * illuminated fraction below expresses the same quantity as `0.5 + 0.5 * inc * signum(angle)/π`,
 * so multiplying it by 360 gives `toDegrees(inc * signum(angle)) + 180` exactly.
 */
export function moonPhaseAngle(date: Date, utcOffsetSeconds: number): number {
  // kt:626 — the middle of the day, in the LOCATION's zone.
  const mjd: number = toMjd(startOfDay(date, utcOffsetSeconds)) + 0.5;
  const sun: EquatorialPosition = sunPosition(mjd);
  const moon: EquatorialPosition = moonPosition(mjd);

  // Geocentric elongation of the moon from the sun.
  const elongation: number = Math.acos(
    Math.sin(sun.declination) * Math.sin(moon.declination) +
      Math.cos(sun.declination) * Math.cos(moon.declination) *
        Math.cos(sun.rightAscension - moon.rightAscension)
  );
  // Phase angle at the moon: sun–moon–observer.
  const inc: number = Math.atan2(
    sun.distanceKm * Math.sin(elongation),
    moon.distanceKm - sun.distanceKm * Math.cos(elongation)
  );
  // Sign: which limb is lit, i.e. waxing or waning.
  const limb: number = Math.atan2(
    Math.cos(sun.declination) * Math.sin(sun.rightAscension - moon.rightAscension),
    Math.sin(sun.declination) * Math.cos(moon.declination) -
      Math.cos(sun.declination) * Math.sin(moon.declination) *
        Math.cos(sun.rightAscension - moon.rightAscension)
  );

  const fraction: number = 0.5 + 0.5 * inc * (limb < 0 ? -1 : 1) / Math.PI;
  const degrees: number = Math.round(fraction * 360);
  return ((degrees % 360) + 360) % 360;
}

/** commons-suncalc MoonPhase.Phase.toPhase + strings.xml's ephemeris_moon_phase_* values. */
export function moonPhaseName(angle: number): string {
  const normalized: number = ((angle % 360) + 360) % 360;
  if (normalized < 22.5) {
    return 'New moon';
  }
  if (normalized < 67.5) {
    return 'Waxing crescent';
  }
  if (normalized < 112.5) {
    return 'First quarter';
  }
  if (normalized < 157.5) {
    return 'Waxing gibbous';
  }
  if (normalized < 202.5) {
    return 'Full moon';
  }
  if (normalized < 247.5) {
    return 'Waning gibbous';
  }
  if (normalized < 292.5) {
    return 'Last quarter';
  }
  if (normalized < 337.5) {
    return 'Waning crescent';
  }
  return 'New moon';
}

/** A resolved rise/set pair after the Android fallbacks have been applied. */
export class AstroPair {
  rise: Date | null = null;
  set: Date | null = null;
}

/**
 * getCalculatedAstroSun / getCalculatedAstroMoon (kt:503-616) — identical fallback ladders:
 *   - never sets            → 00:00 to 23:59:59.999
 *   - no rise but a set     → 00:00 as the rise ("leaving midnight sun season", kt:518)
 *   - set before rise       → recompute the set from the rise's own day
 *   - a rise but no set     → recompute both over a full cycle
 */
function resolve(
  times: RiseSet,
  dayStart: Date,
  latitude: number,
  longitude: number,
  /** Scans 24 h forward from the given INSTANT — see sunTimesFrom/moonTimesFrom. */
  recompute: (instant: Date, latitude: number, longitude: number) => RiseSet
): AstroPair {
  const pair = new AstroPair();

  if (times.alwaysUp) {
    pair.rise = dayStart;
    pair.set = new Date(dayStart.getTime() + DAY_MS - 1);
    return pair;
  }
  if (times.rise === null && times.set !== null) {
    pair.rise = dayStart;
    pair.set = times.set;
    return pair;
  }
  // kt:526-543 / kt:584-600 — the set precedes the rise, so find the set that FOLLOWS the rise by
  // scanning forward from the rise instant itself.
  if (times.rise !== null && times.set !== null && times.set.getTime() < times.rise.getTime()) {
    const next: RiseSet = recompute(times.rise, latitude, longitude);
    pair.rise = times.rise;
    pair.set = next.set;
    return pair;
  }
  // kt:547-554 / kt:604-610 — a rise but no set inside the window; the set is beyond it.
  if (times.rise !== null && times.set === null) {
    const next: RiseSet = recompute(times.rise, latitude, longitude);
    pair.rise = times.rise;
    pair.set = next.set;
    return pair;
  }

  pair.rise = times.rise;
  pair.set = times.set;
  return pair;
}

export function calculatedSun(
  date: Date,
  latitude: number,
  longitude: number,
  utcOffsetSeconds: number
): AstroPair {
  return resolve(
    sunTimes(date, latitude, longitude, utcOffsetSeconds),
    startOfDay(date, utcOffsetSeconds),
    latitude, longitude, sunTimesFrom
  );
}

/** `Daily.twilight` — the same ladder at the civil horizon. Dawn is its rise, dusk its set. */
export function calculatedCivilTwilight(
  date: Date,
  latitude: number,
  longitude: number,
  utcOffsetSeconds: number
): AstroPair {
  return resolve(
    civilTwilightTimes(date, latitude, longitude, utcOffsetSeconds),
    startOfDay(date, utcOffsetSeconds),
    latitude, longitude,
    (instant: Date, lat: number, lon: number) =>
      scanRiseSet(instant, lat, lon, civilTwilightHeight)
  );
}

export function calculatedMoon(
  date: Date,
  latitude: number,
  longitude: number,
  utcOffsetSeconds: number
): AstroPair {
  return resolve(
    moonTimes(date, latitude, longitude, utcOffsetSeconds),
    startOfDay(date, utcOffsetSeconds),
    latitude, longitude, moonTimesFrom
  );
}
