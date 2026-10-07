/*
 * Trend tabs for the daily and hourly cards.
 *
 * Order comes verbatim from the shipped defaults:
 *   SettingsManager.kt:74-80  DEFAULT_DAILY_TREND_DISPLAY
 *   SettingsManager.kt:81-90  DEFAULT_HOURLY_TREND_DISPLAY
 *
 * Labels come from each adapter's getDisplayName(), e.g. DailyTemperatureAdapter.kt:276.
 * The detail screen each item navigates to comes from the adapter's onItemClicked call.
 */

import { DetailScreen } from './DetailScreen';

export enum TrendTabId {
  TEMPERATURE = 'temperature',
  AIR_QUALITY = 'air_quality',
  WIND = 'wind',
  UV_INDEX = 'uv_index',
  PRECIPITATION = 'precipitation',
  SUNSHINE = 'sunshine',
  FEELS_LIKE = 'feels_like',
  HUMIDITY = 'humidity',
  PRESSURE = 'pressure',
  CLOUD_COVER = 'cloud_cover',
  VISIBILITY = 'visibility'
}

export class TrendTab {
  readonly id: TrendTabId;
  /** Button label. */
  readonly name: string;
  /** Screen opened when an item of this tab is tapped. */
  readonly detailScreen: DetailScreen;

  constructor(id: TrendTabId, name: string, detailScreen: DetailScreen) {
    this.id = id;
    this.name = name;
    this.detailScreen = detailScreen;
  }
}

/**
 * Daily tabs in default order (SettingsManager.kt:74-80).
 *
 * Air quality is the second tab, matching the reference device (DailyTrendDisplay.kt:29-35). It
 * was excluded while `Daily`/`Hourly` carried no index — adding it then would have fallen through
 * to the Sunshine branch and plotted sunshine hours under an "Air quality" label. Both now carry
 * `airQualityIndex`, filled by `applyAirQualitySeries` from the pollutant series the app already
 * fetched, so the tab is back.
 */
export const DAILY_TABS: TrendTab[] = [
  new TrendTab(TrendTabId.TEMPERATURE, 'Conditions', DetailScreen.TAG_CONDITIONS),
  new TrendTab(TrendTabId.AIR_QUALITY, 'Air quality', DetailScreen.TAG_AIR_QUALITY),
  new TrendTab(TrendTabId.WIND, 'Wind', DetailScreen.TAG_WIND),
  new TrendTab(TrendTabId.UV_INDEX, 'UV index', DetailScreen.TAG_UV_INDEX),
  new TrendTab(TrendTabId.PRECIPITATION, 'Precipitation', DetailScreen.TAG_PRECIPITATION),
  // DailySunshineAdapter.kt:151 labels it "Sunshine" but navigates to cloud cover (kt:123).
  new TrendTab(TrendTabId.SUNSHINE, 'Sunshine', DetailScreen.TAG_CLOUD_COVER),
  new TrendTab(TrendTabId.FEELS_LIKE, 'Feels like', DetailScreen.TAG_FEELS_LIKE)
];

/**
 * The tabs a card actually shows: the STORED list's order, restricted to tabs this port draws.
 *
 * `DailyTrendAdapter`/`HourlyTrendAdapter` are built from `dailyTrendDisplayList` /
 * `hourlyTrendDisplayList`, so the Daily trends and Hourly trends manage screens decide both which
 * tabs exist and in what order. An empty stored list means "every tab" for these two, which
 * parseDisplayList already handles.
 */
export function tabsFor(all: TrendTab[], storedIds: string[]): TrendTab[] {
  const chosen: TrendTab[] = [];
  for (const id of storedIds) {
    for (const tab of all) {
      if (tab.id === id) {
        chosen.push(tab);
        break;
      }
    }
  }
  // A stored list that names nothing this port draws would leave the card with no tabs at all;
  // fall back to the built-in set rather than render an empty header.
  return chosen.length > 0 ? chosen : all;
}

/** Hourly tabs in default order (SettingsManager.kt:81-90). */
export const HOURLY_TABS: TrendTab[] = [
  new TrendTab(TrendTabId.TEMPERATURE, 'Conditions', DetailScreen.TAG_CONDITIONS),
  new TrendTab(TrendTabId.AIR_QUALITY, 'Air quality', DetailScreen.TAG_AIR_QUALITY),
  new TrendTab(TrendTabId.WIND, 'Wind', DetailScreen.TAG_WIND),
  new TrendTab(TrendTabId.UV_INDEX, 'UV index', DetailScreen.TAG_UV_INDEX),
  new TrendTab(TrendTabId.PRECIPITATION, 'Precipitation', DetailScreen.TAG_PRECIPITATION),
  new TrendTab(TrendTabId.FEELS_LIKE, 'Feels like', DetailScreen.TAG_FEELS_LIKE),
  new TrendTab(TrendTabId.HUMIDITY, 'Humidity / Dew point', DetailScreen.TAG_HUMIDITY),
  new TrendTab(TrendTabId.PRESSURE, 'Pressure', DetailScreen.TAG_PRESSURE),
  new TrendTab(TrendTabId.CLOUD_COVER, 'Cloud cover', DetailScreen.TAG_CLOUD_COVER),
  new TrendTab(TrendTabId.VISIBILITY, 'Visibility', DetailScreen.TAG_VISIBILITY)
];
