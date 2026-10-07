/*
 * The weather-alert card.
 *
 * Port of AlertViewHolder.kt:62-195 (container_main_alert.xml).
 *
 * Two states, exactly as the Kotlin picks between them (kt:84-88):
 *   - currentAlertList empty  -> a single "Alerts to follow" row with the warning icon (kt:96-131)
 *   - otherwise               -> one row per current alert: a coloured triangle, the headline,
 *                               and the formatted date range (kt:133-194)
 *
 * The whole card is clickable and opens the alert screen (kt:79-81); a single alert row opens the
 * same screen scrolled to that alert (kt:147-151).
 *
 * MainAdapter.kt:107-109 places this directly under the header, before any of the reorderable
 * cards, and MainAdapter.isDraggable (kt:274-285) excludes it from drag-to-reorder.
 */

import { Dimens } from '../../theme/Dimens';
import { Alert } from '../../model/Weather';
import { getClockTime, getMediumDayAndMonth, LOCALE_SEPARATOR } from '../../common/Formatter';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** dimens.xml:18 material_icon_size. */
const TRIANGLE_SIZE: number = Dimens.MATERIAL_ICON_SIZE;

@ComponentV2
export struct AlertCard {
  /** Alerts in force now; empty means the "alerts to follow" variant. */
  @Param currentAlerts: Alert[] = [];
  /** The location's UTC offset — alert times print in ITS zone, as Android does. */
  @Param utcOffsetSeconds: number = 0;
  @Param cardBackground: string = '#FFFCFCFF';
  @Param onSurface: string = '#FF191C1E';
  @Param onSurfaceVariant: string = '#FF40484D';
  /**
   * kt:79-81 — the whole card opens the alert screen at the top; kt:147-151 — a single alert row
   * opens it scrolled to THAT alert. Two handlers, because Android passes an alertId from one and
   * not from the other.
   */
  @Event onAlertClick: () => void = () => {
  };
  @Event onSingleAlertClick: (alertId: string) => void = (alertId: string) => {
  };

  /**
   * `Alert.getFormattedDates` (Alert.kt) — "Aug 7, 10:00 AM — 8:00 PM".
   *
   * The start is always DAY + separator + TIME; the end repeats the day only when it differs, which
   * is why a same-day alert ends in a bare time. The port used to print `getHour` on both ends,
   * which drops the date entirely AND the minutes — `getHour` is the trend column's "10 AM" form,
   * where `getFormattedTime` here always shows them.
   */
  private formattedDates(alert: Alert): string {
    if (alert.startDate === null) {
      return '';
    }
    const startDay: string = getMediumDayAndMonth(alert.startDate, this.utcOffsetSeconds);
    const start: string =
      startDay + LOCALE_SEPARATOR + getClockTime(alert.startDate, this.utcOffsetSeconds);
    if (alert.endDate === null) {
      return start;
    }
    const endDay: string = getMediumDayAndMonth(alert.endDate, this.utcOffsetSeconds);
    const endPrefix: string = endDay === startDay ? '' : endDay + LOCALE_SEPARATOR;
    return start + ' — ' + endPrefix + getClockTime(alert.endDate, this.utcOffsetSeconds);
  }

  build() {
    // See MinutelyCard — the 8dp card margin has to live on a wrapper, not on the card itself.
    Column() {
      this.card()
    }
    .width('100%')
    .padding(Dimens.SMALL_MARGIN)
  }

  @Builder
  card() {
    Column() {
      if (this.currentAlerts.length === 0) {
        // kt:96-131 — alerts exist but none has started yet.
        Row() {
          Image($r('app.media.ic_warning'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(this.onSurface)
          // strings.xml: alerts_to_follow = "Upcoming alerts, tap here to see them." The port had
          // shortened this to "Alerts to follow", which is the string's NAME, not its value.
          Text('Upcoming alerts, tap here to see them.')
            .fontFamily(APP_FONT_FAMILY)
            // kt:120 — titleMedium: 16sp, weight 500, 0.15 letter spacing.
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .letterSpacing(0.15)
            .fontColor(this.onSurface)
            .layoutWeight(1)
            .margin({ left: Dimens.NORMAL_MARGIN })
        }
        .width('100%')
        // A one-line ListItem: a fixed 56 dp container with 16 dp of horizontal padding. The
        // height does NOT grow out of the content, which is why deriving it from padding made
        // the pill 72 vp against Android's 56.
        .height(Dimens.LIST_ITEM_ONE_LINE_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
      } else {
        ForEach(this.currentAlerts, (alert: Alert) => {
          Row() {
            // kt:181-189 — a MaterialShapes.Triangle filled with the alert's severity colour.
            Polygon()
              .width(TRIANGLE_SIZE)
              .height(TRIANGLE_SIZE)
              .points([[TRIANGLE_SIZE / 2, 0], [TRIANGLE_SIZE, TRIANGLE_SIZE], [0, TRIANGLE_SIZE]])
              .fill(alert.color)

            Column() {
              Text(alert.headline.length > 0 ? alert.headline : 'Alert') // strings.xml alert
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.TITLE_TEXT_SIZE)
                .fontWeight(FontWeight.Medium)
                .letterSpacing(0.15)
                .fontColor(this.onSurface)
                .width('100%')
              if (this.formattedDates(alert).length > 0) {
                Text(this.formattedDates(alert))
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(Dimens.CONTENT_TEXT_SIZE)
                  .fontColor(this.onSurfaceVariant)
                  .width('100%')
              }
            }
            .layoutWeight(1)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          // A two-line ListItem — headline plus the supporting date range.
          .height(Dimens.LIST_ITEM_TWO_LINE_HEIGHT)
          .alignItems(VerticalAlign.Center)
          .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
          .onClick(() => {
            this.onSingleAlertClick(alert.alertId);
          })
        }, (alert: Alert) => alert.alertId)
      }
    }
    .width('100%')
    // No padding on the card itself: the ListItem rows above own all of it, as they do on Android
    // where the composable is the card's only child.
    .backgroundColor(this.cardBackground)
    .borderRadius(Dimens.CARD_CORNER_RADIUS)
    .onClick(() => {
      this.onAlertClick();
    })
  }
}
