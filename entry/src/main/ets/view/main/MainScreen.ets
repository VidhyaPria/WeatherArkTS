/*
 * Port of fragment_home.xml + HomeFragment.kt.
 *
 * The Android hierarchy is CoordinatorLayout > [AppBar(toolbar), CoordinatorLayout >
 * SwipeSwitchLayout > SwipeRefreshLayout > RecyclerView, InkPageIndicator]. Here that becomes
 * toolbar + Swiper(one Refresh-wrapped card list per location) + the indicator on top.
 *
 * Handlers implemented (see the mapping table agreed for this step):
 *   toolbar nav / edit / overflow  HomeFragment.kt:193-207
 *   pull to refresh                HomeFragment.kt:222-227
 *   horizontal swipe               HomeFragment.kt:475-497
 *   touch shows the indicator      HomeFragment.kt:462-471
 *   tab selection per card         DailyViewHolder.kt:122-133, HourlyViewHolder.kt:122-133
 *   trend item taps                AbsDailyTrendAdapter.kt:83-92, AbsHourlyTrendAdapter.kt:62-76
 *
 * The background is the flat weather theme colour for now; the animated Canvas background is
 * step 2, and the weather icons become animated in step 3.
 */

import { promptAction, router } from '@kit.ArkUI';
import { DragState } from './DragState';
import { LocationPage } from './LocationPage';
import { Dimens } from '../../theme/Dimens';
import { AppColors, getThemeColors, isLightBackground, withAlpha } from '../../theme/AppColors';
import { Alert, cityAndDistrict, getPlace, LocationModel, Weather } from '../../model/Weather';
import { LocationSources } from '../location/WeatherSourcesDialog';
import { selectedWeatherModels } from '../../model/OpenMeteoModels';
import { LocationPreferenceDialog, LocationPrefsResult } from '../location/LocationPreferenceDialog';
import { WeatherKind } from '../../model/WeatherKind';
import { DAILY_TABS, HOURLY_TABS, tabsFor, TrendTab } from '../../model/TrendTab';
import { DetailScreen } from '../../model/DetailScreen';
import { getMainViewModel, MainViewModel } from '../../viewmodel/MainViewModel';
import { goAlertList, goDetails, goPlaceholder } from '../../common/Navigator';
import { dayIndexForDate } from '../details/DetailsData';
import { applyStatusBarStyle, SystemInsets } from '../../common/SystemBars';
import { isTwoPane } from '../../common/TwoPane';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppSettings, isLightTheme, loadSettings } from '../../data/SettingsStore';
import {
  buildDailySeries,
  buildHourlySeries,
  SeriesBundle,
  syncSeries,
  TrendSeries
} from '../trend/TrendDataBuilder';
import { ChartColors } from '../trend/ChartData';
import { DoubleHistogramColors } from '../trend/DoubleHistogramCanvas';
import { AlertCard } from './AlertCard';
import { EnterAnimated } from './EnterAnimated';
import { buildDetailBlocks, DetailBlock } from './DetailBlocks';
import {
  DisplayItem,
  DisplayList,
  displayListToValue,
  parseDisplayList
} from '../../model/DisplayCatalogue';
import { displayListValue, setDisplayList } from '../../data/SettingsStore';
import { FooterCard } from './FooterCard';
import { MinutelyCard } from './MinutelyCard';
import { HalfBlockCard } from './HalfBlockCard';
import { HeaderCard } from './HeaderCard';
import { InkPageIndicator } from './InkPageIndicator';
import { MainToolbar } from './MainToolbar';
import { TrendCard } from './TrendCard';
import { WeatherBackground } from '../background/WeatherBackground';

/**
 * How many half-size detail blocks fit across the grid.
 *
 * `getBlocksPerRow` (DisplayExtensions.kt:79-88), driven from HomeFragment.kt:259 with the
 * RecyclerView's own width. Android measures in units of 160 dp â€” `windowWidth / densityDpi`,
 * where `Context.density` is `densityDpi`, not the vp scale â€” which in ArkUI terms is simply
 * `widthVp / 160`, because vp are already dp.
 *
 * This is what makes landscape a different page rather than the same one stretched: the reference
 * phone (1008 x 2244 at 360 dpi) fits 1008/360 = 2.8 units in portrait and 5.6 in landscape, so
 * two blocks a row become five. On the HarmonyOS device (1260 x 2720 at 520 dpi) it is 2.42 and
 * 5.23, so two become four. The rule is ported, not the number.
 */
const DP_PER_BLOCK_UNIT: number = 160;
/** DisplayExtensions.kt:20 â€” above two blocks, prefer fewer and roomier over squished. */
const SQUISHED_BLOCK_FACTOR: number = 1.1;
/** DisplayExtensions.kt:76 â€” 0.5 + fontScale/2, and the device font scale is the default 1. */
const MIN_BLOCK_WIDTH: number = 1.0;

function blocksPerRowFor(widthVp: number): number {
  if (widthVp <= 0) {
    return 2;
  }
  const units: number = widthVp / DP_PER_BLOCK_UNIT;
  const potential: number = Math.min(5, Math.max(1, Math.floor(units / MIN_BLOCK_WIDTH)));
  if (potential > 2) {
    return Math.min(5, Math.max(1,
      Math.floor(units / (MIN_BLOCK_WIDTH * SQUISHED_BLOCK_FACTOR))));
  }
  return potential;
}
/**
 * The forecast source's attribution string, shown in the footer. Only Open-Meteo is ported
 * (CLAUDE.md), so this is fixed until the source picker exists.
 * OpenMeteoService.kt:145 â€” `weatherAttribution = "Open-Meteo (CC BY 4.0)"`; the Android footer
 * shows the licence, so the port must too.
 */
const FORECAST_SOURCE_NAME: string = 'Open-Meteo (CC BY 4.0)';
/**
 * MaterialWeatherView.mFirstCardMarginTop (kt:95) â€” the scroll distance over which the background
 * fades out and after which it stops animating. The Kotlin computes it as
 * `insets.top + 500` **pixels** and flags the 500 as "TODO: Arbitrary value". 500 px on the
 * reference device (density 2.75) is ~182 dp, so that is the value used here; expressing it in vp
 * rather than px keeps it consistent across densities, which the Kotlin does not.
 */
const BACKGROUND_SCROLL_SPAN: number = 182;
/** Shared at-rest translate â€” see dragTranslation. Never mutate it. */
const NO_TRANSLATE: TranslateOptions = { x: 0, y: 0 };

/** No shadow â€” the resting state of every card that is not being dragged. */
const NO_SHADOW: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
/** ItemTouchHelper raises the dragged view by findMaxElevation + 1 over the cards' own 2dp. */
const DRAG_SHADOW: ShadowOptions = { radius: 24, color: '#33000000', offsetX: 0, offsetY: 6 };
/** DefaultItemAnimator's move duration â€” the displaced card's glide into the vacated slot. */
const SIBLING_SETTLE_MS: number = 250;
/** The retained series a trend card is permanently bound to â€” see MainScreen.seriesSlots. */
class SeriesSlot {
  readonly series: TrendSeries = new TrendSeries();
  builtForKey: string = '';
  /** Bumped on every rebind; TrendList redraws canvases and key lines off it. */
  version: number = 0;
  /** True when the last rebind changed the item count â€” the one case needing a real reload. */
  countChanged: boolean = false;
}

@ComponentV2
export struct MainScreen {
  @Local private currentIndex: number = 0;
  /** Needed to put the Swiper back on the selected page after a rebuild â€” see onReturnedToPage. */
  private swiperController: SwiperController = new SwiperController();
  @Local private loading: boolean = false;
  @Local private indicatorDisplayed: boolean = false;
  /** Bumped after a refresh so the cards rebuild with the new refresh time. */
  @Local private dataVersion: number = 0;

  /** Bumped after a drag so the grid re-reads the reordered card list. */
  /** Width of the scrolling content, needed to size the block grid's rows. */
  /**
   * Bumped when `card_display` changes, so every guard that reads the stored card list re-runs.
   *
   * The list itself lives in the preferences bag and is read through a plain function, which
   * registers no dependency — the trap this port keeps rediscovering. This counter is the
   * subscription, and `onPageShow` bumps it because the Blocks manage screen may have rewritten
   * the list while this screen was parked.
   */
  @Local private cardsVersion: number = 0;
  @Local private contentWidth: number = 0;
  /** System bar insets, published by SystemBars and refreshed on rotation. */
  private insets: SystemInsets = SystemInsets.instance;
  /**
   * MaterialWeatherView.setScrollRate â€” 0 at the top, 1 once the header has scrolled away and the
   * cards cover the background. The implementors stop drawing at 1.
   */
  @Local private backgroundScrollRate: number = 0;

  /** Bumped by Index.onPageShow; watched below so a return from the location list re-syncs. */
  @Param pageShows: number = 0;

  /**
   * Fired when this screen has changed the shared model from underneath a list that is on screen
   * BESIDE it â€” the two-pane arrangement, where the list is not a page that can re-read the model
   * when it is reopened.
   *
   * The two moments that matter are the ones below: the stored list arriving (`loadCached`), and a
   * refresh that actually brought new data. Both change what a row shows, and neither is observable
   * â€” `viewModel.getLocations()` is a plain array.
   *
   * Deliberately NOT wired to `pageShows`, and not fired from a @Monitor on `dataVersion`: Index
   * bumping `pageShows` re-enters this struct's own @Monitor, which bumps `dataVersion`, which would
   * fire this again. It drives a separate counter in Index for that reason.
   */
  @Event onDataLoaded: () => void = () => {
  };

  /**
   * False while another page is pushed on top of this one â€” see the note on Index.pageVisible.
   * Drives the background loop, which otherwise animates underneath a screen that covers it.
   */
  @Param pageVisible: boolean = true;

  /**
   * False while the two-pane list beside this page is being scrolled.
   *
   * The scene is the most expensive thing on the screen, and in two-pane it keeps animating behind
   * a pane that never covers it — so a list gesture contends with a full scene repaint on every
   * frame. NativeApp makes exactly this trade in `Renderer::ListScrolling()`, which already held
   * the scene still for a trend-list gesture and now does the same for the pane's; this is the
   * ArkUI half of it. Only two-pane sets it: in portrait the list is a PAGE, and `pageVisible`
   * already stops the loop outright.
   */
  @Param backgroundAnimates: boolean = true;

  private viewModel: MainViewModel = getMainViewModel();
  private previousTemperature: number = 0;
  /** Id of the card being dragged, or empty when no drag is in progress. */
  /** Live finger offset applied to the dragged card. */
  /**
   * The card order frozen at long-press. During the drag the ForEach NEVER re-reads the order â€”
   * every reorder is expressed as a translate against this snapshot, and the real data reorder is
   * committed once, in endDrag's onFinish, when nothing is moving.
   *
   * This is the load-bearing part of the drag. The previous design swapped `cardOrder` and bumped
   * `orderVersion` on every crossing, and the trace showed what that costs: ArkUI's ForEach does
   * not move a child whose key changes position â€” it destroys and recreates it â€” so every swap
   * rebuilt the two swapped HalfBlockCards from scratch (~15 ms each plus a 23 ms aboutToAppear)
   * and re-measured the whole page (~55 ms), a 72+ ms frame under the finger at every crossing.
   * RecyclerView gets away with reordering live because it moves views without rebuilding them;
   * ArkUI cannot, so the reorder has to stay visual until the gesture is over.
   */
  /** Stable translate per shifted card, rebuilt only when a crossing changes the logical order. */
  /** The card displaced by the last crossing, gliding from its old slot into its new one. */
  /** A refresh that completes mid-drag must not rebuild every page under the finger. */
  private pendingDataBump: boolean = false;
  /** Which location's page the parked bump belongs to. */
  private pendingBumpId: string = '';
  /**
   * One Scroller per location page, keyed by formattedId.
   *
   * There used to be a single shared `Scroller` handed to every `Scroll` the Swiper's ForEach
   * built â€” three scrollables bound to one controller. A Scroller only ever drives one container,
   * so `currentOffset()` did not report the visible page and `backgroundScrollRate` never reached
   * 1. That is why the weather background kept animating: `SunImplementor.draw` bails out at
   * `scrollRate >= 1` (matching kt), and the rate never got there. A trace taken while sitting
   * idle at the bottom of the page showed the background canvas still repainting 30 times a
   * second, 39 draw ops each, underneath cards that hide it completely.
   */
  private scrollers: Map<string, Scroller> = new Map();

  private scrollerFor(location: LocationModel): Scroller {
    let scroller: Scroller | undefined = this.scrollers.get(location.formattedId);
    if (scroller === undefined) {
      scroller = new Scroller();
      this.scrollers.set(location.formattedId, scroller);
    }
    return scroller;
  }
  /**
   * The live card order, standing in for SettingsManager.cardDisplayList until the settings
   * screens land (step 6). Seeded from DEFAULT_CARD_DISPLAY the first time the blocks are
   * built, then rewritten by each drop exactly as MainAdapter.onItemMove does.
   */
  /** All nine drag fields now live here so the extracted LocationPage can observe them. */
  private drag: DragState = new DragState();
  /** The card under the finger, mirrored into the drag preview. */
  @Local private draggedBlock: DetailBlock =
    new DetailBlock('', $r('app.media.ic_gauge'), '', '', '', DetailScreen.TAG_CONDITIONS);

  /**
   * Building the blocks walks the whole current-conditions object, and the grid asks for the
   * list three times per frame (items, height, drag). Memoise per location + data version.
   *
   * The order version is deliberately NOT part of this key. It used to be, which meant every
   * swap during a drag re-ran buildDetailBlocks and handed each HalfBlockCard a brand-new
   * DetailBlock instance â€” a different object reference, so every card in the grid re-rendered
   * from scratch on every pointer crossing, several times a second, while the finger was down.
   * Reordering is now a reshuffle of the same instances, so the cards ArkUI moves are the cards
   * it already had.
   */
  private blocksCache: Map<string, DetailBlock[]> = new Map();
  /** The ordered view of the above; cheap to rebuild because it reuses those instances. */
  private orderedCache: Map<string, DetailBlock[]> = new Map();

  /** The blocks the current data supports, in their natural order. */
  private builtBlocks(location: LocationModel): DetailBlock[] {
    const key: string =
      location.formattedId + ':' + this.pageVersion(location.formattedId).toString() + ':' + (this.isDark() ? 'd' : 'l');
    const hit: DetailBlock[] | undefined = this.blocksCache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const built: DetailBlock[] = buildDetailBlocks(location, this.isDark());
    if (this.blocksCache.size > 8) {
      this.blocksCache.clear();
    }
    this.blocksCache.set(key, built);
    return built;
  }

  /** Applies cardOrder on top of the blocks the current data supports. */
  private orderedBlocks(location: LocationModel): DetailBlock[] {
    // Only the page you are actually dragging on re-reads the order mid-gesture.
    //
    // The Swiper builds all three location pages, and `orderVersion` is MainScreen state, so a
    // swap used to invalidate the grid on every page at once. The drop frame then contained three
    // `CreateTaskMeasure[Scroll]` passes â€” one per page â€” and rebuilt HalfBlockCards on pages that
    // were not even on screen. The off-screen pages keep their previous array until they become
    // current, at which point this key starts tracking orderVersion again and they catch up.
    // `cardOrder` itself is shared, exactly as SettingsManager.cardDisplayList is on Android.
    /*
     * `dataVersion` is read here for the SUBSCRIPTION, not for the key — the same reason
     * `pagerLocations()` reads it.
     *
     * This method is the detail grid's ForEach data source, and everything else it touches is
     * unobservable: `pageVersions` is a plain Map, `drag.orderVersion` is plain state, and
     * `isDark()` reads @Trace through a helper. On a cache hit it does not even evaluate a
     * formatter, so nothing registers and the ForEach is never marked dirty. That is why changing
     * the pressure unit re-rendered the header and left the Pressure block reading "1015 hPa":
     * `bumpAllPages()` had already invalidated the cache key, but nothing ever asked for it again.
     */
    const listVersion: number = this.dataVersion;
    const isCurrent: boolean = location.formattedId === this.currentFormattedId();
    const key: string = location.formattedId + ':' +
      (isCurrent ? this.drag.orderVersion.toString() : 'pending') + ':' +
      this.pageVersion(location.formattedId).toString() + ':' + (this.isDark() ? 'd' : 'l') +
      // The stored card list decides which blocks this returns, so it has to be part of the key.
      ':' + this.cardsVersion.toString() +
      (listVersion < 0 ? 'x' : '');
    const hit: DetailBlock[] | undefined = this.orderedCache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const ordered: DetailBlock[] = this.buildOrderedBlocks(location);
    if (this.orderedCache.size > 8) {
      this.orderedCache.clear();
    }
    this.orderedCache.set(key, ordered);
    return ordered;
  }

  /**
   * The two trend cards' tab sets, decided by the Daily/Hourly trends manage screens.
   * `cardsVersion` is the subscription, exactly as it is for the card list.
   */
  private dailyTabs(): TrendTab[] {
    return tabsFor(DAILY_TABS, this.storedIds(DisplayList.DAILY));
  }

  private hourlyTabs(): TrendTab[] {
    return tabsFor(HOURLY_TABS, this.storedIds(DisplayList.HOURLY));
  }

  private storedIds(list: DisplayList): string[] {
    const ids: string[] = [];
    parseDisplayList(list, displayListValue(list)).forEach((item: DisplayItem) => {
      ids.push(item.id);
    });
    return ids;
  }

  /** The stored card list, parsed. `cardsVersion` is the subscription; see the field. */
  private storedCards(): DisplayItem[] {
    return parseDisplayList(DisplayList.BLOCKS, displayListValue(DisplayList.BLOCKS));
  }

  /** `for (c in cardDisplayList)` (MainAdapter.kt:110) — a removed card is never built. */
  private cardEnabled(id: string): boolean {
    for (const item of this.storedCards()) {
      if (item.id === id) {
        return true;
      }
    }
    return false;
  }

  /**
   * The half-size blocks the current data supports, filtered and ordered by `card_display`.
   *
   * `drag.cardOrder` is the live working order for the gesture; it is SEEDED from the stored list
   * rather than from whatever order the builder happened to produce, which is what makes the Blocks
   * manage screen decide this screen's contents (MainAdapter.kt:110-171).
   */
  private buildOrderedBlocks(location: LocationModel): DetailBlock[] {
    const built: DetailBlock[] = this.builtBlocks(location);
    const byId: Map<string, DetailBlock> = new Map();
    built.forEach((block: DetailBlock) => {
      byId.set(block.id, block);
    });

    // The stored order, restricted to blocks the data actually supports.
    const wanted: string[] = [];
    this.storedCards().forEach((item: DisplayItem) => {
      if (byId.has(item.id)) {
        wanted.push(item.id);
      }
    });
    /*
     * The gesture's working order is re-seeded whenever the stored list no longer agrees with it —
     * which is exactly what returning from the Blocks screen looks like. A drag in progress is not
     * possible here: this runs from the ForEach data source, and a drop commits before the next
     * build.
     */
    const live: string[] = this.drag.cardOrder.filter((id: string) => wanted.indexOf(id) >= 0);
    if (live.length !== wanted.length) {
      this.drag.cardOrder = wanted.slice();
    } else {
      this.drag.cardOrder = live;
    }

    const ordered: DetailBlock[] = [];
    this.drag.cardOrder.forEach((id: string) => {
      const block: DetailBlock | undefined = byId.get(id);
      if (block !== undefined) {
        ordered.push(block);
      }
    });
    return ordered;
  }

  /**
   * MainAdapter.onItemMove (kt:296-311) — the main screen's own drag WRITES the new order back to
   * `card_display`. It is the same setting the Blocks manage screen edits, so a reorder here shows
   * up there and survives a restart.
   *
   * The stored list also holds the three big cards and any card the data does not currently
   * support, and those keep their positions: the merge walks the stored list and replaces only the
   * entries that are in the dragged subset, in the subset's new order.
   */
  private persistCardOrder(): void {
    const dragged: string[] = this.drag.cardOrder;
    if (dragged.length === 0) {
      return;
    }
    const stored: DisplayItem[] = this.storedCards();
    const inSubset: (item: DisplayItem) => boolean =
      (item: DisplayItem) => dragged.indexOf(item.id) >= 0;
    const byId: Map<string, DisplayItem> = new Map();
    stored.forEach((item: DisplayItem) => {
      byId.set(item.id, item);
    });
    let next: number = 0;
    const merged: DisplayItem[] = [];
    stored.forEach((item: DisplayItem) => {
      if (!inSubset(item)) {
        merged.push(item);
        return;
      }
      const replacement: DisplayItem | undefined = byId.get(dragged[next]);
      next++;
      if (replacement !== undefined) {
        merged.push(replacement);
      }
    });
    const value: string = displayListToValue(merged);
    if (value !== displayListValue(DisplayList.BLOCKS)) {
      setDisplayList(DisplayList.BLOCKS, value);
    }
  }

  /**
   * One RETAINED series per card per location â€” the adapter each list is permanently bound to.
   *
   * A tab switch or refresh builds a fresh series and `syncSeries` copies it INTO the retained
   * one: same TrendItemModel instances, same items array, new values. The live columns rebind in
   * place (the models are @ObservedV2) instead of being destroyed and rebuilt, which is what a
   * RecyclerView does and what a fresh-array-per-tab could never do under LazyForEach. `version`
   * bumps on every rebind so TrendList can redraw key lines and canvases.
   */
  private seriesSlots: Map<string, SeriesSlot> = new Map();

  /**
   * `rebuild` false means: hand back whatever this slot already holds, however stale.
   *
   * Only the CURRENT location rebuilds. The build key carries the title colour, which comes from
   * the current location's daylight, so selecting a night location from a daytime one changes the
   * key of every page's series at once — thirteen locations, two cards each, all re-syncing and
   * re-laying-out in one frame. Traced at 1610 ms in FlushDirtyNodeUpdate for a single selection.
   *
   * A page nobody is looking at does not need its labels recoloured, and it takes the rebuild the
   * moment it becomes current: `currentIndex` changing re-renders this screen, the card asks again
   * with `rebuild` true, and the key still differs, so the sync happens then. Selection therefore
   * costs ONE page's sync instead of thirteen.
   *
   * Deliberately NOT a page window: nothing is created or destroyed here, so this cannot repeat
   * either failure that idea produced — no page comes up empty, and no page build lands on the tap.
   */
  private slotSeries(slotKey: string, buildKey: string, rebuild: boolean,
    build: () => TrendSeries): SeriesSlot {
    let slot: SeriesSlot | undefined = this.seriesSlots.get(slotKey);
    if (slot === undefined) {
      slot = new SeriesSlot();
      this.seriesSlots.set(slotKey, slot);
    }
    if (slot.builtForKey !== buildKey && (rebuild || slot.builtForKey.length === 0)) {
      // The empty-key case is a slot that has never been filled: a page must not draw an empty
      // chart just because it is not the one on screen.
      const fresh: TrendSeries = build();
      slot.countChanged = syncSeries(slot.series, fresh);
      slot.builtForKey = buildKey;
      slot.version++;
    }
    return slot;
  }

  /**
   * colorTitleText for the current theme. The histogram-only tabs label their bars with it
   * (setTextColors(..., colorTitleText), e.g. HourlyWindAdapter.kt:89-93), so it has to reach the
   * series builder â€” and it goes into the cache key, or a theme switch would serve stale labels.
   */
  private titleTextColor(): string {
    return AppColors.TITLE_TEXT.resolve(this.isDark());
  }

  /**
   * The providers each trend card pulls its series through. The selected tab lives on the CARD
   * (as it does on Android's per-card adapter), so these take the tab index as an argument and
   * MainScreen holds no reactive tab state at all â€” a chip tap re-renders one card, not three
   * location pages.
   */
  private dailyBundle(location: LocationModel, tabIndex: number): SeriesBundle {
    const titleColor: string = this.titleTextColor();
    const key: string = tabIndex.toString() + ':' + this.pageVersion(location.formattedId).toString() + ':' + titleColor;
    const slot: SeriesSlot = this.slotSeries('d:' + location.formattedId, key,
      location.formattedId === this.currentFormattedId(),
      () => buildDailySeries(location, this.dailyTabs()[tabIndex], titleColor));
    const bundle = new SeriesBundle();
    bundle.items = slot.series.items;
    bundle.itemsVersion = slot.version;
    bundle.itemCountChanged = slot.countChanged;
    bundle.keyLines = slot.series.keyLines;
    // Key line scale: the polyline range when there is one, the histogram range otherwise â€”
    // `host.setData(keyLineList, mHighestIndex, 0f)` (DailyUVAdapter.kt:134-141).
    if (slot.series.items.length > 0) {
      const chart = slot.series.items[0].polyline;
      if (chart.highestValue === null && chart.lowestValue === null) {
        bundle.highestValue = chart.highestHistogramValue;
        bundle.lowestValue = chart.lowestHistogramValue;
      } else {
        bundle.highestValue = chart.highestValue;
        bundle.lowestValue = chart.lowestValue;
      }
    }
    return bundle;
  }

  private hourlyBundle(location: LocationModel, tabIndex: number): SeriesBundle {
    const titleColor: string = this.titleTextColor();
    const key: string = tabIndex.toString() + ':' + this.pageVersion(location.formattedId).toString() + ':' + titleColor;
    const slot: SeriesSlot = this.slotSeries('h:' + location.formattedId, key,
      location.formattedId === this.currentFormattedId(),
      () => buildHourlySeries(location, this.hourlyTabs()[tabIndex], titleColor));
    const bundle = new SeriesBundle();
    bundle.items = slot.series.items;
    bundle.itemsVersion = slot.version;
    bundle.itemCountChanged = slot.countChanged;
    // The hourly card draws no key lines (bundle defaults: empty lines, null bounds).
    return bundle;
  }

  /**
   * Plain methods, not `get` accessors: accessors declared on a @Component struct are not
   * available on the instance at render time, so `this.someGetter` reads back as undefined.
   */
  private isDark(): boolean {
    /*
     * ThemeManager.isLightTheme, now that the settings behind it exist (data/SettingsStore.ets).
     *
     * This was a flat `!location.daylight`, which is what the rule REDUCES to under the Kotlin's
     * defaults â€” dark mode `system` with the system in light â€” and is why it has looked right all
     * along. It is wrong the moment the system is dark or a dark mode is chosen, which the
     * Appearance screen now allows.
     *
     * NOT observed here, deliberately. `isLightTheme` reads @Trace fields, and a @Trace read inside
     * a helper does not register a render dependency â€” the trap this port documents throughout. It
     * needs none: the settings can only be changed on the Settings PAGE, and returning from it
     * bumps `pageShows`, whose @Monitor already re-renders this screen.
     */
    const location: LocationModel | null = this.currentLocation();
    return !isLightTheme(location === null ? null : location.daylight);
  }

  private currentFormattedId(): string {
    const location: LocationModel | null = this.currentLocation();
    return location === null ? '' : location.formattedId;
  }

  /**
   * The pager's data source â€” and the ONLY thing that makes the Swiper's ForEach re-diff.
   *
   * `getLocations()` returns a plain array off a plain view model: reading it observes nothing, so
   * a ForEach whose data source is that call alone is built once and then frozen forever. That is
   * what it was. The app seeds three locations in `buildLocations()`, `loadCached` then replaces
   * the list with the thirteen stored ones, and the pager kept the seeded three for the rest of the
   * session â€” while the toolbar, which reads `currentIndex` and so DOES re-evaluate, went on
   * naming rows out of the thirteen-entry array. The two were indexing into different lists:
   * page 2 was Tokyo's while the toolbar called it Shanghai, and pages 3-12 did not exist at all,
   * so a selection past index 2 could not land anywhere.
   *
   * `dataVersion` is read here for the same reason it is read in `currentLocation()` below: the
   * read is what registers the dependency. It is already bumped everywhere the list can change
   * (`loadCached` finishing, `onReturnedToPage` when the list changed, a refresh that brought data),
   * so those bumps now reach the pager instead of stopping at the attributes.
   *
   * Deliberately NOT back in the ForEach KEY. The key stays pure identity, so a bump re-DIFFS â€”
   * existing pages are kept and only genuinely new locations are built. Putting the version in the
   * key is what rebuilt every page on every bump, and that is the 29 MB/trip leak and the
   * THREAD_BLOCK_6S freeze recorded against the ForEach above. Re-diffing has neither cost.
   */
  private pagerLocations(): LocationModel[] {
    const listVersion: number = this.dataVersion;
    if (listVersion < 0) {
      return [];
    }
    return this.viewModel.getLocations();
  }

  private currentLocation(): LocationModel | null {
    // Indexes through `currentIndex` rather than asking the view model for "the current one".
    //
    // ArkUI V2 works out what to re-render from the observable state a builder actually READS.
    // The view model is a plain object, so `viewModel.getCurrentLocation()` reads nothing
    // observable â€” swiping to another location changed the pages (they come from the Swiper's own
    // ForEach) but never re-evaluated anything derived from this method. The visible symptom was
    // the toolbar still saying "Helsinki" while Tokyo's weather was on screen; the background
    // kind, the theme colours and the dark-mode flag were all equally stale.
    //
    // `dataVersion` is read for the same reason, one level deeper: refresh() REPLACES
    // `location.weather` in place, which is invisible to the framework. Without this read the
    // weather background kept the kind the seeded mock had (CLEAR), so a live "Partly cloudy"
    // still showed the clear-day sun and its orange gradient. Anything derived from the current
    // location has to re-evaluate when either the location or its weather changes.
    const locations: LocationModel[] = this.viewModel.getLocations();
    const index: number = this.currentIndex;
    const weatherVersion: number = this.dataVersion;
    if (weatherVersion < 0) {
      return null;
    }
    if (index < 0 || index >= locations.length) {
      return null;
    }
    const location: LocationModel = locations[index];
    return location === null || location === undefined ? null : location;
  }

  private backgroundColorFor(location: LocationModel | null): string {
    if (location === null || location === undefined ||
      location.weather === null || location.weather.current === null) {
      return AppColors.BACKGROUND.resolve(this.isDark());
    }
    return getThemeColors(location.weather.current.weatherKind, location.daylight)[0];
  }

  /** ?attr/colorSurfaceInverse â€” what the header and toolbar text use. */
  private onBackgroundColor(): string {
    const location: LocationModel | null = this.currentLocation();
    const light: boolean = location === null
      ? true
      : isLightBackground(location.daylight, this.isDark());
    return light ? AppColors.SURFACE_INVERSE.light : AppColors.SURFACE_INVERSE.dark;
  }

  /**
   * MainActivity.updateSystemBarStyle (kt:216-228) â†’ HomeFragment.setSystemBarStyle: the status
   * bar's icons follow the sky, dark on a light background and light on a dark one. Watched on the
   * two pieces of state that can change it â€” the location on screen, and a refresh that changes
   * that location's weather or daylight.
   */
  /** The system's colour mode, which the theme rule needs alongside the stored dark mode. */
  private syncSystemDark(): void {
    const context = getContext(this) as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  @Monitor('currentIndex', 'dataVersion')
  onBackgroundLightnessChanged(): void {
    const location: LocationModel | null = this.currentLocation();
    applyStatusBarStyle(
      location === null ? true : isLightBackground(location.daylight, this.isDark()));
  }

  /**
   * HomeFragment.kt:414-417 — U+2299 prefixes the title for the current position on phones.
   *
   * The literal here was CORRUPTED: this file went through a UTF-8-decoded-as-Latin-1 round trip
   * at some point, so the prefix was stored as the three characters "âŠ™" and the toolbar drew
   * "âŠ™ Helsinki" on the device. The list row never showed it because LocationRowModel.ets kept a
   * clean copy — which is why the two disagreed and only the toolbar was wrong. NativeApp writes
   * the same character as `\xE2\x8A\x99` escapes for the same reason.
   */
  private titleFor(location: LocationModel | null): string {
    if (location === null) {
      return '';
    }
    return (location.isCurrentPosition ? '⊙ ' : '') + getPlace(location);
  }

  /**
   * ChartColors / DoubleHistogramColors are memoised per (weather kind, daylight, dark).
   *
   * They used to be built fresh on every render, and a colours OBJECT is compared by reference:
   * a new instance meant "param changed" to every TrendList on screen. The cost showed up as the
   * tab-tap trace's smoking gun â€” tapping the DAILY Wind chip re-measured three TrendLists
   * (~95 ms each: the daily one legitimately, the hourly one and the neighbour page's for
   * nothing) followed by 290-436 ms onAreaChange JS waves from all the needlessly rebuilt items.
   * Android rebinds exactly one RecyclerView on a tab switch; with stable references, so do we.
   */
  private chartColorsCache: Map<string, ChartColors> = new Map();
  private doubleColorsCache: Map<string, DoubleHistogramColors> = new Map();

  private themeKeyFor(location: LocationModel): string {
    const kind: WeatherKind = location.weather !== null && location.weather.current !== null
      ? location.weather.current.weatherKind
      : WeatherKind.NULL;
    return kind.toString() + ':' + (location.daylight ? 'day' : 'night') + ':' +
      (this.isDark() ? 'd' : 'l');
  }

  private chartColorsFor(location: LocationModel): ChartColors {
    const key: string = this.themeKeyFor(location);
    const hit: ChartColors | undefined = this.chartColorsCache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    // DailyTemperatureAdapter.kt:142-166
    const themeColors: string[] = getThemeColors(
      location.weather !== null && location.weather.current !== null
        ? location.weather.current.weatherKind
        : WeatherKind.NULL,
      location.daylight
    );
    const lightTheme: boolean = !this.isDark();
    const colors = new ChartColors();
    colors.highLine = themeColors[1];
    colors.lowLine = themeColors[2];
    colors.subLine = AppColors.OUTLINE.resolve(this.isDark());
    // setShadowColors (PolylineAndHistogramView.kt:404-417): the high colour at 15% in light
    // themes, the low colour at 30% in dark ones.
    colors.shadowTop = lightTheme ? withAlpha(themeColors[1], 0.15) : withAlpha(themeColors[2], 0.3);
    colors.highText = AppColors.TITLE_TEXT.resolve(this.isDark());
    colors.lowText = AppColors.BODY_TEXT.resolve(this.isDark());
    colors.histogramText = AppColors.PRECIPITATION_PROBABILITY.resolve(this.isDark());
    colors.histogramAlpha = lightTheme ? 0.2 : 0.5;
    if (this.chartColorsCache.size > 8) {
      this.chartColorsCache.clear();
    }
    this.chartColorsCache.set(key, colors);
    return colors;
  }

  private doubleChartColorsFor(location: LocationModel): DoubleHistogramColors {
    const key: string = this.themeKeyFor(location);
    const hit: DoubleHistogramColors | undefined = this.doubleColorsCache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const themeColors: string[] = getThemeColors(
      location.weather !== null && location.weather.current !== null
        ? location.weather.current.weatherKind
        : WeatherKind.NULL,
      location.daylight
    );
    const colors = new DoubleHistogramColors();
    colors.highBar = themeColors[1];
    colors.lowBar = themeColors[2];
    colors.subLine = AppColors.OUTLINE.resolve(this.isDark());
    colors.text = AppColors.BODY_TEXT.resolve(this.isDark());
    // setHistogramAlphas(1f, 0.5f) â€” DailyWindAdapter.kt:92, DailyPrecipitationAdapter.kt:114.
    // The night bar is drawn at half opacity in both double-histogram tabs.
    colors.highAlpha = 1;
    colors.lowAlpha = 0.5;
    if (this.doubleColorsCache.size > 8) {
      this.doubleColorsCache.clear();
    }
    this.doubleColorsCache.set(key, colors);
    return colors;
  }

  /**
   * MainActivity.kt refreshes on resume when the cached weather is stale; here the first frame
   * always pulls, so the screen shows live Open-Meteo data rather than the seeded values.
   */
  /**
   * Opens the location list, and re-reads the model when it comes back.
   *
   * The list screen mutates the shared MainViewModel â€” a location may have been added, deleted,
   * reordered, or a different one selected â€” and none of that is observable state, so the page has
   * to be told to rebuild. `dataVersion` is the existing signal the Swiper's keys already carry.
   */
  private openLocationList(): void {
    /*
     * A no-op while the drawer pane is unfolded â€” the list is already on screen beside this page.
     *
     * DrawerLayout.kt:53 makes openDrawer/closeDrawer no-ops in the two-pane layout for exactly this
     * reason. Pushing the page here would stack a full-width list over a layout that already
     * contains one. LocationList's own fold rule handles the other direction, where the page is
     * already up when the window becomes wide.
     */
    if (isTwoPane()) {
      return;
    }
    // Remembered so the return can tell a pure SELECTION from a real change to the list.
    this.locationsKey = this.currentLocationsKey();
    router.pushUrl({ url: 'pages/LocationList' })
      .then(() => {
      })
      .catch((error: Error) => {
        console.error('Location list unavailable: ' + error.message);
      });
  }

  /**
   * The identity of the list â€” which locations, in what order.
   *
   * Deliberately not a count and not `LocationRevision`: a count misses a reorder, and the revision
   * counter is bumped by `setCurrentIndex` too, so it cannot tell "the user picked a different row"
   * from "the user added or removed one".
   */
  private locationsKey: string = '';

  /**
   * Per-location page version â€” the fix for the freeze that survived the first two attempts.
   *
   * `dataVersion` is global, and it used to be in the Swiper's ForEach key, so a successful refresh
   * of ONE location destroyed and rebuilt EVERY location page. Making the refresh bump conditional
   * helped only while refreshes were failing: with location services off the current position never
   * fetched, so nothing was rebuilt. Turn location on and every selection succeeds, every success
   * remounted all five pages, and the app died again in under ten trips.
   *
   * The page key now carries this instead, bumped only for the location whose weather actually
   * changed. `dataVersion` still exists and is still bumped â€” it is what re-renders MainScreen so
   * the ForEach re-diffs, and it still drives `refreshStamp` for the trend cards â€” but it no longer
   * decides page IDENTITY, so a refresh rebuilds one page instead of all of them.
   */
  private pageVersions: Map<string, number> = new Map();


  private pageVersion(formattedId: string): number {
    const version: number | undefined = this.pageVersions.get(formattedId);
    return version === undefined ? 0 : version;
  }

  private bumpPage(formattedId: string): void {
    this.pageVersions.set(formattedId, this.pageVersion(formattedId) + 1);
  }

  private bumpAllPages(): void {
    const locations: LocationModel[] = this.viewModel.getLocations();
    for (let i = 0; i < locations.length; i++) {
      this.bumpPage(locations[i].formattedId);
    }
  }

  /**
   * The identity of the five unit settings, for the same reason `locationsKey` exists.
   *
   * The stored ids live on `AppSettings.instance` (@ObservedV2, @Trace), but every unit read on
   * this screen goes through a helper in `common/Units.ets` — `temperatureUnitLabel()`,
   * `formatSpeed()` and friends — and a @Trace read inside a helper registers no dependency. So
   * changing a unit on the settings screen re-themes nothing here on its own: coming back showed
   * the temperature converted (the header rebuilt for another reason) while the "°C" beside it was
   * still the old label.
   *
   * Rather than thread an observable through a dozen formatters, the return path compares this
   * key and bumps `dataVersion`, which is already the signal that re-renders every page.
   */
  private unitsKey: string = '';

  private currentUnitsKey(): string {
    const settings: AppSettings = AppSettings.instance;
    return settings.temperatureUnit + ',' + settings.precipitationUnit + ',' +
      settings.speedUnit + ',' + settings.distanceUnit + ',' + settings.pressureUnit;
  }

  private currentLocationsKey(): string {
    const locations: LocationModel[] = this.viewModel.getLocations();
    let key: string = '';
    for (let i = 0; i < locations.length; i++) {
      key += locations[i].formattedId + ',';
    }
    return key;
  }

  /**
   * Re-syncs the page whenever it comes back to the front â€” which, for this screen, means the
   * location list has just closed and may have selected, added, deleted or reordered something.
   *
   * Bumping `dataVersion` re-keys the Swiper's ForEach, so a changed list rebuilds its pages;
   * adopting the model's index is what makes a row tap on the list screen actually land on that
   * location. `Index.onPageShow` is the only place the lifecycle callback can live.
   */
  @Monitor('pageShows')
  onReturnedToPage(): void {
    /*
     * The Blocks manage screen may have rewritten `card_display` while this screen was parked, and
     * nothing here is subscribed to a preferences file. Bumping the counter is what re-runs the
     * per-card guards and the ordered-blocks builder; the cache key carries it for the same reason.
     */
    this.cardsVersion++;
    const index: number = this.viewModel.getCurrentIndex();
    /*
     * TWO updates, deliberately, not one.
     *
     * Bumping dataVersion re-keys every page, so the Swiper's whole ForEach is rebuilt. Setting the
     * index in that same update does not survive the rebuild: the Swiper comes back on page 0, and
     * since nothing swiped, `onChange` never fires to correct it. The toolbar then names the
     * location the model selected while the page underneath is still the first one â€” and worse, the
     * refresh that `onChange` would have triggered never runs, so a freshly added location is never
     * even fetched. Doing the index in a LATER task lets it apply to the rebuilt Swiper.
     *
     * `changeIndex` as well as `.index()`, because the assignment alone does not move a Swiper that
     * already considers itself settled.
     */
    /*
     * The bump is now CONDITIONAL, and that is the whole fix for the freeze.
     *
     * `dataVersion` is in the Swiper's ForEach key, so bumping it destroys and rebuilds every
     * location page â€” header, both trend cards with their lists and canvases, twelve detail cards
     * and the footer, times four locations. Doing that on EVERY return leaked about 29 MB a trip
     * (measured: PSS 467 â†’ 702 MB over eight round-trips, with native memory flat, so it is all
     * ArkTS heap). The retained trees also grew ArkUI's binding registry until `clearBinding` on a
     * later page teardown blocked the main thread past six seconds and the system killed the app
     * with THREAD_BLOCK_6S â€” which is what "it goes to Berlin and then freezes" was: the Swiper
     * starting to animate towards the selected page and stalling partway.
     *
     * A rebuild is only needed when the LIST changed â€” added, deleted or reordered. Picking a
     * different row changes nothing about the pages, only which one is shown, and that is the
     * index sync below.
     */
    const key: string = this.currentLocationsKey();
    const listChanged: boolean = key !== this.locationsKey;
    this.locationsKey = key;

    /*
     * A unit change re-renders every page but does NOT rebuild any of them: the pages are the same
     * pages showing the same data, only formatted differently. So it bumps `dataVersion` (which
     * re-renders) and `bumpAllPages` (which re-keys the cards that cache formatted strings), but it
     * is deliberately NOT folded into `listChanged` — that branch exists to rebuild the ForEach
     * after the list itself changed, and a unit change must not pay for that.
     */
    const units: string = this.currentUnitsKey();
    if (units !== this.unitsKey) {
      this.unitsKey = units;
      this.bumpAllPages();
      this.dataVersion++;
    }

    if (!listChanged) {
      // No rebuild, so the Swiper can be moved straight away â€” the deferral below exists only to
      // outlive a rebuild.
      this.currentIndex = index;
      this.swiperController.changeIndex(index, false);
      this.onRefresh();
      return;
    }

    this.dataVersion++;
    setTimeout(() => {
      this.currentIndex = index;
      this.swiperController.changeIndex(index, false);
      // changeIndex does not fire onChange, so the arrival has to ask for its own refresh â€” which
      // is what fetches a location added moments ago and never fetched.
      this.onRefresh();
    }, 0);
  }

  aboutToAppear(): void {
    // The bar style has to be applied once before any state changes, or the first frame keeps the
    // system default until the first refresh lands.
    this.onBackgroundLightnessChanged();
    // Show the stored forecast first, then refresh over it â€” the order MainActivity uses. Without
    // this the screen is blank until the network answers, and stays blank forever if it does not.
    /*
     * The settings come first, and not just for tidiness: `isDark()` is evaluated on the very first
     * frame, so a screen built before they load would theme from the Kotlin's defaults and then
     * flip. They are a small key-value read, so this does not delay the cached forecast behind a
     * network call â€” it precedes a database read.
     */
    this.syncSystemDark();
    loadSettings(getContext(this) as common.UIAbilityContext).then((): void => {
      // Seeded here rather than left empty, so the FIRST return from the location list does not
      // read as a unit change and pay for a re-key it does not need.
      this.unitsKey = this.currentUnitsKey();
      // The first frame may already be up; bumping the version re-themes it.
      this.dataVersion++;
    });
    this.viewModel.loadCached(getContext(this) as Context).then((restored: boolean): void => {
      if (restored) {
        this.bumpAllPages();
      }
      /*
       * UNCONDITIONAL, unlike the page bump above.
       *
       * `restored` reports whether any stored FORECAST came back, but `loadCached` has replaced the
       * three seeded locations with the stored list by this point whether or not it did. The pager
       * reads `dataVersion` (see `pagerLocations`), so skipping the bump on a restore-less launch
       * would leave the Swiper holding the seeds against a toolbar reading the stored list â€” the
       * same desync, just reached by the fresh-cache path.
       */
      this.dataVersion++;
      // The stored list has replaced the seed by now, so a list rendered beside this screen has to
      // re-read it. Fired even when nothing was restored: "loading finished" is the useful signal,
      // and a pane built during the load is showing the seed either way.
      this.onDataLoaded();
      this.onRefresh();
    });
  }

  /**
   * `triggeredByUser` is the pull-to-refresh gesture, the one path that refetches a location whose
   * stored forecast is still valid. Every other caller — arriving, returning from the list,
   * swiping to another page — takes Android's `checkToUpdateCurrentLocation` route and does
   * nothing when the cache is fresh.
   */
  private onRefresh(triggeredByUser: boolean = false): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    // Captured now: by the time the fetch lands the user may have swiped, and it is THIS
    // location's page that has to be re-keyed, not whichever one happens to be current.
    const refreshed: LocationModel | null = this.viewModel.getCurrentLocation();
    const refreshedId: string = refreshed === null ? '' : refreshed.formattedId;
    this.viewModel.refresh(triggeredByUser).then((updated: boolean): void => {
      // MainActivityViewModel reports a failed refresh in a snackbar (RefreshErrorType.kt:57-68).
      // Without this the screen just sits blank when the network is down, because this port has
      // no cached forecast to fall back on.
      const error: string = this.viewModel.getLastError();
      if (error.length > 0) {
        this.viewModel.clearLastError();
        promptAction.showToast({ message: error, duration: 3000 });
      }
      this.loading = false;
      /*
       * Only a refresh that actually brought new data re-keys the pages.
       *
       * This bump was unconditional, and `onRefresh()` runs on every return from the location list,
       * so every trip destroyed and rebuilt all four Swiper pages even when nothing had changed.
       * A failed refresh now bumps nothing â€” which is the whole of the reported "tap Current
       * location and it freezes": with location services off that refresh ALWAYS fails, so every
       * selection of that row paid for a full rebuild and returned no data to show for it.
       */
      if (!updated) {
        return;
      }
      // Never remount the Swiper page while a drag is in flight â€” park the bump until endDrag.
      if (this.drag.draggingId.length > 0) {
        this.pendingDataBump = true;
        this.pendingBumpId = refreshedId;
      } else {
        this.bumpPage(refreshedId);
        this.dataVersion++;
      }
      // New weather changes what the row says â€” its condition text and its "Last updated" line.
      this.onDataLoaded();
    });
  }

  /* --------------------------------------------------- the edit dialog (MainActivity.kt:481-607) */

  /**
   * The location the dialog is editing, or null when it is closed.
   *
   * Scalars, not the LocationModel: handing a model to a @Param registers V2 observation bindings
   * across its whole weather graph, which is the cost LocationSources and LocationRowModel were
   * both introduced to avoid.
   */
  @Local private editTarget: LocationSources | null = null;
  @Local private editPlace: string = '';
  @Local private editCustomName: string = '';
  @Local private editWeatherModels: string = '';

  /** MainActivity.kt:897-904 */
  private onEditIconClicked(): void {
    if (this.loading) {
      // strings.xml:553
      promptAction.showToast({ message: 'Please wait for refresh to complete' });
      return;
    }
    const location: LocationModel | null = this.currentLocation();
    if (location === null) {
      // kt:488 — `location?.let { ... }`; with nothing selected the dialog simply does not open.
      return;
    }
    this.editPlace = cityAndDistrict(location.city, location.district);
    this.editCustomName = location.customName;
    this.editWeatherModels = location.weatherModels;
    // Assigned LAST, so the dialog never builds against a half-filled set of params.
    this.editTarget = LocationSources.from(location);
  }

  /** The location the open dialog belongs to, or null if it has moved out from under us. */
  private editedLocation(): LocationModel | null {
    if (this.editTarget === null) {
      return null;
    }
    const index: number = this.viewModel.indexOf(this.editTarget.formattedId);
    return index < 0 ? null : this.viewModel.getLocations()[index];
  }

  /**
   * LocationPreferences.kt:151-172 — the nested sources dialog saved.
   *
   * The duplicate branch (kt:153-164) cannot fire in this port: the sources dialog refuses to move
   * off Open-Meteo, so the forecast source never changes and `locationExists` is never consulted.
   * The plain update branch is the one that runs.
   */
  private onEditSourcesSaved(sources: LocationSources): void {
    const location: LocationModel | null = this.editedLocation();
    if (location === null || !sources.changed) {
      return; // kt:880 — nothing changed, so nothing is written.
    }
    sources.applyTo(location);
    this.persistEdit(location, true);
  }

  /** kt:234-256 — the per-location preferences dialog saved. */
  private onEditPrefsSaved(result: LocationPrefsResult): void {
    const location: LocationModel | null = this.editedLocation();
    if (location === null || !result.changed) {
      return;
    }
    /*
     * Compared RESOLVED, not raw.
     *
     * A location that has never been configured stores '' and the dialog hands back the explicit
     * `best_match` — the same selection written two ways. A raw string compare called that a change
     * and refetched, so renaming a location cost a network round trip. That is precisely the
     * "will trigger a full refresh which we should avoid" the Kotlin's own TODO complains about
     * (kt:239-240), reintroduced by the port rather than inherited from it.
     */
    const modelsChanged: boolean =
      selectedWeatherModels(location.weatherModels).join(',') !==
        selectedWeatherModels(result.weatherModels).join(',');
    location.customName = result.customName;
    location.weatherModels = result.weatherModels;
    // The toolbar title reads `getPlace`, so a renamed location has to repaint even when no
    // refetch follows.
    this.editCustomName = result.customName;
    this.editWeatherModels = result.weatherModels;
    /*
     * kt:239-254 nulls every update time "which will trigger a full refresh". A NAME change alone
     * has no business refetching — the Kotlin's own comment calls that out as a TODO — but a model
     * change does, because the models are what the request asks for.
     */
    this.persistEdit(location, modelsChanged);
  }

  /**
   * Writes the edited location back and, when the change affects the DATA rather than the label,
   * clears the refresh stamp so the next refresh is a full one.
   */
  private persistEdit(location: LocationModel, refetch: boolean): void {
    if (refetch && location.weather !== null) {
      location.weather.refreshTime = null;
    }
    this.viewModel.persistLocations();
    this.dataVersion++;
    if (refetch) {
      this.onRefresh(true);
    }
  }

  /** MainActivity.kt:577-581 — Confirm on the delete dialog. */
  private onEditDelete(): void {
    const target: LocationSources | null = this.editTarget;
    this.editTarget = null;
    if (target === null) {
      return;
    }
    const index: number = this.viewModel.indexOf(target.formattedId);
    if (index < 0) {
      return;
    }
    this.viewModel.deleteLocation(index).then((removed: LocationModel | null) => {
      if (removed === null) {
        return;
      }
      /*
       * The pager has one page fewer. Clamping first stops the Swiper being asked for an index
       * past its end when the LAST location was the one deleted.
       */
      const total: number = this.viewModel.getLocations().length;
      const next: number = this.currentIndex >= total ? total - 1 : this.currentIndex;
      this.viewModel.setCurrentIndex(next);
      this.currentIndex = next;
      this.dataVersion++;
      this.onDataLoaded();
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // MaterialWeatherView sits behind everything, filling the window (HomeFragment's
      // weather_view). The flat theme colour is painted by the canvas itself, so the Stack no
      // longer needs a backgroundColor of its own.
      WeatherBackground({
        kind: this.weatherKindFor(this.currentLocation()),
        daylight: this.daylightFor(this.currentLocation()),
        darkMode: this.isDark(),
        sceneColor: this.backgroundColorFor(this.currentLocation()),
        scrollRate: this.backgroundScrollRate,
        /*
         * Stops the frame loop while the location list or search screen is on top of this page,
         * holds it still while the two-pane list beside it is being scrolled — and now also honours
         * screen 3c's `background_animation_mode` (MainScreenSettingsScreen.kt:165-186).
         *
         * "system" is the default and means animate; "disabled" paints the scene once and leaves it
         * still. There is no HarmonyOS reduced-motion flag to consult, so "system" cannot mean
         * anything narrower here — the limitation screen 3c already documents for `isMotionReduced`.
         */
        animate: this.pageVisible && this.backgroundAnimates &&
          AppSettings.instance.backgroundAnimation !== 'disabled',
        /*
         * screen 3c's `main_screen_background` (kt:127-138). Off means no weather scene at all:
         * MaterialWeatherView is not drawn and the page falls back to the flat surface colour,
         * which is what the Kotlin's `mainScreenBackgroundEnabled` does.
         */
        sceneEnabled: AppSettings.instance.mainScreenBackground,
        /*
         * screen 3c's `gravity_sensor_switch` (kt:188-197), passed in exactly as
         * HomeFragment.kt:179-181 does. `pageVisible` is part of it because upstream unregisters
         * the listener the moment the view stops being drawable (MaterialPainterView.kt:90) — a
         * backgrounded screen must not keep a sensor subscription open.
         */
        gravitySensorEnabled: this.pageVisible && AppSettings.instance.gravitySensor
      })

      Column() {
        MainToolbar({
          title: this.titleFor(this.currentLocation()),
          hasLocation: this.currentLocation() !== null,
          contentColor: this.onBackgroundColor(),
          // MainActivity.kt:916-918
          onManageIconClicked: () => {
            // HomeFragment.kt:193-197 â†’ setManagementFragmentVisibility(true). Screen 2 is real
            // now, so this is a route rather than a placeholder.
            this.openLocationList();
          },
          onEditIconClicked: () => {
            this.onEditIconClicked();
          },
          // MainActivity.kt:906-914
          onOpenInOtherAppIconClicked: () => {
            goPlaceholder('Open in another app');
          }
        })

        Swiper(this.swiperController) {
          /*
           * PURE IDENTITY. A page is built once per location and is never destroyed by a refresh.
           *
           * The key used to carry a version counter, because `LocationModel` was a plain object
           * that `refresh()` mutated â€” nothing about the new weather was observable, so the only
           * way to show it was to re-key the ForEach and rebuild the whole subtree. That rebuild
           * is a 4.6 s frame, and since it shares a frame with the toolbar's own re-render, the
           * screen kept showing the previous location's name for seconds after a selection.
           *
           * `LocationModel` is now @ObservedV2 with the four fields a refresh settles marked
           * @Trace, so the fragments below that read `location.weather` re-execute on their own
           * and the key does not have to lie about identity to get them to update.
           */
          /*
           * PURE IDENTITY. A page is built once per location and is never destroyed.
           *
           * The version counter that used to be here existed only to force a rebuild when
           * 
efresh() replaced weather on a plain object. LocationPage now owns those reads
           * against an @ObservedV2 model, so it re-renders itself and the key can mean what it
           * says. Measured: 5.9-7.0 s to show a selected location, down to 1.5 s.
           */
          /*
           * PURE IDENTITY. A page is built once per location and is never destroyed by a refresh.
           *
           * A PAGE WINDOW WAS TRIED TWICE HERE AND REVERTED BOTH TIMES. Building only the current
           * page and its neighbours is what ViewPager2 does, and it measured well — 10.5 MB less
           * PSS, 12.9 MB less native heap, 52 ms faster to first frame. It is not worth what it
           * costs in this port:
           *
           *   attempt 1  a page built fresh showed nothing but its footer. That fault was
           *              EnterAnimated's, not the window's, and is fixed (see its fallback).
           *   attempt 2  with that fixed, SELECTING a location froze the app for six seconds
           *              (appfreeze THREAD_BLOCK_6S, 2026-08-08 22:40, RSS 589 MB).
           *
           * The second is the real objection and it is structural. A window means the selected
           * page is BUILT on selection, and building one runs `syncSeries` -> `copyTrendItem`,
           * which writes @Trace fields one at a time; each write fires V2 change notification, and
           * the stack sat in PartialGC/ParallelEvacuator under `fireChange` -> `runIdleTasks`.
           * Holding every page means that work happens once at startup instead of on every tap.
           *
           * So the trend-series sync is the thing to fix, not the pager. Until `copyTrendItem`
           * stops being a storm of individual @Trace writes, a window converts a memory win into a
           * six-second stall on the most common interaction there is.
           */
          ForEach(this.pagerLocations(), (location: LocationModel) => {
            this.locationPage(location)
          }, (location: LocationModel) =>
          location.formattedId)
        }
        .index(this.currentIndex)
        .loop(false)
        .indicator(false)
        .layoutWeight(1)
        .onChange((index: number) => {
          // HomeFragment.kt:489-496 â€” switching locations.
          const previous: LocationModel | null = this.currentLocation();
          if (previous !== null && previous.weather !== null && previous.weather.current !== null &&
            previous.weather.current.temperature !== null &&
            previous.weather.current.temperature.temperature !== null) {
            this.previousTemperature = previous.weather.current.temperature.temperature;
          }
          this.viewModel.setCurrentIndex(index);
          this.currentIndex = index;
          this.indicatorDisplayed = false;
          // MainActivityViewModel refreshes the location you switch to when its weather is stale.
          // Only the location that was on screen at launch has been fetched, so the others still
          // hold seeded values until they are swiped to.
          this.onRefresh();
        })
        .onAnimationStart(() => {
          // HomeFragment.kt:477-487 â€” the indicator appears while the swipe is in progress.
          this.indicatorDisplayed = true;
        })
        .onAnimationEnd(() => {
          this.indicatorDisplayed = false;
        })
      }
      .width('100%')
      .height('100%')
      /*
       * The window is laid out full screen (SystemBars.enableEdgeToEdge), so the weather
       * background paints through the status bar the way MaterialWeatherView does behind an
       * edge-to-edge Activity. The toolbar still has to start below it: Android gets the same
       * offset from `doOnApplyWindowInsets` on the AppBar, and the footer keeps clear of the
       * navigation bar from the RecyclerView's own bottom inset (HomeFragment.kt:265-267).
       */
      .padding({ top: this.insets.top, bottom: this.insets.bottom })

      InkPageIndicator({
        total: this.viewModel.getIndicator().total,
        currentIndex: this.currentIndex,
        displayed: this.indicatorDisplayed
      })

      /*
       * MainActivity.kt:481-607 — the edit dialog, over everything including the indicator.
       *
       * `editTarget` is what gates it rather than a boolean, because the dialog's @Params are
       * scalars taken from the location at the moment it opened; keeping the two in one field
       * means they cannot disagree.
       */
      if (this.editTarget !== null) {
        LocationPreferenceDialog({
          target: this.editTarget,
          place: this.editPlace,
          customName: this.editCustomName,
          weatherModels: this.editWeatherModels,
          dark: this.isDark(),
          // kt:530 — no Delete button while this is the only saved location.
          canDelete: this.viewModel.getLocations().length > 1,
          onDismiss: () => {
            this.editTarget = null;
          },
          onSourcesSaved: (sources: LocationSources) => {
            this.onEditSourcesSaved(sources);
          },
          onPrefsSaved: (result: LocationPrefsResult) => {
            this.onEditPrefsSaved(result);
          },
          onDelete: () => {
            this.onEditDelete();
          },
          locationExists: (latitude: number, longitude: number, forecastSource: string) =>
          this.viewModel.locationExistsAt(latitude, longitude, forecastSource)
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** The weather kind driving the background scene. */
  private weatherKindFor(location: LocationModel | null): WeatherKind {
    if (location === null || location.weather === null || location.weather.current === null) {
      return WeatherKind.NULL;
    }
    return location.weather.current.weatherKind;
  }

  private daylightFor(location: LocationModel | null): boolean {
    return location === null ? true : location.daylight;
  }

  @Builder
  locationPage(location: LocationModel) {
    /*
     * A COMPONENT, not inline content â€” see LocationPage for the full reason.
     *
     * The structural guards moved in there so they re-evaluate when this location's forecast
     * lands, which is what lets the Swiper's ForEach key go back to pure identity. The card
     * content stays here, passed through @BuilderParam, because it is tuned code that has no
     * reason to move.
     */
    LocationPage({
      location: location,
      loading: this.loading,
      drag: this.drag,
      // Re-runs the blocks builder when a unit preference changes — see LocationPage.unitsVersion.
      unitsVersion: this.dataVersion,
      onRefreshPulled: () => {
        // A REAL pull — LocationPage only calls this after the finger has dragged the page, see
        // its `onStateChange`. That is Android's `triggeredByUser` path (MainActivity.kt:733),
        // which goes straight to `updateWithUpdatingChecking` and skips the "already valid" check.
        this.onRefresh(true);
      },
      scrollerOf: () => this.scrollerFor(location),
      onScrolled: () => {
        this.onPageScrolled(location);
      },
      onWidthChanged: (width: number) => {
        if (width > 0 && Math.abs(width - this.contentWidth) > 0.5) {
          this.contentWidth = width;
        }
      },
      hasAlerts: () => this.hasAlerts(location),
      hasNowcast: () => this.hasNowcast(location),
      cardsVersion: this.cardsVersion,
      cardEnabled: (id: string) => this.cardEnabled(id),
      headerContent: () => {
        this.headerCardFor(location)
      },
      alertContent: () => {
        this.alertCardFor(location)
      },
      nowcastContent: () => {
        this.nowcastCardFor(location)
      },
      dailyContent: () => {
        this.dailyCardWrapped(location)
      },
      hourlyContent: () => {
        this.hourlyCardWrapped(location)
      },
      blocksContent: () => {
        this.detailBlocks(location)
      },
      footerContent: () => {
        this.footerCardFor()
      }
    })
  }

  /** MaterialWeatherView.onScroll (kt:178-186): rate = min(1, scrollY / mFirstCardMarginTop). */
  private onPageScrolled(location: LocationModel): void {
    const offset: number = this.scrollerFor(location).currentOffset().yOffset;
    const rate: number = Math.max(0, Math.min(1, offset / BACKGROUND_SCROLL_SPAN));
    if (Math.abs(rate - this.backgroundScrollRate) > 0.01) {
      this.backgroundScrollRate = rate;
    }
    // Snapping the last hundredth matters: the animation only stops at exactly 1.
    if (rate >= 1 && this.backgroundScrollRate < 1) {
      this.backgroundScrollRate = 1;
    }
  }

  @Builder
  headerCardFor(location: LocationModel) {
    HeaderCard({
      location: location,
      previousTemperature: this.previousTemperature,
      textColor: this.onBackgroundColor(),
      // Bumped by the unit-change branch of onReturnedToPage, so the "°C"/"°F" beside the big
      // number follows the setting — see HeaderCard.unitsVersion.
      unitsVersion: this.dataVersion,
      /*
       * screen 3c's `item_animation_switch` (kt:230-249). In this port the header's count-up is
       * the only per-element animation there is — the progress arcs are painted at their final
       * value rather than swept, so there is nothing else for the switch to turn off.
       */
      animationEnabled: AppSettings.instance.elementAnimations
    })
  }

  /*
   * MainAdapter.kt:107-109 â€” the alert card sits directly under the header, ahead of every
   * reorderable card. Every card is wrapped in EnterAnimated: on Android they all extend
   * AbstractMainViewHolder, so they all get checkEnterScreen's staggered entrance.
   */
  @Builder
  alertCardFor(location: LocationModel) {
    EnterAnimated({ cardId: 'alert' }) {
      AlertCard({
        currentAlerts: this.currentAlerts(location),
        utcOffsetSeconds: location.utcOffsetSeconds,
        // container_main_alert.xml tints the card with @color/alert_background â€” a filled pill.
        cardBackground: AppColors.ALERT_BACKGROUND.resolve(this.isDark()),
        // AlertViewHolder uses colorScheme.onSurface for the headline and icon, not
        // colorSurfaceInverse â€” the two differ in the light theme.
        onSurface: AppColors.ON_SURFACE.resolve(this.isDark()),
        onSurfaceVariant: AppColors.ON_SURFACE_VARIANT.resolve(this.isDark()),
        onAlertClick: () => {
          goAlertList(location.formattedId);
        },
        onSingleAlertClick: (alertId: string) => {
          goAlertList(location.formattedId, alertId);
        }
      })
    }
  }

  @Builder
  nowcastCardFor(location: LocationModel) {
    EnterAnimated({ cardId: 'nowcast' }) {
      MinutelyCard({
        minutely: (location.weather as Weather).minutelyForecast,
        utcOffsetSeconds: location.utcOffsetSeconds,
        cardBackground: AppColors.MAIN_CARD_BACKGROUND.resolve(this.isDark()),
        onSurfaceInverse: AppColors.SURFACE_INVERSE.resolve(this.isDark()),
        bodyTextColor: AppColors.BODY_TEXT.resolve(this.isDark()),
        lineColor: AppColors.OUTLINE.resolve(this.isDark()),
        labelColor: this.isDark() ? AppColors.TEXT_GREY_2ND : AppColors.TEXT_GREY,
        // PrecipitationNowcastViewHolder.kt:193-202 â€” always the rainy theme's first colour.
        columnColor: getThemeColors(WeatherKind.RAINY, location.daylight && !this.isDark())[0],
        // The marker pill — `colorPrimary` on `colorOnPrimary` (kt:165-167).
        markerBackground: AppColors.PRIMARY.resolve(this.isDark()),
        markerTextColor: AppColors.ON_PRIMARY.resolve(this.isDark()),
        redrawKey: location.formattedId + ':' + this.pageVersion(location.formattedId).toString()
      })
    }
  }

  @Builder
  dailyCardWrapped(location: LocationModel) {
    EnterAnimated({ cardId: 'daily' }) {
      this.dailyCard(location)
    }
  }

  @Builder
  hourlyCardWrapped(location: LocationModel) {
    EnterAnimated({ cardId: 'hourly' }) {
      this.hourlyCard(location)
    }
  }

  @Builder
  footerCardFor() {
    FooterCard({
      sourceName: FORECAST_SOURCE_NAME,
      contentColor: this.onBackgroundColor(),
      onSourceClick: () => {
        goPlaceholder('Open-Meteo attribution link');
      },
      onMoreClick: () => {
        goPlaceholder('Data sources');
      }
    })
  }

  /**
   * The half-width blocks. ViewType.isHalfSizeableBlock (ViewType.kt:39-45) marks these as
   * half-sizeable, and MainLayoutManager lays them out getBlocksPerRow() to a row â€” two on a
   * phone. Each block already carries its own 8dp margin, so the grid adds no gaps.
   *
   * Drag-to-reorder is implemented by hand rather than with Grid.editMode(true).
   *
   * editMode was tried and does not work here: ArkUI hides the dragged GridItem and owns the
   * drag session, so the cards below vanish for the duration, and reordering the data source
   * from onItemDragMove â€” the way Android's ItemTouchHelper does â€” invalidates that session
   * mid-gesture, which made the tile blink, detach and land in an unrelated slot.
   *
   * So the gesture is explicit, matching ItemTouchHelper's actual behaviour
   * (MainAdapter.kt:316-341): long-press starts the drag, the pressed card is raised and follows
   * the finger, and every time its centre crosses into another slot the two entries are swapped
   * (kt:305-311) so the displaced card animates into the vacated one. Nothing is ever hidden.
   */
  @Builder
  detailBlocks(location: LocationModel) {
    Grid() {
      ForEach(this.orderedBlocks(location), (block: DetailBlock, index: number) => {
        GridItem() {
          HalfBlockCard({
            block: block,
            cardBackground: AppColors.MAIN_CARD_BACKGROUND.resolve(this.isDark()),
            contentColor: AppColors.SURFACE_INVERSE.resolve(this.isDark()),
            secondaryColor: AppColors.ON_SURFACE_VARIANT.resolve(this.isDark()),
            isDark: this.isDark(),
            presetSide: this.blockSide(),
            onCardClick: () => {
              if (this.drag.draggingId.length === 0) {
                // Screen 4. A block carries no day of its own, so it opens on today —
                // DetailsActivity's initialIndex for a tile is the current day.
                const today: number | null =
                  location.weather === null ? null : location.weather.todayIndex;
                goDetails(location.formattedId, block.detailScreen, today === null ? 0 : today);
              }
            }
          })
        }
        // The dragged card rides above its neighbours and carries a deeper shadow, matching
        // ItemTouchHelper's translationZ = findMaxElevation + 1 over the cards' own 2dp.
        .zIndex(this.drag.draggingId === block.id ? 1 : 0)
        .translate(this.drag.translationFor(block.id))
        // Shared constants, for the same reason dragTranslation returns one: a fresh options
        // object per call reads as a changed attribute on every pan event.
        .shadow(this.drag.draggingId === block.id ? DRAG_SHADOW : NO_SHADOW)
        // NO `.animation(...)` here â€” this was wrong twice over, and it is why the drop snapped
        // instead of gliding:
        //   - An implicit per-attribute animation OVERRIDES an enclosing animateTo for the
        //     attributes it covers, so endDrag's 200 ms settle was being flattened to 0 ms by the
        //     dragged card's `.animation({duration: 0})` â€” the card teleported home on release.
        //   - It never animated the siblings anyway: a swap moves them by ForEach reorder, which
        //     is a layout change, not an attribute change, so the 250 ms glide it promised never
        //     ran once. The displaced card's glide is done by hand instead â€” see
        //     reorderFromPointer, which offsets it back to its old slot and animates that to zero,
        //     exactly what RecyclerView's DefaultItemAnimator does after an instant re-layout.
        // priorityGesture, NOT gesture.
        //
        // This is why the drag never started. HalfBlockCard puts `.onClick` on its own inner
        // Stack, so a ClickRecognizer sits *deeper* in the touch-test chain than this
        // GestureGroup. ArkUI resolves competing recognisers innermost-first, and a click only
        // settles on touch-up â€” so the long press stayed blocked behind it for the whole press
        // and was discarded the moment the finger lifted. The card was never draggable; it just
        // reported a tap.
        //
        // priorityGesture puts this group ahead of its descendants' gestures, which is exactly
        // the case it exists for. A short press still falls through to the card's onClick once
        // this group fails to recognise.
        .priorityGesture(
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false })
              .onAction(() => {
                // A drag whose settle-and-commit has not finished still owns the translate
                // state; starting a second one against it would freeze a snapshot the ForEach
                // is not actually rendering. The commit runs 200 ms after release, long before
                // another 500 ms long-press can complete, so this rejects only true overlaps.
                if (this.drag.draggingId.length > 0) {
                  return;
                }
                // Freeze the order the ForEach is rendering; everything until the commit is
                // translates against this snapshot.
                this.drag.dragBaseOrder = this.drag.cardOrder.slice();
                this.drag.shiftedTranslates = new Map();
                this.drag.draggingId = block.id;
                this.drag.dragDX = 0;
                this.drag.dragDY = 0;
              }),
            PanGesture({ distance: 1 })
              .onActionUpdate((event: GestureEvent) => {
                if (this.drag.draggingId !== block.id) {
                  return;
                }
                this.drag.dragDX = event.offsetX;
                this.drag.dragDY = event.offsetY;
                this.reorderFromPointer(location);
              })
              .onActionEnd(() => {
                this.endDrag();
              })
              .onActionCancel(() => {
                this.endDrag();
              })
          )
        )
        /*
         * The key carries the PAGE version but still must NOT carry the ORDER version.
         *
         * Order version: including it makes every drop rebuild all the GridItems from scratch,
         * which re-runs each card's onAreaChange and makes the shapes visibly settle a beat after
         * the drop. With a stable key ForEach moves the existing items instead. That stays true.
         *
         * Page version: `DetailBlock` is a plain class and `HalfBlockCard` takes it as a @Param,
         * and ForEach does not re-run its item builder for an item whose key is unchanged — it
         * keeps the child it already has. So a rebuilt block array never reached the cards: the
         * values were recomputed, the caches missed and refilled, and the grid went on drawing the
         * previous strings. That is why changing the pressure unit left "1015 hPa" on screen while
         * the header had already switched, and it is fixed by letting the key change when the page
         * data does.
         *
         * The two versions move independently, which is what makes this safe: a drag bumps only
         * `orderVersion`, so these keys stay stable for the whole gesture and the drop still
         * reorders existing items rather than rebuilding them. `pageVersion` changes only when a
         * refresh brings new weather or a unit preference changes — exactly when a rebuild is the
         * point.
         */
      }, (block: DetailBlock) =>
      block.id + ':' + this.pageVersion(location.formattedId).toString())
    }
    .width('100%')
    // Each card is a square inset by its own 8dp margin, so a row is exactly one column wide.
    .height(Math.ceil(this.orderedBlocks(location).length / this.blocksPerRow()) * (this.contentWidth / this.blocksPerRow()))
    .columnsTemplate(this.columnsTemplate())
    .scrollBar(BarState.Off)
    // The grid must not scroll or intercept: the page Scroll owns vertical movement, and the
    // drag gesture lives on the individual GridItems.
    .enableScrollInteraction(false)
  }


  /** Grid slot index â†’ its top-left offset delta from another slot, in vp. */
  private slotDelta(fromIndex: number, toIndex: number, side: number): TranslateOptions {
    const dx: number = (toIndex % this.blocksPerRow() - fromIndex % this.blocksPerRow()) * side;
    const dy: number = (Math.floor(toIndex / this.blocksPerRow()) - Math.floor(fromIndex / this.blocksPerRow())) * side;
    return { x: dx, y: dy };
  }

  /** Recomputes every card's persistent shift from the frozen snapshot to the live order. */
  private rebuildShiftedTranslates(side: number): void {
    const shifted: Map<string, TranslateOptions> = new Map();
    for (let i = 0; i < this.drag.cardOrder.length; i++) {
      const id: string = this.drag.cardOrder[i];
      if (id === this.drag.draggingId) {
        continue;
      }
      const baseIndex: number = this.drag.dragBaseOrder.indexOf(id);
      if (baseIndex >= 0 && baseIndex !== i) {
        shifted.set(id, this.slotDelta(baseIndex, i, side));
      }
    }
    this.drag.shiftedTranslates = shifted;
  }

  /**
   * ItemTouchHelper.onMove â€” when the dragged card's centre moves into another card's slot, the
   * two swap (MainAdapter.kt:305-311). Slots are a fixed grid of square cells, so the target is
   * pure arithmetic; no hit-testing is needed.
   *
   * This is safe to do mid-gesture, unlike the editMode version: the gesture belongs to this
   * component, so reordering the data source cannot invalidate it. `dragFromIndex` is re-based
   * after every swap and the offset is rebased with it, so the card stays under the finger.
   */
  private reorderFromPointer(location: LocationModel): void {
    const side: number = this.contentWidth / this.blocksPerRow();
    if (side <= 0 || this.drag.draggingId.length === 0) {
      return;
    }
    const count: number = this.orderedBlocks(location).length;
    // The dragged card renders in its FROZEN slot for the whole gesture (see dragBaseOrder), so
    // its centre is the frozen slot plus the raw finger offset â€” no rebasing anywhere.
    const origIndex: number = this.drag.dragBaseOrder.indexOf(this.drag.draggingId);
    const fromIndex: number = this.drag.cardOrder.indexOf(this.drag.draggingId);
    if (origIndex < 0 || fromIndex < 0) {
      return;
    }
    const centreX: number = (origIndex % this.blocksPerRow() + 0.5) * side + this.drag.dragDX;
    const centreY: number = (Math.floor(origIndex / this.blocksPerRow()) + 0.5) * side + this.drag.dragDY;

    let col: number = Math.floor(centreX / side);
    let row: number = Math.floor(centreY / side);
    col = Math.max(0, Math.min(this.blocksPerRow() - 1, col));
    row = Math.max(0, Math.min(Math.ceil(count / this.blocksPerRow()) - 1, row));

    const target: number = row * this.blocksPerRow() + col;
    if (target === fromIndex || target < 0 || target >= count) {
      return;
    }

    // The card being displaced â€” it moves from `target` into the slot the drag vacates.
    // MainAdapter.onItemMove (kt:305-311): a swap of the two entries. The data order changes
    // silently (no orderVersion bump â€” nothing rebuilds); the ForEach keeps rendering the frozen
    // order and the shift is expressed as translates.
    const displaced: string = this.drag.cardOrder[target];
    const displacedFromSlot: number = target;
    const displacedToSlot: number = fromIndex;
    this.drag.swap(fromIndex, target);
    this.rebuildShiftedTranslates(side);

    // DefaultItemAnimator's move, by hand: the displaced card's persistent shift now points at
    // its new slot; the transient offset starts it back at the old slot and glides to zero.
    // Both state writes are single JS updates â€” the 250 ms interpolation runs natively.
    this.drag.displacedId = displaced;
    const back: TranslateOptions = this.slotDelta(displacedToSlot, displacedFromSlot, side);
    this.drag.displacedDX = back.x as number;
    this.drag.displacedDY = back.y as number;
    animateTo({
      duration: SIBLING_SETTLE_MS,
      curve: Curve.Friction,
      onFinish: () => {
        if (this.drag.displacedId === displaced) {
          this.drag.displacedId = '';
        }
      }
    }, () => {
      this.drag.displacedDX = 0;
      this.drag.displacedDY = 0;
    });
  }

  /**
   * Release â€” the card glides into its final slot, and only when everything has stopped moving
   * is the real reorder committed. The commit resets every translate in the same state batch
   * that reorders the ForEach, so the rebuild lands on cards that are already exactly where the
   * new order puts them â€” a visual no-op. The one expensive rebuild therefore happens after the
   * gesture, on a static screen, instead of under the finger.
   */
  private endDrag(): void {
    const dragged: string = this.drag.draggingId;
    if (dragged.length === 0) {
      return;
    }
    const side: number = this.contentWidth / this.blocksPerRow();
    const origIndex: number = this.drag.dragBaseOrder.indexOf(dragged);
    const finalIndex: number = this.drag.cardOrder.indexOf(dragged);
    // Where the card must come to rest, measured from its frozen render slot.
    const home: TranslateOptions = origIndex >= 0 && finalIndex >= 0 && side > 0
      ? this.slotDelta(origIndex, finalIndex, side)
      : NO_TRANSLATE;
    // draggingId survives the settle: clearing it early makes dragTranslation() fall through and
    // the card teleport. It is cleared in the commit, which also keeps the raised shadow up
    // until the card has landed, as ItemTouchHelper does.
    animateTo({
      duration: 200,
      curve: Curve.Friction,
      onFinish: () => {
        if (this.drag.draggingId !== dragged) {
          return;
        }
        // The commit: reorder the ForEach and zero every translate in one synchronous batch.
        this.drag.draggingId = '';
        this.drag.displacedId = '';
        this.drag.dragDX = 0;
        this.drag.dragDY = 0;
        this.drag.shiftedTranslates = new Map();
        this.drag.dragBaseOrder = [];
        this.drag.orderVersion++;
        // kt:311 — the drop writes the new order to `card_display`, the same setting screen 3h edits.
        this.persistCardOrder();
        // A refresh parked mid-drag (the ForEach key carries dataVersion, so a bump remounts
        // every Swiper page) is applied now that the gesture is over.
        if (this.pendingDataBump) {
          this.pendingDataBump = false;
          this.bumpPage(this.pendingBumpId);
          this.dataVersion++;
        }
      }
    }, () => {
      this.drag.dragDX = home.x as number;
      this.drag.dragDY = home.y as number;
    });
  }

  /**
   * What follows the finger while a card is being dragged.
   * Not `dragPreview`: every component already inherits a `dragPreview()` attribute method.
   */
  @Builder
  draggedBlockPreview() {
    Column() {
      HalfBlockCard({
        block: this.draggedBlock,
        cardBackground: AppColors.MAIN_CARD_BACKGROUND.resolve(this.isDark()),
        contentColor: AppColors.SURFACE_INVERSE.resolve(this.isDark()),
        secondaryColor: AppColors.ON_SURFACE_VARIANT.resolve(this.isDark()),
        isDark: this.isDark(),
        presetSide: this.blockSide()
      })
    }
    .width(this.contentWidth / this.blocksPerRow())
  }

  /** AlertViewHolder.kt:77 â€” any alert that has not expired keeps the card on screen. */
  private hasAlerts(location: LocationModel): boolean {
    const weather: Weather | null = location.weather;
    return weather !== null && weather.hasActiveAlerts(new Date());
  }

  private currentAlerts(location: LocationModel): Alert[] {
    const weather: Weather | null = location.weather;
    return weather === null ? [] : weather.currentAlerts(new Date());
  }

  /** MainAdapter.kt:110-115 â€” needs minutely precipitation and at least three buckets. */
  private hasNowcast(location: LocationModel): boolean {
    const weather: Weather | null = location.weather;
    if (weather === null) {
      return false;
    }
    return weather.hasMinutelyPrecipitation() && weather.minutelyForecast.length >= 3;
  }

  /**
   * MainAdapter.onItemMove (kt:305-311) â€” a swap of the two entries, not a move-and-shift.
   * Deliberately does NOT bump orderVersion: during a drag the order changes silently and the
   * ForEach keeps its frozen order; endDrag's commit bumps the version exactly once.
   */

  /**
   * MainLayoutManager's span count for a half-sizeable block, from the grid's measured width.
   *
   * Reading `contentWidth` is what makes this react to a rotation: it is @Local, so every builder
   * that asks for the block count re-runs when the page is re-measured in the new orientation.
   */
  private blocksPerRow(): number {
    return blocksPerRowFor(this.contentWidth);
  }

  /** `1fr` per block â€” the Grid equivalent of GridLayoutManager's span count. */
  private columnsTemplate(): string {
    const columns: number = this.blocksPerRow();
    let template: string = '1fr';
    for (let i = 1; i < columns; i++) {
      template += ' 1fr';
    }
    return template;
  }

  /** The square side each card gets: half the content width, less its own 8dp margin per side. */
  private blockSide(): number {
    return Math.max(0, this.contentWidth / this.blocksPerRow() - 2 * Dimens.SMALL_MARGIN);
  }

  @Builder
  dailyCard(location: LocationModel) {
    TrendCard({
      // strings.xml:7
      title: 'Daily forecast',
      titleIcon: $r('app.media.ic_calendar'),
      subtitle: location.weather !== null && location.weather.current !== null
        ? location.weather.current.dailyForecast
        : null,
      tabs: this.dailyTabs(),
      seriesFor: (tabIndex: number): SeriesBundle => this.dailyBundle(location, tabIndex),
      refreshStamp: this.pageVersion(location.formattedId).toString() + ':' + this.titleTextColor(),
      isDaily: true,
      // screen 3c's `trend_horizontal_line_switch` (kt:139-157).
      keyLinesEnabled: AppSettings.instance.trendHorizontalLines,
      listHeight: Dimens.DAILY_TREND_ITEM_HEIGHT,
      // DailyViewHolder.kt:156-158 â€” open scrolled to today.
      initialIndex: location.weather !== null && location.weather.todayIndex !== null
        ? location.weather.todayIndex
        : 0,
      cardBackground: AppColors.MAIN_CARD_BACKGROUND.resolve(this.isDark()),
      // container_main_*_trend_card.xml:21,31 â€” the title icon and title use
      // ?attr/colorSurfaceInverse (= md_theme_inverseSurface, styles.xml:29), not onSurface.
      onSurfaceInverse: AppColors.SURFACE_INVERSE.resolve(this.isDark()),
      bodyTextColor: AppColors.BODY_TEXT.resolve(this.isDark()),
      captionTextColor: AppColors.CAPTION_TEXT.resolve(this.isDark()),
      accentTextColor: AppColors.TITLE_TEXT.resolve(this.isDark()),
      keyLineColor: AppColors.OUTLINE.resolve(this.isDark()),
      keyLineTextColor: this.isDark() ? AppColors.TEXT_GREY_2ND : AppColors.TEXT_GREY,
      // The chips are Material buttons; their containers have to follow the card's theme, or a
      // dark card keeps pale lavender chips where Android's are dark grey.
      chipContainerColor: AppColors.SURFACE_VARIANT.resolve(this.isDark()),
      chipSelectedContainerColor: AppColors.PRIMARY.resolve(this.isDark()),
      chipLabelColor: AppColors.ON_SURFACE_VARIANT.resolve(this.isDark()),
      chipSelectedLabelColor: AppColors.ON_PRIMARY.resolve(this.isDark()),
      chartColors: this.chartColorsFor(location),
      doubleChartColors: this.doubleChartColorsFor(location),
      onItemClick: (tabIndex: number, itemIndex: number) => {
        const tab: TrendTab = this.dailyTabs()[tabIndex];
        // A daily column IS the day, so it opens the pager on that page directly.
        goDetails(location.formattedId, tab.detailScreen, itemIndex);
      }
    })
  }

  @Builder
  hourlyCard(location: LocationModel) {
    TrendCard({
      // strings.xml:8
      title: 'Hourly forecast',
      titleIcon: $r('app.media.ic_schedule'),
      subtitle: location.weather !== null && location.weather.current !== null
        ? location.weather.current.hourlyForecast
        : null,
      tabs: this.hourlyTabs(),
      seriesFor: (tabIndex: number): SeriesBundle => this.hourlyBundle(location, tabIndex),
      refreshStamp: this.pageVersion(location.formattedId).toString() + ':' + this.titleTextColor(),
      isDaily: false,
      // screen 3c's `trend_horizontal_line_switch` (kt:139-157).
      keyLinesEnabled: AppSettings.instance.trendHorizontalLines,
      listHeight: Dimens.HOURLY_TREND_ITEM_HEIGHT,
      initialIndex: 0,
      cardBackground: AppColors.MAIN_CARD_BACKGROUND.resolve(this.isDark()),
      // container_main_*_trend_card.xml:21,31 â€” the title icon and title use
      // ?attr/colorSurfaceInverse (= md_theme_inverseSurface, styles.xml:29), not onSurface.
      onSurfaceInverse: AppColors.SURFACE_INVERSE.resolve(this.isDark()),
      bodyTextColor: AppColors.BODY_TEXT.resolve(this.isDark()),
      captionTextColor: AppColors.CAPTION_TEXT.resolve(this.isDark()),
      accentTextColor: AppColors.TITLE_TEXT.resolve(this.isDark()),
      keyLineColor: AppColors.OUTLINE.resolve(this.isDark()),
      keyLineTextColor: this.isDark() ? AppColors.TEXT_GREY_2ND : AppColors.TEXT_GREY,
      // The chips are Material buttons; their containers have to follow the card's theme, or a
      // dark card keeps pale lavender chips where Android's are dark grey.
      chipContainerColor: AppColors.SURFACE_VARIANT.resolve(this.isDark()),
      chipSelectedContainerColor: AppColors.PRIMARY.resolve(this.isDark()),
      chipLabelColor: AppColors.ON_SURFACE_VARIANT.resolve(this.isDark()),
      chipSelectedLabelColor: AppColors.ON_PRIMARY.resolve(this.isDark()),
      chartColors: this.chartColorsFor(location),
      doubleChartColors: this.doubleChartColorsFor(location),
      onItemClick: (tabIndex: number, itemIndex: number) => {
        const tab: TrendTab = this.hourlyTabs()[tabIndex];
        // An hourly column belongs to a day; the pager opens on the day that hour falls in.
        const hours = location.weather === null ? [] : location.weather.nextHourlyForecast;
        const day: number = itemIndex >= 0 && itemIndex < hours.length
          ? dayIndexForDate(location, hours[itemIndex].date)
          : 0;
        goDetails(location.formattedId, tab.detailScreen, day);
      }
    })
  }
}
