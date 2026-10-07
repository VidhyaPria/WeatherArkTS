/*
 * The app's persisted settings — SettingsManager (domain/settings/SettingsManager.kt).
 *
 * Android keeps them in SharedPreferences through a ConfigStore, so this is `@ohos.data.preferences`
 * rather than the relationalStore the weather and location tables use: it is a flat key-value bag
 * read on almost every frame, not something queried.
 *
 * The KEYS and DEFAULTS are the Kotlin's, verbatim, because they decide what a fresh install looks
 * like:
 *   dark_mode                "system"  (SettingsManager.kt:174-181)
 *   day_night_mode_locations Build.VERSION.SDK_INT < Q, i.e. FALSE on anything modern
 *                            (SettingsManager.kt:185-190)
 *
 * That second default is worth stating plainly, because it is the opposite of what it looks like:
 * "follow each location's day/night" is OFF by default on a current device. The reason both ports
 * have looked right while hardcoding the location rule is the branch below — with dark mode on
 * `system` and the system in LIGHT, the theme follows the location's daylight regardless of it.
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UnitFamily, UNIT_AUTO } from '../model/UnitCatalogue';
import { SOURCE_PREFERENCES, sourcePrefKey } from './SourcePreferences';
import {
  DEFAULT_CARD_DISPLAY,
  DEFAULT_DAILY_TREND_DISPLAY,
  DEFAULT_HOURLY_TREND_DISPLAY,
  DisplayList
} from '../model/DisplayCatalogue';

/** DarkMode.kt:24-32 — the ids are what is stored, and what the settings list shows. */
export enum DarkModeSetting {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

/** DarkModeLocation.kt:23-30. Stored as the BOOLEAN, not the id — see SettingsManager.kt:185. */
export enum DarkModeLocationSetting {
  DAY_NIGHT = 'day_night',
  DARK = 'dark'
}

const STORE_NAME: string = 'breezy_settings';
const KEY_DARK_MODE: string = 'dark_mode';
/** SettingsManager.alternateCalendar — "none", "" for the regional default, or a calendar key. */
const KEY_ALTERNATE_CALENDAR: string = 'alternate_calendar';

/*
 * Screen 3e — External modules (ModulesSettingsScreen.kt). SettingsManager's own key names.
 *
 * Every one of these controls something CLAUDE.md scopes out — widgets, the live wallpaper, the
 * notification widget, broadcast data sharing. The SCREEN is still ported, and the values are still
 * stored, for the same reason the source catalogue is ported without its clients: the settings list
 * is what Android renders, and hiding rows would be inventing a different screen.
 */
const KEY_WEEK_ICON_MODE: string = 'week_icon_mode';
const KEY_MONOCHROME_ICONS: string = 'widget_monochrome_icons';
const KEY_NOTIFICATION_WIDGET: string = 'notification_widget_switch';
const KEY_NOTIFICATION_PERSISTENT: string = 'notification_widget_persistent_switch';
const KEY_NOTIFICATION_STYLE: string = 'notification_widget_style';
const KEY_NOTIFICATION_TEMP_ICON: string = 'notification_widget_temp_icon_switch';
const KEY_NOTIFICATION_FEELS_LIKE: string = 'notification_widget_feels_like';
/** One per broadcast source; the stored value is a comma-separated package list, "" for none. */
const KEY_BROADCAST_PREFIX: string = 'broadcast_packages_';

/**
 * The broadcast sources the Data sharing section lists, in `sourceManager` order.
 *
 * These are the two the reference renders — "Send Breezy Weather Location Update Notifier data" and
 * "Send Gadgetbridge data". Each is a MultiListPreference over the INSTALLED packages that declare
 * the source's intent action; with none installed the list is empty and the row reads "Disabled",
 * which is what the reference shows and what both ports will show on a HarmonyOS device.
 */
export const BROADCAST_SOURCE_IDS: string[] = ['breezy', 'gadgetbridge'];
export const BROADCAST_SOURCE_NAMES: string[] =
  ['Breezy Weather Location Update Notifier', 'Gadgetbridge'];
const KEY_DAY_NIGHT_LOCATIONS: string = 'day_night_mode_locations';
/*
 * The five unit overrides — SettingsManager.kt's `temperature_unit` … `pressure_unit`, all
 * defaulting to the string "auto".
 *
 * "auto" is a real stored value, not the absence of one: the Kotlin writes `value?.id ?: "auto"`
 * and reads `getUnit(...)`, which returns null for "auto" and makes the getter fall through to
 * `<Unit>.getDefaultUnit(currentLocale)`. So "auto" means "follow the region", and it has to round
 * -trip as a string rather than be modelled as an empty preference.
 */
/*
 * Screen 3c's six — SettingsManager.kt again, and every one of them defaults to TRUE except the
 * background animation mode, which is the string "system".
 */
const KEY_MAIN_BACKGROUND: string = 'main_screen_background';
const KEY_TREND_LINES: string = 'trend_horizontal_line_switch';
const KEY_BACKGROUND_ANIMATION: string = 'background_animation_mode';
const KEY_GRAVITY_SENSOR: string = 'gravity_sensor_switch';
const KEY_CARDS_FADE_IN: string = 'list_animation_switch';
const KEY_ELEMENT_ANIMATIONS: string = 'item_animation_switch';

/*
 * Screen 3d — Notifications (NotificationsSettingsScreen.kt:55-239). SettingsManager.kt:143-155 and
 * :376-405 for the keys and, importantly, the defaults, which are NOT all the same:
 *
 *   alert_notification_switch          true   (kt:148)
 *   precipitation_notification_switch  false  (kt:155)
 *   timing_forecast_switch_today       false  (kt:381)
 *   timing_forecast_switch_tomorrow    false  (kt:397)
 *   forecast_time_today                "07:00" (DEFAULT_TODAY_FORECAST_TIME, kt:92)
 *   forecast_time_tomorrow             "21:00" (DEFAULT_TOMORROW_FORECAST_TIME, kt:93)
 */
/**
 * kt:109 — `app_update_check_switch`, default FALSE.
 *
 * The section around it is gated on BreezyWeather.isGitHubUpdateCheckerEnabled, which needs
 * BuildConfig.GITHUB_ORG and GITHUB_REPO. Those come from a properties file that is not in the
 * source tree, so reading the source alone suggests the section never renders — but the reference
 * APK was built WITH them, and does show it. Verified on the device, not inferred.
 */
export const NOTIF_KEY_APP_UPDATES: string = 'app_update_check_switch';
export const NOTIF_KEY_ALERT: string = 'alert_notification_switch';
export const NOTIF_KEY_PRECIPITATION: string = 'precipitation_notification_switch';
export const NOTIF_KEY_TODAY: string = 'timing_forecast_switch_today';
export const NOTIF_KEY_TOMORROW: string = 'timing_forecast_switch_tomorrow';
const KEY_TODAY_FORECAST_TIME: string = 'forecast_time_today';
const KEY_TOMORROW_FORECAST_TIME: string = 'forecast_time_tomorrow';
/**
 * The background-update interval (SettingsManager.kt:157-165, `refresh_rate`).
 *
 * Screen 3d only READS it: both general switches are disabled, and re-summarised, when it is
 * "never" (kt:135-145). Its own screen — Background updates — is not ported yet, so nothing writes
 * it. The default is "1:30" on a release build, so the rows are live, which is what the reference
 * device shows.
 */
const KEY_REFRESH_RATE: string = 'refresh_rate';
/** `SettingsManager.ignoreUpdatesWhenBatteryLow` — the Background updates screen's one switch. */
const KEY_SKIP_WHEN_BATTERY_LOW: string = 'ignore_updates_when_battery_low';
export const UPDATE_INTERVAL_NEVER: string = 'never';

/**
 * `automatic_refresh_rate_values` paired with the names the screen actually shows.
 *
 * The names are NOT `automatic_refresh_rates` verbatim: kt:107-115 replaces each with
 * `UpdateInterval.interval.formatTime(smallestUnit = MINUTES, unitWidth = LONG)` and falls back to
 * the array item only when there is no interval, which is "Never" alone. That is why the
 * reference's summary reads "1 hour, 30 minutes" rather than the array's "1 hr and 30 min".
 */
export const UPDATE_INTERVALS: string[] =
  ['never', '0:30', '1:00', '1:30', '2:00', '3:00', '6:00', '12:00', '24:00'];
export const UPDATE_INTERVAL_NAMES: string[] = ['Never', '30 minutes', '1 hour',
  '1 hour, 30 minutes', '2 hours', '3 hours', '6 hours', '12 hours', '24 hours'];

/** The name for a stored id, falling back to the first entry as `indexOfFirst == -1` does. */
export function updateIntervalName(id: string): string {
  const index: number = UPDATE_INTERVALS.indexOf(id);
  return index < 0 ? UPDATE_INTERVAL_NAMES[0] : UPDATE_INTERVAL_NAMES[index];
}

/**
 * `UpdateInterval.validity` in milliseconds, or -1 for INTERVAL_NEVER, whose Duration is null.
 *
 * It is what `Weather.isValid` is measured against, so it decides whether selecting a location
 * refetches at all (`checkToUpdateCurrentLocation`, MainActivityViewModel.kt:279-283). The ids are
 * the enum's own, "0:30" through "24:00" (UpdateInterval.kt).
 */
export function updateIntervalMs(id: string): number {
  if (id === UPDATE_INTERVAL_NEVER) {
    return -1;
  }
  const parts: string[] = id.split(':');
  if (parts.length !== 2) {
    return -1;
  }
  const hours: number = Number.parseInt(parts[0], 10);
  const minutes: number = Number.parseInt(parts[1], 10);
  if (Number.isNaN(hours) || Number.isNaN(minutes)) {
    return -1;
  }
  return (hours * 60 + minutes) * 60 * 1000;
}

/*
 * Screen 3e — Location.
 *
 * `location_service` is SettingsManager.kt:193-198; the default is BuildConfig.DEFAULT_LOCATION_SOURCE,
 * which the reference build resolves to `native` ("Android" in the source catalogue).
 */
const KEY_LOCATION_SERVICE: string = 'location_service';
/**
 * Baidu's API key.
 *
 * Android keeps per-source config in its OWN SharedPreferences file, `SourceConfigStore(context,
 * id)`, under the bare key "apikey" (BaiduIPLocationService.kt:88-93). This port has one
 * preferences bag, so the source id is folded into the key instead. Same value, one file.
 */
const KEY_BAIDU_IP_APIKEY: string = 'source_baidu_ip_apikey';

/**
 * Screen 3f. `default_weather_source` is SettingsManager.defaultForecastSource; "auto" means the
 * catalogue picks per location, which is what applyDefaultPreset already does.
 */
const KEY_DEFAULT_FORECAST_SOURCE: string = 'default_weather_source';

/**
 * The three ordered lists the manage screens edit — SettingsManager.kt:278-311. Stored as the
 * Kotlin stores them: ids joined by "&".
 */
const KEY_CARD_DISPLAY: string = 'card_display';
const KEY_DAILY_TREND_DISPLAY: string = 'daily_trend_display';
const KEY_HOURLY_TREND_DISPLAY: string = 'hourly_trend_display';

const KEY_TEMPERATURE_UNIT: string = 'temperature_unit';
const KEY_PRECIPITATION_UNIT: string = 'precipitation_unit';
const KEY_SPEED_UNIT: string = 'speed_unit';
const KEY_DISTANCE_UNIT: string = 'distance_unit';
const KEY_PRESSURE_UNIT: string = 'pressure_unit';

/**
 * The live values, observable so every screen re-themes the moment one changes.
 *
 * @ObservedV2/@Trace rather than a plain object for the reason the rest of this port documents: a
 * value read in a build has to be trackable, and these are read in three screens' builds.
 */
@ObservedV2
export class AppSettings {
  static readonly instance: AppSettings = new AppSettings();
  @Trace darkMode: string = DarkModeSetting.SYSTEM;
  /**
   * The alternate calendar shown beside the Gregorian date. SettingsManager defaults it to "none"
   * (CalendarHelper.kt:149 treats that as "no alternate calendar at all").
   */
  @Trace alternateCalendar: string = 'none';

  /* Screen 3e — External modules. Defaults are SettingsManager's. */
  @Trace weekIconMode: string = 'auto';
  @Trace monochromeIcons: boolean = false;
  @Trace notificationWidget: boolean = false;
  @Trace notificationPersistent: boolean = true;
  @Trace notificationStyle: string = 'daily';
  @Trace notificationTempIcon: boolean = false;
  @Trace notificationFeelsLike: boolean = false;
  /** Broadcast package lists, keyed by source id. Empty means the source is disabled. */
  @Trace broadcastPackages: Map<string, string> = new Map<string, string>();
  /** SettingsManager.dayNightModeForLocations — false on SDK >= Q, which is the case here. */
  @Trace dayNightForLocations: boolean = false;
  /** The ability's colour mode, refreshed with the settings so the rule below has both halves. */
  @Trace systemDark: boolean = false;
  /*
   * The unit overrides, each holding a unit id or UNIT_AUTO. @Trace for the usual reason: they are
   * read while formatting values that the weather screen builds, so a change has to re-render it.
   */
  /*
   * Screen 3c. All four switches default to TRUE (SettingsManager's `getBoolean(key, true)`), and
   * the background animation mode to "system".
   */
  @Trace mainScreenBackground: boolean = true;
  @Trace trendHorizontalLines: boolean = true;
  @Trace backgroundAnimation: string = 'system';
  @Trace gravitySensor: boolean = true;
  @Trace cardsFadeIn: boolean = true;
  @Trace elementAnimations: boolean = true;

  /* Screen 3d — Notifications. Defaults are per-key; see the constants above. */
  @Trace appUpdateCheck: boolean = false;
  @Trace alertNotification: boolean = true;
  /** kt:155 — this one defaults to FALSE, unlike the alert switch above it. */
  @Trace precipitationNotification: boolean = false;
  @Trace todayForecast: boolean = false;
  @Trace tomorrowForecast: boolean = false;
  @Trace todayForecastTime: string = '07:00';
  @Trace tomorrowForecastTime: string = '21:00';
  /** Read-only here until the Background updates screen is ported. */
  @Trace refreshRate: string = '1:30';
  /** `ignoreUpdatesWhenBatteryLow` — SettingsManager's default is true. */
  @Trace skipWhenBatteryLow: boolean = true;

  /*
   * The three manage-screen lists, as the "&"-joined id strings Android stores. Kept in their
   * stored form rather than as parsed arrays so a @Trace write is one assignment — an array's
   * mutations would not notify, which is the trap this port keeps rediscovering.
   */
  @Trace cardDisplay: string = DEFAULT_CARD_DISPLAY;
  @Trace dailyTrendDisplay: string = DEFAULT_DAILY_TREND_DISPLAY;
  @Trace hourlyTrendDisplay: string = DEFAULT_HOURLY_TREND_DISPLAY;

  /* Screen 3e — Location. */
  @Trace locationService: string = 'native';
  @Trace baiduIpApiKey: string = '';

  /* Screen 3f — Weather sources. */
  @Trace defaultForecastSource: string = 'auto';
  /**
   * Every configurable source's own values, keyed by `sourcePrefKey(sourceId, key)`.
   *
   * A map rather than ~50 named fields, because Android does not have named fields for these
   * either — each source owns a `SourceConfigStore(id)` and the screen renders whatever
   * `getPreferences` returns. A Map's mutations are not observable, so screen 3f redraws off a
   * revision counter, the way LocationSettings already does.
   */
  readonly sourcePrefs: Map<string, string> = new Map<string, string>();

  @Trace temperatureUnit: string = 'auto';
  @Trace precipitationUnit: string = 'auto';
  @Trace speedUnit: string = 'auto';
  @Trace distanceUnit: string = 'auto';
  @Trace pressureUnit: string = 'auto';
}

let store: preferences.Preferences | null = null;

/** Opens the bag and loads what is in it. A failure leaves the Kotlin's defaults in place. */
export async function loadSettings(context: common.UIAbilityContext): Promise<void> {
  try {
    store = await preferences.getPreferences(context, STORE_NAME);
    const settings: AppSettings = AppSettings.instance;
    settings.darkMode = await store.get(KEY_DARK_MODE, DarkModeSetting.SYSTEM) as string;
    settings.alternateCalendar = await store.get(KEY_ALTERNATE_CALENDAR, 'none') as string;
    settings.weekIconMode = await store.get(KEY_WEEK_ICON_MODE, 'auto') as string;
    settings.monochromeIcons = await store.get(KEY_MONOCHROME_ICONS, false) as boolean;
    settings.notificationWidget = await store.get(KEY_NOTIFICATION_WIDGET, false) as boolean;
    settings.notificationPersistent =
      await store.get(KEY_NOTIFICATION_PERSISTENT, true) as boolean;
    settings.notificationStyle = await store.get(KEY_NOTIFICATION_STYLE, 'daily') as string;
    settings.notificationTempIcon = await store.get(KEY_NOTIFICATION_TEMP_ICON, false) as boolean;
    settings.notificationFeelsLike =
      await store.get(KEY_NOTIFICATION_FEELS_LIKE, false) as boolean;
    const packages: Map<string, string> = new Map<string, string>();
    for (const source of BROADCAST_SOURCE_IDS) {
      packages.set(source, await store.get(KEY_BROADCAST_PREFIX + source, '') as string);
    }
    settings.broadcastPackages = packages;
    settings.dayNightForLocations = await store.get(KEY_DAY_NIGHT_LOCATIONS, false) as boolean;
    settings.mainScreenBackground = await store.get(KEY_MAIN_BACKGROUND, true) as boolean;
    settings.trendHorizontalLines = await store.get(KEY_TREND_LINES, true) as boolean;
    settings.backgroundAnimation = await store.get(KEY_BACKGROUND_ANIMATION, 'system') as string;
    settings.gravitySensor = await store.get(KEY_GRAVITY_SENSOR, true) as boolean;
    settings.cardsFadeIn = await store.get(KEY_CARDS_FADE_IN, true) as boolean;
    settings.elementAnimations = await store.get(KEY_ELEMENT_ANIMATIONS, true) as boolean;
    settings.appUpdateCheck = await store.get(NOTIF_KEY_APP_UPDATES, false) as boolean;
    settings.alertNotification = await store.get(NOTIF_KEY_ALERT, true) as boolean;
    settings.precipitationNotification =
      await store.get(NOTIF_KEY_PRECIPITATION, false) as boolean;
    settings.todayForecast = await store.get(NOTIF_KEY_TODAY, false) as boolean;
    settings.tomorrowForecast = await store.get(NOTIF_KEY_TOMORROW, false) as boolean;
    settings.todayForecastTime = await store.get(KEY_TODAY_FORECAST_TIME, '07:00') as string;
    settings.tomorrowForecastTime = await store.get(KEY_TOMORROW_FORECAST_TIME, '21:00') as string;
    settings.refreshRate = await store.get(KEY_REFRESH_RATE, '1:30') as string;
  settings.skipWhenBatteryLow = await store.get(KEY_SKIP_WHEN_BATTERY_LOW, true) as boolean;
    settings.locationService = await store.get(KEY_LOCATION_SERVICE, 'native') as string;
    settings.baiduIpApiKey = await store.get(KEY_BAIDU_IP_APIKEY, '') as string;
    settings.defaultForecastSource =
      await store.get(KEY_DEFAULT_FORECAST_SOURCE, 'auto') as string;
    settings.cardDisplay = await store.get(KEY_CARD_DISPLAY, DEFAULT_CARD_DISPLAY) as string;
    settings.dailyTrendDisplay =
      await store.get(KEY_DAILY_TREND_DISPLAY, DEFAULT_DAILY_TREND_DISPLAY) as string;
    settings.hourlyTrendDisplay =
      await store.get(KEY_HOURLY_TREND_DISPLAY, DEFAULT_HOURLY_TREND_DISPLAY) as string;
    await loadSourcePrefs(settings);
    settings.temperatureUnit = await store.get(KEY_TEMPERATURE_UNIT, UNIT_AUTO) as string;
    settings.precipitationUnit = await store.get(KEY_PRECIPITATION_UNIT, UNIT_AUTO) as string;
    settings.speedUnit = await store.get(KEY_SPEED_UNIT, UNIT_AUTO) as string;
    settings.distanceUnit = await store.get(KEY_DISTANCE_UNIT, UNIT_AUTO) as string;
    settings.pressureUnit = await store.get(KEY_PRESSURE_UNIT, UNIT_AUTO) as string;
  } catch (error) {
    console.error('settings unavailable: ' + (error as Error).message);
  }
}

/**
 * Screen 3e's settings. One entry point for all of them, keyed the way screen 3b's units are: the
 * screen already knows the preference key, so a branch per row here would be seven copies of the
 * same three lines.
 */
export async function setModuleSetting(key: string, value: string | boolean): Promise<void> {
  const settings = AppSettings.instance;
  if (key === KEY_WEEK_ICON_MODE) {
    settings.weekIconMode = value as string;
  } else if (key === KEY_MONOCHROME_ICONS) {
    settings.monochromeIcons = value as boolean;
  } else if (key === KEY_NOTIFICATION_WIDGET) {
    settings.notificationWidget = value as boolean;
  } else if (key === KEY_NOTIFICATION_PERSISTENT) {
    settings.notificationPersistent = value as boolean;
  } else if (key === KEY_NOTIFICATION_STYLE) {
    settings.notificationStyle = value as string;
  } else if (key === KEY_NOTIFICATION_TEMP_ICON) {
    settings.notificationTempIcon = value as boolean;
  } else if (key === KEY_NOTIFICATION_FEELS_LIKE) {
    settings.notificationFeelsLike = value as boolean;
  } else if (key.startsWith(KEY_BROADCAST_PREFIX)) {
    // A fresh Map, not a mutation: ArkUI V2 sees a REASSIGNMENT, never an in-place edit.
    const next: Map<string, string> = new Map<string, string>();
    settings.broadcastPackages.forEach((existing: string, id: string) => {
      next.set(id, existing);
    });
    next.set(key.substring(KEY_BROADCAST_PREFIX.length), value as string);
    settings.broadcastPackages = next;
  } else {
    return;
  }
  if (store === null) {
    return;
  }
  try {
    await store.put(key, value);
    await store.flush();
  } catch (error) {
    console.error('could not store ' + key + ': ' + (error as Error).message);
  }
}

export async function setAlternateCalendar(value: string): Promise<void> {
  AppSettings.instance.alternateCalendar = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_ALTERNATE_CALENDAR, value);
    await store.flush();
  } catch (error) {
    console.error('could not store alternate_calendar: ' + (error as Error).message);
  }
}

export async function setDarkMode(value: string): Promise<void> {
  AppSettings.instance.darkMode = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_DARK_MODE, value);
    await store.flush();
  } catch (error) {
    console.error('could not store dark_mode: ' + (error as Error).message);
  }
}

/**
 * Screen 3d's four booleans. Same shape as setMainScreenFlag below, and separate from it for the
 * same reason the screens are separate: the keys have different defaults and different owners.
 */
export async function setNotificationFlag(key: string, value: boolean): Promise<void> {
  const settings: AppSettings = AppSettings.instance;
  if (key === NOTIF_KEY_APP_UPDATES) {
    settings.appUpdateCheck = value;
  } else if (key === NOTIF_KEY_ALERT) {
    settings.alertNotification = value;
  } else if (key === NOTIF_KEY_PRECIPITATION) {
    settings.precipitationNotification = value;
  } else if (key === NOTIF_KEY_TODAY) {
    settings.todayForecast = value;
  } else if (key === NOTIF_KEY_TOMORROW) {
    settings.tomorrowForecast = value;
  }
  if (store === null) {
    return;
  }
  try {
    await store.put(key, value);
    await store.flush();
  } catch (error) {
    console.error('could not store ' + key + ': ' + (error as Error).message);
  }
}

/** The two forecast times, stored as "HH:mm" exactly as the Kotlin does. */
export async function setForecastTime(today: boolean, value: string): Promise<void> {
  const settings: AppSettings = AppSettings.instance;
  if (today) {
    settings.todayForecastTime = value;
  } else {
    settings.tomorrowForecastTime = value;
  }
  if (store === null) {
    return;
  }
  try {
    await store.put(today ? KEY_TODAY_FORECAST_TIME : KEY_TOMORROW_FORECAST_TIME, value);
    await store.flush();
  } catch (error) {
    console.error('could not store forecast time: ' + (error as Error).message);
  }
}

/** Screen 3e's location source (`location_service`). */
export async function setLocationService(value: string): Promise<void> {
  AppSettings.instance.locationService = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_LOCATION_SERVICE, value);
    await store.flush();
  } catch (error) {
    console.error('could not store location_service: ' + (error as Error).message);
  }
}

/**
 * Screen 3c's refresh rate — `SettingsManager.updateInterval`, written by the Background updates
 * screen (BackgroundUpdatesSettingsScreen.kt:127-137).
 *
 * Android follows the write with `WeatherUpdateJob.setupTask(context)`, which reschedules the
 * WorkManager job. This port runs no background job — CLAUDE.md skips background refresh — so the
 * value is stored and read, and what reads it is `Weather.isValid`: the interval decides whether
 * selecting a location refetches at all.
 */
export async function setRefreshRate(value: string): Promise<void> {
  AppSettings.instance.refreshRate = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_REFRESH_RATE, value);
    await store.flush();
  } catch (error) {
    console.error('could not store refresh_rate: ' + (error as Error).message);
  }
}

/** `SettingsManager.ignoreUpdatesWhenBatteryLow` (kt:223-228). */
export async function setSkipWhenBatteryLow(value: boolean): Promise<void> {
  AppSettings.instance.skipWhenBatteryLow = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_SKIP_WHEN_BATTERY_LOW, value);
    await store.flush();
  } catch (error) {
    console.error('could not store ignore_updates_when_battery_low: ' + (error as Error).message);
  }
}

/** Screen 3e's Baidu API key — see the key's comment for where Android keeps it. */
export async function setBaiduIpApiKey(value: string): Promise<void> {
  AppSettings.instance.baiduIpApiKey = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_BAIDU_IP_APIKEY, value);
    await store.flush();
  } catch (error) {
    console.error('could not store the Baidu API key: ' + (error as Error).message);
  }
}

/* --------------------------------------------------- screen 3f: weather sources -------------- */

/**
 * Writes one manage-screen list, as the "&"-joined id string.
 *
 * Android writes on `onStop` (CardDisplayManageActivity.kt:186-199) rather than per edit, and only
 * when the list actually changed. This port writes on the same trigger — the manage page's
 * `onPageHide` — for the same reason: a drag produces a write per frame otherwise.
 */
export async function setDisplayList(list: DisplayList, value: string): Promise<void> {
  const settings: AppSettings = AppSettings.instance;
  let key: string = KEY_CARD_DISPLAY;
  if (list === DisplayList.BLOCKS) {
    settings.cardDisplay = value;
  } else if (list === DisplayList.DAILY) {
    key = KEY_DAILY_TREND_DISPLAY;
    settings.dailyTrendDisplay = value;
  } else {
    key = KEY_HOURLY_TREND_DISPLAY;
    settings.hourlyTrendDisplay = value;
  }
  if (store === null) {
    return;
  }
  try {
    await store.put(key, value);
    await store.flush();
  } catch (error) {
    console.error('could not store ' + key + ': ' + (error as Error).message);
  }
}

/** What is stored for one list, in its "&"-joined form. */
export function displayListValue(list: DisplayList): string {
  const settings: AppSettings = AppSettings.instance;
  if (list === DisplayList.BLOCKS) {
    return settings.cardDisplay;
  }
  return list === DisplayList.DAILY ? settings.dailyTrendDisplay : settings.hourlyTrendDisplay;
}

export async function setDefaultForecastSource(value: string): Promise<void> {
  AppSettings.instance.defaultForecastSource = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_DEFAULT_FORECAST_SOURCE, value);
    await store.flush();
  } catch (error) {
    console.error('could not store the default forecast source: ' + (error as Error).message);
  }
}

/**
 * Every source preference in one pass at startup.
 *
 * Reading the whole table is cheaper than a lookup per row while scrolling, and there are only ~50
 * short strings in it. Absent keys stay absent: a missing entry is what "not configured" means, and
 * an instance row then shows its own default URL.
 */
async function loadSourcePrefs(settings: AppSettings): Promise<void> {
  if (store === null) {
    return;
  }
  settings.sourcePrefs.clear();
  for (const section of SOURCE_PREFERENCES) {
    for (const spec of section.prefs) {
      const key: string = sourcePrefKey(section.sourceId, spec.key);
      try {
        const value = await store.get(key, '') as string;
        if (value.length > 0) {
          settings.sourcePrefs.set(key, value);
        }
      } catch (error) {
        console.error('could not read ' + key + ': ' + (error as Error).message);
      }
    }
  }
}

/** What a source preference currently holds, or '' when it has never been set. */
export function sourcePrefValue(sourceId: string, key: string): string {
  const stored: string | undefined =
    AppSettings.instance.sourcePrefs.get(sourcePrefKey(sourceId, key));
  return stored !== undefined ? stored : '';
}

/**
 * Writes one source preference. An empty value REMOVES it, which is how Android clears a config
 * (`config.edit().remove(...)` — ClimWebService.kt:366-368), so the row goes back to its default.
 */
export async function setSourcePref(
  sourceId: string,
  key: string,
  value: string
): Promise<void> {
  const storeKey: string = sourcePrefKey(sourceId, key);
  if (value.length > 0) {
    AppSettings.instance.sourcePrefs.set(storeKey, value);
  } else {
    AppSettings.instance.sourcePrefs.delete(storeKey);
  }
  if (store === null) {
    return;
  }
  try {
    if (value.length > 0) {
      await store.put(storeKey, value);
    } else {
      await store.delete(storeKey);
    }
    await store.flush();
  } catch (error) {
    console.error('could not store ' + storeKey + ': ' + (error as Error).message);
  }
}

export async function setDayNightForLocations(value: boolean): Promise<void> {
  AppSettings.instance.dayNightForLocations = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_DAY_NIGHT_LOCATIONS, value);
    await store.flush();
  } catch (error) {
    console.error('could not store day_night_mode_locations: ' + (error as Error).message);
  }
}

/**
 * Screen 3c's booleans, written through one function because they differ only by key.
 *
 * The @Trace field is set FIRST and the file written after, so the row redraws on the tap rather
 * than a frame later when the preferences write lands.
 */
export async function setMainScreenFlag(key: string, value: boolean): Promise<void> {
  const settings: AppSettings = AppSettings.instance;
  if (key === KEY_MAIN_BACKGROUND) {
    settings.mainScreenBackground = value;
  } else if (key === KEY_TREND_LINES) {
    settings.trendHorizontalLines = value;
  } else if (key === KEY_GRAVITY_SENSOR) {
    settings.gravitySensor = value;
  } else if (key === KEY_CARDS_FADE_IN) {
    settings.cardsFadeIn = value;
  } else if (key === KEY_ELEMENT_ANIMATIONS) {
    settings.elementAnimations = value;
  } else {
    return;
  }
  if (store === null) {
    return;
  }
  try {
    await store.put(key, value);
    await store.flush();
  } catch (error) {
    console.error('could not store ' + key + ': ' + (error as Error).message);
  }
}

export async function setBackgroundAnimation(value: string): Promise<void> {
  AppSettings.instance.backgroundAnimation = value;
  if (store === null) {
    return;
  }
  try {
    await store.put(KEY_BACKGROUND_ANIMATION, value);
    await store.flush();
  } catch (error) {
    console.error('could not store background_animation_mode: ' + (error as Error).message);
  }
}

/** The keys screen 3c writes, exported so the screen names them rather than repeating literals. */
export const MAIN_KEY_BACKGROUND: string = KEY_MAIN_BACKGROUND;
export const MAIN_KEY_TREND_LINES: string = KEY_TREND_LINES;
export const MAIN_KEY_GRAVITY: string = KEY_GRAVITY_SENSOR;
export const MAIN_KEY_FADE_IN: string = KEY_CARDS_FADE_IN;
export const MAIN_KEY_ELEMENTS: string = KEY_ELEMENT_ANIMATIONS;

/**
 * The stored id for a family, or UNIT_AUTO.
 *
 * Reading through the family rather than five near-identical getters keeps the settings screen a
 * loop over five rows instead of five copies of the same row — which is what the Kotlin's
 * `listPreferenceItem` blocks are, minus the repetition.
 */
export function unitSetting(family: UnitFamily): string {
  const settings: AppSettings = AppSettings.instance;
  if (family === UnitFamily.TEMPERATURE) {
    return settings.temperatureUnit;
  }
  if (family === UnitFamily.PRECIPITATION) {
    return settings.precipitationUnit;
  }
  if (family === UnitFamily.SPEED) {
    return settings.speedUnit;
  }
  if (family === UnitFamily.DISTANCE) {
    return settings.distanceUnit;
  }
  return settings.pressureUnit;
}

function unitKey(family: UnitFamily): string {
  if (family === UnitFamily.TEMPERATURE) {
    return KEY_TEMPERATURE_UNIT;
  }
  if (family === UnitFamily.PRECIPITATION) {
    return KEY_PRECIPITATION_UNIT;
  }
  if (family === UnitFamily.SPEED) {
    return KEY_SPEED_UNIT;
  }
  if (family === UnitFamily.DISTANCE) {
    return KEY_DISTANCE_UNIT;
  }
  return KEY_PRESSURE_UNIT;
}

export async function setUnitSetting(family: UnitFamily, value: string): Promise<void> {
  const settings: AppSettings = AppSettings.instance;
  if (family === UnitFamily.TEMPERATURE) {
    settings.temperatureUnit = value;
  } else if (family === UnitFamily.PRECIPITATION) {
    settings.precipitationUnit = value;
  } else if (family === UnitFamily.SPEED) {
    settings.speedUnit = value;
  } else if (family === UnitFamily.DISTANCE) {
    settings.distanceUnit = value;
  } else {
    settings.pressureUnit = value;
  }
  if (store === null) {
    return;
  }
  try {
    await store.put(unitKey(family), value);
    await store.flush();
  } catch (error) {
    console.error('could not store ' + unitKey(family) + ': ' + (error as Error).message);
  }
}

/**
 * The app's effective dark mode — what `isSystemInDarkTheme()` answers inside the app once
 * `AppCompatDelegate.setDefaultNightMode` has been applied (AppearanceSettingsScreen.kt:194).
 *
 * This is what the SETTINGS screens theme from, because SettingsActivity takes BreezyWeatherTheme's
 * default rather than the location's daylight.
 */
export function appIsDark(): boolean {
  const settings: AppSettings = AppSettings.instance;
  if (settings.darkMode === DarkModeSetting.DARK) {
    return true;
  }
  if (settings.darkMode === DarkModeSetting.LIGHT) {
    return false;
  }
  return settings.systemDark;
}

/**
 * ThemeManager.isLightTheme (ThemeManager.kt:68-84), verbatim:
 *
 *   LIGHT  -> daylight
 *   DARK   -> dayNightModeForLocations && daylight
 *   SYSTEM -> systemDark ? (dayNightModeForLocations && daylight) : daylight
 *
 * The Kotlin's own comment (kt:61-67) is the readable form: when dark mode is "always light" a
 * location is light by day and dark by night; when it is "always dark" the location rule only
 * applies if day/night for locations is on; and "follow system" applies whichever of those two the
 * system is currently in.
 *
 * `daylight` is null when there is no location to ask, and `daylight == true` is false then — so a
 * port with no location resolves to the dark theme, exactly as the Kotlin's `daylight == true` does.
 */
export function isLightTheme(daylight: boolean | null): boolean {
  const settings: AppSettings = AppSettings.instance;
  const isDay: boolean = daylight === true;
  if (settings.darkMode === DarkModeSetting.LIGHT) {
    return isDay;
  }
  if (settings.darkMode === DarkModeSetting.DARK) {
    return settings.dayNightForLocations && isDay;
  }
  return settings.systemDark ? (settings.dayNightForLocations && isDay) : isDay;
}
