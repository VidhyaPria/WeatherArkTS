/*
 * Screen 4 - the tile / trend detail screen.
 *
 * Source: ui/details/DetailsActivity.kt + ui/details/DetailsScreen.kt (:111-194 the scaffold,
 * :196-260 the day pager, :262-349 the FAB menu, :351-518 the per-tag dispatch).
 *
 * NOT DailyWeatherActivity - `IntentHelper` only exposes `startDailyWeatherActivity`, but the tiles
 * and trend columns of the shipped APK open `DetailsActivity`; the capture
 * (ref_screen4_details_pressure.png) is what settled it.
 *
 * Shape, measured off that capture at density 3.25:
 *   BWCenterAlignedTopAppBar   back arrow at 16 vp, title CENTRED, 64 vp tall
 *   PrimaryScrollableTabRow    one tab per day: short label / day of month (headlineMedium) /
 *                              "MMM"; the selected tab is primary-coloured with a 3 vp underline
 *                              71 vp wide, which is the 103 vp tab minus its 16 vp side padding
 *   header                     labelMedium label then displaySmall value with the unit a size down
 *   chart                      NOT in this increment - see MORNING.md
 *   About <tag>                titleLarge heading indented a further 16 vp, then a card of prose
 *   FAB                        bottom-right, the tag's icon, opening the other detail screens
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { LocationModel } from '../model/Weather';
import { AppSettings, isLightTheme } from '../data/SettingsStore';
import { AnimatedWeatherIcon } from '../view/common/AnimatedWeatherIcon';
import { SystemInsets } from '../common/SystemBars';
import {
  DetailScreen,
  detailScreenIcon,
  detailScreenName,
  toDetailScreenList
} from '../model/DetailScreen';
import { WindowMetrics } from '../common/SystemBars';
import {
  DetailsChartSpec,
  DetailsItemModel,
  DetailsRow,
  DetailsSection,
  DetailsPair,
  DetailsSummary,
  SummaryColumn,
  detailsChart,
  detailsItems,
  detailsSectionsFor,
  detailsSummary,
  DEW_POINT_HEADING,
  pollutantOptions,
  precipitationPairs,
  PRECIPITATION_PROBABILITY_HEADING
} from '../view/details/DetailsData';
import { PollutantDef } from '../model/Pollutant';
import { DetailsChartCanvas } from '../view/details/DetailsChartCanvas';
import { DetailsParams } from '../common/Navigator';
import { display } from '@kit.ArkUI';
import { getMainViewModel } from '../viewmodel/MainViewModel';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { APP_FONT_FAMILY, LineHeights } from '../common/Typography';
import { localDayOfMonth, localMonth } from '../common/LocalTime';
import { getWeek } from '../common/Formatter';
import { getWeatherIcon } from '../common/WeatherIcons';
import { MoonPhaseCanvas } from '../view/main/MoonPhaseCanvas';

/** dimens.xml small_weather_icon_size — `WeatherCondition`'s icon (DetailsConditions.kt:748). */
const CONDITION_ICON_SIZE: number = 42;

/**
 * The Sun & moon rows' leading images, by the asset name `DetailsRow.icon` carries.
 *
 * Android tints all three with `colorTextContent` (DetailsSunMoon.kt:344, 420, 481), so the
 * artwork's own colour never shows and the "_light" cut is as good as the "_dark" one — the port
 * recolours it to onSurface either way. NativeApp draws the same two files.
 */
/** A `DetailsItem`'s leading icon, by the drawable name the model carries. */
function detailsItemIcon(name: string): Resource {
  if (name === 'ic_mode_heat') {
    return $r('app.media.ic_mode_heat');
  }
  if (name === 'ic_sunshine_duration') {
    return $r('app.media.ic_sunshine_duration');
  }
  return $r('app.media.ic_mode_cool');
}

function listItemIcon(name: string): Resource {
  if (name === 'weather_clear_day_mini') {
    return $r('app.media.weather_clear_day_mini_light');
  }
  if (name === 'weather_clear_night_mini') {
    return $r('app.media.weather_clear_night_mini_light');
  }
  return $r('app.media.ic_twilight');
}

/** getFormattedDate("MMM") - the third line of a pager column. */
const SHORT_MONTHS: string[] =
  ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/*
 * PrimaryScrollableTabRow's geometry, measured off the capture: the "Yda" and "Today" columns are
 * 336 device px apart at density 3.25, and the indicator is 231 px wide - 103 vp and 71 vp, i.e.
 * the tab minus 16 vp of padding on each side. Material's own minimum for a scrollable tab is
 * 90 vp, so a narrower label (this port renders "Aug" where the reference renders a Persian
 * "Mordad 18") still lays out at 90 rather than collapsing.
 */
const TAB_WIDTH: number = 103;
const TAB_MIN_WIDTH: number = 90;
const TAB_SIDE_PADDING: number = 16;
const TAB_EDGE_PADDING: number = 52;
const INDICATOR_HEIGHT: number = 3;
/** bottomDetailsInset (DetailsCommon.kt:451-456) - 16 - 3 plus the FAB's 56. */
const BOTTOM_INSET: number = Dimens.NORMAL_MARGIN * 3 + 56;
const FAB_SIZE: number = 56;

/**
 * How many pollutant buttons stay inline before the rest move into the ⋮ menu.
 *
 * MEASURED on the reference, which fits AQI, PM2.5, PM10 and O3 before its "More" button:
 * `[52,1623][339,1779]`, `[346..570]`, `[577..792]`, `[799..961]`, `[968..1150]`. The port kept
 * three and pushed O3 into the menu.
 */
const INLINE_POLLUTANT_COUNT: number = 4;

/**
 * The switcher's button height, MEASURED: the reference's chips are 156 px, i.e. 48 vp, where this
 * port drew 40. `ToggleButton` inside a `ButtonGroup` (DetailsAirQuality.kt:548-587).
 */
const POLLUTANT_CHIP_HEIGHT: number = 48;
/** The overflow panel's measured width, the same one the trend tabs' menu uses. */
const POLLUTANT_MENU_WIDTH: number = 160;
/** LinearProgressIndicator height in AirQualityDetails (DetailsAirQuality.kt:824). */
const POLLUTANT_BAR_HEIGHT: number = 10;
/**
 * `MaterialTheme.typography.headlineSmall` — the size of the one in-list heading on screen 4, the
 * "Precipitation probability" line that separates the two chart groups (DetailsPrecipitation.kt:186).
 */
const HEADLINE_SMALL_TEXT_SIZE: number = 24;

/**
 * The tags whose chart this port draws.
 *
 * For any other tag the "not enough hourly data" row is suppressed: the Kotlin draws a chart there,
 * so showing its unavailable-chart string would blame the DATA for something that is a gap in the
 * port. Pollen and Sun & moon are absent from BOTH lists because the Kotlin gives them a pollen
 * grid and an EphemerisChart, not a line chart at all.
 */
const CHART_PORTED: DetailScreen[] = [
  DetailScreen.TAG_CONDITIONS,
  DetailScreen.TAG_FEELS_LIKE,
  DetailScreen.TAG_PRESSURE,
  DetailScreen.TAG_HUMIDITY,
  DetailScreen.TAG_CLOUD_COVER,
  DetailScreen.TAG_VISIBILITY,
  DetailScreen.TAG_UV_INDEX,
  DetailScreen.TAG_WIND,
  DetailScreen.TAG_AIR_QUALITY,
  DetailScreen.TAG_PRECIPITATION,
  // Sun & moon's chart is the EphemerisChart, and it is now drawn — but the Kotlin gates it on the
  // day having a valid sun or moon rather than on an hourly count, and shows nothing when it does
  // not (DetailsSunMoon.kt:96-100). So it is deliberately NOT in this list, whose only job is to
  // decide who gets the "not enough hourly data" row.
];

@Entry
@ComponentV2
struct Details {
  @Local private location: LocationModel | null = null;
  @Local private screen: DetailScreen = DetailScreen.TAG_CONDITIONS;
  @Local private dayIndex: number = 0;
  @Local private menuOpen: boolean = false;
  @Local private isDark: boolean = false;
  /** The hour the chart marker is on, or -1. Feeds the header's activeItem branch. */
  @Local private activeHourMs: number = -1;
  /**
   * The SECOND chart's marker.
   *
   * Precipitation is the one screen with two charts, and the Kotlin gives each its own
   * `activeQuantityItem` / `activeProbabilityItem` (DetailsPrecipitation.kt:103-151), so touching
   * one leaves the other's header on its day summary.
   */
  @Local private activeHourMs2: number = -1;
  /** The degree day's PlainTooltip (DetailsConditions.kt:291-299), open until it is dismissed. */
  @Local private tooltipOpen: boolean = false;
  @Local private tooltipText: string = '';
  /** The air-quality screen's picked pollutant, "" for the index itself (`selectedPollutant`). */
  @Local private pollutantId: string = '';
  @Local private pollutantOverflowShown: boolean = false;
  private now: Date = new Date();
  private tabScroller: Scroller = new Scroller();
  private insets: SystemInsets = SystemInsets.instance;
  /** BreezyLineChart sizes itself from the window (kt:244), so the page has to measure it once. */
  private windowHeightVp: number = 800;

  aboutToAppear(): void {
    const params = router.getParams() as DetailsParams;
    if (params !== null && params !== undefined) {
      this.screen = params.screen as DetailScreen;
      this.dayIndex = params.dayIndex;
      const model = getMainViewModel();
      for (const candidate of model.getLocations()) {
        if (candidate.formattedId === params.locationId) {
          this.location = candidate;
          break;
        }
      }
    }
    try {
      /*
       * The chart is `windowHeightInDp / 4` (BreezyLineChart.kt:244), and `windowHeightInDp` is
       * `resources.displayMetrics.heightPixels` — the ACTIVITY WINDOW, which on the reference is
       * the display less the status bar: its DetailsActivity frame is [0,130][1260,2720].
       *
       * Measured: Android's chart is 648 px and this port's was 680, because it divided the whole
       * 2720 px display. (2720 - 123) / 3.25 / 4 = 199.8 vp = 649 px, one pixel off Android's.
       */
      // `insets.top` is already vp — SystemBars.ets:89 converts it on the way in.
      this.windowHeightVp = px2vp(display.getDefaultDisplaySync().height) - this.insets.top;
    } catch (error) {
      // Keeps the default rather than failing the page; the chart's own floor is 100 vp anyway.
      console.error(`Details: could not read the display height: ${(error as Error).message}`);
    }
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
  }

  /*
   * DetailsScreen.kt:121 — `ThemeManager.isLightTheme(context, detailsUiState.location)`, then
   * `BreezyWeatherTheme(!isLightTheme)` on :129. This page follows the LOCATION's day/night, not the
   * system, which is why a night location paints the whole details window near-black on Android.
   *
   * It used to call appIsDark() — the settings-screen rule (SettingsActivity takes
   * BreezyWeatherTheme's default). That is right for Settings and wrong here: with the default
   * "follow system" on a light phone it pinned the page light, so a night location got a white
   * details page while the main screen behind it was correctly dark.
   */
  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    // Null while the location has not resolved — `daylight == true` is false then, and the Kotlin
    // paints dark in exactly that case (DetailsUiState.kt:24 starts `location` null).
    this.isDark = !isLightTheme(this.location === null ? null : this.location.daylight);
  }

  /** The day list, or an empty one while the location has no forecast. */
  private days(): Date[] {
    const weather = this.location?.weather;
    if (weather === null || weather === undefined) {
      return [];
    }
    const out: Date[] = [];
    for (const daily of weather.dailyForecast) {
      out.push(daily.date);
    }
    return out;
  }

  private todayIndex(): number {
    const weather = this.location?.weather;
    const index = weather?.todayIndex;
    return index === null || index === undefined ? -1 : index;
  }

  /**
   * The first line of a pager column - DetailsScreen.kt:237-245.
   * "Yda" / "Today" / "Tmw" around today, the short weekday everywhere else.
   */
  private shortLabel(index: number, date: Date): string {
    const today: number = this.todayIndex();
    if (today < 0) {
      return getWeek(date, this.utcOffset());
    }
    if (index === today - 1) {
      return 'Yda'; // strings.xml:38
    }
    if (index === today) {
      return 'Today'; // strings.xml:39
    }
    if (index === today + 1) {
      return 'Tmw'; // strings.xml:40
    }
    return getWeek(date, this.utcOffset());
  }

  private utcOffset(): number {
    return this.location === null ? 0 : this.location.utcOffsetSeconds;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.topBar()
        this.dayPager()
        this.detailsBody()
      }
      .width('100%')
      .height('100%')

      if (this.menuOpen) {
        this.menuScrim()
      }
      this.fabMenu()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.isDark))
    .padding({
      top: this.insets.top,
      bottom: this.insets.bottom,
      left: this.insets.left,
      right: this.insets.right
    })
  }

  /** BWCenterAlignedTopAppBar - back arrow, centred title, no actions. */
  @Builder
  private topBar() {
    Stack({ alignContent: Alignment.Center }) {
      Text(detailScreenName(this.screen))
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(22)
        .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
        .maxLines(1)

      Row() {
        Image($r('app.media.ic_back'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.isDark))
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding({ left: Dimens.NORMAL_MARGIN })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height(Dimens.ACTION_BAR_HEIGHT)
  }

  /** DailyPagerIndicator (kt:196-260). */
  @Builder
  private dayPager() {
    Column() {
      Scroll(this.tabScroller) {
        Row() {
          ForEach(this.days(), (date: Date, index: number) => {
            this.dayTab(date, index);
          }, (date: Date, index: number) => index.toString() + ':' + date.getTime().toString())
        }
        .padding({ left: TAB_EDGE_PADDING, right: TAB_EDGE_PADDING })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // PrimaryScrollableTabRow draws a divider under the whole row.
      Divider()
        .color(AppColors.OUTLINE.resolve(this.isDark))
        .strokeWidth(1)
    }
    .width('100%')
  }

  @Builder
  private dayTab(date: Date, index: number) {
    Column() {
      Column({ space: 0 }) {
        Text(this.shortLabel(index, date))
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontColor(index === this.dayIndex
            ? AppColors.PRIMARY.resolve(this.isDark)
            : AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
          .maxLines(1)

        Text(localDayOfMonth(date, this.utcOffset()).toString().padStart(2, '0'))
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(28)
          .fontColor(index === this.dayIndex
            ? AppColors.PRIMARY.resolve(this.isDark)
            : AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
          .maxLines(1)

        Text(SHORT_MONTHS[localMonth(date, this.utcOffset())])
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontColor(index === this.dayIndex
            ? AppColors.PRIMARY.resolve(this.isDark)
            : AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
          .maxLines(1)
      }
      .padding({
        top: Dimens.SMALL_MARGIN,
        bottom: Dimens.SMALL_MARGIN,
        left: TAB_SIDE_PADDING,
        right: TAB_SIDE_PADDING
      })
      .alignItems(HorizontalAlign.Center)

      // PrimaryTabIndicator: it spans the tab's CONTENT, not the whole tab.
      Row()
        .width(TAB_WIDTH - TAB_SIDE_PADDING * 2)
        .height(INDICATOR_HEIGHT)
        .borderRadius(INDICATOR_HEIGHT / 2)
        .backgroundColor(index === this.dayIndex
          ? AppColors.PRIMARY.resolve(this.isDark)
          : Color.Transparent)
    }
    .constraintSize({ minWidth: TAB_MIN_WIDTH })
    .width(TAB_WIDTH)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.dayIndex = index;
      // A marker left from the previous day would put the header on an hour that is no longer
      // plotted — `Open()` in the NDK resets it for the same reason.
      this.activeHourMs = -1;
      this.activeHourMs2 = -1;
    })
  }

  /** The LazyColumn of DetailsPressure and its siblings, with the same content padding. */
  @Builder
  private detailsBody() {
    Scroll() {
      Column() {
        this.summaryHeader()

        /*
         * The gap belongs to the HEADER, not to the chart. `DetailsSunMoon` (kt:96-100) emits its
         * EphemerisChart as the list's first item with nothing above it, so a port that always
         * spaced before the chart pushed that page 16 dp down: the reference's chart top is 676
         * and this port's was 703.
         */
        if (this.summary().columns.length > 0) {
          Blank().height(Dimens.NORMAL_MARGIN)
        }

        this.chart()

        /*
         * AirQualitySwitcher (DetailsAirQuality.kt:542-654) — a ButtonGroup of AQI plus every
         * pollutant the reading carries, drawn under the chart because the chart's own axis is
         * what the selection changes.
         */
        if (this.screen === DetailScreen.TAG_AIR_QUALITY && this.pollutantChoices().length > 0) {
          Blank().height(Dimens.NORMAL_MARGIN)
          this.pollutantSwitcher()
        }

      // TemperatureSwitcher (DetailsConditions.kt:451-490) is only on the Conditions screen, and
      // it is how the two tags relate: onRealTempSwitch calls setSelectedChart (kt:409).
      if (this.screen === DetailScreen.TAG_CONDITIONS || this.screen === DetailScreen.TAG_FEELS_LIKE) {
        Row({ space: 2 }) {
          ForEach([DetailScreen.TAG_CONDITIONS, DetailScreen.TAG_FEELS_LIKE], (tag: DetailScreen) => {
            Row({ space: Dimens.SMALL_MARGIN }) {
              if (this.screen === tag) {
                Image($r('app.media.ic_check'))
                  .width(18)
                  .height(18)
                  .fillColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark))
              }
              Text(tag === DetailScreen.TAG_CONDITIONS ? 'Actual' : 'Feels like') // :52 / :54
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.TITLE_TEXT_SIZE)
                .fontColor(this.screen === tag
                  ? AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark)
                  : AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
                .maxLines(1)
            }
            .layoutWeight(1)
            .height(40)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.screen === tag
              ? AppColors.PRIMARY_CONTAINER.resolve(this.isDark)
              : AppColors.SURFACE_VARIANT.resolve(this.isDark))
            .borderRadius(20)
            .onClick(() => {
              this.screen = tag;
              this.activeHourMs = -1;
              this.activeHourMs2 = -1;
            })
          }, (tag: DetailScreen) => tag)
        }
        .width('100%')
        .margin({ top: Dimens.SMALL_MARGIN })
      }

        // The switcher sits BELOW the chart, not in the header (DetailsConditions.kt:236-246),
        // followed by the one-line explanation of which temperature is plotted (kt:239-251).
        if (this.screen === DetailScreen.TAG_CONDITIONS || this.screen === DetailScreen.TAG_FEELS_LIKE) {
          Text(this.screen === DetailScreen.TAG_CONDITIONS
            ? 'The actual temperature.'                                    // strings.xml:53
            : 'What the temperature feels like, as a result of humidity, wind and/or sunlight.')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            .width('100%')
            .margin({ top: Dimens.SMALL_MARGIN })
        }

        /*
         * The bare DetailsItem rows, between the chart's explanation and the sections — where
         * DetailsConditions.kt:284-360 puts the degree day. Preceded by a small_margin spacer
         * (kt:286-288) and drawn only when there is one, so most days show nothing.
         */
        ForEach(this.items(), (item: DetailsItemModel, index: number) => {
          Blank().height(item.spacerAbove)
          this.detailsItem(item)
        }, (item: DetailsItemModel, index: number) =>
          index.toString() + ':' + item.headline + ':' + item.supporting)

        /*
         * Precipitation's second half — the one screen the Kotlin builds as two chart groups
         * (DetailsPrecipitation.kt:166-221): the quantity breakdown, a divider, then the whole
         * "Precipitation probability" group with its own header, chart and breakdown.
         */
        if (this.screen === DetailScreen.TAG_PRECIPITATION) {
          this.halfDayPairs(this.pairs(0))
        }

        /*
         * The probability group closes TWO screens, not one.
         *
         * DetailsPrecipitation.kt:166-221 puts it under the quantity breakdown, and
         * DetailsConditions.kt:360-405 puts the identical group — divider, headlineSmall heading,
         * the Daytime/Nighttime summary, the chart and the breakdown — at the end of the
         * CONDITIONS page. It used to be gated on the precipitation tag alone, so the screen every
         * hourly and daily trend column opens simply ended after the description line.
         */
        if (this.screen === DetailScreen.TAG_PRECIPITATION ||
          this.screen === DetailScreen.TAG_CONDITIONS ||
          this.screen === DetailScreen.TAG_FEELS_LIKE) {
          if (this.hasProbability()) {
            this.secondGroup(PRECIPITATION_PROBABILITY_HEADING, Dimens.SMALL_MARGIN)
            this.halfDayPairs(this.pairs(1))
          }
        }

        Blank().height(Dimens.NORMAL_MARGIN)

        ForEach(this.sections(), (section: DetailsSection, index: number) => {
          this.section(section, this.screen === DetailScreen.TAG_HUMIDITY && index === 0
            && this.hasSecondChart());
          /*
           * Humidity is the one screen whose second group sits BETWEEN its two About cards, not
           * after them: `DetailsHumidity.kt:176-216` draws the humidity card, a divider, the
           * "Dew point" heading, its header and its chart, and only then "About dew point".
           * Measured on the reference: card bottom 2182, heading top 2289 — 107 px, which is the
           * divider's own 16 + 1 + 16 dp and NOT a section gap on top of it, so the card before it
           * gives up its bottom margin.
           */
          if (this.screen === DetailScreen.TAG_HUMIDITY && index === 0 && this.hasSecondChart()) {
            this.secondGroup(DEW_POINT_HEADING, Dimens.NORMAL_MARGIN)
          }
          // Same trap as the summary header above: a day change keeps every heading and swaps only
          // the body, so a heading-only key rebuilt nothing. sectionKey digests the content.
        }, (section: DetailsSection, index: number) => index.toString() + ':' + sectionKey(section))

        Blank().height(BOTTOM_INSET)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: Dimens.NORMAL_MARGIN,
        right: Dimens.NORMAL_MARGIN,
        top: Dimens.SMALL_MARGIN,
        bottom: Dimens.SMALL_MARGIN
      })
    }
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * The summary block: one column for the scalar tags, two side by side for the four that
   * summarise a half-day each (WindSummary, PrecipitationSummary, WeatherConditionSummary).
   */
  /**
   * `WeatherCondition` (DetailsConditions.kt:718-766) — the half-day's `small_weather_icon_size`
   * icon, a `small_margin` gap and the condition text in BOLD onSurface.
   *
   * Extracted because it appears in TWO positions: below the temperature in portrait and beside it
   * in landscape (kt:625-633). Only Conditions and Feels like have one; every other tag's
   * description is the plain onSurfaceVariant line.
   */
  @Builder
  private weatherCondition(col: SummaryColumn) {
    Row({ space: Dimens.SMALL_MARGIN }) {
      /*
       * kt:732-756 — an ANIMATED icon when the element-animations setting is on, a static one when
       * it is off. The Kotlin branches on exactly that, and tapping the animated one calls
       * `startAnimators()` to replay it (kt:744-746).
       *
       * The port used to draw the static Image unconditionally, so this screen never animated
       * however the setting was set.
       *
       * The null test is repeated here rather than relied on from the caller: pulling this out of
       * the Column lost the enclosing `if (col.iconKind !== null)` that used to narrow the type.
       */
      if (col.iconKind !== null && AppSettings.instance.elementAnimations) {
        AnimatedWeatherIcon({
          kind: col.iconKind,
          daytime: col.iconDaylight,
          iconSize: CONDITION_ICON_SIZE,
          animated: true
        })
      } else if (col.iconKind !== null) {
        Image(getWeatherIcon(col.iconKind, col.iconDaylight))
          .width(CONDITION_ICON_SIZE)
          .height(CONDITION_ICON_SIZE)
      }
      Text(col.description)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .layoutWeight(WindowMetrics.instance.width > WindowMetrics.instance.height ? 1 : 0)
    .width(WindowMetrics.instance.width > WindowMetrics.instance.height ? undefined : '100%')
    .alignItems(VerticalAlign.Center)
    // The `small_margin` above it exists only in the stacked (portrait) arrangement — kt:631.
    .margin({ top: WindowMetrics.instance.width > WindowMetrics.instance.height ? 0 : Dimens.SMALL_MARGIN })
  }

  @Builder
  private summaryHeader() {
    /*
     * `context.isLandscape` (DetailsConditions.kt:625, :630) is read INLINE below rather than into
     * a local. Two constraints meet: a @Builder body may contain only UI syntax, so there is
     * nowhere to put a `const`; and `WindowMetrics` has to be read DIRECTLY in the build or a
     * rotation does not re-lay-out, which is the observation note in common/TwoPane.ets.
     * `isLandscape()` exists for callers that are not themselves a build.
     */
    Column() {
      Row({ space: Dimens.SMALL_MARGIN }) {
        ForEach(this.summary().columns, (col: SummaryColumn, index: number) => {
          Row({ space: Dimens.SMALL_MARGIN }) {
            if (col.dotColor.length > 0) {
              Image($r('app.media.ic_circle'))
                .width(Dimens.MATERIAL_ICON_SIZE)
                .height(Dimens.MATERIAL_ICON_SIZE)
                .fillColor(col.dotColor)
            }
            Column() {
              /*
               * Every line here is a `TextFixedHeight` in the Kotlin (DetailsCommon.kt:346-393):
               * its height is `style.lineHeight * maxLines` with the glyphs centred in it, NOT the
               * font's own line box. So the label is 16 vp tall whatever the typeface does, the
               * value 44, and the third line 16 (labelMedium) or 20 (labelLarge).
               *
               * Measured against the reference: Android 52 / 143 px, this port 46 / 137 before
               * the line heights went in.
               */
              Text(col.label)
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
                .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                .lineHeight(LineHeights.LABEL_MEDIUM)
                .maxLines(1)

              // displaySmall with the unit at headlineSmall (UnitUtils.formatUnitsDifferentFontSize).
              Text() {
                Span(col.value)
                  .fontSize(36)
                  .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                if (col.unit.length > 0) {
                  Span(col.unit)
                    .fontSize(24)
                    .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                }
                if (col.valueSuffix.length > 0) {
                  // Wind's arrow: appended AFTER the unit, back at displaySmall (kt:283-286).
                  Span(col.valueSuffix)
                    .fontSize(36)
                    .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                }
                if (col.valueLevel.length > 0) {
                  /*
                   * Air quality's and UV's LEVEL NAME, inside the same displaySmall line at
                   * headlineSmall in onSurfaceVariant (DetailsAirQuality.kt:421-430). The
                   * reference's node reads "27 Fair" and is 143 px; both ports had "Fair" on a
                   * third line, making those two headers 52 px too tall.
                   */
                  Span(' ' + col.valueLevel)
                    .fontSize(24)
                    .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
                }
              }
              .fontFamily(APP_FONT_FAMILY)
              .lineHeight(LineHeights.DISPLAY_SMALL)
              .maxLines(1)

              /*
               * kt:630-633 — in PORTRAIT the condition sits a `small_margin` BELOW the temperature.
               * In landscape it moves out of this Column entirely and becomes a sibling of it, a
               * `large_margin` to the right (kt:625-628); see the branch after this Column.
               */
              if (col.iconKind !== null && WindowMetrics.instance.width <= WindowMetrics.instance.height) {
                this.weatherCondition(col)
              } else if (col.iconKind === null && col.descriptionLine > 0) {
                /*
                 * Drawn even when EMPTY. Every `<Tag>Item` stacks `TextFixedHeight`s and the wind
                 * one has an explicit empty else-branch (kt:318-324) so a half-day with no gusts
                 * still lines up with one that has them. `descriptionLine` is labelMedium's 16 or
                 * labelLarge's 20, per tag.
                 */
                Text(col.description)
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(col.descriptionLine === LineHeights.LABEL_LARGE
                    ? Dimens.CONTENT_TEXT_SIZE : Dimens.SUBTITLE_TEXT_SIZE)
                  .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
                  .lineHeight(col.descriptionLine)
                  .maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.Start)
            // In landscape the Column no longer owns the whole row, so it takes what it needs and
            // leaves the rest to the condition beside it.
            .layoutWeight(col.iconKind !== null && WindowMetrics.instance.width > WindowMetrics.instance.height ? 1 : 0)

            // kt:625-628 — beside the temperature, a `large_margin` away, landscape only.
            if (col.iconKind !== null && WindowMetrics.instance.width > WindowMetrics.instance.height) {
              Blank().width(Dimens.LARGE_MARGIN - Dimens.SMALL_MARGIN)
              this.weatherCondition(col)
            }
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
          /*
           * The key has to carry the column's CONTENT, not just its label. Conditions and Feels
           * like both produce "Daytime" and "Nighttime", so a label-only key left the header
           * showing the actual temperature and its weather text after the switcher had moved to
           * Feels like — ForEach saw the same two keys and rebuilt neither.
           */
        }, (col: SummaryColumn, index: number) => index.toString() + ':' + col.label + ':'
          + col.value + ':' + col.unit + ':' + col.description + ':' + col.dotColor + ':'
          + (col.iconKind === null ? '-' : col.iconKind.toString()))
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
  }

  /**
   * The chart, or the "not enough data" row the Kotlin shows in its place.
   *
   * `UnavailableChart` (DetailsCommon.kt:137-169) is a centred icon and a bodySmall line across
   * half the width, and it is what a tag with fewer than CHART_MIN_COUNT points gets - including
   * every tag whose chart is not in this increment.
   */
  @Builder
  private chart() {
    if (this.chartSpec() === null && !CHART_PORTED.includes(this.screen)) {
      // Nothing. The Kotlin draws a chart here for these tags, so claiming "not enough hourly
      // data" would be a lie about the DATA when what is missing is the port. See MORNING.md.
      Blank().height(0)
    } else if (this.chartSpec() !== null) {
      DetailsChartCanvas({
        spec: this.chartSpec() as DetailsChartSpec,
        utcOffsetSeconds: this.utcOffset(),
        isDark: this.isDark,
        keyLinesEnabled: AppSettings.instance.trendHorizontalLines,
        windowHeightVp: this.windowHeightVp,
        revision: this.screen + ':' + this.dayIndex.toString() + ':' + (this.isDark ? 'd' : 'l')
          + ':' + this.pollutantId,
        activeHourMs: this.activeHourMs,
        onActiveHourChange: (at: number) => { this.activeHourMs = at; }
      })
    } else {
      Row({ space: Dimens.SMALL_MARGIN }) {
        Image($r('app.media.ic_info'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.isDark))
        Text(this.hasAnyHours() ? 'Not enough hourly data available to display a chart for this day.'
          : 'No hourly data available.') // strings.xml:44-45
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
      }
      .width('50%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: Dimens.SMALL_MARGIN })
    }
  }

  private chartSpec(): DetailsChartSpec | null {
    return this.location === null ? null
      : detailsChart(this.location, this.screen, this.dayIndex, this.pollutantId);
  }

  /** The rain/snow (0) or per-type probability (1) breakdown under each chart. */
  private pairs(variant: number): DetailsPair[] {
    return this.location === null ? []
      : precipitationPairs(this.location, this.dayIndex, variant);
  }

  /** The probability chart's spec — precipitation's second one (kt:588-629). */
  private chartSpec2(): DetailsChartSpec | null {
    return this.location === null ? null
      : detailsChart(this.location, this.screen, this.dayIndex, this.pollutantId, 1);
  }

  /**
   * The probability group's gate (kt:178-181): either half-day carries a probability, or any hour
   * of the day does. With Open-Meteo that is normally true, and it is false for a day whose hours
   * have fallen out of the forecast window.
   */
  private hasProbability(): boolean {
    const weather = this.location?.weather;
    if (weather === null || weather === undefined
      || this.dayIndex < 0 || this.dayIndex >= weather.dailyForecast.length) {
      return false;
    }
    const daily = weather.dailyForecast[this.dayIndex];
    if (daily.day !== null && daily.day.precipitationProbability !== null) {
      return true;
    }
    if (daily.night !== null && daily.night.precipitationProbability !== null) {
      return true;
    }
    const spec: DetailsChartSpec | null = this.chartSpec2();
    return spec !== null && spec.points.length > 0;
  }

  /**
   * A screen's SECOND chart group: a divider, a headlineSmall heading, its own header, and its own
   * chart.
   *
   * Three tags have one. Precipitation and Conditions close with the probability group
   * (DetailsPrecipitation.kt:166-221 / DetailsConditions.kt:360-405); Humidity has the DEW POINT
   * group (DetailsHumidity.kt:176-216), which is the same five elements in the same order and was
   * missing from both ports entirely.
   *
   * The heading is a bare `Text` at x = the page inset, NOT a `DetailsSectionHeader` — it takes no
   * extra normal_margin from the start, which is why the reference draws it at x=52 where "About
   * relative humidity" is at 104.
   */
  @Builder
  private secondGroup(heading: string, headingGap: number) {
    // DetailsSectionDivider — a rule with a normal_margin above and below (kt:310-317).
    Divider()
      .color(AppColors.OUTLINE.resolve(this.isDark))
      .strokeWidth(1)
      .margin({ top: Dimens.NORMAL_MARGIN, bottom: Dimens.NORMAL_MARGIN })

    Text(heading)
      .fontFamily(APP_FONT_FAMILY)
      .fontSize(HEADLINE_SMALL_TEXT_SIZE)
      .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
      // headlineSmall is 24 sp on a 32 sp line: Android 104 px, this port 91 without it.
      .lineHeight(LineHeights.HEADLINE_SMALL)
      /*
       * The gap under the heading is NOT the same on the two groups, and the reference shows it:
       * the probability heading is followed by 26 px (`Spacer(small_margin)`,
       * DetailsPrecipitation.kt:190-192) and the dew-point one by 52
       * (`Spacer(normal_margin)`, DetailsHumidity.kt:185-187). Measured on the reference:
       * probability heading bottom 2428 -> "Daytime" 2454; dew point 2393 -> "Today" 2445.
       */
      .margin({ bottom: headingGap })

    this.summaryHeader2()

    Blank().height(Dimens.NORMAL_MARGIN)

    this.chart2()
  }

  /** Whether the second chart has enough points to draw — the gate on Humidity's dew-point group. */
  private hasSecondChart(): boolean {
    return this.chartSpec2() !== null;
  }

  /** PrecipitationProbabilityHeader — the same two columns, on the second marker (kt:506-524). */
  @Builder
  private summaryHeader2() {
    Row({ space: Dimens.SMALL_MARGIN }) {
      ForEach(this.summary2().columns, (col: SummaryColumn, index: number) => {
        Column() {
          Text(col.label)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            .lineHeight(LineHeights.LABEL_MEDIUM)
            .maxLines(1)
          Text(col.value)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(36)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            .lineHeight(LineHeights.DISPLAY_SMALL)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }, (col: SummaryColumn, index: number) =>
        index.toString() + ':' + col.label + ':' + col.value)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  private summary2(): DetailsSummary {
    return this.location === null
      ? new DetailsSummary()
      : detailsSummary(this.location, this.screen, this.dayIndex, this.now, this.activeHourMs2,
        this.pollutantId, 1);
  }

  /** The second chart, with its own marker. */
  @Builder
  private chart2() {
    if (this.chartSpec2() !== null) {
      DetailsChartCanvas({
        spec: this.chartSpec2() as DetailsChartSpec,
        utcOffsetSeconds: this.utcOffset(),
        isDark: this.isDark,
        keyLinesEnabled: AppSettings.instance.trendHorizontalLines,
        windowHeightVp: this.windowHeightVp,
        revision: 'p2:' + this.dayIndex.toString() + ':' + (this.isDark ? 'd' : 'l'),
        activeHourMs: this.activeHourMs2,
        onActiveHourChange: (at: number) => { this.activeHourMs2 = at; }
      })
    } else {
      Row({ space: Dimens.SMALL_MARGIN }) {
        Image($r('app.media.ic_info'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.isDark))
        Text(this.hasAnyHours() ? 'Not enough hourly data available to display a chart for this day.'
          : 'No hourly data available.')
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
      }
      .width('50%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: Dimens.SMALL_MARGIN })
    }
  }

  /**
   * `PrecipitationDetails` and its two siblings (kt:418-475): a Daytime column and a Nighttime
   * column of `DetailsItem`s built from the same list of labels, each row a bold headline over its
   * value, and the whole block absent when the list is empty.
   */
  @Builder
  private halfDayPairs(pairs: DetailsPair[]) {
    if (pairs.length > 0) {
      Row({ space: Dimens.SMALL_MARGIN }) {
        Column() {
          Text('Daytime') // strings.xml daytime
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            // `DaytimeLabel` is a TextFixedHeight at labelMedium — 16 dp, not the font's own box.
            .lineHeight(LineHeights.LABEL_MEDIUM)
            .maxLines(1)
          ForEach(pairs, (pair: DetailsPair, index: number) => {
            this.pairItem(pair.label, pair.dayValue)
          }, (pair: DetailsPair, index: number) => 'd' + index.toString() + ':' + pair.dayValue)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text('Nighttime')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            // `DaytimeLabel` is a TextFixedHeight at labelMedium — 16 dp, not the font's own box.
            .lineHeight(LineHeights.LABEL_MEDIUM)
            .maxLines(1)
          ForEach(pairs, (pair: DetailsPair, index: number) => {
            this.pairItem(pair.label, pair.nightValue)
          }, (pair: DetailsPair, index: number) => 'n' + index.toString() + ':' + pair.nightValue)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: Dimens.NORMAL_MARGIN })
      .alignItems(VerticalAlign.Top)
    }
  }

  /**
   * One row of a half-day breakdown — a `DetailsItem` with no icon (`DailyPrecipitationDetail`,
   * DetailsPrecipitation.kt:477-503), so it carries the SAME metric as the degree-day and
   * sunshine rows: a bodyLarge headline on its 24 sp line (78 px) over a BARE 16 sp supporting
   * line at the font's own leading (61), 139 in total. Measured on the reference:
   * `[52,1727][237,1866]`, against this port's 61 + 53.
   */
  @Builder
  private pairItem(label: string, value: string) {
    Column() {
      Text(label)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
        .lineHeight(LineHeights.BODY_LARGE)
        .maxLines(1)
      Text(value)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
        .maxLines(1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Dimens.NORMAL_MARGIN })
  }

  /** Which of the two "no chart" strings applies - kt:160-164 keys it on the point count. */
  private hasAnyHours(): boolean {
    const weather = this.location?.weather;
    return weather !== null && weather !== undefined && weather.hourlyForecast.length > 0;
  }

  private summary(): DetailsSummary {
    return this.location === null
      ? new DetailsSummary()
      : detailsSummary(this.location, this.screen, this.dayIndex, this.now, this.activeHourMs,
        this.pollutantId);
  }

  /** The picker's entries: "AQI" plus every pollutant the day's reading carries. */
  private pollutantChoices(): PollutantDef[] {
    return this.location === null ? [] : pollutantOptions(this.location, this.dayIndex);
  }

  private pollutantLabel(index: number): string {
    // strings.xml:170 — the first entry is the index itself, `air_quality_index_short`.
    return index === 0 ? 'AQI' : this.pollutantChoices()[index - 1].shortName;
  }

  private pollutantIdAt(index: number): string {
    return index === 0 ? '' : this.pollutantChoices()[index - 1].id;
  }

  private selectedPollutantIndex(): number {
    const choices: PollutantDef[] = this.pollutantChoices();
    for (let i = 0; i < choices.length; i++) {
      if (choices[i].id === this.pollutantId) {
        return i + 1;
      }
    }
    return 0;
  }

  @Builder
  private pollutantOverflowMenu() {
    Menu() {
      ForEach(this.overflowIndices(), (index: number) => {
        MenuItem(index === this.selectedPollutantIndex()
          ? { content: this.pollutantLabel(index), endIcon: $r('app.media.ic_check') } as MenuItemOptions
          : { content: this.pollutantLabel(index) } as MenuItemOptions)
          .onClick(() => {
            this.pollutantOverflowShown = false;
            this.selectPollutant(this.pollutantIdAt(index));
          })
      }, (index: number) => index.toString())
    }
    .width(POLLUTANT_MENU_WIDTH)
  }

  /** Everything past the inline three, which is what the ⋮ menu holds. */
  private overflowIndices(): number[] {
    const out: number[] = [];
    for (let i = INLINE_POLLUTANT_COUNT; i <= this.pollutantChoices().length; i++) {
      out.push(i);
    }
    return out;
  }

  private inlineIndices(): number[] {
    const out: number[] = [];
    const total: number = this.pollutantChoices().length + 1;
    for (let i = 0; i < Math.min(INLINE_POLLUTANT_COUNT, total); i++) {
      out.push(i);
    }
    return out;
  }

  private selectPollutant(id: string): void {
    this.pollutantId = id;
    // The chart's axis, the header and the sections all change with it, so the marker has to go.
    this.activeHourMs = -1;
  }

  /**
   * `AirQualitySwitcher` (DetailsAirQuality.kt:542-654) — a connected ButtonGroup whose tail moves
   * into a ⋮ menu, the same overflow rule the trend tabs already use (TrendTabGroup.ets:15-16).
   */
  @Builder
  private pollutantSwitcher() {
    Row({ space: 2 }) {
      ForEach(this.inlineIndices(), (index: number) => {
        Row({ space: Dimens.SMALL_MARGIN }) {
          if (index === this.selectedPollutantIndex()) {
            Image($r('app.media.ic_check'))
              .width(18)
              .height(18)
              .fillColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark))
          }
          Text(this.pollutantLabel(index))
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(index === this.selectedPollutantIndex()
              ? AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark)
              : AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
            .maxLines(1)
        }
        .layoutWeight(1)
        .height(POLLUTANT_CHIP_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(index === this.selectedPollutantIndex()
          ? AppColors.PRIMARY_CONTAINER.resolve(this.isDark)
          : AppColors.SURFACE_VARIANT.resolve(this.isDark))
        .borderRadius(POLLUTANT_CHIP_HEIGHT / 2)
        .onClick(() => {
          this.selectPollutant(this.pollutantIdAt(index));
        })
      }, (index: number) => index.toString() + ':' + this.pollutantLabel(index))

      if (this.pollutantChoices().length + 1 > INLINE_POLLUTANT_COUNT) {
        Image($r('app.media.ic_more_vert'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
          .margin({ left: Dimens.SMALL_MARGIN })
          .responseRegion({ x: '-50%', y: '-50%', width: '200%', height: '200%' })
          .bindMenu(this.pollutantOverflowShown, this.pollutantOverflowMenu, {
            onDisappear: () => {
              this.pollutantOverflowShown = false;
            }
          })
          .onClick(() => {
            this.pollutantOverflowShown = true;
          })
      }
    }
    .width('100%')
  }

  private items(): DetailsItemModel[] {
    return this.location === null ? [] : detailsItems(this.location, this.screen, this.dayIndex);
  }

  /**
   * `DetailsItem` (DetailsCommon.kt:82-135) — icon, bold bodyLarge headline with a help glyph
   * beside it, supporting line under, the whole row tapping to show the PlainTooltip.
   */
  @Builder
  private detailsItem(item: DetailsItemModel) {
    Row({ space: Dimens.SMALL_MARGIN }) {
      if (item.icon.length > 0) {
        Image(detailsItemIcon(item.icon))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.isDark))
      }
      Column() {
        Row({ space: Dimens.SMALL_MARGIN }) {
          Text(item.headline)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            /*
             * The headline is styled `bodyLarge`, so it takes its 24 sp line; the supporting line
             * below is a BARE `Text` with no style at all (DetailsCommon.kt:130-132), which keeps
             * the font's own leading. Measured on the reference, a `DetailsItem` is 139 px, and
             * 78 + 61 is exactly that — this port drew 61 + 53.
             */
            .lineHeight(LineHeights.BODY_LARGE)
          if (item.explanation.length > 0) {
            // Sized to the headline's font, as the Kotlin sizes it (kt:120-128).
            Image($r('app.media.ic_help_outline'))
              .width(Dimens.TITLE_TEXT_SIZE)
              .height(Dimens.TITLE_TEXT_SIZE)
              .fillColor(AppColors.ON_SURFACE.resolve(this.isDark))
          }
        }
        .alignItems(VerticalAlign.Center)

        if (item.supporting.length > 0) {
          // A bare `Text(it)` in the Kotlin — 16 sp with NO line height, unlike the headline.
          Text(item.supporting)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (item.explanation.length > 0) {
        this.tooltipText = item.explanation;
        this.tooltipOpen = true;
      }
    })
    /*
     * A custom builder rather than `message:`, because the system popup is a light bubble and a
     * Material 3 PlainTooltip is inverseSurface with inverseOnSurface bodySmall text. The NDK
     * draws that pair directly; matching it here keeps the two ports comparable.
     */
    .bindPopup(this.tooltipOpen, {
      builder: (): void => { this.tooltipBubble(); },
      placement: Placement.Top,
      popupColor: AppColors.SURFACE_INVERSE.resolve(this.isDark),
      radius: 4,
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible) {
          this.tooltipOpen = false;
        }
      }
    })
  }

  @Builder
  private tooltipBubble() {
    Text(this.tooltipText)
      .fontFamily(APP_FONT_FAMILY)
      .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
      .fontColor(AppColors.ON_SURFACE_INVERSE.resolve(this.isDark))
      .padding({ left: Dimens.SMALL_MARGIN, right: Dimens.SMALL_MARGIN, top: 4, bottom: 4 })
  }

  private sections(): DetailsSection[] {
    return this.location === null
      ? []
      : detailsSectionsFor(this.location, this.screen, this.dayIndex, this.pollutantId);
  }

  /** DetailsSectionHeader (with its optional bodySmall subtitle) + DetailsCardText or a row list. */
  @Builder
  private section(section: DetailsSection, dividerFollows: boolean = false) {
    Column() {
      if (section.heading.length > 0) {
        Text(section.heading)
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(22)
          .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
          // titleLarge, 22 sp on a 28 sp line: Android 91 px, this port 84 without it.
          .lineHeight(LineHeights.TITLE_LARGE)
          .margin({ left: Dimens.NORMAL_MARGIN,
            bottom: section.subtitle.length > 0 ? 0 : Dimens.SMALL_MARGIN })
      }
      if (section.subtitle.length > 0) {
        Text(section.subtitle)
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
          .lineHeight(LineHeights.BODY_SMALL)
          .margin({ left: Dimens.NORMAL_MARGIN, bottom: Dimens.SMALL_MARGIN })
      }

      if (section.paragraphs.length > 0 || section.rows.length > 0) {
        Column({ space: section.rows.length > 0 ? Dimens.SMALL_MARGIN : Dimens.NORMAL_MARGIN }) {
          // A scale table's bold header row (DetailsUV.kt:331-345).
          if (section.headerLabel.length > 0) {
            Row({ space: Dimens.SMALL_MARGIN }) {
              Text(section.headerLabel)
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.TITLE_TEXT_SIZE)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                .lineHeight(LineHeights.BODY_LARGE)
                .layoutWeight(section.labelWeight)
              // Air quality and Beaufort have a THIRD column (kt:736-756 / DetailsWind.kt:520-535).
              if (section.headerMiddle.length > 0) {
                Text(section.headerMiddle)
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(Dimens.TITLE_TEXT_SIZE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                  .lineHeight(LineHeights.BODY_LARGE)
                  .layoutWeight(section.middleWeight)
              }
              Text(section.headerValue)
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.TITLE_TEXT_SIZE)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                .lineHeight(LineHeights.BODY_LARGE)
                .textAlign(TextAlign.End)
                .layoutWeight(section.valueWeight)
            }
            .width('100%')
          }

          ForEach(section.paragraphs, (paragraph: string) => {
            Text(paragraph)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.TITLE_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
              /*
               * `DetailsCardText` and every scale cell are plain `Text`s, so they take Compose's
               * default style — bodyLarge, 16 sp on a 24 sp line. Measured against the reference:
               * a four-line paragraph is 312 px there and was 244 here, 78 a line against 61.
               */
              .lineHeight(LineHeights.BODY_LARGE)
              .width('100%')
          }, (paragraph: string) => paragraph.substring(0, 24))

          if (section.pollutantGrid) {
            this.pollutantDetailsGrid(section.rows)
          } else if (section.pollenGrid) {
            this.pollenDetailsGrid(section.rows)
          } else if (section.listItemRows) {
            this.listItemRows(section.rows)
          } else {
            ForEach(section.rows, (row: DetailsRow, index: number) => {
              Row({ space: Dimens.SMALL_MARGIN }) {
                /*
                 * The first column is a Row of the dot and the label sharing ONE weight, not two
                 * siblings — DetailsUV.kt:357-372, DetailsWind.kt:564-579,
                 * DetailsAirQuality.kt:786-800. Drawn as a nested Row so the dot does not eat into
                 * the second column's share.
                 */
                Row({ space: Dimens.SMALL_MARGIN }) {
                  if (row.dotColor.length > 0) {
                    /*
                     * `Icon(ic_circle, size = material_icon_size)` — 24 dp, not 16. Measured: the
                     * reference's row text starts at x=208 and this port's at 182, which is
                     * exactly the 8 dp the smaller dot gave back.
                     */
                    Circle({ width: Dimens.MATERIAL_ICON_SIZE, height: Dimens.MATERIAL_ICON_SIZE })
                      .fill(row.dotColor)
                  }
                  Text(row.label)
                    .fontFamily(APP_FONT_FAMILY)
                    .fontSize(Dimens.TITLE_TEXT_SIZE)
                    .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                    .lineHeight(LineHeights.BODY_LARGE)
                    .layoutWeight(1)
                }
                .layoutWeight(section.labelWeight)
                .alignItems(VerticalAlign.Center)
                if (row.middle.length > 0) {
                  // Also a plain Text in the Kotlin: bodyLarge onSurface, not a smaller variant.
                  Text(row.middle)
                    .fontFamily(APP_FONT_FAMILY)
                    .fontSize(Dimens.TITLE_TEXT_SIZE)
                    .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                    .lineHeight(LineHeights.BODY_LARGE)
                    .layoutWeight(section.middleWeight)
                }
                if (row.value.length > 0) {
                  Text(row.value)
                    .fontFamily(APP_FONT_FAMILY)
                    .fontSize(Dimens.TITLE_TEXT_SIZE)
                    .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
                    .lineHeight(LineHeights.BODY_LARGE)
                    .textAlign(TextAlign.End)
                    .layoutWeight(section.valueWeight)
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }, (row: DetailsRow, index: number) =>
              index.toString() + ':' + row.label + ':' + row.value + ':' + row.middle)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        /*
         * A `ListItem` carries its OWN 16 dp horizontal padding and its own fixed height, so the
         * card around it has none — the reference's Sun & moon card is 728 px for four rows, four
         * times the 56 dp token, with nothing above the first or below the last.
         */
        .padding(section.listItemRows ? 0 : {
          left: Dimens.NORMAL_MARGIN,
          right: Dimens.NORMAL_MARGIN,
          top: Dimens.SMALL_MARGIN,
          bottom: Dimens.SMALL_MARGIN
        })
        .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.isDark))
        .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    /*
     * The 16 dp between sections is the `item { Spacer(normal_margin) }` the Kotlin puts between
     * them. A section immediately followed by a `DetailsSectionDivider` does NOT get it: the
     * divider carries its own 16 dp above. Measured on the reference's humidity page, the About
     * card ends at 2182 and "Dew point" starts at 2289 — 107 px, which is 16 + 1 + 16 dp exactly.
     */
    .margin({ bottom: dividerFollows ? 0 : Dimens.NORMAL_MARGIN })
  }

  /**
   * The Sun & moon card's rows — four Material3 `ListItem`s (DetailsSunMoon.kt:339-558).
   *
   * A `ListItem`'s height is a FIXED TOKEN: one line with a leading image is
   * `ListItemOneLineContainerHeight` = 56 dp, not the height of its text. Measured on the
   * reference the rows sit on an exact 182 px pitch (1376 / 1558 / 1740 / 1922); this port drew
   * them as five bare Texts on an 87 px one. Its own comment in Dimens.ets has said this since the
   * alert pill, and this is the fifth time the project has had to relearn it.
   *
   * Padding is ListItemDefaults': 16 dp a side, and 16 dp between the leading image and the
   * headline — the reference's icon is at x=104 and its text at x=234, off a card edge of 52.
   */
  @Builder
  private listItemRows(rows: DetailsRow[]) {
    Column() {
      ForEach(rows, (row: DetailsRow, index: number) => {
        Row({ space: Dimens.NORMAL_MARGIN }) {
          if (row.moonPhaseAngle >= 0) {
            // `DailyMoonPhase`'s leading content is a MoonPhaseView at the day's angle (kt:534-548).
            MoonPhaseCanvas({
              discSize: Dimens.MATERIAL_ICON_SIZE,
              surfaceAngle: row.moonPhaseAngle,
              strokeColor: AppColors.ON_SURFACE.resolve(this.isDark),
              redrawKey: row.moonPhaseAngle.toString() + (this.isDark ? 'd' : 'l')
            })
              .width(Dimens.MATERIAL_ICON_SIZE)
              .height(Dimens.MATERIAL_ICON_SIZE)
          } else if (row.icon.length > 0) {
            Image(listItemIcon(row.icon))
              .width(Dimens.MATERIAL_ICON_SIZE)
              .height(Dimens.MATERIAL_ICON_SIZE)
              .fillColor(AppColors.ON_SURFACE.resolve(this.isDark))
          }
          Text(row.label)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            .lineHeight(LineHeights.BODY_LARGE)
            .layoutWeight(1)
        }
        .width('100%')
        .height(Dimens.LIST_ITEM_ONE_LINE_HEIGHT)
        .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
        .alignItems(VerticalAlign.Center)
      }, (row: DetailsRow, index: number) => index.toString() + ':' + row.label + ':' + row.icon)
    }
    .width('100%')
  }

  /**
   * `AirQualityDetails` (DetailsAirQuality.kt:656-682) — a FlowRow of two per row, each a bold
   * pollutant name, a 10 vp progress bar in that pollutant's colour over the same colour at 10%,
   * and the concentration right-aligned under it.
   *
   * The bar's fraction is the sub-index over 250, not the concentration over its band — "we use
   * air quality index for the progress bar instead of concentration for more realistic bar"
   * (kt:170) — and it arrives in the row's `middle`.
   */
  @Builder
  private pollutantDetailsGrid(rows: DetailsRow[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(rows, (row: DetailsRow, index: number) => {
        Column({ space: 2 }) {
          Text(row.label)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            .width('100%')
          Stack({ alignContent: Alignment.Start }) {
            // The track is the bar's own colour at 10%, not a separate trackColor (kt:826-831).
            Row()
              .width('100%')
              .height(POLLUTANT_BAR_HEIGHT)
              .backgroundColor(row.dotColor)
              .opacity(0.1)
              .borderRadius(POLLUTANT_BAR_HEIGHT / 2)
            Row()
              .width((Number.parseFloat(row.middle) * 100).toString() + '%')
              .height(POLLUTANT_BAR_HEIGHT)
              .backgroundColor(row.dotColor)
              .borderRadius(POLLUTANT_BAR_HEIGHT / 2)
          }
          .width('100%')
          .height(POLLUTANT_BAR_HEIGHT)
          Text(row.value)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
            .width('100%')
            .textAlign(TextAlign.End)
        }
        .width('50%')
        .padding(Dimens.SMALL_MARGIN)
        .alignItems(HorizontalAlign.Start)
      }, (row: DetailsRow, index: number) =>
        index.toString() + ':' + row.label + ':' + row.value + ':' + row.middle)
    }
    .width('100%')
  }

  /**
   * `PollenGrid` (AllergenComposables.kt:54-131) — a FlowRow of two per row, each a
   * material-icon-sized dot in the allergen's colour beside its name in titleMedium over
   * "12/m³ – Low" in bodyMedium. Rows are spaced a normal_margin apart and the whole grid is
   * padded by one (kt:63-67).
   */
  @Builder
  private pollenDetailsGrid(rows: DetailsRow[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(rows, (row: DetailsRow, index: number) => {
        Row({ space: Dimens.SMALL_MARGIN }) {
          Image($r('app.media.ic_circle'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(row.dotColor)
          Column() {
            Text(row.label)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.TITLE_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE.resolve(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(row.value)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.CONTENT_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('50%')
        .padding({ top: Dimens.SMALL_MARGIN, bottom: Dimens.SMALL_MARGIN })
        .alignItems(VerticalAlign.Center)
      }, (row: DetailsRow, index: number) => index.toString() + ':' + row.label + ':' + row.value)
    }
    .width('100%')
  }

  /** A tap anywhere outside the open menu closes it, as FloatingActionButtonMenu does. */
  @Builder
  private menuScrim() {
    Column()
      .width('100%')
      .height('100%')
      .onClick(() => {
        this.menuOpen = false;
      })
  }

  /** FloatingActionButtonMenu (kt:284-347) - the other detail screens, listed above the FAB. */
  @Builder
  private fabMenu() {
    Column({ space: Dimens.SMALL_MARGIN }) {
      if (this.menuOpen && this.location !== null) {
        ForEach(toDetailScreenList(this.location), (item: DetailScreen) => {
          Row({ space: Dimens.SMALL_MARGIN }) {
            Image(detailScreenIcon(item))
              .width(Dimens.MATERIAL_ICON_SIZE)
              .height(Dimens.MATERIAL_ICON_SIZE)
              .fillColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark))
            Text(detailScreenName(item))
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.TITLE_TEXT_SIZE)
              .fontColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark))
              .maxLines(1)
          }
          .padding({
            left: Dimens.NORMAL_MARGIN,
            right: Dimens.NORMAL_MARGIN,
            top: Dimens.SMALL_MARGIN + 4,
            bottom: Dimens.SMALL_MARGIN + 4
          })
          .backgroundColor(AppColors.PRIMARY_CONTAINER.resolve(this.isDark))
          .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
          .onClick(() => {
            this.screen = item;
            this.activeHourMs = -1;
            this.activeHourMs2 = -1;
            this.menuOpen = false;
          })
        }, (item: DetailScreen) => item)
      }

      // ToggleFloatingActionButton: its icon becomes a * while the menu is open (kt:303-312).
      Row() {
        Image(this.menuOpen ? $r('app.media.ic_close') : detailScreenIcon(this.screen))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.isDark))
      }
      .width(FAB_SIZE)
      .height(FAB_SIZE)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppColors.PRIMARY_CONTAINER.resolve(this.isDark))
      .borderRadius(Dimens.NORMAL_MARGIN)
      .onClick(() => {
        this.menuOpen = !this.menuOpen;
      })
    }
    .alignItems(HorizontalAlign.End)
    .margin({ right: Dimens.NORMAL_MARGIN, bottom: Dimens.NORMAL_MARGIN })
  }
}

/**
 * A digest of everything a section DRAWS, for the ForEach key.
 *
 * ForEach only rebuilds an item whose key changed, and `section` reaches the @Builder by value, so
 * a key that omits the body leaves the previous day's card on screen under the right heading.
 */
function sectionKey(section: DetailsSection): string {
  let key: string = section.heading + '|' + section.subtitle + '|' + section.headerLabel + '|'
    + section.headerValue;
  for (const paragraph of section.paragraphs) {
    key += '|' + paragraph;
  }
  for (const row of section.rows) {
    key += '|' + row.label + '~' + row.value + '~' + row.dotColor;
  }
  return key;
}
