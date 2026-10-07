/*
 * The app typeface.
 *
 * The Android build renders in Roboto (the platform default there). ArkUI's default is
 * HarmonyOS Sans, so identical sizes and weights still produced visibly different text — the
 * letterforms differ. Roboto is registered in pages/Index.ets and referenced by this name.
 *
 * ArkUI does not cascade text styles from a parent, so every Text has to opt in with
 * .fontFamily(APP_FONT_FAMILY). Applying it in one place is not possible.
 */

export const APP_FONT_FAMILY: string = 'Roboto';

/**
 * The SETTINGS typeface, which is not the same one.
 *
 * The reference renders in two faces and which one depends on the screen:
 *
 *   * the main weather screen is classic Views, themed with `android:fontFamily=@font/robotoflex`
 *     (styles.xml:316, and the values-v26 / values-v28 copies) — the app's own bundled Roboto;
 *   * every settings screen is Compose, and its typography is `fontFamily = FontFamily.Default`
 *     (Type.kt:28, :36, :43) — the SYSTEM sans-serif.
 *
 * On the reference device `sans-serif` resolves to HarmonyOS_Sans.ttf, NOT Roboto:
 * /system/etc/fonts.xml names it in the first <family>, under the comment "first font is default".
 * That is also this device's default, so naming no family here matches the reference exactly and
 * keeps the two ports on the same glyphs as each other.
 *
 * The comment above used to assert that Roboto was "the platform default there" and this port put
 * Roboto on every screen. Measured on 2026-08-11 against the reference's own uiautomator bounds,
 * that made every settings label about 8 % narrow — "Notifications of app updates" 649 px against
 * 708, "Disabled" 168 against 185 — enough that "Notifications of severe weather alerts" fitted on
 * one line here where the reference wraps it onto two, leaving that row 285 px against 364.
 */
export const SETTINGS_FONT_FAMILY: string = 'HarmonyOS Sans';

/**
 * Material 3 line heights, in vp, for the roles this port uses.
 *
 * An ArkUI `Text` with no `.lineHeight()` gets a line box of roughly 1.17 x its font size, where
 * Material's is 1.4 to 1.5 — so every stacked-text layout came out about 20 % short and drifted
 * further with each line. Measured against the reference on 2026-08-11: a 16 fp body line was
 * 61 px where Android's is 78, a 22 fp titleLarge 84 against 91, a 36 fp displaySmall 137 against
 * 143. The type scale is the fix; a Text that has to occupy Android's height MUST set one.
 *
 * Source: Material 3 `Typography` defaults, as used by MaterialTheme.typography.* in the Kotlin.
 */
export class LineHeights {
  /** bodySmall — 12 sp on a 16 sp line. Also labelMedium, which shares the metric. */
  static readonly BODY_SMALL: number = 16;
  /** labelMedium — 12 sp on a 16 sp line. The half-day header's "Daytime" / "Nighttime". */
  static readonly LABEL_MEDIUM: number = 16;
  /** labelLarge — 14 sp on a 20 sp line. Wind's gusts line. */
  static readonly LABEL_LARGE: number = 20;
  /** bodyMedium — 14 sp on a 20 sp line. */
  static readonly BODY_MEDIUM: number = 20;
  /** bodyLarge — 16 sp on a 24 sp line. Compose's default text style, so most body copy. */
  static readonly BODY_LARGE: number = 24;
  /** titleMedium — 16 sp on a 24 sp line. */
  static readonly TITLE_MEDIUM: number = 24;
  /** titleLarge — 22 sp on a 28 sp line. `DetailsSectionHeader`. */
  static readonly TITLE_LARGE: number = 28;
  /** headlineSmall — 24 sp on a 32 sp line. The in-page group headings. */
  static readonly HEADLINE_SMALL: number = 32;
  /** displaySmall — 36 sp on a 44 sp line. Every detail header's value. */
  static readonly DISPLAY_SMALL: number = 44;
}
