/*
 * Port of container_main_header.xml + HeaderViewHolder.kt.
 *
 * Structure and spacing, top to bottom (container_main_header.xml):
 *   root       vertical, gravity bottom, 8dp start/end padding, 16dp bottom padding (:11-13)
 *   row        refresh-time text (14sp, 6dp drawable padding, 8dp bottom margin) (:21-37)
 *   condition  textAppearanceTitleLarge, bold, 8dp top margin, centred (:58-70)
 *   temperature 140sp value with a 50sp unit beside it; value has -10dp top margin (:77-106)
 *   feels like  titleLarge, -10dp top margin, 8dp bottom margin, centred (:109-123)
 *   range       titleMedium, centred (:125-137)
 *
 * Every text uses ?attr/colorSurfaceInverse, which resolves to md_theme_inverseSurface
 * (styles.xml:29).
 *
 * There is no click listener on this card — only a ripple foreground (:9).
 */

import { Dimens } from '../../theme/Dimens';
import { LocationModel } from '../../model/Weather';
import { formatRelativeTime } from '../../common/Formatter';
import { temperatureUnitLabel, temperatureValue as toDisplayTemperature } from '../../common/Units';
import { getTemperatureRangeSummary } from '../../viewmodel/MainViewModel';
import { NumberAnimText } from './NumberAnimText';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** textAppearanceTitleLarge is 22sp in Material 3. */
const TITLE_LARGE_TEXT_SIZE: number = 22;
/** textAppearanceTitleMedium is 16sp in Material 3. */
const TITLE_MEDIUM_TEXT_SIZE: number = 16;
/** container_main_header.xml:97 — the unit next to the big number. */
const TEMPERATURE_UNIT_TEXT_SIZE: number = 50;

@ComponentV2
export struct HeaderCard {
  @Param location: LocationModel = new LocationModel();
  /** Previous location's temperature, so the count-up starts where the last one ended. */
  @Param previousTemperature: number = 0;
  @Param textColor: string = '#FF191C1E';
  @Param animationEnabled: boolean = true;
  /**
   * Bumped whenever a unit preference changes, and read in the unit LABEL's own expression below.
   *
   * ArkUI V2 gives every attribute expression its own update closure with its own dependency set,
   * and re-renders only the closures whose dependencies changed — a parent re-rendering does not
   * re-evaluate a child expression that depends on nothing. `Text(temperatureUnitLabel())` depends
   * on nothing observable: the unit is read inside a helper in `common/Units.ets`. So switching to
   * Fahrenheit converted the NUMBER (its `toValue` is a @Param, which is tracked) and left "°C"
   * sitting beside it — 19 °C became 65 °C rather than 65 °F.
   *
   * Passing the version in as a @Param and naming it in that expression gives the closure something
   * to depend on. This is the same shape as the pager fix in MainScreen: the read IS the
   * subscription, and it has to happen where the framework is looking.
   */
  @Param unitsVersion: number = 0;

  private conditionText(): string {
    const weather = this.location.weather;
    if (weather === null || weather.current === null || weather.current.weatherText === null) {
      return '';
    }
    return weather.current.weatherText;
  }

  private hasTemperature(): boolean {
    const weather = this.location.weather;
    if (weather === null || weather.current === null || weather.current.temperature === null) {
      return false;
    }
    return weather.current.temperature.temperature !== null;
  }

  /**
   * Rounded current temperature in the *display* unit, or 0 when absent — guarded by
   * hasTemperature().
   *
   * The model stores Celsius and the unit beside this number comes from temperatureUnitLabel(),
   * so the value has to be converted here too; without it an imperial build rendered the Celsius
   * number with a °F label ("22 °F" under a "Day: 75° • Night: 72°" range).
   */
  private temperatureValue(): number {
    const weather = this.location.weather;
    if (weather === null || weather.current === null || weather.current.temperature === null) {
      return 0;
    }
    const value: number | null = weather.current.temperature.temperature;
    return value === null ? 0 : Math.round(toDisplayTemperature(value));
  }

  /**
   * HeaderViewHolder.kt:109-135 — the feels-like line is hidden when it rounds to the same
   * value as the actual temperature.
   */
  private feelsLikeText(): string {
    const weather = this.location.weather;
    if (weather === null || weather.current === null || weather.current.temperature === null) {
      return '';
    }
    const feelsLike: number | null = weather.current.temperature.feelsLikeTemperature;
    const actual: number | null = weather.current.temperature.temperature;
    if (feelsLike === null) {
      return '';
    }
    // The comparison happens in the display unit: two Celsius values a degree apart can round to
    // the same Fahrenheit value, and the Kotlin hides the line whenever the *shown* numbers match.
    const feelsLikeShown: number = Math.round(toDisplayTemperature(feelsLike));
    if (actual !== null && Math.round(toDisplayTemperature(actual)) === feelsLikeShown) {
      return '';
    }
    // strings.xml:56 — "Feels like %s"
    return 'Feels like ' + feelsLikeShown.toString() + '°';
  }

  /**
   * The degree unit beside the big number. `version` is unused as a value — passing it is what
   * puts a tracked read in the calling expression, see `unitsVersion`.
   */
  private unitLabel(version: number): string {
    return version < 0 ? '' : temperatureUnitLabel();
  }

  /** Weather.kt:94-160 — "Day: 30° • Night: 14°"; empty when there is nothing to show. */
  private rangeText(): string {
    const summary: string | null = getTemperatureRangeSummary(this.location);
    return summary === null ? '' : summary;
  }

  private refreshText(): string {
    const weather = this.location.weather;
    if (weather === null || weather.refreshTime === null) {
      return '';
    }
    return formatRelativeTime(weather.refreshTime, new Date());
  }

  build() {
    Column() {
      // Refresh time row.
      if (this.refreshText().length > 0) {
        Row() {
          Image($r('app.media.ic_time'))
            .width(Dimens.CONTENT_TEXT_SIZE)
            .height(Dimens.CONTENT_TEXT_SIZE)
            .fillColor(this.textColor)
          Text(this.refreshText())
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontColor(this.textColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: 6 })
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .margin({ bottom: Dimens.SMALL_MARGIN })
      }

      // Weather condition.
      if (this.conditionText().length > 0) {
        Text(this.conditionText())
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(TITLE_LARGE_TEXT_SIZE)
          .fontColor(this.textColor)
          .fontWeight(FontWeight.Bold)
          .margin({ top: Dimens.SMALL_MARGIN })
      }

      // Big temperature with its unit.
      if (this.hasTemperature()) {
        Row() {
          NumberAnimText({
            // Celsius from the model, like temperatureValue() — convert so the count-up starts
            // in the same unit it ends in.
            fromValue: Math.round(toDisplayTemperature(this.previousTemperature)),
            toValue: this.temperatureValue(),
            animationEnabled: this.animationEnabled,
            textSize: Dimens.MAIN_TITLE_TEXT_SIZE,
            textColor: this.textColor,
            animKey: this.location.formattedId + ':' + this.temperatureValue().toString()
          })
          // The argument is what subscribes this Text to a unit change — see `unitsVersion`.
          Text(this.unitLabel(this.unitsVersion))
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(TEMPERATURE_UNIT_TEXT_SIZE)
            .fontColor(this.textColor)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 5 })
        }
        .alignItems(VerticalAlign.Top)
        .margin({ top: -10 })
      }

      if (this.feelsLikeText().length > 0) {
        Text(this.feelsLikeText())
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(TITLE_LARGE_TEXT_SIZE)
          .fontColor(this.textColor)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .margin({ top: -10, bottom: 8 })
      }

      if (this.rangeText().length > 0) {
        Text(this.rangeText())
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(TITLE_MEDIUM_TEXT_SIZE)
          .fontColor(this.textColor)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: Dimens.SMALL_MARGIN,
      right: Dimens.SMALL_MARGIN,
      bottom: Dimens.NORMAL_MARGIN
    })
  }
}
