/*
 * The daily and hourly trend cards.
 *
 * Both Android layouts are identical apart from the title, the title icon and the list height,
 * so one component covers both:
 *   container_main_daily_trend_card.xml   (ic_calendar,  "Daily forecast",  298dp)
 *   container_main_hourly_trend_card.xml  (ic_schedule,  "Hourly forecast", 206dp)
 *
 * Geometry from those layouts:
 *   card    ShapeAppearance.Material3.Corner.ExtraLarge, strokeWidth 0, elevation 2dp
 *           (AbstractMainCardViewHolder.kt:47-51), 8dp margins on all sides (kt:52-59)
 *   icon    24dp, 20dp start margin, vertically centred on the title
 *   title   textAppearanceTitleMedium, 20dp top margin, 8dp after the icon
 *   subtitle 2dp below the title, 20dp horizontal margins, content_text style
 *   buttons 8dp below the subtitle, aligned with the icon
 *   list    8dp below the buttons, full width
 */

import { Dimens } from '../../theme/Dimens';
import { TrendTab } from '../../model/TrendTab';
import { ChartColors } from '../trend/ChartData';
import { DoubleHistogramColors } from '../trend/DoubleHistogramCanvas';
import { SeriesBundle } from '../trend/TrendDataBuilder';
import { TrendList } from '../trend/TrendList';
import { TrendTabGroup } from './TrendTabGroup';
import { APP_FONT_FAMILY } from '../../common/Typography';

@ComponentV2
export struct TrendCard {
  @Param title: string = '';
  @Param titleIcon: Resource = $r('app.media.ic_calendar');
  @Param subtitle: string | null = null;
  @Param tabs: TrendTab[] = [];
  /**
   * The selected tab is CARD state, initialised once — DailyViewHolder keeps `selectedIndex` on
   * its own trendAdapter, not on the activity. When this was MainScreen state, one chip tap
   * re-rendered the entire screen: every location page's builders re-ran, ~140 ms of diffuse
   * dirty-node work per tap with nothing visibly changing outside this card.
   */
  @Param @Once selectedIndex: number = 0;
  /**
   * Hands back the retained, rebound-in-place series for a tab. Called at build time, so a
   * selection change pulls fresh data with a render scoped to this card alone.
   */
  @Event seriesFor: (index: number) => SeriesBundle = () => new SeriesBundle();
  /**
   * @Event closures are excluded from param diffing, so a refresh would leave this card showing
   * pre-refresh data — this stamp is the ordinary @Param that forces the re-pull (dataVersion +
   * theme colour on the MainScreen side).
   */
  @Param refreshStamp: string = '';
  @Param isDaily: boolean = true;
  @Param listHeight: number = Dimens.DAILY_TREND_ITEM_HEIGHT;
  @Param initialIndex: number = 0;

  @Param cardBackground: string = '#FFFCFCFF';
  @Param onSurfaceInverse: string = '#FF191C1E';
  @Param bodyTextColor: string = '#FF666666';
  @Param captionTextColor: string = '#FFB2B2B2';
  @Param accentTextColor: string = '#FF000000';
  @Param keyLineColor: string = '#10000000';
  @Param keyLineTextColor: string = '#FF4D4D4D';
  /** screen 3c's `trend_horizontal_line_switch`, passed through to the chart canvas. */
  @Param keyLinesEnabled: boolean = true;
  /* The trend chips are Material buttons, so their containers theme with the card. */
  @Param chipContainerColor: string = '#FFDCE3E9';
  @Param chipSelectedContainerColor: string = '#FF00668B';
  @Param chipLabelColor: string = '#FF40484D';
  @Param chipSelectedLabelColor: string = '#FFFFFFFF';
  @Param chartColors: ChartColors = new ChartColors();
  @Param doubleChartColors: DoubleHistogramColors = new DoubleHistogramColors();

  @Event onItemClick: (tabIndex: number, itemIndex: number) => void = () => {
  };

  private subtitleText(): string {
    return this.subtitle === null ? '' : this.subtitle;
  }

  /**
   * The current tab's series, pulled fresh on every build of this card. Reading `refreshStamp`
   * here is deliberate: it ties this card's render to the stamp, so a refresh (which cannot be
   * seen through the @Event) re-pulls through the provider.
   */
  private bundle(): SeriesBundle {
    return this.refreshStamp.length >= 0 ? this.seriesFor(this.selectedIndex) : new SeriesBundle();
  }

  build() {
    // Outer wrapper reproduces the card's 8dp margin (AbstractMainCardViewHolder.kt:52-59).
    // Putting .margin() straight on a .width('100%') card makes it 100% + 16vp wide, so the
    // margin is pushed off-screen and the weather background never shows at the edges.
    Column() {
      Column() {
          // Title row — icon and title, icon vertically centred against the title text.
        Row() {
          Image(this.titleIcon)
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(this.onSurfaceInverse)
          Text(this.title)
            .fontFamily(APP_FONT_FAMILY)
            // textAppearanceTitleMedium is 16sp at weight 500 with 0.15 letter spacing. The port
            // had the size but left the weight at the default 400, which is why the card titles
            // read lighter and looser than the Android ones.
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .letterSpacing(0.15)
            .fontColor(this.onSurfaceInverse)
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: Dimens.LARGE_MARGIN })
        .margin({ top: Dimens.LARGE_MARGIN })

        // Subtitle — hidden when the source gives no summary (DailyViewHolder.kt:68-73).
        if (this.subtitleText().length > 0) {
          Text(this.subtitleText())
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontColor(this.bodyTextColor)
            .width('100%')
            .margin({ top: 2 })
            .padding({ left: Dimens.LARGE_MARGIN, right: Dimens.LARGE_MARGIN })
        }

        Row() {
          TrendTabGroup({
            tabs: this.tabs,
            selectedIndex: this.selectedIndex,
            // Without these the chips kept TrendTabGroup's light-theme defaults, so a dark card
            // still had pale lavender containers where Android's are dark grey. The four are the
            // Material button-group roles: surfaceVariant / primary for the containers,
            // onSurfaceVariant / onPrimary for their labels.
            containerColor: this.chipContainerColor,
            selectedContainerColor: this.chipSelectedContainerColor,
            labelColor: this.chipLabelColor,
            selectedLabelColor: this.chipSelectedLabelColor,
            onSelect: (index: number) => {
              this.selectedIndex = index;
            }
          })
        }
        .width('100%')

        TrendList({
          items: this.bundle().items,
          itemsVersion: this.bundle().itemsVersion,
          itemCountChanged: this.bundle().itemCountChanged,
          keyLines: this.bundle().keyLines,
          colors: this.chartColors,
          doubleColors: this.doubleChartColors,
          isDaily: this.isDaily,
          listHeight: this.listHeight,
          keyLineColor: this.keyLineColor,
          keyLineTextColor: this.keyLineTextColor,
          keyLinesEnabled: this.keyLinesEnabled,
          accentTextColor: this.accentTextColor,
          bodyTextColor: this.bodyTextColor,
          captionTextColor: this.captionTextColor,
          highestValue: this.bundle().highestValue,
          lowestValue: this.bundle().lowestValue,
          initialIndex: this.initialIndex,
          onItemClick: (index: number) => {
            this.onItemClick(this.selectedIndex, index);
          }
        })
          .margin({ top: Dimens.SMALL_MARGIN })
      }
      .width('100%')
      .backgroundColor(this.cardBackground)
      .borderRadius(Dimens.CARD_CORNER_RADIUS)
      .shadow({
        radius: Dimens.CARD_ELEVATION * 2,
        color: '#20000000',
        offsetX: 0,
        offsetY: Dimens.CARD_ELEVATION
      })
      .clip(true)
    }
    .width('100%')
    .padding(Dimens.SMALL_MARGIN)
  }
}
