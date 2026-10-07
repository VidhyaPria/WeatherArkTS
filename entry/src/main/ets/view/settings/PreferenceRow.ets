/*
 * One row of a settings list â€” PreferenceViewWithCard (Preference.kt:101-134) wrapping
 * PreferenceView (Preference.kt:136-227) inside Material3ExpressiveCardListItem
 * (Material3Widgets.kt:194-226).
 *
 * The layout, extracted rather than eyeballed:
 *
 *   card          elevation 2 dp (defaultCardListItemElevation, Material3Widgets.kt:187),
 *                 colorScheme.surface, corners 28 dp on the group's OUTER edges and 2 dp on the
 *                 inner ones (dimens.xml:21, Material3Widgets.kt:204-225)
 *   ListItem      PaddingValues(vertical = 8.dp) (Preference.kt:148-152)
 *   leading icon  24 dp, tinted onSurface (Preference.kt:167-178)
 *   title         typography.titleMedium, onSurface (Preference.kt:187-191)
 *   summary       typography.bodyMedium, onSurfaceVariant, with a small_margin spacer ABOVE it
 *                 (Preference.kt:210-222)
 *
 * `isFirst`/`isLast` are the group's edges, not the list's: a group of two rows is first+last, a
 * lone row is both, and a middle row is neither.
 */

import { Dimens } from '../../theme/Dimens';
import { AppColors } from '../../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../../common/Typography';

/** MaterialTheme.typography.titleMedium â€” 16 sp, weight 500. */
const TITLE_TEXT_SIZE: number = 16;
/** MaterialTheme.typography.bodyMedium â€” 14 sp. */
const SUMMARY_TEXT_SIZE: number = 14;
/** ListItemDefaults' horizontal content padding. */
const LIST_ITEM_H_PADDING: number = 16;
/** ListItemDefaults' gap between the leading icon and the headline. */
const LEADING_GAP: number = 16;
/** titleMedium â€” 16 sp on a 24 sp line. */
const TITLE_LINE_HEIGHT: number = 24;
/** bodyMedium â€” 14 sp on a 20 sp line. */
const SUMMARY_LINE_HEIGHT: number = 20;
/**
 * The Material 3 type scale's TRACKING, which this port used to drop.
 *
 * titleMedium carries 0.15 sp and bodyMedium 0.25. Measured against the reference on 2026-08-11
 * after the typeface was corrected: "Notifications of app updates" inked 681 px here against 699
 * there and "Disabled" 172 against 176, and 28 and 8 characters of this tracking are worth 13.7 and
 * 6.5 px — which is the whole of what was left.
 */
const TITLE_LETTER_SPACING: number = 0.15;
const SUMMARY_LETTER_SPACING: number = 0.25;
/**
 * The row's vertical padding, MEASURED on the reference rather than assembled.
 *
 * CORRECTED 2026-08-11, from 19. The earlier value came from the row PITCH (293 px for a one-line
 * summary) minus the 169 px of content: 124 -> 62 a side -> 19 dp. But the pitch INCLUDES the 7 px
 * small separator, so that quietly folded the separator into the padding.
 *
 * Settled by scanning a pixel column down the reference's Units screen and reading the CARD runs
 * directly, which is the measurement the earlier one stood in for:
 *     gap  7 px    the smallSeparator - 2 dp, which both ports already draw separately
 *     CARD 286 px  twice, independently (y 917..1202 and y 1503..1788)
 *     286 - 169 content = 117 -> 58.5 a side -> 18 dp
 * Cross-check that pins it: card top 917 + 58.5 puts the title at 975.5, and the reference's
 * "Precipitation unit" title is at 976.
 *
 * The stale derivation follows, kept because it names where the 16 dp of it comes from:
 * The reference's rows inside one card sit 293 px apart with a one-line summary and 358 px with a
 * two-line one, against a content height of 24 + 8 + 20n dp; that is 38 dp of padding in both
 * cases, i.e. 19 dp a side. Preference.kt:148 accounts for 8 dp of it and ListItemDefaults for
 * another 8; the remaining 3 dp a side is what `Material3ExpressiveCardListItem` contributes, and
 * that composable's internals are a library detail this tree does not contain â€” so the total is
 * taken from the measurement instead of guessed at. The port used to pad by 8 dp and let its own
 * shorter line boxes decide the rest, which made every settings row 183 px against 293.
 */
const ROW_V_PADDING: number = 18;
/**
 * A SWITCH row's vertical padding, which is NOT the same 18 and is not measured but read.
 *
 * The card variant of `SwitchPreferenceView` (SwitchPreference.kt:103-152) is not a ListItem: it is
 * a plain `Row` with `.padding(normal_margin)` — 16 dp on every side (kt:122) — holding a weighted
 * Column and a Switch with a `small_margin` Spacer between them (kt:143). So none of the ListItem
 * reasoning above applies to it: no 8 dp inner padding, no ListItemDefaults, and no one-line floor.
 *
 * Confirmed on the reference by scanning its Notifications screen: the switch cards run 273 px
 * against a plain row's 286, and 273 - 169 of content is 104, i.e. exactly 16 dp a side. Both ports
 * drew these at 18 dp with a 16 dp gap to the switch, so every switch row was 13 px too tall.
 */
const SWITCH_ROW_V_PADDING: number = 16;
/** Material 3 Switch: 52 x 32 dp. The reference draws it 169 x 104 px at this density. */
const SWITCH_WIDTH: number = 52;
const SWITCH_HEIGHT: number = 32;
/** ListItemOneLineContainerHeight — the floor for a row with no summary. */
const LIST_ITEM_ONE_LINE_HEIGHT: number = 56;

/**
 * `SectionHeader` (Section.kt:31-46) — a Box padded `normal_margin` all round with a bodyMedium
 * SemiBold `primary` Text inside.
 *
 * ONE copy. Five settings pages each carried their own identical `@Builder sectionHeader`, and all
 * five had the same defect: no line height, so the text box measured 53 px where bodyMedium's
 * 20 sp line is 65, and the whole header came out 157 px against the reference's 169
 * (16 + 20 + 16 dp). That is 12 px of drift injected at every section boundary — the Appearance
 * screen accumulated 31 px of it by "Theme".
 *
 * Measured on the reference: the text node is `[104,676][568,741]`, so 65 px tall, sitting 52 px
 * inside a box that runs 624..793 with the next card starting exactly at 793.
 */
@Builder
export function settingsSectionHeader(title: string, dark: boolean) {
  Text(title)
    .fontFamily(SETTINGS_FONT_FAMILY)
    .fontSize(SUMMARY_TEXT_SIZE)
    .fontWeight(FontWeight.Medium)
    .fontColor(AppColors.PRIMARY.resolve(dark))
    .lineHeight(SUMMARY_LINE_HEIGHT)
    .letterSpacing(SUMMARY_LETTER_SPACING)
    .width('100%')
    .padding(Dimens.NORMAL_MARGIN)
}

@ComponentV2
export struct PreferenceRow {
  @Param title: string = '';
  @Param summary: string = '';
  @Param icon: Resource | null = null;
  @Param dark: boolean = false;
  /** The group's outer edges â€” see the header note. */
  @Param isFirst: boolean = false;
  @Param isLast: boolean = false;
  /**
   * SwitchPreferenceView (SwitchPreference.kt:86-230) is this same row with a trailing Switch, so
   * it is a mode here rather than a second component â€” which is what the Kotlin does too.
   *
   * The WHOLE ROW toggles (kt:116-120): the Switch is trailing content, not the only target.
   */
  @Param showSwitch: boolean = false;
  @Param checked: boolean = false;
  /**
   * kt:112 â€” a disabled row is drawn at half alpha and takes no input.
   *
   * `rowEnabled`, not `enabled`: `enabled` is an attribute method inherited from CustomComponent,
   * so a member of that name collides with it and the compiler rejects the struct. The same trap
   * NumberAnimText documents for `fontSize`/`fontColor`.
   */
  @Param rowEnabled: boolean = true;

  @Event onTap: () => void = () => {
  };
  @Event onToggle: (value: boolean) => void = () => {
  };

  private corner(outer: boolean): number {
    return outer ? Dimens.SETTINGS_CARD_CORNER_RADIUS : Dimens.SETTINGS_CARD_INNER_CORNER_RADIUS;
  }

  build() {
    Row() {
      if (this.icon !== null) {
        Image(this.icon)
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
          .margin({ right: LEADING_GAP })
      }

      Column() {
        Text(this.title)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(TITLE_TEXT_SIZE)
          // titleMedium carries weight 500; the port's other titleMedium text does the same.
          .fontWeight(FontWeight.Medium)
          // titleMedium is 16 sp on a 24 sp LINE. Without saying so the line box came out at
          // 61 px where the reference's title node measures 78.
          .lineHeight(TITLE_LINE_HEIGHT)
          .letterSpacing(TITLE_LETTER_SPACING)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')

        if (this.summary.length > 0) {
          // The spacer is part of the supporting content, above the text (Preference.kt:213-215).
          Text(this.summary)
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(SUMMARY_TEXT_SIZE)
            // bodyMedium is 14 sp on a 20 sp line; the reference's summary node measures 65.
            .lineHeight(SUMMARY_LINE_HEIGHT)
            .letterSpacing(SUMMARY_LETTER_SPACING)
            .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
            .width('100%')
            .margin({ top: Dimens.SMALL_MARGIN })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showSwitch) {
        Toggle({ type: ToggleType.Switch, isOn: this.checked })
          .enabled(this.rowEnabled)
          /*
           * Material 3's Switch is 52 x 32 dp, and ArkUI's Toggle defaults to 36 x 20 — measured on
           * the reference at 169 x 104 px against this port's 117 x 65. Size matters twice over
           * here: the switch is what is left of the row's width, so an undersized one also handed
           * the title 877 px to wrap in where the reference gives it 857.
           */
          .width(SWITCH_WIDTH)
          .height(SWITCH_HEIGHT)
          .selectedColor(AppColors.PRIMARY.resolve(this.dark))
          // small_margin, NOT the leading 16 — SwitchPreference.kt:143 is a Spacer of small_margin.
          .margin({ left: Dimens.SMALL_MARGIN })
          .onChange((value: boolean) => {
            // Guarded because a Toggle reports the change the row's own onClick just made, which
            // would toggle it straight back.
            if (this.rowEnabled && value !== this.checked) {
              this.onToggle(value);
            }
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .opacity(this.rowEnabled ? 1.0 : 0.5)
    /*
     * A row with NO summary is a one-line ListItem: 56 dp, plus Preference.kt:148's 8 dp a side.
     * Derived from the source rather than measured, because this screen has no summary-less row
     * to measure; it only ever raises a row that would otherwise be shorter.
     */
    // A SWITCH row is not a ListItem at all, so no floor applies to it; see SWITCH_ROW_V_PADDING.
    .constraintSize({
      minHeight: this.showSwitch ? 0 : LIST_ITEM_ONE_LINE_HEIGHT + 2 * Dimens.SMALL_MARGIN
    })
    .padding({
      left: LIST_ITEM_H_PADDING,
      right: LIST_ITEM_H_PADDING,
      top: this.showSwitch ? SWITCH_ROW_V_PADDING : ROW_V_PADDING,
      bottom: this.showSwitch ? SWITCH_ROW_V_PADDING : ROW_V_PADDING
    })
    // getWidgetSurfaceColor(2.dp, surface) â€” an ELEVATION TINT, not plain surface. See AppColors.
    .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.dark))
    .borderRadius({
      topLeft: this.corner(this.isFirst),
      topRight: this.corner(this.isFirst),
      bottomLeft: this.corner(this.isLast),
      bottomRight: this.corner(this.isLast)
    })
    .onClick(() => {
      if (!this.rowEnabled) {
        return;
      }
      // kt:116-120 â€” tapping anywhere on a switch row flips it; only a plain row navigates.
      if (this.showSwitch) {
        this.onToggle(!this.checked);
        return;
      }
      this.onTap();
    })
  }
}
