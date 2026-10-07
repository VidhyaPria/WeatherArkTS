/*
 * TimePickerPreferenceView's dialog (TimePickerPreference.kt:147-219, :238-304).
 *
 * Android calls Material 3's `TimePicker(state)`, a CLOCK DIAL. That composable is library code and
 * is NOT in breezy-weather-6.2.1/, so every number below was measured off screenshots of the
 * reference APK rather than read out of the source or recalled from androidx:
 *
 *   ref_screen3d_timepicker.png      12-hour, 07:00 selected
 *   ref_screen3d_timepicker_24h.png  the same at 24-hour
 *
 * Device 1260x2720 at density 3.25, so displayed-px x 0.4187 = dp. What that yielded, and what the
 * two captures settled that guessing would have got wrong:
 *
 *   - 12-hour: ONE ring of 12 numerals, 12 at the top, and an AM/PM toggle beside the readout.
 *   - 24-hour: TWO concentric rings — OUTER 0..11, INNER 12..23, both starting at the top — and no
 *     AM/PM toggle at all.
 *
 * The stored value is "HH:mm" in both modes (kt:222-233 formats with twelveHour = false), so the
 * mode is presentation only and never round-trips.
 *
 * The keyboard button swaps the dial for a TimeInput (kt:213-217); that is ported too, because it
 * is the only way to reach a minute precisely on a 60-step ring.
 */

import { i18n } from '@kit.LocalizationKit';
import { Dimens } from '../../theme/Dimens';
import { AppColors } from '../../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../../common/Typography';
import { WindowMetrics } from '../../common/SystemBars';
/** configuration.screenHeightDp > 400 (TimePickerPreference.kt:173, :213). */
const TIME_PICKER_MIN_HEIGHT: number = 400;

/* ---- measured off the reference; see the header ---- */
const DIALOG_WIDTH: number = 325;
const DIALOG_CORNER: number = 28;
const DIALOG_PADDING: number = 24;
/** typography.labelMedium (kt:273) — a caption, not a heading. */
const TITLE_TEXT_SIZE: number = 12;
/** The hour/minute readout boxes. */
const SELECTOR_WIDTH: number = 96;
const SELECTOR_HEIGHT: number = 80;
const SELECTOR_TEXT_SIZE: number = 45;
const SELECTOR_CORNER: number = 8;
/** The AM/PM toggle, 12-hour only. */
const PERIOD_WIDTH: number = 52;
const PERIOD_CORNER: number = 8;
const PERIOD_TEXT_SIZE: number = 14;
/** The dial. */
const DIAL_SIZE: number = 256;
const RING_OUTER_RADIUS: number = 101;
const RING_INNER_RADIUS: number = 69;
const BALL_RADIUS: number = 24;
const NUMERAL_TEXT_SIZE: number = 16;
const HAND_WIDTH: number = 2;
const ACTION_TEXT_SIZE: number = 14;

const DEG: number = Math.PI / 180;

/** "HH:mm" → hour and minute. A malformed value falls back to midnight, as a parse failure would. */
function parseTime(value: string): number[] {
  const parts: string[] = value.split(':');
  const hour: number = parts.length > 0 ? Number.parseInt(parts[0], 10) : 0;
  const minute: number = parts.length > 1 ? Number.parseInt(parts[1], 10) : 0;
  return [
    Number.isNaN(hour) ? 0 : Math.max(0, Math.min(23, hour)),
    Number.isNaN(minute) ? 0 : Math.max(0, Math.min(59, minute))
  ];
}

/** Back to the stored form, zero-padded — see the file header. */
function pad(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/**
 * How the ROW displays a stored time — Date.getFormattedTime (DateExtensions.kt:111-121) through
 * TimePickerPreference.kt:134. Verified against the reference, which is a 12-hour device and reads
 * "7:00 AM" where a 24-hour one reads "07:00".
 */
export function formatTimeForDisplay(value: string): string {
  const hm: number[] = parseTime(value);
  if (i18n.System.is24HourClock()) {
    return pad(hm[0]) + ':' + pad(hm[1]);
  }
  const suffix: string = hm[0] < 12 ? 'AM' : 'PM';
  const twelve: number = hm[0] % 12 === 0 ? 12 : hm[0] % 12;
  return twelve.toString() + ':' + pad(hm[1]) + ' ' + suffix;
}

@ComponentV2
export struct TimePickerDialog {
  /** The stored "HH:mm". */
  @Param selected: string = '07:00';
  @Param dark: boolean = false;
  @Event onChosen: (value: string) => void = () => {
  };
  @Event onDismiss: () => void = () => {
  };

  @Local private pendingHour: number = 0;
  @Local private pendingMinute: number = 0;
  /** Which field the dial is editing — the hour box is the one selected on open (kt:151-155). */
  @Local private editingMinute: boolean = false;
  /** The keyboard button's state (kt:193, `showingPicker`). */
  @Local private textEntry: boolean = false;
  @Local private hourText: string = '';
  @Local private minuteText: string = '';
  private twentyFourHour: boolean = true;

  aboutToAppear(): void {
    const hm: number[] = parseTime(this.selected);
    this.pendingHour = hm[0];
    this.pendingMinute = hm[1];
    this.hourText = pad(hm[0]);
    this.minuteText = pad(hm[1]);
    this.twentyFourHour = i18n.System.is24HourClock();
  }

  /* ------------------------------------------------------------------- readout ---- */

  /** What the hour box shows: 0-23 as stored, or 1-12 when a period toggle carries the rest. */
  private displayHour(): number {
    if (this.twentyFourHour) {
      return this.pendingHour;
    }
    return this.pendingHour % 12 === 0 ? 12 : this.pendingHour % 12;
  }

  private isPm(): boolean {
    return this.pendingHour >= 12;
  }

  /** Moving the AM/PM toggle keeps the dial hand where it is and shifts by twelve hours. */
  private setPm(pm: boolean): void {
    if (pm === this.isPm()) {
      return;
    }
    this.pendingHour = pm ? this.pendingHour + 12 : this.pendingHour - 12;
  }

  /* ---------------------------------------------------------------------- dial ---- */

  /**
   * A touch anywhere on the dial picks the nearest value.
   *
   * The angle is measured from 12 o'clock, clockwise. For minutes that is one step per 6°; for
   * hours one per 30°. In 24-hour mode the RADIUS decides the ring — inside the midpoint of the
   * two rings is 12..23, outside is 0..11 — which is what the second capture established.
   */
  private onDialTouch(x: number, y: number): void {
    const centre: number = DIAL_SIZE / 2;
    const dx: number = x - centre;
    const dy: number = y - centre;
    let degrees: number = Math.atan2(dx, -dy) / DEG;
    if (degrees < 0) {
      degrees += 360;
    }
    if (this.editingMinute) {
      this.pendingMinute = Math.round(degrees / 6) % 60;
      this.minuteText = pad(this.pendingMinute);
      return;
    }
    const step: number = Math.round(degrees / 30) % 12;
    if (!this.twentyFourHour) {
      // 1..12 on the face; the period toggle supplies the other half.
      const face: number = step === 0 ? 12 : step;
      const base: number = face === 12 ? 0 : face;
      this.pendingHour = this.isPm() ? base + 12 : base;
    } else {
      const radius: number = Math.sqrt(dx * dx + dy * dy);
      const inner: boolean = radius < (RING_OUTER_RADIUS + RING_INNER_RADIUS) / 2;
      this.pendingHour = inner ? step + 12 : step;
    }
    this.hourText = pad(this.pendingHour);
  }

  /** Where the hand points, in degrees clockwise from 12 o'clock. */
  private handAngle(): number {
    if (this.editingMinute) {
      return this.pendingMinute * 6;
    }
    return (this.pendingHour % 12) * 30;
  }

  /** How far out the ball sits — the inner ring only exists in 24-hour mode. */
  private handRadius(): number {
    if (!this.editingMinute && this.twentyFourHour && this.pendingHour >= 12) {
      return RING_INNER_RADIUS;
    }
    return RING_OUTER_RADIUS;
  }

  /**
   * One numeral.
   *
   * `selected` is recomputed HERE from `index` rather than passed in, and the ForEach keys below
   * fold the selection into the key. Both are needed: a @Builder's by-value parameters are not
   * re-evaluated when a @Local changes, and a ForEach whose keys are unchanged never re-diffs its
   * children. Together those left the hand pointing at the new hour while the OLD numeral stayed
   * highlighted and the readout kept the old value — caught on device, not in review.
   */
  @Builder
  numeral(value: number, index: number, radius: number, inner: boolean) {
    Text(this.editingMinute || this.twentyFourHour ? pad(value) : value.toString())
      .fontFamily(SETTINGS_FONT_FAMILY)
      .fontSize(NUMERAL_TEXT_SIZE)
      .fontColor((inner ? this.pendingHour === value : this.isSelectedOuter(index))
        ? AppColors.ON_PRIMARY.resolve(this.dark)
        : AppColors.ON_SURFACE.resolve(this.dark))
      .textAlign(TextAlign.Center)
      .width(BALL_RADIUS * 2)
      .height(BALL_RADIUS * 2)
      .position({
        x: DIAL_SIZE / 2 + radius * Math.sin(index * 30 * DEG) - BALL_RADIUS,
        y: DIAL_SIZE / 2 - radius * Math.cos(index * 30 * DEG) - BALL_RADIUS
      })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  /** The twelve numerals of whichever ring, as a list of [value, index]. */
  private outerValues(): number[] {
    if (this.editingMinute) {
      // The minute face is labelled every five minutes: 00, 05, 10 … 55.
      return [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
    }
    if (this.twentyFourHour) {
      return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
    }
    return [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  }

  /** 24-hour only: the inner ring, 12..23 (ref_screen3d_timepicker_24h.png). */
  private innerValues(): number[] {
    return [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];
  }

  private isSelectedOuter(index: number): boolean {
    if (this.editingMinute) {
      return this.pendingMinute === index * 5;
    }
    if (this.twentyFourHour) {
      return this.pendingHour === index;
    }
    const face: number = this.pendingHour % 12 === 0 ? 12 : this.pendingHour % 12;
    return face === this.outerValues()[index];
  }

  @Builder
  dial() {
    Stack() {
      // The disc.
      Column()
        .width(DIAL_SIZE)
        .height(DIAL_SIZE)
        .borderRadius(DIAL_SIZE / 2)
        .backgroundColor(AppColors.SURFACE_VARIANT.resolve(this.dark))

      // The hand, drawn as a thin bar rotated about the centre, and the ball at its end.
      Column()
        .width(HAND_WIDTH)
        .height(this.handRadius())
        .backgroundColor(AppColors.PRIMARY.resolve(this.dark))
        .position({ x: DIAL_SIZE / 2 - HAND_WIDTH / 2, y: DIAL_SIZE / 2 - this.handRadius() })
        .rotate({ x: 0, y: 0, z: 1, centerX: HAND_WIDTH / 2, centerY: this.handRadius(),
          angle: this.handAngle() })
        .hitTestBehavior(HitTestMode.Transparent)

      Column()
        .width(BALL_RADIUS * 2)
        .height(BALL_RADIUS * 2)
        .borderRadius(BALL_RADIUS)
        .backgroundColor(AppColors.PRIMARY.resolve(this.dark))
        .position({
          x: DIAL_SIZE / 2 + this.handRadius() * Math.sin(this.handAngle() * DEG) - BALL_RADIUS,
          y: DIAL_SIZE / 2 - this.handRadius() * Math.cos(this.handAngle() * DEG) - BALL_RADIUS
        })
        .hitTestBehavior(HitTestMode.Transparent)

      ForEach(this.outerValues(), (value: number, index: number) => {
        this.numeral(value, index, RING_OUTER_RADIUS, false)
      }, (value: number, index: number) =>
        'o' + index.toString() + (this.isSelectedOuter(index) ? 'S' : ''))

      if (this.twentyFourHour && !this.editingMinute) {
        ForEach(this.innerValues(), (value: number, index: number) => {
          this.numeral(value, index, RING_INNER_RADIUS, true)
        }, (value: number, index: number) =>
          'i' + index.toString() + (this.pendingHour === value ? 'S' : ''))
      }
    }
    .width(DIAL_SIZE)
    .height(DIAL_SIZE)
    // A drag moves the hand continuously, which is what the Material dial does.
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        this.onDialTouch(event.touches[0].x, event.touches[0].y);
      }
    })
  }

  /* ------------------------------------------------------------------ readout ----- */

  /*
   * The readout boxes and the AM/PM halves are built INLINE below rather than through @Builder
   * helpers, for the reason `numeral` documents: a @Builder's by-value parameters do not
   * re-evaluate when a @Local changes, which left these showing the previous time.
   */

  build() {
    /*
     * kt:173 / kt:213 — `configuration.screenHeightDp > 400`.
     *
     * In a SHORT viewport Material's dialog is the text input alone: no dial, and no keyboard/clock
     * toggle to get back to one. On this device that is landscape (388 dp tall against 837), and
     * both ports drew the dial there, in a dialog taller than the window.
     *
     * Read here, in build(), and not through a cached field: this is the read that has to re-run on
     * rotation, which is the note at the top of common/TwoPane.ets.
     */
    /*
     * The height test is read INLINE, three times, rather than into a local.
     *
     * Two constraints meet here. A component's build() must be a single root node, so there is
     * nowhere to put a `const` before it. And `WindowMetrics` has to be read DIRECTLY in the build
     * or the rotation does not re-lay-out — a read inside a plain helper does not register as a
     * render dependency, which is the trap common/TwoPane.ets documents. `timePickerHasDial()`
     * exists for callers that are not themselves a build.
     *
     * kt:158-162 also titles the two states apart: `dialog_time_picker_select_time` for the dial,
     * `dialog_time_picker_input_time` for the typed one. With no dial to return to, this dialog is
     * always the input one.
     */
    // The scrim. Tapping it dismisses without storing, like a Material dialog's outside touch.
    Column() {
      Column() {
        Text(WindowMetrics.instance.height > TIME_PICKER_MIN_HEIGHT ? 'Select time' : 'Enter time')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          // kt:271 — padding(bottom = 20.dp) between the title and the picker.
          .margin({ bottom: 20 })

        /* ---- the hour : minute readout, with AM/PM beside it on a 12-hour device ---- */
        Row() {
          Text(pad(this.displayHour()))
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(SELECTOR_TEXT_SIZE)
            .fontColor(this.editingMinute
              ? AppColors.ON_SURFACE.resolve(this.dark)
              : AppColors.ON_PRIMARY_CONTAINER.resolve(this.dark))
            .textAlign(TextAlign.Center)
            .width(SELECTOR_WIDTH)
            .height(SELECTOR_HEIGHT)
            .borderRadius(SELECTOR_CORNER)
            .backgroundColor(this.editingMinute
              ? AppColors.SURFACE_VARIANT.resolve(this.dark)
              : AppColors.PRIMARY_CONTAINER.resolve(this.dark))
            .onClick(() => {
              this.editingMinute = false;
            })

          Text(':')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(SELECTOR_TEXT_SIZE)
            .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
            .textAlign(TextAlign.Center)
            .width(24)

          Text(pad(this.pendingMinute))
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(SELECTOR_TEXT_SIZE)
            .fontColor(this.editingMinute
              ? AppColors.ON_PRIMARY_CONTAINER.resolve(this.dark)
              : AppColors.ON_SURFACE.resolve(this.dark))
            .textAlign(TextAlign.Center)
            .width(SELECTOR_WIDTH)
            .height(SELECTOR_HEIGHT)
            .borderRadius(SELECTOR_CORNER)
            .backgroundColor(this.editingMinute
              ? AppColors.PRIMARY_CONTAINER.resolve(this.dark)
              : AppColors.SURFACE_VARIANT.resolve(this.dark))
            .onClick(() => {
              this.editingMinute = true;
            })

          if (!this.twentyFourHour) {
            Column() {
              Text('AM')
                .fontFamily(SETTINGS_FONT_FAMILY)
                .fontSize(PERIOD_TEXT_SIZE)
                .fontColor(!this.isPm()
                  ? AppColors.ON_TERTIARY_CONTAINER.resolve(this.dark)
                  : AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
                .textAlign(TextAlign.Center)
                .width(PERIOD_WIDTH)
                .height(SELECTOR_HEIGHT / 2)
                .backgroundColor(!this.isPm()
                  ? AppColors.TERTIARY_CONTAINER.resolve(this.dark)
                  : Color.Transparent)
                .borderRadius({ topLeft: PERIOD_CORNER, topRight: PERIOD_CORNER })
                .onClick(() => {
                  this.setPm(false);
                })
              Text('PM')
                .fontFamily(SETTINGS_FONT_FAMILY)
                .fontSize(PERIOD_TEXT_SIZE)
                .fontColor(this.isPm()
                  ? AppColors.ON_TERTIARY_CONTAINER.resolve(this.dark)
                  : AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
                .textAlign(TextAlign.Center)
                .width(PERIOD_WIDTH)
                .height(SELECTOR_HEIGHT / 2)
                .backgroundColor(this.isPm()
                  ? AppColors.TERTIARY_CONTAINER.resolve(this.dark)
                  : Color.Transparent)
                .borderRadius({ bottomLeft: PERIOD_CORNER, bottomRight: PERIOD_CORNER })
                .onClick(() => {
                  this.setPm(true);
                })
            }
            .width(PERIOD_WIDTH)
            .height(SELECTOR_HEIGHT)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .borderRadius(PERIOD_CORNER)
            .borderWidth(1)
            .borderColor(AppColors.COMPOSE_OUTLINE.resolve(this.dark))
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        /* ---- the dial, or the text fields the keyboard button swaps in ---- */
        if (this.textEntry || WindowMetrics.instance.height <= TIME_PICKER_MIN_HEIGHT) {
          Row() {
            TextInput({ text: this.hourText })
              .type(InputType.Number)
              .maxLength(2)
              .width(SELECTOR_WIDTH)
              .height(SELECTOR_HEIGHT)
              .onChange((value: string) => {
                this.hourText = value;
                const parsed: number = Number.parseInt(value, 10);
                if (!Number.isNaN(parsed) && parsed >= 0 && parsed <= 23) {
                  this.pendingHour = parsed;
                }
              })
            Text(':')
              .fontFamily(SETTINGS_FONT_FAMILY)
              .fontSize(SELECTOR_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
              .width(24)
              .textAlign(TextAlign.Center)
            TextInput({ text: this.minuteText })
              .type(InputType.Number)
              .maxLength(2)
              .width(SELECTOR_WIDTH)
              .height(SELECTOR_HEIGHT)
              .onChange((value: string) => {
                this.minuteText = value;
                const parsed: number = Number.parseInt(value, 10);
                if (!Number.isNaN(parsed) && parsed >= 0 && parsed <= 59) {
                  this.pendingMinute = parsed;
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: Dimens.LARGE_MARGIN, bottom: Dimens.LARGE_MARGIN })
        } else {
          Column() {
            this.dial()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: Dimens.LARGE_MARGIN, bottom: Dimens.NORMAL_MARGIN })
        }

        /* ---- keyboard toggle bottom-LEFT, actions bottom-right (kt:184-208, :276-300) ---- */
        Row() {
          // kt:172-210 — the whole `toggle` slot is gated on the same height test, so a short
          // viewport has no button at all rather than one that swaps to a dial it cannot fit.
          if (WindowMetrics.instance.height > TIME_PICKER_MIN_HEIGHT) {
            Image($r('app.media.ic_keyboard'))
              .width(Dimens.MATERIAL_ICON_SIZE)
              .height(Dimens.MATERIAL_ICON_SIZE)
              .fillColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
              .onClick(() => {
                this.textEntry = !this.textEntry;
              })
          }

          Blank()

          Text('CANCEL') // android.R.string.cancel, uppercase on the reference device
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(ACTION_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.NORMAL_MARGIN)
            .onClick(() => {
              this.onDismiss();
            })
          Text('Confirm') // strings.xml:500 `action_confirm` — an app string, so not uppercased
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(ACTION_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.NORMAL_MARGIN)
            .onClick(() => {
              this.onChosen(pad(this.pendingHour) + ':' + pad(this.pendingMinute));
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width(DIALOG_WIDTH)
      .padding(DIALOG_PADDING)
      .backgroundColor(AppColors.DIALOG_SURFACE.resolve(this.dark))
      .borderRadius(DIALOG_CORNER)
      // Swallow taps on the card so they do not reach the scrim behind it.
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#52000000')
    .onClick(() => {
      this.onDismiss();
    })
  }
}
