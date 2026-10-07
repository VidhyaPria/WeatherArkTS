/*
 * The staggered card entrance.
 *
 * Port of MainModuleUtils.getEnterAnimator (ui/main/utils/MainModuleUtils.kt:31-48) together with
 * View.getFloatingOvershotEnterAnimators (common/extensions/DisplayExtensions.kt:264-277) and the
 * bookkeeping in AbstractMainViewHolder.checkEnterScreen / executeEnterAnimator (kt:61-96).
 *
 * Each card, the first time it scrolls into view, plays:
 *   alpha        0    -> 1
 *   translationY 120dp -> 0   OvershootInterpolator(0.4 + 0.2 * pendingCount)
 *   scaleX/Y     1.025 -> 1   DecelerateInterpolator(1f)
 * with duration = max(500 - pendingCount * 50, 250) and startDelay = pendingCount * 200.
 *
 * `pendingCount` is the number of entrances already in flight — that is what produces the
 * cascade rather than every visible card animating at once. Android keeps it as
 * pendingAnimatorList and drops an entry once that entry's startDelay has elapsed (kt:90-93);
 * the same is modelled here with a module-level counter.
 */

import { curves } from '@kit.ArkUI';

/** MainModuleUtils.kt:34 — dpToPx(120f) */
const TRANSLATION_Y: number = 120;
/** MainModuleUtils.kt:35-36 */
const SCALE_FROM: number = 1.025;
/** MainModuleUtils.kt:29 */
const BASE_ENTER_DURATION: number = 500;
/** MainModuleUtils.kt:46 */
const DELAY_PER_PENDING: number = 200;
/** MainModuleUtils.kt:45 */
const DURATION_REDUCTION_PER_PENDING: number = 50;

/** Mirrors pendingAnimatorList.size at the moment an entrance is scheduled. */
let pendingCount: number = 0;

export class EnterTiming {
  readonly delay: number;
  readonly duration: number;
  /** OvershootInterpolator tension — MainModuleUtils.kt:33. */
  readonly overshootTension: number;

  constructor(delay: number, duration: number, overshootTension: number) {
    this.delay = delay;
    this.duration = duration;
    this.overshootTension = overshootTension;
  }
}

export const ENTER_TRANSLATION_Y: number = TRANSLATION_Y;
export const ENTER_SCALE_FROM: number = SCALE_FROM;

/**
 * Claims the next slot in the cascade. The caller starts its animation immediately with the
 * returned delay; the slot frees itself once that delay has passed, exactly as the Kotlin does.
 */
/**
 * Which cards have already played their entrance, by block id.
 *
 * AbstractMainViewHolder.checkEnterScreen (kt:61-79) runs the entrance once per card for the
 * lifetime of the screen. A per-component guard cannot express that, because reordering the grid
 * re-renders the cards and a fresh instance would start from opacity 0 again.
 */
const enteredBlockIds: Set<string> = new Set<string>();

export function hasEntered(blockId: string): boolean {
  return enteredBlockIds.has(blockId);
}

export function markEntered(blockId: string): void {
  enteredBlockIds.add(blockId);
}

export function claimEnterTiming(): EnterTiming {
  const index: number = pendingCount;
  pendingCount++;
  const delay: number = index * DELAY_PER_PENDING;
  const duration: number = Math.max(
    BASE_ENTER_DURATION - index * DURATION_REDUCTION_PER_PENDING,
    BASE_ENTER_DURATION / 2
  );
  setTimeout(() => {
    pendingCount = Math.max(0, pendingCount - 1);
  }, delay);
  return new EnterTiming(delay, duration, 0.4 + 0.2 * index);
}

/**
 * A cubic bezier standing in for OvershootInterpolator(tension). Android's curve is
 * `t' = t - 1; t'*t'*((tension + 1) * t' + tension) + 1`, which lands past 1 and settles back;
 * the control point's y is lifted by the tension to reproduce that overshoot.
 */
export function overshootCurve(tension: number): ICurve {
  return curves.cubicBezierCurve(0.34, 1 + tension * 0.55, 0.64, 1);
}

/** DisplayExtensions.kt:54 — DecelerateInterpolator(1f). */
export function decelerateCurve(): ICurve {
  return curves.cubicBezierCurve(0, 0, 0.58, 1);
}
