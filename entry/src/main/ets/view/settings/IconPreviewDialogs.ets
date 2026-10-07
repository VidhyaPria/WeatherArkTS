/*
 * The three dialogs the icon-preview screen opens — one per icon family.
 *
 *   Daytime / Nighttime          AnimatableIconDialog  (PreviewIconActivity.kt:183)
 *   Minimal Daytime / Nighttime  MinimalIconDialog     (kt:197)
 *   Shortcuts Daytime / Nighttime AdaptiveIconDialog   (kt:210)
 *   Sun & moon                   nothing — SunIcon.onItemClicked is "// do nothing." (kt:222)
 *
 * All three are `MaterialAlertDialogBuilder` with `.setTitle(code.name + "_DAY"/"_NIGHT")` and a
 * custom view. That title is the WeatherCode ENUM NAME, which is not the same set of names this
 * port's WeatherKind uses — see `weatherCodeName`.
 *
 * These are VIEW dialogs, not Compose ones, so their container is ALERT_DIALOG_SURFACE (the
 * Material 3 baseline #ECE6F0 / #2B2930) rather than the DIALOG_SURFACE the preference dialogs
 * take. Both were sampled off the reference; see AppColors.
 */

import { Dimens } from '../../theme/Dimens';
import { AppColors } from '../../theme/AppColors';
import { SETTINGS_FONT_FAMILY, LineHeights } from '../../common/Typography';
import { WeatherKind } from '../../model/WeatherKind';
import { AnimatedWeatherIcon, iconBaseName } from '../common/AnimatedWeatherIcon';

/** MaterialAlertDialog's title is headlineSmall. */
const DIALOG_TITLE_TEXT_SIZE: number = 24;
/** @dimen/current_weather_icon_container_size (dimens.xml). */
const ANIMATABLE_ICON_CONTAINER: number = 128;
/** dialog_adaptive_icon.xml:11-12 — a fixed 108dp view. */
const ADAPTIVE_ICON_SIZE: number = 108;

/**
 * The Android `WeatherCode` enum name, which is what the dialog titles show.
 *
 * WeatherCode.kt:21-32 names them CLEAR, PARTLY_CLOUDY, CLOUDY, RAIN, … — this port's WeatherKind
 * calls the same three CLOUD, RAINY and so on, so a straight `WeatherKind[kind]` would title the
 * dialog "CLOUD_DAY" where the reference reads "PARTLY_CLOUDY_DAY".
 */
export function weatherCodeName(kind: WeatherKind, daytime: boolean): string {
  let name: string;
  switch (kind) {
    case WeatherKind.CLEAR: name = 'CLEAR'; break;
    case WeatherKind.CLOUD: name = 'PARTLY_CLOUDY'; break;
    case WeatherKind.CLOUDY: name = 'CLOUDY'; break;
    case WeatherKind.RAINY: name = 'RAIN'; break;
    case WeatherKind.SNOW: name = 'SNOW'; break;
    case WeatherKind.WIND: name = 'WIND'; break;
    case WeatherKind.FOG: name = 'FOG'; break;
    case WeatherKind.HAZE: name = 'HAZE'; break;
    case WeatherKind.SLEET: name = 'SLEET'; break;
    case WeatherKind.HAIL: name = 'HAIL'; break;
    case WeatherKind.THUNDER: name = 'THUNDER'; break;
    case WeatherKind.THUNDERSTORM: name = 'THUNDERSTORM'; break;
    default: name = ''; break;
  }
  return name + (daytime ? '_DAY' : '_NIGHT');
}

/**
 * The five masks `AdaptiveIconView.setPath` can be given.
 *
 * `AdaptiveIconDialog.kt:47` picks one with `Random().nextInt(AdaptiveIconView.PATH_TEARDROP + 1)`,
 * so teardrop is the highest constant and there are five in total.
 *
 * The library (com.github.breezy-weather:AdaptiveIconView:0.0.3) is a Gradle dependency and is NOT
 * vendored in this tree, so its exact path geometry cannot be read the way an app resource can.
 * These are the standard Android adaptive-icon masks the library provides, expressed as corner
 * radii on the 108 dp square. The one the reference happened to roll — teardrop, three round
 * corners and a tight bottom-right — is reproduced from the capture; the other four are the
 * standard shapes. This is the one place on this screen not taken from a readable source, and it
 * is recorded as such rather than presented as measured.
 */
enum AdaptiveMask {
  CIRCLE = 0,
  SQUIRCLE = 1,
  ROUNDED_SQUARE = 2,
  SQUARE = 3,
  TEARDROP = 4
}

/** Corner radii in percent of the side, clockwise from top-left. */
function maskRadii(mask: AdaptiveMask): string[] {
  switch (mask) {
    case AdaptiveMask.CIRCLE: return ['50%', '50%', '50%', '50%'];
    // A squircle is a superellipse; a 42 % radius is its closest rounded-rect equivalent.
    case AdaptiveMask.SQUIRCLE: return ['42%', '42%', '42%', '42%'];
    case AdaptiveMask.ROUNDED_SQUARE: return ['20%', '20%', '20%', '20%'];
    case AdaptiveMask.SQUARE: return ['0', '0', '0', '0'];
    default: return ['50%', '50%', '12%', '50%'];
  }
}

/* ---------------------------------------------------------------------------------------------
 * AnimatableIconDialog — dialog_animatable_icon.xml
 * ------------------------------------------------------------------------------------------- */

@ComponentV2
export struct AnimatableIconDialog {
  @Param kind: WeatherKind = WeatherKind.NULL;
  @Param daytime: boolean = true;
  @Param dark: boolean = false;
  @Event onDismiss: () => void = () => {
  };

  /**
   * Remount key for the icon.
   *
   * `container.setOnClickListener { iconView.startAnimators() }` (kt:44) replays the set from the
   * top. This port's AnimatedWeatherIcon starts its loop in aboutToAppear and wraps around by
   * itself, exactly as AnimatableIconView does when its set ends, so the only thing a tap has to
   * do is put it back at step 0 — which is what dropping and rebuilding the component does.
   */
  @Local private replay: number = 0;
  @Local private mounted: boolean = true;

  private restart(): void {
    this.mounted = false;
    this.replay++;
    setTimeout(() => {
      this.mounted = true;
    }, 0);
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#52000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Text(weatherCodeName(this.kind, this.daytime))
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(DIALOG_TITLE_TEXT_SIZE)
          .lineHeight(LineHeights.HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')

        // The FrameLayout: the icon is centred with a normal_margin all round, and the WHOLE
        // container is the tap target that replays the animation.
        Column() {
          if (this.mounted) {
            AnimatedWeatherIcon({
              kind: this.kind,
              daytime: this.daytime,
              iconSize: ANIMATABLE_ICON_CONTAINER,
              animated: true
            })
          }
        }
        .width('100%')
        .height(ANIMATABLE_ICON_CONTAINER + Dimens.NORMAL_MARGIN * 2)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.restart();
        })
      }
      .width(Dimens.DIALOG_WIDTH)
      .padding({
        left: Dimens.DIALOG_PADDING,
        right: Dimens.DIALOG_PADDING,
        top: Dimens.DIALOG_PADDING
      })
      .backgroundColor(AppColors.ALERT_DIALOG_SURFACE.resolve(this.dark))
      .borderRadius(Dimens.DIALOG_CORNER_RADIUS)
      // Swallow taps so they do not reach the scrim.
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}

/* ---------------------------------------------------------------------------------------------
 * MinimalIconDialog — dialog_minimal_icon.xml
 * ------------------------------------------------------------------------------------------- */

@ComponentV2
export struct MinimalIconDialog {
  @Param kind: WeatherKind = WeatherKind.NULL;
  @Param daytime: boolean = true;
  @Param dark: boolean = false;
  @Event onDismiss: () => void = () => {
  };

  /**
   * The three variants, in the layout's order: light, grey, dark
   * (dialog_minimal_icon.xml:14-70, MinimalIconDialog.kt:38-50).
   *
   * These are the `_mini_light` / `_mini_grey` / `_mini_dark` assets, resolved by name off the same
   * base the animated icon uses. The grey family had to be copied in from the Android source; the
   * port previously shipped only light and dark, because nothing on any ported screen asked for
   * grey — `getMinimalIcon` picks between light and dark by theme and never needs the third.
   */
  private variantFor(suffix: string): Resource {
    return $r('app.media.' + iconBaseName(this.kind, this.daytime) + '_mini_' + suffix);
  }

  @Builder
  private cell(suffix: string) {
    // SquareFrameLayout with weight 1, and the image inset by material_icon_size on every side.
    Column() {
      Image(this.variantFor(suffix))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
    }
    .layoutWeight(1)
    .aspectRatio(1)
    .padding(Dimens.MATERIAL_ICON_SIZE)
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#52000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Text(weatherCodeName(this.kind, this.daytime))
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(DIALOG_TITLE_TEXT_SIZE)
          .lineHeight(LineHeights.HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')

        Row() {
          this.cell('light')
          this.cell('grey')
          this.cell('dark')
        }
        .width('100%')
      }
      .width(Dimens.DIALOG_WIDTH)
      .padding({
        left: Dimens.DIALOG_PADDING,
        right: Dimens.DIALOG_PADDING,
        top: Dimens.DIALOG_PADDING
      })
      .backgroundColor(AppColors.ALERT_DIALOG_SURFACE.resolve(this.dark))
      .borderRadius(Dimens.DIALOG_CORNER_RADIUS)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}

/* ---------------------------------------------------------------------------------------------
 * AdaptiveIconDialog — dialog_adaptive_icon.xml
 * ------------------------------------------------------------------------------------------- */

@ComponentV2
export struct AdaptiveIconDialog {
  @Param kind: WeatherKind = WeatherKind.NULL;
  @Param daytime: boolean = true;
  @Param dark: boolean = false;
  /**
   * Which mask this showing rolled. Chosen by the OPENER, not here: kt:48 rolls it once as the
   * dialog is built, so it must not change while the dialog is on screen — an @Local seeded from
   * Math.random() in the struct would re-roll on every rebuild.
   */
  @Param maskIndex: number = 0;
  @Event onDismiss: () => void = () => {
  };

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#52000000')
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        Text(weatherCodeName(this.kind, this.daytime))
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(DIALOG_TITLE_TEXT_SIZE)
          .lineHeight(LineHeights.HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')

        Column() {
          /*
           * AdaptiveIcon(foreground, Color.TRANSPARENT.toDrawable(), 0.5) — the FOREGROUND layer
           * only, clipped to the rolled mask. The background is transparent, so what shows through
           * the mask is whatever the foreground PNG carries, which is why the reference's teardrop
           * reads as a pale disc with the sun on it rather than as a coloured tile.
           */
          Image($r('app.media.shortcuts_' + shortcutBaseName(this.kind, this.daytime) +
            '_foreground'))
            .width(ADAPTIVE_ICON_SIZE)
            .height(ADAPTIVE_ICON_SIZE)
            .objectFit(ImageFit.Contain)
            .borderRadius({
              topLeft: maskRadii(this.maskIndex as AdaptiveMask)[0],
              topRight: maskRadii(this.maskIndex as AdaptiveMask)[1],
              bottomRight: maskRadii(this.maskIndex as AdaptiveMask)[2],
              bottomLeft: maskRadii(this.maskIndex as AdaptiveMask)[3]
            })
            .clip(true)
        }
        .width('100%')
        .height(ADAPTIVE_ICON_SIZE + Dimens.NORMAL_MARGIN * 2)
        .justifyContent(FlexAlign.Center)
      }
      .width(Dimens.DIALOG_WIDTH)
      .padding({
        left: Dimens.DIALOG_PADDING,
        right: Dimens.DIALOG_PADDING,
        top: Dimens.DIALOG_PADDING
      })
      .backgroundColor(AppColors.ALERT_DIALOG_SURFACE.resolve(this.dark))
      .borderRadius(Dimens.DIALOG_CORNER_RADIUS)
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * The shortcut artwork's base name.
 *
 * NOT `iconBaseName` with the prefix swapped: the shortcut set drops the `weather_` prefix and its
 * names are `shortcuts_clear_day`, `shortcuts_partly_cloudy_night`, … so this returns just the
 * stem. Kept beside the dialog that needs it rather than in WeatherIcons, which has no other
 * caller for the foreground layer.
 */
export function shortcutBaseName(kind: WeatherKind, daytime: boolean): string {
  const base: string = iconBaseName(kind, daytime);
  return base.startsWith('weather_') ? base.substring('weather_'.length) : base;
}

/** How many masks there are, for the caller's roll. */
export const ADAPTIVE_MASK_COUNT: number = 5;
