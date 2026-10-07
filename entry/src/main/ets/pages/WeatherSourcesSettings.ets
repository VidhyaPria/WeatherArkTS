/*
 * Screen 3f — Weather sources. Port of WeatherSourcesSettingsScreen.kt (:71-242).
 *
 * Captured before this was written: ref_screen3f_sources_top.png, ref_screen3f_sources_bottom.png
 * and ref_screen3f_instance_dialog.png.
 *
 *   General      Default source for new locations
 *   <source>     that source's own preferences, one section each, 40 of them
 *
 * The Kotlin is a loop, not a layout: it asks every ConfigurableSource for `getPreferences(context)`
 * and renders whatever comes back (kt:196-233). This port has no source clients to ask, so the
 * lists are transcribed in data/SourcePreferences.ets and the loop reads that instead. Section
 * headers come from SourceCatalogue, so they match the pickers on screens 2 and 3e exactly.
 *
 * WHAT IS REAL HERE: all of it. Every value is stored, every summary reflects what is stored, and
 * the default source actually decides which source a location added on screen 2b starts on
 * (SearchActivityRepository.kt:101-140) — so it is not a dead setting.
 *
 * The freenet disclaimer (kt:95-146) is absent for the same reason it is on screen 3e: the
 * reference build is not that flavour, and its capture starts straight at General.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow, settingsSectionHeader } from '../view/settings/PreferenceRow';
import { ListPreferenceDialog, ListPreferenceOption } from '../view/settings/ListPreferenceDialog';
import { EditTextDialog } from '../view/settings/EditTextDialog';
import { SystemInsets } from '../common/SystemBars';
import {
  AppSettings,
  appIsDark,
  setDefaultForecastSource,
  setSourcePref,
  sourcePrefValue
} from '../data/SettingsStore';
import { getSource, getSupportedFeatureSources, SourceFeature, SourceInfo } from '../data/SourceCatalogue';
import {
  DEFAULT_UNCHANGED,
  INSTANCE_INVALID,
  SOURCE_PREFERENCES,
  SourcePrefKind,
  SourcePrefOption,
  SourcePrefSection,
  SourcePrefSpec
} from '../data/SourcePreferences';
import { LocationModel } from '../model/Weather';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;
const SECTION_TEXT_SIZE: number = 14;

/** strings.xml:704. */
const DEFAULT_SOURCE_TITLE: string = 'Default source for new locations';
/** strings.xml:879 — and the "auto" key it stands for. */
const AUTOMATIC: string = 'Automatic';
const AUTO: string = 'auto';

/* -------------------------------------------------------------------- the flattened list ------ */

enum ItemKind {
  HEADER = 0,
  /** The one row in General. Its options are sources, not a stored value array. */
  DEFAULT_SOURCE = 1,
  LIST = 2,
  TEXT = 3
}

/**
 * One line of the screen, header or row.
 *
 * Flattened because the list is lazy: LazyForEach wants a single indexable sequence, and Android's
 * PreferenceScreen is a LazyColumn emitting exactly this — a header item, then a row item per
 * preference (kt:193-236).
 */
class SourceLine {
  readonly kind: ItemKind;
  readonly key: string;
  readonly title: string;
  /** Rows only. */
  readonly sourceId: string;
  readonly spec: SourcePrefSpec | null;
  readonly isFirst: boolean;
  readonly isLast: boolean;
  /** Headers only — a large separator sits above every one except General's. */
  readonly gapAbove: boolean;

  constructor(kind: ItemKind, key: string, title: string, sourceId: string,
    spec: SourcePrefSpec | null, isFirst: boolean, isLast: boolean, gapAbove: boolean) {
    this.kind = kind;
    this.key = key;
    this.title = title;
    this.sourceId = sourceId;
    this.spec = spec;
    this.isFirst = isFirst;
    this.isLast = isLast;
    this.gapAbove = gapAbove;
  }
}

/** Built once — the table never changes at runtime, only the values behind it do. */
function buildLines(): SourceLine[] {
  const lines: SourceLine[] = [];
  lines.push(new SourceLine(ItemKind.HEADER, 'h_general', 'General', '', null, false, false, false));
  lines.push(new SourceLine(ItemKind.DEFAULT_SOURCE, 'default_source', DEFAULT_SOURCE_TITLE,
    '', null, true, true, false));

  for (const section of SOURCE_PREFERENCES) {
    const source: SourceInfo | null = getSource(section.sourceId);
    // A source in the preferences table but not the catalogue would be a porting slip, not a state
    // the app can reach; skip it rather than draw a section with no name.
    if (source === null) {
      continue;
    }
    lines.push(new SourceLine(ItemKind.HEADER, 'h_' + section.sourceId, source.name,
      section.sourceId, null, false, false, true));
    for (let i = 0; i < section.prefs.length; i++) {
      const spec: SourcePrefSpec = section.prefs[i];
      lines.push(new SourceLine(
        spec.kind === SourcePrefKind.LIST ? ItemKind.LIST : ItemKind.TEXT,
        section.sourceId + '/' + spec.key,
        spec.title,
        section.sourceId,
        spec,
        i === 0,
        i === section.prefs.length - 1,
        false));
    }
  }
  return lines;
}

/**
 * The lazy list's backing store.
 *
 * Static: the lines are the same for the life of the screen, so nothing here ever notifies. A value
 * changing does not change the LIST, only what a row draws, and that is redrawn off the revision
 * counter the same way LocationSettings does it.
 */
class SourceLineSource implements IDataSource {
  private readonly lines: SourceLine[] = buildLines();

  totalCount(): number {
    return this.lines.length;
  }

  getData(index: number): SourceLine {
    return this.lines[index];
  }

  registerDataChangeListener(_listener: DataChangeListener): void {
  }

  unregisterDataChangeListener(_listener: DataChangeListener): void {
  }
}

@Entry
@ComponentV2
struct WeatherSourcesSettings {
  private insets: SystemInsets = SystemInsets.instance;
  private settings: AppSettings = AppSettings.instance;
  private lines: SourceLineSource = new SourceLineSource();

  @Local private dark: boolean = false;
  /** Which row's dialog is open — '' for none, 'default_source', or `<sourceId>/<key>`. */
  @Local private openKey: string = '';
  @Local private revision: number = 0;

  aboutToAppear(): void {
    this.syncDark();
  }

  onPageShow(): void {
    this.syncDark();
  }

  private syncDark(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.dark = appIsDark();
  }

  /** Re-reads every summary after a write — see SettingsStore.sourcePrefs on why not @Trace. */
  private stamp(): boolean {
    return this.revision >= 0;
  }

  /* --------------------------------------------------------------- the default-source row ----- */

  /**
   * kt:159-172 — "Automatic" first, then every source that reports FORECAST for a BLANK location,
   * which is what `Location()` gives the Kotlin. An entry is selectable unless the source is
   * configurable and not configured (kt:166-168); it is still listed either way.
   */
  private defaultSourceOptions(): ListPreferenceOption[] {
    const options: ListPreferenceOption[] = [new ListPreferenceOption(AUTO, AUTOMATIC)];
    const worldwide: SourceInfo[] =
      getSupportedFeatureSources(SourceFeature.FORECAST, new LocationModel(), '');
    for (const source of worldwide) {
      /*
       * kt:165 calls `it.getName(context)`, not `it.name` — SourceExtensions.getName appends
       * `settings_weather_source_not_configured` ("%s (not configured)") to an unconfigured one, so
       * the entry is RENAMED as well as dimmed. Read off the Android dialog, which lists
       * "Infoplaza (not configured)", "PirateWeather (not configured)" and
       * "Met Office (United Kingdom) (not configured)" while the rest are plain.
       */
      const label: string = source.configured ? source.name : source.name + ' (not configured)';
      options.push(new ListPreferenceOption(source.id, label, source.configured));
    }
    return options;
  }

  /** kt:154-158 — a stored id that is not on the list reads as "auto". */
  private defaultSourceSummary(): string {
    const options: ListPreferenceOption[] = this.defaultSourceOptions();
    for (const option of options) {
      if (this.stamp() && option.value === this.settings.defaultForecastSource) {
        return option.name;
      }
    }
    return AUTOMATIC;
  }

  private defaultSourceSelected(): string {
    const options: ListPreferenceOption[] = this.defaultSourceOptions();
    for (const option of options) {
      if (option.value === this.settings.defaultForecastSource) {
        return option.value;
      }
    }
    return AUTO;
  }

  /* ------------------------------------------------------------------- a source's own rows ---- */

  /** LIST rows show the chosen option's name; the stored value is the option's key. */
  private listSummary(line: SourceLine): string {
    const spec: SourcePrefSpec = line.spec as SourcePrefSpec;
    const options: SourcePrefOption[] = spec.options !== undefined ? spec.options : [];
    const stored: string = this.stamp() ? sourcePrefValue(line.sourceId, spec.key) : '';
    const wanted: string = stored.length > 0 ? stored : (spec.fallback !== undefined ? spec.fallback : '');
    for (const option of options) {
      if (option.value === wanted) {
        return option.name;
      }
    }
    return options.length > 0 ? options[0].name : '';
  }

  /**
   * TEXT rows show what is stored. Empty falls back to the source's own default URL for an instance
   * row (ClimWebService.kt:376-380) and to "Default (unchanged)" for an API key (AtmoService.kt:158-161).
   */
  private textSummary(line: SourceLine): string {
    const spec: SourcePrefSpec = line.spec as SourcePrefSpec;
    const stored: string = this.stamp() ? sourcePrefValue(line.sourceId, spec.key) : '';
    if (stored.length > 0) {
      return stored;
    }
    return spec.placeholder !== undefined ? spec.placeholder : DEFAULT_UNCHANGED;
  }

  private listOptions(spec: SourcePrefSpec): ListPreferenceOption[] {
    const options: ListPreferenceOption[] = [];
    const source: SourcePrefOption[] = spec.options !== undefined ? spec.options : [];
    for (const option of source) {
      options.push(new ListPreferenceOption(option.value, option.name));
    }
    return options;
  }

  /** The line whose dialog is open, or null. */
  private openLine(): SourceLine | null {
    if (this.openKey.length === 0) {
      return null;
    }
    for (let i = 0; i < this.lines.totalCount(); i++) {
      const line: SourceLine = this.lines.getData(i);
      if (line.key === this.openKey) {
        return line;
      }
    }
    return null;
  }

  /** Delegates to the ONE implementation in view/settings/PreferenceRow.ets. */
  @Builder
  sectionHeader(title: string) {
    settingsSectionHeader(title, this.dark)
  }

  @Builder
  line(item: SourceLine) {
    Column() {
      if (item.kind === ItemKind.HEADER) {
        if (item.gapAbove) {
          // largeSeparatorItem() before every source section (kt:192).
          Column().width('100%').height(Dimens.SETTINGS_LARGE_SEPARATOR)
        }
        this.sectionHeader(item.title)
      } else if (item.kind === ItemKind.DEFAULT_SOURCE) {
        PreferenceRow({
          title: item.title,
          summary: this.defaultSourceSummary(),
          icon: null,
          dark: this.dark,
          isFirst: true,
          isLast: true,
          onTap: () => {
            this.openKey = item.key;
          }
        })
      } else {
        PreferenceRow({
          title: item.title,
          summary: item.kind === ItemKind.LIST ? this.listSummary(item) : this.textSummary(item),
          icon: null,
          dark: this.dark,
          isFirst: item.isFirst,
          isLast: item.isLast,
          onTap: () => {
            this.openKey = item.key;
          }
        })
        // smallSeparatorItem() between rows of one section (kt:230-232).
        if (!item.isLast) {
          Column().width('100%').height(Dimens.SETTINGS_SMALL_SEPARATOR)
        }
      }
    }
    .width('100%')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Image($r('app.media.ic_back'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .margin({ left: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              router.back();
            })

          Blank()

          Image($r('app.media.ic_info'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .margin({ right: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              // AboutActivityIconButton (AppBar.kt:29-31) opens the REAL About screen, on every
              // settings screen that carries the icon - not just the root. Both ports used to send
              // all ten to the placeholder.
              router.pushUrl({ url: 'pages/About' })
                .catch((error: Error) => {
                  console.error('About unavailable: ' + error.message);
                });
            })
        }
        .width('100%')
        .height(APP_BAR_HEIGHT)
        .alignItems(VerticalAlign.Center)

        Text('Weather sources') // strings.xml:701 `settings_weather_sources`
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .maxLines(1)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN, top: Dimens.LARGE_TITLE_TOP_PADDING })
          .height(APP_BAR_EXPANDED_HEIGHT - APP_BAR_HEIGHT)

        /*
         * A LAZY list, unlike every other settings screen in this port.
         *
         * The others are a Scroll + Column of a dozen rows; this one has ninety, and Android's is a
         * LazyColumn. Building all ninety eagerly would put rows in memory that the Android app
         * never materialises — which would show up in the very comparison this project exists to
         * make, as a cost of the port rather than of the platform.
         */
        List() {
          LazyForEach(this.lines, (item: SourceLine) => {
            ListItem() {
              this.line(item)
            }
          }, (item: SourceLine) => item.key)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppColors.SURFACE.resolve(this.dark))
      .padding({
        top: this.insets.top,
        bottom: this.insets.bottom,
        left: this.insets.left,
        right: this.insets.right
      })

      if (this.openKey === 'default_source') {
        ListPreferenceDialog({
          title: DEFAULT_SOURCE_TITLE,
          options: this.defaultSourceOptions(),
          selected: this.defaultSourceSelected(),
          dark: this.dark,
          onChosen: (value: string) => {
            this.openKey = '';
            setDefaultForecastSource(value).then(() => {
              this.revision++;
            });
          },
          onDismiss: () => {
            this.openKey = '';
          }
        })
      } else if (this.openLine() !== null) {
        this.dialogFor(this.openLine() as SourceLine)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  dialogFor(line: SourceLine) {
    if (line.spec !== null && line.kind === ItemKind.LIST) {
      ListPreferenceDialog({
        title: line.title,
        options: this.listOptions(line.spec as SourcePrefSpec),
        selected: this.listSummarySelected(line),
        dark: this.dark,
        onChosen: (value: string) => {
          this.openKey = '';
          setSourcePref(line.sourceId, (line.spec as SourcePrefSpec).key, value).then(() => {
            this.revision++;
          });
        },
        onDismiss: () => {
          this.openKey = '';
        }
      })
    } else if (line.spec !== null) {
      EditTextDialog({
        title: line.title,
        content: sourcePrefValue(line.sourceId, (line.spec as SourcePrefSpec).key),
        placeholder: (line.spec as SourcePrefSpec).placeholder !== undefined
          ? (line.spec as SourcePrefSpec).placeholder as string
          : '',
        url: (line.spec as SourcePrefSpec).url === true,
        regexError: INSTANCE_INVALID,
        dark: this.dark,
        onChosen: (value: string) => {
          this.openKey = '';
          setSourcePref(line.sourceId, (line.spec as SourcePrefSpec).key, value).then(() => {
            this.revision++;
          });
        },
        onDismiss: () => {
          this.openKey = '';
        }
      })
    }
  }

  /** The key the radio should start on — the stored one, or the preference's own default. */
  private listSummarySelected(line: SourceLine): string {
    const spec: SourcePrefSpec = line.spec as SourcePrefSpec;
    const stored: string = sourcePrefValue(line.sourceId, spec.key);
    if (stored.length > 0) {
      return stored;
    }
    return spec.fallback !== undefined ? spec.fallback : '';
  }
}
