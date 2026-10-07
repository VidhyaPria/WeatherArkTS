/*
 * Screen 3c — Background updates. Port of BackgroundUpdatesSettingsScreen.kt (:80-299).
 *
 * TWO sections:
 *   General       Refresh rate            a list preference over UpdateInterval's nine values
 *                 Skip when battery is low a switch, DISABLED while the rate is "Never" (kt:224)
 *   Troubleshoot  Disable battery optimization
 *                 Manufacturer specific instructions
 *                 Worker info              summary is "Last run: <yyyy-MM-dd HH:mm>", or absent
 *
 * What the rows DO differs from Android, and each difference is forced rather than chosen:
 *
 *   - Android follows every write with `WeatherUpdateJob.setupTask(context)`, which reschedules a
 *     WorkManager job. CLAUDE.md skips background refresh, so this port stores the value and
 *     nothing schedules anything. The refresh rate is still LIVE: `Weather.isValid` measures the
 *     stored forecast against it, so it decides whether selecting a location refetches at all.
 *   - "Disable battery optimization" launches `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
 *     (kt:246-252). HarmonyOS has no equivalent intent an app can fire for itself.
 *   - "Manufacturer specific instructions" opens https://dontkillmyapp.com/ (kt:273) — a browser
 *     the shell owns, not this page.
 *   - "Worker info" starts `WorkerInfoActivity` (kt:291), which is not ported.
 *
 * Per CLAUDE.md a handler that leads somewhere unported goes to the placeholder carrying its
 * name — never hidden, never a crash. All three do.
 *
 * The "Never" confirmation dialog (kt:139-215) IS ported: three paragraphs of warning and a
 * Continue button that stays disabled for ten seconds while a counter runs down in its label.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY, LineHeights } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow, settingsSectionHeader } from '../view/settings/PreferenceRow';
import { ListPreferenceDialog, ListPreferenceOption } from '../view/settings/ListPreferenceDialog';
import { SystemInsets } from '../common/SystemBars';
import {
  AppSettings,
  appIsDark,
  setRefreshRate,
  setSkipWhenBatteryLow,
  UPDATE_INTERVAL_NAMES,
  UPDATE_INTERVAL_NEVER,
  UPDATE_INTERVALS,
  updateIntervalName
} from '../data/SettingsStore';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

/** kt:140 — the Continue button is dead for ten seconds. */
const NEVER_COUNTDOWN_SECONDS: number = 10;
/** kt:163 — the "%d MB" the second warning paragraph is formatted with. */
const NEVER_WARNING_MEGABYTES: number = 5;

/* strings.xml — the three warning paragraphs, verbatim. */
const NEVER_WARNING_1: string =
  'By turning off background updates, you will no longer receive notifications of alerts or ' +
  'precipitation. Widgets won’t be refreshed until you open the app.';
const NEVER_WARNING_2: string =
  'The background update process is lightweight: it only refreshes your first location at your ' +
  'select rate, and secondary locations only if you need them, once a day. It’s battery-efficient ' +
  'and should not exceed ' + NEVER_WARNING_MEGABYTES.toString() + ' MB of data consumption a month.';
const NEVER_WARNING_3: string =
  'Consider using a less frequent refresh rate rather than turning off background updates, ' +
  'otherwise tap “Continue” if you still want to proceed.';

@Entry
@ComponentV2
struct BackgroundUpdatesSettings {
  private insets: SystemInsets = SystemInsets.instance;
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  @Local private rateDialogOpen: boolean = false;
  /** The "are you sure" sheet the Never option opens instead of committing (kt:129-131). */
  @Local private neverDialogOpen: boolean = false;
  @Local private countdown: number = NEVER_COUNTDOWN_SECONDS;
  private countdownTimer: number = -1;

  aboutToAppear(): void {
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
  }

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  private rateOptions(): ListPreferenceOption[] {
    const out: ListPreferenceOption[] = [];
    for (let i = 0; i < UPDATE_INTERVALS.length; i++) {
      out.push(new ListPreferenceOption(UPDATE_INTERVALS[i], UPDATE_INTERVAL_NAMES[i]));
    }
    return out;
  }

  /** kt:141-146 — one tick a second until it reaches zero, then the button comes alive. */
  private startCountdown(): void {
    this.stopCountdown();
    this.countdown = NEVER_COUNTDOWN_SECONDS;
    this.countdownTimer = setInterval(() => {
      if (this.countdown > 0) {
        this.countdown = this.countdown - 1;
      }
      if (this.countdown <= 0) {
        this.stopCountdown();
      }
    }, 1000);
  }

  private stopCountdown(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  build() {
    Stack() {
      Column() {
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

        Text('Background updates') // strings.xml settings_background_updates
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .maxLines(1)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({
            left: Dimens.NORMAL_MARGIN,
            right: Dimens.NORMAL_MARGIN,
            top: Dimens.LARGE_TITLE_TOP_PADDING
          })
          .height(APP_BAR_EXPANDED_HEIGHT - APP_BAR_HEIGHT)

        Scroll() {
          Column() {
            settingsSectionHeader('General', this.dark) // strings.xml settings_section_general

            PreferenceRow({
              title: 'Refresh rate', // settings_background_updates_refresh_title
              summary: updateIntervalName(this.settings.refreshRate),
              icon: null,
              dark: this.dark,
              isFirst: true,
              onTap: () => {
                this.rateDialogOpen = true;
              }
            })

            Blank().height(Dimens.SETTINGS_SMALL_SEPARATOR)

            PreferenceRow({
              // kt:224 — the switch is dead while nothing is scheduled to skip.
              title: 'Skip when battery is low',
              summary: this.settings.skipWhenBatteryLow ? 'Enabled' : 'Disabled',
              icon: null,
              dark: this.dark,
              isLast: true,
              showSwitch: true,
              checked: this.settings.skipWhenBatteryLow,
              rowEnabled: this.settings.refreshRate !== UPDATE_INTERVAL_NEVER,
              onToggle: (value: boolean) => {
                setSkipWhenBatteryLow(value);
              }
            })

            Blank().height(Dimens.SETTINGS_LARGE_SEPARATOR)

            settingsSectionHeader('Troubleshoot', this.dark)

            PreferenceRow({
              title: 'Disable battery optimization',
              summary: 'This is the first thing to try when you don’t receive notifications or ' +
                'widgets are not refreshing.',
              icon: null,
              dark: this.dark,
              isFirst: true,
              onTap: () => {
                goPlaceholder('Disable battery optimization');
              }
            })

            Blank().height(Dimens.SETTINGS_SMALL_SEPARATOR)

            PreferenceRow({
              title: 'Manufacturer specific instructions',
              summary: 'Some manufacturers have additional app restrictions that kill background ' +
                'services. The Don’t kill my app! website has info on how to fix it.',
              icon: null,
              dark: this.dark,
              onTap: () => {
                goPlaceholder('Manufacturer specific instructions');
              }
            })

            Blank().height(Dimens.SETTINGS_SMALL_SEPARATOR)

            PreferenceRow({
              title: 'Worker info',
              /*
               * kt:280-288 — the summary is present only when a background run has happened, and
               * this port never schedules one, so it is always absent. Android shows the same
               * empty row on a device that has never run the job.
               */
              summary: '',
              icon: null,
              dark: this.dark,
              isLast: true,
              onTap: () => {
                router.pushUrl({ url: 'pages/WorkerInfo' })
                  .catch((error: Error) => {
                    console.error('Worker info unavailable: ' + error.message);
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

      if (this.rateDialogOpen) {
        ListPreferenceDialog({
          title: 'Refresh rate',
          options: this.rateOptions(),
          selected: this.settings.refreshRate,
          dark: this.dark,
          onChosen: (value: string) => {
            this.rateDialogOpen = false;
            // kt:128-136 — "Never" asks first; everything else commits on the tap.
            if (value === UPDATE_INTERVAL_NEVER) {
              this.neverDialogOpen = true;
              this.startCountdown();
              return;
            }
            setRefreshRate(value);
          },
          onDismiss: () => {
            this.rateDialogOpen = false;
          }
        })
      }

      if (this.neverDialogOpen) {
        this.neverWarning()
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }

  /** The AlertDialog at kt:147-214 — three bodyMedium paragraphs, Cancel, and a timed Continue. */
  @Builder
  private neverWarning() {
    Column() {
      Column({ space: Dimens.NORMAL_MARGIN }) {
        ForEach([NEVER_WARNING_1, NEVER_WARNING_2, NEVER_WARNING_3], (paragraph: string) => {
          Text(paragraph)
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
            .lineHeight(LineHeights.BODY_MEDIUM)
            .width('100%')
        }, (paragraph: string) => paragraph.substring(0, 24))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: Dimens.SMALL_MARGIN }) {
        Blank()
        Text('Cancel')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(AppColors.PRIMARY.resolve(this.dark))
          .padding(Dimens.SMALL_MARGIN)
          .onClick(() => {
            this.stopCountdown();
            this.neverDialogOpen = false;
          })
        // kt:188-196 — the label carries the seconds left while the button is dead.
        Text(this.countdown > 0 ? 'Continue (' + this.countdown.toString() + ')' : 'Continue')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(this.countdown > 0
            ? AppColors.ON_SURFACE_VARIANT.resolve(this.dark)
            : AppColors.PRIMARY.resolve(this.dark))
          .padding(Dimens.SMALL_MARGIN)
          .onClick(() => {
            if (this.countdown > 0) {
              return;
            }
            this.stopCountdown();
            this.neverDialogOpen = false;
            setRefreshRate(UPDATE_INTERVAL_NEVER);
          })
      }
      .width('100%')
      .margin({ top: Dimens.NORMAL_MARGIN })
    }
    .width('80%')
    .padding(Dimens.LARGE_MARGIN)
    .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.dark))
    .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
  }
}
