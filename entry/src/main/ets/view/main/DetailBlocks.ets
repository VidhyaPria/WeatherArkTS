/*
 * The half-size detail blocks below the hourly card.
 *
 * Order comes from DEFAULT_CARD_DISPLAY (SettingsManager.kt:61-73):
 *   nowcast, daily_forecast, hourly_forecast, precipitation, wind, air_quality, pollen,
 *   humidity, uv, visibility, pressure, sun, moon
 * ViewType.isHalfSizeableBlock (ViewType.kt:39-45) marks precipitation..moon as half-width,
 * so they lay out two per row on a phone while the header and trend cards span the full width.
 *
 * Each block is gated on its value being present, exactly as MainAdapter.kt:122-170 does —
 * a card whose value is null is not added to the list at all.
 *
 * Icon and title per block come from the container_main_*.xml layouts; the tap target of each
 * whole card opens a detail screen (the *ViewHolder.kt line is cited per entry).
 */

import { Astro, Daily, HalfDay, LocationModel, PollenEntry, Weather } from '../../model/Weather';
import { localHours } from '../../common/LocalTime';
import { DetailScreen } from '../../model/DetailScreen';
import { WeatherKind } from '../../model/WeatherKind';
import { aqiLevelColor, AppColors, getThemeColors, withAlpha } from '../../theme/AppColors';
import { aqiLevelName } from '../../model/Pollutant';
import {
  distanceUnitLabel,
  formatDistance,
  formatPrecipitation,
  formatPressure,
  formatSpeed,
  formatTemperatureNarrow,
  precipitationUnitLabel,
  pressureUnitLabel,
  speedUnitLabel
} from '../../common/Units';

/** HumidityViewHolder.kt:56-69 — the wave fill is chosen by humidity bucket. */
function humidityWaves(percent: number): Resource {
  if (percent <= 20) {
    return $r('app.media.humidity_percent_7');
  }
  if (percent <= 40) {
    return $r('app.media.humidity_percent_30');
  }
  if (percent <= 60) {
    return $r('app.media.humidity_percent_50');
  }
  if (percent <= 80) {
    return $r('app.media.humidity_percent_75');
  }
  return $r('app.media.humidity_percent_90');
}

export class DetailBlock {
  readonly id: string;
  readonly icon: Resource;
  readonly title: string;
  /** Big 45sp number (Weather.TextAppearance.MainBlock.NumberDigit, styles.xml:310-314). */
  readonly value: string;
  /** Unit, rendered smaller beside the number — "0 in", "5 mph", "22.2 mi". */
  readonly unit: string;
  /** Secondary line under the value, or empty. */
  readonly secondaryLabel: string;
  readonly secondaryValue: string;
  readonly detailScreen: DetailScreen;

  /* Shape and ornaments, assigned after construction. */
  /**
   * Circle vs rounded rectangle is a property of the card type, not of its position in the
   * grid. Each layout declares it: app:shapeAppearance="…Corner.Full" on wind, air_quality,
   * visibility and pressure; "…Corner.ExtraLarge" on precipitation, pollen, humidity and astro.
   */
  isCircle: boolean = false;
  /**
   * container_main_uv.xml has no MaterialCardView at all — its root is a bare ConstraintLayout,
   * so the UV block draws only its sun graphic with no card behind it.
   */
  hasCard: boolean = true;
  /** Rotation applied to the shape, used for the wind arrow. */
  shapeRotation: number = 0;
  /**
   * Guideline percentages, read straight off each container_main_*.xml. There is no shared
   * value — the layouts differ per block:
   *   air_quality, pressure, visibility, wind   0.2 / 0.8
   *   uv                                       0.2 / 0.77 vertical, 0.2 / 0.8 horizontal
   *   astro, pollen                            0.1 / 0.9
   *   humidity, precipitation                  0.08 / 0.92
   */
  insetTopPercent: number = 0.08;
  insetBottomPercent: number = 0.08;
  insetHorizontalPercent: number = 0.08;
  /**
   * container_main_pressure.xml:99-126 is the only block that puts its unit on its own line,
   * centred and bottom-aligned to the lower guideline, at textAppearanceLabelLarge rather than
   * beside the number. Rendering "1016 hPa" on one line is what made the circle look cramped.
   */
  unitOnOwnLine: boolean = false;

  /** Applies one guideline percentage to all four edges. */
  setInsets(percent: number): void {
    this.insetTopPercent = percent;
    this.insetBottomPercent = percent;
    this.insetHorizontalPercent = percent;
  }
  /** Cover crops to fill; the wind arrow and UV sun need to stay whole. */
  shapeFitsInside: boolean = false;
  /** Allergen rows — when present the block lists these instead of a big number. */
  pollenRows: PollenEntry[] = [];
  /** Astro block: rise and set times shown beneath an arc, plus an optional phase label. */
  astro: Astro | null = null;
  /** Sun blocks theme their arc as clear-day, moon blocks as clear-night (AstroViewHolder.kt:84-90). */
  astroIsSun: boolean = true;
  /** themeColors[0] — the solid elapsed arc (AstroViewHolder.kt:126-131). */
  astroLineColor: string = '';
  /** themeColors[1] at 66% (light) or themeColors[2] at 50% (dark) — the dashed track. */
  astroTrackColor: string = '';
  /** The drawable that rides the head of the arc (AstroViewHolder.kt:122-124). */
  astroIcon: Resource | null = null;
  /** Elapsed fraction of the arc, or -1 when there is no valid rise/set pair. */
  astroProgress: number = -1;
  /** Vector fill behind the content — the humidity waves, visibility blob, wind blob. */
  shape: Resource | null = null;
  shapeTint: string = '';
  /**
   * Draw `secondaryValue` inside a filled circle instead of as plain text — the humidity block's
   * dew-point badge (container_main_humidity.xml `dew_point_circle`, an oval of ?attr/colorTertiary
   * with the value centred on it). No other block has one.
   */
  secondaryIsChip: boolean = false;
  /**
   * The Clock block (container_main_clock.xml), which shares nothing with the other tiles: no
   * title row, no value line, no unit — a scalloped shape with the hour over the minute and a pair
   * of analog hands on top. `HalfBlockCard` branches on this rather than trying to express it
   * through the value/secondary fields.
   */
  isClock: boolean = false;
  /**
   * The clock shows the LOCATION's time, not the phone's — ClockViewHolder.kt:61-62 sets
   * `timeZone = location.timeZone.id` on both TextClocks. Carried on the block because that is
   * the only thing `HalfBlockCard` is given.
   */
  clockUtcOffsetSeconds: number = 0;
  /** Ring gauge (ArcProgress). Negative means the block has no gauge. */
  arcProgress: number = -1;
  arcMax: number = 100;
  arcColor: string = '';
  arcBackground: string = '';

  constructor(
    id: string,
    icon: Resource,
    title: string,
    value: string,
    unit: string,
    detailScreen: DetailScreen,
    secondaryLabel: string = '',
    secondaryValue: string = ''
  ) {
    this.id = id;
    this.icon = icon;
    this.title = title;
    this.value = value;
    this.unit = unit;
    this.detailScreen = detailScreen;
    this.secondaryLabel = secondaryLabel;
    this.secondaryValue = secondaryValue;
  }
}

/**
 * UvViewHolder.kt:54-59 -> UV.getShape() (domain UV.kt:81-91). Bands are the WHO scale:
 * UV_INDEX_LOW 3, MIDDLE 6, HIGH 8, EXCESSIVE 11 (domain/UV.kt:33-36).
 */
function uvShape(index: number, darkMode: boolean): Resource {
  if (index < 3) {
    return darkMode ? $r('app.media.uv_low_dark') : $r('app.media.uv_low');
  }
  if (index < 6) {
    return darkMode ? $r('app.media.uv_moderate_dark') : $r('app.media.uv_moderate');
  }
  if (index < 8) {
    return darkMode ? $r('app.media.uv_high_dark') : $r('app.media.uv_high');
  }
  if (index < 11) {
    return darkMode ? $r('app.media.uv_very_high_dark') : $r('app.media.uv_very_high');
  }
  return darkMode ? $r('app.media.uv_extreme_dark') : $r('app.media.uv_extreme');
}

/** UV.getLevel() (UV.kt:29-39) — strings.xml:145-149, same bands as the shape. */
function uvLevelName(index: number): string {
  if (index < 3) {
    return 'Low';
  }
  if (index < 6) {
    return 'Moderate';
  }
  if (index < 8) {
    return 'High';
  }
  if (index < 11) {
    return 'Very high';
  }
  return 'Extreme';
}

/*
 * The AQI level name now comes from AirQualityMapper.aqiLevelName, a direct port of
 * PollutantIndex.getAqiToName. The list previously here was wrong above level 1: the real
 * names are Excellent / Fair / Poor / Unhealthy / Very unhealthy / Dangerous
 * (strings.xml:167-182), not "Moderate / Poor / Very poor / Severe".
 */

/**
 * AstroViewHolder.kt:125-139 — a light theme takes themeColors[0] for the arc and themeColors[1]
 * at 66% for the dashed track; a dark theme takes themeColors[2] for the arc and the same colour
 * at 50% for the track.
 */
function applyAstroColors(block: DetailBlock, isDark: boolean): void {
  const themeColors: string[] = getThemeColors(WeatherKind.CLEAR, block.astroIsSun);
  if (!isDark) {
    block.astroLineColor = themeColors[0];
    block.astroTrackColor = withAlpha(themeColors[1], 0.66);
  } else {
    block.astroLineColor = themeColors[2];
    block.astroTrackColor = withAlpha(themeColors[2], 0.5);
  }
}

/**
 * Distance.getVisibilityDescription (UnitExtensions.kt:112-121) against the Met Office bands at
 * kt:94-98 — 1 / 4 / 10 / 20 / 40 km. The port had a three-way guess ("Clear" / "Good" / "Hazy"),
 * so a perfectly clear 43 km reading printed "Clear" where the Android device printed
 * "Perfectly clear", and "Hazy" is not one of the six strings at all.
 */
function visibilityDescription(metres: number): string {
  if (metres < 1000) {
    return 'Very poor';
  }
  if (metres < 4000) {
    return 'Poor';
  }
  if (metres < 10000) {
    return 'Moderate';
  }
  if (metres < 20000) {
    return 'Good';
  }
  if (metres < 40000) {
    return 'Clear';
  }
  return 'Perfectly clear';
}

/**
 * The half-day the precipitation tile's total covers — PrecipitationViewHolder.kt:44-52.
 *
 * Before 05:00 it is YESTERDAY's night, before 17:00 today's day, otherwise tonight. The same
 * window `currentHalfDayPrecipitation` picks the total from; this returns the half-day itself
 * because the tile's LABEL depends on its rain and snow as well as on its total.
 */
function currentHalfDay(weather: Weather, utcOffsetSeconds: number): HalfDay | null {
  const todayIndex: number | null = weather.todayIndex;
  if (todayIndex === null) {
    return null;
  }
  const today: Daily | undefined = weather.dailyForecast[todayIndex];
  if (today === undefined) {
    return null;
  }
  const hour: number = localHours(new Date(), utcOffsetSeconds);
  if (hour < 5) {
    const yesterday: Daily | undefined = weather.dailyForecast[todayIndex - 1];
    return yesterday === undefined ? null : yesterday.night;
  }
  return hour < 17 ? today.day : today.night;
}

/**
 * The tile's second line — PrecipitationViewHolder.kt:54-84.
 *
 * SIX strings, not one: "Daytime"/"Nighttime" by the half-day, and "precipitation"/"rain"/"snow"
 * by what the half-day is made of. It narrows to "rain" or "snow" only when that part is the WHOLE
 * total; a mixed half-day, or one with both, stays on the general wording.
 *
 * Both ports hard-coded "Daytime precipitation" until now — symmetric, so it never showed up as an
 * asymmetry, but wrong against Android for every evening and every snowy day. It could not be
 * ported before this session because `HalfDay` carried no rain or snow to test.
 */
function precipitationTileLabel(half: HalfDay | null, isDay: boolean): string {
  const rain: number = half === null || half.precipitationRain === null ? 0 : half.precipitationRain;
  const snow: number = half === null || half.precipitationSnow === null ? 0 : half.precipitationSnow;
  const total: number =
    half === null || half.precipitationTotal === null ? 0 : half.precipitationTotal;
  /*
   * The Kotlin compares Precipitation values, which are whole micrometres and so exactly equal when
   * one part is the entire total. These are accumulated doubles in millimetres, so the same test
   * needs a tolerance well under a micrometre.
   */
  const isWholeTotal = (part: number): boolean => Math.abs(part - total) < 1e-6;
  if (rain > 0 && snow > 0) {
    return isDay ? 'Daytime precipitation' : 'Nighttime precipitation';
  }
  if (snow > 0 && isWholeTotal(snow)) {
    return isDay ? 'Daytime snow' : 'Nighttime snow';
  }
  if (rain > 0 && snow <= 0 && isWholeTotal(rain)) {
    return isDay ? 'Daytime rain' : 'Nighttime rain';
  }
  return isDay ? 'Daytime precipitation' : 'Nighttime precipitation';
}

export function buildDetailBlocks(location: LocationModel, isDark: boolean): DetailBlock[] {
  const blocks: DetailBlock[] = [];
  const weather = location.weather;
  if (weather === null || weather.current === null) {
    return blocks;
  }
  const c = weather.current;

  // PrecipitationViewHolder.kt:111-117 -> TAG_PRECIPITATION
  if (c.precipitationTotal !== null) {
    // kt:51 — `isDay` is the 05:00-16:59 window, the same one that picks the half-day.
    const localHour: number = localHours(new Date(), location.utcOffsetSeconds);
    blocks.push(new DetailBlock(
      'precipitation',
      $r('app.media.ic_precipitation'),
      'Precipitation', // strings.xml:76
      formatPrecipitation(c.precipitationTotal),
      precipitationUnitLabel(),
      DetailScreen.TAG_PRECIPITATION,
      // PrecipitationViewHolder shows which half-day the total covers, and what it is made of.
      precipitationTileLabel(currentHalfDay(weather, location.utcOffsetSeconds),
        localHour >= 5 && localHour < 17)
    ));
  }

  // WindViewHolder.kt:98-104 -> TAG_WIND
  if (c.windSpeed !== null) {
    const wind = new DetailBlock(
      'wind',
      $r('app.media.ic_wind'),
      'Wind', // strings.xml:102
      formatSpeed(c.windSpeed),
      speedUnitLabel(),
      DetailScreen.TAG_WIND,
      c.windGusts === null ? '' : 'Gusts: ' + formatSpeed(c.windGusts) + ' ' + speedUnitLabel()
    );
    // wind_arrow.xml fills with @color/sys_widget_background (colors.xml:136) and is turned
    // to point along the wind direction (WindViewHolder.kt:68-75).
    // container_main_wind.xml — 0.2 / 0.8 guidelines.
    wind.setInsets(0.2);
    wind.isCircle = true;
    wind.shape = $r('app.media.wind_arrow');
    wind.shapeTint = AppColors.SYS_WIDGET_BACKGROUND.resolve(isDark);
    wind.shapeFitsInside = true;
    wind.shapeRotation = c.windDegree === null ? 0 : c.windDegree;
    blocks.push(wind);
  }

  // AirQualityViewHolder.kt:101-107 -> TAG_AIR_QUALITY
  if (c.airQualityIndex !== null) {
    const aq = new DetailBlock(
      'air_quality',
      $r('app.media.ic_air_quality'),
      'Air quality', // strings.xml:14 air_quality_short
      Math.round(c.airQualityIndex).toString(),
      '',
      DetailScreen.TAG_AIR_QUALITY,
      aqiLevelName(c.airQualityIndex)
    );
    // AirQualityViewHolder.kt:81-91 — level colour, background the same at 10% alpha,
    // max = PollutantIndex.aqiThresholds.last() = 250.
    const aqiColor: string = aqiLevelColor(c.airQualityIndex);
    // container_main_air_quality.xml — 0.2 / 0.8 guidelines.
    aq.setInsets(0.2);
    aq.isCircle = true;
    aq.arcProgress = c.airQualityIndex;
    aq.arcMax = 250;
    aq.arcColor = aqiColor;
    aq.arcBackground = withAlpha(aqiColor, 0.1);
    blocks.push(aq);
  }

  /*
   * PollenViewHolder.kt:129-135 -> TAG_POLLEN, its OWN detail screen.
   *
   * This used to route to TAG_AIR_QUALITY behind a comment saying "there is no TAG_POLLEN in the
   * ported enum yet". That stopped being true when the pollen detail screen landed —
   * `DetailScreen.ets:20` declares the tag and `DetailsData.ets:1400,1729` build the screen for
   * it — but the workaround stayed, so tapping the Pollen tile opened Air quality. NativeApp maps
   * the same block to `DetailTag::Pollen` (Renderer.cpp:616-618) and always did, which is why the
   * two ports disagreed and only this one was wrong.
   */
  /*
   * `pollensWithConcentration` (Pollen.kt:32-38) — the MAIN screen's block lists only the allergens
   * reading above zero. The mapper now keeps every allergen the source REPORTS, because the detail
   * screen's PollenGrid lists `validPollens` instead, so the "> 0" rule lives here with the
   * consumer that actually has it.
   */
  const pollenWithConcentration: PollenEntry[] = [];
  for (const entry of c.pollen) {
    if (entry.concentration > 0) {
      pollenWithConcentration.push(entry);
    }
  }
  if (pollenWithConcentration.length > 0) {
    const pollen = new DetailBlock(
      'pollen',
      $r('app.media.ic_allergy'),
      'Pollen', // strings.xml:16
      '',
      '',
      DetailScreen.TAG_POLLEN
    );
    // container_main_pollen.xml — 0.1 / 0.9 guidelines.
    pollen.setInsets(0.1);
    pollen.pollenRows = pollenWithConcentration;
    blocks.push(pollen);
  }

  // HumidityViewHolder.kt:89-95 -> TAG_HUMIDITY
  if (c.relativeHumidity !== null) {
    const humidity = new DetailBlock(
      'humidity',
      $r('app.media.ic_humidity_percentage'),
      'Humidity', // strings.xml:334
      Math.round(c.relativeHumidity).toString(),
      '%',
      DetailScreen.TAG_HUMIDITY,
      'Dew point', // strings.xml:342
      c.dewPoint === null ? '' : formatTemperatureNarrow(c.dewPoint)
    );
    humidity.shape = humidityWaves(c.relativeHumidity);
    humidity.shapeTint = AppColors.TERTIARY_CONTAINER.resolve(isDark);
    humidity.secondaryIsChip = true;
    blocks.push(humidity);
  }

  // UvViewHolder.kt:71-77 -> TAG_UV_INDEX
  if (c.uvIndex !== null) {
    const uv = new DetailBlock(
      'uv',
      $r('app.media.ic_uv'),
      'UV index', // strings.xml:144 uv_index_short
      Math.round(c.uvIndex).toString(),
      '',
      DetailScreen.TAG_UV_INDEX,
      // container_main_uv.xml:97-106 — the level sits under the number (UvViewHolder.kt:63).
      uvLevelName(c.uvIndex)
    );
    // No MaterialCardView in container_main_uv.xml — the sun graphic is the whole block, and
    // the index sits centred on top of it rather than left-aligned against a card edge.
    uv.hasCard = false;
    uv.isCircle = true;
    uv.shape = uvShape(c.uvIndex, isDark);
    uv.shapeFitsInside = true;
    // container_main_uv.xml:16-42 — its own guidelines, tighter at the bottom than every other
    // block, which is what keeps "Moderate" clear of the sun graphic's beads.
    uv.insetTopPercent = 0.2;
    uv.insetBottomPercent = 1 - 0.77;
    uv.insetHorizontalPercent = 0.2;
    blocks.push(uv);
  }

  // VisibilityViewHolder.kt:63-69 -> TAG_VISIBILITY
  if (c.visibility !== null) {
    const visibility = new DetailBlock(
      'visibility',
      $r('app.media.ic_eye'),
      'Visibility', // strings.xml:361
      formatDistance(c.visibility),
      distanceUnitLabel(),
      DetailScreen.TAG_VISIBILITY,
      visibilityDescription(c.visibility)
    );
    // visibility_shape.xml — three paths, all ?attr/colorTertiaryContainer.
    // container_main_visibility.xml — 0.2 / 0.8 guidelines.
    visibility.setInsets(0.2);
    visibility.isCircle = true;
    visibility.shape = $r('app.media.visibility_shape');
    visibility.shapeTint = AppColors.TERTIARY_CONTAINER.resolve(isDark);
    blocks.push(visibility);
  }

  // PressureViewHolder.kt:76-82 -> TAG_PRESSURE
  if (c.pressure !== null) {
    const pressure = new DetailBlock(
      'pressure',
      $r('app.media.ic_gauge'),
      'Pressure', // strings.xml:350
      formatPressure(c.pressure),
      pressureUnitLabel(),
      DetailScreen.TAG_PRESSURE
    );
    // PressureViewHolder.kt:59-68 — progress is hPa above 963 on a 100-wide scale,
    // coloured with colorPrimary and backed by the same colour at 10% alpha.
    const primary: string = AppColors.PRIMARY.resolve(isDark);
    // container_main_pressure.xml — 0.2 / 0.8 guidelines, and the unit sits on its own line.
    pressure.setInsets(0.2);
    pressure.unitOnOwnLine = true;
    pressure.isCircle = true;
    pressure.arcProgress = c.pressure - 963;
    pressure.arcMax = 100;
    pressure.arcColor = primary;
    pressure.arcBackground = withAlpha(primary, 0.1);
    blocks.push(pressure);
  }

  // AstroViewHolder.kt:150-156 -> TAG_SUN_MOON. Both are rectangular cards
  // (container_main_astro.xml uses Corner.ExtraLarge) showing rise and set times.
  //
  // AstroViewHolder.kt:84-90 themes both arcs off WEATHER_KIND_CLEAR, passing `isSun` as the
  // daylight flag — so the sun arc is clear-day amber and the moon arc clear-night blue,
  // whatever the actual current weather is.
  const now = new Date();
  if (c.sun !== null) {
    const sunBlock = new DetailBlock(
      'sun',
      // AstroViewHolder.kt:93-98 — weather_clear_day_mini_xml, not the UV lightbulb.
      $r('app.media.ic_sunny'),
      'Sun', // strings.xml ephemeris_sun
      '',
      '',
      /*
       * TAG_SUN_MOON, which is what the comment above always said and what the NDK's
       * `DetailTagForBlock` always did. Both astro tiles were still wired to TAG_CONDITIONS —
       * a leftover from before the tag existed, so tapping the Sun card in ArkUIApp opened the
       * temperature screen where the same tap in the NDK opened Sun & moon.
       */
      DetailScreen.TAG_SUN_MOON
    );
    sunBlock.setInsets(0.1);
    sunBlock.astro = c.sun;
    sunBlock.astroIsSun = true;
    sunBlock.astroIcon = $r('app.media.weather_clear_day');
    sunBlock.astroProgress = c.sun.progressAt(now);
    applyAstroColors(sunBlock, isDark);
    blocks.push(sunBlock);
  }
  if (c.moon !== null) {
    const moonBlock = new DetailBlock(
      'moon',
      $r('app.media.ic_weather_night'),
      'Moon', // strings.xml ephemeris_moon
      '',
      '',
      DetailScreen.TAG_SUN_MOON
    );
    moonBlock.setInsets(0.1);
    moonBlock.astro = c.moon;
    moonBlock.astroIsSun = false;
    moonBlock.astroIcon = $r('app.media.weather_clear_night');
    moonBlock.astroProgress = c.moon.progressAt(now);
    applyAstroColors(moonBlock, isDark);
    blocks.push(moonBlock);
  }

  /*
   * ClockViewHolder.kt:36-77 -> TAG_CONDITIONS on today (kt:69-76).
   *
   * Unconditional: it is a clock, so unlike every block above it there is no reading that can be
   * absent. It is only ever hidden by being left out of `card_display`, which is where it starts —
   * CardDisplay's default list does not include it, so this appears only once the user adds it on
   * the Blocks screen, exactly as on Android.
   *
   * The card is `hasCard = false`: container_main_clock.xml has no MaterialCardView at all, only a
   * ConstraintLayout whose 1:1 child holds the scalloped `clock_shape` drawable. The shape IS the
   * surface, which is why it sits straight on the weather background like the UV block does.
   *
   * Insets are the layout's own guidelines: 0.1/0.9 vertically for the text pair, and NONE
   * horizontally — the LinearLayout is `match_parent` wide, so it ignores the 0.2/0.8 vertical
   * guidelines it is constrained to (a match_parent child overrides its side constraints).
   */
  const clockBlock = new DetailBlock(
    'clock',
    // Never drawn — the clock has no title row. DetailBlock requires an icon, so this is the
    // nearest existing asset rather than a new one added only to be ignored.
    $r('app.media.ic_time'),
    'Clock', // strings.xml `clock`
    '',
    '',
    DetailScreen.TAG_CONDITIONS
  );
  clockBlock.isClock = true;
  clockBlock.clockUtcOffsetSeconds = location.utcOffsetSeconds;
  clockBlock.hasCard = false;
  clockBlock.insetTopPercent = 0.1;
  clockBlock.insetBottomPercent = 0.1;
  clockBlock.insetHorizontalPercent = 0;
  clockBlock.shape = $r('app.media.clock_shape');
  clockBlock.shapeTint = AppColors.SURFACE.resolve(isDark);
  /*
   * False, meaning "fill the square" — which is what the shape has to do here, because it IS the
   * card's surface. The flag does NOT mean the same thing in the two ports: here it selects
   * ImageFit.Contain vs Cover, which are identical for a square asset in a square box, whereas the
   * NDK's `true` insets the asset by 18 % so the wind arrow and UV sun stay whole. Both ports set
   * it false for the clock so both draw the shape at the full side.
   */
  clockBlock.shapeFitsInside = false;
  blocks.push(clockBlock);

  return blocks;
}
