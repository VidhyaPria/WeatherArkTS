/*
 * The card drag-and-reorder state, as one observed object.
 *
 * It used to be nine `@Local` fields on MainScreen. They have to move somewhere ArkUI can observe
 * from a CHILD component, because the detail grid is being extracted out of MainScreen into
 * `LocationPage` — and a child cannot watch its parent's @Local. An @ObservedV2 class passed down
 * as a @Param gives the grid the same per-field reactivity it had when it lived in the parent.
 *
 * The LOGIC does not move: MainScreen still owns `reorderFromPointer`, `endDrag` and the rest, and
 * mutates these fields exactly as before. This is only where the values live.
 *
 * Which fields are @Trace and which are not is deliberate, and follows what the render reads:
 *   traced      everything the grid draws from — the dragged id, the live offsets, the per-card
 *               shifts, the displaced card's transient glide, and the commit counter
 *   not traced  `cardOrder` and `dragBaseOrder`, which are read only by the drag ARITHMETIC.
 *               `cardOrder` is deliberately mutated silently during a gesture (MainAdapter.kt:
 *               305-311 swaps entries with no rebuild); making it observable would re-render the
 *               ForEach on every pointer crossing, which is exactly the 72 ms in-gesture frame an
 *               earlier session removed.
 */

/**
 * Hoisted: a fresh object per call reads as a changed attribute on every pan event.
 *
 * The raised-card shadow constants stay in MainScreen — they carry that screen's own measured
 * values (radius 24 / offsetY 6) and are not the same as the location list's.
 */
export const NO_TRANSLATE: TranslateOptions = { x: 0, y: 0 };

@ObservedV2
export class DragState {
  /** The card under the finger, or empty. Survives the drop settle so the card glides home. */
  @Trace draggingId: string = '';
  /** Raw finger travel since the gesture began. */
  @Trace dragDX: number = 0;
  @Trace dragDY: number = 0;
  /** Each card's persistent shift from the frozen snapshot to the live order. */
  @Trace shiftedTranslates: Map<string, TranslateOptions> = new Map();
  /** The card displaced by the latest crossing, mid-glide. */
  @Trace displacedId: string = '';
  @Trace displacedDX: number = 0;
  @Trace displacedDY: number = 0;
  /** Bumped only on the commit, after the gesture — this is what rebuilds the grid, once. */
  @Trace orderVersion: number = 0;

  /**
   * The order the ForEach renders. Mutated SILENTLY during a gesture, on purpose — see the note at
   * the top of this file.
   */
  cardOrder: string[] = [];
  /** The snapshot frozen at long-press; every translate is measured against it. */
  dragBaseOrder: string[] = [];

  /** Android's swap (MainAdapter.kt:305-311) — two entries exchanged, not a move. */
  swap(from: number, to: number): void {
    if (from < 0 || to < 0 || from >= this.cardOrder.length || to >= this.cardOrder.length) {
      return;
    }
    const moved: string = this.cardOrder[from];
    this.cardOrder[from] = this.cardOrder[to];
    this.cardOrder[to] = moved;
  }

  /**
   * The live offset for one card. The at-rest case returns a shared constant rather than a fresh
   * object: this runs for all twelve cards on every pan event, and a new reference each time is a
   * changed attribute, which a previous session traced to 1146 JSAnimation slices flushing in one
   * 281 ms frame at the release.
   */
  translationFor(blockId: string): TranslateOptions {
    if (this.draggingId === blockId) {
      return { x: this.dragDX, y: this.dragDY };
    }
    const base: TranslateOptions | undefined = this.shiftedTranslates.get(blockId);
    if (this.displacedId === blockId) {
      const baseX: number = base !== undefined ? base.x as number : 0;
      const baseY: number = base !== undefined ? base.y as number : 0;
      return { x: baseX + this.displacedDX, y: baseY + this.displacedDY };
    }
    return base !== undefined ? base : NO_TRANSLATE;
  }
}
