/*
 * The Dependencies screen — DependenciesActivity.kt:36-69.
 *
 * The Kotlin hands `R.raw.aboutlibraries` to AboutLibraries' `LibrariesContainer` with
 * `showLicenseBadges = true`. Its row, measured off ref_dependencies.png:
 *
 *   name      titleMedium, with the VERSION right-aligned on the same line
 *   author    bodyMedium in onSurfaceVariant, under the name
 *   licence   a filled pill per licence, primary container with onPrimaryContainer text
 *
 * Plain rows on the surface — no card, unlike the settings lists.
 *
 * WHAT IT LISTS: this port's own dependencies, not Android's. See `APP_DEPENDENCIES`.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';
import { APP_DEPENDENCIES, DependencyItem } from '../model/AboutCatalogue';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
/** AboutLibraries' row padding. */
const ROW_PADDING: number = 16;
const BADGE_H_PADDING: number = 10;
const BADGE_V_PADDING: number = 4;
const BADGE_RADIUS: number = 12;

@Entry
@ComponentV2
struct Dependencies {
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
      }
      .width('100%')
      .height(APP_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      Text('Dependencies') // strings.xml `action_dependencies`
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
          ForEach(APP_DEPENDENCIES, (item: DependencyItem, index: number) => {
            this.libraryRow(item)
          }, (item: DependencyItem, index: number) => index.toString() + ':' + item.name)

          Column().width('100%').height(Dimens.NORMAL_MARGIN + this.insets.bottom)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
    .padding({ top: this.insets.top, left: this.insets.left, right: this.insets.right })
  }

  @Builder
  private libraryRow(item: DependencyItem) {
    Column() {
      Row() {
        Text(item.name)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .layoutWeight(1)
        if (item.version.length > 0) {
          Text(item.version)
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (item.author.length > 0) {
        Text(item.author)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          .margin({ top: 2 })
      }

      if (item.license.length > 0) {
        Text(item.license)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.dark))
          .padding({
            left: BADGE_H_PADDING,
            right: BADGE_H_PADDING,
            top: BADGE_V_PADDING,
            bottom: BADGE_V_PADDING
          })
          .backgroundColor(AppColors.PRIMARY_CONTAINER.resolve(this.dark))
          .borderRadius(BADGE_RADIUS)
          .margin({ top: Dimens.SMALL_MARGIN })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(ROW_PADDING)
  }
}
