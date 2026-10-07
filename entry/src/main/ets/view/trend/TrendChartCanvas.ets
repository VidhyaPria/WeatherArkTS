/*
 * The one chart canvas a trend column keeps for its whole life.
 *
 * TrendItem used to choose between two @ComponentV2 canvases with an if/else on the chart kind.
 * Tabs alternate kinds (Conditions is a polyline, Wind a double histogram), so every tab switch
 * destroyed one custom component and built the other in all six visible columns — ~9 ms build
 * plus up to 20 ms destroy each, the 130-270 ms dirty-node flush that survived every other
 * tab-tap fix. This component never unmounts: a kind change just makes the redrawKey @Monitor
 * repaint the same surface through the other painter.
 */

import { ChartColors, ChartData } from './ChartData';
import { ChartKind } from './TrendDataBuilder';
import { PolylineHistogramPainter } from './PolylineHistogramCanvas';
import {
  DoubleHistogramColors,
  DoubleHistogramData,
  DoubleHistogramPainter
} from './DoubleHistogramCanvas';

/** Stateless between paints, so both are shared by every column. */
const POLYLINE_PAINTER = new PolylineHistogramPainter();
const DOUBLE_PAINTER = new DoubleHistogramPainter();

/** Recycled along with its TrendItem — see the note there. */
@ReusableV2
@ComponentV2
export struct TrendChartCanvas {
  @Param kind: ChartKind = ChartKind.POLYLINE;
  @Param data: ChartData = new ChartData();
  @Param doubleData: DoubleHistogramData = new DoubleHistogramData();
  @Param colors: ChartColors = new ChartColors();
  @Param doubleColors: DoubleHistogramColors = new DoubleHistogramColors();
  @Param canvasWidth: number = 0;
  @Param canvasHeight: number = 0;
  /**
   * Changes whenever the size, the data or the kind changes. onReady only fires once, so this is
   * what triggers a repaint after the parent has measured the remaining space.
   */
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  @Monitor('redrawKey')
  onRedrawRequested(monitor: IMonitor): void {
    if (this.ready) {
      this.draw();
    }
  }

  /**
   * Repaint when this component comes back out of the reuse pool.
   *
   * The @Monitor above is not enough on its own. A recycled component is re-inserted with new
   * @Param values, but the canvas it brings with it still holds the PREVIOUS column's drawing,
   * and the repaint has to happen after the node is back in the tree — running it from the param
   * update alone left columns showing a neighbour's chart (a visible step in the temperature
   * polyline, e.g. "6 PM" reading 64° between 72° and 70°).
   *
   * `aboutToReuse` is the V2 reuse callback (CustomComponentV2, API 18); by the time it runs the
   * params are already updated, so a plain redraw is correct. Posting it to the next tick also
   * guarantees the canvas is attached and sized before anything is drawn into it.
   */
  aboutToReuse(): void {
    if (!this.ready) {
      return;
    }
    this.draw();
    setTimeout(() => {
      if (this.ready) {
        this.draw();
      }
    }, 0);
  }

  build() {
    Canvas(this.ctx)
      .width(this.canvasWidth)
      .height(this.canvasHeight)
      .onReady(() => {
        this.ready = true;
        this.draw();
      })
  }

  private draw(): void {
    if (this.kind === ChartKind.POLYLINE) {
      POLYLINE_PAINTER.paint(this.ctx, this.data, this.colors, this.canvasWidth, this.canvasHeight);
    } else {
      DOUBLE_PAINTER.paint(this.ctx, this.doubleData, this.doubleColors, this.canvasWidth, this.canvasHeight);
    }
  }
}
