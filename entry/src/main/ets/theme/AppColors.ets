/*
 * Colours ported 1:1 from the Android app. No value here is invented.
 *
 * Sources:
 *   res/values/colors.xml            (light)
 *   res/values-night/colors.xml      (dark)
 *   res/values/styles.xml:4-57       (BreezyWeatherTheme attribute -> colour bindings)
 *   ui-weather-view/.../implementor/*.kt (per-weather-kind theme colours)
 */

import { WeatherKind } from '../model/WeatherKind';

/** One resolved colour pair: light theme value and dark theme value. */
export class ColorPair {
  readonly light: string;
  readonly dark: string;

  constructor(light: string, dark: string) {
    this.light = light;
    this.dark = dark;
  }

  resolve(isDark: boolean): string {
    return isDark ? this.dark : this.light;
  }
}

export class AppColors {
  /*
   * Material 3 tokens — the MATERIAL YOU palette, not colors.xml's static one.
   *
   * res/values-v31/colors.xml and res/values-night-v31/colors.xml rebind every md_theme_* colour
   * to an @android:color/system_* resource on SDK >= 31. The reference phone is Android 12
   * (SDK 31), so those buckets win and colors.xml's #205DAF family NEVER applies there — it is the
   * pre-v31 fallback for Android 11 and below. Both ports used to carry that fallback, which is
   * why every screen read blue against the reference's teal.
   *
   * The values below are the device's own palette, extracted exactly rather than sampled:
   *   adb pull /system/framework/framework-res.apk && aapt2 dump resources
   * `settings get secure theme_customization_overlay_packages` is null, so no wallpaper overlay is
   * applied and these are the static framework defaults — stable across reboots and wallpapers.
   * Five were independently confirmed by sampling the reference's pixels: accent1_600 on the clock
   * digits, accent1_700 and accent2_500 on its hands, neutral1_10 and neutral1_900 on the tiles.
   *
   * Light comes from values-v31, dark from values-night-v31; the resource each maps to is named.
   */
  /** accent1_600 / accent1_200 */
  static readonly PRIMARY = new ColorPair('#FF00668B', '#FF76D1FF');
  /** accent1_0 / accent1_800 */
  static readonly ON_PRIMARY = new ColorPair('#FFFFFFFF', '#FF003549');
  /** neutral1_0 / neutral1_1000 */
  static readonly BACKGROUND = new ColorPair('#FFFFFFFF', '#FF000000');
  /** neutral1_1000 / neutral1_0 */
  static readonly ON_BACKGROUND = new ColorPair('#FF000000', '#FFFFFFFF');
  /** neutral1_10 / neutral1_900 */
  static readonly SURFACE = new ColorPair('#FFFCFCFF', '#FF191C1E');
  /** neutral1_900 / neutral1_100 */
  static readonly ON_SURFACE = new ColorPair('#FF191C1E', '#FFE1E3E5');
  /** neutral2_100 / neutral2_700 */
  static readonly SURFACE_VARIANT = new ColorPair('#FFDCE3E9', '#FF40484D');
  /** neutral2_700 / neutral2_200 */
  static readonly ON_SURFACE_VARIANT = new ColorPair('#FF40484D', '#FFC0C7CD');
  /** colorOutline — note the deliberately low alpha in both themes. */
  static readonly OUTLINE = new ColorPair('#10000000', '#10FFFFFF');
  /**
   * The Compose `outline` role, which is NOT the XML `colorOutline` above.
   *
   * `md_theme_outline` is #10000000 / #10ffffff (colors.xml:128, values-night:46) — 6 % alpha,
   * because the View screens use it as a TRACK colour behind the air-quality and pressure bars
   * (container_main_air_quality.xml:64). Screen 2 is Compose, and BreezyWeatherTheme
   * (Theme.kt:30-40) overrides only primary/secondary/tertiary, so `outline` there is whatever
   * `lightColorScheme()`/`darkColorScheme()` leave it: the Material 3 baseline. Borrowing the XML
   * value would draw the empty state's outlined button with an all-but-invisible border.
   */
  static readonly COMPOSE_OUTLINE = new ColorPair('#FF70777C', '#FF8A9297');
  /**
   * The Compose `outlineVariant` role — what `HorizontalDivider` draws with by default, and the
   * only place either port needs it (the alert screen's rules between description, instruction and
   * source). Same reasoning as COMPOSE_OUTLINE: BreezyWeatherTheme leaves it at the Material 3
   * baseline, so it is `lightColorScheme()`/`darkColorScheme()`'s value, not the XML colorOutline.
   */
  static readonly COMPOSE_OUTLINE_VARIANT = new ColorPair('#FFC0C7CD', '#FF40484D');
  /**
   * colorSurfaceInverse = md_theme_inverseSurface (styles.xml:29). Header/toolbar text sits on this.
   * neutral1_900 / neutral1_100.
   */
  static readonly SURFACE_INVERSE = new ColorPair('#FF191C1E', '#FFE1E3E5');
  /**
   * colorOnSurfaceInverse = md_theme_inverseOnSurface (styles.xml:28, colors.xml:129 /
   * values-night:47). The snackbar's message colour — it is the only thing in this port that reads
   * against SURFACE_INVERSE.
   */
  static readonly ON_SURFACE_INVERSE = new ColorPair('#FFE1E3E5', '#FF191C1E');

  /**
   * The settings list card — `getWidgetSurfaceColor(2.dp, surface)` (Material3Widgets.kt:68-80,
   * :227), NOT plain `surface`.
   *
   * Material 3 tints an elevated surface rather than lightening it: the colour is `surfaceTint`
   * (which defaults to `primary`) laid over `surface` at
   *   alpha = ((4.5 * ln(elevation + 1)) + 2) / 100
   * which at the cards' 2 dp is 0.069438. Computed from this port's own PRIMARY and SURFACE, so it
   * stays consistent with them — recomputed when the palette moved to Material You:
   *   light  #00668B over #FCFCFF -> #EAF2F7
   *   dark   #76D1FF over #191C1E -> #1F292E
   * That faint cast is why a plain white card reads as wrong beside it.
   */
  static readonly SETTINGS_CARD = new ColorPair('#FFEAF2F7', '#FF1F292E');

  /**
   * A dialog's container. NOT `SETTINGS_CARD` — the three dialogs used to borrow that, and it is
   * measurably wrong: a dialog is `surfaceContainerHigh`, which is a different role from a 2 dp
   * elevated settings card.
   *
   * There are TWO of them, because Breezy raises dialogs through two different stacks and they do
   * NOT resolve to the same colour:
   *
   *   DIALOG_SURFACE       Compose `AlertDialog` — every list/edit/time preference, and the
   *                        alternate-calendar picker. Compose derives surfaceContainerHigh from the
   *                        DYNAMIC neutral palette.
   *   ALERT_DIALOG_SURFACE View `MaterialAlertDialogBuilder` — the three icon-preview dialogs.
   *                        styles.xml overrides no surfaceContainer* attribute, so these stay at
   *                        the Material 3 BASELINE, which is the faintly purple #ECE6F0.
   *
   * All four values were sampled off the reference in both modes, not derived:
   *   Compose  light #E2E9F0  dark #242B30   (alternate-calendar dialog)
   *   View     light #ECE6F0  dark #2B2930   (CLEAR_DAY animatable-icon dialog)
   */
  static readonly DIALOG_SURFACE = new ColorPair('#FFE2E9F0', '#FF242B30');
  static readonly ALERT_DIALOG_SURFACE = new ColorPair('#FFECE6F0', '#FF2B2930');

  /**
   * The three manage screens' toolbar — `getWidgetSurfaceColor(6f, colorPrimary, colorSurface)`
   * (CardDisplayManageActivity.kt:107-113), the same overlay as SETTINGS_CARD but at 6 dp:
   *   alpha = ((4.5 * ln(6 + 1)) + 2) / 100 = 0.10757
   *   light  #00668B over #FCFCFF -> #E1ECF3
   *   dark   #76D1FF over #191C1E -> #232F36
   *
   * CORRECTION. This comment used to say these View-based activities "take the app's own palette
   * rather than Material You". That was wrong, and it is what kept both ports blue: values-v31
   * rebinds `md_theme_primary` ITSELF, so the XML theme is every bit as wallpaper-derived as the
   * Compose one. There is no screen in the app that uses colors.xml's static palette on SDK >= 31.
   */
  static readonly ELEVATED_SURFACE_6 = new ColorPair('#FFE1ECF3', '#FF232F36');

  /*
   * Text tokens. styles.xml:51-53 bind these attributes:
   *   colorTitleText   -> colorTextTitle
   *   colorBodyText    -> colorTextContent
   *   colorCaptionText -> colorTextSubtitle
   * colors.xml:81-83 / values-night/colors.xml:6-8
   */
  static readonly TITLE_TEXT = new ColorPair('#FF000000', '#FFFFFFFF');
  static readonly BODY_TEXT = new ColorPair('#FF666666', '#FF999999');
  /** dark value resolves through colorTextLight2nd (colors.xml:79). */
  static readonly CAPTION_TEXT = new ColorPair('#FFB2B2B2', '#FF999999');

  /** colors.xml:76-77 — used for the trend list text colour (DailyViewHolder.kt:142-151). */
  static readonly TEXT_GREY = '#FF4D4D4D';
  static readonly TEXT_GREY_2ND = '#FFB2B2B2';

  /**
   * The main screen's cards. This used to read `colorMainCardBackground` (colors.xml:85, #FDFCFF),
   * but that attribute is DEAD: it is declared in attrs.xml, given a value in colors.xml and bound
   * in styles.xml:54, and then referenced by no layout in the app. What the cards actually take is
   * `styles.xml:101` — `<item name="cardBackgroundColor">?attr/colorSurface</item>` — which is why
   * the reference's tiles measure #FCFCFF (neutral1_10) and not #FDFCFF.
   */
  static readonly MAIN_CARD_BACKGROUND = AppColors.SURFACE;

  /**
   * The alert card is tinted, not a normal white card: `android:backgroundTint="@color/alert_background"`
   * on container_main_alert.xml's MaterialCardView. colors.xml / values-night/colors.xml.
   */
  static readonly ALERT_BACKGROUND = new ColorPair('#FFFFB4AB', '#FF410002');
  /** colors.xml `alert_text` — the severity accent, not used for the card's own label. */
  /**
   * alert_text is the background's companion, NOT the card's text colour. AlertViewHolder tints
   * the headline and the warning icon with MaterialTheme.colorScheme.onSurface and the dates with
   * onSurfaceVariant, which is why Android's pill reads near-white on maroon.
   */
  static readonly ALERT_TEXT = new ColorPair('#FFBA1A1A', '#FFFF897D');

  /** colorPrecipitationProbability = md_theme_primary (colors.xml:86) */
  static readonly PRECIPITATION_PROBABILITY = AppColors.PRIMARY;

  /**
   * colorTertiaryContainer — tints the humidity waves and the visibility blob
   * (humidity_percent_*.xml, visibility_shape.xml use ?attr/colorTertiaryContainer).
   * colors.xml:116 / values-night/colors.xml:34
   */
  /** accent3_100 / accent3_700 */
  static readonly TERTIARY_CONTAINER = new ColorPair('#FFE6DEFF', '#FF484264');
  /** accent3_900 / accent3_100 */
  static readonly ON_TERTIARY_CONTAINER = new ColorPair('#FF1D1736', '#FFE6DEFF');
  /*
   * colorTertiary / colorOnTertiary — the humidity block's dew-point badge.
   * humidity_dew_point_circle.xml is an oval solid-filled with ?attr/colorTertiary, and
   * container_main_humidity.xml draws the value centred on it in ?attr/colorOnTertiary.
   */
  /** accent3_600 / accent3_200 */
  static readonly TERTIARY = new ColorPair('#FF605A7C', '#FFCAC1EA');
  /** accent3_0 / accent3_800 */
  static readonly ON_TERTIARY = new ColorPair('#FFFFFFFF', '#FF322C4C');
  /** sys_widget_background — the wind block's blob (colors.xml:136 / values-night:54). */
  /*
   * The container roles the location list uses (LocationHolder.kt:74-95). A row is
   * primaryContainer when it is the selected location, alert_background when it has active
   * warnings, and the elevated surface otherwise; the two swipe backgrounds behind it are
   * errorContainer for delete and secondary/tertiaryContainer for settings.
   */
  /** accent1_100 / accent1_700 */
  static readonly PRIMARY_CONTAINER = new ColorPair('#FFC1E8FF', '#FF004C69');
  /** accent1_900 / accent1_100 */
  static readonly ON_PRIMARY_CONTAINER = new ColorPair('#FF001E2C', '#FFC1E8FF');
  /** colorScheme.error — the outlined field's border and helper text when a value fails its regex. */
  static readonly ERROR = new ColorPair('#FFB3261E', '#FFF2B8B5');
  static readonly ERROR_CONTAINER = new ColorPair('#FFF9DEDC', '#FF8C1D18');
  static readonly ON_ERROR_CONTAINER = new ColorPair('#FF410E0B', '#FFF9DEDC');
  /** accent2_100 / accent2_700 */
  static readonly SECONDARY_CONTAINER = new ColorPair('#FFD1E5F4', '#FF374955');
  /** accent2_900 / accent2_100 */
  static readonly ON_SECONDARY_CONTAINER = new ColorPair('#FF091E28', '#FFD1E5F4');

  static readonly SYS_WIDGET_BACKGROUND = new ColorPair('#FFDCE2F9', '#FF404659');

  /**
   * Air-quality level colours (colors.xml:21-26). The level is
   * aqiThresholds.indexOfLast { aqi >= it } over [0, 20, 50, 100, 150, 250]
   * (PollutantIndex.kt), and the colour is colorLevel_(level + 1).
   */
  static readonly AQI_THRESHOLDS: number[] = [0, 20, 50, 100, 150, 250];
  static readonly LEVEL_COLORS: string[] =
    ['#FF72D572', '#FFFFCA28', '#FFFFA726', '#FFE52F35', '#FF99004C', '#FF7E0023'];

  /** R.color.sunshine (colors.xml:70) — the daily Sunshine tab's bars. */
  static readonly SUNSHINE = '#FFFDBC4C';

  /** Indicator dots — HomeFragment.kt:212-215: white, and white at 50% alpha. */
  static readonly INDICATOR_CURRENT = '#FFFFFFFF';
  static readonly INDICATOR_OTHER = '#80FFFFFF';

  /**
   * The search screen's surface and the divider under its input field.
   *
   * DERIVED, not extracted — and the only value in this file that is. SearchActivity.kt:163-168
   * asks for `SearchBarDefaults.colors().containerColor` at `SearchBarDefaults.TonalElevation`, and
   * `HorizontalDivider(color = SearchBarDefaults.colors().dividerColor)` at :190. Those constants
   * live in `androidx.compose.material3:1.5.0-alpha21`, which is a Maven dependency and is NOT
   * vendored under breezy-weather-6.2.1 — there is no source file in the reference tree to read
   * them from, so CLAUDE.md's "extract the exact value" has nothing to point at here.
   *
   * Rather than invent a hex value, both are built out of values the app itself defines:
   *
   *   surface   `elevatedSurface` at 2 dp — the app's own getWidgetSurfaceColor overlay at
   *             `defaultCardListItemElevation = 2.dp` (Material3Widgets.kt:187), the one elevation
   *             the app names for a primary-tinted surface, already used for the location rows.
   *   divider   colorOutline (md_theme_outline), the role a Material divider takes.
   *
   * Sampling the running Android build was the other option and was rejected on purpose: its
   * Compose screens run under `dynamicLightColorScheme` (Theme.kt:50-52), so those pixels are the
   * reference PHONE's Material You palette, not the app's. The rest of this port is the static
   * md_theme_* palette, and mixing the two would make this one screen match no other.
   */
  static readonly SEARCH_DIVIDER = AppColors.OUTLINE;
}

/**
 * Beaufort number for a speed in m/s.
 *
 * SpeedUnit.BEAUFORT_SCALE.convertFromReference (SpeedUnit.kt:167-182) buckets the speed in
 * cm/s against WIND_SPEED_1..12 (kt:311-322), so the thresholds below are those constants
 * divided by 100.
 */
export function beaufortLevel(metresPerSecond: number): number {
  const thresholds: number[] = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7];
  let level: number = 0;
  for (let i = 0; i < thresholds.length; i++) {
    if (metresPerSecond >= thresholds[i]) {
      level = i + 1;
    }
  }
  return level;
}

/** Wind.getColor (Wind.kt:39-51) — colorLevel_1..6 by Beaufort band. */
export function windColor(metresPerSecond: number | null): string | null {
  if (metresPerSecond === null) {
    return null;
  }
  const bf: number = beaufortLevel(metresPerSecond);
  if (bf < 4) {
    return AppColors.LEVEL_COLORS[0];
  }
  if (bf < 6) {
    return AppColors.LEVEL_COLORS[1];
  }
  if (bf < 8) {
    return AppColors.LEVEL_COLORS[2];
  }
  if (bf < 10) {
    return AppColors.LEVEL_COLORS[3];
  }
  if (bf < 12) {
    return AppColors.LEVEL_COLORS[4];
  }
  return AppColors.LEVEL_COLORS[5];
}

/**
 * UV.getUVColor (UV.kt:68-78) — colorLevel_1..5 against UV_INDEX_LOW/MIDDLE/HIGH/EXCESSIVE
 * (domain UV.kt:33-36 = 3 / 6 / 8 / 11).
 */
export function uvColor(index: number | null): string | null {
  if (index === null) {
    return null;
  }
  if (index < 3) {
    return AppColors.LEVEL_COLORS[0];
  }
  if (index < 6) {
    return AppColors.LEVEL_COLORS[1];
  }
  if (index < 8) {
    return AppColors.LEVEL_COLORS[2];
  }
  if (index < 11) {
    return AppColors.LEVEL_COLORS[3];
  }
  return AppColors.LEVEL_COLORS[4];
}

/**
 * Precipitation.getHalfDayPrecipitationColor (Precipitation.kt:27-60) against
 * PRECIPITATION_HALF_DAY_LIGHT/MEDIUM/HEAVY/RAINSTORM (domain Precipitation.kt:36-39).
 */
export function halfDayPrecipitationColor(millimetres: number | null): string | null {
  if (millimetres === null) {
    return null;
  }
  if (millimetres <= 7.75) {
    return AppColors.LEVEL_COLORS[0];
  }
  if (millimetres <= 32.25) {
    return AppColors.LEVEL_COLORS[1];
  }
  if (millimetres <= 57.75) {
    return AppColors.LEVEL_COLORS[2];
  }
  if (millimetres <= 102.25) {
    return AppColors.LEVEL_COLORS[3];
  }
  return AppColors.LEVEL_COLORS[4];
}

/**
 * Ratio.getCloudCoverColor (UnitExtensions.kt:413-420) against CLOUD_COVER_FEW / CLOUD_COVER_SCT
 * (kt:408-409 = 37.5 / 62.5 percent, i.e. 3 and 5 okta).
 */
export function cloudCoverColor(percent: number | null): string | null {
  if (percent === null) {
    return null;
  }
  if (percent < 37.5) {
    return AppColors.LEVEL_COLORS[0];
  }
  if (percent <= 62.5) {
    return AppColors.LEVEL_COLORS[1];
  }
  return AppColors.LEVEL_COLORS[2];
}

/**
 * Precipitation.getHourlyPrecipitationColor (Precipitation.kt:62-95) against
 * PRECIPITATION_HOURLY_LIGHT/MEDIUM/HEAVY/RAINSTORM (domain Precipitation.kt:42-45).
 */
export function hourlyPrecipitationColor(millimetres: number | null): string | null {
  if (millimetres === null) {
    return null;
  }
  if (millimetres <= 5) {
    return AppColors.LEVEL_COLORS[0];
  }
  if (millimetres <= 10) {
    return AppColors.LEVEL_COLORS[1];
  }
  if (millimetres <= 15) {
    return AppColors.LEVEL_COLORS[2];
  }
  if (millimetres <= 20) {
    return AppColors.LEVEL_COLORS[3];
  }
  return AppColors.LEVEL_COLORS[4];
}

/** Parsed 8-digit ARGB colour. */
class Argb {
  a: number = 255;
  r: number = 0;
  g: number = 0;
  b: number = 0;
}

function parseArgb(color: string): Argb {
  const hex: string = color.startsWith('#') ? color.substring(1) : color;
  const out = new Argb();
  if (hex.length === 8) {
    out.a = parseInt(hex.substring(0, 2), 16);
    out.r = parseInt(hex.substring(2, 4), 16);
    out.g = parseInt(hex.substring(4, 6), 16);
    out.b = parseInt(hex.substring(6, 8), 16);
  } else {
    out.a = 255;
    out.r = parseInt(hex.substring(0, 2), 16);
    out.g = parseInt(hex.substring(2, 4), 16);
    out.b = parseInt(hex.substring(4, 6), 16);
  }
  return out;
}

function toHex2(value: number): string {
  let v: number = Math.round(value);
  if (v < 0) {
    v = 0;
  }
  if (v > 255) {
    v = 255;
  }
  const s: string = v.toString(16);
  return s.length === 1 ? '0' + s : s;
}

function buildArgb(a: number, r: number, g: number, b: number): string {
  return '#' + toHex2(a) + toHex2(r) + toHex2(g) + toHex2(b);
}

/**
 * Equivalent of ColorUtils.setAlphaComponent.
 * @param alphaFactor 0..1
 */
export function withAlpha(color: string, alphaFactor: number): string {
  const c: Argb = parseArgb(color);
  return buildArgb(255 * alphaFactor, c.r, c.g, c.b);
}

/**
 * ColorUtils.getWidgetSurfaceColor (common/utils/ColorUtils.kt) — Material's elevation overlay.
 *
 * A raised surface is not a different colour token: it is the surface with the PRIMARY colour laid
 * over it at an alpha derived from the elevation, `(4.5·ln(dp+1) + 2) / 100`. The location rows use
 * it at 2 dp, which is where their faint tint comes from.
 */
export function elevatedSurface(elevationDp: number, tint: string, surface: string): string {
  if (elevationDp === 0) {
    return surface;
  }
  const alpha: number = (4.5 * Math.log(elevationDp + 1) + 2) / 100;
  const front: Argb = parseArgb(tint);
  const back: Argb = parseArgb(surface);
  const blend = (f: number, b: number): number => f * alpha + b * (1 - alpha);
  return buildArgb(255, blend(front.r, back.r), blend(front.g, back.g), blend(front.b, back.b));
}

/** The search screen's Surface colour — see the note on AppColors.SEARCH_DIVIDER for why derived. */
export function searchSurface(isDark: boolean): string {
  return elevatedSurface(2, AppColors.PRIMARY.resolve(isDark), AppColors.SURFACE.resolve(isDark));
}

/**
 * MaterialWeatherThemeDelegate.kt:38-44 — getBrighterColor().
 * Converts to HSV, drops saturation by 0.25 and raises value by 0.25.
 */
export function getBrighterColor(color: string): string {
  const c: Argb = parseArgb(color);
  const r: number = c.r / 255;
  const g: number = c.g / 255;
  const b: number = c.b / 255;

  const max: number = Math.max(r, Math.max(g, b));
  const min: number = Math.min(r, Math.min(g, b));
  const delta: number = max - min;

  let h: number = 0;
  if (delta !== 0) {
    if (max === r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max === g) {
      h = 60 * (((b - r) / delta) + 2);
    } else {
      h = 60 * (((r - g) / delta) + 4);
    }
  }
  if (h < 0) {
    h += 360;
  }

  let s: number = max === 0 ? 0 : delta / max;
  let v: number = max;

  // Android clamps HSV components when rebuilding the colour.
  s = Math.min(1, Math.max(0, s - 0.25));
  v = Math.min(1, Math.max(0, v + 0.25));

  const cc: number = v * s;
  const x: number = cc * (1 - Math.abs(((h / 60) % 2) - 1));
  const m: number = v - cc;

  let rr: number = 0;
  let gg: number = 0;
  let bb: number = 0;
  if (h < 60) {
    rr = cc;
    gg = x;
  } else if (h < 120) {
    rr = x;
    gg = cc;
  } else if (h < 180) {
    gg = cc;
    bb = x;
  } else if (h < 240) {
    gg = x;
    bb = cc;
  } else if (h < 300) {
    rr = x;
    bb = cc;
  } else {
    rr = cc;
    bb = x;
  }

  return buildArgb(c.a, (rr + m) * 255, (gg + m) * 255, (bb + m) * 255);
}

/**
 * MaterialWeatherThemeDelegate.innerGetBackgroundColor (kt:46-68), resolving through the
 * per-implementor theme colours:
 *   SunImplementor.kt:96, MeteorShowerImplementor.kt:267, CloudImplementor.kt:592-601,
 *   RainImplementor.kt:299-306, SnowImplementor.kt:164-166, HailImplementor.kt:171-173,
 *   WindImplementor.kt:175-177
 */
export function getWeatherBackgroundColor(kind: WeatherKind, daylight: boolean): string {
  switch (kind) {
    case WeatherKind.CLEAR:
      return daylight ? '#FFFDBC4C' : '#FF141C2C';
    case WeatherKind.CLOUD:
      return daylight ? '#FF00A5D9' : '#FF222D43';
    case WeatherKind.CLOUDY:
      return daylight ? '#FF9DAFC1' : '#FF263238';
    case WeatherKind.FOG:
      return daylight ? '#FFA3AEC2' : '#FF4F5D68';
    case WeatherKind.HAZE:
      return daylight ? '#FFE1C899' : '#FF6C5C49';
    case WeatherKind.THUNDER:
      return daylight ? '#FFB296BD' : '#FF231739';
    case WeatherKind.THUNDERSTORM:
      return daylight ? '#FFB296BD' : '#FF231739';
    case WeatherKind.HAIL:
      return daylight ? '#FF68BAFF' : '#FF1A5B92';
    case WeatherKind.SNOW:
      return daylight ? '#FF68BAFF' : '#FF1A5B92';
    case WeatherKind.SLEET:
      return daylight ? '#FF68BAFF' : '#FF1A5B92';
    case WeatherKind.RAINY:
      return daylight ? '#FF4297E7' : '#FF264E8F';
    case WeatherKind.WIND:
      return daylight ? '#FFEACDA3' : '#FF958675';
    default:
      return '#00000000';
  }
}

/**
 * The three stops of a `weather_background_*` gradient, top to bottom.
 *
 * Android's page background is NOT a flat colour: MaterialPainterView sets
 * `background = getWeatherBackgroundDrawable(weatherKind, daylight)`
 * (MaterialPainterView.kt:203, WeatherImplementorFactory.kt:152-173), and every one of those
 * drawables is a three-stop vertical gradient — `<gradient android:angle="270" startColor
 * centerColor endColor>`, where angle 270 puts startColor at the TOP.
 *
 * The port was filling the canvas with `getThemeColors(kind, daylight)[0]` instead. That value is
 * a real Android colour, but it is the *theme accent* (MaterialWeatherThemeDelegate, used for the
 * chart lines and the header), not the background. For a partly-cloudy day it is #00A5D9 — the
 * saturated blue that made the HarmonyOS screen look nothing like the Android one, which shows a
 * pale #64DBFF fading to near-white.
 */
export class BackgroundGradient {
  readonly top: string;
  readonly middle: string;
  readonly bottom: string;

  constructor(top: string, middle: string, bottom: string) {
    this.top = top;
    this.middle = middle;
    this.bottom = bottom;
  }
}

/**
 * ui-weather-view/res/drawable/weather_background_*.xml, with the drawable-night variants.
 *
 * `darkMode` selects the night qualifier. Two drawables have no night variant and so are shared:
 * `weather_background_clear_night` and `weather_background_default`. Note that
 * `weather_background_clear_day` DOES have one, so a clear day in dark mode is the muted orange
 * rather than the bright one.
 *
 * Returns null for kinds with no drawable (WEATHER_KIND_NULL → weather_background_default, which
 * is `<solid android:color="@android:color/transparent"/>`); the caller falls back to the flat
 * app background.
 */
export function getWeatherBackgroundGradient(
  kind: WeatherKind,
  daylight: boolean,
  darkMode: boolean
): BackgroundGradient | null {
  switch (kind) {
    case WeatherKind.CLEAR:
      if (daylight) {
        // weather_background_clear_day
        return darkMode
          ? new BackgroundGradient('#FF592B19', '#FFCC6143', '#FFD18268')
          : new BackgroundGradient('#FFFFBA5E', '#FFFFC67E', '#FFFFF0E2');
      }
      // weather_background_clear_night — no night variant.
      return new BackgroundGradient('#FF171D52', '#FF3F4DBA', '#FF5E68BD');
    case WeatherKind.CLOUD:
      // weather_background_partly_cloudy
      return darkMode
        ? new BackgroundGradient('#FF1C2F75', '#FF585D6D', '#FF747B99')
        : new BackgroundGradient('#FF64DBFF', '#FFD6DEE0', '#FFE2F0F6');
    case WeatherKind.CLOUDY:
      return darkMode
        ? new BackgroundGradient('#FF23262C', '#FF525D66', '#FF6B8394')
        : new BackgroundGradient('#FFAFBCC7', '#FFD2D6DB', '#FFEBEFF8');
    case WeatherKind.FOG:
      return darkMode
        ? new BackgroundGradient('#FF131B45', '#FF2A5476', '#FF918EAF')
        : new BackgroundGradient('#FFA2C3FF', '#FFB3AFD1', '#FFE7BEB0');
    case WeatherKind.HAZE:
      return darkMode
        ? new BackgroundGradient('#FF4D3314', '#FF755125', '#FFC5AF9D')
        : new BackgroundGradient('#FFFFDDA1', '#FFD1C3AF', '#FFB5E8EF');
    case WeatherKind.HAIL:
      return darkMode
        ? new BackgroundGradient('#FF335A7E', '#FF435A6F', '#FF303742')
        : new BackgroundGradient('#FFDDF7FF', '#FFE1E5E9', '#FFA0AFC1');
    case WeatherKind.RAINY:
      return darkMode
        ? new BackgroundGradient('#FF233361', '#FF2F4997', '#FF252731')
        : new BackgroundGradient('#FF97B6D1', '#FFA6BBCE', '#FF97A8D7');
    case WeatherKind.SLEET:
      return darkMode
        ? new BackgroundGradient('#FF23306B', '#FF3549A4', '#FF23262F')
        : new BackgroundGradient('#FFB4D3ED', '#FFC5D2DC', '#FFADC3DE');
    case WeatherKind.SNOW:
      return darkMode
        ? new BackgroundGradient('#FF353A47', '#FF455762', '#FF414F83')
        : new BackgroundGradient('#FF93A2AD', '#FFE3E7EB', '#FFEDF2F6');
    case WeatherKind.THUNDER:
    case WeatherKind.THUNDERSTORM:
      // WeatherImplementorFactory.kt:170 — both thunder kinds share one drawable.
      return darkMode
        ? new BackgroundGradient('#FF2F2B38', '#FF50406D', '#FF2C1C4D')
        : new BackgroundGradient('#FFC697D7', '#FFC1A3CE', '#FFAB90DB');
    case WeatherKind.WIND:
      return darkMode
        ? new BackgroundGradient('#FF313E3A', '#FF529B73', '#FF638170')
        : new BackgroundGradient('#FF96D0A3', '#FFDFFAE7', '#FFE8F4EE');
    default:
      return null;
  }
}

/**
 * MaterialWeatherThemeDelegate.getThemeColors (kt:73-87).
 * Returns [background, high-line, low-line] where the third entry is the second at 50% alpha.
 *
 * Despite the name of the first entry this is the theme ACCENT, used for the trend chart lines
 * and the nowcast columns — not the page background. See getWeatherBackgroundGradient.
 */
export function getThemeColors(kind: WeatherKind, daylight: boolean): string[] {
  let color: string = getWeatherBackgroundColor(kind, daylight);
  if (!daylight) {
    color = getBrighterColor(color);
  }
  return [color, color, withAlpha(color, 0.5)];
}

/*
 * Pollen level dot colours.
 *
 * The `pollen_level_colors` array (arrays.xml) is pollenLevel_1 … pollenLevel_5 — it does NOT
 * start at pollenLevel_0. getPollenIndexToColor (PollenIndex.kt:76-84) reaches the grey
 * pollenLevel_0 only through its `if (pollenIndex == 0)` early return, i.e. a concentration of
 * exactly zero, which is also the only case that reads "None" rather than a level name.
 *
 * So the five levels "Very low" … "Very high" map to indices 0…4 of THIS array, and a "Very low"
 * reading is the teal #08C286 — not grey. Indexing a six-entry ramp by level shifted every dot
 * one band down and made "Very low" read as "None".
 */
const POLLEN_LEVEL_COLORS: string[] =
  ['#FF08C286', '#FF6AD555', '#FFFFD741', '#FFFFAB40', '#FFFF3B30'];

/** colors.xml pollenLevel_0 — a zero concentration only. */
export const POLLEN_LEVEL_NONE_COLOR: string = '#FFBFBFBF';

export function pollenLevelColor(level: number): string {
  const i: number = Math.max(0, Math.min(level, POLLEN_LEVEL_COLORS.length - 1));
  return POLLEN_LEVEL_COLORS[i];
}

/** PollutantIndex.getAqiToLevel — index of the last threshold at or below the value. */
export function aqiLevelColor(index: number): string {
  let level: number = -1;
  for (let i = 0; i < AppColors.AQI_THRESHOLDS.length; i++) {
    if (index >= AppColors.AQI_THRESHOLDS[i]) {
      level = i;
    }
  }
  if (level < 0) {
    level = 0;
  }
  const colorIndex: number = Math.min(level, AppColors.LEVEL_COLORS.length - 1);
  return AppColors.LEVEL_COLORS[colorIndex];
}

/**
 * MaterialWeatherThemeDelegate.isLightBackground (kt:89-97):
 * light only when it is daytime AND the system is not in night mode.
 */
export function isLightBackground(daylight: boolean, systemIsDark: boolean): boolean {
  return daylight && !systemIsDark;
}
