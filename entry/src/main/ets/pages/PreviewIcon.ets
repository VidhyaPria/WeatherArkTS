/*
 * The icon preview screen — PreviewIconActivity.kt:44-160.
 *
 * A 4-column grid of every icon the resource provider can produce, in seven sections
 * (kt:62-109). Titles and rules span all four columns (`SpanSizeLookup`, WeatherIconAdapter.kt:126-137);
 * icon cells are square with the image inset by `large_margin` on every side
 * (item_weather_icon.xml). Section titles are bold `content_text_size` in `colorTitleText` with a
 * `normal_margin` all round (item_weather_icon_title.xml); the rules are 1 dp of `?attr/colorOutline`
 * (item_line.xml).
 *
 * The toolbar is a plain MaterialToolbar, not the LargeTopAppBar the settings screens use: 64 vp
 * tall, `getWidgetSurfaceColor(6f, colorPrimary, colorSurface)` behind it (kt:133-139), the provider
 * name as its title, and one `action_about` action that opens the provider's system app page
 * (kt:119-132).
 *
 * SCOPE: `ResourcesProviderFactory.getNewInstance(packageName)` picks an external icon pack when one
 * is installed. CLAUDE.md scopes external icon packs out entirely, so this screen always previews
 * the DEFAULT provider — which is the one whose artwork both ports actually bundle, and the one
 * Android shows when no pack is installed. Nothing on the screen is stubbed: every cell below is a
 * real asset or a real procedural drawable.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';
import { WeatherKind } from '../model/WeatherKind';
import { getMinimalIcon, getShortcutIcon, getWeatherIcon } from '../common/WeatherIcons';
import { SunMoonCanvas } from '../view/common/SunMoonCanvas';
import {
  AdaptiveIconDialog,
  ADAPTIVE_MASK_COUNT,
  AnimatableIconDialog,
  MinimalIconDialog
} from '../view/settings/IconPreviewDialogs';

/** ?attr/actionBarSize (dimens.xml:36). */
const TOOLBAR_HEIGHT: number = 64;
/** textAppearanceHeadline6. */
const TOOLBAR_TITLE_TEXT_SIZE: number = 20;
const COLUMN_COUNT: number = 4;
const LINE_HEIGHT: number = 1;

/** `WeatherCode.entries`, in declaration order (WeatherCode.kt:21-32). */
const WEATHER_CODES: WeatherKind[] = [
  WeatherKind.CLEAR,
  WeatherKind.CLOUD,
  WeatherKind.CLOUDY,
  WeatherKind.RAINY,
  WeatherKind.SNOW,
  WeatherKind.WIND,
  WeatherKind.FOG,
  WeatherKind.HAZE,
  WeatherKind.SLEET,
  WeatherKind.HAIL,
  WeatherKind.THUNDER,
  WeatherKind.THUNDERSTORM
];

/** Which family of artwork a section draws. */
enum IconSet {
  FULL = 0,
  MINIMAL = 1,
  SHORTCUT = 2,
  EPHEMERIS = 3
}

class PreviewSection {
  readonly title: string;
  readonly set: IconSet;
  readonly daytime: boolean;

  constructor(title: string, set: IconSet, daytime: boolean) {
    this.title = title;
    this.set = set;
    this.daytime = daytime;
  }
}

/** kt:69-108 — the seven sections, in order. */
const SECTIONS: PreviewSection[] = [
  new PreviewSection('Daytime', IconSet.FULL, true), // strings.xml `daytime`
  new PreviewSection('Nighttime', IconSet.FULL, false), // strings.xml `nighttime`
  new PreviewSection('Minimal Daytime', IconSet.MINIMAL, true),
  new PreviewSection('Minimal Nighttime', IconSet.MINIMAL, false),
  new PreviewSection('Shortcuts Daytime', IconSet.SHORTCUT, true),
  new PreviewSection('Shortcuts Nighttime', IconSet.SHORTCUT, false),
  new PreviewSection('Sun & moon', IconSet.EPHEMERIS, true) // strings.xml `ephemeris`
];

@Entry
@ComponentV2
struct PreviewIcon {
  private insets: SystemInsets = SystemInsets.instance;
  @Local private dark: boolean = false;
  @Local private cellSize: number = 0;

  /*
   * The open dialog, if any. `IconSet` doubles as the discriminator because the section a cell
   * belongs to is exactly what decides which dialog opens (kt:180-211).
   */
  @Local private dialogSet: IconSet | null = null;
  @Local private dialogKind: WeatherKind = WeatherKind.NULL;
  @Local private dialogDaytime: boolean = true;
  /** Rolled once when the adaptive dialog opens — kt:48 does the same and must not re-roll. */
  @Local private dialogMask: number = 0;

  private openDialog(section: PreviewSection, kind: WeatherKind): void {
    // SunIcon.onItemClicked is "// do nothing." (kt:222), so the ephemeris row has no dialog.
    if (section.set === IconSet.EPHEMERIS) {
      return;
    }
    this.dialogKind = kind;
    this.dialogDaytime = section.daytime;
    if (section.set === IconSet.SHORTCUT) {
      this.dialogMask = Math.floor(Math.random() * ADAPTIVE_MASK_COUNT);
    }
    this.dialogSet = section.set;
  }

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

  /**
   * kt:121-129 — `action_about` opens the system app-details page of the provider. For the default
   * provider that is this app itself, which is `startApplicationDetailsActivity(activity)`.
   */
  private openAppDetails(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: { pushParams: 'com.example.arkuiapp' }
    };
    context.startAbility(want).catch((error: Error) => {
      console.error('App details unavailable: ' + error.message);
    });
  }

  private iconFor(section: PreviewSection, kind: WeatherKind): Resource | null {
    switch (section.set) {
      case IconSet.FULL:
        return getWeatherIcon(kind, section.daytime);
      case IconSet.MINIMAL:
        return getMinimalIcon(kind, section.daytime, this.dark);
      case IconSet.SHORTCUT:
        return getShortcutIcon(kind, section.daytime);
      default:
        return null;
    }
  }

  build() {
    // The dialogs are Stack overlays over the whole page, the pattern the other ported dialogs
    // already use here (see ListPreferenceDialog): a real dialog dims the screen behind it.
    Stack() {
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
        // kt:116 — the toolbar title is the provider's name.
        Text('Breezy Weather') // res_breezy/values/strings.xml `brand_name`
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(TOOLBAR_TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .maxLines(1)
          .layoutWeight(1)
          .margin({ left: Dimens.NORMAL_MARGIN })
        Image($r('app.media.ic_info'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
          .margin({ right: Dimens.NORMAL_MARGIN })
          .onClick(() => {
            this.openAppDetails();
          })
      }
      .width('100%')
      .height(TOOLBAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
      // kt:133-139 — getWidgetSurfaceColor(6f, colorPrimary, colorSurface).
      .backgroundColor(AppColors.ELEVATED_SURFACE_6.resolve(this.dark))

      Scroll() {
        Column() {
          ForEach(SECTIONS, (section: PreviewSection, index: number) => {
            this.sectionTitle(section.title)
            if (section.set === IconSet.EPHEMERIS) {
              this.ephemerisRow()
            } else {
              this.iconGrid(section)
            }
            // kt:73/79/86/92/98/104 — a rule after every section but the last.
            if (index !== SECTIONS.length - 1) {
              this.rule()
            }
          }, (section: PreviewSection, index: number) => index.toString() + ':' + section.title)

          Column().width('100%').height(Dimens.NORMAL_MARGIN + this.insets.bottom)
        }
        .width('100%')
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const width: number = Number(newValue.width);
          if (width > 0) {
            this.cellSize = width / COLUMN_COUNT;
          }
        })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
    .padding({ top: this.insets.top, left: this.insets.left, right: this.insets.right })

      if (this.dialogSet === IconSet.FULL) {
        AnimatableIconDialog({
          kind: this.dialogKind,
          daytime: this.dialogDaytime,
          dark: this.dark,
          onDismiss: () => {
            this.dialogSet = null;
          }
        })
      } else if (this.dialogSet === IconSet.MINIMAL) {
        MinimalIconDialog({
          kind: this.dialogKind,
          daytime: this.dialogDaytime,
          dark: this.dark,
          onDismiss: () => {
            this.dialogSet = null;
          }
        })
      } else if (this.dialogSet === IconSet.SHORTCUT) {
        AdaptiveIconDialog({
          kind: this.dialogKind,
          daytime: this.dialogDaytime,
          dark: this.dark,
          maskIndex: this.dialogMask,
          onDismiss: () => {
            this.dialogSet = null;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontFamily(SETTINGS_FONT_FAMILY)
      .fontSize(Dimens.CONTENT_TEXT_SIZE)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppColors.TITLE_TEXT.resolve(this.dark))
      .width('100%')
      // item_weather_icon_title.xml has a normal_margin on all four sides; as padding on a
      // full-width Text that is the same box, and unlike a margin it cannot be clipped away.
      .padding(Dimens.NORMAL_MARGIN)
  }

  @Builder
  private rule() {
    Column()
      .width('100%')
      .height(LINE_HEIGHT)
      .backgroundColor(AppColors.OUTLINE.resolve(this.dark))
  }

  /** The 12 weather codes, four to a row. */
  @Builder
  private iconGrid(section: PreviewSection) {
    Column() {
      ForEach([0, 1, 2], (row: number) => {
        Row() {
          ForEach([0, 1, 2, 3], (column: number) => {
            this.iconCell(section, WEATHER_CODES[row * COLUMN_COUNT + column])
          }, (column: number) => column.toString())
        }
        .width('100%')
      }, (row: number) => row.toString())
    }
    .width('100%')
  }

  @Builder
  private iconCell(section: PreviewSection, kind: WeatherKind) {
    Column() {
      Image(this.iconFor(section, kind))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
    }
    .width(this.cellSize)
    .height(this.cellSize)
    // item_weather_icon.xml — the image is inset by large_margin inside a SQUARE cell.
    .padding(Dimens.LARGE_MARGIN)
    // WeatherIconAdapter binds onItemClicked to the whole cell; each family opens its own dialog.
    .onClick(() => {
      this.openDialog(section, kind);
    })
  }

  /** kt:106-108 — one sun cell and one moon cell, both procedural drawables. */
  @Builder
  private ephemerisRow() {
    Row() {
      Column() {
        SunMoonCanvas({
          boxSize: Math.max(0, this.cellSize - Dimens.LARGE_MARGIN * 2),
          isSun: true,
          redrawKey: 'sun@' + this.cellSize.toString()
        })
      }
      .width(this.cellSize)
      .height(this.cellSize)
      .padding(Dimens.LARGE_MARGIN)

      Column() {
        SunMoonCanvas({
          boxSize: Math.max(0, this.cellSize - Dimens.LARGE_MARGIN * 2),
          isSun: false,
          redrawKey: 'moon@' + this.cellSize.toString()
        })
      }
      .width(this.cellSize)
      .height(this.cellSize)
      .padding(Dimens.LARGE_MARGIN)
    }
    .width('100%')
  }
}
