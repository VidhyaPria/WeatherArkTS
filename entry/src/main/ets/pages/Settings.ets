/*
 * Screen 3 — the root settings screen. Port of RootSettingsScreen.kt's RootSettingsView (:38-153).
 *
 * Eight rows in five grouped cards, in the Kotlin's order, with the separators it uses:
 *
 *   [ Background updates ]                      largeSeparator
 *   [ Appearance | Main screen ]                largeSeparator
 *   [ Notifications | External modules ]        largeSeparator
 *   [ Location | Weather sources ]              largeSeparator
 *   [ Debug ]
 *
 * A group is one rounded block — see PreferenceRow for how isFirst/isLast shape it, and Dimens for
 * the 2 dp / 16 dp separators that tell rows-within-a-group apart from group-to-group gaps.
 *
 * EVERY row leads somewhere not ported yet, so each goes to the placeholder page carrying its own
 * name, per CLAUDE.md. Two of them are scoped out permanently rather than merely unbuilt — Background
 * updates is background refresh, External modules is widgets and the live wallpaper — and they are
 * still SHOWN, because the settings list is what Android renders; hiding them would be inventing a
 * different screen.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';
import { LocationModel } from '../model/Weather';
import { getMainViewModel, MainViewModel } from '../viewmodel/MainViewModel';
import { goPlaceholder } from '../common/Navigator';
import { PreferenceRow } from '../view/settings/PreferenceRow';
import { SystemInsets } from '../common/SystemBars';
import { AppSettings, appIsDark } from '../data/SettingsStore';

/*
 * LargeTopAppBar's metrics. Material Components library values, NOT app resources — flagged the
 * same way the snackbar's design_snackbar_* dimensions are, because the library is not vendored
 * here and they cannot be extracted from this repository.
 */
/** The icon row: TopAppBarSmallTokens.ContainerHeight. */
const APP_BAR_HEIGHT: number = 64;
/** TopAppBarLargeTokens.ContainerHeight — the whole bar with its title expanded. */
const APP_BAR_EXPANDED_HEIGHT: number = 152;
/** The expanded title is typography.headlineMedium. */
const HEADLINE_TEXT_SIZE: number = 28;

/** One row's worth of content, so the list below reads as the Kotlin does. */
@ObservedV2
class SettingsEntry {
  title: string;
  summary: string;
  icon: Resource;
  isFirst: boolean;
  isLast: boolean;
  /** Ends the group after this row — a largeSeparator in the Kotlin. */
  endsGroup: boolean;

  constructor(title: string, summary: string, icon: Resource, isFirst: boolean, isLast: boolean,
    endsGroup: boolean) {
    this.title = title;
    this.summary = summary;
    this.icon = icon;
    this.isFirst = isFirst;
    this.isLast = isLast;
    this.endsGroup = endsGroup;
  }
}

@Entry
@ComponentV2
struct Settings {
  private viewModel: MainViewModel = getMainViewModel();
  private insets: SystemInsets = SystemInsets.instance;

  /**
   * The SYSTEM colour mode — NOT the selected location's daylight.
   *
   * This is the one screen family that breaks the MODE_NIGHT_AUTO rule screens 1 and 2 follow, and
   * it is deliberate in the Kotlin: `SettingsActivity.onCreate` calls `BreezyWeatherTheme { }` with
   * no argument (:107-111), so it takes the default `darkTheme = isSystemInDarkTheme()`, where
   * MainActivity passes `!ThemeManager.isLightTheme(this, daylight)` (MainActivity.kt:390, :462).
   *
   * Confirmed against the device: with Helsinki in its night the location list is dark and the
   * settings screen behind it is LIGHT (`ref_screen3_settings.png`). This port had it following the
   * location, which made settings dark on the same data.
   */
  @Local private dark: boolean = false;

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
    // `appIsDark()` is the app's effective mode — the dark-mode SETTING applied over the system one,
    // which is what `isSystemInDarkTheme()` answers inside the app once setDefaultNightMode has run.
    this.dark = appIsDark();
  }

  /** RootSettingsScreen.kt:60-148, in order. Strings are strings.xml's, verbatim. */
  private entries(): SettingsEntry[] {
    return [
      new SettingsEntry('Background updates', 'Refresh rate, troubleshoot',
        $r('app.media.ic_sync'), true, true, true),
      new SettingsEntry('Appearance', 'Language, dark mode, icon pack, units',
        $r('app.media.ic_palette'), true, false, false),
      new SettingsEntry('Main screen', 'Blocks order, items displayed, animations',
        $r('app.media.ic_home'), false, true, true),
      new SettingsEntry('Notifications',
        'Notifications of weather alerts, precipitations or forecast for the first location',
        $r('app.media.ic_notifications'), true, false, false),
      new SettingsEntry('External modules',
        'Widgets, notification widget, wallpaper, data sharing with other apps',
        $r('app.media.ic_widgets'), false, true, true),
      new SettingsEntry('Location', 'Location services settings',
        $r('app.media.ic_location'), true, false, false),
      new SettingsEntry('Weather sources',
        'Default weather source for new locations, custom API keys, other source settings',
        $r('app.media.ic_factory'), false, true, true),
      new SettingsEntry('Debug', 'Crash logs',
        $r('app.media.ic_bug_report'), true, true, false)
    ];
  }

  build() {
    Column() {
      /*
       * FitStatusBarTopAppBar is a Material3 LargeTopAppBar (FitSystemBarComposeWrappers.kt:34),
       * driven by exitUntilCollapsedScrollBehavior (Material3Widgets.kt:83-85) — NOT the
       * centre-aligned bar screen 2 uses. The navigation and action icons sit on their own row and
       * the title is a large headline BELOW them, left-aligned at normal_margin.
       *
       * The LargeTopAppBar metrics are Material Components library values, not app resources, and
       * are marked as such: 64 dp collapsed row, 152 dp expanded container, headlineMedium title.
       */
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

        // AboutActivityIconButton (AppBar.kt:32-44) — Icons.Outlined.Info, tinted onSurface.
        Image($r('app.media.ic_info'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
          .margin({ right: Dimens.NORMAL_MARGIN })
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' })
              .catch((error: Error) => {
                console.error('About unavailable: ' + error.message);
              });
          })
      }
      .width('100%')
      .height(APP_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)

      // The expanded title line. strings.xml `action_settings`.
      Text('Settings')
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
          ForEach(this.entries(), (entry: SettingsEntry, index: number) => {
            PreferenceRow({
              title: entry.title,
              summary: entry.summary,
              icon: entry.icon,
              dark: this.dark,
              isFirst: entry.isFirst,
              isLast: entry.isLast,
              onTap: () => {
                // Only External modules is still a placeholder.
                if (entry.title === 'Background updates') {
                  router.pushUrl({ url: 'pages/BackgroundUpdatesSettings' })
                    .catch((error: Error) => {
                      console.error('Background updates unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'Appearance') {
                  router.pushUrl({ url: 'pages/AppearanceSettings' })
                    .catch((error: Error) => {
                      console.error('Appearance unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'Main screen') {
                  router.pushUrl({ url: 'pages/MainScreenSettings' })
                    .catch((error: Error) => {
                      console.error('Main screen settings unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'Notifications') {
                  router.pushUrl({ url: 'pages/NotificationsSettings' })
                    .catch((error: Error) => {
                      console.error('Notifications settings unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'Location') {
                  router.pushUrl({ url: 'pages/LocationSettings' })
                    .catch((error: Error) => {
                      console.error('Location settings unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'Weather sources') {
                  router.pushUrl({ url: 'pages/WeatherSourcesSettings' })
                    .catch((error: Error) => {
                      console.error('Weather sources settings unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'Debug') {
                  router.pushUrl({ url: 'pages/DebugSettings' })
                    .catch((error: Error) => {
                      console.error('Debug settings unavailable: ' + error.message);
                    });
                  return;
                }
                if (entry.title === 'External modules') {
                  router.pushUrl({ url: 'pages/ModulesSettings' })
                    .catch((error: Error) => {
                      console.error('External modules unavailable: ' + error.message);
                    });
                  return;
                }
                goPlaceholder(entry.title);
              }
            })

            // smallSeparatorItem between rows of a group, largeSeparatorItem between groups
            // (RootSettingsScreen.kt:71-137). Nothing after the last row; the scroll padding
            // below stands in for bottomInsetItem().
            if (index < this.entries().length - 1) {
              Column()
                .width('100%')
                .height(entry.endsGroup ? Dimens.SETTINGS_LARGE_SEPARATOR
                                        : Dimens.SETTINGS_SMALL_SEPARATOR)
            }
          }, (entry: SettingsEntry, index: number) => index.toString())
        }
        .width('100%')
        // paddings.plus(PaddingValues(horizontal = normal_margin)) (RootSettingsScreen.kt:58).
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
    // Material3Scaffold's containerColor is `surface` (Material3Widgets.kt:96); the CARDS are the
    // tinted colour, which is what separates them from the page.
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
    .padding({
      top: this.insets.top,
      bottom: this.insets.bottom,
      left: this.insets.left,
      right: this.insets.right
    })
  }
}
