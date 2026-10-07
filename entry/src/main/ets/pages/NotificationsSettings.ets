/*
 * Screen 3d — Notifications. Port of NotificationsSettingsScreen.kt (:55-239).
 *
 * TWO sections, each its own card group:
 *
 *   General   Notifications of severe weather alerts | Notifications of precipitations
 *   Forecast  Notification for the day's forecast | its time |
 *             Notification for next-day forecast | its time
 *
 * WHAT IS REAL HERE:
 *
 *   the four switches and the two times   real — stored under SettingsManager's own keys, with its
 *                                         own per-key defaults (see SettingsStore).
 *   the notification jobs behind them     NOT ported. CLAUDE.md skips background refresh entirely,
 *                                         and TodayForecastNotificationJob / the alert and
 *                                         precipitation pushes are exactly that. This is the same
 *                                         treatment the weather sources get: the screen and its
 *                                         settings are ported, the client behind them is not.
 *
 * ONE section of the Kotlin is deliberately absent:
 *
 *   the permission banner (kt:81-107)   gated on SDK >= TIRAMISU and on POST_NOTIFICATIONS not
 *                                       being granted. HarmonyOS has no equivalent runtime
 *                                       notification permission to be missing — enabling
 *                                       notifications is a user action in system settings, not a
 *                                       grant this app can request — so the banner has no state to
 *                                       show. With nothing to grant, `hasNotificationPermission` is
 *                                       effectively always true and every row below is live, which
 *                                       is what the `enabled =` arguments reduce to.
 *
 * The App updates section (kt:109-126) IS present. Reading the source alone argues otherwise — it
 * is gated on BreezyWeather.isGitHubUpdateCheckerEnabled, which needs BuildConfig.GITHUB_ORG and
 * GITHUB_REPO, and those come from a properties file absent from the tree (build.gradle.kts:
 * 193-209). The reference APK was built WITH them and does render the section, which a screenshot
 * of the device settled. Sourced from the build, not from the source.
 *
 * The two General rows are disabled, and re-summarised, when the background update interval is
 * "never" (kt:135-145). That interval belongs to the Background updates screen, which is not ported
 * yet; nothing writes it, and its default is "1:30", so the rows are live. The conditional is
 * ported anyway so that porting that screen needs no change here.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow, settingsSectionHeader } from '../view/settings/PreferenceRow';
import { formatTimeForDisplay, TimePickerDialog } from '../view/settings/TimePickerDialog';
import { SystemInsets } from '../common/SystemBars';
import {
  AppSettings,
  appIsDark,
  NOTIF_KEY_ALERT,
  NOTIF_KEY_APP_UPDATES,
  NOTIF_KEY_PRECIPITATION,
  NOTIF_KEY_TODAY,
  NOTIF_KEY_TOMORROW,
  setForecastTime,
  setNotificationFlag,
  UPDATE_INTERVAL_NEVER
} from '../data/SettingsStore';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
const SECTION_TEXT_SIZE: number = 14;

const ENABLED: string = 'Enabled';
const DISABLED: string = 'Disabled';
/** strings.xml:877 — the summary a General row shows when background updates are off. */
const NO_BACKGROUND_UPDATES: string = 'Unavailable, enable background updates first';

/** Which time picker is up, if any. */
enum OpenDialog {
  NONE = 0,
  TODAY_TIME = 1,
  TOMORROW_TIME = 2
}

@Entry
@ComponentV2
struct NotificationsSettings {
  private insets: SystemInsets = SystemInsets.instance;
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  @Local private dialog: number = OpenDialog.NONE;
  /** Bumped after a write and read in every summary — see MainScreenSettings.revision. */
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

  /* ------------------------------------------------------------------------ summaries -------- */

  private stamp(): boolean {
    return this.revision >= 0;
  }

  /** kt:143-145 — background updates off makes both General rows dead. */
  private backgroundUpdatesOn(): boolean {
    return this.stamp() && this.settings.refreshRate !== UPDATE_INTERVAL_NEVER;
  }

  private onOff(value: boolean): string {
    return this.stamp() && value ? ENABLED : DISABLED;
  }

  /**
   * kt:135-141 — the OFF summary is the "enable background updates first" line rather than plain
   * "Disabled" when the interval is never. The ON summary is unconditional, because the checked
   * state is itself ANDed with the interval (kt:142-143), so a row that reads "Enabled" is always
   * a row whose updates can actually run.
   */
  private generalSummary(value: boolean): string {
    if (this.backgroundUpdatesOn()) {
      return this.onOff(value);
    }
    return NO_BACKGROUND_UPDATES;
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

        Text('Notifications') // strings.xml:819 `settings_notifications`
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
            /* ---- App updates (kt:109-126) ---- */
            this.sectionHeader('App updates') // strings.xml:900 `notification_channel_app_updates`

            PreferenceRow({
              title: 'Notifications of app updates', // strings.xml:821
              summary: this.onOff(this.settings.appUpdateCheck),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: true,
              showSwitch: true,
              checked: this.settings.appUpdateCheck,
              onToggle: (value: boolean) => {
                setNotificationFlag(NOTIF_KEY_APP_UPDATES, value).then(() => {
                  this.revision++;
                });
              }
            })

            this.separator(true)

            /* ---- General (kt:130-174) ---- */
            this.sectionHeader('General') // settings_notifications_section_general → settings_section_general

            PreferenceRow({
              title: 'Notifications of severe weather alerts', // strings.xml:827
              summary: this.generalSummary(this.settings.alertNotification),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              showSwitch: true,
              // kt:142-143 — the stored flag ANDed with the interval, so the switch cannot read
              // "on" while nothing can deliver it.
              checked: this.settings.alertNotification && this.backgroundUpdatesOn(),
              rowEnabled: this.backgroundUpdatesOn(),
              onToggle: (value: boolean) => {
                setNotificationFlag(NOTIF_KEY_ALERT, value).then(() => {
                  this.revision++;
                });
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Notifications of precipitations', // strings.xml:828
              summary: this.generalSummary(this.settings.precipitationNotification),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              showSwitch: true,
              checked: this.settings.precipitationNotification && this.backgroundUpdatesOn(),
              rowEnabled: this.backgroundUpdatesOn(),
              onToggle: (value: boolean) => {
                setNotificationFlag(NOTIF_KEY_PRECIPITATION, value).then(() => {
                  this.revision++;
                });
              }
            })

            this.separator(true)

            /* ---- Forecast (kt:178-234) ---- */
            this.sectionHeader('Forecast') // strings.xml:829

            PreferenceRow({
              title: 'Notification for the day’s forecast', // strings.xml:830
              summary: this.onOff(this.settings.todayForecast),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              showSwitch: true,
              checked: this.settings.todayForecast,
              onToggle: (value: boolean) => {
                setNotificationFlag(NOTIF_KEY_TODAY, value).then(() => {
                  this.revision++;
                });
              }
            })
            this.separator(false)

            // kt:195-205 — the time row is live only while its own switch is on.
            PreferenceRow({
              title: 'Notification time for the day’s forecast', // strings.xml:831
              // kt:134 — the row shows the LOCALISED time, not the stored "HH:mm".
              summary: this.stamp() ? formatTimeForDisplay(this.settings.todayForecastTime) : '',
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              rowEnabled: this.settings.todayForecast,
              onTap: () => {
                this.dialog = OpenDialog.TODAY_TIME;
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Notification for next-day forecast', // strings.xml:832
              summary: this.onOff(this.settings.tomorrowForecast),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              showSwitch: true,
              checked: this.settings.tomorrowForecast,
              onToggle: (value: boolean) => {
                setNotificationFlag(NOTIF_KEY_TOMORROW, value).then(() => {
                  this.revision++;
                });
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Notification time for next-day forecast', // strings.xml:833
              summary: this.stamp() ? formatTimeForDisplay(this.settings.tomorrowForecastTime) : '',
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              rowEnabled: this.settings.tomorrowForecast,
              onTap: () => {
                this.dialog = OpenDialog.TOMORROW_TIME;
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

      if (this.dialog === OpenDialog.TODAY_TIME) {
        TimePickerDialog({
          selected: this.settings.todayForecastTime,
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setForecastTime(true, value).then(() => {
              this.revision++;
            });
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }

      if (this.dialog === OpenDialog.TOMORROW_TIME) {
        TimePickerDialog({
          selected: this.settings.tomorrowForecastTime,
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setForecastTime(false, value).then(() => {
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
