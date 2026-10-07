/*
 * Screen 3a — Appearance. Port of AppearanceSettingsScreen.kt (:88-353).
 *
 * Two sections:
 *
 *   Language and region   Language | Units | Alternate calendar
 *   Theme                 App dark mode | Location-based dark mode | Icon pack
 *
 * WHAT IS REAL HERE, and what is not:
 *
 *   App dark mode              real — stored, and it re-themes every screen through
 *                              SettingsStore.isLightTheme
 *   Location-based dark mode   real — stored; disabled while App dark mode is "Light", and forced
 *                              to show "Follow day/night" then (kt:203-206)
 *   Language                   the port is English-only per CLAUDE.md, so the list has one entry
 *   Units                      real — its own screen, `pages/UnitSettings`
 *   Alternate calendar         not ported yet
 *   Icon pack                  external icon packs are scoped out entirely by CLAUDE.md
 *
 * The rows that are not real still SHOW, with the value they would have, because the settings list
 * is what Android renders — hiding them would be inventing a different screen.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow, settingsSectionHeader } from '../view/settings/PreferenceRow';
import { ListPreferenceDialog, ListPreferenceOption } from '../view/settings/ListPreferenceDialog';
import {
  CalendarOption,
  calendarOptions,
  calendarSummary,
  deviceCountry,
  deviceLanguage
} from '../model/CalendarCatalogue';
import { SystemInsets } from '../common/SystemBars';
import {
  AppSettings,
  appIsDark,
  DarkModeLocationSetting,
  DarkModeSetting,
  setAlternateCalendar,
  setDarkMode,
  setDayNightForLocations
} from '../data/SettingsStore';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
/** SectionHeader: bodyMedium, SemiBold, primary, padded normal_margin (Section.kt:31-46). */
const SECTION_TEXT_SIZE: number = 14;
/** typography.headlineSmall — the icon-packs dialog title (kt:288). */
const DIALOG_TITLE_TEXT_SIZE: number = 24;
/** kt:316-317 — the provider's own launcher icon, 42 dp. */
const PROVIDER_ICON_SIZE: number = 42;
/** The same dialog inset ListPreferenceDialog uses, so the two dialogs line up. */
const DIALOG_PADDING: number = 24;

/** Which dialog is up, if any. */
enum OpenDialog {
  NONE = 0,
  DARK_MODE = 1,
  DARK_MODE_LOCATIONS = 2,
  LANGUAGE = 3,
  ICON_PACK = 4,
  /**
   * kt:130-131 — `CalendarPreferenceView` is an inline list preference, NOT a screen. Both ports
   * used to treat the row as a navigation: ArkUI sent it to the placeholder and the NDK did
   * nothing at all, which was the more visible of the two bugs.
   */
  ALTERNATE_CALENDAR = 5
}

@Entry
@ComponentV2
struct AppearanceSettings {
  private insets: SystemInsets = SystemInsets.instance;
  /** Read directly in the build, so a change re-themes and re-labels the rows. */
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  @Local private dialog: number = OpenDialog.NONE;
  /** Bumped after a write so the rows re-read the store. */
  @Local private revision: number = 0;

  aboutToAppear(): void {
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  /* ------------------------------------------------------------------ the option lists -------- */

  /** dark_mode_values / dark_modes (arrays.xml), with the ids DarkMode.kt stores. */
  private darkModeOptions(): ListPreferenceOption[] {
    return [
      /*
       * The first entry names the SYSTEM's current mode in parentheses (kt:144-176):
       *
       *   MODE_NIGHT_NO     -> "Follow system (Light)"
       *   MODE_NIGHT_YES    -> "Follow system (Dark)"
       *   MODE_NIGHT_AUTO   -> "(Follow day/night)"      no HarmonyOS equivalent
       *   MODE_NIGHT_CUSTOM -> "(<start> - <end>)"       no HarmonyOS equivalent
       *   else              -> "Follow system (Light)"
       *
       * The two branches that HAVE an equivalent are the two that occur on a modern device, and
       * `systemDark` is exactly `uiModeManager.nightMode` for them, so they are ported. AUTO and
       * CUSTOM fall to the Kotlin's own `else`, which is the Light label — the same answer this
       * gives. The reference device renders "Follow system (Light)".
       */
      new ListPreferenceOption(DarkModeSetting.SYSTEM,
        'Follow system (' + (this.settings.systemDark ? 'Dark' : 'Light') + ')'),
      new ListPreferenceOption(DarkModeSetting.LIGHT, 'Light'),
      new ListPreferenceOption(DarkModeSetting.DARK, 'Dark')
    ];
  }

  /** dark_mode_location_values / dark_modes_location. */
  private darkModeLocationOptions(): ListPreferenceOption[] {
    return [
      new ListPreferenceOption(DarkModeLocationSetting.DAY_NIGHT, 'Follow day/night'),
      new ListPreferenceOption(DarkModeLocationSetting.DARK,
        'Always dark when app is in dark mode')
    ];
  }

  private darkModeName(): string {
    const options: ListPreferenceOption[] = this.darkModeOptions();
    for (let i = 0; i < options.length; i++) {
      if (options[i].value === this.settings.darkMode) {
        return options[i].name;
      }
    }
    return options[0].name;
  }

  /**
   * kt:203-206 — while App dark mode is "Light" this always reads "Follow day/night", whatever is
   * stored, because the location rule is unconditional in that branch of isLightTheme.
   */
  private darkModeLocationKey(): string {
    if (this.settings.darkMode === DarkModeSetting.LIGHT) {
      return DarkModeLocationSetting.DAY_NIGHT;
    }
    return this.settings.dayNightForLocations
      ? DarkModeLocationSetting.DAY_NIGHT
      : DarkModeLocationSetting.DARK;
  }

  private darkModeLocationName(): string {
    const key: string = this.darkModeLocationKey();
    const options: ListPreferenceOption[] = this.darkModeLocationOptions();
    return key === options[0].value ? options[0].name : options[1].name;
  }

  /** kt:211 — the row is disabled while App dark mode is "Light". */
  private darkModeLocationEnabled(): boolean {
    return this.settings.darkMode !== DarkModeSetting.LIGHT;
  }

  /*
   * Delegates to the ONE implementation in view/settings/PreferenceRow.ets. Five settings pages
   * each carried an identical private copy of this builder and all five had the same defect: no
   * line height, so a section header measured 157 px against the reference's 169.
   */
  @Builder
  sectionHeader(title: string) {
    settingsSectionHeader(title, this.dark)
  }

  /**
   * The "Icon packs" dialog — AppearanceSettingsScreen.kt:246-344.
   *
   * `ResourcesProviderFactory.getProviderList` returns the default provider plus every installed
   * icon pack. CLAUDE.md scopes external packs out, so the list is exactly what Android shows on a
   * device with none installed: one row, the default provider. Its magnifier opens the preview
   * screen (kt:322-338); the row itself would select the pack, which with one provider is a no-op,
   * so it closes the dialog as choosing the already-selected pack does.
   *
   * The "Get more" button is gated on `BuildConfig.ICON_PACKS_LINK` (kt:254) and is absent here for
   * the same reason the packs are.
   */
  @Builder
  iconPackDialog() {
    Column() {
      Column() {
        Text('Icon packs') // strings.xml `settings_icon_packs_title`
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(DIALOG_TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .padding({ left: DIALOG_PADDING, right: DIALOG_PADDING })
          .margin({ top: DIALOG_PADDING, bottom: Dimens.NORMAL_MARGIN })

        Row() {
          Image($r('app.media.startIcon'))
            .width(PROVIDER_ICON_SIZE)
            .height(PROVIDER_ICON_SIZE)
          Text('Breezy Weather') // res_breezy/values/strings.xml `brand_name`
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
            .layoutWeight(1)
            .margin({ left: Dimens.NORMAL_MARGIN })
          Image($r('app.media.ic_search'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .onClick(() => {
              this.dialog = OpenDialog.NONE;
              router.pushUrl({ url: 'pages/PreviewIcon' })
                .catch((error: Error) => {
                  console.error('Icon preview unavailable: ' + error.message);
                });
            })
        }
        .width('100%')
        .height(Dimens.LIST_ITEM_ONE_LINE_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
        .onClick(() => {
          this.dialog = OpenDialog.NONE;
        })

        Row() {
          Blank()
          Text('CLOSE') // strings.xml `action_close`
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .onClick(() => {
              this.dialog = OpenDialog.NONE;
            })
        }
        .width('100%')
        .padding(DIALOG_PADDING)
      }
      .width('80%')
      .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.dark))
      .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
    .onClick(() => {
      this.dialog = OpenDialog.NONE;
    })
  }

  @Builder
  separator(large: boolean) {
    Column()
      .width('100%')
      .height(large ? Dimens.SETTINGS_LARGE_SEPARATOR : Dimens.SETTINGS_SMALL_SEPARATOR)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ---- LargeTopAppBar, as the root settings screen uses ----
        Row() {
          Image($r('app.media.ic_back'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              router.back();
            })

          Blank()

          Image($r('app.media.ic_info'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .margin({ right: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              // AboutActivityIconButton (AppBar.kt:29-31) opens the REAL About screen, on every
              // settings screen that carries the icon - not just the root. Both ports used to send
              // all ten to the placeholder.
              router.pushUrl({ url: 'pages/About' })
                .catch((error: Error) => {
                  console.error('About unavailable: ' + error.message);
                });
            })
        }
        .width('100%')
        .height(APP_BAR_HEIGHT)
        .alignItems(VerticalAlign.Center)

        Text('Appearance') // strings.xml `settings_appearance`
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .maxLines(1)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN, top: Dimens.LARGE_TITLE_TOP_PADDING })
          .height(APP_BAR_EXPANDED_HEIGHT - APP_BAR_HEIGHT)

        Scroll() {
          Column() {
            /* ---- Language and region (kt:112-137) ---- */
            this.sectionHeader('Language and region')

            PreferenceRow({
              title: 'Language',
              summary: 'English',
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              onTap: () => {
                this.dialog = OpenDialog.LANGUAGE;
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Units',
              summary: 'Temperature, precipitation, distance, speed, pressure',
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              onTap: () => {
                router.pushUrl({ url: 'pages/UnitSettings' })
                  .catch((error: Error) => {
                    console.error('Units unavailable: ' + error.message);
                  });
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Alternate calendar',
              summary: calendarSummary(this.settings.alternateCalendar, deviceLanguage(),
                deviceCountry()),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              onTap: () => {
                this.dialog = OpenDialog.ALTERNATE_CALENDAR;
              }
            })

            this.separator(true)

            /* ---- Theme (kt:141-353) ---- */
            this.sectionHeader('Theme')

            PreferenceRow({
              title: 'App dark mode',
              summary: this.darkModeName(),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              onTap: () => {
                this.dialog = OpenDialog.DARK_MODE;
              }
            })
            this.separator(false)

            // Disabled while App dark mode is "Light" — Preference.kt:159's alpha, and no tap.
            PreferenceRow({
              title: 'Location-based dark mode',
              summary: this.darkModeLocationName(),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              onTap: () => {
                if (this.darkModeLocationEnabled()) {
                  this.dialog = OpenDialog.DARK_MODE_LOCATIONS;
                }
              }
            })
              .opacity(this.darkModeLocationEnabled() ? 1.0 : 0.5)
            this.separator(false)

            PreferenceRow({
              title: 'Icon pack',
              summary: 'Default',
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              onTap: () => {
                // kt:238 — the row opens the "Icon packs" dialog, it does not navigate.
                this.dialog = OpenDialog.ICON_PACK;
              }
            })
          }
          .width('100%')
          .padding({
            left: Dimens.NORMAL_MARGIN,
            right: Dimens.NORMAL_MARGIN,
            bottom: Dimens.LARGE_MARGIN
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.SURFACE.resolve(this.dark))
      .padding({
        top: this.insets.top,
        bottom: this.insets.bottom,
        left: this.insets.left,
        right: this.insets.right
      })

      if (this.dialog === OpenDialog.DARK_MODE) {
        ListPreferenceDialog({
          title: 'App dark mode',
          options: this.darkModeOptions(),
          selected: this.settings.darkMode,
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setDarkMode(value).then(() => {
              // The choice re-themes THIS screen as well as the ones behind it.
              this.syncDark();
              this.revision++;
            });
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }

      if (this.dialog === OpenDialog.DARK_MODE_LOCATIONS) {
        ListPreferenceDialog({
          title: 'Location-based dark mode',
          options: this.darkModeLocationOptions(),
          selected: this.darkModeLocationKey(),
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setDayNightForLocations(value === DarkModeLocationSetting.DAY_NIGHT).then(() => {
              this.revision++;
            });
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }

      if (this.dialog === OpenDialog.ICON_PACK) {
        this.iconPackDialog()
      }

      if (this.dialog === OpenDialog.LANGUAGE) {
        ListPreferenceDialog({
          // CLAUDE.md keeps this port English-only, so the list is honest about having one entry
          // rather than offering locales that are not translated.
          title: 'Language',
          options: [new ListPreferenceOption('en', 'English')],
          selected: 'en',
          dark: this.dark,
          onChosen: () => {
            this.dialog = OpenDialog.NONE;
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }

      if (this.dialog === OpenDialog.ALTERNATE_CALENDAR) {
        ListPreferenceDialog({
          title: 'Alternate calendar', // strings.xml settings_appearance_calendar_title
          options: this.calendarDialogOptions(),
          selected: this.settings.alternateCalendar,
          dark: this.dark,
          onChosen: (value: string) => {
            setAlternateCalendar(value).then(() => {
              this.revision++;
            });
            this.dialog = OpenDialog.NONE;
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** The twelve rows, in CalendarHelper's order. */
  private calendarDialogOptions(): ListPreferenceOption[] {
    const options: ListPreferenceOption[] = [];
    calendarOptions(deviceLanguage(), deviceCountry()).forEach((option: CalendarOption) => {
      options.push(new ListPreferenceOption(option.id, option.name));
    });
    return options;
  }
}
