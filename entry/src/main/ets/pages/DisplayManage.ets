/*
 * Screens 3h / 3i / 3j â€” Blocks, Daily trends, Hourly trends.
 *
 * ONE page for all three, because Android is three Activities over one layout and one adapter shape
 * (CardDisplayManageActivity.kt, DailyTrendDisplayManageActivity.kt,
 * HourlyTrendDisplayManageActivity.kt â€” the same file three times, differing only in which enum
 * they edit). Which list is being edited arrives as a router parameter.
 *
 * References captured before this was written:
 *   ref_screen3h_blocks.png   ref_screen3i_daily.png   ref_screen3j_hourly.png
 *
 * The shape (activity_card_display_manage.xml):
 *
 *   toolbar      a SMALL toolbar â€” back arrow + title, on a 6 dp elevated surface. NOT the
 *                LargeTopAppBar every other screen-3 page uses; these are View activities.
 *   list         one 56 dp row per ENABLED item, divided by a 1 px colorOutline rule:
 *                  drag handle (primary) | title | optional gear (primary) | âœ• (primary)
 *                padded 128 dp at the bottom so the chip bar never covers the last row.
 *   bottom bar   a horizontal row of Assist chips, one per DISABLED item. Tapping one appends it
 *                to the list. The bar slides away when there are none.
 *
 * Every gesture Android has is here: drag the handle to reorder, swipe a row either way to delete,
 * tap âœ• to delete, tap the gear to open that card's own manage screen, tap a chip to bring it back.
 *
 * The write happens on `onPageHide`, not per edit â€” CardDisplayManageActivity.kt:186-199 writes in
 * `onStop`, and only if the list actually changed, precisely so a drag does not write per frame.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { APP_FONT_FAMILY } from '../common/Typography';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark, displayListValue, setDisplayList } from '../data/SettingsStore';
import {
  DisplayItem,
  DisplayList,
  displayListRemainder,
  displayListToValue,
  listFromKey,
  parseDisplayList,
  titleFor
} from '../model/DisplayCatalogue';

/** `?attr/actionBarSize` â€” the small toolbar these activities use. */
const TOOLBAR_HEIGHT: number = 56;
/** Material 3 Toolbar title, `titleLarge`. A library token; the library is not vendored here. */
const TOOLBAR_TITLE_SIZE: number = 22;
/** item_card_display.xml:7 â€” the row is a fixed 56 dp, not content-sized. */
const ROW_HEIGHT: number = 56;
/** `@style/material_image_button`: a 40 dp box with 8 dp padding, so a 24 dp glyph. */
const ICON_BUTTON_SIZE: number = 40;
/** activity_card_display_manage.xml:38. */
const LIST_BOTTOM_PADDING: number = 128;
/** Widget.Material3.Chip.Assist. */
const CHIP_HEIGHT: number = 32;
const CHIP_CORNER: number = 8;
const CHIP_H_PADDING: number = 16;
/** The bottom bar's entrance/exit â€” kt:206-229. */
const BAR_IN_MS: number = 350;
const BAR_OUT_MS: number = 150;

/** The router parameter this page is pushed with. */
export class DisplayManageParams {
  which: string = 'blocks';
}

@Entry
@ComponentV2
struct DisplayManage {
  private insets: SystemInsets = SystemInsets.instance;

  @Local private dark: boolean = false;
  @Local private list: DisplayList = DisplayList.BLOCKS;
  /** The live order. Reassigned wholesale on every change â€” a mutation would notify nothing. */
  @Local private items: DisplayItem[] = [];
  /** The chips, derived from `items` but held explicitly so the bar can animate independently. */
  @Local private chips: DisplayItem[] = [];
  @Local private barVisible: boolean = false;
  @Local private barAlpha: number = 0;
  @Local private barShift: number = 0;

  /*
   * The drag, started by the HANDLE â€” as Android does (CardDisplayAdapter.kt:52-57) and as the NDK
   * port does. See the handle's onTouch for how the List is kept out of the gesture.
   *
   * `dragId` is the row under the finger, `dragFrom` the slot it started in, `dragDY` the raw
   * window-space offset. Rows other than the dragged one re-lay out instantly, which is what the
   * NDK does too, so the two ports move identically.
   */
  @Local private dragId: string = '';
  @Local private dragFrom: number = -1;
  @Local private dragDY: number = 0;
  private dragStartY: number = 0;

  /** What was stored when the page opened, so onPageHide can skip a no-op write (kt:188-190). */
  private storedOnEntry: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as DisplayManageParams;
    this.list = listFromKey(params !== undefined && params !== null ? params.which : 'blocks');
    this.storedOnEntry = displayListValue(this.list);
    this.items = parseDisplayList(this.list, this.storedOnEntry);
    this.chips = displayListRemainder(this.list, this.items);
    // kt:181-183 â€” the bar starts hidden and is shown by the first resetBottomBarVisibility().
    this.barVisible = this.chips.length > 0;
    this.barAlpha = this.barVisible ? 1 : 0;
    this.barShift = this.barVisible ? 0 : CHIP_HEIGHT + Dimens.NORMAL_MARGIN * 2;
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
    /*
     * The Blocks screen's gear opens ANOTHER manage screen, and that screen writes its own list on
     * the way out. Nothing this page shows depends on it, but the summary on screen 3c does, so the
     * stored value is re-read rather than assumed.
     */
    const stored: string = displayListValue(this.list);
    if (stored !== displayListToValue(this.items)) {
      this.storedOnEntry = stored;
      this.items = parseDisplayList(this.list, stored);
      this.chips = displayListRemainder(this.list, this.items);
    }
  }

  /** kt:186-199 â€” write on the way out, and only if the list actually changed. */
  onPageHide(): void {
    const value: string = displayListToValue(this.items);
    if (value !== this.storedOnEntry) {
      this.storedOnEntry = value;
      setDisplayList(this.list, value);
    }
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  /* ---------------------------------------------------------------- the list's own edits ------ */

  /** kt:158-166 â€” the chip is removed and the item appended to the list. */
  private restoreChip(index: number): void {
    if (index < 0 || index >= this.chips.length) {
      return;
    }
    const restored: DisplayItem = this.chips[index];
    const chips: DisplayItem[] = this.chips.slice();
    chips.splice(index, 1);
    this.chips = chips;
    const next: DisplayItem[] = this.items.slice();
    next.push(restored);
    this.items = next;
    this.resetBarVisibility();
  }

  /** kt:206-229 â€” the bar slides in over 350 ms and out over 150 ms, and only when it flips. */
  private resetBarVisibility(): void {
    const visible: boolean = this.chips.length > 0;
    if (visible === this.barVisible) {
      return;
    }
    this.barVisible = visible;
    const hidden: number = CHIP_HEIGHT + Dimens.NORMAL_MARGIN * 2;
    this.getUIContext().animateTo({
      duration: visible ? BAR_IN_MS : BAR_OUT_MS,
      curve: visible ? Curve.FastOutSlowIn : Curve.FastOutLinearIn
    }, () => {
      this.barAlpha = visible ? 1 : 0;
      this.barShift = visible ? 0 : hidden;
    });
  }

  /* ---------------------------------------------------------------------- the drag ------------ */

  /**
   * ItemTouchHelper.onMove (kt:66-75) â€” `add(toPosition, removeAt(fromPosition))`, a MOVE rather
   * than a swap, so everything between the two ends shifts by one.
   */
  private indexOfId(source: DisplayItem[], id: string): number {
    for (let i = 0; i < source.length; i++) {
      if (source[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  /** The dragged row rides with the finger; every other row sits where the model puts it. */
  private translationFor(id: string): number {
    if (this.dragId !== id) {
      return 0;
    }
    const now: number = this.indexOfId(this.items, id);
    return this.dragDY - (now - this.dragFrom) * ROW_HEIGHT;
  }

  /** ItemTouchHelper.onMove (kt:66-75), rounded to whole rows against the frozen start slot. */
  private reorderFromPointer(): void {
    if (this.dragId.length === 0) {
      return;
    }
    const now: number = this.indexOfId(this.items, this.dragId);
    if (now < 0) {
      return;
    }
    let target: number = this.dragFrom + Math.round(this.dragDY / ROW_HEIGHT);
    target = Math.max(0, Math.min(this.items.length - 1, target));
    if (target !== now) {
      this.moveItem(now, target);
    }
  }

  private moveItem(from: number, to: number): void {
    if (from < 0 || from >= this.items.length || to < 0 || to >= this.items.length || from === to) {
      return;
    }
    const next: DisplayItem[] = this.items.slice();
    next.splice(to, 0, next.splice(from, 1)[0]);
    this.items = next;
  }

  /* ------------------------------------------------------------------------ builders ---------- */

  @Builder
  iconButton(icon: Resource) {
    Image(icon)
      .width(Dimens.MATERIAL_ICON_SIZE)
      .height(Dimens.MATERIAL_ICON_SIZE)
      .fillColor(AppColors.PRIMARY.resolve(this.dark))
  }

  /** The errorContainer bar an item swipes away over â€” item_card_display.xml:10-15. */
  @Builder
  deleteBackground() {
    Row() {
      Image($r('app.media.ic_delete'))
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .fillColor(AppColors.ON_ERROR_CONTAINER.resolve(this.dark))
        .margin({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
    }
    .height(ROW_HEIGHT)
    .backgroundColor(AppColors.ERROR_CONTAINER.resolve(this.dark))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  row(item: DisplayItem) {
    Row() {
      /*
       * The handle STARTS THE DRAG on touch-down, exactly as Android does
       * (CardDisplayAdapter.kt:52-57) and exactly as the NDK port does.
       *
       * `hitTestBehavior(HitTestMode.Block)` is what makes that possible, and it is the one thing
       * that works. Three earlier attempts all died the same way â€” instrumented, the drag was
       * cancelled ~10 vp in, every time â€” because the enclosing List's scroll recogniser claimed
       * the gesture at touch slop and the framework then delivered TouchType.Cancel to the child:
       *
       *   a vertical PanGesture                                    the list scrolled instead
       *   raw onTouch + enableScrollInteraction(false) on the DOWN  cancelled at ~10 vp
       *   the same + event.stopPropagation()                        cancelled at ~10 vp
       *
       * `stopPropagation` stops the event BUBBLING; it does not stop the ancestor being a touch
       * target in the first place, which is why it changed nothing. `HitTestMode.Block` removes the
       * ancestors from the hit-test chain for this finger, so the List never joins the arena and
       * has nothing to win.
       */
      Row() {
        this.iconButton($r('app.media.ic_drag'))
      }
      .width(ICON_BUTTON_SIZE)
      .height(ICON_BUTTON_SIZE)
      .margin({ left: Dimens.SMALL_MARGIN })
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => {
        if (event.touches.length === 0) {
          return;
        }
        // windowY, not y: the row translates under the finger, and a component-relative
        // coordinate would feed that movement back into the offset.
        const windowY: number = event.touches[0].windowY;
        if (event.type === TouchType.Down) {
          this.dragId = item.id;
          this.dragFrom = this.indexOfId(this.items, item.id);
          this.dragStartY = windowY;
          this.dragDY = 0;
        } else if (event.type === TouchType.Move) {
          if (this.dragId !== item.id) {
            return;
          }
          this.dragDY = windowY - this.dragStartY;
          this.reorderFromPointer();
        } else {
          this.dragId = '';
          this.dragFrom = -1;
          this.dragDY = 0;
        }
      })

      Text(item.name)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: Dimens.SMALL_MARGIN })

      // CardDisplay.configure (kt:63-71) â€” present on exactly two rows, and only on Blocks.
      if (item.configures.length > 0) {
        Row() {
          this.iconButton($r('app.media.ic_settings'))
        }
        .width(ICON_BUTTON_SIZE)
        .height(ICON_BUTTON_SIZE)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const params = new DisplayManageParams();
          params.which = item.configures;
          router.pushUrl({ url: 'pages/DisplayManage', params: params })
            .catch((error: Error) => {
              console.error('could not open ' + item.configures + ': ' + error.message);
            });
        })
      }

      Row() {
        this.iconButton($r('app.media.ic_close'))
      }
      .width(ICON_BUTTON_SIZE)
      .height(ICON_BUTTON_SIZE)
      .margin({ right: Dimens.SMALL_MARGIN })
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.removeItem(item.id);
      })
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
  }

  /** Removal by id, so the âœ• and the swipe agree even mid-drag. */
  private removeItem(id: string): void {
    const index: number = this.indexOfId(this.items, id);
    if (index < 0) {
      return;
    }
    const removed: DisplayItem = this.items[index];
    const next: DisplayItem[] = this.items.slice();
    next.splice(index, 1);
    this.items = next;
    const chips: DisplayItem[] = this.chips.slice();
    chips.push(removed);
    this.chips = chips;
    this.resetBarVisibility();
  }

  @Builder
  chip(item: DisplayItem, index: number) {
    Text(item.name)
      .fontFamily(APP_FONT_FAMILY)
      .fontSize(Dimens.CONTENT_TEXT_SIZE)
      .fontWeight(FontWeight.Bold) // item_tag.xml:8
      .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
      .height(CHIP_HEIGHT)
      .padding({ left: CHIP_H_PADDING, right: CHIP_H_PADDING })
      .borderRadius(CHIP_CORNER)
      .borderWidth(1)
      .borderColor(AppColors.COMPOSE_OUTLINE.resolve(this.dark))
      .margin({ right: Dimens.NORMAL_MARGIN })
      .onClick(() => {
        this.restoreChip(index);
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
        Row() {
          Image($r('app.media.ic_back'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .margin({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              router.back();
            })

          Text(titleFor(this.list))
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(TOOLBAR_TITLE_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
            .maxLines(1)
            .layoutWeight(1)
        }
        .width('100%')
        // The bar reaches under the status bar and pads itself down, as FitSystemBarAppBarLayout does.
        .height(TOOLBAR_HEIGHT + this.insets.top)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppColors.ELEVATED_SURFACE_6.resolve(this.dark))
        .padding({ top: this.insets.top })

        List() {
          ForEach(this.items, (item: DisplayItem) => {
            ListItem() {
              Column() {
                this.row(item)
                // ListDecoration â€” a hairline in colorOutline between rows.
                Divider()
                  .strokeWidth(1)
                  .color(AppColors.OUTLINE.resolve(this.dark))
              }
              .width('100%')
            }
            .translate({ y: this.translationFor(item.id) })
            .zIndex(this.dragId === item.id ? 1 : 0)
            .swipeAction({
              start: {
                builder: () => {
                  this.deleteBackground();
                },
                onAction: () => {
                  this.removeItem(item.id);
                },
                actionAreaDistance: 56
              },
              end: {
                builder: () => {
                  this.deleteBackground();
                },
                onAction: () => {
                  this.removeItem(item.id);
                },
                actionAreaDistance: 56
              }
            })
          }, (item: DisplayItem) => item.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ bottom: LIST_BOTTOM_PADDING })
        // Held off for the whole drag, so the list cannot scroll out from under the row. The
        // handle's HitTestMode.Block already keeps the List out of the gesture; this stops a
        // second finger scrolling mid-drag.
        .enableScrollInteraction(this.dragId.length === 0)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.SURFACE.resolve(this.dark))
      .padding({ left: this.insets.left, right: this.insets.right })

      // The chip bar. Always built; it rides off the bottom when there is nothing in it.
      Scroll() {
        Row() {
          ForEach(this.chips, (item: DisplayItem, index: number) => {
            this.chip(item, index)
          }, (item: DisplayItem) => 'chip_' + item.id)
        }
        .padding({ left: Dimens.NORMAL_MARGIN, top: Dimens.NORMAL_MARGIN, bottom: Dimens.NORMAL_MARGIN })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      // Chips start at the leading edge, as the horizontal RecyclerView does; a Scroll centres
      // its content by default and that put a single chip in the middle of the bar.
      .align(Alignment.Start)
      .width('100%')
      .backgroundColor(AppColors.BACKGROUND.resolve(this.dark))
      .padding({ bottom: this.insets.bottom, left: this.insets.left, right: this.insets.right })
      .opacity(this.barAlpha)
      .translate({ y: this.barShift })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
  }
}
