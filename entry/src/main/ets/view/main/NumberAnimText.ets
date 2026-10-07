/*
 * Port of NumberAnimTextView as the header uses it.
 *
 * HeaderViewHolder.kt:98-104 sets the duration to abs(to - from) * 20ms, clamped to at least
 * 1000ms and at most 2000ms, then HeaderViewHolder.kt:156-162 starts the count from the previous
 * value to the new one when the card enters the screen.
 */

import { APP_FONT_FAMILY } from '../../common/Typography';

@ComponentV2
export struct NumberAnimText {
  /** Value the previous location left behind (mTemperatureFrom). */
  @Param fromValue: number = 0;
  /** Value to land on (mTemperatureTo). */
  @Param toValue: number = 0;
  /** isAnimEnabled — itemAnimationEnabled in the Kotlin. */
  @Param animationEnabled: boolean = true;
  /**
   * textSize / textColor rather than fontSize / fontColor: both of those are attribute
   * methods inherited from CustomComponent, so members of those names collide with them.
   */
  @Param textSize: number = 140;
  @Param textColor: string = '#FF191C1E';
  @Param animKey: string = '';

  @Local private displayed: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.start();
  }

  aboutToDisappear(): void {
    this.stop();
  }

  /**
   * Watches `toValue` as well as `animKey`, and that second name is the fix, not tidiness.
   *
   * `animKey` and `toValue` are two @Params computed from the same `temperatureValue()` in the
   * parent, but they are delivered as separate param writes and nothing guarantees the order. A
   * monitor that fires on `animKey` alone can therefore run while `toValue` is still the PREVIOUS
   * value, and `start()` would snapshot that stale target and dutifully animate to it — leaving
   * the big header number on the old reading while every other field in the header (condition,
   * feels-like, the day/night range — all plain Text) showed the new one.
   *
   * Observed twice: Tokyo rendering 24° beside "Feels like 36°" when Open-Meteo reported 31.2°/
   * 36.1°, and Berlin 23° beside "Feels like 14°" against a reported 16.0°/14.4°. In both the
   * stale number was the cached value from the previous session.
   *
   * Naming `toValue` here means a late-arriving target re-triggers the animation instead of being
   * ignored, whichever order the two params land in.
   */
  @Monitor('animKey', 'toValue')
  onTargetChanged(monitor: IMonitor): void {
    this.start();
  }

  private stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private start(): void {
    this.stop();
    if (!this.animationEnabled) {
      this.displayed = this.toValue;
      return;
    }

    const from: number = this.fromValue;
    const to: number = this.toValue;
    if (from === to) {
      this.displayed = to;
      return;
    }
    // `to` above is only used to size the animation. The tick below re-reads `this.toValue` every
    // frame and the final frame assigns it outright, so the number always LANDS on the current
    // target even if it changed after this call — belt and braces with the @Monitor above.

    // kt:101-104
    let duration: number = Math.abs(to - from) * 20;
    duration = Math.max(1000, Math.min(2000, duration));

    const frameMs: number = 16;
    const totalFrames: number = Math.max(1, Math.round(duration / frameMs));
    let frame: number = 0;
    this.displayed = from;

    this.timerId = setInterval(() => {
      frame++;
      // Live, not the `to` captured above: a target that changes mid-count is followed rather
      // than finished against a value that is no longer current.
      const target: number = this.toValue;
      const progress: number = Math.min(1, frame / totalFrames);
      this.displayed = progress >= 1 ? target : Math.round(from + (target - from) * progress);
      if (progress >= 1) {
        this.stop();
      }
    }, frameMs);
  }

  build() {
    Text(this.displayed.toString())
      .fontFamily(APP_FONT_FAMILY)
      .fontSize(this.textSize)
      .fontColor(this.textColor)
      .fontWeight(FontWeight.Bold)
      .maxLines(1)
  }
}
