/*
 * The two-pane rule — list beside the weather page instead of over it.
 *
 * Android expresses this with a resource qualifier plus a runtime check, and BOTH are required:
 *
 *   res/layout-w640dp/activity_main.xml   selects the two-pane layout at >= 640 dp of window width
 *   DrawerLayout.kt:53                    `unfold && isLandscape` is what actually unfolds the pane
 *
 * The width qualifier SELECTS the layout; the landscape test UNFOLDS it. A 640 dp portrait window —
 * a tablet held upright — gets the drawer but folded, which is the same single-pane behaviour this
 * port already has. So the condition here is landscape AND >= 640 dp, not either.
 *
 * The pane's width is `getTabletListAdaptiveWidth`: the window less the content's adaptive width,
 * clamped to the drawer's own bounds. This port targets a phone, so the 512 dp content cap applies
 * and the clamp is what decides in practice — 320 dp on the reference device.
 *
 * This is the ArkTS twin of Renderer::TwoPane() / Renderer::PaneWidth() in NativeApp, deliberately
 * kept identical so the two ports cannot drift on layout while they are being compared.
 *
 * OBSERVATION NOTE: these are plain functions, and a @Trace read inside a helper does NOT register
 * as a render dependency — the trap LocationList.ets documents for `rows()`. A component that must
 * re-lay-out on rotation has to read `WindowMetrics.instance.width`/`.height` DIRECTLY in its build;
 * once it does, these helpers are re-evaluated with it and are safe to call for the arithmetic.
 */

import { WindowMetrics } from './SystemBars';

/** The `w640dp` qualifier, in dp. */
const TWO_PANE_MIN_WIDTH: number = 640;
/** getTabletListAdaptiveWidth's cap on the content pane. */
const ADAPTIVE_MAX_WIDTH: number = 512;
/** MIN_DRAWER_WIDTH_DP / MAX_DRAWER_WIDTH_DP. */
const MIN_DRAWER_WIDTH: number = 280;
const MAX_DRAWER_WIDTH: number = 320;

export function isTwoPane(): boolean {
  const metrics: WindowMetrics = WindowMetrics.instance;
  if (metrics.width <= 0 || metrics.height <= 0) {
    return false;
  }
  return metrics.width > metrics.height && metrics.width >= TWO_PANE_MIN_WIDTH;
}

/**
 * `configuration.screenHeightDp > 400` (TimePickerPreference.kt:173, :213).
 *
 * Material's time picker collapses in a SHORT viewport: below this the dial and the keyboard/clock
 * toggle both disappear and the dialog is the text input alone. It is a height test rather than an
 * orientation one, which matters — a tall landscape window would keep the dial — but on this device
 * it comes to the same thing: 837 dp tall in portrait, 388 in landscape.
 *
 * Read `WindowMetrics.instance.height` DIRECTLY in a build() that must re-lay-out on rotation; see
 * the observation note at the top of this file.
 */
const TIME_PICKER_MIN_HEIGHT: number = 400;

/**
 * `Context.isLandscape` — the window wider than it is tall.
 *
 * Screen 4's Conditions page is the one place outside screens 1 and 2 that branches on it:
 * `WeatherCondition` sits BESIDE the temperature in landscape and BELOW it in portrait
 * (DetailsConditions.kt:625-633).
 *
 * Same observation rule as the rest of this file — read it inside the build() that must re-lay-out.
 */
export function isLandscape(): boolean {
  const metrics: WindowMetrics = WindowMetrics.instance;
  return metrics.width > 0 && metrics.height > 0 && metrics.width > metrics.height;
}

export function timePickerHasDial(): boolean {
  const height: number = WindowMetrics.instance.height;
  // A height of 0 is "not measured yet", and the dial is the portrait default.
  return height <= 0 || height > TIME_PICKER_MIN_HEIGHT;
}

/** The list pane's width in vp, or 0 when there is only one pane. */
export function paneWidth(): number {
  if (!isTwoPane()) {
    return 0;
  }
  const width: number = WindowMetrics.instance.width;
  const adaptive: number = Math.min(width, ADAPTIVE_MAX_WIDTH);
  let drawer: number = width - adaptive;
  drawer = Math.max(drawer, MIN_DRAWER_WIDTH);
  drawer = Math.min(drawer, MAX_DRAWER_WIDTH);
  return drawer;
}
