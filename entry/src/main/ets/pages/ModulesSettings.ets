/*
 * Screen 3e — External modules. Port of ModulesSettingsScreen.kt (:104-380).
 *
 *   General             Live wallpaper | Icon to display in weekly views | Monochrome icons
 *   Widgets in use      CONDITIONAL — one row per widget actually placed (kt:189-242)
 *   Notification widget Notification widget | Persistent | Style | Temperature as status bar icon
 *                       | Use feels like temperature
 *   Data sharing        one row per broadcast source (kt:363-378)
 *
 * WHAT IS REAL HERE, AND WHAT IS NOT:
 *
 * Every module this screen configures — home-screen widgets, the live wallpaper, the notification
 * widget, broadcast data sharing — is on CLAUDE.md's skip list. The SCREEN is still ported and its
 * values are still stored, for exactly the reason the source catalogue is ported without its
 * clients: the settings list is what Android renders, and dropping rows would be inventing a
 * different screen. So the switches and pickers are REAL — they store, they persist, they redraw —
 * and only the things that would reach outside the app are placeheld:
 *
 *   Live wallpaper   `WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER` (kt:126-152). HarmonyOS has
 *                    no live wallpaper an app can offer, so the row goes to the placeholder.
 *   Widgets in use   the section is CONDITIONAL on widgets being placed (kt:189-224 builds the list
 *                    from AppWidgetManager). This port places none, so the list is empty and the
 *                    whole section is absent — which is also what the reference shows on a device
 *                    with no widgets, confirmed by dumping it.
 *   Notification     the notification-permission row (kt:250-276) is gated on Android 13's
 *   permission      POST_NOTIFICATIONS not being granted; HarmonyOS has no equivalent runtime grant
 *                    to be missing, so it is absent for the same reason screen 3d's banner is.
 *
 * The Data sharing rows are MultiListPreferences over the INSTALLED packages that declare each
 * source's intent action (kt:365-372). With none installed the list is empty and the row reads
 * "Disabled" — what the reference shows, and what a HarmonyOS device will always show.
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
  BROADCAST_SOURCE_IDS,
  BROADCAST_SOURCE_NAMES,
  setModuleSetting
} from '../data/SettingsStore';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

/** SettingsManager's key names, so the row and the store agree without a translation table. */
const KEY_WEEK_ICON_MODE: string = 'week_icon_mode';
const KEY_MONOCHROME_ICONS: string = 'widget_monochrome_icons';
const KEY_NOTIFICATION_WIDGET: string = 'notification_widget_switch';
const KEY_NOTIFICATION_PERSISTENT: string = 'notification_widget_persistent_switch';
const KEY_NOTIFICATION_STYLE: string = 'notification_widget_style';
const KEY_NOTIFICATION_TEMP_ICON: string = 'notification_widget_temp_icon_switch';
const KEY_NOTIFICATION_FEELS_LIKE: string = 'notification_widget_feels_like';
const KEY_BROADCAST_PREFIX: string = 'broadcast_packages_';

/** arrays.xml `week_icon_modes` / `week_icon_mode_values`. */
const WEEK_ICON_MODES: ListPreferenceOption[] = [
  new ListPreferenceOption('auto', 'Day / Night'), // settings_color_day_night
  new ListPreferenceOption('day', 'Always day'), // settings_color_day_always
  new ListPreferenceOption('night', 'Always night') // settings_color_night_always
];

/** arrays.xml `notification_styles` / `notification_style_values`. */
const NOTIFICATION_STYLES: ListPreferenceOption[] = [
  new ListPreferenceOption('native', 'Native'), // notification_style_native
  new ListPreferenceOption('cities', 'Cities'), // notification_style_cities
  new ListPreferenceOption('daily', 'Daily forecast'), // daily_forecast
  new ListPreferenceOption('hourly', 'Hourly forecast') // hourly_forecast
];

enum OpenDialog {
  NONE = 0,
  WEEK_ICON_MODE = 1,
  NOTIFICATION_STYLE = 2
}

@Entry
@ComponentV2
struct ModulesSettings {
  private insets: SystemInsets = SystemInsets.instance;
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  @Local private dialog: number = OpenDialog.NONE;

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

  /** `settings_enabled` / `settings_disabled` — every switch row's summary. */
  private onOff(value: boolean): string {
    return value ? 'Enabled' : 'Disabled';
  }

  private nameFor(options: ListPreferenceOption[], value: string): string {
    for (const option of options) {
      if (option.value === value) {
        return option.name;
      }
    }
    return options.length > 0 ? options[0].name : '';
  }

  /**
   * kt:283-296 — the four rows below the master switch are DISABLED while the notification widget
   * itself is off, and `Persistent` additionally needs it on to mean anything.
   */
  private notificationRowsEnabled(): boolean {
    return this.settings.notificationWidget;
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

        Text('External modules') // strings.xml settings_modules
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
            /* ---- General (kt:119-187) ---- */
            settingsSectionHeader('General', this.dark) // settings_section_general

            PreferenceRow({
              title: 'Live wallpaper',
              summary: 'Set a weather animation as wallpaper',
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              onTap: () => {
                // kt:126-152 — ACTION_CHANGE_LIVE_WALLPAPER. No HarmonyOS equivalent.
                goPlaceholder('Live wallpaper');
              }
            })
            this.separator()

            PreferenceRow({
              title: 'Icon to display in weekly views',
              summary: this.nameFor(WEEK_ICON_MODES, this.settings.weekIconMode),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              onTap: () => {
                this.dialog = OpenDialog.WEEK_ICON_MODE;
              }
            })
            this.separator()

            PreferenceRow({
              title: 'Monochrome icons',
              summary: this.onOff(this.settings.monochromeIcons),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              checked: this.settings.monochromeIcons,
              showSwitch: true,
              onToggle: (value: boolean) => {
                setModuleSetting(KEY_MONOCHROME_ICONS, value);
              }
            })

            /*
             * "Widgets in use" (kt:189-242) is absent: the section only exists when
             * AppWidgetManager reports a placed widget, and this port places none. The reference
             * omits it too on a device with no widgets — confirmed by dumping that screen.
             */

            this.largeSeparator()

            /* ---- Notification widget (kt:248-361) ---- */
            settingsSectionHeader('Notification widget', this.dark)

            PreferenceRow({
              title: 'Notification widget',
              summary: this.onOff(this.settings.notificationWidget),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              checked: this.settings.notificationWidget,
              showSwitch: true,
              onToggle: (value: boolean) => {
                setModuleSetting(KEY_NOTIFICATION_WIDGET, value);
              }
            })
            this.separator()

            PreferenceRow({
              title: 'Persistent',
              summary: this.onOff(this.settings.notificationPersistent),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              rowEnabled: this.notificationRowsEnabled(),
              checked: this.settings.notificationPersistent,
              showSwitch: true,
              onToggle: (value: boolean) => {
                setModuleSetting(KEY_NOTIFICATION_PERSISTENT, value);
              }
            })
            this.separator()

            PreferenceRow({
              title: 'Style',
              summary: this.nameFor(NOTIFICATION_STYLES, this.settings.notificationStyle),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              rowEnabled: this.notificationRowsEnabled(),
              onTap: () => {
                if (this.notificationRowsEnabled()) {
                  this.dialog = OpenDialog.NOTIFICATION_STYLE;
                }
              }
            })
            this.separator()

            PreferenceRow({
              title: 'Temperature as status bar icon',
              summary: this.onOff(this.settings.notificationTempIcon),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              rowEnabled: this.notificationRowsEnabled(),
              checked: this.settings.notificationTempIcon,
              showSwitch: true,
              onToggle: (value: boolean) => {
                setModuleSetting(KEY_NOTIFICATION_TEMP_ICON, value);
              }
            })
            this.separator()

            PreferenceRow({
              title: 'Use feels like temperature',
              summary: this.onOff(this.settings.notificationFeelsLike),
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              rowEnabled: this.notificationRowsEnabled(),
              checked: this.settings.notificationFeelsLike,
              showSwitch: true,
              onToggle: (value: boolean) => {
                setModuleSetting(KEY_NOTIFICATION_FEELS_LIKE, value);
              }
            })

            this.largeSeparator()

            /* ---- Data sharing (kt:363-378) ---- */
            settingsSectionHeader('Data sharing', this.dark) // settings_modules_broadcast_title

            ForEach(BROADCAST_SOURCE_IDS, (id: string, index: number) => {
              PreferenceRow({
                // strings.xml `settings_modules_broadcast_send_data_title` = "Send %s data"
                title: 'Send ' + BROADCAST_SOURCE_NAMES[index] + ' data',
                summary: this.broadcastSummary(id),
                icon: null,
                dark: this.dark,
                isFirst: index === 0,
                isLast: index === BROADCAST_SOURCE_IDS.length - 1,
                onTap: () => {
                  /*
                   * A MultiListPreference over the INSTALLED packages that declare the source's
                   * intent action (kt:365-372). On HarmonyOS none can be, so the list is always
                   * empty — the row shows "Disabled" and opens nothing, which is what the
                   * reference does with an empty list rather than showing an empty dialog.
                   */
                  goPlaceholder('Send ' + BROADCAST_SOURCE_NAMES[index] + ' data');
                }
              })
              if (index < BROADCAST_SOURCE_IDS.length - 1) {
                this.separator()
              }
            }, (id: string) => id)

            Column().width('100%').height(Dimens.LARGE_MARGIN + this.insets.bottom)
          }
          .width('100%')
          .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.SURFACE.resolve(this.dark))
      .padding({ top: this.insets.top, left: this.insets.left, right: this.insets.right })

      if (this.dialog === OpenDialog.WEEK_ICON_MODE) {
        ListPreferenceDialog({
          title: 'Icon to display in weekly views',
          options: WEEK_ICON_MODES,
          selected: this.settings.weekIconMode,
          dark: this.dark,
          onChosen: (value: string) => {
            setModuleSetting(KEY_WEEK_ICON_MODE, value);
            this.dialog = OpenDialog.NONE;
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      } else if (this.dialog === OpenDialog.NOTIFICATION_STYLE) {
        ListPreferenceDialog({
          title: 'Style',
          options: NOTIFICATION_STYLES,
          selected: this.settings.notificationStyle,
          dark: this.dark,
          onChosen: (value: string) => {
            setModuleSetting(KEY_NOTIFICATION_STYLE, value);
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

  /** kt:365-372 — the row reads its enabled package list; empty is "Disabled". */
  private broadcastSummary(id: string): string {
    const packages: string | undefined = this.settings.broadcastPackages.get(id);
    return packages !== undefined && packages.length > 0 ? 'Enabled' : 'Disabled';
  }

  @Builder
  private separator() {
    Column()
      .width('100%')
      .height(Dimens.SETTINGS_SMALL_SEPARATOR)
  }

  @Builder
  private largeSeparator() {
    Column()
      .width('100%')
      .height(Dimens.SETTINGS_LARGE_SEPARATOR)
  }
}
