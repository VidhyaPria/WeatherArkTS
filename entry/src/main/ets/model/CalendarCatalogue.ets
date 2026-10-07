/*
 * The alternate-calendar catalogue — CalendarHelper.kt:55-160.
 *
 * Android builds this list at runtime from ICU: `supportedCalendars` (kt:44-55) mapped through
 * `ULocale.getDisplayKeywordValue`, sorted BY DISPLAY NAME, then "None" inserted at 0 and
 * "Regional preference (…)" at 1.
 *
 * Neither ArkTS nor the NDK can reach ICU's keyword display names, so the English names below were
 * read off the reference's own dialog rather than invented — `uiautomator dump` on
 * AppearanceSettings → Alternate calendar gave all twelve rows verbatim. CLAUDE.md scopes strings
 * to English for now, which is exactly what ICU returns for the `en` locale here. The order is
 * already the sorted one, so nothing re-sorts at runtime.
 */

import { i18n } from '@kit.LocalizationKit';

/**
 * `context.currentLocale` — the device's own locale, which is what decides the regional default.
 * Guarded because `getSystemRegion` throws on some builds rather than returning empty.
 */
export function deviceLanguage(): string {
  try {
    return i18n.System.getSystemLanguage();
  } catch (error) {
    return 'en';
  }
}

export function deviceCountry(): string {
  try {
    return i18n.System.getSystemRegion();
  } catch (error) {
    return '';
  }
}

/** One row of the picker. */
export class CalendarOption {
  /** The stored value. "none", "" for the regional preference, or a Unicode calendar key. */
  readonly id: string;
  readonly name: string;

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

/**
 * The ten real calendars, in the order ICU's display names sort into
 * (CalendarHelper.kt:98 `.sortedBy { it.displayName }`).
 */
const SUPPORTED: CalendarOption[] = [
  new CalendarOption('chinese', 'Chinese Calendar'),
  new CalendarOption('dangi', 'Dangi Calendar'),
  new CalendarOption('hebrew', 'Hebrew Calendar'),
  new CalendarOption('indian', 'Indian National Calendar'),
  new CalendarOption('islamic', 'Islamic Calendar'),
  new CalendarOption('islamic-rgsa', 'Islamic Calendar (Saudi Arabia, sighting)'),
  new CalendarOption('islamic-umalqura', 'Islamic Calendar (Umm al-Qura)'),
  new CalendarOption('islamic-tbla', 'Islamic Calendar (tabular, astronomical epoch)'),
  new CalendarOption('islamic-civil', 'Islamic Calendar (tabular, civil epoch)'),
  new CalendarOption('persian', 'Persian Calendar')
];

/**
 * `getCalendarPreferenceForLocale` (CalendarHelper.kt:118-143) — which calendar the device's own
 * locale implies. Ported rule for rule; everything it does not name falls through to Gregorian,
 * which the list represents as "None".
 */
function regionalPreferenceId(language: string, country: string): string {
  const lang: string = language.toLowerCase();
  const region: string = country.toUpperCase();
  if (region === 'CN' || region === 'HK' || region === 'MO' || region === 'TW' || lang === 'zh') {
    return 'chinese';
  }
  if (region === 'KP' || region === 'KR' || lang === 'ko') {
    return 'dangi';
  }
  if (lang === 'he' || lang === 'iw') {
    return 'hebrew';
  }
  if (region === 'IN') {
    return 'indian';
  }
  if (region === 'SA') {
    return 'islamic-rgsa';
  }
  if (region === 'IR' || lang === 'fa') {
    return 'persian';
  }
  // "Looks like all locales default to Gregorian" (kt:139-141).
  return '';
}

/** The display name for an id, or empty when it is not a real calendar. */
function nameFor(id: string): string {
  for (const option of SUPPORTED) {
    if (option.id === id) {
      return option.name;
    }
  }
  return '';
}

/**
 * The whole list, with "None" first and "Regional preference (…)" second.
 *
 * The parenthesised name is the DEVICE's regional default, so it legitimately differs between the
 * reference phone (which resolved to Chinese) and any other locale — the same class of difference
 * as the reverse geocoder's district. `settings_none` is the fallback when the locale implies
 * Gregorian, which is what kt:112 does.
 */
export function calendarOptions(language: string, country: string): CalendarOption[] {
  const regional: string = regionalPreferenceId(language, country);
  const regionalName: string = regional.length > 0 ? nameFor(regional) : 'None';
  const options: CalendarOption[] = [
    new CalendarOption('none', 'None'), // strings.xml settings_none
    // strings.xml `parenthesis` = "%1$s (%2$s)", with settings_regional_preference.
    new CalendarOption('', 'Regional preference (' + regionalName + ')')
  ];
  for (const option of SUPPORTED) {
    options.push(option);
  }
  return options;
}

/** The row summary for a stored value. */
export function calendarSummary(stored: string, language: string, country: string): string {
  for (const option of calendarOptions(language, country)) {
    if (option.id === stored) {
      return option.name;
    }
  }
  return 'None';
}
