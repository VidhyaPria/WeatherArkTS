/*
 * Screen 3b — Units. Port of UnitSettingsScreen.kt (:44-264).
 *
 * FIVE list preferences in ONE card group, no section headers: Temperature, Precipitation, Speed,
 * Distance, Pressure. `isFirst = true` is on temperature (kt:90) and `isLast = true` on pressure
 * (kt:248), with `smallSeparatorItem()` between each pair (kt:104, :156, :191, :226) — so the group
 * is a single rounded card with 2 dp gaps, the same shape the root settings screen uses.
 *
 * Every list is `arrayOf("auto") + <Unit>.entries`, i.e. the regional preference first and then the
 * units themselves; the row summary is the name of whatever is selected, and "auto" reads
 * "Regional preference (<what it resolves to>)" (kt:72-81).
 *
 * TITLES AND OPTION NAMES WERE READ OFF THE REFERENCE DEVICE, not derived. The long unit names come
 * from ICU's MeasureUnit at UnitWidth.LONG, which this port cannot compute, so they were captured
 * with `uiautomator dump` from the Android build's own dialogs. See `model/UnitCatalogue.ets`.
 *
 * WHAT IS REAL HERE: all five. Each writes through SettingsStore into the same key SettingsManager
 * uses, and the weather screen re-reads it — this is not a screen of placeholders.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow } from '../view/settings/PreferenceRow';
import { ListPreferenceDialog, ListPreferenceOption } from '../view/settings/ListPreferenceDialog';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark, setUnitSetting, unitSetting } from '../data/SettingsStore';
import { regionalDefaultId, regionalDefaultSnowfallId } from '../common/Units';
import { UnitDef, UnitFamily, unitById, unitsFor, UNIT_AUTO } from '../model/UnitCatalogue';

const APP_BAR_HEIGHT: number = 64;
const APP_BAR_EXPANDED_HEIGHT: number = 152;
const HEADLINE_TEXT_SIZE: number = 28;

/** One row of the screen: which quantity it configures and what the Kotlin titles it. */
class UnitRow {
  readonly family: UnitFamily;
  readonly title: string;

  constructor(family: UnitFamily, title: string) {
    this.family = family;
    this.title = title;
  }
}

/** kt:69, :105, :157, :192, :227 — settings_units_* in strings.xml, in this order. */
const UNIT_ROWS: UnitRow[] = [
  new UnitRow(UnitFamily.TEMPERATURE, 'Temperature unit'),
  new UnitRow(UnitFamily.PRECIPITATION, 'Precipitation unit'),
  new UnitRow(UnitFamily.SPEED, 'Speed unit'),
  new UnitRow(UnitFamily.DISTANCE, 'Distance unit'),
  new UnitRow(UnitFamily.PRESSURE, 'Pressure unit')
];

@Entry
@ComponentV2
struct UnitSettings {
  private insets: SystemInsets = SystemInsets.instance;
  /** Read directly in the build so a write re-labels the row that made it. */
  private settings: AppSettings = AppSettings.instance;

  @Local private dark: boolean = false;
  /** The family whose dialog is open, or null for none. */
  @Local private openFamily: string = '';
  /**
   * Bumped after a write, and READ in `summaryFor` — which is the only thing that re-labels the row.
   *
   * The stored ids live on `AppSettings.instance`, an @ObservedV2 whose fields are @Trace, but a
   * @Trace read inside a helper does not register a dependency (the trap this port documents
   * throughout). `summaryFor` is exactly such a helper, so without this the row went on showing
   * "Regional preference (degrees Celsius)" after Fahrenheit had been chosen and written. A @Local
   * read in a helper DOES register — it is the component's own state — so this one line is what
   * makes the summary follow the choice.
   */
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

  /* ------------------------------------------------------------------ the option lists -------- */

  /**
   * "Regional preference (…)" — R.string.parenthesis applied to settings_regional_preference and
   * the resolved unit's long name (kt:72-81).
   *
   * Precipitation is the one that can name TWO units: the Kotlin shows "<rain>/<snow>" when the
   * default precipitation unit and the default SNOWFALL unit differ (kt:114-130), which on a metric
   * device is "millimeters/centimeters".
   */
  private regionalName(family: UnitFamily): string {
    const resolved: UnitDef | null = unitById(family, regionalDefaultId(family));
    const name: string = resolved === null ? '' : resolved.longName;
    if (family === UnitFamily.PRECIPITATION) {
      const snow: UnitDef | null = unitById(family, regionalDefaultSnowfallId());
      if (snow !== null && snow.id !== regionalDefaultId(family)) {
        return 'Regional preference (' + name + '/' + snow.longName + ')';
      }
    }
    return 'Regional preference (' + name + ')';
  }

  /** `arrayOf("auto") + <Unit>.entries` — the regional row first, then the units. */
  private optionsFor(family: UnitFamily): ListPreferenceOption[] {
    const options: ListPreferenceOption[] = [
      new ListPreferenceOption(UNIT_AUTO, this.regionalName(family))
    ];
    const units: UnitDef[] = unitsFor(family);
    for (let i = 0; i < units.length; i++) {
      options.push(new ListPreferenceOption(units[i].id, units[i].longName));
    }
    return options;
  }

  /**
   * kt:84-86 — the summary is the selected entry's name, and an id that is not in the list falls
   * back to the FIRST entry, i.e. the regional one. That fallback is what makes a stored unit the
   * Kotlin later removed degrade gracefully instead of rendering blank.
   */
  private summaryFor(family: UnitFamily): string {
    // Read for the subscription, not the value — see `revision`.
    const revision: number = this.revision;
    if (revision < 0) {
      return '';
    }
    const stored: string = unitSetting(family);
    const options: ListPreferenceOption[] = this.optionsFor(family);
    for (let i = 0; i < options.length; i++) {
      if (options[i].value === stored) {
        return options[i].name;
      }
    }
    return options[0].name;
  }

  @Builder
  separator() {
    Column()
      .width('100%')
      .height(Dimens.SETTINGS_SMALL_SEPARATOR)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ---- LargeTopAppBar, as the root settings and Appearance screens use ----
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

          // kt:61 — AboutActivityIconButton, the same action the other settings screens carry.
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

        Text('Units') // strings.xml `settings_units`
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(HEADLINE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .maxLines(1)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN, top: Dimens.LARGE_TITLE_TOP_PADDING })
          .height(APP_BAR_EXPANDED_HEIGHT - APP_BAR_HEIGHT)

        Scroll() {
          Column() {
            ForEach(UNIT_ROWS, (row: UnitRow, index: number) => {
              PreferenceRow({
                title: row.title,
                summary: this.summaryFor(row.family),
                icon: null,
                dark: this.dark,
                isFirst: index === 0,
                isLast: index === UNIT_ROWS.length - 1,
                onTap: () => {
                  this.openFamily = row.family;
                }
              })
              if (index < UNIT_ROWS.length - 1) {
                this.separator()
              }
            }, (row: UnitRow) => row.family)
          }
          .width('100%')
          .padding({
            left: Dimens.NORMAL_MARGIN,
            right: Dimens.NORMAL_MARGIN,
            bottom: Dimens.LARGE_MARGIN
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
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

      if (this.openFamily.length > 0) {
        ListPreferenceDialog({
          title: this.openDialogTitle(),
          options: this.optionsFor(this.openFamily as UnitFamily),
          selected: unitSetting(this.openFamily as UnitFamily),
          dark: this.dark,
          onChosen: (value: string) => {
            const family: UnitFamily = this.openFamily as UnitFamily;
            this.openFamily = '';
            // Choosing IS the commit (ListPreference.kt:241-313 has no confirm button), and the
            // write is what every other screen re-reads to re-render in the new unit.
            setUnitSetting(family, value).then(() => {
              this.revision++;
            });
          },
          onDismiss: () => {
            this.openFamily = '';
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  private openDialogTitle(): string {
    for (let i = 0; i < UNIT_ROWS.length; i++) {
      if (UNIT_ROWS[i].family === this.openFamily) {
        return UNIT_ROWS[i].title;
      }
    }
    return '';
  }
}
