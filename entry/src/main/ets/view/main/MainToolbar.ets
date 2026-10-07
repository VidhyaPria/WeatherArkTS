/*
 * Port of the MaterialToolbar in fragment_home.xml:23-35 plus its handlers in
 * HomeFragment.kt:193-207 and the menu in res/menu/activity_main.xml.
 *
 * Layout: transparent background, ?attr/actionBarSize (64dp, dimens.xml:36), 8dp end padding,
 * navigation icon ic_list tinted ?attr/colorSurfaceInverse, title in the same colour with
 * textAppearanceHeadline6.
 *
 * Handlers:
 *   navigation icon      -> onManageIconClicked   (HomeFragment.kt:193-195)
 *   action_edit          -> onEditIconClicked     (kt:199, shown as an icon, showAsAction=ifRoom)
 *   overflow             -> ic_more_vert          (kt:207)
 *   action_open_in_other_app -> onOpenInOtherAppIconClicked (kt:200, showAsAction=never)
 *
 * Both menu items stay hidden until a location has loaded (kt:204-205, 279-284).
 */

import { Dimens } from '../../theme/Dimens';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** textAppearanceHeadline6 is 20sp. */
const TOOLBAR_TITLE_TEXT_SIZE: number = 20;
/**
 * The Toolbar's own `titleMarginStart`, on top of the navigation button's width.
 *
 * MEASURED on the reference, not guessed: the navigation ImageButton occupies [0,182] (56 dp at
 * 3.25 px/dp) and the title TextView starts at 195, i.e. exactly 4 dp later. Neither
 * fragment_home.xml nor this project's styles set a title margin, so it is the Material toolbar
 * default and it applies to this port too. Both ports placed the title flush at 56 dp.
 */
const TOOLBAR_TITLE_MARGIN_START: number = 4;

@ComponentV2
export struct MainToolbar {
  @Param title: string = '';
  /** Controls both menu items, matching the Kotlin visibility rule. */
  @Param hasLocation: boolean = false;
  @Param contentColor: string = '#FF191C1E';
  @Event onManageIconClicked: () => void = () => {
  };
  @Event onEditIconClicked: () => void = () => {
  };
  @Event onOpenInOtherAppIconClicked: () => void = () => {
  };

  @Builder
  overflowMenu() {
    Menu() {
      // activity_main.xml:11-16 — "Open in another app" (strings.xml:475).
      MenuItem({
        startIcon: $r('app.media.ic_open_in_new'),
        content: 'Open in another app'
      })
        .onClick(() => {
          this.onOpenInOtherAppIconClicked();
        })
    }
  }

  build() {
    Row() {
      // Navigation icon — "Location list" (strings.xml:467).
      Image($r('app.media.ic_list'))
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .fillColor(this.contentColor)
        .margin({ left: Dimens.NORMAL_MARGIN })
        .onClick(() => {
          this.onManageIconClicked();
        })

      Text(this.title)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(TOOLBAR_TITLE_TEXT_SIZE)
        .fontColor(this.contentColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: Dimens.NORMAL_MARGIN + TOOLBAR_TITLE_MARGIN_START })

      if (this.hasLocation) {
        // activity_main.xml:5-9 — "Edit this location" (strings.xml:474).
        Image($r('app.media.ic_edit'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(this.contentColor)
          .margin({ right: Dimens.NORMAL_MARGIN })
          .onClick(() => {
            this.onEditIconClicked();
          })

        Image($r('app.media.ic_more_vert'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(this.contentColor)
          .bindMenu(this.overflowMenu)
      }
    }
    .width('100%')
    .height(Dimens.ACTION_BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .padding({ right: Dimens.SMALL_MARGIN })
  }
}
