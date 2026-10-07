/*
 * Edge-to-edge, and the status bar's foreground colour.
 *
 * `BreezyActivity.onCreate` calls `enableEdgeToEdge()` and then `window.setSystemBarStyle(...)`
 * (BreezyActivity.kt:39-41), so the weather background paints THROUGH the status bar and the clock
 * and signal icons sit on top of it — which is why the Android screenshots show the orange sky
 * behind the time and the ports showed a white strip. HarmonyOS defaults the other way: the window
 * is laid out inside the avoid areas and the bar keeps the system's own background.
 *
 * `setSystemBarStyle` also flips the bar's FOREGROUND with the theme
 * (DisplayExtensions.kt:214-241, driven from MainActivity.updateSystemBarStyle), so a light sky
 * gets dark icons and a night sky gets light ones. That is a per-location, per-refresh decision
 * here, so the screen calls `applyStatusBarStyle` whenever its background lightness changes.
 *
 * The top inset the layout loses by going full screen is published through AppStorage, because the
 * toolbar still has to start below the status bar — Android gets the same value from
 * `doOnApplyWindowInsets`.
 */

import { window } from '@kit.ArkUI';

/**
 * The insets, in vp, as observable state.
 *
 * @ObservedV2/@Trace rather than AppStorage because the screen is @ComponentV2 — @StorageProp is
 * V1-only — and because a rotation has to re-run the layout that reads them.
 */
@ObservedV2
export class SystemInsets {
  static readonly instance: SystemInsets = new SystemInsets();
  /** Status bar height; 0 until the window has reported its avoid area. */
  @Trace top: number = 0;
  /** Navigation bar height — the footer keeps clear of it, as Android's `insets.bottom` does. */
  @Trace bottom: number = 0;
  /**
   * The side insets, which only become non-zero in LANDSCAPE — that is where the cutout and the
   * gesture bar move to. Android asks for them explicitly: SearchActivity.kt:130-132 gives its
   * BottomAppBar `WindowInsets.safeDrawing.only(Horizontal + Bottom)`, and the Material3Scaffold
   * passes the same horizontal padding down to the content. Without them a rotated screen puts its
   * text under the cutout.
   */
  @Trace left: number = 0;
  @Trace right: number = 0;
}

/**
 * The window's own size, in vp — what decides between one pane and two.
 *
 * Android reads the same thing through a resource qualifier: `res/layout-w640dp/activity_main.xml`
 * is selected when the window is at least 640 dp wide. There is no qualifier mechanism here, so the
 * width is observed and the rule applied in code; see common/TwoPane.ets.
 */
@ObservedV2
export class WindowMetrics {
  static readonly instance: WindowMetrics = new WindowMetrics();
  @Trace width: number = 0;
  @Trace height: number = 0;
}

/**
 * Plain callbacks for a size change, alongside the observable class above.
 *
 * Both exist because they answer different questions. A component that LAYS OUT differently reads
 * `WindowMetrics` directly in its build and re-renders; a component that has to take an ACTION on a
 * rotation — the location list page popping itself when the layout becomes two-pane — cannot express
 * that as a render, and a @Monitor cannot watch a plain field. This is the explicit way to say it.
 */
type WindowSizeListener = () => void;

const sizeListeners: WindowSizeListener[] = [];

export function addWindowSizeListener(listener: WindowSizeListener): void {
  sizeListeners.push(listener);
}

export function removeWindowSizeListener(listener: WindowSizeListener): void {
  const index: number = sizeListeners.indexOf(listener);
  if (index >= 0) {
    sizeListeners.splice(index, 1);
  }
}

let mainWindow: window.Window | null = null;
let lastLightStatusBar: boolean | null = null;

function publishInsets(win: window.Window): void {
  try {
    const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    SystemInsets.instance.top = px2vp(area.topRect.height);
    SystemInsets.instance.bottom = px2vp(area.bottomRect.height);
    // The side rects report a WIDTH, not a height — in landscape this is where the bar has gone.
    SystemInsets.instance.left = px2vp(area.leftRect.width);
    SystemInsets.instance.right = px2vp(area.rightRect.width);
  } catch (error) {
    console.error('avoid area unavailable: ' + (error as Error).message);
  }
  try {
    const rect = win.getWindowProperties().windowRect;
    WindowMetrics.instance.width = px2vp(rect.width);
    WindowMetrics.instance.height = px2vp(rect.height);
  } catch (error) {
    console.error('window rect unavailable: ' + (error as Error).message);
  }
  for (let i = 0; i < sizeListeners.length; i++) {
    sizeListeners[i]();
  }
}

/**
 * Lays the window out under the system bars and makes them transparent. Call once, from
 * onWindowStageCreate, before the content is loaded.
 */
export function enableEdgeToEdge(win: window.Window): void {
  mainWindow = win;
  try {
    win.setWindowLayoutFullScreen(true);
  } catch (error) {
    console.error('setWindowLayoutFullScreen failed: ' + (error as Error).message);
  }
  try {
    // Transparent, as `statusBarColor = Color.TRANSPARENT` — the page's own background shows.
    win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000'
    });
  } catch (error) {
    console.error('setWindowSystemBarProperties failed: ' + (error as Error).message);
  }
  publishInsets(win);
  // A rotation changes both insets, and the avoid area is only correct once the window has resized.
  try {
    win.on('windowSizeChange', () => publishInsets(win));
    win.on('avoidAreaChange', () => publishInsets(win));
  } catch (error) {
    console.error('inset listener failed: ' + (error as Error).message);
  }
}

/**
 * `isAppearanceLightStatusBars` — note the Kotlin's own comment at DisplayExtensions.kt:236:
 * "Contrary to the documentation FALSE applies a light foreground color and TRUE a dark foreground
 * color". So a LIGHT background wants DARK icons.
 */
export function applyStatusBarStyle(lightBackground: boolean): void {
  if (mainWindow === null || lastLightStatusBar === lightBackground) {
    return;
  }
  lastLightStatusBar = lightBackground;
  try {
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: lightBackground ? '#000000' : '#FFFFFF',
      navigationBarContentColor: lightBackground ? '#000000' : '#FFFFFF'
    });
  } catch (error) {
    console.error('status bar style failed: ' + (error as Error).message);
  }
}
