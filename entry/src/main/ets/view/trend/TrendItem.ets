/*
 * One trend column.
 *
 * Layout follows the Android measure pass:
 *   DailyTrendItemView.kt:99-153   week text, date text, day icon, chart, night icon, 16vp bottom
 *   HourlyTrendItemView.kt:82-127  hour text, icon, chart, 16vp bottom
 *
 * Text sizes are title_text (16fp) for the week/hour line and content_text (14fp) for the date
 * line (DailyTrendItemView.kt:87-94, styles.xml:150-162).
 *
 * The chart takes whatever vertical space is left, exactly as the Android measure pass does; the
 * height is read back through onAreaChange so the canvas can compute its geometry in real units.
 */

import { Dimens, TrendDimens } from '../../theme/Dimens';
import { ChartColors } from './ChartData';
import { TrendItemModel } from './TrendDataBuilder';
import { DoubleHistogramColors } from './DoubleHistogramCanvas';
import { TrendChartCanvas } from './TrendChartCanvas';
import { APP_FONT_FAMILY } from '../../common/Typography';

/**
 * @ReusableV2 — this is the RecyclerView view-holder recycling the port was missing.
 *
 * LazyForEach keeps only a window of items alive, but by default it DESTROYS a component that
 * scrolls out and BUILDS a fresh one for the item scrolling in. A trace of a hard fling through
 * the hourly list (~384 columns) showed exactly that: 115 TrendItem builds costing 1509 ms —
 * ~13 ms each — 115 canvas builds and 224 node destroys, producing 52 frames over 16.6 ms with a
 * 216 ms worst case. The daily list hides the problem because its 16 columns are all built and
 * cached after one fling; the hourly list never stops paying.
 *
 * RecyclerView never rebuilds: it rebinds a recycled view. @ReusableV2 gives ArkUI the same
 * licence — the node tree is kept in a pool and handed back with new @Param values.
 */
@ReusableV2
@ComponentV2
export struct TrendItem {
  @Param item: TrendItemModel = new TrendItemModel();
  @Param colors: ChartColors = new ChartColors();
  @Param doubleColors: DoubleHistogramColors = new DoubleHistogramColors();
  /** True for the daily card, which also shows a date line and a night icon. */
  @Param isDaily: boolean = true;
  /** AbsDailyTrendAdapter.kt:77-80 — accent vs. body colour for the labels. */
  @Param accentTextColor: string = '#FF000000';
  @Param bodyTextColor: string = '#FF666666';
  @Param captionTextColor: string = '#FFB2B2B2';
  @Event onItemClick: () => void = () => {
  };
  /**
   * Reports the chart band (top offset within this column, and its height) so the host can place
   * the key lines. TrendRecyclerView.kt:97-100 reads exactly this off its first child.
   */
  @Event onChartBandChange: (top: number, height: number) => void = () => {
  };
  /**
   * The chart band height the host already measured on an identical column, or 0.
   *
   * Without it every freshly built column mounts with chartHeight 0 (no canvas child), measures
   * itself, writes the @Local, and renders a SECOND time to mount the canvas — and a tab switch
   * rebuilds every visible column, so the trace showed the whole list doing that double pass
   * inside one 450 ms onAreaChange JS wave. Every column of a list has the same internal layout,
   * so after the first one has ever measured, the rest can mount right-sized in a single pass.
   */
  @Param presetChartHeight: number = 0;
  /**
   * Folded into the canvases' redrawKey. A refresh rebinds the models under UNCHANGED item keys
   * (same tab, same index), so without this the canvases would keep the pre-refresh picture —
   * the key alone only changes on a tab switch.
   */
  @Param redrawSalt: number = 0;

  @Local private chartHeight: number = 0;

  /** The preset when the host knows it, this column's own measurement until then. */
  private chartBandHeight(): number {
    return this.presetChartHeight > 0 ? this.presetChartHeight : this.chartHeight;
  }

  private subLabelText(): string {
    return this.item.subLabel === null ? '' : this.item.subLabel;
  }

  build() {
    Column() {
      // Week (daily) or hour (hourly) label.
      Text(this.item.topLabel)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontColor(this.item.accent ? this.accentTextColor : this.bodyTextColor)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: TrendDimens.ITEM_TEXT_MARGIN, bottom: TrendDimens.ITEM_TEXT_MARGIN })

      // Date line — daily only.
      if (this.isDaily && this.subLabelText().length > 0) {
        Text(this.subLabelText())
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(this.item.accent ? this.bodyTextColor : this.captionTextColor)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: TrendDimens.ITEM_TEXT_MARGIN, bottom: TrendDimens.ITEM_TEXT_MARGIN })
      }

      // Day icon. The slot is kept even when the icon is missing, matching
      // missingIconVisibility = INVISIBLE (DailyTemperatureAdapter.kt:112-115). Tabs that show no
      // icon at all (UV, sunshine, cloud cover) leave hasIcons false, so the slot collapses the
      // way it does on Android where setDayIconDrawable is simply never called.
      if (this.item.hasIcons) {
        Stack() {
          if (this.item.dayIcon !== null) {
            if (this.item.dayIconIsArrow) {
              // PorterDuff SRC_ATOP tint on the wind arrows (DailyWindAdapter.kt:71-75).
              Image(this.item.dayIcon)
                .width(TrendDimens.ITEM_ICON_SIZE)
                .height(TrendDimens.ITEM_ICON_SIZE)
                .objectFit(ImageFit.Contain)
                .fillColor(this.item.dayIconTint)
                .rotate({ angle: this.item.dayIconRotation })
            } else {
              Image(this.item.dayIcon)
                .width(TrendDimens.ITEM_ICON_SIZE)
                .height(TrendDimens.ITEM_ICON_SIZE)
                .objectFit(ImageFit.Contain)
            }
          }
        }
        .width(TrendDimens.ITEM_ICON_SIZE)
        .height(TrendDimens.ITEM_ICON_SIZE)
        .margin({ top: TrendDimens.ITEM_ICON_MARGIN, bottom: TrendDimens.ITEM_ICON_MARGIN })
      }

      // Chart — fills the remaining height. ONE component for both chart kinds: an if/else on
      // the kind here would destroy and rebuild the canvas in every column whenever a tab switch
      // crossed the polyline/histogram divide — see TrendChartCanvas.
      Stack() {
        if (this.chartBandHeight() > 0) {
          TrendChartCanvas({
            kind: this.item.chartKind,
            data: this.item.polyline,
            doubleData: this.item.doubleHistogram,
            colors: this.colors,
            doubleColors: this.doubleColors,
            canvasWidth: Dimens.TREND_ITEM_WIDTH,
            canvasHeight: this.chartBandHeight(),
            redrawKey: this.item.key + '@' + this.chartBandHeight().toString() + '@' + this.redrawSalt.toString()
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const height: number = Number(newValue.height);
        if (height <= 0) {
          return;
        }
        // With a trusted preset there is nothing to re-render for; the write (and the second
        // render pass it forces) only happens when this column has to measure for itself.
        if (this.presetChartHeight <= 0 && Math.abs(height - this.chartHeight) > 0.5) {
          this.chartHeight = height;
        }
        // Always reported: the host keeps the band per column layout and uses the report to
        // seed or correct it (a preset that disagrees with reality gets fixed here).
        this.onChartBandChange(Number(newValue.position.y), height);
      })

      // Night icon — daily only, pinned above the bottom margin
      // (DailyTrendItemView.kt:137-142).
      if (this.isDaily && this.item.hasIcons) {
        Stack() {
          if (this.item.nightIcon !== null) {
            if (this.item.nightIconIsArrow) {
              // DailyWindAdapter.kt:101-105 — the night arrow takes the night wind's colour.
              Image(this.item.nightIcon)
                .width(TrendDimens.ITEM_ICON_SIZE)
                .height(TrendDimens.ITEM_ICON_SIZE)
                .objectFit(ImageFit.Contain)
                .fillColor(this.item.nightIconTint)
                .rotate({ angle: this.item.nightIconRotation })
            } else {
              Image(this.item.nightIcon)
                .width(TrendDimens.ITEM_ICON_SIZE)
                .height(TrendDimens.ITEM_ICON_SIZE)
                .objectFit(ImageFit.Contain)
            }
          }
        }
        .width(TrendDimens.ITEM_ICON_SIZE)
        .height(TrendDimens.ITEM_ICON_SIZE)
        .margin({ top: TrendDimens.ITEM_ICON_MARGIN, bottom: TrendDimens.ITEM_ICON_MARGIN })
      }
    }
    .width(Dimens.TREND_ITEM_WIDTH)
    .height('100%')
    .padding({ bottom: TrendDimens.ITEM_MARGIN_BOTTOM })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onItemClick();
    })
  }
}
