/*
 * One half-width detail block (precipitation, wind, humidity, …).
 *
 * Layout from container_main_humidity.xml, shared by every half-size block:
 *   content  square — layout_constraintDimensionRatio="1:1" (:19)
 *   inset    guidelines at 8% / 92% on both axes (:24-50)
 *   icon     square, sized to the title, at the start guideline (:52-69)
 *   title    textAppearanceLabelLarge at title_text_size (16sp), bold,
 *            ?attr/colorSurfaceInverse, 4dp after the icon (:71-88)
 *   value    Weather.TextAppearance.MainBlock.NumberDigit = 45sp (styles.xml:310-314)
 *   extra    optional secondary row, e.g. the dew point badge (:104-143)
 *
 * Shape is a property of the card type, declared by each layout's app:shapeAppearance:
 * Corner.Full (circle) for wind, air quality, visibility and pressure; Corner.ExtraLarge
 * (28dp rect) for precipitation, pollen, humidity and astro. Circular blocks centre their
 * title, value and secondary line; rectangular blocks left-align all three. The unit
 * ("mm", "m/s", "%") is rendered smaller beside the number.
 *
 * The whole card is the tap target (e.g. HumidityViewHolder.kt:89-95).
 */

import { Dimens } from '../../theme/Dimens';
import {
  claimEnterTiming,
  decelerateCurve,
  ENTER_SCALE_FROM,
  ENTER_TRANSLATION_Y,
  EnterTiming,
  hasEntered,
  markEntered,
  overshootCurve
} from '../../common/EnterAnimation';
import { DetailScreen } from '../../model/DetailScreen';
import { PollenEntry } from '../../model/Weather';
import { AppColors, pollenLevelColor } from '../../theme/AppColors';
import { DetailBlock } from './DetailBlocks';
import { ArcProgressCanvas } from './ArcProgressCanvas';
import { AstroArcCanvas } from './AstroArcCanvas';
import { MoonPhaseCanvas } from './MoonPhaseCanvas';
import { APP_FONT_FAMILY } from '../../common/Typography';
import { AppSettings } from '../../data/SettingsStore';
import { ClockHandsCanvas } from './ClockHandsCanvas';
import { ClockTicker } from './ClockTicker';
import { localHours, localMinutes } from '../../common/LocalTime';
import { i18n } from '@kit.LocalizationKit';

/** container_main_humidity.xml dew_point_circle — android:padding="12dp". */
const DEW_POINT_CIRCLE_PADDING: number = 12;
/** Large enough that the 1:1 box always renders as a full circle. */
const DEW_POINT_CIRCLE_RADIUS: string = '50%';

/** Level dot beside each allergen row. */
const POLLEN_DOT_SIZE: number = 20;

/* Guideline insets are per-block now and live on DetailBlock — no layout shares one value. */
/** styles.xml:310-314 */
const NUMBER_DIGIT_TEXT_SIZE: number = 45;
/** container_main_humidity.xml:85 — gap between the title icon and the title. */
const TITLE_ICON_GAP: number = 4;
/** The unit sits noticeably smaller than the number. */
const UNIT_TEXT_SIZE: number = 20;
/** container_main_astro.xml:63-64 */
const ASTRO_TITLE_ICON_SIZE: number = 20;

/*
 * container_main_clock.xml:57-99 — the two TextClocks.
 *
 * `autoSizeTextType="uniform"` over 50..130sp at 1sp granularity, in a box that is 80 % of the
 * square split in half. Rather than reimplement autosizing, the settled size was measured off the
 * reference: the digits paint 138 px tall on a 552 px card, and Roboto's cap height is 0.711 em,
 * so 138 / 0.711 / 3.25 px-per-vp = 59.7 -> 60. That is a whole step of the 1sp granularity, which
 * is the check that it is the size autosize actually chose rather than a number that merely fits.
 */
const CLOCK_DIGIT_TEXT_SIZE: number = 60;

@ComponentV2
export struct HalfBlockCard {
  @Param block: DetailBlock =
    new DetailBlock('', $r('app.media.ic_gauge'), '', '', '', DetailScreen.TAG_CONDITIONS);
  @Param cardBackground: string = '#FFFCFCFF';
  @Param contentColor: string = '#FF191C1E';
  @Param secondaryColor: string = '#FF40484D';
  /** Selects the light/dark shadow alpha the astro arc fades with (SunMoonView.kt:336-337). */
  @Param isDark: boolean = false;
  /**
   * Square side in vp. The caller always knows it — a card is half the content width less its own
   * 8dp margin per side — so it is passed in rather than measured.
   *
   * This used to fall back to the card's own `onAreaChange`. A trace during a drag showed 94 nodes
   * with area-change callbacks being evaluated every frame; twelve of them were these cards,
   * re-measuring to a value the parent had already computed exactly. `MainScreen.blockSide()`
   * produces the identical number, and it is available on the first frame — which the measured
   * value was not, and which is why an un-hinted drag preview used to rasterise empty.
   */
  @Param presetSide: number = 0;
  @Event onCardClick: () => void = () => {
  };

  /* Entrance state — see EnterAnimation.ets. Starts hidden and 120vp low, like Android. */
  @Local private enterOpacity: number = 0;
  @Local private enterOffsetY: number = ENTER_TRANSLATION_Y;
  @Local private enterScale: number = ENTER_SCALE_FROM;
  private enterStarted: boolean = false;

  /**
   * AbstractMainViewHolder.checkEnterScreen (kt:61-79) runs the entrance the first time the card
   * is laid out within the host's height, and never again. onVisibleAreaChange is the ArkUI
   * equivalent; the guard makes it once-only.
   */
  private startEnterAnimation(): void {
    if (this.enterStarted) {
      return;
    }
    this.enterStarted = true;
    markEntered(this.block.id);
    const timing: EnterTiming = claimEnterTiming();
    animateTo({
      duration: timing.duration,
      delay: timing.delay,
      curve: overshootCurve(timing.overshootTension)
    }, () => {
      this.enterOffsetY = 0;
    });
    animateTo({
      duration: timing.duration,
      delay: timing.delay,
      curve: decelerateCurve()
    }, () => {
      this.enterOpacity = 1;
      this.enterScale = 1;
    });
  }

  aboutToAppear(): void {
    // The Clock block is the only one with a life of its own; see ClockTicker for the boundary
    // alignment and why the timer is reference-counted across the Swiper's pages.
    if (this.block.isClock) {
      ClockTicker.instance.start();
    }
    // A card that has already played its entrance must never play it again.
    //
    // `enterStarted` is a per-instance field, so it only guards the lifetime of one component
    // instance. Reordering the grid bumps orderVersion, the cards re-render, and each one
    // restarted from opacity 0 with a staggered claimEnterTiming() delay — up to 200 ms per
    // pending card. That is what made the tiles "disappear and blink" during a drag, and it
    // happened with both drag implementations because it was never the drag's fault.
    //
    // AbstractMainViewHolder.checkEnterScreen (kt:61-79) runs the entrance once per card and
    // never again, so the record has to outlive the component: it is keyed by block id.
    //
    // screen 3c's `list_animation_switch` short-circuits the same way: AbstractMainViewHolder only
    // hides the card (kt:53-55) when the setting is on, so off starts settled rather than playing
    // a zero-length animation. See EnterAnimated, which carries the same gate for the full-width
    // cards.
    if (!AppSettings.instance.cardsFadeIn || hasEntered(this.block.id)) {
      this.enterStarted = true;
      markEntered(this.block.id);
      this.enterOpacity = 1;
      this.enterOffsetY = 0;
      this.enterScale = 1;
    }
    // There is deliberately NO "reveal after N seconds" safety net here. There used to be a 3 s
    // one, and it was why the tiles never animated in on scroll: the whole grid is laid out at
    // once, so every below-the-fold card had already been forced to its final state long before
    // the user scrolled down to it. onVisibleAreaChange is reliable for these cards — they are
    // real laid-out nodes inside the page Scroll — so the entrance can simply wait for it, which
    // is what checkEnterScreen does on Android.
  }

  /**
   * The square side. A plain method, not a `get` accessor: accessors declared on a struct are not
   * available on the instance at render time.
   */
  private side(): number {
    return this.presetSide;
  }

  /*
   * Insets come from each block's own layout now (DetailBlock.inset*Percent). They were
   * previously guessed from the card's shape — 8% for rectangles and double that for circles —
   * but no layout uses 16%: the circular blocks are all 20%, which is why their contents looked
   * enlarged next to the Android build.
   */
  private horizontalInset(): number {
    return this.isAstro() ? Dimens.SMALL_MARGIN : this.side() * this.block.insetHorizontalPercent;
  }

  private topInset(): number {
    return this.side() * this.block.insetTopPercent;
  }

  private bottomInset(): number {
    return this.side() * this.block.insetBottomPercent;
  }

  private isAstro(): boolean {
    return this.block.astro !== null;
  }

  aboutToDisappear(): void {
    if (this.block.isClock) {
      ClockTicker.instance.stop();
    }
  }

  /**
   * The location's hour, 0-23. Reading `ClockTicker.instance` through `now()` is what subscribes
   * this card to the minute boundary — without it the tile would render once and then stand still.
   */
  private clockHour(): number {
    return localHours(ClockTicker.now(), this.block.clockUtcOffsetSeconds);
  }

  private clockMinute(): number {
    return localMinutes(ClockTicker.now(), this.block.clockUtcOffsetSeconds);
  }

  /**
   * `format12Hour="hh"` / `format24Hour="HH"` (container_main_clock.xml:79-80) — both are
   * zero-padded two-digit, and "hh" makes midnight and noon read 12 rather than 00.
   */
  private clockHourText(): number {
    const h: number = this.clockHour();
    // Same source the time picker uses (TimePickerDialog.ets:79) — the system's own setting, which
    // is what `is12Hour` resolves to on Android.
    if (i18n.System.is24HourClock()) {
      return h;
    }
    const twelve: number = h % 12;
    return twelve === 0 ? 12 : twelve;
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + value.toString() : value.toString();
  }

  /**
   * The astro card is the exception: its SunMoonView ignores the guidelines in favour of an 8dp
   * side margin (container_main_astro.xml:56-57), so the card pads to 8dp and its text rows make
   * up the remaining distance to the 10% guideline themselves.
   */
  private astroTextInset(): number {
    if (!this.isAstro()) {
      return 0;
    }
    return Math.max(0, this.side() * this.block.insetHorizontalPercent - Dimens.SMALL_MARGIN);
  }

  private horizontalAlign(): HorizontalAlign {
    return this.block.isCircle ? HorizontalAlign.Center : HorizontalAlign.Start;
  }

  private rowAlign(): FlexAlign {
    return this.block.isCircle ? FlexAlign.Center : FlexAlign.Start;
  }

  private textAlign(): TextAlign {
    return this.block.isCircle ? TextAlign.Center : TextAlign.Start;
  }

  build() {
    // Outer wrapper carries the 8dp card margin (AbstractMainCardViewHolder.kt:52-59).
    Column() {
      Stack() {
        // Decorative fill behind the content — humidity waves, visibility blob, wind blob.
        // The vectors ship with ?attr/colorTertiaryContainer (or sys_widget_background) as
        // their fill, so they are exported white and tinted here.
        // Tinted shapes (waves, blobs) ship as white vectors; the UV sun keeps its own
        // baked-in petal colours, so it must not be tinted.
        if (this.block.shape !== null && this.block.shapeTint.length > 0) {
          Image(this.block.shape)
            .width('100%')
            .height('100%')
            .objectFit(this.block.shapeFitsInside ? ImageFit.Contain : ImageFit.Cover)
            .fillColor(this.block.shapeTint)
            .rotate({ angle: this.block.shapeRotation })
            .hitTestBehavior(HitTestMode.Transparent)
        } else if (this.block.shape !== null) {
          Image(this.block.shape)
            .width('100%')
            .height('100%')
            .objectFit(this.block.shapeFitsInside ? ImageFit.Contain : ImageFit.Cover)
            .rotate({ angle: this.block.shapeRotation })
            .hitTestBehavior(HitTestMode.Transparent)
        }

        // Ring gauge for the air-quality and pressure blocks.
        if (this.block.arcProgress >= 0 && this.side() > 0) {
          ArcProgressCanvas({
            progress: this.block.arcProgress,
            max: this.block.arcMax,
            progressColor: this.block.arcColor,
            trackColor: this.block.arcBackground,
            side: this.side(),
            redrawKey: this.block.id + '@' + this.side().toString()
          })
        }

        if (this.block.isClock) {
          /*
           * container_main_clock.xml:57-99. The LinearLayout is `match_parent` WIDE and 0dp tall
           * between the 10 % and 90 % guidelines, so it ignores the 0.2/0.8 vertical guidelines it
           * is also constrained to — a match_parent child overrides its own side constraints. Both
           * TextClocks carry layout_weight="1", so each takes exactly half the remaining height;
           * the hour is gravity bottom and the minute gravity top, which is what closes the gap
           * between the two rows of digits.
           */
          Column() {
            Text(HalfBlockCard.pad2(this.clockHourText()))
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(CLOCK_DIGIT_TEXT_SIZE)
              .fontColor(AppColors.PRIMARY.resolve(this.isDark))
              .maxLines(1)
              .width('100%')
              .height('50%')
              .textAlign(TextAlign.Center)
              .align(Alignment.Bottom)
            Text(HalfBlockCard.pad2(this.clockMinute()))
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(CLOCK_DIGIT_TEXT_SIZE)
              .fontColor(AppColors.PRIMARY.resolve(this.isDark))
              .maxLines(1)
              .width('100%')
              .height('50%')
              .textAlign(TextAlign.Center)
              .align(Alignment.Top)
          }
          .width('100%')
          .height('100%')
          .padding({ top: this.topInset(), bottom: this.bottomInset() })

          // The AnalogClock sits LAST in the layout, so its hands are drawn over both the shape
          // and the digits — clearly visible crossing the "05" in the reference capture.
          ClockHandsCanvas({
            side: this.side(),
            hour: this.clockHour(),
            minute: this.clockMinute(),
            redrawKey: this.block.id + '@' + this.side().toString() + '@' +
              this.clockHour().toString() + ':' + this.clockMinute().toString()
          })
        } else {
        Column() {
        // Title row — icon + label.
        Row() {
          // container_main_astro.xml:63-64 sizes the astro title icon at 20sp; the other
          // blocks match it to the title text size.
          Image(this.block.icon)
            .width(this.isAstro() ? ASTRO_TITLE_ICON_SIZE : Dimens.TITLE_TEXT_SIZE)
            .height(this.isAstro() ? ASTRO_TITLE_ICON_SIZE : Dimens.TITLE_TEXT_SIZE)
            .fillColor(this.contentColor)
          Text(this.block.title)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.TITLE_TEXT_SIZE)
            .fontColor(this.contentColor)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: TITLE_ICON_GAP })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(this.rowAlign())
        .padding({ left: this.astroTextInset(), right: this.astroTextInset() })

        // Pollen lists its allergens instead of a number, each with a level dot.
        if (this.block.pollenRows.length > 0) {
          Column() {
            ForEach(this.block.pollenRows, (row: PollenEntry) => {
              Row() {
                Circle()
                  .width(POLLEN_DOT_SIZE)
                  .height(POLLEN_DOT_SIZE)
                  .fill(pollenLevelColor(row.level))
                Column() {
                  Text(row.name)
                    .fontFamily(APP_FONT_FAMILY)
                    .fontSize(Dimens.TITLE_TEXT_SIZE)
                    .fontColor(this.contentColor)
                    .fontWeight(FontWeight.Bold)
                    .maxLines(1)
                  Text(row.levelName)
                    .fontFamily(APP_FONT_FAMILY)
                    .fontSize(Dimens.CONTENT_TEXT_SIZE)
                    .fontColor(this.secondaryColor)
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: Dimens.SMALL_MARGIN })
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: Dimens.SMALL_MARGIN })
            }, (row: PollenEntry) => row.name)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.block.astro !== null) {
          // Sun / Moon (container_main_astro.xml). The arc sits directly under the title with
          // only an 8dp side margin (:56-57), so it is wider than the 10% text guidelines; the
          // rise/set row is spread_inside between them (:99), and the phase row is centred with
          // its baseline on the bottom guideline (:136-151).
          Column() {
            AstroArcCanvas({
              side: this.side() - 2 * Dimens.SMALL_MARGIN,
              progress: this.block.astroProgress,
              lineColor: this.block.astroLineColor,
              backgroundLineColor: this.block.astroTrackColor,
              lightTheme: !this.isDark,
              icon: this.block.astroIcon,
              redrawKey: this.block.id + '@' + this.side().toString()
            })

            Row() {
              Text(this.block.astro.riseTime)
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.TITLE_TEXT_SIZE)
                .fontColor(this.contentColor)
                .maxLines(1)
              Blank()
              Text(this.block.astro.setTime)
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.TITLE_TEXT_SIZE)
                .fontColor(this.contentColor)
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: this.astroTextInset(), right: this.astroTextInset() })
            .margin({ top: Dimens.SMALL_MARGIN })

            if (this.block.astro.phase.length > 0) {
              Row() {
                // MoonViewHolder.kt:57-64 — the phase disc only appears when the phase is valid.
                MoonPhaseCanvas({
                  discSize: Dimens.TITLE_TEXT_SIZE,
                  surfaceAngle: this.block.astro.phaseAngle,
                  strokeColor: this.secondaryColor,
                  redrawKey: this.block.id + '@' + this.block.astro.phaseAngle.toString()
                })
                Text(this.block.astro.phase)
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(Dimens.TITLE_TEXT_SIZE)
                  .fontColor(this.contentColor)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  // container_main_astro.xml:126 — 4dp between the disc and the label.
                  .margin({ left: 4 })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .justifyContent(FlexAlign.Center)
              .padding({ left: this.astroTextInset(), right: this.astroTextInset() })
              .margin({ top: Dimens.SMALL_MARGIN })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.block.unitOnOwnLine) {
          // container_main_pressure.xml:99-126 — the number spans the full card width and the
          // unit sits on its own line beneath it at textAppearanceLabelLarge, bottom-aligned to
          // the lower guideline. Keeping "1016 hPa" on one line is what forced the number wide.
          Column() {
            Text(this.block.value)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(NUMBER_DIGIT_TEXT_SIZE)
              .minFontSize(22)
              .maxFontSize(NUMBER_DIGIT_TEXT_SIZE)
              .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
              .fontColor(this.contentColor)
              .maxLines(1)
              .textAlign(TextAlign.Center)
              .width('100%')
              // container_main_pressure.xml:107 — android:paddingVertical="4dp"
              .padding({ top: 4, bottom: 4 })
            Text(this.block.unit)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.TITLE_TEXT_SIZE)
              .fontColor(this.contentColor)
              .maxLines(1)
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
        // Big value with its smaller unit, vertically centred in the remaining band.
        Row() {
          // Four-digit values (pressure in hPa) overflow a circular card at the full 45sp,
          // so the number shrinks to fit rather than spilling past the curved edge.
          Text(this.block.value)
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(NUMBER_DIGIT_TEXT_SIZE)
            .minFontSize(22)
            .maxFontSize(NUMBER_DIGIT_TEXT_SIZE)
            .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
            .fontColor(this.contentColor)
            .maxLines(1)
            // Bounded width so shrink-to-fit has something to shrink against — but NOT
            // layoutWeight, which would stretch the number and shove the unit to the far edge
            // instead of keeping it adjacent ("1.2 mm", not "1.2        mm").
            .constraintSize({ maxWidth: '76%' })
          if (this.block.unit.length > 0) {
            Text(this.block.unit)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(UNIT_TEXT_SIZE)
              .fontColor(this.contentColor)
              .maxLines(1)
              .margin({ left: 4, bottom: 6 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Bottom)
        .justifyContent(this.rowAlign())
        }

        // Optional secondary row (the humidity block's dew point badge).
        // Most blocks carry a label only ("Daytime precipitation", "Gusts: 8 mph", "Fair",
        // "Clear"); humidity is the one that pairs a value with it ("58° Dew point").
        if (this.block.secondaryLabel.length > 0 || this.block.secondaryValue.length > 0) {
          Row() {
            if (this.block.secondaryValue.length > 0) {
              if (this.block.secondaryIsChip) {
                // dew_point_circle: an oval of ?attr/colorTertiary, 12 dp of padding around a
                // titleMedium value in ?attr/colorOnTertiary. Android sizes it 1:1 from the space
                // left under humidity_value; here the text's own height plus that padding gives
                // the same circle without a second layout pass.
                Text(this.block.secondaryValue)
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(Dimens.TITLE_TEXT_SIZE)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.ON_TERTIARY.resolve(this.isDark))
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .padding(DEW_POINT_CIRCLE_PADDING)
                  .aspectRatio(1)
                  .backgroundColor(AppColors.TERTIARY.resolve(this.isDark))
                  .borderRadius(DEW_POINT_CIRCLE_RADIUS)
              } else {
                Text(this.block.secondaryValue)
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(Dimens.CONTENT_TEXT_SIZE)
                  .fontColor(this.contentColor)
                  .maxLines(1)
              }
            }
            Text(this.block.secondaryLabel)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.CONTENT_TEXT_SIZE)
              .fontColor(this.block.secondaryIsChip
                ? AppColors.ON_TERTIARY_CONTAINER.resolve(this.isDark)
                : this.secondaryColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: this.block.secondaryValue.length > 0 ? Dimens.SMALL_MARGIN : 0 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(this.rowAlign())
        }
        }
        .width('100%')
        .height('100%')
        .padding({
          left: this.horizontalInset(),
          right: this.horizontalInset(),
          top: this.topInset(),
          bottom: this.bottomInset()
        })
        .alignItems(this.horizontalAlign())
        }
      }
      .width('100%')
      .aspectRatio(1)
      // The UV block has no card behind it at all.
      .backgroundColor(this.block.hasCard ? this.cardBackground : Color.Transparent)
      // ShapeAppearance.Material3.Corner.Full is just the square card at a 50% radius.
      // Expressed as a percentage rather than `this.side / 2`: `side` is only known after the
      // first onAreaChange, so a measured radius makes every freshly created card — including
      // the drag preview and anything ForEach rebuilds — flash as a rectangle first.
      .borderRadius(this.block.isCircle ? '50%' : Dimens.CARD_CORNER_RADIUS)
      .shadow(this.block.hasCard ? {
        radius: Dimens.CARD_ELEVATION * 2,
        color: '#20000000',
        offsetX: 0,
        offsetY: Dimens.CARD_ELEVATION
      } : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
      .clip(true)
      .onClick(() => {
        this.onCardClick();
      })
    }
    .width('100%')
    .padding(Dimens.SMALL_MARGIN)
    .opacity(this.enterOpacity)
    .translate({ y: this.enterOffsetY })
    .scale({ x: this.enterScale, y: this.enterScale })
    .onVisibleAreaChange([0.0, 1.0], (_isExpanding: boolean, currentRatio: number) => {
      if (currentRatio > 0) {
        this.startEnterAnimation();
      }
    })
  }
}
