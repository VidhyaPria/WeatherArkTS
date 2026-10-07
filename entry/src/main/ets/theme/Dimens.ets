/*
 * Dimensions ported 1:1 from the Android app.
 *
 * Source: breezy-weather-6.2.1/app/src/main/res/values/dimens.xml
 * Android `dp` maps to ArkUI `vp`, Android `sp` maps to ArkUI `fp` (both 1:1).
 */

export class Dimens {
  // margin (dimens.xml:4-6)
  static readonly LARGE_MARGIN: number = 20;
  static readonly NORMAL_MARGIN: number = 16;
  static readonly SMALL_MARGIN: number = 8;

  // image (dimens.xml:18)
  static readonly MATERIAL_ICON_SIZE: number = 24;
  /*
   * Material 3 ListTokens container heights. Both alert layouts are a `ListItem`, whose height is
   * a FIXED token, not the sum of its content and padding — AlertViewHolder supplies no padding of
   * its own. Getting this wrong is what made the alert pill 72 vp instead of 56.
   *   ListItemOneLineContainerHeight = 56.dp — headline + leading (UpcomingAlerts)
   *   ListItemTwoLineContainerHeight = 72.dp — headline + supporting + leading (AlertList)
   * Horizontal padding is 16 dp (ListItemDefaults), which NORMAL_MARGIN already is.
   */
  static readonly LIST_ITEM_ONE_LINE_HEIGHT: number = 56;
  static readonly LIST_ITEM_TWO_LINE_HEIGHT: number = 72;

  // view (dimens.xml:31-36)
  static readonly TREND_ITEM_WIDTH: number = 67;
  static readonly TREND_ITEM_HEIGHT_MIN: number = 144;
  static readonly DAILY_TREND_ITEM_HEIGHT: number = 298;
  static readonly HOURLY_TREND_ITEM_HEIGHT: number = 206;
  static readonly ACTION_BAR_HEIGHT: number = 64;

  // text (dimens.xml:39-45)
  static readonly MAIN_TITLE_TEXT_SIZE: number = 140;
  static readonly LARGE_TITLE_TEXT_SIZE: number = 20;
  static readonly TITLE_TEXT_SIZE: number = 16;
  static readonly CONTENT_TEXT_SIZE: number = 14;
  static readonly SUBTITLE_TEXT_SIZE: number = 12;

  /**
   * Material 3 `ShapeAppearance.Material3.Corner.ExtraLarge`, used by both trend cards.
   * Source: container_main_daily_trend_card.xml:8, container_main_hourly_trend_card.xml:8
   */
  static readonly CARD_CORNER_RADIUS: number = 28;

  /**
   * The top padding a LargeTopAppBar's 88 vp title band needs so its headline lands where Material
   * puts it.
   *
   * `TwoRowsTopAppBar` places the title's BASELINE `LargeTitleBottomPadding = 28.dp` above the
   * bar's bottom edge — not its box, and not centred in anything. For a Roboto line box the
   * baseline sits ~0.79 of the way down, so a 28 sp headline (line box ~39 vp) wants a box top of
   * `152 - 28 - 0.79 * 39 = 93`, i.e. a CENTRE at ~112.6 vp below the bar's top.
   *
   * Centring in the band puts it at 108 — 5 vp high. A Text of height 88 with this top padding
   * centres its content at `108 + PADDING / 2`, which is 112.6 at 9.
   *
   * Both ports had a different wrong rule (this one, and centring in a 64 vp row at the bar's
   * bottom, which lands at 120) so they disagreed by 12 vp on EVERY large-app-bar screen. Measured
   * on the reference device Android's headline centre is ~113 vp. NativeApp applies the same rule
   * from the measured text height — see `LargeTitleTop` in render/Theme.h.
   */
  static readonly LARGE_TITLE_TOP_PADDING: number = 9;

  /*
   * The settings list's grouped cards (dimens.xml:21-23).
   *
   * A group is one rounded block: the OUTER corners of the first and last row carry the full
   * radius and every corner between them is 2 dp, which is what makes a group read as one card
   * rather than a stack (Material3Widgets.kt:204-225). The separators are the gaps BETWEEN
   * groups (16 dp) and between rows inside one (2 dp).
   */
  static readonly SETTINGS_CARD_CORNER_RADIUS: number = 28;
  static readonly SETTINGS_CARD_INNER_CORNER_RADIUS: number = 2;
  static readonly SETTINGS_SMALL_SEPARATOR: number = 2;
  static readonly SETTINGS_LARGE_SEPARATOR: number = 16;
  /** defaultCardListItemElevation (Material3Widgets.kt:187). */
  static readonly SETTINGS_CARD_ELEVATION: number = 2;

  /** AbstractMainCardViewHolder.kt:47-51 — card elevation is 2dp. */
  static readonly CARD_ELEVATION: number = 2;

  /**
   * A dialog's container width and corner.
   *
   * The width is a THEME value, not a per-dialog one: the alternate-calendar picker (a tall list)
   * and the animatable-icon dialog (one square icon) both measure 1039 px on the reference's
   * 1260 px screen, i.e. 319.7 dp, which is 320 dp to the nearest whole. The dialogs used to say
   * `.width('80%')`, which is 1008 px — 31 px narrow.
   */
  static readonly DIALOG_WIDTH: number = 320;
  static readonly DIALOG_CORNER_RADIUS: number = 28;
  /** MaterialAlertDialog's own content inset. */
  static readonly DIALOG_PADDING: number = 24;
}

/**
 * Constants belonging to the trend chart widgets.
 *
 * Sources:
 *   PolylineAndHistogramView.kt:513-524 (companion object)
 *   DailyTrendItemView.kt:252-256, HourlyTrendItemView.kt:188-192
 *   TrendRecyclerView.kt:191-196
 */
export class TrendDimens {
  // PolylineAndHistogramView
  static readonly CHART_MARGIN_TOP: number = 24;
  static readonly CHART_MARGIN_BOTTOM: number = 36;
  static readonly POLYLINE_SIZE: number = 5;
  static readonly POLYLINE_TEXT_SIZE: number = 14;
  static readonly HISTOGRAM_WIDTH: number = 4.5;
  static readonly HISTOGRAM_TEXT_SIZE: number = 12;
  static readonly CHART_LINE_SIZE: number = 1;
  static readonly CHART_TEXT_MARGIN: number = 2;
  static readonly SHADOW_ALPHA_FACTOR_LIGHT: number = 0.15;
  static readonly SHADOW_ALPHA_FACTOR_DARK: number = 0.3;

  // Daily/HourlyTrendItemView
  static readonly ITEM_ICON_SIZE: number = 32;
  static readonly ITEM_TEXT_MARGIN: number = 2;
  static readonly ITEM_ICON_MARGIN: number = 8;

  // TrendRecyclerView
  static readonly KEY_LINE_WIDTH: number = 1;
  static readonly KEY_LINE_TEXT_SIZE: number = 12;
  static readonly KEY_LINE_TEXT_MARGIN: number = 2;
  static readonly ITEM_MARGIN_BOTTOM: number = 16;
}
