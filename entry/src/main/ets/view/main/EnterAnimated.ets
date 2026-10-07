/*
 * The wrapper that plays a card's entrance the first time it scrolls into view.
 *
 * Android gives every main card this for free: they all extend AbstractMainViewHolder, and
 * HomeFragment's scroll listener calls checkEnterScreen on each one (kt:61-79), which fires the
 * staggered alpha/translate/scale animation exactly once per card. The port only had it on
 * HalfBlockCard, so the header, the trend cards and the nowcast/alert cards simply appeared.
 *
 * This is the equivalent of that itemView-level behaviour, so the animation lives in one place
 * rather than being copied into every card component.
 */

import { AppSettings } from '../../data/SettingsStore';
import {
  claimEnterTiming,
  decelerateCurve,
  ENTER_SCALE_FROM,
  ENTER_TRANSLATION_Y,
  EnterTiming,
  hasEntered,
  markEntered,
  overshootCurve
} from '../../common/EnterAnimation';

/**
 * How long to wait for onVisibleAreaChange before assuming it is not coming.
 *
 * Long enough that the framework's initial report always wins — the fallback must never pre-empt a
 * card that is genuinely below the fold — and short enough to be invisible on a page the user has
 * just swiped to.
 */
const FALLBACK_DELAY_MS: number = 100;

@ComponentV2
export struct EnterAnimated {
  /** Identity for the once-per-screen record — a card must not replay after a reorder. */
  @Param cardId: string = '';
  @BuilderParam content: () => void;

  @Local private enterOpacity: number = 0;
  @Local private enterOffsetY: number = ENTER_TRANSLATION_Y;
  @Local private enterScale: number = ENTER_SCALE_FROM;
  private started: boolean = false;
  /**
   * Whether onVisibleAreaChange has reported AT ALL — including a report of 0.
   *
   * This is the difference between "off screen, wait for the scroll" and "nothing is ever going to
   * tell us", and the two are indistinguishable from the animation state alone.
   */
  private sawVisibility: boolean = false;
  private fallbackTimer: number = -1;

  aboutToAppear(): void {
    /*
     * screen 3c's `list_animation_switch` (MainScreenSettingsScreen.kt:210-227).
     *
     * AbstractMainViewHolder.onBindView (kt:53-55) only sets `itemView.alpha = 0f` when the
     * setting is on, and checkEnterScreen (kt:71-75) calls onEnterScreen() directly instead of
     * running the animator. So off does not mean "play it instantly" — it means the card was never
     * hidden in the first place, which is what this settled start reproduces.
     */
    if (!AppSettings.instance.cardsFadeIn || hasEntered(this.cardId)) {
      this.started = true;
      markEntered(this.cardId);
      this.enterOpacity = 1;
      this.enterOffsetY = 0;
      this.enterScale = 1;
      return;
    }
    /*
     * A card CREATED ALREADY ON SCREEN never gets a visibility crossing, and so never appears.
     *
     * onVisibleAreaChange fires on a CHANGE of visible ratio. A card scrolled into view crosses 0
     * and animates; a card built into a page that is already the current one was visible from its
     * first frame, so there is no crossing to report and it sits at opacity 0 for ever. That is
     * what made a swiped-to page look empty while its footer — the one thing not wrapped in this
     * component — showed.
     *
     * The fallback fires only when NOTHING has been reported. A card below the fold does get a
     * callback, with a ratio of 0, so it takes the normal path and still waits for the scroll; the
     * staggered entrance is unchanged for every case that already worked.
     */
    this.fallbackTimer = setTimeout(() => {
      this.fallbackTimer = -1;
      if (!this.started && !this.sawVisibility) {
        this.start();
      }
    }, FALLBACK_DELAY_MS);
  }

  aboutToDisappear(): void {
    if (this.fallbackTimer >= 0) {
      clearTimeout(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
  }

  private start(): void {
    if (this.started) {
      return;
    }
    this.started = true;
    markEntered(this.cardId);
    const timing: EnterTiming = claimEnterTiming();
    animateTo({
      duration: timing.duration,
      delay: timing.delay,
      curve: overshootCurve(timing.overshootTension)
    }, () => {
      this.enterOffsetY = 0;
    });
    animateTo({
      duration: timing.duration,
      delay: timing.delay,
      curve: decelerateCurve()
    }, () => {
      this.enterOpacity = 1;
      this.enterScale = 1;
    });
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .opacity(this.enterOpacity)
    .translate({ y: this.enterOffsetY })
    .scale({ x: this.enterScale, y: this.enterScale })
    // checkEnterScreen's condition is "laid out and top < host height", i.e. any part of the card
    // is inside the viewport. A visible-area ratio above 0 is the same test.
    .onVisibleAreaChange([0.0, 1.0], (_isExpanding: boolean, currentRatio: number) => {
      // Recorded even at 0: it is what tells the fallback above that this card IS being tracked.
      this.sawVisibility = true;
      if (currentRatio > 0) {
        this.start();
      }
    })
  }
}
