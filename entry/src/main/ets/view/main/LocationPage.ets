/*
 * One location's page — the Swiper child that was `MainScreen.locationPage`.
 *
 * WHY THIS IS A COMPONENT AND NOT A @Builder
 *
 * As a @Builder it belonged to MainScreen's render scope, and that is what made the whole screen
 * slow. `refresh()` replaces `location.weather`, and the guards below (`weather !== null`, the
 * daily/hourly lengths, the alert and nowcast tests) decide the page's STRUCTURE. A @Trace on the
 * model registers its dependency against MainScreen, so a new forecast re-rendered MainScreen, the
 * Swiper's ForEach re-diffed, the keys were unchanged, the children were kept — and the guards
 * never re-ran. The only way to get new weather on screen was to put a version counter in the
 * ForEach key and rebuild the entire page: a 4.6 s frame (traced: 60 custom-node destroys, 39
 * builds, 149 canvas passes, 38 image decodes), which is also the frame that paints the new
 * toolbar title, so selecting a location left the previous one on screen for seconds.
 *
 * Owning the reads here fixes that. `LocationModel` is @ObservedV2 with `weather` @Trace, so this
 * component re-renders itself when its own location's forecast arrives, and the ForEach key goes
 * back to being pure identity — the page is built once and never destroyed.
 *
 * The card content stays in MainScreen as @Builders and arrives through @BuilderParam. That is
 * deliberate: `detailBlocks`, `dailyCard` and `hourlyCard` are heavily tuned code that took several
 * sessions to get right, and moving them would risk regressions for no benefit. They re-execute
 * whenever this component re-renders, reading MainScreen's current state as they always did.
 */

import { LocationModel, Weather } from '../../model/Weather';
import { DragState } from './DragState';
import { Dimens } from '../../theme/Dimens';

@ComponentV2
export struct LocationPage {
  /**
   * The location this page draws. @ObservedV2 with `weather` @Trace — reading it below is what
   * makes this component re-render when its own forecast lands.
   */
  @Param location: LocationModel = new LocationModel();
  /** MainScreen's refresh flag; drives the pull-to-refresh spinner. */
  @Param loading: boolean = false;
  /**
   * The shared drag state, observed.
   *
   * Needed for the COMMIT, not the gesture. Mid-drag everything already worked — the card follows
   * the finger, because those translates are attributes on nodes the builder already created. What
   * did not work was the drop: `endDrag` bumps `orderVersion`, `orderedBlocks` re-keys on it and
   * returns the new order, and the grid's ForEach reorders — but only if something re-runs the
   * builder. `orderVersion` lives on MainScreen, so without this @Param nothing told LocationPage
   * to re-render and the cards sprang back to their original slots on release.
   */
  @Param drag: DragState = new DragState();
  /**
   * MainScreen's `dataVersion`, for exactly the reason `drag` is here.
   *
   * The detail blocks format their values through helpers in `common/Units.ets`, which read the
   * unit preferences off `AppSettings` — an @ObservedV2 this page never touches. So changing the
   * pressure unit re-rendered MainScreen (the header picked it up) and left the Pressure block
   * reading "1015 hPa": `blocksContent` is a @BuilderParam INVOKED IN THIS PAGE'S SCOPE, so a read
   * of MainScreen's @Local from inside it registers nothing here, and nothing re-ran the builder.
   *
   * Passing the version in as a @Param and naming it in the guard below is the same trick
   * `orderStamp` plays for a drag commit.
   */
  @Param unitsVersion: number = 0;

  @Event onRefreshPulled: () => void = () => {
  };
  /** The page's own Scroller — one per location, so `currentOffset()` reports the visible page. */
  @Event scrollerOf: () => Scroller = () => new Scroller();
  @Event onScrolled: () => void = () => {
  };
  @Event onWidthChanged: (width: number) => void = () => {
  };
  /** MainAdapter.kt:107-109 — the alert card only appears while an alert has not expired. */
  @Event hasAlerts: () => boolean = () => false;
  /** MainAdapter.kt:110-115 — the nowcast needs precipitation and at least three buckets. */
  @Event hasNowcast: () => boolean = () => false;
  /**
   * `for (c in cardDisplayList)` (MainAdapter.kt:110) — a card the Blocks manage screen has removed
   * is not built at all. The three big cards are IN that list, alongside the half-size blocks.
   */
  @Event cardEnabled: (id: string) => boolean = () => true;
  /** Bumped when `card_display` changes, so the three guards below re-evaluate. */
  @Param cardsVersion: number = 0;

  @BuilderParam headerContent: () => void;
  @BuilderParam alertContent: () => void;
  @BuilderParam nowcastContent: () => void;
  @BuilderParam dailyContent: () => void;
  @BuilderParam hourlyContent: () => void;
  @BuilderParam blocksContent: () => void;
  @BuilderParam footerContent: () => void;

  /*
   * @Computed, NOT a plain method — that distinction is the whole fix, and this codebase has been
   * caught by it three times.
   *
   * ArkUI V2 decides what to re-render from the observable state a render dependency reads. A
   * @Trace read inside an ordinary private method registers nothing, so guards written as
   * `this.hasDaily()` compile, look right and never re-evaluate: Berlin and Tokyo rendered as an
   * empty page — toolbar and footer only — because their pages were built before `loadCached`
   * filled `weather`, and nothing ever re-read it. A local `const` in build() is not an option
   * either; ArkUI requires build() to be a single root node with no statements before it.
   *
   * A @Computed getter is the supported way to derive from @Trace state: it re-evaluates when
   * `location.weather` is replaced and re-renders whatever read it. The `hasAlerts` / `hasNowcast`
   * events can then stay as callbacks — these getters are what trigger the re-render, and the
   * callbacks only decide the detail once it is already running.
   */
  @Computed
  get hasDaily(): boolean {
    const weather: Weather | null = this.location.weather;
    return weather !== null && weather.dailyForecast.length > 0;
  }

  @Computed
  get hasHourly(): boolean {
    const weather: Weather | null = this.location.weather;
    return weather !== null && weather.nextHourlyForecast.length > 0;
  }

  /** Reading orderVersion here is what re-renders this page when a drop commits. */
  @Computed
  get orderStamp(): number {
    return this.drag.orderVersion;
  }

  /** Re-read on every forecast so the alert and nowcast callbacks are asked again. */
  @Computed
  get weatherStamp(): number {
    const weather: Weather | null = this.location.weather;
    return weather === null ? 0 : weather.dailyForecast.length + weather.alertList.length + 1;
  }

  /**
   * True once the finger has dragged this page past the top, cleared when the pull it licenses is
   * delivered. See the `onStateChange` note below.
   */
  @Local private pulled: boolean = false;

  build() {
    // One-way binding: $$ is V1 two-way syntax. The spinner is driven entirely by MainScreen's
    // `loading`, which onRefreshing sets and the refresh promise clears.
    Refresh({ refreshing: this.loading }) {
      Scroll(this.scrollerOf()) {
        Column() {
          this.headerContent()

          if (this.weatherStamp > 0 && this.hasAlerts()) {
            this.alertContent()
          }

          // Each of the three is gated on the STORED card list as well as on its data, exactly as
          // MainAdapter.kt:110-121 gates them. `cardsVersion` is read for the subscription.
          if (this.weatherStamp > 0 && this.cardsVersion >= 0 && this.hasNowcast() &&
            this.cardEnabled('nowcast')) {
            this.nowcastContent()
          }

          if (this.hasDaily && this.cardsVersion >= 0 && this.cardEnabled('daily_forecast')) {
            this.dailyContent()
          }

          if (this.hasHourly && this.cardsVersion >= 0 && this.cardEnabled('hourly_forecast')) {
            this.hourlyContent()
          }

          // Both reads are subscriptions, not conditions: `orderStamp` re-runs the builder when a
          // drag commits, `unitsVersion` when a unit preference changes.
          if (this.orderStamp >= 0 && this.unitsVersion >= 0) {
            this.blocksContent()
          }

          // MainAdapter.kt:173 — the footer closes every location page.
          this.footerContent()
        }
        .width('100%')
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.onWidthChanged(Number(newValue.width));
        })
      }
      .width('100%')
      .height('100%')
      /*
       * FitTabletRecyclerView.kt:33-34 — the main list carries `normal_margin / 2` of horizontal
       * padding, i.e. 8 dp, on top of whatever each item asks for.
       *
       * It was missing here, so every card on screen 1 was 8 dp wider on each side than Android's
       * and every left-aligned thing in the header sat 8 dp further out. Measured on the
       * reference: the daily trend card spans x 52..1208 and the refresh-time row 52..1208, where
       * this port had 26..1234 for both. The padding goes on the Scroll rather than on its Column
       * so the Column still measures the INNER width — `onWidthChanged` feeds the block grid's
       * span count and square side, and a border-box width would have oversized every tile.
       */
      .padding({ left: Dimens.SMALL_MARGIN, right: Dimens.SMALL_MARGIN })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      // MaterialWeatherView.onScroll (kt:178-186): rate = min(1, scrollY / mFirstCardMarginTop).
      .onDidScroll(() => {
        this.onScrolled();
      })
    }
    /*
     * `onRefreshing` fires whenever the component ENTERS the refreshing state, gesture or not — and
     * `refreshing` is bound to MainScreen's `loading`, so a PROGRAMMATIC refresh re-entered through
     * this callback as though the user had pulled. That mattered because the pull path is the one
     * caller allowed to skip Android's "already valid" check, so every selection refetched a
     * forecast that was still good. A hilog probe caught it as a `byUser=y` call nobody made.
     *
     * A real pull passes through Drag / OverDrag on its way to Refresh; a programmatic one jumps
     * straight to Refresh. So the gesture states are what license the callback, and the licence is
     * spent as soon as it is used.
     */
    .onStateChange((state: RefreshStatus) => {
      if (state === RefreshStatus.Drag || state === RefreshStatus.OverDrag) {
        this.pulled = true;
      }
    })
    .onRefreshing(() => {
      if (!this.pulled) {
        return;
      }
      this.pulled = false;
      this.onRefreshPulled();
    })
    .width('100%')
    .height('100%')
  }
}
