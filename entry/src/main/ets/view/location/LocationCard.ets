/*
 * One saved location, as a row â€” item_location_card.xml bound by LocationHolder.kt.
 *
 * The Android row is a full-corner filled MaterialCardView wrapping a SlidingItemContainerLayout,
 * whose child is [drag handle | weather icon | title / body]. The sliding container is what reveals
 * the delete and settings actions when the row is swiped; that behaviour is task 8, and this file
 * lays out the row and paints it in the states LocationHolder chooses between (kt:74-95):
 *
 *   selected    primaryContainer / onPrimaryContainer
 *   has alerts  alert_background / alert_text
 *   otherwise   the 2 dp elevated surface / colorTitleText + colorBodyText
 */

import { Dimens } from '../../theme/Dimens';
import { AppColors, elevatedSurface } from '../../theme/AppColors';
import { APP_FONT_FAMILY } from '../../common/Typography';
import { getWeatherIcon } from '../../common/WeatherIcons';
import { WeatherKind } from '../../model/WeatherKind';

/** dimens.xml small_weather_icon_size. */
const WEATHER_ICON_SIZE: number = 42;
/**
 * styles.xml material_image_button â€” 40 dp with 8 dp padding. Its 8 dp MARGIN does not apply:
 * item_location_card.xml:30 overrides it with `android:layout_margin="0dp"`.
 */
const DRAG_BUTTON_SIZE: number = 40;
/**
 * ShapeAppearance.Material3.Corner.Full on a wrap_content card is a stadium â€” the radius is half
 * the row's height. Anything at or above that half-height produces the same shape, so a constant
 * comfortably past it avoids measuring the row to draw it.
 */
const ROW_CORNER_RADIUS: number = 48;
/** ItemTouchHelper.getSwipeThreshold's default â€” half the item's width commits the swipe. */
const SWIPE_THRESHOLD: number = 0.5;
/** ViewConfiguration's 8 dp touch slop, so a vertical scroll is never read as a swipe. */
const SWIPE_SLOP: number = 8;
/** DefaultItemAnimator's move duration, which is what the spring-back reads as. */
const SWIPE_SETTLE_MS: number = 250;
/** dimens.xml touch_rise_z, as onChildDraw applies to the row under the finger. Hoisted â€” an
 * object literal rebuilt per render is a changed attribute every frame (screen 1's drag lesson). */
const DRAG_SHADOW: ShadowOptions = { radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 };
const NO_SHADOW: ShadowOptions = { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };

@ComponentV2
export struct LocationCard {
  /*
   * The row's fields arrive as scalars rather than as the LocationRowModel.
   *
   * The colours are chosen in helper methods below, and a @Trace read inside a helper does not
   * register as a render dependency â€” so binding the model object and mutating its fields would
   * update the two Texts and leave every colour stale. A scalar @Param re-renders the whole
   * component, helpers included, which is what these need.
   */
  @Param title: string = '';
  @Param body: string = '';
  @Param selected: boolean = false;
  @Param alerts: number = 0;
  @Param currentPosition: boolean = false;
  @Param weatherKind: WeatherKind | null = null;
  @Param daylight: boolean = true;
  @Param dark: boolean = false;
  /** Lifted by the list while this row is being dragged, as onChildDraw raises it (kt:127-135). */
  @Param lifted: boolean = false;
  /** Vertical offset applied while dragging, owned by the list which knows the row geometry. */
  @Param dragOffsetY: number = 0;

  @Event onSelect: () => void = () => {
  };
  @Event onDelete: () => void = () => {
  };
  @Event onOpenSettings: () => void = () => {
  };
  /*
   * Named for the HANDLE rather than the drag: onDragStart/onDragMove/onDragEnd are all attribute
   * methods every CustomComponent inherits, so members of those names fail to compile â€” the same
   * collision as ackground above.
   */
  @Event onHandleDown: () => void = () => {
  };
  @Event onHandleMoved: (offsetY: number) => void = () => {
  };
  @Event onHandleUp: () => void = () => {
  };

  /** Live horizontal swipe offset; 0 at rest. */
  @Local private swipeX: number = 0;
  /** Measured once, so the swipe threshold is a fraction of the real row width. */
  @Local private rowWidth: number = 0;

  /** kt:74-83 â€” the row's own background, before the sliding container reveals anything. */
  // Named rowBackground because a plain 'background' collides with the attribute method every
  // CustomComponent inherits, the same trap NumberAnimText documents for fontSize/fontColor.
  private rowBackground(): string {
    if (this.selected) {
      return AppColors.PRIMARY_CONTAINER.resolve(this.dark);
    }
    if (this.alerts > 0) {
      return AppColors.ALERT_BACKGROUND.resolve(this.dark);
    }
    // getWidgetSurfaceColor(2 dp, colorPrimary, colorSurface) â€” Material's elevation overlay.
    return elevatedSurface(Dimens.CARD_ELEVATION, AppColors.PRIMARY.resolve(this.dark),
      AppColors.SURFACE.resolve(this.dark));
  }

  /** kt:85-95 */
  private dragTint(): string {
    if (this.selected) {
      return AppColors.ON_PRIMARY_CONTAINER.resolve(this.dark);
    }
    if (this.alerts > 0) {
      return AppColors.ALERT_TEXT.resolve(this.dark);
    }
    return AppColors.PRIMARY.resolve(this.dark);
  }

  /** kt:105-111 */
  private titleColor(): string {
    return this.selected
      ? AppColors.ON_PRIMARY_CONTAINER.resolve(this.dark)
      : AppColors.TITLE_TEXT.resolve(this.dark);
  }

  /** kt:116-121 */
  private bodyColor(): string {
    return this.alerts > 0
      ? AppColors.ALERT_TEXT.resolve(this.dark)
      : AppColors.BODY_TEXT.resolve(this.dark);
  }

  build() {
    Stack({ alignContent: this.swipeX > 0 ? Alignment.Start : Alignment.End }) {
      /*
       * SlidingItemContainerLayout's revealed action (kt:119-149).
       *
       * In LTR the container shows `iconResStart` on `backgroundColorStart` when the row is dragged
       * to the RIGHT (totalX > 0), and `iconResEnd`/`backgroundColorEnd` when dragged left. Bound by
       * LocationHolder.kt:56-72 to delete-on-errorContainer at the start edge and
       * settings-on-secondary/tertiaryContainer at the end edge â€” so right is delete and left is
       * settings, which is also how ItemTouchHelper's END and START map.
       *
       * (The `location_swipe_to_delete` talkback string says "swipe left to delete"; the code says
       * otherwise, and the code is what the app does.)
       */
      Image(this.swipeX > 0 ? $r('app.media.ic_delete') : $r('app.media.ic_settings'))
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .fillColor(this.actionTint())
        .margin({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })

      Row() {
        // The drag handle. Touching it starts the reorder immediately â€” LocationHolder.kt:129-135
        // hands the drag to the ItemTouchHelper on ACTION_DOWN, with no long press.
        Image($r('app.media.ic_drag'))
          .width(DRAG_BUTTON_SIZE)
          .height(DRAG_BUTTON_SIZE)
          .fillColor(this.dragTint())
          /*
           * NO margin. `material_image_button` carries an 8 dp one, but item_location_card.xml:30
           * OVERRIDES it with `android:layout_margin="0dp"`, so the handle sits flush against the
           * card's leading edge. Taking the style's default instead pushed the handle 8 dp in AND
           * opened an 8 dp gap before the weather icon, moving every row's title 16 dp (52 px)
           * right of Android's. Measured on the reference: handle [52,432], icon x=182, title
           * x=345, against 78 / 234 / 397 here.
           */
          .padding(Dimens.SMALL_MARGIN)
          /*
           * `priorityGesture`, not `gesture` or a raw onTouch.
           *
           * A plain onTouch stops receiving Move events the moment the enclosing Scroll claims the
           * vertical drag, so the reorder never started â€” the same arbitration that made screen 1's
           * card drag report only taps until it was moved to priorityGesture. Priority is exactly
           * the case that attribute exists for: on the handle, the drag must always beat the
           * ancestors. `distance: 1` keeps it near-immediate, as LocationHolder.kt:129-135 hands the
           * drag over on ACTION_DOWN with no long press.
           */
          .priorityGesture(
            PanGesture({ direction: PanDirection.Vertical, distance: 1 })
              .onActionStart(() => {
                this.onHandleDown();
              })
              .onActionUpdate((event: GestureEvent) => {
                this.onHandleMoved(event.offsetY);
              })
              .onActionEnd(() => {
                this.onHandleUp();
              })
              .onActionCancel(() => {
                this.onHandleUp();
              })
          )

        Row() {
          // The icon is hidden entirely until a refresh has produced a weather code (kt:97-104).
          if (this.weatherKind !== null) {
            Image(getWeatherIcon(this.weatherKind, this.daylight))
              .width(WEATHER_ICON_SIZE)
              .height(WEATHER_ICON_SIZE)
              .margin({ right: Dimens.SMALL_MARGIN })
          }

          Column() {
            Text(this.title)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.TITLE_TEXT_SIZE)
              .fontColor(this.titleColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Start)

            // title2 is GONE when the body is empty (kt:113-115), not just blank.
            if (this.body.length > 0) {
              Text(this.body)
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.CONTENT_TEXT_SIZE)
                .fontColor(this.bodyColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Start)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        // The content block carries normal_margin top, bottom and end and NO start margin
        // (item_location_card.xml:44-46), so it begins where the drag button ends.
        .margin({
          top: Dimens.NORMAL_MARGIN,
          bottom: Dimens.NORMAL_MARGIN,
          right: Dimens.NORMAL_MARGIN
        })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.rowBackground())
      .translate({ x: this.swipeX })
      .onClick(() => {
        this.onSelect();
      })
    }
    /*
     * The revealed colour is the CONTAINER's own background, exactly as SlidingItemContainerLayout
     * calls `setBackgroundColor` on itself (kt:143,148) and puts one icon in front of the item.
     * Painting it on a child sized `height('100%')` instead made every row expand to the height of
     * the whole list â€” a Stack sizes to its largest child, and a percentage height on a child of an
     * auto-sized Stack resolves against the PARENT, not its siblings.
     */
    .backgroundColor(this.actionBackground())
    // ShapeAppearance.Material3.Corner.Full on a wrap_content card â€” a stadium, so the radius is
    // half the row's height. A large constant gets the same result without measuring.
    .borderRadius(ROW_CORNER_RADIUS)
    .clip(true)
    .width('100%')
    // onChildDraw raises the dragged row by touch_rise_z and puts it above its neighbours.
    .translate({ y: this.dragOffsetY })
    .shadow(this.lifted ? DRAG_SHADOW : NO_SHADOW)
    .zIndex(this.lifted ? 1 : 0)
    .onAreaChange((_: Area, area: Area) => {
      this.rowWidth = Number(area.width);
    })
    /*
     * ItemTouchHelper's swipe, hand-rolled: ArkUI has no equivalent of a RecyclerView item touch
     * helper. Only horizontal pans are claimed, so the enclosing Scroll keeps vertical ones.
     */
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: SWIPE_SLOP })
        .onActionUpdate((event: GestureEvent) => {
          this.swipeX = event.offsetX;
        })
        .onActionEnd(() => {
          this.settleSwipe();
        })
        .onActionCancel(() => {
          this.animateSwipeHome();
        })
    )
  }

  /**
   * ItemTouchHelper's default `getSwipeThreshold` is half the item's width; past it the swipe is
   * committed, short of it the row springs back. Both actions end with the row back in place â€”
   * the settings branch calls notifyItemChanged (kt:91) and a refused delete does the same
   * (kt:100), while a real delete removes the row from the list entirely.
   */
  private settleSwipe(): void {
    const travelled: number = Math.abs(this.swipeX);
    const committed: boolean = this.rowWidth > 0 && travelled > this.rowWidth * SWIPE_THRESHOLD;
    const toDelete: boolean = this.swipeX > 0;
    this.animateSwipeHome();
    if (!committed) {
      return;
    }
    if (toDelete) {
      this.onDelete();
    } else {
      this.onOpenSettings();
    }
  }

  private animateSwipeHome(): void {
    this.getUIContext().animateTo({ duration: SWIPE_SETTLE_MS, curve: Curve.Friction }, () => {
      this.swipeX = 0;
    });
  }

  /** The revealed action's background â€” errorContainer when deleting, the settings pair when not. */
  private actionBackground(): string {
    if (this.swipeX > 0) {
      return AppColors.ERROR_CONTAINER.resolve(this.dark);
    }
    // kt:60-64 â€” a current-position row reveals tertiaryContainer, a saved one secondaryContainer.
    return this.currentPosition
      ? AppColors.TERTIARY_CONTAINER.resolve(this.dark)
      : AppColors.SECONDARY_CONTAINER.resolve(this.dark);
  }

  /** The revealed icon's tint â€” the `on` role that pairs with whatever actionBackground chose. */
  private actionTint(): string {
    if (this.swipeX > 0) {
      return AppColors.ON_ERROR_CONTAINER.resolve(this.dark);
    }
    return this.currentPosition
      ? AppColors.ON_TERTIARY_CONTAINER.resolve(this.dark)
      : AppColors.ON_SECONDARY_CONTAINER.resolve(this.dark);
  }
}

