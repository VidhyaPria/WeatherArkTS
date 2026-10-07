/*
 * Screen 3c — Main screen. Port of MainScreenSettingsScreen.kt (:55-256).
 *
 * THREE sections, each its own card group:
 *
 *   Displayed data   Blocks | Daily trends | Hourly trends
 *   Options          Weather-based background | Threshold lines on charts
 *   Animations       Background animation | Gravity sensor | Blocks fade in |
 *                    Other element animations
 *
 * WHAT IS REAL HERE:
 *
 *   the four switches and the animation mode   real — stored under SettingsManager's own keys
 *   Blocks / Daily trends / Hourly trends      each opens a MANAGE screen (a drag-to-reorder list,
 *                                              kt:90-120 IntentHelper.start*ManageActivity) that is
 *                                              its own screen in the migration order and is not
 *                                              ported, so each goes to the placeholder carrying its
 *                                              name. Their SUMMARIES are real — the list of what is
 *                                              displayed, exactly as CardDisplay.getSummary and its
 *                                              siblings build it.
 *
 * The Kotlin follows four of these changes with a "changes apply after restart" snackbar and a
 * Restart action (kt:151-157, :178-184, :197-203). That is not ported: `recreateAllActivities` has
 * no HarmonyOS equivalent, and offering a restart button that cannot restart would be worse than
 * saying nothing. The settings themselves are stored correctly either way.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow, settingsSectionHeader } from '../view/settings/PreferenceRow';
import { ListPreferenceDialog, ListPreferenceOption } from '../view/settings/ListPreferenceDialog';
import { SystemInsets } from '../common/SystemBars';
import {
  AppSettings,
  appIsDark,
  MAIN_KEY_BACKGROUND,
  MAIN_KEY_ELEMENTS,
  MAIN_KEY_FADE_IN,
  MAIN_KEY_GRAVITY,
  MAIN_KEY_TREND_LINES,
  setBackgroundAnimation,
  setMainScreenFlag,
  displayListValue
} from '../data/SettingsStore';
import {
  DisplayList,
  displayListSummary,
  keyFor,
  parseDisplayList
} from '../model/DisplayCatalogue';
import { DisplayManageParams } from './DisplayManage';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
/** SectionHeader: bodyMedium, SemiBold, primary, padded normal_margin (Section.kt:31-46). */
const SECTION_TEXT_SIZE: number = 14;

/** strings.xml `settings_enabled` / `settings_disabled` — the summary of every switch row. */
const ENABLED: string = 'Enabled';
const DISABLED: string = 'Disabled';

/**
 * The three summaries are `getSummary(context, list)` (CardDisplay.kt:78-82) — the STORED list's
 * names joined by `locale_separator`, which is ", " in English.
 *
 * These used to be constants, because the manage screens were not ported and so the lists could not
 * differ from their defaults. They are ported now, so the summaries read what is stored.
 */
function summaryOf(list: DisplayList): string {
  return displayListSummary(parseDisplayList(list, displayListValue(list)));
}

/** Opens one of the three manage screens (kt:90-120, IntentHelper.start*ManageActivity). */
function openManage(list: DisplayList): void {
  const params = new DisplayManageParams();
  params.which = keyFor(list);
  router.pushUrl({ url: 'pages/DisplayManage', params: params })
    .catch((error: Error) => {
      console.error('could not open ' + params.which + ': ' + error.message);
    });
}

/** Which dialog is up, if any. */
enum OpenDialog {
  NONE = 0,
  BACKGROUND_ANIMATION = 1
}

@Entry
@ComponentV2
struct MainScreenSettings {
  private insets: SystemInsets = SystemInsets.instance;
  /** Read directly in the build, so a write re-labels the row that made it. */
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  @Local private dialog: number = OpenDialog.NONE;
  /**
   * Bumped after a write and read in every summary — the same reason the Units screen has one.
   * A @Trace field on `AppSettings` read through a helper registers no dependency; a @Local read
   * in a helper does.
   */
  @Local private revision: number = 0;

  aboutToAppear(): void {
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
    // Coming back from a manage screen: the three summaries read plain functions, so nothing here
    // is subscribed to the list changing. The revision bump is what re-runs them.
    this.revision++;
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  /* ------------------------------------------------------------------------ summaries -------- */

  /** Reads `revision` for the subscription; see the field. */
  private stamp(): boolean {
    return this.revision >= 0;
  }

  private onOff(value: boolean): string {
    return this.stamp() && value ? ENABLED : DISABLED;
  }

  /** background_animation_values / background_animation (arrays.xml). */
  private animationOptions(): ListPreferenceOption[] {
    return [
      new ListPreferenceOption('system', 'Follow system'),
      new ListPreferenceOption('enabled', ENABLED),
      new ListPreferenceOption('disabled', DISABLED)
    ];
  }

  private animationName(): string {
    const options: ListPreferenceOption[] = this.animationOptions();
    for (let i = 0; i < options.length; i++) {
      if (this.stamp() && options[i].value === this.settings.backgroundAnimation) {
        return options[i].name;
      }
    }
    return options[0].name;
  }

  /** Delegates to the ONE implementation in view/settings/PreferenceRow.ets. */
  @Builder
  sectionHeader(title: string) {
    settingsSectionHeader(title, this.dark)
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
        // ---- LargeTopAppBar, as every other screen-3 page uses ----
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

        Text('Main screen') // strings.xml `settings_main`
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
            /* ---- Displayed data (kt:81-122) ---- */
            this.sectionHeader('Displayed data')

            PreferenceRow({
              title: 'Blocks',
              summary: this.stamp() ? summaryOf(DisplayList.BLOCKS) : '',
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              onTap: () => {
                openManage(DisplayList.BLOCKS);
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Daily trends',
              summary: this.stamp() ? summaryOf(DisplayList.DAILY) : '',
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              onTap: () => {
                openManage(DisplayList.DAILY);
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Hourly trends',
              summary: this.stamp() ? summaryOf(DisplayList.HOURLY) : '',
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              onTap: () => {
                openManage(DisplayList.HOURLY);
              }
            })

            this.separator(true)

            /* ---- Options (kt:126-160) ---- */
            this.sectionHeader('Options')

            PreferenceRow({
              title: 'Weather-based background',
              summary: this.onOff(this.settings.mainScreenBackground),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              showSwitch: true,
              checked: this.settings.mainScreenBackground,
              onToggle: (value: boolean) => {
                setMainScreenFlag(MAIN_KEY_BACKGROUND, value).then(() => {
                  this.revision++;
                });
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Threshold lines on charts',
              summary: this.onOff(this.settings.trendHorizontalLines),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              showSwitch: true,
              checked: this.settings.trendHorizontalLines,
              onToggle: (value: boolean) => {
                setMainScreenFlag(MAIN_KEY_TREND_LINES, value).then(() => {
                  this.revision++;
                });
              }
            })

            this.separator(true)

            /* ---- Animations (kt:164-254) ---- */
            this.sectionHeader('Animations')

            PreferenceRow({
              title: 'Background animation',
              summary: this.animationName(),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              onTap: () => {
                this.dialog = OpenDialog.BACKGROUND_ANIMATION;
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Gravity sensor',
              summary: this.onOff(this.settings.gravitySensor),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              showSwitch: true,
              checked: this.settings.gravitySensor,
              onToggle: (value: boolean) => {
                setMainScreenFlag(MAIN_KEY_GRAVITY, value).then(() => {
                  this.revision++;
                });
              }
            })
            this.separator(false)

            /*
             * kt:208-228 — both of the remaining switches are DISABLED when the system has
             * animations turned off, and then read "Unavailable, enable animations in Android
             * settings first" whatever is stored. HarmonyOS exposes no equivalent of
             * `context.isMotionReduced`, so `animationsEnabled` is unconditionally true here and
             * the rows are always live. Flagged rather than faked: the alternative is a row that
             * claims a system state this port cannot read.
             */
            PreferenceRow({
              title: 'Blocks fade in',
              summary: this.onOff(this.settings.cardsFadeIn),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              showSwitch: true,
              checked: this.settings.cardsFadeIn,
              onToggle: (value: boolean) => {
                setMainScreenFlag(MAIN_KEY_FADE_IN, value).then(() => {
                  this.revision++;
                });
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Other element animations',
              summary: this.onOff(this.settings.elementAnimations),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              showSwitch: true,
              checked: this.settings.elementAnimations,
              onToggle: (value: boolean) => {
                setMainScreenFlag(MAIN_KEY_ELEMENTS, value).then(() => {
                  this.revision++;
                });
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

      if (this.dialog === OpenDialog.BACKGROUND_ANIMATION) {
        ListPreferenceDialog({
          title: 'Background animation',
          options: this.animationOptions(),
          selected: this.settings.backgroundAnimation,
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setBackgroundAnimation(value).then(() => {
              this.revision++;
            });
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
}
