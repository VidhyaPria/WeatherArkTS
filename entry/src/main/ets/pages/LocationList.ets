/*
 * Screen 2 as a PUSHED PAGE — the narrow-window arrangement.
 *
 * The screen itself lives in view/location/LocationListView.ets, because it is rendered in two
 * places: here, pushed over the weather page below 640 dp, and as the permanently-unfolded left
 * pane of `res/layout-w640dp/activity_main.xml` in landscape at 640 dp or more (pages/Index.ets).
 * This file is only the page shell and the rule that decides which of the two is in force.
 */

import { router } from '@kit.ArkUI';
import { LocationListView } from '../view/location/LocationListView';
import { addWindowSizeListener, removeWindowSizeListener } from '../common/SystemBars';
import { isTwoPane } from '../common/TwoPane';

@Entry
@ComponentV2
struct LocationList {
  /**
   * Bumped on every return to this page, which is how the list learns that the search screen has
   * added a city. `onPageShow` is an @Entry callback and cannot live in the component itself.
   */
  @Local private refreshTick: number = 0;

  /**
   * THE FOLD RULE — rotating into two-pane while this page is open has to pop it.
   *
   * Two-pane has no full-screen list: the layout puts the list in the drawer pane and
   * DrawerLayout.kt:53 unfolds that pane permanently, so the pane IS the list. Leaving this page up
   * would show a full-width list over a layout that already contains one, which Android cannot
   * produce. MainScreen refuses to PUSH this page while two-pane; this is the same rule applied to a
   * page that was already open when the window changed size under it.
   *
   * This is the ArkTS twin of the fold in Renderer::OnSurfaceChanged, where the NDK port shipped it
   * first — a rotation there left the list drawn full-width with a back arrow.
   *
   * A plain listener rather than a @Monitor: the window size is not this component's state, and
   * popping a page is an action rather than a re-render.
   */
  private readonly foldIfTwoPane: () => void = () => {
    if (isTwoPane()) {
      router.back();
    }
  };

  aboutToAppear(): void {
    addWindowSizeListener(this.foldIfTwoPane);
    // The window may already be wide — a cold start straight into landscape reports its size before
    // this page ever appears, so waiting only for a CHANGE would miss it.
    this.foldIfTwoPane();
  }

  aboutToDisappear(): void {
    removeWindowSizeListener(this.foldIfTwoPane);
  }

  onPageShow(): void {
    this.refreshTick++;
  }

  build() {
    Column() {
      LocationListView({ paneMode: false, refreshTick: this.refreshTick })
    }
    .width('100%')
    .height('100%')
  }
}
