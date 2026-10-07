/*
 * Location dots.
 *
 * Source: fragment_home.xml:79-89 (dotDiameter 8dp, dotGap 8dp, animationDuration 300,
 * 16dp margin, bottom-centre, starts at alpha 0) and HomeFragment.kt:212-215 (current dot white,
 * the others white at 50%). HomeFragment.kt:315 hides it entirely for a single location, and
 * HomeFragment.kt:462-471 fades it in while the user is dragging.
 */

import { Dimens } from '../../theme/Dimens';
import { AppColors } from '../../theme/AppColors';

const DOT_DIAMETER: number = 8;
const DOT_GAP: number = 8;
const ANIMATION_DURATION: number = 300;

@ComponentV2
export struct InkPageIndicator {
  @Param total: number = 0;
  @Param currentIndex: number = 0;
  /** setDisplayState — true while the user is touching or swiping. */
  @Param displayed: boolean = false;

  build() {
    // fragment_home.xml + HomeFragment.kt:315 — nothing to show for a single location.
    if (this.total > 1) {
      Row({ space: DOT_GAP }) {
        ForEach(this.buildIndices(), (index: number) => {
          Circle()
            .width(DOT_DIAMETER)
            .height(DOT_DIAMETER)
            .fill(index === this.currentIndex ? AppColors.INDICATOR_CURRENT : AppColors.INDICATOR_OTHER)
        }, (index: number) => index.toString())
      }
      .margin(Dimens.NORMAL_MARGIN)
      .opacity(this.displayed ? 1 : 0)
      .animation({ duration: ANIMATION_DURATION, curve: Curve.EaseInOut })
    }
  }

  private buildIndices(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.total; i++) {
      out.push(i);
    }
    return out;
  }
}
