/*
 * The two hands of the Clock block's AnalogClock (container_main_clock.xml:101-105).
 *
 * `android:dialTint="@android:color/transparent"` hides the framework's dial, so the only thing
 * that view contributes is a pair of hands drawn over the scalloped shape and the two digits.
 *
 * Everything here is MEASURED off the reference, not taken from a spec — the hands belong to the
 * platform's AnalogClock, so there is no app resource to read them from. Method: enable the Clock
 * block on the reference, screencap, and take the bounding box of each hand's colour. At 05:51 on a
 * 552 px card (the shape's own painted extent is 536 px, because the vector's path spans 171.2 of
 * its 176 viewport):
 *
 *     minute hand   bbox 178 x 145 px at (777, 2166), clock centre (931.5, 2287.5)
 *     hour hand     bbox  54 x 129 px at (910, 2295)
 *
 * Solving each bbox against its known angle — 51 min = 306 deg, 5.85 h = 175.5 deg — for the tip
 * distance and the cap radius gives, as fractions of the card side:
 *
 *     stroke width        0.083
 *     hour hand length    0.205
 *     minute hand length  0.294
 *
 * The colours are NOT theme-derived. Sampled in both light and dark mode, the hands are
 * #657985 (accent2_500) and #004C69 (accent1_700) in BOTH — they are the framework drawable's own
 * tints, not the app's palette, so they do not take a ColorPair.
 */

/** system_accent2_500 — the minute hand, in both themes. */
const MINUTE_HAND_COLOR: string = '#FF657985';
/** system_accent1_700 — the hour hand, in both themes. */
const HOUR_HAND_COLOR: string = '#FF004C69';

const STROKE_FRACTION: number = 0.083;
const HOUR_LENGTH_FRACTION: number = 0.205;
const MINUTE_LENGTH_FRACTION: number = 0.294;

@ComponentV2
export struct ClockHandsCanvas {
  /** The card's side in px. Nothing is drawn until the card has been measured. */
  @Param side: number = 0;
  /** Local hour 0-23 and minute 0-59, already offset into the location's zone. */
  @Param hour: number = 0;
  @Param minute: number = 0;
  /** Changing this forces a repaint — `onReady` fires once, so a changed .id() would not. */
  @Param redrawKey: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @Monitor('redrawKey', 'side')
  onRedraw(): void {
    this.draw();
  }

  private draw(): void {
    const s: number = this.side;
    if (s <= 0) {
      return;
    }
    const ctx = this.context;
    ctx.clearRect(0, 0, s, s);

    const cx: number = s / 2;
    const cy: number = s / 2;
    ctx.lineCap = 'round';
    ctx.lineWidth = s * STROKE_FRACTION;

    /*
     * Both hands sweep continuously, as AnalogClock's do: the hour hand is at
     * (h + m/60) / 12 of a turn, not at a whole hour, which is why the reference's hour hand sits
     * just past the 5 at 05:51. Angles are measured clockwise from 12 o'clock.
     */
    const minuteTurn: number = this.minute / 60;
    const hourTurn: number = ((this.hour % 12) + this.minute / 60) / 12;

    this.hand(cx, cy, hourTurn, s * HOUR_LENGTH_FRACTION, HOUR_HAND_COLOR);
    this.hand(cx, cy, minuteTurn, s * MINUTE_LENGTH_FRACTION, MINUTE_HAND_COLOR);
  }

  /** One hand from the centre outwards. `turn` is 0..1 clockwise from 12. */
  private hand(cx: number, cy: number, turn: number, length: number, color: string): void {
    const ctx = this.context;
    const angle: number = turn * 2 * Math.PI;
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.sin(angle) * length, cy - Math.cos(angle) * length);
    ctx.stroke();
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      // The hands are decoration; the card owns the tap.
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.draw();
      });
  }
}
