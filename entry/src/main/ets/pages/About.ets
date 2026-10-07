/*
 * The About screen — AboutActivity / AboutScreen.kt:86-372.
 *
 * Measured off the reference device (ref_about_top.png, ref_about_contributors.png):
 *
 *   app bar        the same FitStatusBarTopAppBar every screen-3 page uses — a 64 vp icon row with
 *                  the back arrow, then the headlineMedium title below it
 *   header         the launcher icon at 72 vp, "Breezy Weather" in headlineSmall, and the version
 *                  line in labelMedium onSurfaceVariant, the whole block padded 24 vp (kt:375-401)
 *   update row     a lone card, "Check for app updates" with ic_sync
 *   Contact        a labelMedium section title, then a grouped card of Source code / Matrix room
 *   About app      the same, with Privacy policy / Dependencies
 *   Contributors   one row per contributor, name in titleMedium with an optional bodyMedium
 *                  contribution line under it (kt:474-509)
 *   Translators    the same rows, filtered to the device language
 *
 * Every row that opens a URL goes through `AlertDialogLink` (kt:365-370) — a confirmation naming
 * the link, not a silent jump out of the app.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow } from '../view/settings/PreferenceRow';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';
import {
  ABOUT_APP_LINKS,
  ABOUT_CONTACT_LINKS,
  AboutLinkItem,
  APP_CONTRIBUTORS,
  APP_TRANSLATORS,
  ContributorItem,
  RELEASES_LINK
} from '../model/AboutCatalogue';

/* The LargeTopAppBar metrics screen 3's pages already use — see pages/Settings.ets. */
const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

/** The header block (kt:375-401). */
const HEADER_PADDING: number = 24;
const APP_ICON_SIZE: number = 72;
/** typography.headlineSmall / labelMedium. */
const BRAND_TEXT_SIZE: number = 24;
const VERSION_TEXT_SIZE: number = 12;
/** SectionTitle is labelMedium, padded a normal_margin all round (kt:404-411). */
const SECTION_TITLE_SIZE: number = 12;

@Entry
@ComponentV2
struct About {
  private insets: SystemInsets = SystemInsets.instance;
  /** The SYSTEM colour mode, as every screen-3 page uses — see pages/Settings.ets. */
  @Local private dark: boolean = false;
  /**
   * `versionFormatted` (kt:413-417) — "Release <versionName>" for a release build.
   *
   * Read from the bundle rather than hard-coded, which is what BuildConfig.VERSION_NAME is. It
   * therefore shows THIS port's version, not the 6.2.1 the reference shows: the ports are a
   * different build of the same app, and both show the same string as each other.
   */
  @Local private version: string = '';
  /** AlertDialogLink (kt:365-370) — the confirmation before leaving the app. */
  @Local private linkToOpen: string = '';

  aboutToAppear(): void {
    this.syncDark();
    this.readVersion();
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

  private readVersion(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.version = 'Release ' + info.versionName;
    } catch (error) {
      // The header still draws; only the version line is empty, which is better than a wrong one.
      console.error('About: could not read the bundle version: ' + (error as Error).message);
    }
  }

  private iconOf(name: string): Resource {
    if (name === 'ic_code') {
      return $r('app.media.ic_code');
    }
    if (name === 'ic_forum') {
      return $r('app.media.ic_forum');
    }
    if (name === 'ic_shield_lock') {
      return $r('app.media.ic_shield_lock');
    }
    return $r('app.media.ic_contract');
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
        }
        .width('100%')
        .height(APP_BAR_HEIGHT)
        .alignItems(VerticalAlign.Center)

        Text('About') // strings.xml `action_about`
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
            this.header()

            // The update card is a group of one (kt:184-279).
            PreferenceRow({
              title: 'Check for app updates', // strings.xml `about_check_for_app_updates`
              icon: $r('app.media.ic_sync'),
              dark: this.dark,
              isFirst: true,
              isLast: true,
              onTap: () => {
                /*
                 * kt:272-275 — with no in-app update checker the row opens the releases page
                 * instead, which is the branch a build without one takes. This port has no
                 * updater: `background/updater` is background refresh, which CLAUDE.md scopes out.
                 */
                this.linkToOpen = RELEASES_LINK;
              }
            })

            Column().width('100%').height(Dimens.SETTINGS_LARGE_SEPARATOR)

            this.sectionTitle('Contact') // strings.xml `about_contact`
            this.linkGroup(ABOUT_CONTACT_LINKS)

            Column().width('100%').height(Dimens.SETTINGS_LARGE_SEPARATOR)

            this.sectionTitle('About app') // strings.xml `about_app`
            this.linkGroup(ABOUT_APP_LINKS)

            Column().width('100%').height(Dimens.SETTINGS_LARGE_SEPARATOR)

            this.sectionTitle('Contributors') // strings.xml `about_contributors`
            this.contributorGroup(APP_CONTRIBUTORS)

            Column().width('100%').height(Dimens.SETTINGS_LARGE_SEPARATOR)

            this.sectionTitle('Translators') // strings.xml `about_translators`
            this.contributorGroup(APP_TRANSLATORS)

            // bottomInsetItem + getCardListItemMarginDp (kt:360-362).
            Column().width('100%').height(Dimens.NORMAL_MARGIN + this.insets.bottom)
          }
          .width('100%')
          .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      if (this.linkToOpen.length > 0) {
        this.linkDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
    .padding({ top: this.insets.top, left: this.insets.left, right: this.insets.right })
  }

  /** Header (kt:375-401) — the icon, the brand name, the version. */
  @Builder
  private header() {
    Column() {
      // `ic_launcher_round` (kt:381). `foreground` is the layered icon's foreground layer alone,
      // which is nearly white on a white surface; `startIcon` is the composed icon.
      Image($r('app.media.startIcon'))
        .width(APP_ICON_SIZE)
        .height(APP_ICON_SIZE)

      Text('Breezy Weather') // strings.xml `brand_name`
        .fontFamily(SETTINGS_FONT_FAMILY)
        .fontSize(BRAND_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .margin({ top: Dimens.SMALL_MARGIN })

      Text(this.version)
        .fontFamily(SETTINGS_FONT_FAMILY)
        .fontSize(VERSION_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
    }
    .width('100%')
    .padding(HEADER_PADDING)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontFamily(SETTINGS_FONT_FAMILY)
      .fontSize(SECTION_TITLE_SIZE)
      .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
      .width('100%')
      .padding(Dimens.NORMAL_MARGIN)
  }

  /** A grouped card of link rows, with the 2 vp inner separators the Kotlin's SmallSeparatorItem is. */
  @Builder
  private linkGroup(items: AboutLinkItem[]) {
    ForEach(items, (item: AboutLinkItem, index: number) => {
      PreferenceRow({
        title: item.title,
        icon: this.iconOf(item.icon),
        dark: this.dark,
        isFirst: index === 0,
        isLast: index === items.length - 1,
        onTap: () => {
          if (item.url.length > 0) {
            this.linkToOpen = item.url;
            return;
          }
          if (item.screen === 'Privacy policy') {
            router.pushUrl({ url: 'pages/PrivacyPolicy' })
              .catch((error: Error) => {
                console.error('Privacy policy unavailable: ' + error.message);
              });
            return;
          }
          if (item.screen === 'Dependencies') {
            router.pushUrl({ url: 'pages/Dependencies' })
              .catch((error: Error) => {
                console.error('Dependencies unavailable: ' + error.message);
              });
            return;
          }
          goPlaceholder(item.screen);
        }
      })
      if (index < items.length - 1) {
        Column().width('100%').height(Dimens.SETTINGS_SMALL_SEPARATOR)
      }
    }, (item: AboutLinkItem, index: number) => index.toString() + ':' + item.title)
  }

  /** ContributorView (kt:474-509) — the name, and the contribution line when there is one. */
  @Builder
  private contributorGroup(items: ContributorItem[]) {
    ForEach(items, (item: ContributorItem, index: number) => {
      PreferenceRow({
        title: item.name,
        summary: item.contribution,
        dark: this.dark,
        isFirst: index === 0,
        isLast: index === items.length - 1,
        onTap: () => {
          // kt:326-330 — a contributor with no link is not a link; the row simply does nothing.
          if (item.link.length > 0) {
            this.linkToOpen = item.link;
          }
        }
      })
      if (index < items.length - 1) {
        Column().width('100%').height(Dimens.SETTINGS_SMALL_SEPARATOR)
      }
    }, (item: ContributorItem, index: number) => index.toString() + ':' + item.name)
  }

  /**
   * `AlertDialogLink` — "Open %s?" with Cancel and OK (strings.xml `about_open_link_message`).
   *
   * Drawn as an overlay rather than through `AlertDialog`, so the two ports can draw the same
   * bubble: the NDK has no dialog framework and paints its own.
   */
  @Builder
  private linkDialog() {
    Column() {
      Column() {
        Text('Open ' + this.linkToOpen + '?')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')

        Row({ space: Dimens.NORMAL_MARGIN }) {
          Blank()
          Text('Cancel') // strings.xml `action_cancel`
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .onClick(() => {
              this.linkToOpen = '';
            })
          Text('OK')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .onClick(() => {
              this.openLink();
            })
        }
        .width('100%')
        .margin({ top: Dimens.NORMAL_MARGIN })
      }
      .width('80%')
      .padding(HEADER_PADDING)
      .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.dark))
      .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
    .onClick(() => {
      this.linkToOpen = '';
    })
  }

  private openLink(): void {
    const url: string = this.linkToOpen;
    this.linkToOpen = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      }).catch((error: Error) => {
        console.error('About: could not open ' + url + ': ' + error.message);
      });
    } catch (error) {
      console.error('About: could not open ' + url + ': ' + (error as Error).message);
    }
  }
}
