/*
 * Screen 3e — Location. Port of LocationSettingsScreen.kt (:75-327).
 *
 * THREE sections, verified against the reference device before this was written
 * (ref_screen3e_location_top.png / ref_screen3e_location_full.png — that is the WHOLE screen, it
 * does not scroll further):
 *
 *   General                   Location service
 *   Native API                Location access | Location access in background | Device's GPS usage
 *   Baidu IP location (China) API key
 *
 * WHAT IS REAL HERE:
 *
 *   Location service   real — `location_service` (SettingsManager.kt:193-198), default `native`.
 *                      The three options come from SourceCatalogue's locationSourceList, which was
 *                      already ported: native "Android", ipsb "IP.SB", baidu_ip "Baidu…(China)".
 *   the two grantable  real — coarse maps to ohos.permission.APPROXIMATELY_LOCATION (already
 *   permission rows    declared for the my-location FAB) and precise to ohos.permission.LOCATION.
 *                      The summary follows the ACTUAL grant, and tapping requests it. Tapping a row
 *                      that is already granted shows the Kotlin's snackbar (kt:210-213).
 *   API key            real — stored, and shown as "Default (unchanged)" while empty.
 *
 * The BACKGROUND row is rendered but does not request. `ohos.permission.LOCATION_IN_BACKGROUND`
 * exists, but background refresh is scoped out by CLAUDE.md, so asking for it would be requesting a
 * permission this port can never use. It leads to the placeholder instead — the same treatment the
 * Background updates row gets on the settings root. Android's own row is disabled until coarse is
 * granted (kt:227), and that part IS reproduced.
 *
 * The freenet disclaimer block (kt:109-160) is absent: it is gated on BuildConfig.FLAVOR ==
 * "freenet", and the reference build is not that flavour — confirmed by the capture, which starts
 * straight at General.
 */

import { router } from '@kit.ArkUI';
import { abilityAccessCtrl, bundleManager, common, ConfigurationConstant, Permissions } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow, settingsSectionHeader } from '../view/settings/PreferenceRow';
import { ListPreferenceDialog, ListPreferenceOption } from '../view/settings/ListPreferenceDialog';
import { EditTextDialog } from '../view/settings/EditTextDialog';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark, setBaiduIpApiKey, setLocationService } from '../data/SettingsStore';
import { getSource } from '../data/SourceCatalogue';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
const SECTION_TEXT_SIZE: number = 14;

/** strings.xml:713 — what an empty API key reads as. */
const DEFAULT_UNCHANGED: string = 'Default (unchanged)';
/** strings.xml:686 — the snackbar for a row whose permission is already granted. */
const ALREADY_GRANTED: string = 'Permission already granted';

const COARSE: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION';
const PRECISE: Permissions = 'ohos.permission.LOCATION';

enum OpenDialog {
  NONE = 0,
  LOCATION_SERVICE = 1,
  BAIDU_API_KEY = 2
}

@Entry
@ComponentV2
struct LocationSettings {
  private insets: SystemInsets = SystemInsets.instance;
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  @Local private dialog: number = OpenDialog.NONE;
  @Local private revision: number = 0;
  /** The live grant state, re-read on every return to the page. */
  @Local private coarseGranted: boolean = false;
  @Local private preciseGranted: boolean = false;
  @Local private snackbar: string = '';

  aboutToAppear(): void {
    this.syncDark();
    this.syncPermissions();
  }

  onPageShow(): void {
    this.syncDark();
    // Coming back from the system settings page is the usual way one of these changes.
    this.syncPermissions();
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  /** PermissionStatus.Granted (kt:189, :255) — read from the token, not remembered. */
  private granted(permission: Permissions): boolean {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      return manager.checkAccessTokenSync(info.appInfo.accessTokenId, permission) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (error) {
      console.error('could not read a permission: ' + (error as Error).message);
      return false;
    }
  }

  private syncPermissions(): void {
    this.coarseGranted = this.granted(COARSE);
    this.preciseGranted = this.granted(PRECISE);
  }

  /**
   * kt:197-214 — not granted asks for it; already granted says so.
   *
   * The Kotlin's second branch (`shouldShowRequestPermissionRationale` → open the app's details
   * page) is what HarmonyOS does for us: once a request has been permanently refused,
   * requestPermissionsFromUser returns without a prompt, and the user has to go to system settings
   * anyway. There is no separate rationale query to consult here.
   */
  private requestPermission(permission: Permissions): void {
    if (this.granted(permission)) {
      this.snackbar = ALREADY_GRANTED;
      setTimeout(() => {
        this.snackbar = '';
      }, 2000);
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    manager.requestPermissionsFromUser(context, [permission])
      .then(() => {
        this.syncPermissions();
        this.revision++;
      })
      .catch((error: Error) => {
        console.error('permission request failed: ' + error.message);
      });
  }

  /* ------------------------------------------------------------------------ summaries -------- */

  private stamp(): boolean {
    return this.revision >= 0;
  }

  /** locationSourceList (SourceCatalogue), in the Kotlin's order. */
  private locationOptions(): ListPreferenceOption[] {
    const ids: string[] = ['native', 'ipsb', 'baidu_ip'];
    const options: ListPreferenceOption[] = [];
    for (let i = 0; i < ids.length; i++) {
      const source = getSource(ids[i]);
      options.push(new ListPreferenceOption(ids[i], source !== null ? source.name : ids[i]));
    }
    return options;
  }

  /** kt:174 — the row's summary is the chosen source's own name. */
  private locationServiceName(): string {
    const options: ListPreferenceOption[] = this.locationOptions();
    for (let i = 0; i < options.length; i++) {
      if (this.stamp() && options[i].value === this.settings.locationService) {
        return options[i].name;
      }
    }
    return options[0].name;
  }

  private apiKeySummary(): string {
    return this.stamp() && this.settings.baiduIpApiKey.length > 0
      ? this.settings.baiduIpApiKey
      : DEFAULT_UNCHANGED;
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

        Text('Location') // strings.xml:682 `settings_location`
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
            /* ---- General (kt:162-183) ---- */
            this.sectionHeader('General')

            PreferenceRow({
              title: 'Location service', // strings.xml:685
              summary: this.locationServiceName(),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: true,
              onTap: () => {
                this.dialog = OpenDialog.LOCATION_SERVICE;
              }
            })

            this.separator(true)

            /* ---- Native API (kt:185-283) ---- */
            this.sectionHeader('Native API') // strings.xml:465

            PreferenceRow({
              title: 'Location access', // :687
              summary: this.stamp() && this.coarseGranted
                ? 'Allowed. You can add your current location as a location.' // :688
                : 'Please allow if you want to be able to add your current location as a location.', // :689
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: false,
              onTap: () => {
                this.requestPermission(COARSE);
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Location access in background', // :690
              summary: this.stamp() && false
                ? 'Enabled. App will be able to refresh weather data for your current location in background.' // :691
                : 'Please enable “Allow all the time” to have background refreshes for your current location.', // :692
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: false,
              // kt:227 — dead until coarse is granted.
              rowEnabled: this.coarseGranted,
              onTap: () => {
                // Background refresh is scoped out; see the file header.
                goPlaceholder('Location access in background');
              }
            })
            this.separator(false)

            PreferenceRow({
              title: 'Device’s GPS usage', // :693
              summary: this.stamp() && this.preciseGranted
                ? 'Enabled. Device’s network provider will be used in priority and most of the time, but GPS can also be used as a fallback.' // :694
                : 'Enable “Use precise location” if you have trouble getting a location.', // :695
              icon: null,
              dark: this.dark,
              isFirst: false,
              isLast: true,
              rowEnabled: this.coarseGranted, // kt:260
              onTap: () => {
                this.requestPermission(PRECISE);
              }
            })

            this.separator(true)

            /* ---- the configurable location source's own section (kt:286-327) ---- */
            this.sectionHeader('Baidu IP location (China)')

            PreferenceRow({
              title: 'API key', // strings.xml:714
              summary: this.apiKeySummary(),
              icon: null,
              dark: this.dark,
              isFirst: true,
              isLast: true,
              onTap: () => {
                this.dialog = OpenDialog.BAIDU_API_KEY;
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

      if (this.dialog === OpenDialog.LOCATION_SERVICE) {
        ListPreferenceDialog({
          title: 'Location service',
          options: this.locationOptions(),
          selected: this.settings.locationService,
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setLocationService(value).then(() => {
              this.revision++;
            });
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }

      if (this.dialog === OpenDialog.BAIDU_API_KEY) {
        EditTextDialog({
          title: 'API key',
          content: this.settings.baiduIpApiKey,
          dark: this.dark,
          onChosen: (value: string) => {
            this.dialog = OpenDialog.NONE;
            setBaiduIpApiKey(value).then(() => {
              this.revision++;
            });
          },
          onDismiss: () => {
            this.dialog = OpenDialog.NONE;
          }
        })
      }

      // kt:210-213's snackbar, for a row whose permission is already granted.
      if (this.snackbar.length > 0) {
        Text(this.snackbar)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE_INVERSE.resolve(this.dark))
          .padding(Dimens.NORMAL_MARGIN)
          .backgroundColor(AppColors.SURFACE_INVERSE.resolve(this.dark))
          .borderRadius(Dimens.CARD_CORNER_RADIUS)
          .margin({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
          .position({ x: 0, y: '85%' })
      }
    }
    .width('100%')
    .height('100%')
  }
}
