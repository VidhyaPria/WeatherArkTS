/*
 * The per-location weather-sources dialog — SecondarySourcesPreference (LocationPreferences.kt:351-916).
 *
 * Reached from THREE places on Android, and all three are wired to this one component:
 *   swipe a row left        LocationItemTouchCallback.kt:96
 *   the my-location FAB     ManagementFragment.kt:240-244
 *   picking a search result SearchActivity.kt:212-223
 *
 * Eight rows, one per SourceFeature, each a title + the selected source's name that opens a grouped
 * radio picker. The catalogue behind them is `data/SourceCatalogue.ets`, which is the whole of
 * SourceManager's metadata — CLAUDE.md scopes down the source CLIENTS, not the source list.
 *
 * What is deliberately NOT here, and why:
 *   the freenet disclaimer card   inside `if (BuildConfig.FLAVOR == "freenet")` (kt:454-494); the
 *                                 reference build is the `basic` flavour
 *   the "Learn more" link dialog  only reachable from that card (kt:910-915)
 *   `cityId` / `needsGeocodeRefresh` reset on Save (kt:850, 859-860) — the port's LocationModel
 *                                 carries neither field, because nothing in it reverse-geocodes by
 *                                 city id
 *
 * Built as a Stack overlay rather than a CustomDialog, which is the pattern LocationSearch's own
 * source chooser already established here: the scrim and dismiss-on-tap-outside are what a dialog
 * contributes behaviourally, and both are present.
 */

import { Dimens } from '../../theme/Dimens';
import { AppColors, searchSurface } from '../../theme/AppColors';
import { APP_FONT_FAMILY } from '../../common/Typography';
import { LocationModel } from '../../model/Weather';
import { goPlaceholder } from '../../common/Navigator';
import {
  getCompatibleSources,
  getSource,
  GROUP_RECOMMENDED,
  SourceFeature,
  sourceFeatureName,
  SourceGroup,
  SourceInfo
} from '../../data/SourceCatalogue';

/** `MaterialTheme.typography.headlineSmall` — the dialog titles (kt:442-448). */
const HEADLINE_SMALL: number = 24;
/** `titleSmall`, the centred group headings inside the picker (ListPreference.kt:274). */
const TITLE_SMALL: number = 14;
/** ListPreference.kt's RadioButton row — a 40 dp target around the 24 dp control. */
const RADIO_ROW_HEIGHT: number = 56;
/**
 * Material3's ListItem is a fixed 72 dp for a two-line item, whatever the text measures. With
 * PreferenceView's own 8 dp above and below (Preference.kt:149) a source row is 88 dp.
 */
const LIST_ITEM_TWO_LINE: number = 72;
/** `.alpha(if (enabled) 1f else 0.5f)` — Preference.kt:159 and ListPreference.kt:398. */
const DISABLED_ALPHA: number = 0.5;
/** AlertDialogNoPadding's scrim. */
const SCRIM: string = '#52000000';

/**
 * The rows, in the Kotlin's order (kt:514-840). Reverse geocoding is appended conditionally, which
 * is why it is not in this array.
 */
const FEATURE_ROWS: SourceFeature[] = [
  SourceFeature.FORECAST,
  SourceFeature.CURRENT,
  SourceFeature.AIR_QUALITY,
  SourceFeature.POLLEN,
  SourceFeature.MINUTELY,
  SourceFeature.ALERT,
  SourceFeature.NORMALS
];

/**
 * Everything this dialog needs about a location, and nothing else.
 *
 * Deliberately NOT a LocationModel. A LocationModel reaches its `weather` — some four hundred
 * hourly entries plus daily, minutely and alert objects — and handing one to a `@Param` makes
 * ArkUI V2 register observation bindings across that whole graph. The binding registry is a
 * dictionary that `clearBinding` enumerates with `Object.keys` on every page teardown, so a few
 * trips through this screen grew it until a page push blocked the main thread past six seconds and
 * the system killed the app with THREAD_BLOCK_6S. See LocationRowModel for the same fix.
 *
 * All fields are scalars. `probe()` rebuilds a throwaway LocationModel for the catalogue, which
 * takes one only because its predicates read coordinates and country — never the weather.
 */
export class LocationSources {
  formattedId: string = '';
  latitude: number = 0;
  longitude: number = 0;
  /** Location.admin1 — read by the regional Atmo predicates. */
  region: string = '';
  admin2: string = '';
  countryCode: string = '';
  isCurrentPosition: boolean = false;

  forecastSource: string = '';
  currentSource: string = '';
  airQualitySource: string = '';
  pollenSource: string = '';
  minutelySource: string = '';
  alertSource: string = '';
  normalsSource: string = '';
  reverseGeocodingSource: string = '';
  /**
   * Whether the dialog actually changed anything (kt:847). The host uses it to decide between
   * kt:880's "the location goes back untouched" and the rewrite that also clears the refresh time.
   */
  changed: boolean = false;

  static from(location: LocationModel): LocationSources {
    const sources = new LocationSources();
    sources.formattedId = location.formattedId;
    sources.latitude = location.latitude;
    sources.longitude = location.longitude;
    sources.region = location.region;
    sources.admin2 = location.admin2;
    sources.countryCode = location.countryCode;
    sources.isCurrentPosition = location.isCurrentPosition;
    sources.forecastSource = location.forecastSource;
    sources.currentSource = location.currentSource;
    sources.airQualitySource = location.airQualitySource;
    sources.pollenSource = location.pollenSource;
    sources.minutelySource = location.minutelySource;
    sources.alertSource = location.alertSource;
    sources.normalsSource = location.normalsSource;
    sources.reverseGeocodingSource = location.reverseGeocodingSource;
    return sources;
  }

  /** Copies the eight selections onto the real location a Save applies to. */
  applyTo(location: LocationModel): void {
    location.forecastSource = this.forecastSource;
    location.currentSource = this.currentSource;
    location.airQualitySource = this.airQualitySource;
    location.pollenSource = this.pollenSource;
    location.minutelySource = this.minutelySource;
    location.alertSource = this.alertSource;
    location.normalsSource = this.normalsSource;
    location.reverseGeocodingSource = this.reverseGeocodingSource;
  }
}

/** One line of the picker: a centred group heading, or a selectable source. */
class PickerEntry {
  readonly id: string;
  readonly label: string;
  readonly enabled: boolean;
  readonly isHeader: boolean;
  /** Whether this port can actually run it — an unimplemented pick routes to the placeholder. */
  readonly implemented: boolean;

  constructor(id: string, label: string, enabled: boolean, isHeader: boolean, implemented: boolean) {
    this.id = id;
    this.label = label;
    this.enabled = enabled;
    this.isHeader = isHeader;
    this.implemented = implemented;
  }

  static header(title: string): PickerEntry {
    return new PickerEntry('', title, false, true, false);
  }
}

@ComponentV2
export struct WeatherSourcesDialog {
  /** The location being configured, as scalars. Never mutated here; Save hands a copy back. */
  @Param target: LocationSources = new LocationSources();
  @Param dark: boolean = false;
  /**
   * `onClose(location)` (kt:439-441, 878-881, 898). A null means Cancel — nothing is saved and, at
   * the two entry points that were ADDING a location, nothing is added.
   */
  @Event onClose: (sources: LocationSources | null) => void = () => {
  };
  /**
   * `locationExists` (kt:480-482) — asked whether changing the forecast source would collide with a
   * location already saved. Takes the triple rather than a location, so no model crosses the
   * boundary. Supplied by the host page, which owns the view model.
   */
  @Event locationExists: (latitude: number, longitude: number, forecastSource: string) => boolean =
    () => false;

  /**
   * A throwaway LocationModel for the catalogue's predicates, which read coordinates, country and
   * admin names only. Built per call and never stored, so it never reaches state management.
   */
  private probe(): LocationModel {
    const location = new LocationModel();
    location.formattedId = this.target.formattedId;
    location.latitude = this.target.latitude;
    location.longitude = this.target.longitude;
    location.region = this.target.region;
    location.admin2 = this.target.admin2;
    location.countryCode = this.target.countryCode;
    location.isCurrentPosition = this.target.isCurrentPosition;
    return location;
  }

  /* --------------------------------------------------------------- the eight selections -------- */

  @Local private forecastSource: string = '';
  @Local private currentSource: string = '';
  @Local private airQualitySource: string = '';
  @Local private pollenSource: string = '';
  @Local private minutelySource: string = '';
  @Local private alertSource: string = '';
  @Local private normalsSource: string = '';
  @Local private reverseGeocodingSource: string = '';

  /** kt:362-363 — Save only rewrites the location when something actually changed. */
  @Local private hasChangedASource: boolean = false;
  @Local private hasChangedReverseGeocodingSource: boolean = false;
  /** kt:365 — set when the chosen forecast source would duplicate an existing location. */
  @Local private isLocationDuplicate: boolean = false;

  /** Which row's picker is open, or null. */
  @Local private openPicker: SourceFeature | null = null;

  aboutToAppear(): void {
    // `remember { mutableStateOf(location.xSource ?: "") }` (kt:364-372).
    this.forecastSource = this.target.forecastSource;
    this.currentSource = this.target.currentSource;
    this.airQualitySource = this.target.airQualitySource;
    this.pollenSource = this.target.pollenSource;
    this.minutelySource = this.target.minutelySource;
    this.alertSource = this.target.alertSource;
    this.normalsSource = this.target.normalsSource;
    this.reverseGeocodingSource = this.target.reverseGeocodingSource;
  }

  private selectedFor(feature: SourceFeature): string {
    switch (feature) {
      case SourceFeature.FORECAST:
        return this.forecastSource;
      case SourceFeature.CURRENT:
        return this.currentSource;
      case SourceFeature.AIR_QUALITY:
        return this.airQualitySource;
      case SourceFeature.POLLEN:
        return this.pollenSource;
      case SourceFeature.MINUTELY:
        return this.minutelySource;
      case SourceFeature.ALERT:
        return this.alertSource;
      case SourceFeature.NORMALS:
        return this.normalsSource;
      default:
        return this.reverseGeocodingSource;
    }
  }

  private setSelected(feature: SourceFeature, id: string): void {
    switch (feature) {
      case SourceFeature.FORECAST:
        this.forecastSource = id;
        break;
      case SourceFeature.CURRENT:
        this.currentSource = id;
        break;
      case SourceFeature.AIR_QUALITY:
        this.airQualitySource = id;
        break;
      case SourceFeature.POLLEN:
        this.pollenSource = id;
        break;
      case SourceFeature.MINUTELY:
        this.minutelySource = id;
        break;
      case SourceFeature.ALERT:
        this.alertSource = id;
        break;
      case SourceFeature.NORMALS:
        this.normalsSource = id;
        break;
      default:
        this.reverseGeocodingSource = id;
        break;
    }
  }

  /** kt:800 — the address-lookup row exists only for a current position. */
  private showsReverseGeocoding(): boolean {
    return this.target.isCurrentPosition;
  }

  /** Location.isUsable — a current position with no fix yet (kt:495). */
  private isUsable(): boolean {
    return this.target.latitude !== 0 || this.target.longitude !== 0;
  }

  /* ----------------------------------------------------------------- the picker contents ------- */

  /**
   * One row's entries, flattened: the ungrouped bucket first, then a heading per group.
   *
   * The ungrouped bucket is the Kotlin's `put(null, ...)` (kt:569-597 and the rows after it), and
   * ListPreferenceWithGroupsView emits no heading for a null key (ListPreference.kt:335-342). It
   * holds up to two pseudo-entries:
   *   the SELECTED source, when it is no longer compatible → "%s (unavailable)", disabled
   *   "None", or "Forecast" on the current-weather row, which means "take it from the forecast"
   * The forecast row itself gets neither None nor Forecast — a location must have a forecast source.
   */
  private entriesFor(feature: SourceFeature): PickerEntry[] {
    const selected: string = this.selectedFor(feature);
    const groups: SourceGroup[] = getCompatibleSources(feature, this.probe(), selected);
    const entries: PickerEntry[] = [];

    let compatible: boolean = false;
    for (let g = 0; g < groups.length; g++) {
      for (let s = 0; s < groups[g].sources.length; s++) {
        if (groups[g].sources[s].id === selected) {
          compatible = true;
        }
      }
    }
    if (selected.length > 0 && !compatible) {
      // strings.xml `settings_weather_source_unavailable` = "%s (unavailable)".
      entries.push(new PickerEntry(selected, selected + ' (unavailable)', false, false, false));
    }
    if (feature !== SourceFeature.FORECAST) {
      // kt:589-595 — the current-weather row says "Forecast" where the others say "None".
      const label: string = feature === SourceFeature.CURRENT ? 'Forecast' : 'None';
      entries.push(new PickerEntry('', label, true, false, true));
    }

    for (let g = 0; g < groups.length; g++) {
      const group: SourceGroup = groups[g];
      if (group.sources.length === 0) {
        continue;
      }
      entries.push(PickerEntry.header(group.title));
      for (let s = 0; s < group.sources.length; s++) {
        const source: SourceInfo = group.sources[s];
        // kt:341-344 — an unconfigured ConfigurableSource, or one that does not support this
        // location, is listed but not selectable.
        const enabled: boolean = source.configured && source.supports(this.probe(), feature);
        /*
         * `SourceExtensions.getName` renames it rather than only dimming it:
         * `settings_weather_source_not_configured` = "%s (not configured)". Confirmed on the
         * Android device, whose Forecast picker reads "Infoplaza (not configured)",
         * "PirateWeather (not configured)" and "Met Office (United Kingdom) (not configured)"
         * while AccuWeather, OpenWeather and Météo-France appear unsuffixed.
         */
        const label: string = source.configured ? source.name : source.name + ' (not configured)';
        entries.push(new PickerEntry(source.id, label, enabled, false, source.implemented));
      }
    }
    return entries;
  }

  /** The row's summary — the label of whichever entry is currently selected (kt:1001-1005). */
  private summaryFor(feature: SourceFeature): string {
    const selected: string = this.selectedFor(feature);
    if (selected.length === 0) {
      return feature === SourceFeature.CURRENT ? 'Forecast' : 'None';
    }
    const source: SourceInfo | null = getSource(selected);
    return source !== null ? source.name : selected + ' (unavailable)';
  }

  /* ------------------------------------------------------------------------- actions ----------- */

  private onPicked(feature: SourceFeature, entry: PickerEntry): void {
    if (!entry.enabled) {
      return;
    }
    this.openPicker = null;
    /*
     * CLAUDE.md's source scope: "Selecting a source other than Open-Meteo shows the same 'not yet
     * ported' placeholder used for unported screens — never hidden, never a crash." So an
     * unimplemented pick is answered with the placeholder and the selection is left alone, exactly
     * as the search screen's own chooser does. Clearing a feature ("None") is always allowed.
     */
    if (entry.id.length > 0 && !entry.implemented) {
      const source: SourceInfo | null = getSource(entry.id);
      goPlaceholder((source !== null ? source.name : entry.id) + ' ' +
        sourceFeatureName(feature).toLowerCase());
      return;
    }

    if (feature === SourceFeature.REVERSE_GEOCODING) {
      this.reverseGeocodingSource = entry.id;
      this.hasChangedReverseGeocodingSource = true;
      return;
    }

    if (feature === SourceFeature.FORECAST) {
      // kt:544-554 — only a CHANGE of forecast source can create a duplicate.
      this.isLocationDuplicate = entry.id !== this.target.forecastSource &&
        this.locationExists(this.target.latitude, this.target.longitude, entry.id);
    }
    this.setSelected(feature, entry.id);
    this.hasChangedASource = true;
  }

  /**
   * The eight current selections, as the value object Save hands back (kt:848-877).
   *
   * Only the sources travel. The host owns the LocationModel and applies them with
   * `LocationSources.applyTo`, which keeps the weather graph out of this component entirely.
   */
  private currentSelection(): LocationSources {
    const chosen = new LocationSources();
    chosen.formattedId = this.target.formattedId;
    chosen.latitude = this.target.latitude;
    chosen.longitude = this.target.longitude;
    chosen.region = this.target.region;
    chosen.admin2 = this.target.admin2;
    chosen.countryCode = this.target.countryCode;
    chosen.isCurrentPosition = this.target.isCurrentPosition;
    chosen.forecastSource = this.forecastSource;
    chosen.currentSource = this.currentSource;
    chosen.airQualitySource = this.airQualitySource;
    chosen.pollenSource = this.pollenSource;
    chosen.minutelySource = this.minutelySource;
    chosen.alertSource = this.alertSource;
    chosen.normalsSource = this.normalsSource;
    chosen.reverseGeocodingSource = this.reverseGeocodingSource;
    chosen.changed = this.hasChangedASource || this.hasChangedReverseGeocodingSource;
    return chosen;
  }

  /** kt:843-882. */
  private onSave(): void {
    if (this.isLocationDuplicate) {
      return;
    }
    /*
     * Either way the selection goes back — unchanged is kt:880's "the location goes back
     * untouched", and the host can tell the two apart because applying an identical selection is a
     * no-op. Clearing `weather.refreshTime` (kt:863-876 nulls every update time so the next refresh
     * is a full one) belongs to the host too, since the weather never crosses into this component.
     */
    this.onClose(this.currentSelection());
  }

  /* --------------------------------------------------------------------------- build ----------- */

  build() {
    Stack() {
      // Tapping the scrim is `onDismissRequest` → onClose(null) (kt:439-441).
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.onClose(null);
        })

      Column() {
        // strings.xml `settings_weather_sources`
        Text('Weather sources')
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        Scroll() {
          Column() {
            // kt:495-513 — a current position with no fix yet cannot be matched to national sources.
            if (this.target.isCurrentPosition && !this.isUsable()) {
              Text('More weather sources may become available for your location after the first refresh.')
                .fontFamily(APP_FONT_FAMILY)
                .fontSize(Dimens.CONTENT_TEXT_SIZE)
                .fontColor(AppColors.ON_SECONDARY_CONTAINER.resolve(this.dark))
                .width('100%')
                .padding(Dimens.NORMAL_MARGIN)
                .backgroundColor(AppColors.SECONDARY_CONTAINER.resolve(this.dark))
                .borderRadius(Dimens.CARD_CORNER_RADIUS)
                .margin({ bottom: Dimens.SMALL_MARGIN })
            }

            ForEach(FEATURE_ROWS, (feature: SourceFeature) => {
              this.featureRow(feature)
              // kt:558-565 — the duplicate warning sits directly under the forecast row.
              if (feature === SourceFeature.FORECAST && this.isLocationDuplicate) {
                Text('Location list already contains this location with this forecast source.')
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
                  .fontColor(AppColors.ALERT_TEXT.resolve(this.dark))
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
              }
            }, (feature: SourceFeature) => feature.toString())

            if (this.showsReverseGeocoding()) {
              this.featureRow(SourceFeature.REVERSE_GEOCODING)
            }
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // kt:843-907 — Cancel then Save, trailing.
        Row() {
          // `android.R.string.cancel`, which the platform button style renders upper-case —
          // "CANCEL" beside "Save" on the device.
          Text('CANCEL')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.onClose(null);
            })

          // strings.xml `action_save`. kt:845 disables it while the choice would duplicate.
          Text('Save')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .opacity(this.isLocationDuplicate ? DISABLED_ALPHA : 1)
            .padding(Dimens.SMALL_MARGIN)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.onSave();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Dimens.SMALL_MARGIN })
      }
      .width('90%')
      .padding(Dimens.LARGE_MARGIN + 4)
      .backgroundColor(searchSurface(this.dark))
      .borderRadius(Dimens.CARD_CORNER_RADIUS)
      .constraintSize({ maxHeight: '85%' })

      // The nested picker sits ABOVE the sources dialog, as a second AlertDialog does.
      if (this.openPicker !== null) {
        this.picker(this.openPicker)
      }
    }
    .width('100%')
    .height('100%')
  }

  /** One feature row — PreferenceView's ListItem (Preference.kt:154-226). */
  @Builder
  featureRow(feature: SourceFeature) {
    Column() {
      Text(sourceFeatureName(feature))
        .fontFamily(APP_FONT_FAMILY)
        // `MaterialTheme.typography.titleMedium` (Preference.kt:190)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)

      // `Spacer(small_margin)` then bodyMedium onSurfaceVariant (Preference.kt:214-220).
      Text(this.summaryFor(feature))
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.CONTENT_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: Dimens.SMALL_MARGIN })
    }
    .width('100%')
    /*
     * A Material3 ListItem is a FIXED 72 dp for a two-line item, whatever its text measures, and
     * PreferenceView (Preference.kt:148-166) wraps it in `PaddingValues(vertical = 8.dp)` — so the
     * row is 88 dp and its content is CENTRED in it, not stacked from the top.
     *
     * This used to size to its text and came out at 59 dp against the reference build's 88, which
     * made the whole dialog read tighter than Android's.
     */
    .height(LIST_ITEM_TWO_LINE + Dimens.SMALL_MARGIN * 2)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    // ListItemDefaults' 16 dp sides.
    .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
    .onClick(() => {
      this.openPicker = feature;
    })
  }

  /** The grouped radio picker for one row (ListPreference.kt:241-313). */
  @Builder
  picker(feature: SourceFeature) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.openPicker = null;
        })

      Column() {
        // The picker's title is the ROW's title, at headlineSmall (ListPreference.kt:244-250).
        Text(sourceFeatureName(feature))
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        List() {
          ForEach(this.entriesFor(feature), (entry: PickerEntry, index: number) => {
            ListItem() {
              if (entry.isHeader) {
                // titleSmall, CENTRED, with large_margin above unless it is the first line.
                Text(entry.label)
                  .fontFamily(APP_FONT_FAMILY)
                  .fontSize(TITLE_SMALL)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ left: Dimens.SMALL_MARGIN, right: Dimens.SMALL_MARGIN })
                  .margin({
                    top: index === 0 ? Dimens.SMALL_MARGIN : Dimens.LARGE_MARGIN,
                    bottom: Dimens.SMALL_MARGIN
                  })
              } else {
                this.radioRow(feature, entry)
              }
            }
          }, (entry: PickerEntry, index: number) =>
          index.toString() + ':' + entry.id + ':' + entry.label)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // The picker's only button is a Cancel; picking a row applies and closes (kt:301-311).
        Row() {
          // `android.R.string.cancel`, which the platform button style renders upper-case —
          // "CANCEL" beside "Save" on the device.
          Text('CANCEL')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.openPicker = null;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Dimens.SMALL_MARGIN })
      }
      .width('90%')
      .padding(Dimens.LARGE_MARGIN + 4)
      .backgroundColor(searchSurface(this.dark))
      .borderRadius(Dimens.CARD_CORNER_RADIUS)
      .constraintSize({ maxHeight: '85%' })
    }
    .width('100%')
    .height('100%')
  }

  /** ListPreference.kt:368-403 — a Radio, an 8 dp gap, and a titleMedium label. */
  @Builder
  radioRow(feature: SourceFeature, entry: PickerEntry) {
    Row() {
      Radio({ value: entry.id, group: 'sourceFeature' + feature.toString() })
        .checked(entry.id === this.selectedFor(feature))
        .radioStyle({
          checkedBackgroundColor: AppColors.PRIMARY.resolve(this.dark),
          uncheckedBorderColor: AppColors.ON_SURFACE_VARIANT.resolve(this.dark)
        })
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .enabled(entry.enabled)
        .onClick(() => {
          this.onPicked(feature, entry);
        })

      Text(entry.label)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .margin({ left: Dimens.SMALL_MARGIN })
    }
    .width('100%')
    .height(RADIO_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: Dimens.SMALL_MARGIN, right: Dimens.SMALL_MARGIN })
    // A disabled row is drawn at half opacity and does not respond, which is what
    // `enabled = false` gives a Compose RadioButton row.
    .opacity(entry.enabled ? 1 : DISABLED_ALPHA)
    .onClick(() => {
      this.onPicked(feature, entry);
    })
  }
}
