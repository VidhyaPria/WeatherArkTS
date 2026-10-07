/*
 * Entry page — hosts the main weather screen (step 1 of the migration).
 *
 * Also registers Roboto, the typeface the Android app renders in. ArkUI's default is HarmonyOS
 * Sans, which is why the port's text read differently at identical sizes and weights.
 *
 * The face is `Roboto-Regular.ttf` from the reference device's /system/fonts — and despite the
 * name that is the 2.3 MB VARIABLE font, carrying a `wght` axis from 100 to 900. It replaces the
 * 300 KB `RobotoStatic-Regular.ttf` this port used to bundle, which was chosen to keep the HAP
 * small for the memory comparison and turned out to cost real fidelity: a static Regular cut has
 * no bold face, so every `weight 500` and `weight 700` run on the screen silently fell back to
 * 400. The header temperature is the most obvious — container_main_header.xml:82-83 asks for
 * `textStyle="bold"` AND `textFontWeight="700"`, and the port drew it in Regular.
 *
 * Android renders its bold from this same file, so this is the faithful choice rather than a
 * heavier one. It costs both ports 2 MB equally, which leaves the ArkUI-vs-NDK comparison intact.
 *
 * ArkUI does not cascade text styles, so `Text` components take .fontFamily(APP_FONT_FAMILY)
 * individually; see common/Typography.ets.
 */

import { font } from '@kit.ArkUI';
import { APP_FONT_FAMILY } from '../common/Typography';
import { MainScreen } from '../view/main/MainScreen';
import { LocationListView } from '../view/location/LocationListView';
import { addWindowSizeListener } from '../common/SystemBars';
import { isTwoPane, paneWidth } from '../common/TwoPane';

@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    addWindowSizeListener(this.syncPanes);
    // The window may already be landscape — a cold start into it reports its size before this.
    this.syncPanes();
    try {
      /*
       * THREE FACES under one family, not one variable font — and that is a performance fix, not a
       * cosmetic one.
       *
       * The port used to bundle the 2.3 MB VARIABLE Roboto (a `wght` axis). Asking a variable font
       * for a non-default weight makes the engine INSTANCE it, and it does that per Text node,
       * every time one is built — measured at ~6 ms per node. A settings row has a weight-500
       * title over a weight-400 summary, so each row paid it: 13.8 ms to build, against 7.7 ms
       * with static faces, and `load page: pages/Settings` 173.5 ms against 108.7 ms.
       *
       * These three are INSTANCED FROM THAT SAME VARIABLE FONT (fontTools varLib.instancer at
       * wght 400/500/700, wdth 100, ital 0), so the outlines are identical to what the variable
       * font produced at those weights — this changes when the work happens, not what is drawn.
       * Each carries the family name "Roboto" with its own subfamily and a matching
       * OS/2.usWeightClass, which is what lets the shaper pick a face by weight instead of
       * interpolating one.
       *
       * They total ~1.09 MB against 2.37 MB, so the HAP gets smaller too.
       */
      font.registerFont({
        familyName: APP_FONT_FAMILY,
        familySrc: $rawfile('Roboto-Regular.ttf')
      });
      font.registerFont({
        familyName: APP_FONT_FAMILY,
        familySrc: $rawfile('Roboto-Medium.ttf')
      });
      font.registerFont({
        familyName: APP_FONT_FAMILY,
        familySrc: $rawfile('Roboto-Bold.ttf')
      });
    } catch (error) {
      // A failed registration just falls back to HarmonyOS Sans; it must not stop the screen.
      console.error('Roboto registration failed: ' + (error as Error).message);
    }
  }

  /**
   * Bumped every time this page comes back to the front, which is how the main screen learns that
   * the location list has been and gone.
   *
   * `onPageShow` is an @Entry lifecycle callback, so it can only live here — MainScreen is a child
   * struct and never receives it. Watching the shared LocationRevision from MainScreen was tried
   * first and does not work: while the list screen is pushed on top, MainScreen's page is not
   * rendering, and a @Monitor on it does not run. The selection was correctly recorded in the
   * model and the Swiper simply never moved.
   */
  @Local private pageShows: number = 0;

  /**
   * False while another page (the location list, the search screen) is pushed on top of this one.
   *
   * `router.pushUrl` does NOT unmount this page — `aboutToDisappear` never runs, and the
   * WeatherBackground's displaySync loop kept animating the whole time screen 2 covered it. Its two
   * existing stop conditions do not cover this: `scrollRate >= 1` is about the CARDS covering the
   * background within this page, and `animate` was never driven by anything.
   *
   * Measured on screen 2, gesture-windowed at 120 Hz: per-frame UI work fell from p90 4.44 ms to
   * 1.88 ms (max 13.44 → 6.83 ms) once the loop was stopped. It was drawing 30 fps of particles
   * under a page that covers them completely, which also holds the little cluster off its idle
   * clock. The NDK port already gives screen 2 no frames at all, so leaving this would have made
   * the memory comparison measure the asymmetry rather than the two runtimes.
   */
  @Local private pageVisible: boolean = true;

  /**
   * The layout decision, held as STATE rather than read from the window on each build.
   *
   * Reading `WindowMetrics` directly in the build was tried first and does not work here, for the
   * same reason this file already gives for @Monitor: while the location list is pushed on top,
   * this page is not rendering. A rotation that happens then changes the @Trace fields with nothing
   * observing them, and the page comes back with its old tree — measured on device as a landscape
   * window still laid out in one full-width pane.
   *
   * Assigning a @Local is observable with no ambiguity, and it is refreshed from BOTH edges: the
   * window-size listener for a rotation while this page is live, and `onPageShow` for one that
   * happened while it was covered.
   */
  @Local private twoPane: boolean = false;
  /** The pane's width in vp; only meaningful while `twoPane` is true. */
  @Local private paneVp: number = 0;

  private readonly syncPanes: () => void = () => {
    this.twoPane = isTwoPane();
    this.paneVp = paneWidth();
  };

  /**
   * Tells the pane to re-read the model. SEPARATE from `pageShows`, which drives MainScreen.
   *
   * The pane can be built before the location store has finished loading — a cold start straight
   * into landscape does exactly that — and it then shows `buildLocations()`'s three-city seed with
   * no current-position row, which is what put a my-location FAB back on a list that already had
   * one. Measured on device: `n=3 has=false pane=true rows=3` while storage held 13.
   *
   * Nothing about that corrects itself, because `viewModel.getLocations()` is a plain array and
   * `hasCurrentPosition()` is a helper — neither is observable. MainScreen owns the load, so it
   * announces it and this counter carries the news.
   *
   * It is its own counter rather than `pageShows` because that one feeds MainScreen's
   * @Monitor('pageShows'), which bumps `dataVersion`, which is what fires the event — a loop.
   */
  @Local private paneTick: number = 0;

  /**
   * True while the two-pane list is being scrolled; holds the weather scene still for the gesture.
   *
   * Set only from the pane — in portrait the list is a pushed page and `pageVisible` already stops
   * the background loop.
   */
  @Local private paneScrolling: boolean = false;

  onPageShow(): void {
    this.pageShows++;
    this.pageVisible = true;
    // A city added on the search screen lands while this page is covered; the pane has to re-read.
    this.paneTick++;
    // A rotation while the list covered this page leaves the decision stale; this is where it is
    // caught, because the listener above fired into a page that was not rendering.
    this.syncPanes();
  }

  onPageHide(): void {
    this.pageVisible = false;
  }

  /**
   * A selection made in the pane has no navigation to announce it, so this stands in for the page
   * return that MainScreen's @Monitor('pageShows') normally watches for.
   *
   * A STABLE field, not an inline closure: a fresh arrow function on every build changes the child's
   * @Event parameter identity, which makes the child update when nothing about it actually changed.
   */
  private readonly onPaneSelected: () => void = () => {
    this.pageShows++;
  };

  /**
   * MainScreen owns the load and the refresh; the pane is beside it rather than under it, so it is
   * told rather than left to notice. Bumps NOTHING when there is no pane to tell.
   */
  private readonly onMainDataLoaded: () => void = () => {
    if (this.twoPane) {
      this.paneTick++;
    }
  };

  /** The pane's list started or stopped moving; the scene follows. */
  private readonly onPaneScrollActive: (active: boolean) => void = (active: boolean) => {
    this.paneScrolling = active;
  };

  build() {
    /*
     * ONE MainScreen, ALWAYS, with the pane inserted beside it.
     *
     * This was an if/else with a MainScreen in each branch, and that is a trap: flipping `twoPane`
     * on a rotation put the two call sites on different branches, so ArkUI destroyed the entire
     * weather subtree and built a new one. Every TrendChartCanvas went with it, and tearing those
     * down is what runs `clearBindingInternal` over the V2 binding registry — the app froze for six
     * seconds at 664 MB doing exactly that (appfreeze THREAD_BLOCK_6S, 2026-08-08 18:25), and
     * rotating landscape -> portrait left it stuck.
     *
     * With a single instance, a rotation only inserts or removes the pane; the weather page is
     * re-laid-out, not rebuilt.
     *
     * `res/layout-w640dp/activity_main.xml` + DrawerLayout.kt:53 — see common/TwoPane.ets.
     */
    Row() {
      // The drawer pane, permanently unfolded. It comes FIRST because it is the start edge, and it
      // is given an explicit width — the weather page takes what is left.
      if (this.twoPane) {
        LocationListView({
          paneMode: true,
          refreshTick: this.paneTick,
          onSelected: this.onPaneSelected,
          onScrollActive: this.onPaneScrollActive
        })
          .width(this.paneVp)
          .height('100%')
      }

      MainScreen({
        pageShows: this.pageShows,
        pageVisible: this.pageVisible,
        // Held still for the length of a pane-list gesture; see MainScreen.backgroundAnimates.
        backgroundAnimates: !this.paneScrolling,
        onDataLoaded: this.onMainDataLoaded
      })
        .layoutWeight(1)
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
