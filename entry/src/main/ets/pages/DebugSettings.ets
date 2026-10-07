/*
 * Screen 3g — Debug. Port of DebugSettingsScreen.kt (:56-190).
 *
 * ONE card with ONE row on a release build: "Share crash logs".
 *
 * The Kotlin's other three sections — force weather update, the two unit-formatting switches and
 * the RefreshErrorType list — are ALL inside `if (BreezyWeather.instance.debugMode)`
 * (kt:122-189), and `debugMode` is `applicationInfo.flags and FLAG_DEBUGGABLE` (BreezyWeather.kt:
 * 72-74) — false on a release APK. Confirmed against the reference device rather than inferred:
 * ref_screen3g_debug.png shows exactly this one row.
 *
 * The permission banner (kt:81-107) is absent for the reason screen 3d's is: it is gated on
 * Android 13's POST_NOTIFICATIONS not being granted, and HarmonyOS has no equivalent runtime grant
 * to be missing.
 *
 * The row's ACTION is not ported. CrashLogUtils.dumpLogs (kt:117) shells out to logcat and hands
 * the file to a FileProvider share sheet; neither has a HarmonyOS equivalent an app can reach for
 * its own faultlogs. Per CLAUDE.md a handler that leads somewhere unported goes to the placeholder
 * carrying its name, which is what it does — never hidden, never a crash.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow } from '../view/settings/PreferenceRow';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

@Entry
@ComponentV2
struct DebugSettings {
  private insets: SystemInsets = SystemInsets.instance;

  @Local private dark: boolean = false;

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

  build() {
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

      Text('Debug') // strings.xml:858 `settings_debug`
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
          PreferenceRow({
            title: 'Share crash logs', // strings.xml:862
            summary: 'Saves error logs to a file for sharing with the developers', // :863
            icon: null,
            dark: this.dark,
            isFirst: true,
            isLast: true,
            onTap: () => {
              goPlaceholder('Share crash logs');
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
  }
}
