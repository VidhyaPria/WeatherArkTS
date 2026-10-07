/*
 * The connected button group above each trend chart.
 *
 * Source: DailyViewHolder.kt:93-137 / HourlyViewHolder.kt:91-135 —
 *   - hidden entirely when there are fewer than two tabs (kt:93-95)
 *   - the selected button is checked, tapping another moves the check (kt:122-133)
 *   - overflowMode="menu" (container_main_*_trend_card.xml:52) moves the tail into a "More" menu,
 *     labelled with R.string.action_more (kt:110-113, strings.xml:487)
 */

import { Dimens } from '../../theme/Dimens';
import { TrendTab } from '../../model/TrendTab';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** How many buttons stay inline before the rest move into the overflow menu. */
const INLINE_BUTTON_COUNT: number = 3;

/**
 * Overflow panel width. Measured on the reference device: the panel spans ~565..1007 px on a
 * 1008 px-wide, 2.75-density screen — 442 px, i.e. ~160 dp.
 */
const OVERFLOW_MENU_WIDTH: number = 160;

/** Material3 pressed state-layer opacity. */
const PRESSED_STATE_LAYER_ALPHA: number = 0.1;

/** Material button height — 108 px / 2.75 on the reference device. */
const CHIP_HEIGHT: number = 40;
/** Label padding inside each button, measured off the same capture. */
const CHIP_HORIZONTAL_PADDING: number = 12;

/** Composites `overlay` at `alpha` over the opaque `base`. Both are #AARRGGBB or #RRGGBB. */
function blendOver(base: string, overlay: string, alpha: number): string {
  const b: number[] = channels(base);
  const o: number[] = channels(overlay);
  const mix: (i: number) => number = (i: number) => Math.round(b[i] + (o[i] - b[i]) * alpha);
  return '#FF' + hex(mix(0)) + hex(mix(1)) + hex(mix(2));
}

/** [r, g, b] from #AARRGGBB or #RRGGBB. */
function channels(color: string): number[] {
  const body: string = color.charAt(0) === '#' ? color.slice(1) : color;
  const rgb: string = body.length === 8 ? body.slice(2) : body;
  return [
    parseInt(rgb.slice(0, 2), 16),
    parseInt(rgb.slice(2, 4), 16),
    parseInt(rgb.slice(4, 6), 16)
  ];
}

function hex(value: number): string {
  const clamped: number = Math.max(0, Math.min(255, value));
  return (clamped < 16 ? '0' : '') + clamped.toString(16);
}

@ComponentV2
export struct TrendTabGroup {
  @Param tabs: TrendTab[] = [];
  @Param selectedIndex: number = 0;
  @Param containerColor: string = '#FFDCE3E9';
  @Param selectedContainerColor: string = '#FF00668B';
  @Param labelColor: string = '#FF40484D';
  @Param selectedLabelColor: string = '#FFFFFFFF';
  @Event onSelect: (index: number) => void = () => {
  };

  /**
   * Drives `bindMenu`'s isShow form. The builder-only form of bindMenu opens on its own internal
   * click, which loses the same arbitration race against the enclosing Scroll/Swiper that the
   * chips used to lose ("Click try accept Scroll" / "Click gesture judge reject" in hilog) — that
   * is the delay between tapping ⋮ and the menu appearing. Opening it from a parallel TapGesture
   * instead takes the click out of arbitration entirely.
   */
  @Local private overflowShown: boolean = false;

  /**
   * Which chip the finger is currently on, or -1.
   *
   * A MaterialButton paints its pressed state layer the instant the finger lands, before anything
   * decides whether the gesture is a tap. The port drew nothing until the tab had already changed,
   * so a press had no acknowledgement at all and the button read as unresponsive — the "not as
   * smooth as Android" report. `onTouch` is a raw touch listener, not a recogniser, so it fires
   * immediately and cannot lose arbitration to the Scroll or Swiper the way a click does.
   */
  @Local private pressedIndex: number = -1;

  /**
   * The Material state layer: the label colour at 10% over the container
   * (Widget.Material3.Button, state_layer pressed alpha). Both inputs are #AARRGGBB strings.
   */
  private pressedContainer(index: number): string {
    const base: string = index === this.selectedIndex ? this.selectedContainerColor : this.containerColor;
    if (index !== this.pressedIndex) {
      return base;
    }
    const overlay: string = index === this.selectedIndex ? this.selectedLabelColor : this.labelColor;
    return blendOver(base, overlay, PRESSED_STATE_LAYER_ALPHA);
  }

  /**
   * The tick goes on the TRAILING edge, with the label leading — `endIcon`, not `selectIcon`.
   *
   * Measured off the reference device (`ref_overflow.png` + a uiautomator dump of the open menu):
   * each row is a title TextView spanning x=[603,918] with a `checkbox` node at x=[918,972], the
   * panel ending at ~1005. So the label starts at the leading edge and the tick sits at the far
   * end. `MenuItem(...).selectIcon(true)` draws ArkUI's select icon at the *leading* edge and
   * centres the label, which is why the port had it on the wrong side.
   *
   * The overflowed buttons are `isCheckable = true` MaterialButtons (DailyViewHolder.kt:122-123),
   * which is where the tick comes from — the dump shows Precipitation, the live tab, as the one
   * row with checked="true".
   */
  private itemOptions(name: string, index: number): MenuItemOptions {
    if (index === this.selectedIndex) {
      return { content: name, endIcon: $r('app.media.ic_check') };
    }
    return { content: name };
  }

  @Builder
  overflowMenu() {
    Menu() {
      ForEach(this.tabs.slice(INLINE_BUTTON_COUNT), (tab: TrendTab, offset: number) => {
        MenuItem(this.itemOptions(tab.name, INLINE_BUTTON_COUNT + offset))
          .onClick(() => {
            this.overflowShown = false;
            this.onSelect(INLINE_BUTTON_COUNT + offset);
          })
      }, (tab: TrendTab) => tab.id)
    }
    .width(OVERFLOW_MENU_WIDTH)
  }

  build() {
    // kt:93-95 — a single tab means no group at all.
    if (this.tabs.length >= 2) {
      Row({ space: 2 }) {
        ForEach(this.tabs.slice(0, INLINE_BUTTON_COUNT), (tab: TrendTab, index: number) => {
          Text(tab.name)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            // MaterialButton labels are textAppearanceLabelLarge: 14sp at weight 500.
            .fontWeight(FontWeight.Medium)
            .fontColor(index === this.selectedIndex ? this.selectedLabelColor : this.labelColor)
            // Measured off the reference: buttons are 108 px tall on the 2.75-density device
            // (≈ 40 dp, the Material default) with ~12 dp of horizontal label padding — the
            // port's 16 + text-driven height made the chips shorter and wider than Android's.
            .height(CHIP_HEIGHT)
            .padding({ left: CHIP_HORIZONTAL_PADDING, right: CHIP_HORIZONTAL_PADDING })
            .textAlign(TextAlign.Center)
            .backgroundColor(this.pressedContainer(index))
            // Immediate press acknowledgement, the way a MaterialButton's state layer works.
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedIndex = index;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedIndex = -1;
              }
            })
            // Widget.Material3Expressive.MaterialButtonGroup.Connected: the checked button is a
            // full pill, the unchecked ones are square-ish with a small radius. The port drew
            // every chip as a pill, which is the "they look like different buttons" difference.
            .borderRadius(index === this.selectedIndex ? 20 : 8)
            .maxLines(1)
            // NOT .onClick: these chips sit inside a Scroll inside a Swiper, and a plain click
            // enters exclusive gesture arbitration with both. hilog shows the cost directly —
            // "Click try accept Scroll" / "Click gesture judge reject" — so a tap only resolves
            // once the scroll recogniser gives up, which reads as a very laggy button.
            // A parallel TapGesture is recognised alongside the ancestors instead of after them.
            .parallelGesture(
              TapGesture({ count: 1 })
                .onAction(() => {
                  this.onSelect(index);
                })
            )
        }, (tab: TrendTab) => tab.id)

        if (this.tabs.length > INLINE_BUTTON_COUNT) {
          // Android's overflow is the ⋮ icon and nothing else
          // (MaterialButtonGroup OVERFLOW_BUTTON_TAG, DailyViewHolder.kt:109-113).
          //
          // The inline set is ALWAYS the first three tabs. Picking an item from the overflow
          // only ticks it in the menu and redraws the chart — the three buttons never change and
          // none of them shows as selected. The port used to promote the chosen overflow tab
          // into a fourth chip, which is why the row grew and behaved unlike the Android one.
          Image($r('app.media.ic_more_vert'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(this.labelColor)
            .margin({ left: Dimens.SMALL_MARGIN })
            // On Android the tappable thing is the whole overflow MaterialButton, not the 24dp
            // glyph. responseRegion grows the hit area to 48dp without changing the layout, so
            // taps that land just off the dots still open the menu.
            .responseRegion({ x: '-50%', y: '-50%', width: '200%', height: '200%' })
            // Opened by hand, not by bindMenu's own click — see `overflowShown`.
            .bindMenu(this.overflowShown, this.overflowMenu, {
              onDisappear: () => {
                this.overflowShown = false;
              }
            })
            .parallelGesture(
              TapGesture({ count: 1 })
                .onAction(() => {
                  this.overflowShown = true;
                })
            )
        }
      }
      .margin({ top: Dimens.SMALL_MARGIN, left: Dimens.LARGE_MARGIN })
    }
  }
}
