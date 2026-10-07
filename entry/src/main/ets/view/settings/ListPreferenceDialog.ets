/*
 * The single-choice dialog a list preference opens (ListPreference.kt:241-313).
 *
 *   title    typography.headlineSmall, onSurface
 *   body     one RadioButton per value; choosing one CLOSES the dialog and fires the change
 *   button   a single "Cancel" TextButton, primary, typography.labelLarge
 *
 * There is no confirm: the radio IS the commit, which is why the only button is a cancel.
 */

import { AppColors } from '../../theme/AppColors';
import { Dimens } from '../../theme/Dimens';
import { SETTINGS_FONT_FAMILY, LineHeights } from '../../common/Typography';
import { SystemInsets } from '../../common/SystemBars';

/** typography.headlineSmall — 24 sp. Material Components value; the library is not vendored here. */
const TITLE_TEXT_SIZE: number = 24;
/** typography.labelLarge — 14 sp. */
const BUTTON_TEXT_SIZE: number = 14;
/** typography.bodyLarge, which a RadioButton's label carries — 16 sp. */
const OPTION_TEXT_SIZE: number = 16;
/**
 * A radio row's MINIMUM height — it grows for a label that wraps.
 *
 * NOT the 56 dp Material3 ListItem token this used to carry. A single-choice row inside an
 * AlertDialog is not a ListItem; it is a radio plus a label, and its height is the 48 dp minimum
 * touch target. Measured on the reference's alternate-calendar dialog, which is the one place with
 * both one-line and two-line labels in the same list:
 *
 *   Chinese -> Dangi -> Hebrew -> Indian    156 px pitch each = 48 dp
 *   "Islamic Calendar (Saudi Arabia, sighting)" occupies 1542..1698 — also 156 px, but that is its
 *   TEXT, two 78 px lines with no padding left over
 *
 * So the row is `max(48 dp, content)`, which a fixed height cannot express: at 56 dp every row was
 * 26 px too tall AND a wrapped label would have been clipped.
 */
const OPTION_MIN_HEIGHT: number = 48;

/**
 * The button row under the list.
 *
 * Measured on the reference's alternate-calendar dialog rather than guessed from Material's
 * spec: its twelve 156 px rows end at 2322 and the container at 2633, so the button block plus the
 * dialog's own 24 dp bottom padding is 311 px. A 40 dp button under a 32 dp gap accounts for it
 * exactly, and the whole dialog then measures 2418 px against the reference's 2418:
 *
 *   78 padding + 104 title + 52 margin + 1872 rows + 104 gap + 130 button + 78 padding
 */
const BUTTON_ROW_HEIGHT: number = 40;
const BUTTON_ROW_TOP_MARGIN: number = 32;
/** AlertDialog's own container inset and corner. */
const DIALOG_CORNER: number = 28;
const DIALOG_PADDING: number = 24;

/** One selectable value. Plain data — nothing observes it. */
export class ListPreferenceOption {
  value: string;
  name: string;
  /**
   * `enableArray` (ListPreference.kt:280-294). A disabled option is still LISTED and still takes a
   * tap; the tap simply does nothing. Only the Weather sources default-source picker has any —
   * every other list on screen 3 passes them all enabled.
   */
  enabled: boolean;

  constructor(value: string, name: string, enabled: boolean = true) {
    this.value = value;
    this.name = name;
    this.enabled = enabled;
  }
}

/** onSurface at 50% — a disabled option's label (ListPreference.kt:395-399). */
const DISABLED_OPACITY: number = 0.5;

@ComponentV2
export struct ListPreferenceDialog {
  @Param title: string = '';
  @Param options: ListPreferenceOption[] = [];
  @Param selected: string = '';
  @Param dark: boolean = false;

  /** Fired with the chosen value. The dialog closes first, as the Kotlin's radio does. */
  @Event onChosen: (value: string) => void = () => {
  };
  @Event onDismiss: () => void = () => {
  };

  /** kt:287 — a disabled row absorbs the tap rather than closing the dialog. */
  private choose(option: ListPreferenceOption): void {
    if (!option.enabled) {
      return;
    }
    this.onChosen(option.value);
  }

  build() {
    // The scrim: a real dialog dims everything, and a tap outside dismisses it.
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#52000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Text(this.title)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(TITLE_TEXT_SIZE)
          // headlineSmall is 24 sp on a 32 sp LINE; without this the title box is ~28 px short and
          // the whole dialog with it. Same defect the icon dialogs had.
          .lineHeight(LineHeights.HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        ForEach(this.options, (option: ListPreferenceOption) => {
          Row() {
            Radio({ value: option.value, group: 'list-preference' })
              .checked(option.value === this.selected)
              .enabled(option.enabled)
              .opacity(option.enabled ? 1 : DISABLED_OPACITY)
              .radioStyle({
                checkedBackgroundColor: AppColors.PRIMARY.resolve(this.dark)
              })
              .onClick(() => {
                // Choosing commits and closes — ListPreference.kt:286-294.
                this.choose(option);
              })

            Text(option.name)
              .fontFamily(SETTINGS_FONT_FAMILY)
              .fontSize(OPTION_TEXT_SIZE)
              // bodyLarge is 16 sp on a 24 sp LINE. Without it each line was 61 px against the
              // reference's 78, which only shows on the labels that WRAP — a one-line row is pinned
              // by OPTION_MIN_HEIGHT either way, so the list looked right until a label wrapped.
              .lineHeight(LineHeights.BODY_LARGE)
              .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
              .opacity(option.enabled ? 1 : DISABLED_OPACITY)
              .layoutWeight(1)
              .margin({ left: Dimens.NORMAL_MARGIN })
          }
          .width('100%')
          .constraintSize({ minHeight: OPTION_MIN_HEIGHT })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.choose(option);
          })
        }, (option: ListPreferenceOption) => option.value)

        /*
         * android.R.string.cancel — the only button; the radio is the commit.
         *
         * UPPERCASE because that is what the reference device renders. The string resource itself
         * is "Cancel"; the Material button style upper-cases it, and `uiautomator dump` reports
         * "CANCEL" in every dialog on the device — checked in both the Appearance dark-mode dialog
         * and all five Units dialogs. Written out rather than applied as a text transform so the
         * dumps of the two ports compare literally.
         */
        Row() {
          Blank()
          Text('CANCEL')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(BUTTON_TEXT_SIZE)
            .lineHeight(LineHeights.LABEL_LARGE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.onDismiss();
            })
        }
        .width('100%')
        .height(BUTTON_ROW_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .margin({ top: BUTTON_ROW_TOP_MARGIN })
      }
      .width(Dimens.DIALOG_WIDTH)
      .padding(DIALOG_PADDING)
      .backgroundColor(AppColors.DIALOG_SURFACE.resolve(this.dark))
      .borderRadius(DIALOG_CORNER)
      /*
       * Android centres the dialog in the window BELOW the status bar, not in the whole display:
       * the reference's container spans 216..2633, whose centre is 1424 where the display's is
       * 1360. Half the top inset is exactly that 64 px. The scrim still covers everything, which
       * is why the offset is on the container rather than on the Stack.
       */
      .offset({ y: SystemInsets.instance.top / 2 })
    }
    .width('100%')
    .height('100%')
  }
}
