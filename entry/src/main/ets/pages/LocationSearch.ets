/*
 * Screen 2b — add a location by searching for it. Port of SearchActivity.kt's ContentView (:114-359).
 *
 * Android's is a Material3Scaffold whose bottom bar carries the attribution line and a Tune FAB,
 * over a Surface holding [search input | divider | progress | results]. What is deliberately NOT
 * here, and why:
 *
 *   the freenet disclaimer card     inside `if (BuildConfig.FLAVOR == "freenet")` (:269); the
 *                                   reference build is the `basic` flavour
 *   the "Learn more" link dialog    only reachable from that card (:300-310)
 *   SecondarySourcesPreference      (:212-223) the per-feature source picker shown after a hit is
 *                                   chosen. Every feature has exactly one candidate in an
 *                                   Open-Meteo-only build, so the dialog would have nothing to
 *                                   choose; picking a result does what its `onClose(location)`
 *                                   does — adds the location and finishes.
 *
 * The source chooser IS ported in full, all five sources, because CLAUDE.md scopes down the source
 * *clients* and not the source *metadata*: see data/SourceCatalogue.ets.
 */

import { promptAction, router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../theme/Dimens';
import { AppColors, searchSurface } from '../theme/AppColors';
import { APP_FONT_FAMILY } from '../common/Typography';
import { LocationModel } from '../model/Weather';
import { AddLocationResult, getMainViewModel, MainViewModel } from '../viewmodel/MainViewModel';
import { goPlaceholder } from '../common/Navigator';
import { SearchResultModel } from '../view/location/SearchResultModel';
import { OpenMeteoLocationResult } from '../data/openmeteo/OpenMeteoJson';
import { fetchLocationSearch, LocationSearchError } from '../data/openmeteo/OpenMeteoApi';
import {
  DEFAULT_LOCATION_SEARCH_SOURCE,
  LOCATION_SEARCH_SOURCES,
  locationSearchSourceOrDefault,
  SourceInfo
} from '../data/SourceCatalogue';
import { SystemInsets } from '../common/SystemBars';
import { LocationSources, WeatherSourcesDialog } from '../view/location/WeatherSourcesDialog';

/** SearchBarDefaults.InputFieldHeight — the Material3 search bar's fixed 56 dp field. */
const INPUT_FIELD_HEIGHT: number = 56;
/** Material3SearchBarInputField's textStyle: titleMedium at an explicit 18 sp (Widgets.kt:149-153). */
const INPUT_TEXT_SIZE: number = 18;
/**
 * The gap between the leading magnifier's 24 dp box and the input's text, MEASURED on the
 * reference: box at 16 dp (52 px), text node at 169 px, so 39 px = 12 dp. See the comment at the
 * icon for why this is measured rather than derived. NativeApp uses the same number.
 */
const SEARCH_ICON_TEXT_GAP: number = 12;
/** Material3 BottomAppBar's `BottomAppBarHorizontalPadding`, applied to its `actions` slot. */
const BOTTOM_BAR_ACTION_PADDING: number = 4;
/** Material3 FAB: 56 dp with a 24 dp icon. */
const FAB_SIZE: number = 56;
/** BottomAppBar's height. */
const BOTTOM_BAR_HEIGHT: number = 80;
/** `LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp))` — SearchActivity.kt:198. */
const RESULT_SPACING: number = 4;
/** LinearProgressIndicator's track height. */
const PROGRESS_HEIGHT: number = 4;
/** Material3's two-line ListItem token — a fixed height, not a content hug. */
const LIST_ITEM_TWO_LINE_HEIGHT: number = 72;
/** ListItemDefaults' vertical padding; with the minimum above it also gives the 88 dp three-line. */
const LIST_ITEM_VERTICAL_PADDING: number = 12;
/** bodyLarge — 16 sp on a 24 sp line. */
const HEADLINE_LINE_HEIGHT: number = 24;
/** bodyMedium — 14 sp on a 20 sp line. */
const SUPPORTING_LINE_HEIGHT: number = 20;

/** `listResource`'s second element — LoadableLocationStatus. */
enum SearchStatus {
  SUCCESS,
  LOADING,
  ERROR
}

@Entry
@ComponentV2
struct LocationSearch {
  private viewModel: MainViewModel = getMainViewModel();
  private insets: SystemInsets = SystemInsets.instance;

  @Local private dark: boolean = false;
  /** `var text by rememberSaveable` (:122) — the live contents of the field. */
  @Local private query: string = '';
  /** `latestTextSearch` (:123) — the term the visible results belong to, for the empty message. */
  @Local private latestTextSearch: string = '';
  @Local private results: SearchResultModel[] = [];
  @Local private status: SearchStatus = SearchStatus.SUCCESS;
  /** `isLoading` (:121) — set while a chosen hit is being turned into a saved location. */
  @Local private isLoading: boolean = false;
  @Local private sourceId: string = DEFAULT_LOCATION_SEARCH_SOURCE;
  @Local private sourceDialogOpen: boolean = false;
  /**
   * Whether the weather-sources dialog is up (SearchActivity.kt:212-223).
   *
   * A boolean plus two PLAIN fields, not a `@Local LocationModel` — see the note on LocationList's
   * `sourcesOpen`: a LocationModel in V2 state pulls its whole weather graph into the binding
   * registry, which is what froze the app.
   */
  @Local private sourcesOpen: boolean = false;
  private sourcesTarget: LocationSources = new LocationSources();
  private pendingLocation: LocationModel | null = null;
  /**
   * Guards against an out-of-order reply: a slow first search must not overwrite the results of a
   * later one. `mRepository.cancel()` (SearchViewModel.kt:60) is how the Kotlin does it, by
   * disposing the in-flight RxJava subscription; @ohos.net.http has no cancel, so the reply is
   * matched against the request that is current when it lands.
   */
  private requestSeq: number = 0;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.dark = context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private source(): SourceInfo {
    return locationSearchSourceOrDefault(this.sourceId);
  }

  /* ------------------------------------------------------------------------ the search --------- */

  /**
   * requestLocationList (SearchViewModel.kt:59-99).
   *
   * `str.trim()` is the Kotlin's (:63); an all-whitespace query reaches the API as empty and is
   * refused, so it is dropped here as `onSearch` already drops an empty one (:176).
   */
  private runSearch(raw: string): void {
    const query: string = raw.trim();
    if (query.length === 0) {
      return;
    }
    this.latestTextSearch = query;
    this.status = SearchStatus.LOADING;
    this.results = [];

    this.requestSeq++;
    const seq: number = this.requestSeq;
    // `context.currentLocale.code` (OpenMeteoService.kt:641). English only, per CLAUDE.md.
    fetchLocationSearch(query, 'en')
      .then((hits: OpenMeteoLocationResult[]) => {
        if (seq !== this.requestSeq) {
          return;
        }
        const models: SearchResultModel[] = [];
        for (let i = 0; i < hits.length; i++) {
          models.push(new SearchResultModel(hits[i]));
        }
        this.results = models;
        this.status = SearchStatus.SUCCESS;
      })
      .catch((error: Error) => {
        if (seq !== this.requestSeq) {
          return;
        }
        this.results = [];
        this.status = SearchStatus.ERROR;
        // SnackbarHelper (SearchViewModel.kt:66-76). A LocationSearchError is the source saying it
        // failed; anything else is the transport. Both surface, neither is swallowed.
        this.toast(error instanceof LocationSearchError
          ? 'Location search failed'
          : 'Could not reach Open-Meteo');
      });
  }

  /**
   * setSelectedLocation (SearchViewModel.kt:106-117) followed by the dialog's `onClose(location)`
   * (SearchActivity.kt:216-221), which is what actually finishes the activity with a result.
   *
   * ManagementFragment then calls addLocation on what comes back; here the screen does it directly
   * against the shared view model and the list refreshes in its own `onPageShow`. Routing the
   * location back through `router.back({ params })` was the alternative and buys nothing — both
   * screens already share one view model, and screen 1 established that a page behind a pushed
   * route does not run its watchers.
   */
  private onResultPicked(result: SearchResultModel): void {
    if (this.isLoading) {
      return;
    }
    /*
     * SearchActivity.kt:212-223 — picking a hit opens SecondarySourcesPreference, and only its
     * `onClose(location)` finishes the activity with a result. The port used to add straight away,
     * which was the honest shortcut while that dialog did not exist.
     */
    const picked: LocationModel = result.toLocation();
    this.pendingLocation = picked;
    this.sourcesTarget = LocationSources.from(picked);
    this.sourcesOpen = true;
  }

  /** `onClose` from the weather-sources dialog — null is a cancel, anything else is the add. */
  private onSourcesClosed(sources: LocationSources | null): void {
    const picked: LocationModel | null = this.pendingLocation;
    this.sourcesOpen = false;
    this.pendingLocation = null;
    if (sources === null || picked === null) {
      return;
    }
    sources.applyTo(picked);
    this.isLoading = true;
    this.viewModel.addLocation(picked)
      .then((added: AddLocationResult) => {
        this.isLoading = false;
        if (!added.added) {
          /*
           * ManagementFragment.kt:471-476 — a location the list already holds is REFUSED, with
           * `location_message_already_exists`, and the screen stays open so another hit can be
           * picked. The port used to treat it as a success and pop back, which looked exactly like
           * adding a second copy had worked.
           */
          this.toast('Location list already contains this location with this forecast source.');
          return;
        }
        this.toast('Location added'); // strings.xml `location_message_added` (kt:475)
        router.back();
      })
      .catch((error: Error) => {
        this.isLoading = false;
        console.error('Could not add location: ' + error.message);
        this.toast('Could not add location');
      });
  }

  /**
   * The radio rows (SearchActivity.kt:318-336).
   *
   * Android would switch the source and re-run the query. This port has a client for Open-Meteo
   * only, so per CLAUDE.md's source scope a different pick is answered with the "not yet ported"
   * placeholder and the active source is left alone — switching to a source that cannot answer
   * would leave the screen unable to search at all.
   */
  private onSourcePicked(source: SourceInfo): void {
    this.sourceDialogOpen = false;
    if (!source.implemented) {
      goPlaceholder(source.name + ' location search');
      return;
    }
    this.sourceId = source.id;
    if (this.query.length > 0) {
      this.runSearch(this.query);
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  /* ------------------------------------------------------------------------------ build -------- */

  build() {
    /*
     * The dialog is a SIBLING of the content, not a child of it.
     *
     * Nesting it inside the padded Column made its scrim start below the status bar, because a
     * `position({x: 0, y: 0})` resolves against the parent's padded content box rather than the
     * window. A real dialog dims everything.
     */
    Stack() {
      this.content()
      if (this.sourceDialogOpen) {
        this.sourceDialog()
      }
      if (this.sourcesOpen) {
        WeatherSourcesDialog({
          target: this.sourcesTarget,
          dark: this.dark,
          onClose: (sources: LocationSources | null) => {
            this.onSourcesClosed(sources);
          },
          locationExists: (latitude: number, longitude: number, forecastSource: string) =>
          this.viewModel.locationExistsAt(latitude, longitude, forecastSource)
        })
      }
    }
    .width('100%')
    .height('100%')
    // `Surface(color = SearchBarDefaults.colors().containerColor)` (:163-168) — the whole screen,
    // input field and results alike, sits on one tinted surface rather than the plain background.
    .backgroundColor(searchSurface(this.dark))
  }

  @Builder
  content() {
    Column() {
      // ---- the search input (:173-189) ----
      Row() {
        /*
         * `leadingIcon = Icon(Icons.Default.Search)` (:188), inside the decoration box that
         * offsets it 4 dp (Widgets.kt:167-171).
         *
         * MEASURED on the reference rather than assembled from the Compose constants, because the
         * 4 dp offset is applied to a slot whose own width and padding are Material3 internals
         * this tree does not contain. Pixel-scanning both captures over the same row band:
         *
         *     magnifier's leftmost dark pixel   Android 61   this port 74   (+4 dp)
         *     hint text's leftmost dark pixel   Android 171  this port 197  (+8 dp)
         *
         * The glyph sits 9 px inside its 24 dp box, so the reference's box starts at 52 = 16 dp
         * exactly, and its text node at 169 = 12 dp after the box ends. The `+ 4` here was the
         * Kotlin's offset added on top of a 16 dp base that already accounted for it.
         */
        Image($r('app.media.ic_search'))
          .width(Dimens.MATERIAL_ICON_SIZE)
          .height(Dimens.MATERIAL_ICON_SIZE)
          .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
          .margin({ left: Dimens.NORMAL_MARGIN, right: SEARCH_ICON_TEXT_GAP })

        TextInput({ text: this.query, placeholder: 'Search for a location…' })
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(INPUT_TEXT_SIZE)
          // `fontWeight = FontWeight.Normal` is set explicitly (Widgets.kt:151) because
          // titleMedium's own weight is Medium.
          .fontWeight(FontWeight.Normal)
          .fontColor(AppColors.ON_BACKGROUND.resolve(this.dark))
          .placeholderFont({ size: INPUT_TEXT_SIZE, weight: FontWeight.Normal, family: APP_FONT_FAMILY })
          .placeholderColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .caretColor(AppColors.ON_BACKGROUND.resolve(this.dark))
          // `keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search)` (Widgets.kt:155)
          .enterKeyType(EnterKeyType.Search)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding(0)
          .layoutWeight(1)
          .height(INPUT_FIELD_HEIGHT)
          .defaultFocus(true)
          .onChange((value: string) => {
            this.query = value;
          })
          .onSubmit(() => {
            // `onSearch` (:175-181): an empty query does nothing at all — no search, and
            // `latestTextSearch` is left as it was so the empty-state message does not change.
            if (this.query.length > 0) {
              this.runSearch(this.query);
            }
          })
      }
      .width('100%')
      .height(INPUT_FIELD_HEIGHT)
      .alignItems(VerticalAlign.Center)

      // `HorizontalDivider(color = SearchBarDefaults.colors().dividerColor)` (:190)
      Divider()
        .color(AppColors.SEARCH_DIVIDER.resolve(this.dark))
        .strokeWidth(1)

      // ---- progress (:192-194) ----
      // Shown while the list is loading OR while a picked result is being saved — the Kotlin ORs
      // the two flags, so one bar covers both.
      if (this.status === SearchStatus.LOADING || this.isLoading) {
        Progress({ value: 0, total: 100, type: ProgressType.Linear })
          .color(AppColors.PRIMARY.resolve(this.dark))
          .backgroundColor(AppColors.SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          .height(PROGRESS_HEIGHT)
          .style({ enableSmoothEffect: true })
      }

      // ---- results, or the empty state (:195-250) ----
      if (this.results.length > 0) {
        List({ space: RESULT_SPACING }) {
          ForEach(this.results, (result: SearchResultModel) => {
            ListItem() {
              this.resultRow(result)
            }
          }, (result: SearchResultModel, index: number) =>
            // Two hits can share a name AND a full admin path (different postcodes inside one
            // commune), so the index is what makes the key unique.
          index.toString() + ':' + result.getPlace())
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      } else {
        Column() {
          // The advice block appears only after a SUCCESSFUL search that found nothing (:230-232).
          // After an error the snackbar has already said so, and this stays empty.
          if (this.latestTextSearch.length > 0 && this.status === SearchStatus.SUCCESS) {
            // strings.xml `location_search_no_results` — "%1$s can’t find %2$s"
            Text(this.source().name + ' can’t find ' + this.latestTextSearch)
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.TITLE_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
              .width('100%')
              .textAlign(TextAlign.Start)

            // `Spacer(height = small_margin)` (:242)
            Text('Make sure your search is spelled correctly and not too specific. Alternatively, ' +
              'you can try another location search source which may produce different results.')
              .fontFamily(APP_FONT_FAMILY)
              .fontSize(Dimens.CONTENT_TEXT_SIZE)
              .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
              .width('100%')
              .textAlign(TextAlign.Start)
              .margin({ top: Dimens.SMALL_MARGIN })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding(Dimens.NORMAL_MARGIN)
      }

      // ---- the bottom app bar (:129-160) ----
      Row() {
        // strings.xml `location_results_by` — "Location results by %s", the attribution of the
        // ACTIVE source (:141-144).
        Text('Location results by ' + this.source().searchAttribution)
          .fontFamily(APP_FONT_FAMILY)
          // `MaterialTheme.typography.bodySmall` (:145)
          .fontSize(Dimens.SUBTITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          /*
           * 16 dp from the Box (:136) PLUS Material3's own `BottomAppBarHorizontalPadding` of
           * 4 dp on the actions row — the reference measures this text node at x=65, i.e. 20 dp,
           * where both ports had 52. The FAB is unaffected: it is the bar's
           * `floatingActionButton` slot, not an action, and both ports already place it at
           * 1026..1208 like the reference.
           */
          .margin({ left: Dimens.NORMAL_MARGIN + BOTTOM_BAR_ACTION_PADDING,
            right: Dimens.NORMAL_MARGIN })

        // The Tune FAB (:151-159). Unlike the location list's gold FABs this one takes
        // `FloatingActionButtonDefaults.containerColor`, the Material default, which is
        // primaryContainer — not the tertiary the list screen asks for explicitly.
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_tune'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_PRIMARY_CONTAINER.resolve(this.dark))
        }
        .width(FAB_SIZE)
        .height(FAB_SIZE)
        .borderRadius(Dimens.NORMAL_MARGIN)
        .backgroundColor(AppColors.PRIMARY_CONTAINER.resolve(this.dark))
        .margin({ right: Dimens.NORMAL_MARGIN })
        .onClick(() => {
          // openDialogLocationSearchSource (:153)
          this.sourceDialogOpen = true;
        })
      }
      .width('100%')
      .height(BOTTOM_BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    // The side insets matter only in landscape, and they are what keeps the results and the
    // attribution line clear of the cutout — `safeDrawing.only(Horizontal + Bottom)` (:130-132).
    .padding({
      top: this.insets.top,
      bottom: this.insets.bottom,
      left: this.insets.left,
      right: this.insets.right
    })
  }

  /** One result — `ListItem(headlineContent, supportingContent)` (:201-209). */
  @Builder
  resultRow(result: SearchResultModel) {
    Column() {
      Text(result.getPlace())
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        // bodyLarge's line height, so a row measures the same as the reference's.
        .lineHeight(HEADLINE_LINE_HEIGHT)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(result.administrationLevels())
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.CONTENT_TEXT_SIZE)
        // bodyMedium's line height, which is what decides where the wrap threshold falls.
        .lineHeight(SUPPORTING_LINE_HEIGHT)
        .fontColor(AppColors.ON_SURFACE_VARIANT.resolve(this.dark))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    /*
     * A Material3 ListItem's height is a FIXED TOKEN, not the sum of its content — the same thing
     * the alert card was wrong about. Measured on the reference, the result rows sit on a perfect
     * 72 dp / 88 dp grid with 4 dp between them:
     *
     *     row 1 top 315.5  two-line  234 px   title at 361   (measured 361)
     *     row 2 top 562.5  three-line 286 px  title at 601.5 (measured 601)
     *     row 3 top 861.5  two-line  234 px   title at 907   (measured 907)
     *     ... and every row after it, to 2389
     *
     * A 12 dp vertical padding with a 72 dp minimum reproduces both: one supporting line gives
     * 24+20+24 = 68 dp, which the minimum lifts to 72; a wrapped one gives 24+40+24 = 88 exactly.
     * The port used to hug its content with 8 dp padding, so every row was 179 px against 247 and
     * the whole list was ~27 % short.
     */
    .constraintSize({ minHeight: LIST_ITEM_TWO_LINE_HEIGHT })
    .padding({
      left: Dimens.NORMAL_MARGIN,
      right: Dimens.NORMAL_MARGIN,
      top: LIST_ITEM_VERTICAL_PADDING,
      bottom: LIST_ITEM_VERTICAL_PADDING
    })
    // `colors = ListItemDefaults.colors(containerColor = SearchBarDefaults.colors().containerColor)`
    // (:202-203) — the rows are the same surface as the screen, not cards on top of it.
    .backgroundColor(searchSurface(this.dark))
    .onClick(() => {
      this.onResultPicked(result);
    })
  }

  /**
   * AlertDialogNoPadding with a radio list (:255-351).
   *
   * Built as a Stack rather than a CustomDialog so the whole screen stays one struct; the scrim and
   * the dismiss-on-tap-outside are what the dialog contributes behaviourally, and both are here.
   */
  @Builder
  sourceDialog() {
    Stack() {
      // Tapping the scrim is `onDismissRequest` (:257).
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#52000000')
        .onClick(() => {
          this.sourceDialogOpen = false;
        })

      Column() {
        // strings.xml `location_search_source`, `MaterialTheme.typography.headlineSmall` (:258-263)
        Text('Location search source')
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(24)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: Dimens.NORMAL_MARGIN })

        /*
         * The radio list SCROLLS — it is a LazyColumn upstream (:266-337), and it has to be. In
         * landscape the Android dialog shows four of the five sources with China below the fold;
         * a plain Column here would push CANCEL off the bottom of the screen instead.
         */
        List() {
          ForEach(LOCATION_SEARCH_SOURCES, (source: SourceInfo) => {
            ListItem() {
              this.sourceRow(source)
            }
          }, (source: SourceInfo) => source.id)
        }
        .width('100%')
        // Tall enough for the whole list in portrait, capped so landscape scrolls rather than
        // overflowing. The dialog is 80% of the screen; this leaves room for title and button.
        .constraintSize({ maxHeight: '60%' })
        .scrollBar(BarState.Off)

        // The confirm button is a Cancel — it only closes (:339-349).
        Row() {
          Text('CANCEL')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(Dimens.CONTENT_TEXT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .padding(Dimens.SMALL_MARGIN)
            .onClick(() => {
              this.sourceDialogOpen = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Dimens.SMALL_MARGIN })
      }
      .width('80%')
      .padding(Dimens.LARGE_MARGIN + 4)
      .backgroundColor(searchSurface(this.dark))
      .borderRadius(Dimens.CARD_CORNER_RADIUS)
      // Never taller than the window, whatever the orientation — the list inside takes the squeeze.
      .constraintSize({ maxHeight: '90%' })
    }
    .width('100%')
    .height('100%')
  }

  /** One radio row — `RadioButton(selected, enabled, onClick, text)` (:322-335). */
  @Builder
  sourceRow(source: SourceInfo) {
    Row() {
      Radio({ value: source.id, group: 'locationSearchSource' })
        .checked(source.id === this.sourceId)
        .radioStyle({
          checkedBackgroundColor: AppColors.PRIMARY.resolve(this.dark),
          uncheckedBorderColor: AppColors.ON_SURFACE_VARIANT.resolve(this.dark)
        })
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .onClick(() => {
          this.onSourcePicked(source);
        })

      Text(source.name)
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.TITLE_TEXT_SIZE)
        .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .margin({ left: Dimens.NORMAL_MARGIN })
    }
    .width('100%')
    .height(Dimens.LIST_ITEM_ONE_LINE_HEIGHT)
    .alignItems(VerticalAlign.Center)
    // The whole row is the target, as RadioButton's own Row carries the click (:322).
    .onClick(() => {
      this.onSourcePicked(source);
    })
  }
}
