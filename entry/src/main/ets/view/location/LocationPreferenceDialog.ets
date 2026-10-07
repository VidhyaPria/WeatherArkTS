/*
 * The main screen's "Edit this location" dialog.
 *
 * MainActivity.kt:481-607 wraps `LocationPreference` (LocationPreferences.kt:75-350) in an
 * AlertDialogNoPadding with a Close button, a Delete button, and a delete-confirmation dialog
 * behind Delete. `onEditIconClicked` (kt:897-904) opens it; a refresh in flight refuses it first.
 *
 * This is NOT the same composable as the location list's swipe-left dialog. That one is
 * `SecondarySourcesPreference` (kt:352-916), which this port already has as WeatherSourcesDialog —
 * and which is reached from HERE as one of four rows. The distinction cost this port a real gap:
 * the sources dialog was ported and wired from the list and from search, and the main screen's edit
 * icon, which opens the OUTER dialog, went to the placeholder because the inner one already existed.
 *
 * The four rows (kt:90-145), in order:
 *
 *   Location service       only when the location is the current position (kt:90-112). A picker
 *                          over locationSourceList; choosing writes the GLOBAL `location_service`
 *                          setting and closes the whole dialog with `onClose(null)` (kt:109-110).
 *   Weather sources        opens WeatherSourcesDialog (kt:113-122, 147-175).
 *   Location preferences   shown when the location is not the current position, or when some
 *                          source contributes a per-location screen (kt:123-134). Opens a second
 *                          dialog: the custom name, then a section per such source.
 *   Global settings        opens the Main screen settings page and closes (kt:135-145).
 *
 * Surface conventions (scrim, 90% width, LARGE_MARGIN+4 padding, 85% max height, the trailing
 * button row) are taken from WeatherSourcesDialog so the two read as the same dialog stack, which
 * is what they are on Android — both are AlertDialogNoPadding.
 */

import { router } from '@kit.ArkUI';
import { Dimens } from '../../theme/Dimens';
import { AppColors, searchSurface } from '../../theme/AppColors';
/*
 * The Compose face, not Roboto. Every composable in this stack lives in `ui/common/composables/`
 * and takes `fontFamily = FontFamily.Default` (Type.kt:28) — the SYSTEM sans-serif, which on the
 * reference device is HarmonyOS Sans. The constant is named for the settings screens because that
 * is where the distinction was first found; it means "the face Compose gets".
 */
import { SETTINGS_FONT_FAMILY } from '../../common/Typography';
import { AppSettings, setLocationService } from '../../data/SettingsStore';
import { getSource } from '../../data/SourceCatalogue';
import { LocationSources, WeatherSourcesDialog } from './WeatherSourcesDialog';
import {
  modelsSummary,
  selectedWeatherModels,
  WeatherModelInfo,
  WEATHER_MODELS
} from '../../model/OpenMeteoModels';

/** `MaterialTheme.typography.headlineSmall` — every dialog title in this stack. */
const HEADLINE_SMALL: number = 24;
/** AlertDialogNoPadding's scrim, matching WeatherSourcesDialog. */
const SCRIM: string = '#52000000';
/** Material3 ListItem, two-line — what a non-card PreferenceView measures (Preference.kt:136-227). */
const LIST_ITEM_TWO_LINE: number = 72;
/** Material3 ListItem, one line — a switch row with no summary (SwitchPreference.kt:155-230). */
const LIST_ITEM_ONE_LINE: number = 56;
/** `Widget.Material3.Switch` — 52 x 32 dp, the size the settings rows were corrected to. */
const SWITCH_WIDTH: number = 52;
const SWITCH_HEIGHT: number = 32;
/** Material's titleMedium / bodyMedium tracking, in sp. */
const TITLE_LETTER_SPACING: number = 0.15;
const SUMMARY_LETTER_SPACING: number = 0.25;
/** The 1 px rule `HorizontalDivider()` draws between model groups. */
const DIVIDER_HEIGHT: number = 1;
/** ListPreference.kt's radio row. */
const RADIO_ROW_HEIGHT: number = 56;

/** locationSourceList (SourceCatalogue.ets:555), in the Kotlin's order. */
const LOCATION_SOURCE_IDS: string[] = ['native', 'ipsb', 'baidu_ip'];

/**
 * What the dialog gives back when the per-location preferences are saved.
 *
 * Scalars only, for the reason LocationSources documents: a LocationModel reaches its weather graph
 * and handing one to a @Param registers observation bindings across all of it.
 */
export class LocationPrefsResult {
  customName: string = '';
  weatherModels: string = '';
  /** Whether anything actually changed — kt:889 only calls onSave when it did. */
  changed: boolean = false;
}

/** One row of the models dialog, mirroring `WeatherModelStatus` (OpenMeteoService.kt:775-778). */
class ModelRow {
  readonly model: WeatherModelInfo;
  enabled: boolean;

  constructor(model: WeatherModelInfo, enabled: boolean) {
    this.model = model;
    this.enabled = enabled;
  }
}

@ComponentV2
export struct LocationPreferenceDialog {
  /** The location being edited, as the sources dialog already models it. */
  @Param target: LocationSources = new LocationSources();
  /** `location.cityAndDistrict` — what the custom-name field seeds itself with (kt:200-204). */
  @Param place: string = '';
  @Param customName: string = '';
  @Param weatherModels: string = '';
  @Param dark: boolean = false;
  /** `locationListSize() > 1` (MainActivity.kt:530) — the Delete button is absent below that. */
  @Param canDelete: boolean = false;

  /** Close, the scrim, and the two rows that navigate away — all `onClose(null)`. */
  @Event onDismiss: () => void = () => {
  };
  /** The nested weather-sources dialog saved. The host applies it to the real location. */
  @Event onSourcesSaved: (sources: LocationSources) => void = () => {
  };
  /** The per-location preferences dialog saved. */
  @Event onPrefsSaved: (result: LocationPrefsResult) => void = () => {
  };
  /** Confirm on the delete dialog (kt:577-581). */
  @Event onDelete: () => void = () => {
  };
  /** Passed straight through to the sources dialog. */
  @Event locationExists: (latitude: number, longitude: number, forecastSource: string) => boolean =
    () => false;

  /* ------------------------------------------------------------------------- dialog state ------ */

  @Local private sourcesOpen: boolean = false;
  @Local private prefsOpen: boolean = false;
  @Local private modelsOpen: boolean = false;
  @Local private nameEditOpen: boolean = false;
  @Local private deleteConfirmOpen: boolean = false;
  @Local private servicePickerOpen: boolean = false;

  /** The preferences dialog's working copies — discarded unless Confirm is pressed. */
  @Local private draftName: string = '';
  @Local private draftModels: ModelRow[] = [];
  @Local private prefsChanged: boolean = false;
  @Local private modelsChanged: boolean = false;
  /** Bumped to re-read `draftModels`, which ForEach cannot see mutate in place. */
  @Local private modelsVersion: number = 0;
  /** The name field's live text. */
  @Local private nameDraft: string = '';

  /* ------------------------------------------------------------------------------- rules ------- */

  /**
   * `sourcesWithPreferencesScreen` (SourceManager.kt:409-432), reduced to the one source in this
   * port that has a per-location screen.
   *
   * Two details matter and both were got wrong first time:
   *   - it walks ALL SEVEN source slots, not just the forecast one;
   *   - Open-Meteo's own `hasPreferencesScreen` (OpenMeteoService.kt:755-762) answers true only for
   *     FORECAST, CURRENT and MINUTELY — being the pollen or air-quality source does not earn it a
   *     section.
   * And kt:424 reads `it.first ?: location.forecastSource`, so an empty slot IS the forecast
   * source, which is what "" already means in this model.
   */
  private hasSourcePreferences(): boolean {
    const forecast: string = this.target.forecastSource;
    const current: string =
      this.target.currentSource.length > 0 ? this.target.currentSource : forecast;
    const minutely: string =
      this.target.minutelySource.length > 0 ? this.target.minutelySource : forecast;
    return forecast === 'openmeteo' || current === 'openmeteo' || minutely === 'openmeteo';
  }

  /** kt:123 — the row is hidden only for a current position with nothing to configure. */
  private showsPreferencesRow(): boolean {
    return !this.target.isCurrentPosition || this.hasSourcePreferences();
  }

  /** kt:200-204 — the field shows the custom name, or the city when there is none. */
  private nameSummary(): string {
    return this.customName.length > 0 ? this.customName : this.place;
  }

  private locationServiceName(): string {
    const chosen: string = AppSettings.instance.locationService;
    const source = getSource(chosen);
    return source !== null ? source.name : chosen;
  }

  /* ------------------------------------------------------------------- opening the sub-dialogs - */

  private openPreferences(): void {
    this.draftName = this.customName;
    this.nameDraft = this.nameSummary();
    this.prefsChanged = false;
    this.rebuildModelDraft();
    this.prefsOpen = true;
  }

  /** kt:789-801 — every model, flagged by whether the location's stored list contains it. */
  private rebuildModelDraft(): void {
    const selected: string[] = selectedWeatherModels(this.weatherModels);
    const rows: ModelRow[] = [];
    for (let i = 0; i < WEATHER_MODELS.length; i++) {
      rows.push(new ModelRow(WEATHER_MODELS[i], selected.includes(WEATHER_MODELS[i].id)));
    }
    this.draftModels = rows;
    this.modelsChanged = false;
    this.modelsVersion++;
  }

  /**
   * kt:854-879 — the switch handler, ported as it behaves.
   *
   * Turning a model ON turns every OTHER model off. The Kotlin reads
   * `OpenMeteoWeatherModel.entries.filter { id != model.model.id }`, where `id` is the SOURCE's id
   * ("openmeteo") and never equals a model id — so the filter keeps every entry and the loop
   * disables all of them before re-enabling the one just tapped. Whatever was intended, that is
   * what the reference build does: the switches behave as a single-select. Ported 1:1 rather than
   * "corrected", because the requirement here is to match the app, and a port that allowed two
   * models at once would send a `models=a,b` request the reference never sends.
   */
  private onModelToggled(index: number, checked: boolean): void {
    const rows: ModelRow[] = this.draftModels;
    if (checked) {
      for (let i = 0; i < rows.length; i++) {
        rows[i].enabled = false;
      }
      rows[index].enabled = true;
    } else {
      rows[index].enabled = false;
    }
    this.modelsChanged = true;
    this.modelsVersion++;
  }

  /** kt:889-897 — the models dialog's Confirm. */
  private confirmModels(): void {
    if (this.modelsChanged) {
      this.prefsChanged = true;
    }
    this.modelsOpen = false;
  }

  /** kt:911-917 — Cancel and dismiss both restore the stored selection. */
  private cancelModels(): void {
    this.rebuildModelDraft();
    this.modelsOpen = false;
  }

  /** The model ids the draft currently has on, in catalogue order, `best_match` if none. */
  private draftModelValue(): string {
    const ids: string[] = [];
    for (let i = 0; i < this.draftModels.length; i++) {
      if (this.draftModels[i].enabled) {
        ids.push(this.draftModels[i].model.id);
      }
    }
    // kt:894 — `.ifEmpty { BEST_MATCH.id }`.
    return ids.length > 0 ? ids.join(',') : 'best_match';
  }

  /** The summary under the Weather models row, from the DRAFT rather than the stored value. */
  private draftModelsSummary(): string {
    return this.modelsVersion >= 0 ? modelsSummary(this.draftModelValue()) : '';
  }

  /**
   * kt:205-215 — the custom name's own rule, which is not "store what was typed".
   *
   * Typing the city back, or clearing the field, stores "" — so the name follows a later geocode
   * again instead of being frozen at whatever the city happened to be when the user opened the
   * dialog. Anything else is stored verbatim.
   */
  private onNameEntered(value: string): void {
    if (value !== this.place && value !== this.customName) {
      this.draftName = value;
      this.prefsChanged = true;
    } else if ((value === this.place || value.length === 0) && this.customName.length > 0) {
      this.draftName = '';
      this.prefsChanged = true;
    }
    this.nameEditOpen = false;
  }

  /** The preferences dialog's Confirm. */
  private confirmPreferences(): void {
    if (this.prefsChanged) {
      const result = new LocationPrefsResult();
      result.customName = this.draftName;
      result.weatherModels = this.draftModelValue();
      result.changed = true;
      this.onPrefsSaved(result);
    }
    this.prefsOpen = false;
  }

  /* ------------------------------------------------------------------------------- build ------- */

  build() {
    Stack() {
      // `onDismissRequest` (kt:492-494) — the scrim closes the whole thing without saving.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.onDismiss();
        })

      Column() {
        // strings.xml:474 `action_edit_location`, headlineSmall (kt:495-501).
        Text('Edit this location')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        Scroll() {
          Column() {
            // kt:90-112 — current position only.
            if (this.target.isCurrentPosition) {
              this.preferenceRow('Location service', this.locationServiceName(),
                $r('app.media.ic_location'), () => {
                  this.servicePickerOpen = true;
                })
            }

            // kt:113-122. strings.xml:701 / :712.
            this.preferenceRow('Weather sources',
              'Customize weather data sources used for this location',
              $r('app.media.ic_factory'), () => {
                this.sourcesOpen = true;
              })

            // kt:123-134. strings.xml:698 / :699.
            if (this.showsPreferencesRow()) {
              this.preferenceRow('Location preferences',
                'Additional customizations for this location',
                $r('app.media.ic_settings'), () => {
                  this.openPreferences();
                })
            }

            // kt:135-145. strings.xml:696 / :802.
            this.preferenceRow('Global settings', 'Blocks order, items displayed, animations',
              $r('app.media.ic_home'), () => {
                // kt:143-144 — the settings screen opens and the dialog closes behind it.
                router.pushUrl({ url: 'pages/MainScreenSettings' })
                  .catch((error: Error) => {
                    console.error('Main screen settings unavailable: ' + error.message);
                  });
                this.onDismiss();
              })
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        /*
         * kt:517-546 — Delete (error-coloured, leading) then Close (trailing). Compose puts the
         * dismissButton before the confirmButton in an AlertDialog's button row, which is why
         * Delete reads first.
         */
        Row() {
          if (this.canDelete) {
            // strings.xml:538 `action_delete`, on colorScheme.error (kt:537-541).
            Text('DELETE')
              .fontFamily(SETTINGS_FONT_FAMILY)
              .fontSize(Dimens.CONTENT_TEXT_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppColors.ALERT_TEXT.resolve(this.dark))
              .padding(Dimens.SMALL_MARGIN)
              .onClick(() => {
                this.deleteConfirmOpen = true;
              })
          }

          // strings.xml:501 `action_close`.
          Text('CLOSE')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.onDismiss();
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

      // Each sub-dialog stacks ABOVE this one, as a second AlertDialog does on Android.
      if (this.servicePickerOpen) {
        this.locationServicePicker()
      }
      if (this.sourcesOpen) {
        WeatherSourcesDialog({
          target: this.target,
          dark: this.dark,
          onClose: (sources: LocationSources | null) => {
            this.sourcesOpen = false;
            // kt:151-172 — a null is Cancel and leaves the outer dialog standing.
            if (sources !== null) {
              this.onSourcesSaved(sources);
            }
          },
          locationExists: (latitude: number, longitude: number, forecastSource: string) =>
          this.locationExists(latitude, longitude, forecastSource)
        })
      }
      if (this.prefsOpen) {
        this.preferencesDialog()
      }
      if (this.modelsOpen) {
        this.modelsDialog()
      }
      if (this.nameEditOpen) {
        this.nameDialog()
      }
      if (this.deleteConfirmOpen) {
        this.deleteDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  /* ------------------------------------------------------------------------------- rows -------- */

  /**
   * `PreferenceView` with a leading icon and a transparent container (Preference.kt:136-227) —
   * every row in this dialog passes `containerColor = Color.Transparent`, so there is no card.
   */
  @Builder
  preferenceRow(title: string, summary: string, icon: Resource, onTap: () => void) {
    Row() {
      Image(icon)
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .fillColor(AppColors.ON_SURFACE.resolve(this.dark))

      Column() {
        Text(title)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(TITLE_LETTER_SPACING)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(summary)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .letterSpacing(SUMMARY_LETTER_SPACING)
          .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: Dimens.SMALL_MARGIN })
      }
      .layoutWeight(1)
      .margin({ left: Dimens.NORMAL_MARGIN })
    }
    .width('100%')
    // A two-line ListItem is a fixed 72 dp token, not content + padding.
    .constraintSize({ minHeight: LIST_ITEM_TWO_LINE })
    .alignItems(VerticalAlign.Center)
    .padding({
      left: Dimens.NORMAL_MARGIN,
      right: Dimens.NORMAL_MARGIN,
      top: Dimens.SMALL_MARGIN,
      bottom: Dimens.SMALL_MARGIN
    })
    .onClick(onTap)
  }

  /* -------------------------------------------------------------------------- sub-dialogs ------ */

  /** kt:92-111 — a SourceView over locationSourceList; picking writes the global setting. */
  @Builder
  locationServicePicker() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.servicePickerOpen = false;
        })

      Column() {
        Text('Location service')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        List() {
          ForEach(LOCATION_SOURCE_IDS, (id: string) => {
            ListItem() {
              Row() {
                Radio({ value: id, group: 'locationService' })
                  .checked(id === AppSettings.instance.locationService)
                  .radioStyle({
                    checkedBackgroundColor: AppColors.PRIMARY.resolve(this.dark),
                    uncheckedBorderColor: AppColors.ON_SURFACE_VARIANT.resolve(this.dark)
                  })
                  .width(Dimens.MATERIAL_ICON_SIZE)
                  .height(Dimens.MATERIAL_ICON_SIZE)
                  .onClick(() => {
                    this.pickLocationService(id);
                  })

                Text(this.sourceName(id))
                  .fontFamily(SETTINGS_FONT_FAMILY)
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
              .onClick(() => {
                this.pickLocationService(id);
              })
            }
          }, (id: string) => id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Row() {
          Text('CANCEL')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.servicePickerOpen = false;
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

  private sourceName(id: string): string {
    const source = getSource(id);
    return source !== null ? source.name : id;
  }

  /** kt:108-111 — writes the GLOBAL setting, then closes the whole dialog. */
  private pickLocationService(id: string): void {
    setLocationService(id).catch((error: Error) => {
      console.error('Location service write failed: ' + error.message);
    });
    this.servicePickerOpen = false;
    this.onDismiss();
  }

  /** kt:177-320 — "Location preferences": the custom name, then a section per source. */
  @Builder
  preferencesDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.prefsOpen = false;
        })

      Column() {
        Text('Location preferences')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        Scroll() {
          Column() {
            // kt:195-218 — the General section exists only for a saved location; a current
            // position has no name of its own to override.
            if (!this.target.isCurrentPosition) {
              this.sectionHeader('General')
              this.preferenceRowNoIcon('Custom name',
                this.draftName.length > 0 ? this.draftName : this.place, () => {
                  this.nameDraft = this.draftName.length > 0 ? this.draftName : this.place;
                  this.nameEditOpen = true;
                })
            }

            // kt:220-224 — one section per source with a per-location screen. Open-Meteo's is a
            // single "Weather models" row (OpenMeteoService.kt:803-821).
            if (this.hasSourcePreferences()) {
              this.sectionHeader('Open-Meteo')
              this.preferenceRowNoIcon('Weather models', this.draftModelsSummary(), () => {
                this.modelsOpen = true;
              })
            }
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Row() {
          Text('CANCEL')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.prefsOpen = false;
            })

          Text('Confirm')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.confirmPreferences();
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

  /** `SectionHeader` (Section.kt) — titleSmall in the primary colour, 16 dp sides. */
  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontFamily(SETTINGS_FONT_FAMILY)
      .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppColors.PRIMARY.resolve(this.dark))
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({
        left: Dimens.NORMAL_MARGIN,
        right: Dimens.NORMAL_MARGIN,
        top: Dimens.NORMAL_MARGIN,
        bottom: Dimens.SMALL_MARGIN
      })
  }

  /** The same row without a leading icon — what the preferences dialog's rows are. */
  @Builder
  preferenceRowNoIcon(title: string, summary: string, onTap: () => void) {
    Column() {
      Text(title)
        .fontFamily(SETTINGS_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Medium)
        .letterSpacing(TITLE_LETTER_SPACING)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(summary)
        .fontFamily(SETTINGS_FONT_FAMILY)
        .fontSize(Dimens.CONTENT_TEXT_SIZE)
        .letterSpacing(SUMMARY_LETTER_SPACING)
        .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: Dimens.SMALL_MARGIN })
    }
    .width('100%')
    .constraintSize({ minHeight: LIST_ITEM_TWO_LINE })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: Dimens.NORMAL_MARGIN,
      right: Dimens.NORMAL_MARGIN,
      top: Dimens.SMALL_MARGIN,
      bottom: Dimens.SMALL_MARGIN
    })
    .onClick(onTap)
  }

  /** EditTextPreferenceView's own dialog — a single field over the current value. */
  @Builder
  nameDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.nameEditOpen = false;
        })

      Column() {
        Text('Custom name')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        TextInput({ text: this.nameDraft })
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .caretColor(AppColors.PRIMARY.resolve(this.dark))
          .backgroundColor(AppColors.SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          .onChange((value: string) => {
            this.nameDraft = value;
          })

        Row() {
          Text('CANCEL')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.nameEditOpen = false;
            })

          Text('OK')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.onNameEntered(this.nameDraft);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Dimens.NORMAL_MARGIN })
      }
      .width('90%')
      .padding(Dimens.LARGE_MARGIN + 4)
      .backgroundColor(searchSurface(this.dark))
      .borderRadius(Dimens.CARD_CORNER_RADIUS)
    }
    .width('100%')
    .height('100%')
  }

  /** OpenMeteoService.kt:823-936 — the weather-models list. */
  @Builder
  modelsDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.cancelModels();
        })

      Column() {
        Text('Weather models')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        List() {
          ForEach(this.draftModels, (row: ModelRow, index: number) => {
            ListItem() {
              Column() {
                // kt:843-845 — a rule ABOVE every combining model, and kt:880-882 one BELOW
                // "Best match". Together they fence the two special entries off from the rest.
                if (row.model.id.endsWith('_seamless')) {
                  this.divider()
                }
                this.modelRow(row, index)
                if (row.model.id === 'best_match') {
                  this.divider()
                }
              }
              .width('100%')
            }
          }, (row: ModelRow, index: number) =>
          row.model.id + ':' + index.toString() + ':' + this.modelsVersion.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .cachedCount(4)

        Row() {
          Text('CANCEL')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.cancelModels();
            })

          Text('Confirm')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.confirmModels();
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

  @Builder
  divider() {
    Column()
      .width('100%')
      .height(DIVIDER_HEIGHT)
      // `HorizontalDivider()` takes DividerDefaults.color, which is Material 3's outlineVariant.
      .backgroundColor(AppColors.COMPOSE_OUTLINE_VARIANT.resolve(this.dark))
  }

  /** A non-card SwitchPreferenceView (SwitchPreference.kt:155-230) — a bare ListItem. */
  @Builder
  modelRow(row: ModelRow, index: number) {
    Row() {
      Column() {
        Text(row.model.name)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.TITLE_TEXT_SIZE)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(TITLE_LETTER_SPACING)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)

        // kt:198-211 — the supporting line exists only when there IS one, and only the two
        // combining models have one, so most rows are a one-line 56 dp item.
        if (row.model.description.length > 0) {
          Text(row.model.description)
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .letterSpacing(SUMMARY_LETTER_SPACING)
            .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: Dimens.SMALL_MARGIN })
        }
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: row.enabled })
        .width(SWITCH_WIDTH)
        .height(SWITCH_HEIGHT)
        .selectedColor(AppColors.PRIMARY.resolve(this.dark))
        .margin({ left: Dimens.SMALL_MARGIN })
        .onChange((checked: boolean) => {
          this.onModelToggled(index, checked);
        })
    }
    .width('100%')
    .constraintSize({
      minHeight: row.model.description.length > 0 ? LIST_ITEM_TWO_LINE : LIST_ITEM_ONE_LINE
    })
    .alignItems(VerticalAlign.Center)
    .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
    .onClick(() => {
      this.onModelToggled(index, !row.enabled);
    })
  }

  /** MainActivity.kt:549-603 — the delete confirmation. */
  @Builder
  deleteDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SCRIM)
        .onClick(() => {
          this.deleteConfirmOpen = false;
        })

      Column() {
        // strings.xml:440
        Text('Delete location?')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_SMALL)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        /*
         * strings.xml:441 / :442 — the named and unnamed forms. Android chooses on
         * `it.city.isNotEmpty()` (kt:563), so a location with no city takes the second string; the
         * quotes around the name are part of the resource, curly in the original.
         */
        // Escaped rather than typed: a non-ASCII literal in this tree has reached the device as
        // mojibake before, and the curly quotes and apostrophe here are part of the resource.
        Text(this.place.length > 0
          ? 'You’re about to delete “' + this.place +
            '” from your list of saved locations.'
          : 'You’re about to delete this location from your list of saved locations.')
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)

        Row() {
          Text('CANCEL')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.deleteConfirmOpen = false;
            })

          // strings.xml:500 `action_confirm`. kt:577-581 closes BOTH dialogs, then deletes.
          Text('Confirm')
            .fontFamily(SETTINGS_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              this.deleteConfirmOpen = false;
              this.onDelete();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Dimens.NORMAL_MARGIN })
      }
      .width('90%')
      .padding(Dimens.LARGE_MARGIN + 4)
      .backgroundColor(searchSurface(this.dark))
      .borderRadius(Dimens.CARD_CORNER_RADIUS)
    }
    .width('100%')
    .height('100%')
  }
}
