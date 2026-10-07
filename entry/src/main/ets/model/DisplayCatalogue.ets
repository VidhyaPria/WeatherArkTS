/*
 * The three ordered display lists screen 3c's "Displayed data" section edits.
 *
 *   Blocks         CardDisplay.kt:32-53          — which cards screen 1 stacks, in order
 *   Daily trends   DailyTrendDisplay.kt:29-36    — the daily trend card's tabs, in order
 *   Hourly trends  HourlyTrendDisplay.kt:29-39   — the hourly trend card's tabs, in order
 *
 * Ids and defaults are the Kotlin's verbatim (SettingsManager.kt:61-90), and the names are
 * strings.xml's. NativeApp's cpp/data/DisplayCatalogue.* is the same table, so the two ports edit
 * and store exactly the same thing.
 *
 * Two Kotlin quirks worth keeping straight, because they differ per list:
 *
 *   - an EMPTY stored value means "no cards" for Blocks (CardDisplay.kt:58-70 returns an empty
 *     list), but "every tab" for the two trend lists (DailyTrendDisplay.kt:40-52). Emptying the
 *     Blocks list is therefore a real, reachable state; emptying a trend list is not, because the
 *     stored string is never empty once written — it is only empty before the key exists.
 *   - the defaults are NOT "all entries": Blocks omits `clock`, and the daily list omits nothing
 *     while the hourly list omits nothing either. `clock` is the one item that starts in the chip
 *     row, which is exactly what ref_screen3h_blocks.png shows.
 */

export enum DisplayList {
  BLOCKS = 0,
  DAILY = 1,
  HOURLY = 2
}

export class DisplayItem {
  readonly id: string;
  readonly name: string;
  /**
   * CardDisplay.configure (kt:29) — the gear button. Only two cards have one, and each opens
   * another manage screen. '' means no gear.
   */
  readonly configures: string;

  constructor(id: string, name: string, configures: string = '') {
    this.id = id;
    this.name = name;
    this.configures = configures;
  }
}

/** CardDisplay.kt:32-53. */
const CARD_DISPLAY: DisplayItem[] = [
  new DisplayItem('nowcast', 'Precipitation nowcasting'),
  new DisplayItem('daily_forecast', 'Daily forecast', 'daily'),
  new DisplayItem('hourly_forecast', 'Hourly forecast', 'hourly'),
  new DisplayItem('precipitation', 'Precipitation'),
  new DisplayItem('wind', 'Wind'),
  new DisplayItem('air_quality', 'Air quality'),
  new DisplayItem('pollen', 'Pollen'),
  new DisplayItem('humidity', 'Humidity'),
  new DisplayItem('uv', 'UV index'),
  new DisplayItem('visibility', 'Visibility'),
  new DisplayItem('pressure', 'Pressure'),
  new DisplayItem('sun', 'Sun'),
  new DisplayItem('moon', 'Moon'),
  new DisplayItem('clock', 'Clock')
];

/** DailyTrendDisplay.kt:29-36. */
const DAILY_TREND_DISPLAY: DisplayItem[] = [
  new DisplayItem('temperature', 'Conditions'),
  new DisplayItem('air_quality', 'Air quality'),
  new DisplayItem('wind', 'Wind'),
  new DisplayItem('uv_index', 'UV index'),
  new DisplayItem('precipitation', 'Precipitation'),
  new DisplayItem('sunshine', 'Sunshine'),
  new DisplayItem('feels_like', 'Feels like')
];

/** HourlyTrendDisplay.kt:29-39. */
const HOURLY_TREND_DISPLAY: DisplayItem[] = [
  new DisplayItem('temperature', 'Conditions'),
  new DisplayItem('air_quality', 'Air quality'),
  new DisplayItem('wind', 'Wind'),
  new DisplayItem('uv_index', 'UV index'),
  new DisplayItem('precipitation', 'Precipitation'),
  new DisplayItem('feels_like', 'Feels like'),
  new DisplayItem('humidity', 'Humidity / Dew point'),
  new DisplayItem('pressure', 'Pressure'),
  new DisplayItem('cloud_cover', 'Cloud cover'),
  new DisplayItem('visibility', 'Visibility')
];

/** SettingsManager.kt:61-73 — note `clock` is absent, which is why it starts as a chip. */
export const DEFAULT_CARD_DISPLAY: string =
  'nowcast&daily_forecast&hourly_forecast&precipitation&wind&air_quality&pollen&humidity&uv' +
  '&visibility&pressure&sun&moon';
/** SettingsManager.kt:74-80. */
export const DEFAULT_DAILY_TREND_DISPLAY: string =
  'temperature&air_quality&wind&uv_index&precipitation&sunshine&feels_like';
/** SettingsManager.kt:81-90. */
export const DEFAULT_HOURLY_TREND_DISPLAY: string =
  'temperature&air_quality&wind&uv_index&precipitation&feels_like&humidity&pressure&cloud_cover' +
  '&visibility';

export function catalogueFor(list: DisplayList): DisplayItem[] {
  if (list === DisplayList.BLOCKS) {
    return CARD_DISPLAY;
  }
  return list === DisplayList.DAILY ? DAILY_TREND_DISPLAY : HOURLY_TREND_DISPLAY;
}

/** The toolbar title — strings.xml:805-807. */
export function titleFor(list: DisplayList): string {
  if (list === DisplayList.BLOCKS) {
    return 'Blocks';
  }
  return list === DisplayList.DAILY ? 'Daily trends' : 'Hourly trends';
}

export function defaultValueFor(list: DisplayList): string {
  if (list === DisplayList.BLOCKS) {
    return DEFAULT_CARD_DISPLAY;
  }
  return list === DisplayList.DAILY ? DEFAULT_DAILY_TREND_DISPLAY : DEFAULT_HOURLY_TREND_DISPLAY;
}

/** The router parameter, and the id the NDK sends over the same channel. */
export function keyFor(list: DisplayList): string {
  if (list === DisplayList.BLOCKS) {
    return 'blocks';
  }
  return list === DisplayList.DAILY ? 'daily' : 'hourly';
}

export function listFromKey(key: string): DisplayList {
  if (key === 'daily') {
    return DisplayList.DAILY;
  }
  return key === 'hourly' ? DisplayList.HOURLY : DisplayList.BLOCKS;
}

/** `value.split("&").mapNotNull { entries.firstOrNull { it.id == cardId } }`. */
export function parseDisplayList(list: DisplayList, value: string): DisplayItem[] {
  const catalogue: DisplayItem[] = catalogueFor(list);
  const chosen: DisplayItem[] = [];
  if (value.length === 0) {
    // Blocks: an empty value is an empty list. The trend lists: every entry (see the header).
    return list === DisplayList.BLOCKS ? chosen : catalogue.slice();
  }
  for (const id of value.split('&')) {
    for (const item of catalogue) {
      if (item.id === id) {
        chosen.push(item);
        break;
      }
    }
  }
  return chosen;
}

/** `list.joinToString("&") { it.id }`. */
export function displayListToValue(items: DisplayItem[]): string {
  const ids: string[] = [];
  for (const item of items) {
    ids.push(item.id);
  }
  return ids.join('&');
}

/** The entries NOT in `items`, in the catalogue's order — the chip row (kt:144-156). */
export function displayListRemainder(list: DisplayList, items: DisplayItem[]): DisplayItem[] {
  const rest: DisplayItem[] = [];
  for (const candidate of catalogueFor(list)) {
    let used: boolean = false;
    for (const item of items) {
      if (item.id === candidate.id) {
        used = true;
        break;
      }
    }
    if (!used) {
      rest.push(candidate);
    }
  }
  return rest;
}

/**
 * `getSummary` (kt:78-82) — the names joined by `locale_separator`, which is ", " in English. This
 * is what screen 3c's three rows show.
 */
export function displayListSummary(items: DisplayItem[]): string {
  const names: string[] = [];
  for (const item of items) {
    names.push(item.name);
  }
  return names.join(', ');
}
