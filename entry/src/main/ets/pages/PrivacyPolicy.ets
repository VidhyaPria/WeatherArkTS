/*
 * The Privacy policy screen — PrivacyPolicyActivity.kt:60-146.
 *
 * A `PreferenceScreen` of one card group: the app's own row first, then one row per HTTP source that
 * declares a privacy policy, **sorted by name** (kt:73-83, a Collator on the current locale).
 * Every row is `title = source name`, `summary = the URL`, and tapping opens it.
 *
 * The URL table is `model/AboutCatalogue.ets`; the source list and its names come from the same
 * `SOURCES` catalogue every other source-listing screen uses, so this screen cannot disagree with
 * them about a name.
 *
 * The row set is every source whose `privacyPolicyUrl` starts with "http" — 47 of the catalogue's
 * 75; the other 28 declare `privacyPolicyUrl = ""` and the Kotlin's own filter drops them. An
 * earlier note here blamed a short screen on the CATALOGUE being incomplete; the catalogue has all
 * 75 ids, and the short screen was `PRIVACY_POLICY_URLS`, which stopped at 25 rows. Both are now
 * complete.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { PreferenceRow } from '../view/settings/PreferenceRow';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';
import { SourceInfo, SOURCES } from '../data/SourceCatalogue';
import { PRIVACY_POLICY_LINK, PRIVACY_POLICY_URLS } from '../model/AboutCatalogue';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

/** One row: a name and the URL under it. */
class PolicyRow {
  readonly name: string;
  readonly url: string;

  constructor(name: string, url: string) {
    this.name = name;
    this.url = url;
  }
}

@Entry
@ComponentV2
struct PrivacyPolicy {
  private insets: SystemInsets = SystemInsets.instance;
  @Local private dark: boolean = false;
  @Local private linkToOpen: string = '';

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

  /** kt:73-83 — the sources that declare a policy, by name. The app's own row leads (kt:96-119). */
  private rows(): PolicyRow[] {
    const out: PolicyRow[] = [new PolicyRow('Breezy Weather', PRIVACY_POLICY_LINK)];
    const sources: PolicyRow[] = [];
    for (const source of SOURCES) {
      const url: string | undefined = PRIVACY_POLICY_URLS.get(source.id);
      if (url !== undefined && url.startsWith('http')) {
        sources.push(new PolicyRow(source.name, url));
      }
    }
    sources.sort((a: PolicyRow, b: PolicyRow) => a.name.localeCompare(b.name));
    return out.concat(sources);
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

        Text('Privacy policy') // strings.xml `about_privacy_policy`
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
            ForEach(this.rows(), (row: PolicyRow, index: number) => {
              PreferenceRow({
                title: row.name,
                summary: row.url,
                dark: this.dark,
                isFirst: index === 0,
                isLast: index === this.rows().length - 1,
                onTap: () => {
                  this.linkToOpen = row.url;
                }
              })
              // SmallSeparatorItem between every pair (kt:121-129).
              if (index < this.rows().length - 1) {
                Column().width('100%').height(Dimens.SETTINGS_SMALL_SEPARATOR)
              }
            }, (row: PolicyRow, index: number) => index.toString() + ':' + row.name)

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

  /** The same confirmation the About screen raises — one bubble, drawn by the page in both ports. */
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
          Text('Cancel')
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
      .padding(24)
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
        console.error('PrivacyPolicy: could not open ' + url + ': ' + error.message);
      });
    } catch (error) {
      console.error('PrivacyPolicy: could not open ' + url + ': ' + (error as Error).message);
    }
  }
}
