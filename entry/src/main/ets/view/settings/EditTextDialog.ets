/*
 * EditTextPreferenceView's dialog (ui/settings/preference/composables/EditTextPreference.kt:135-225).
 *
 * The same shell every other preference dialog on screen 3 uses — see ListPreferenceDialog — with a
 * single-line OutlinedTextField in place of the radio list. Cancel leaves the stored value alone;
 * the positive button commits whatever is in the field, including the empty string, because
 * clearing a key back to the bundled default is a real action (BaiduIPLocationService.kt:95-97
 * falls back to BuildConfig).
 *
 * Verified against the reference device (ref_screen3f_instance_dialog.png): the buttons read
 * "CANCEL" and "Done" — NOT "Confirm", which is a different string (action_confirm) used by other
 * dialogs. The field carries a visible outline and shows its placeholder in grey while empty.
 */

import { Dimens } from '../../theme/Dimens';
import { AppColors } from '../../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../../common/Typography';

const DIALOG_CORNER: number = 28;
const DIALOG_PADDING: number = 24;
/** headlineSmall, as the list-choice dialog's title uses. */
const DIALOG_TITLE_SIZE: number = 24;
const ACTION_TEXT_SIZE: number = 14;
/** OutlinedTextFieldDefaults — 1dp border, 4dp corner. */
const FIELD_BORDER_WIDTH: number = 1;
const FIELD_CORNER: number = 4;
const FIELD_HEIGHT: number = 56;
/** The supporting text under the field, bodySmall. */
const ERROR_TEXT_SIZE: number = 12;
/** Compose's disabled-button alpha. */
const DISABLED_OPACITY: number = 0.38;

@ComponentV2
export struct EditTextDialog {
  @Param title: string = '';
  /** The stored value; empty is normal and means "unchanged". */
  @Param content: string = '';
  /**
   * Shown in grey while the field is empty — an instance row's default URL. A row with a
   * placeholder also ACCEPTS empty, which is how it is reset (kt:166-168).
   */
  @Param placeholder: string = '';
  /**
   * kt:200 — when set, the field must satisfy EditTextPreference.URL_REGEX (an https URL ending in
   * a slash) or the positive button is dead.
   */
  @Param url: boolean = false;
  /** kt:176-180 — the message under a failing field. strings.xml:891 settings_invalid_syntax. */
  @Param regexError: string = 'Invalid syntax';
  @Param dark: boolean = false;
  @Event onChosen: (value: string) => void = () => {
  };
  @Event onDismiss: () => void = () => {
  };

  @Local private draft: string = '';

  aboutToAppear(): void {
    this.draft = this.content;
  }

  /**
   * EditTextPreference.URL_REGEX. Kept here rather than in the table because it is the dialog's
   * rule, and only the dialog enforces it.
   */
  private matchesUrl(value: string): boolean {
    return value.startsWith('https://') && value.endsWith('/');
  }

  /** kt:166-168 — an empty value is only an error when there is no placeholder to fall back on. */
  private invalid(): boolean {
    if (!this.url) {
      return false;
    }
    if (this.draft.length === 0) {
      return this.placeholder.length === 0;
    }
    return !this.matchesUrl(this.draft);
  }

  build() {
    // The scrim. Tapping it dismisses without storing, like a Material dialog's outside touch.
    Column() {
      Column() {
        Text(this.title)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(DIALOG_TITLE_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        TextInput({ text: this.draft, placeholder: this.placeholder })
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .placeholderColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .caretColor(AppColors.PRIMARY.resolve(this.dark))
          .backgroundColor(Color.Transparent)
          .showUnderline(false)
          .borderWidth(FIELD_BORDER_WIDTH)
          .borderRadius(FIELD_CORNER)
          .borderColor(this.invalid()
            ? AppColors.ERROR.resolve(this.dark)
            : AppColors.COMPOSE_OUTLINE.resolve(this.dark))
          .height(FIELD_HEIGHT)
          .width('100%')
          .onChange((value: string) => {
            this.draft = value;
          })

        // kt:169-184 — only present while the value actually fails.
        if (this.invalid()) {
          Text(this.regexError)
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(ERROR_TEXT_SIZE)
            .fontColor(AppColors.ERROR.resolve(this.dark))
            .width('100%')
            .padding({ top: Dimens.SMALL_MARGIN, left: Dimens.NORMAL_MARGIN })
        }

        Row() {
          Blank()
          Text('CANCEL') // android.R.string.cancel, uppercase on the reference device
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(ACTION_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.NORMAL_MARGIN)
            .onClick(() => {
              this.onDismiss();
            })
          Text('Done') // strings.xml:493 `action_done`
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(ACTION_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .opacity(this.invalid() ? DISABLED_OPACITY : 1)
            .padding(Dimens.NORMAL_MARGIN)
            .onClick(() => {
              // kt:200 — a failing value cannot be committed at all, not merely warned about.
              if (this.invalid()) {
                return;
              }
              this.onChosen(this.draft);
            })
        }
        .width('100%')
      }
      .width(Dimens.DIALOG_WIDTH)
      .padding(DIALOG_PADDING)
      .backgroundColor(AppColors.DIALOG_SURFACE.resolve(this.dark))
      .borderRadius(DIALOG_CORNER)
      // Swallow taps on the card so they do not reach the scrim behind it.
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#52000000')
    .onClick(() => {
      this.onDismiss();
    })
  }
}
