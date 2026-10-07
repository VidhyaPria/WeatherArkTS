/*
 * Worker info — WorkerInfoActivity.kt:69-131, reached from Background updates ▸ Troubleshoot.
 *
 * Three sections, each a header over one card holding a MONOSPACE text block padded
 * normal_margin (kt:100-113, and SectionText at kt:132-140):
 *
 *     Enqueued
 *     Finished
 *     Running
 *
 * The content of each is WorkManager's job list for those states, rendered by `constructString`
 * (kt:175-205). That function has an explicit empty case: it appends a single "-" when the list is
 * empty, which is what the reference shows for any state with no jobs.
 *
 * WHY EVERY SECTION READS "-" HERE, AND WHY THAT IS NOT A STUB:
 * CLAUDE.md skips background refresh entirely, so neither port ever enqueues a job. There is no
 * WorkManager to query and, more to the point, nothing that could be in any of the three lists —
 * so "-" is not a placeholder standing in for content we failed to fetch, it is the value the
 * Kotlin itself produces for an empty list. The screen is complete; its data is legitimately
 * empty, the same way the alert card is empty because Open-Meteo declares no ALERTS feature.
 *
 * The row that opens this used to go to the placeholder in both ports.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY, LineHeights } from '../common/Typography';
import { settingsSectionHeader } from '../view/settings/PreferenceRow';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

/**
 * `FontFamily.Monospace` (kt:136). ArkUI resolves this to the platform's fixed-pitch face, the
 * same way Compose resolves the generic family rather than naming a font.
 */
const MONOSPACE_FAMILY: string = 'monospace';
/** The block is bodyMedium, which is what a Compose `Text` with no style override carries here. */
const BODY_TEXT_SIZE: number = 14;

/** kt:175-181 — an empty state list renders as a single "-". */
const EMPTY_SECTION: string = '-';

@Entry
@ComponentV2
struct WorkerInfo {
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

        /*
         * NO ⓘ here. `AboutActivityIconButton` is used by TEN settings screens (AppBar.kt:32 and
         * its nine callers) but NOT by WorkerInfoActivity, whose FitStatusBarTopAppBar (kt:79-85)
         * takes only a title and onBackPressed with no `actions`. An earlier version of this file
         * added one by copying the Debug screen's bar.
         */
      }
      .width('100%')
      .height(APP_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      // strings.xml settings_background_updates_worker_info_title
      Text('Worker info')
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
          // The three strings are translatable="false" in strings.xml, so they are these literals
          // in every locale.
          settingsSectionHeader('Enqueued', this.dark)
          this.sectionCard(EMPTY_SECTION)
          settingsSectionHeader('Finished', this.dark)
          this.sectionCard(EMPTY_SECTION)
          settingsSectionHeader('Running', this.dark)
          this.sectionCard(EMPTY_SECTION)
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

  /** One section's card: a Box padded normal_margin around a monospace block (kt:132-140). */
  @Builder
  private sectionCard(text: string) {
    Column() {
      Text(text)
        .fontFamily(MONOSPACE_FAMILY)
        .fontSize(BODY_TEXT_SIZE)
        .lineHeight(LineHeights.BODY_MEDIUM)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding(Dimens.NORMAL_MARGIN)
    .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.dark))
    .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
  }
}
