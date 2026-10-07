/*
 * Host for the trend columns — the ArkTS equivalent of TrendRecyclerView.
 *
 * Two responsibilities, both from TrendRecyclerView.kt:
 *   - scroll the columns horizontally (the List below)
 *   - draw the horizontal key lines behind them (drawKeyLines, kt:88-166)
 *
 * The key line band is taken from the first column, matching kt:97-100.
 * Key lines are only drawn when isTrendHorizontalLinesEnabled is on; that setting defaults to true
 * (SettingsManager.kt:326-328) and arrives as `keyLinesEnabled` from whichever screen hosts this
 * list. (This comment used to say the value was hard-coded "until the settings screens land". They
 * landed; all four call sites pass `AppSettings.instance.trendHorizontalLines`.)
 */

import { Dimens, TrendDimens } from '../../theme/Dimens';
import { ChartColors } from './ChartData';
import { KeyLine, TrendItemModel } from './TrendDataBuilder';
import { TrendItem } from './TrendItem';
import { DoubleHistogramColors } from './DoubleHistogramCanvas';
import { canvasFont, canvasFontAscent, canvasFontDescent } from './CanvasText';

/**
 * Backing store for the LazyForEach below.
 *
 * TrendRecyclerView is a RecyclerView: it keeps roughly as many item views alive as fit on screen
 * and recycles the rest. The port used a plain ForEach, which instantiates *every* item up front —
 * and the hourly card's item count is `nextHourlyForecast.size` (HourlyTemperatureAdapter.kt:205),
 * which with forecast_days=16 is around 384. Each item carries its own Canvas plus up to three
 * Images, so a location page was building ~384 canvases, and the Swiper keeps a neighbouring page
 * alive as well. That is the "loading is extremely slow" report, and it is also why switching a
 * trend tab took seconds: a new series meant rebuilding all of them.
 *
 * LazyForEach restores the RecyclerView behaviour — only the visible window plus `cachedCount`
 * exists at a time. It matters twice over here, because this project exists to compare memory.
 */
class TrendItemDataSource implements IDataSource {
  private items: TrendItemModel[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): TrendItemModel {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }

  /** Swapping the series (a tab change, or a completed refresh) is a wholesale reload. */
  reload(items: TrendItemModel[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}

@ComponentV2
export struct TrendList {
  @Param items: TrendItemModel[] = [];
  /**
   * The rebind counter. The items ARRAY reference is permanent (MainScreen retains it and copies
   * new values into the same @ObservedV2 models), so the array param never signals a change —
   * this version does. On a bump the list adopts the new layout's chart band, redraws the key
   * lines, and — only if the item COUNT changed — reloads the LazyForEach. The columns
   * themselves rebind through their models; no reload, no node rebuilds, no re-measure.
   */
  @Param itemsVersion: number = 0;
  @Param itemCountChanged: boolean = false;
  @Param keyLines: KeyLine[] = [];
  /**
   * screen 3c's `trend_horizontal_line_switch` (MainScreenSettingsScreen.kt:139-157).
   *
   * The lines are still BUILT when this is off — TrendDataBuilder keeps producing them, exactly as
   * the Kotlin's adapters do — they are simply not painted. Upstream gates the drawing the same
   * way, through TrendRecyclerView's key-line list being ignored rather than the data changing.
   */
  @Param keyLinesEnabled: boolean = true;
  @Param colors: ChartColors = new ChartColors();
  @Param doubleColors: DoubleHistogramColors = new DoubleHistogramColors();
  @Param isDaily: boolean = true;
  @Param listHeight: number = 0;
  /** colorOutline — TrendRecyclerView.setLineColor (DailyViewHolder.kt:139-141). */
  @Param keyLineColor: string = '#10000000';
  /** colorTextGrey / colorTextGrey2nd (DailyViewHolder.kt:142-151). */
  @Param keyLineTextColor: string = '#FF4D4D4D';
  @Param accentTextColor: string = '#FF000000';
  @Param bodyTextColor: string = '#FF666666';
  @Param captionTextColor: string = '#FFB2B2B2';
  /** Highest/lowest of the current series — the key line scale (kt:104-110). */
  @Param highestValue: number | null = null;
  @Param lowestValue: number | null = null;
  /** Index the list should start at, e.g. today for the daily card (DailyViewHolder.kt:156-158). */
  @Param initialIndex: number = 0;
  @Event onItemClick: (index: number) => void = () => {
  };

  @Local private chartTop: number = 0;
  @Local private chartBottom: number = 0;
  @Local private listWidth: number = 0;
  /**
   * The chart band height for the CURRENT column layout, handed to every TrendItem as
   * presetChartHeight so rebuilt columns mount their canvas in a single pass (see TrendItem).
   * Zero until a column of this layout has measured itself once.
   */
  @Local private presetBand: number = 0;
  /** Measured band (top / height) per column-layout signature, learned from the first report. */
  private bandTopBySignature: Map<string, number> = new Map();
  private bandHeightBySignature: Map<string, number> = new Map();

  /**
   * Columns lay out identically when they agree on these flags — a tab switch can change any of
   * them (UV drops the icons, hourly has no date line), which changes the band height.
   */
  private layoutSignature(): string {
    if (this.items.length === 0) {
      return '';
    }
    const first: TrendItemModel = this.items[0];
    return (this.isDaily ? 'd' : 'h') + (first.hasIcons ? 'i' : '-') +
      (first.subLabel !== null && first.subLabel.length > 0 ? 's' : '-');
  }

  /** Adopts the remembered band for the current layout, or clears it for an unseen one. */
  private adoptBandForLayout(): void {
    const signature: string = this.layoutSignature();
    const height: number | undefined = this.bandHeightBySignature.get(signature);
    const top: number | undefined = this.bandTopBySignature.get(signature);
    if (height !== undefined && top !== undefined) {
      this.presetBand = height;
      this.chartTop = top;
      this.chartBottom = top + height;
    } else {
      this.presetBand = 0;
    }
  }

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private scroller: Scroller = new Scroller();
  private dataSource: TrendItemDataSource = new TrendItemDataSource();

  private redrawKeyLines(): void {
    if (!this.ready) {
      return;
    }
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.listWidth, this.listHeight);

    if (
      !this.keyLinesEnabled ||
      this.keyLines.length === 0 ||
      this.highestValue === null ||
      this.lowestValue === null ||
      this.chartBottom <= this.chartTop
    ) {
      return;
    }
    const dataRange: number = this.highestValue - this.lowestValue;
    if (dataRange === 0) {
      return;
    }
    const boundaryRange: number = this.chartBottom - this.chartTop;

    for (let i = 0; i < this.keyLines.length; i++) {
      const line: KeyLine = this.keyLines[i];
      // kt:107-109 — lines outside the data range are skipped.
      if (line.value > this.highestValue || line.value < this.lowestValue) {
        continue;
      }
      const y: number = this.chartBottom - (line.value - this.lowestValue) / dataRange * boundaryRange;

      ctx.beginPath();
      ctx.lineCap = 'round';
      ctx.lineWidth = TrendDimens.KEY_LINE_WIDTH;
      ctx.strokeStyle = this.keyLineColor;
      ctx.moveTo(0, y);
      ctx.lineTo(this.listWidth, y);
      ctx.stroke();

      ctx.fillStyle = this.keyLineTextColor;
      ctx.font = canvasFont(TrendDimens.KEY_LINE_TEXT_SIZE);
      const margin: number = TrendDimens.KEY_LINE_TEXT_MARGIN;
      const ascent: number = canvasFontAscent(TrendDimens.KEY_LINE_TEXT_SIZE);
      const descent: number = canvasFontDescent(TrendDimens.KEY_LINE_TEXT_SIZE);
      // kt:122-163 — above the line sits on the descent, below the line on the ascent.
      const textY: number = line.above ? y - descent - margin : y + ascent + margin;

      ctx.textAlign = 'left';
      ctx.fillText(line.contentLeft, 2 * margin, textY);
      ctx.textAlign = 'right';
      ctx.fillText(line.contentRight, this.listWidth - 2 * margin, textY);
    }
  }

  /**
   * Switching tabs swaps the key lines and the scale, but none of the callbacks below fire for
   * that: the chart band and the list width are unchanged, and onReady runs once. Without this the
   * canvas keeps whatever the previous tab painted — the Conditions "Normal" lines stayed visible
   * on top of the Wind chart, labelled with temperatures.
   */
  @Monitor('keyLines', 'highestValue', 'lowestValue', 'keyLineColor', 'keyLineTextColor',
    'keyLinesEnabled')
  onKeyLinesChanged(monitor: IMonitor): void {
    this.redrawKeyLines();
  }

  /** A tab change or a completed refresh rebound the retained items in place. */
  @Monitor('itemsVersion')
  onItemsRebound(monitor: IMonitor): void {
    this.adoptBandForLayout();
    if (this.itemCountChanged || this.dataSource.totalCount() !== this.items.length) {
      this.dataSource.reload(this.items);
    }
    this.redrawKeyLines();
  }

  aboutToAppear(): void {
    // @Monitor does not fire for the initial value, so the first series is seeded here.
    this.adoptBandForLayout();
    this.dataSource.reload(this.items);
    // DailyViewHolder.kt:156-158 — the daily card opens scrolled to today.
    if (this.initialIndex > 0) {
      setTimeout(() => {
        this.scroller.scrollToIndex(this.initialIndex);
      }, 0);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width('100%')
        .height(this.listHeight)
        .hitTestBehavior(HitTestMode.Transparent)
        .onReady(() => {
          this.ready = true;
          this.redrawKeyLines();
        })

      List({ space: 0, scroller: this.scroller }) {
        LazyForEach(this.dataSource, (item: TrendItemModel, index: number) => {
          ListItem() {
            TrendItem({
              item: item,
              colors: this.colors,
              doubleColors: this.doubleColors,
              isDaily: this.isDaily,
              accentTextColor: this.accentTextColor,
              bodyTextColor: this.bodyTextColor,
              captionTextColor: this.captionTextColor,
              onItemClick: () => {
                this.onItemClick(index);
              },
              presetChartHeight: this.presetBand,
              redrawSalt: this.itemsVersion,
              // Every column has the same internal layout, so any of them reports the same band.
              // This used to be restricted to index 0, which no longer works now the list
              // recycles: the daily card opens scrolled to today, so column 0 may never be built.
              onChartBandChange: (top: number, height: number) => {
                // Learn (or correct) the band for this column layout, so the NEXT rebuild of
                // identical columns mounts in a single pass.
                const signature: string = this.layoutSignature();
                const known: number | undefined = this.bandHeightBySignature.get(signature);
                if (known === undefined || Math.abs(known - height) > 0.5) {
                  this.bandHeightBySignature.set(signature, height);
                  this.bandTopBySignature.set(signature, top);
                  this.presetBand = height;
                }
                const bottom: number = top + height;
                if (Math.abs(top - this.chartTop) > 0.5 || Math.abs(bottom - this.chartBottom) > 0.5) {
                  this.chartTop = top;
                  this.chartBottom = bottom;
                  this.redrawKeyLines();
                }
              }
            })
          }
          .width(Dimens.TREND_ITEM_WIDTH)
        }, (item: TrendItemModel) => item.key)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      // RecyclerView keeps a small off-screen buffer either side; this is the equivalent.
      .cachedCount(2)
      .width('100%')
      .height(this.listHeight)
    }
    .width('100%')
    .height(this.listHeight)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const width: number = Number(newValue.width);
      if (width > 0 && Math.abs(width - this.listWidth) > 0.5) {
        this.listWidth = width;
        this.redrawKeyLines();
      }
    })
  }
}
