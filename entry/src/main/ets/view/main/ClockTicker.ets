/*
 * The minute tick behind the Clock block.
 *
 * Android's `TextClock` and `AnalogClock` both register for `Intent.ACTION_TIME_TICK`, which the
 * system broadcasts on every minute BOUNDARY — not on a 60 s timer started whenever the view
 * happened to be attached. The difference is visible: a naive interval started at :37 would roll
 * the display at :37 of each minute, leaving the clock a minute behind for most of every minute.
 * This aligns to the boundary the way the broadcast does, then repeats each minute.
 *
 * The observable is the TIME ITSELF, truncated to the minute, rather than a meaningless counter.
 * That is deliberate: a tile that reads `minuteOfEpoch` both subscribes and gets the value it
 * needs, so there is no dummy read to keep alive — and truncating to the minute is exactly what a
 * TextClock whose format carries no seconds displays anyway.
 */

@ObservedV2
export class ClockTicker {
  static readonly instance: ClockTicker = new ClockTicker();

  /** Whole minutes since the epoch. Changes once per minute boundary. */
  @Trace minuteOfEpoch: number = Math.floor(Date.now() / 60000);

  private alignTimer: number = -1;
  private minuteTimer: number = -1;
  private starts: number = 0;

  /** The instant this value stands for — the top of the current minute, in local ms. */
  static now(): Date {
    return new Date(ClockTicker.instance.minuteOfEpoch * 60000);
  }

  /**
   * Reference-counted, because every clock tile on every Swiper page calls it. Without the count
   * the first page to go away would stop the timer for the pages still on screen.
   */
  start(): void {
    this.starts++;
    if (this.starts > 1) {
      return;
    }
    this.minuteOfEpoch = Math.floor(Date.now() / 60000);
    const now = new Date();
    const msToBoundary: number = (60 - now.getSeconds()) * 1000 - now.getMilliseconds();
    this.alignTimer = setTimeout(() => {
      this.alignTimer = -1;
      this.minuteOfEpoch = Math.floor(Date.now() / 60000);
      this.minuteTimer = setInterval(() => {
        this.minuteOfEpoch = Math.floor(Date.now() / 60000);
      }, 60000);
    }, msToBoundary);
  }

  stop(): void {
    if (this.starts > 0) {
      this.starts--;
    }
    if (this.starts > 0) {
      return;
    }
    if (this.alignTimer !== -1) {
      clearTimeout(this.alignTimer);
      this.alignTimer = -1;
    }
    if (this.minuteTimer !== -1) {
      clearInterval(this.minuteTimer);
      this.minuteTimer = -1;
    }
  }
}
