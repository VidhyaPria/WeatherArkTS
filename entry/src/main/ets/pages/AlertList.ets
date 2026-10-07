/*
 * The alert screen — AlertActivity.kt + AlertScreen.kt:74-228.
 *
 * A LazyColumn of `location.weather.alertList` — EVERY alert, not just the ones in force; the main
 * card's two variants filter, this screen does not. One `Material3ExpressiveCardListItem` per alert
 * (isFirst = isLast = true, so every card carries the full corner radius), 16 vp apart, with 16 vp
 * of horizontal contentPadding.
 *
 * Card body (kt:130-215), all of it inside 16 vp of padding:
 *   row      the severity triangle (24 vp) + 16 vp + [headline titleMedium bold onSurface,
 *            formatted dates labelMedium onSurfaceVariant]
 *   then, each preceded by 8 vp and — from the second one on — a HorizontalDivider:
 *   desc     bodyMedium onSurfaceVariant
 *   instr    bodyMedium onSurfaceVariant
 *   source   "Source: %s" bodyMedium onSurfaceVariant
 *
 * `alertId` scrolls the list to that alert (kt:88-102); the main card's per-row taps pass it, its
 * card-level tap does not, and an unknown id falls back to the top exactly as the Kotlin does.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Alert, LocationModel } from '../model/Weather';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { APP_FONT_FAMILY } from '../common/Typography';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';
import { getMainViewModel } from '../viewmodel/MainViewModel';
import { AlertListParams } from '../common/Navigator';
import { getClockTime, getMediumDayAndMonth, LOCALE_SEPARATOR } from '../common/Formatter';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
/** dimens.xml:18 material_icon_size — the triangle's box. */
const TRIANGLE_SIZE: number = Dimens.MATERIAL_ICON_SIZE;
/** typography.labelMedium. */
const LABEL_MEDIUM_TEXT_SIZE: number = 12;
const DIVIDER_HEIGHT: number = 1;

@Entry
@ComponentV2
struct AlertList {
  private insets: SystemInsets = SystemInsets.instance;
  @Local private dark: boolean = false;
  @Local private location: LocationModel | null = null;
  private alertId: string = '';
  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const params = router.getParams() as AlertListParams;
    if (params !== null && params !== undefined) {
      this.alertId = params.alertId;
      const model = getMainViewModel();
      for (const candidate of model.getLocations()) {
        if (candidate.formattedId === params.locationId) {
          this.location = candidate;
          break;
        }
      }
    }
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
    // kt:88-102 — open on the alert that was tapped, or at the top when there was none.
    const alerts: Alert[] = this.alerts();
    if (alerts.length === 0) {
      return;
    }
    let index: number = 0;
    if (this.alertId.length > 0) {
      for (let i = 0; i < alerts.length; i++) {
        if (alerts[i].alertId === this.alertId) {
          index = i;
          break;
        }
      }
    }
    this.listScroller.scrollToIndex(index);
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  private alerts(): Alert[] {
    const location: LocationModel | null = this.location;
    if (location === null || location.weather === null) {
      return [];
    }
    return location.weather.alertList;
  }

  /** `Alert.getFormattedDates` (Alert.kt:27-56) — the same helper the main card uses. */
  private formattedDates(alert: Alert): string {
    if (alert.startDate === null) {
      return '';
    }
    const offset: number = this.location === null ? 0 : this.location.utcOffsetSeconds;
    const startDay: string = getMediumDayAndMonth(alert.startDate, offset);
    const start: string = startDay + LOCALE_SEPARATOR + getClockTime(alert.startDate, offset);
    if (alert.endDate === null) {
      return start;
    }
    const endDay: string = getMediumDayAndMonth(alert.endDate, offset);
    const endPrefix: string = endDay === startDay ? '' : endDay + LOCALE_SEPARATOR;
    return start + ' — ' + endPrefix + getClockTime(alert.endDate, offset);
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

      Text('Alerts') // strings.xml `alerts`
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(HEADLINE_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .maxLines(1)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN, top: Dimens.LARGE_TITLE_TOP_PADDING })
        .height(APP_BAR_EXPANDED_HEIGHT - APP_BAR_HEIGHT)

      List({ scroller: this.listScroller }) {
        ForEach(this.alerts(), (alert: Alert, index: number) => {
          ListItem() {
            Column() {
              this.alertCard(alert)
              // kt:217-219 — 16 vp between cards, but none after the last.
              if (index !== this.alerts().length - 1) {
                Column().width('100%').height(Dimens.NORMAL_MARGIN)
              }
            }
            .width('100%')
          }
        }, (alert: Alert, index: number) => index.toString() + ':' + alert.alertId)

        ListItem() {
          // bottomInsetItem(extraHeight = getCardListItemMarginDp) — kt:222-224.
          Column()
            .width('100%')
            .height(Dimens.NORMAL_MARGIN + Dimens.SMALL_MARGIN + this.insets.bottom)
        }
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .layoutWeight(1)
      .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
    .padding({ top: this.insets.top, left: this.insets.left, right: this.insets.right })
  }

  @Builder
  private alertCard(alert: Alert) {
    Column() {
      Row() {
        // kt:138-145 — MaterialShapes.Triangle filled with the alert's severity colour.
        Polygon()
          .width(TRIANGLE_SIZE)
          .height(TRIANGLE_SIZE)
          .points([[TRIANGLE_SIZE / 2, 0], [TRIANGLE_SIZE, TRIANGLE_SIZE], [0, TRIANGLE_SIZE]])
          .fill(alert.color)

        Column() {
          Text(alert.headline.length > 0 ? alert.headline : 'Alert') // strings.xml `alert`
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontWeight(FontWeight.Bold) // kt:154 — FontWeight.Bold, not titleMedium's Medium.
            .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
            .width('100%')
          if (this.formattedDates(alert).length > 0) {
            Text(this.formattedDates(alert))
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(LABEL_MEDIUM_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
              .width('100%')
          }
        }
        .layoutWeight(1)
        .margin({ left: Dimens.NORMAL_MARGIN })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (alert.description.length > 0) {
        Column().width('100%').height(Dimens.SMALL_MARGIN)
        this.body(alert.description)
      }
      if (alert.instruction.length > 0) {
        if (alert.description.length > 0) {
          Column().width('100%').height(Dimens.SMALL_MARGIN)
          this.divider()
        }
        Column().width('100%').height(Dimens.SMALL_MARGIN)
        this.body(alert.instruction)
      }
      if (alert.source.length > 0) {
        if (alert.description.length > 0 || alert.instruction.length > 0) {
          Column().width('100%').height(Dimens.SMALL_MARGIN)
          this.divider()
        }
        Column().width('100%').height(Dimens.SMALL_MARGIN)
        this.body('Source: ' + alert.source) // strings.xml `alert_source`
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Dimens.NORMAL_MARGIN)
    .backgroundColor(AppColors.SETTINGS_CARD.resolve(this.dark))
    .borderRadius(Dimens.SETTINGS_CARD_CORNER_RADIUS)
  }

  @Builder
  private body(text: string) {
    Text(text)
      .fontFamily(APP_FONT_FAMILY)
      .fontSize(Dimens.CONTENT_TEXT_SIZE)
      .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
      .width('100%')
  }

  @Builder
  private divider() {
    Column()
      .width('100%')
      .height(DIVIDER_HEIGHT)
      .backgroundColor(AppColors.COMPOSE_OUTLINE_VARIANT.resolve(this.dark))
  }
}
