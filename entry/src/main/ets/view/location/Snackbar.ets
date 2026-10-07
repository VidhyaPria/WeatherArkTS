/*
 * The app's snackbar — a port of org.breezyweather.common.snackbar, not Material's.
 *
 * Breezy Weather ships its own Snackbar rather than using the design library's, so there is a
 * concrete layout, duration and animation to port instead of a platform default to approximate:
 *
 *   SnackbarHelper.kt:36                Snackbar.LENGTH_LONG, always with cardStyle = true
 *                                       (BreezyActivity.kt:82, BreezyFragment.kt:42)
 *   SnackbarManager.kt:203              LENGTH_LONG = 3000 ms, then it dismisses itself
 *   Snackbar.kt:510-511                 ANIMATION_DURATION 450 ms, ANIMATION_FADE_DURATION 200 ms
 *   container_snackbar_layout_inner_card.xml   the card layout, reproduced below
 *
 * WHY THIS EXISTS. The undo after a delete was offered as a `promptAction.showDialog`, which is
 * modal and waits for ever. Android's is neither: it floats over the list, the list stays usable
 * underneath, and after three seconds it leaves and the deletion simply stands. Reported from the
 * device as "the popup remains always until you tap outside", which is exactly right.
 *
 * NOT EXTRACTED FROM THE VENDORED SOURCE, and flagged as such: `design_snackbar_padding_vertical`,
 * `design_snackbar_padding_horizontal`, `design_snackbar_extra_spacing_horizontal` and
 * `design_snackbar_text_max_lines` are referenced by the layout but live in the Material Components
 * library, which is not part of this repository. The library's published values are used below and
 * marked, rather than passed off as extracted.
 */

import { curves } from '@kit.ArkUI';
import { AppColors } from '../../theme/AppColors';
import { Dimens } from '../../theme/Dimens';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** SnackbarManager.kt:203 — LENGTH_LONG. */
const DURATION_MS: number = 3000;
/** Snackbar.kt:510-511. */
const ANIMATION_DURATION: number = 450;
const ANIMATION_FADE_DURATION: number = 200;
/** The inner LinearLayout's padding (container_snackbar_layout_inner_card.xml:15). */
const INNER_PADDING: number = 4;
/** Material Components library values — see the header note. */
const SNACKBAR_PADDING_VERTICAL: number = 14;
const SNACKBAR_PADDING_HORIZONTAL: number = 12;
const SNACKBAR_TEXT_MAX_LINES: number = 2;
/** material_card: 2 dp (styles.xml:100, DEFAULT_CARD_LIST_ITEM_ELEVATION_DP). */
const CARD_ELEVATION: number = 2;
/** getFloatingOvershotEnterAnimators() — the default overshoot factor (DisplayExtensions.kt:255). */
const OVERSHOOT_TENSION: number = 1.5;
/** The card starts at 1.1 and settles to 1 (SnackbarAnimationUtils.kt:33-34). */
const ENTER_SCALE_FROM: number = 1.1;
/** How far below its resting place the card starts; its own height, so it is fully off. */
const ENTER_OFFSET: number = 120;

/**
 * OvershootInterpolator(tension), verbatim from the AOSP formula:
 *   t' = (t-1)^2 * ((tension+1)*(t-1) + tension) + 1
 * It passes 1 and comes back, which is the whole character of the entrance.
 */
function overshoot(fraction: number): number {
  const t: number = fraction - 1.0;
  return t * t * ((OVERSHOOT_TENSION + 1.0) * t + OVERSHOOT_TENSION) + 1.0;
}

/** DecelerateInterpolator(1f) — 1 - (1-t)^2. Drives the two scale animators. */
function decelerate(fraction: number): number {
  const inv: number = 1.0 - fraction;
  return 1.0 - inv * inv;
}

@ComponentV2
export struct Snackbar {
  @Param message: string = '';
  /** strings.xml `action_undo`. Empty means no action, as setAction(null) does. */
  @Param actionLabel: string = '';
  @Param dark: boolean = false;

  /** The action was tapped. The bar leaves immediately, as Snackbar.kt's action listener does. */
  @Event onAction: () => void = () => {
  };
  /**
   * The bar has finished leaving, for any reason. The caller drops it from its state here — timing
   * out is NOT a cancellation: the deletion stands, exactly as letting Android's snackbar expire.
   */
  @Event onDismissed: () => void = () => {
  };

  @Local private offsetY: number = ENTER_OFFSET;
  // Named `cardScale`, not `scale`: CustomComponent already declares a `scale` attribute method and
  // a state variable of that name collides with it.
  @Local private cardScale: number = ENTER_SCALE_FROM;
  @Local private contentOpacity: number = 0;

  private timer: number = -1;
  /** Guards against the timeout and a tap both trying to dismiss. */
  private leaving: boolean = false;

  aboutToAppear(): void {
    // translationY height -> 0 on an overshoot, scale 1.1 -> 1 on a decelerate, played together.
    this.getUIContext().animateTo({
      duration: ANIMATION_DURATION,
      curve: curves.customCurve(overshoot)
    }, () => {
      this.offsetY = 0;
    });
    this.getUIContext().animateTo({
      duration: ANIMATION_DURATION,
      curve: curves.customCurve(decelerate)
    }, () => {
      this.cardScale =1.0;
    });
    // animateChildrenIn(ANIMATION_DURATION - ANIMATION_FADE_DURATION, ANIMATION_FADE_DURATION)
    // (Snackbar.kt:246-249) — the text fades in over the tail of the slide, not with it.
    this.getUIContext().animateTo({
      duration: ANIMATION_FADE_DURATION,
      delay: ANIMATION_DURATION - ANIMATION_FADE_DURATION
    }, () => {
      this.contentOpacity = 1.0;
    });

    this.timer = setTimeout(() => {
      this.leave();
    }, DURATION_MS);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  /** animateViewOut (Snackbar.kt:260-269) — back down by its own height, fast-out-slow-in. */
  private leave(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    this.getUIContext().animateTo({
      duration: ANIMATION_DURATION,
      curve: curves.cubicBezierCurve(0.4, 0.0, 0.2, 1.0),
      onFinish: () => {
        this.onDismissed();
      }
    }, () => {
      this.offsetY = ENTER_OFFSET;
    });
  }

  build() {
    Row() {
      Text(this.message)
        .fontFamily(APP_FONT_FAMILY)
        // title_text (styles.xml:150-153) — title_text_size, 16 sp. The style's colour is
        // overridden by the layout to colorOnSurfaceInverse.
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE_INVERSE.resolve(this.dark))
        .maxLines(SNACKBAR_TEXT_MAX_LINES)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({
          top: SNACKBAR_PADDING_VERTICAL,
          bottom: SNACKBAR_PADDING_VERTICAL,
          left: SNACKBAR_PADDING_HORIZONTAL,
          right: SNACKBAR_PADDING_HORIZONTAL
        })

      if (this.actionLabel.length > 0) {
        // A borderless button: no container, colorTertiaryContainer, bold (layout :46-48).
        Text(this.actionLabel)
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.TERTIARY_CONTAINER.resolve(this.dark))
          .maxLines(1)
          .padding({
            top: SNACKBAR_PADDING_VERTICAL,
            bottom: SNACKBAR_PADDING_VERTICAL,
            left: SNACKBAR_PADDING_HORIZONTAL,
            right: SNACKBAR_PADDING_HORIZONTAL
          })
          .onClick(() => {
            // The listener runs, then the bar leaves — the row is already back by the time the
            // slide-out finishes, which is what Android shows too.
            this.onAction();
            this.leave();
          })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(INNER_PADDING)
    .backgroundColor(AppColors.SURFACE_INVERSE.resolve(this.dark))
    // material3_card_list_item_corner_radius, 16 dp (dimens.xml:24).
    .borderRadius(Dimens.NORMAL_MARGIN)
    .shadow({
      radius: CARD_ELEVATION * 2,
      color: '#33000000',
      offsetY: CARD_ELEVATION
    })
    // material_card's margins, all small_margin (styles.xml:96-98) with the layout's own
    // marginTop of small_margin (container_snackbar_layout_inner_card.xml:7).
    .margin({
      left: Dimens.SMALL_MARGIN,
      right: Dimens.SMALL_MARGIN,
      bottom: Dimens.SMALL_MARGIN,
      top: Dimens.SMALL_MARGIN
    })
    .translate({ y: this.offsetY })
    .scale({ x: this.cardScale, y: this.cardScale })
    .opacity(this.contentOpacity)
  }
}
