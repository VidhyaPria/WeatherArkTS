/*
 * Screen 2's body — the saved-location list. Port of ManagementFragment.kt's ContentView (:169-300).
 *
 * Android's is a Material3Scaffold with a centre-aligned top app bar, a column of FABs at the
 * bottom end, and a RecyclerView of location cards. What is deliberately NOT here, and why:
 *
 *   the debug-location FAB       gated on `BreezyWeather.instance.debugMode` (:222)
 *   notification permission card an Android runtime-permission prompt with no counterpart
 *   app-update check card        ties to an update channel this port does not have
 *
 * Selecting a row, swiping it either way, dragging it by its handle, and both FABs are all live.
 *
 * WHY THIS IS A COMPONENT AND NOT A PAGE. It is rendered in two places. Below 640 dp it is a pushed
 * page (pages/LocationList.ets); in landscape at 640 dp or more it is the permanently-unfolded left
 * pane of `res/layout-w640dp/activity_main.xml`, rendered by pages/Index.ets beside the weather
 * screen. `paneMode` is the difference, and it changes exactly what DrawerLayout changes: there is
 * no back arrow (ManagementFragment.kt:198-202 passes a null onBackPressed while the drawer is
 * visible), and choosing a row does not navigate anywhere because there is nothing to navigate back
 * from — the weather page is already on screen next to it.
 */

import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Dimens } from '../../theme/Dimens';
import { AppColors } from '../../theme/AppColors';
import { APP_FONT_FAMILY } from '../../common/Typography';
import { LocationModel } from '../../model/Weather';
import { AddLocationResult, getMainViewModel, MainViewModel } from '../../viewmodel/MainViewModel';
import { LocationSources, WeatherSourcesDialog } from './WeatherSourcesDialog';
import { buildCurrentPositionLocation } from '../../data/LocationStore';
import { applyDefaultPreset } from '../../data/SourceCatalogue';
import { goPlaceholder } from '../../common/Navigator';
import { LocationCard } from './LocationCard';
import { Snackbar } from './Snackbar';
import { LocationRowModel } from './LocationRowModel';
import { SystemInsets } from '../../common/SystemBars';
import { ensureLocationPermission } from '../../data/CurrentPosition';
import { AppSettings, isLightTheme } from '../../data/SettingsStore';

/** BWCenterAlignedTopAppBar's height — ?attr/actionBarSize, as on screen 1. */
const APP_BAR_HEIGHT: number = 64;
/** Material3 FAB: 56 dp, 16 dp icon inset, sitting normal_margin from the screen edges. */
const FAB_SIZE: number = 56;
/** LinearProgressIndicator's track height, and the Spacer that stands in for it (kt:289). */
const PROGRESS_HEIGHT: number = 4;
/** ButtonDefaults.MinHeight — the Material3 button's fixed height. */
const BUTTON_HEIGHT: number = 40;
/** ButtonDefaults.ContentPadding — 24 dp at the sides for a text-only button. */
const BUTTON_H_PADDING: number = 24;
/** ButtonDefaults.IconSize / IconSpacing — 18 dp glyph, 8 dp gap before the label. */
const BUTTON_ICON_SIZE: number = 18;
const BUTTON_ICON_SPACING: number = 8;
/** `MaterialTheme.typography.bodyLarge` (kt:400, 421) — 16 sp. */
const BUTTON_TEXT_SIZE: number = 16;

@ComponentV2
export struct LocationListView {
  private viewModel: MainViewModel = getMainViewModel();
  private insets: SystemInsets = SystemInsets.instance;

  /**
   * True when this is the unfolded drawer pane rather than a pushed page. See the header note.
   */
  @Param paneMode: boolean = false;

  /**
   * Bumped by the owner whenever this view has to re-read the model.
   *
   * `onPageShow` is an @Entry lifecycle callback and cannot live in a component, so the two owners
   * supply the signal instead: the page bumps it from its own onPageShow, and Index bumps it when
   * the search screen returns. Without it a city added by the search would not appear.
   */
  @Param refreshTick: number = 0;

  /**
   * Fired after a row is chosen in PANE mode, where there is no navigation to carry the news.
   *
   * The weather page is a sibling, already on screen; it learns of the new selection the same way it
   * learns of one made on the pushed page — see MainScreen's @Monitor('pageShows').
   */
  @Event onSelected: () => void = () => {
  };

  /**
   * True while this list is being scrolled, false when it comes to rest. Pane mode only — see the
   * handlers on the Scroll below.
   */
  @Event onScrollActive: (active: boolean) => void = () => {
  };

  /**
   * The rows, rebuilt by hand after every mutation.
   *
   * The view model's list is a plain array it mutates in place, so nothing about a delete or a
   * reorder is observable. Reading the shared LocationRevision counter was tried first and does not
   * work: `rows()` is a helper method, and a @Trace read inside one does not register as a render
   * dependency of the component that calls it — after a reorder the counter advanced and this
   * screen never rebuilt. Assigning a fresh array to a @Local is observable with no ambiguity.
   */
  @Local private rowModels: LocationRowModel[] = [];

  /**
   * This screen is a plain Material surface, not a weather background — but it is still DARK
   * whenever the SELECTED location is in its night.
   *
   * This used to read the system's colour mode, on the reasoning that the management screen has no
   * location of its own. The reference build says otherwise, and it was checked on the device:
   * with a daytime location selected the list is light, and selecting a night-time one turns the
   * whole screen dark with the system theme untouched (`ref_screen2_light.png` /
   * `ref_screen2_dark.png`). MODE_NIGHT_AUTO REPLACES the system value app-wide rather than
   * combining with it, so every screen under BreezyWeatherTheme follows the current location — the
   * same rule as `MainScreen.isDark()`, and the same one the NDK already applies through
   * `scene.darkMode = !forecast.daylight`.
   *
   * The system mode is still the fallback for the case Android cannot reach: no location at all.
   */
  @Local private dark: boolean = false;

  /**
   * MainActivityViewModel._locationListLoading (kt:98-99), which gates the progress bar at kt:281.
   *
   * On Android it is set around the list WRITES — validating and storing an added location
   * (kt:496-514) and the reverse geocoding that precedes it (kt:532-552). The only one of those
   * this screen starts is the my-location FAB, so the flag lives here rather than on the shared
   * view model; the search screen already runs its own bar for its own add. Keeping it local also
   * sidesteps the trap that a plain field on the view model is invisible to the framework.
   */
  @Local private listLoading: boolean = false;

  aboutToAppear(): void {
    this.refreshRows();
  }

  /** The owner's signal that the model may have changed under this view. */
  @Monitor('refreshTick')
  onRefreshRequested(): void {
    this.refreshRows();
  }

  /**
   * MODE_NIGHT_AUTO, as MainScreen.isDark() applies it: the selected location's daylight flag, with
   * the system's colour mode standing in only when there is no location to ask.
   */
  private syncDark(): void {
    /*
     * ThemeManager.isLightTheme (ThemeManager.kt:68-84), the same rule MainScreen applies.
     *
     * This screen used to derive it itself — the location's daylight, with the system mode standing
     * in when there was no location. That is what the rule reduces to under the defaults, and the
     * `no location` fallback is subsumed too: `daylight == true` is false for a null location, so
     * the rule answers dark exactly as the old fallback did on a dark system.
     */
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSettings.instance.systemDark =
      context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const location: LocationModel | null = this.viewModel.getCurrentLocation();
    this.dark = !isLightTheme(location === null ? null : location.daylight);
  }

  /**
   * Re-reads the view model's list. Must be called after every mutation this screen makes.
   *
   * The model at index i is REUSED and rewritten rather than replaced, so the card bound to that
   * slot keeps its nodes. Only a change in the number of rows adds or drops one. Replacing them
   * wholesale, together with an index in the ForEach key, is what made a drag-drop rebuild a card
   * per moved slot and cost 116 ms — see the note on LocationRowModel.
   *
   * A fresh ARRAY is still assigned: @Local observes the reference, and the elements inside it are
   * the same objects, so the ForEach diff sees stable keys and leaves the nodes alone.
   */
  private refreshRows(): void {
    // Every mutation and every return to this page comes through here, which is also when the
    // selected location — and so the colour mode — can have changed.
    this.syncDark();
    const now = new Date();
    const selectedId: string = this.viewModel.getCurrentLocation()?.formattedId ?? '';
    const locations: LocationModel[] = this.viewModel.getLocations();
    const previous: LocationRowModel[] = this.rowModels;
    const models: LocationRowModel[] = [];
    for (let i = 0; i < locations.length; i++) {
      const selected: boolean = locations[i].formattedId === selectedId;
      if (i < previous.length) {
        previous[i].apply(locations[i], selected, now);
        models.push(previous[i]);
      } else {
        models.push(new LocationRowModel(locations[i], selected, now));
      }
    }
    this.rowModels = models;
  }

  /* ---------------------------------------------------------------- drag to reorder ---------- */

  /** Index of the row under the finger, or -1. */
  @Local private dragIndex: number = -1;
  /** Where that row would land if the finger lifted now — LocationItemTouchCallback's mDragTo. */
  @Local private dropIndex: number = -1;
  /** Live finger travel, so the lifted row follows it exactly. */
  @Local private dragDY: number = 0;
  /** One row plus its spacing; every row is the same height. */
  @Local private rowHeight: number = 0;

  /**
   * onSelectedChanged(ACTION_STATE_DRAG) — the drag begins the moment the handle is touched.
   *
   * Refused outright while a refresh is in flight (LocationItemTouchCallback.kt:60-67). Because the
   * drag never starts, `updateDrag` returns on its own `dragIndex < 0` guard and `offsetFor` keeps
   * every row at 0 — so the row does not follow the finger either, and the toast fires once rather
   * than on every move event. Android's second refusal in `onMove` (kt:77-79) exists because
   * ItemTouchHelper keeps the gesture alive after the first one; nothing here does.
   */
  private beginDrag(index: number): void {
    if (this.refuseWhileRefreshing()) {
      return;
    }
    this.dragIndex = index;
    this.dropIndex = index;
    this.dragDY = 0;
  }

  /**
   * The one refusal all four gestures share — strings.xml `message_please_wait_refresh`.
   * Returns true when the caller must stop.
   */
  private refuseWhileRefreshing(): boolean {
    if (!this.viewModel.isRefreshing()) {
      return false;
    }
    this.toast('Please wait for refresh to complete');
    return true;
  }

  /** onMove — the drop target is recomputed from how many row-heights the finger has travelled. */
  private updateDrag(offsetY: number): void {
    if (this.dragIndex < 0 || this.rowHeight <= 0) {
      return;
    }
    // PanGesture reports travel since the gesture began, so no origin has to be kept here.
    this.dragDY = offsetY;
    const shift: number = Math.round(this.dragDY / this.rowHeight);
    const count: number = this.viewModel.getLocations().length;
    this.dropIndex = Math.max(0, Math.min(count - 1, this.dragIndex + shift));
  }

  /**
   * onSelectedChanged(ACTION_STATE_IDLE) — the reorder is committed once, on release, not on every
   * crossing. `swapLocations` is a MOVE despite its name (`valid.add(to, valid.removeAt(from))`).
   */
  private endDrag(): void {
    const from: number = this.dragIndex;
    const to: number = this.dropIndex;
    this.dragIndex = -1;
    this.dropIndex = -1;
    this.dragDY = 0;
    if (from >= 0 && to >= 0 && from !== to) {
      this.viewModel.moveLocation(from, to);
      // The list is already reordered in memory; only the database write is still in flight.
      this.refreshRows();
    }
  }

  /**
   * Where a row sits while a drag is in progress: the lifted one follows the finger, and the rows
   * between its old and new slots shift by one to open the gap — which is what notifyItemMoved
   * animates on Android.
   */
  private offsetFor(index: number): number {
    if (this.dragIndex < 0 || this.rowHeight <= 0) {
      return 0;
    }
    if (index === this.dragIndex) {
      return this.dragDY;
    }
    if (this.dropIndex > this.dragIndex && index > this.dragIndex && index <= this.dropIndex) {
      return -this.rowHeight;
    }
    if (this.dropIndex < this.dragIndex && index >= this.dropIndex && index < this.dragIndex) {
      return this.rowHeight;
    }
    return 0;
  }

  /* --------------------------------------------------------------------- swipe actions ------- */

  /**
   * ItemTouchHelper.END (kt:100-118) — delete, with an Undo that puts the row back where it was.
   *
   * The refusal at one remaining is the screen's, not the model's: the Kotlin checks the size in
   * the swipe handler so it can show `location_message_list_cannot_be_empty` itself.
   */
  private onDelete(formattedId: string): void {
    const index: number = this.viewModel.indexOf(formattedId);
    if (index < 0) {
      return;
    }
    // Order matters and is the Kotlin's: the "cannot be empty" refusal is checked BEFORE the
    // refresh one (kt:100 vs kt:106), so the last row reports why it survived even mid-refresh.
    if (this.viewModel.getLocations().length <= 1) {
      this.toast('Location list cannot be empty');
      return;
    }
    if (this.refuseWhileRefreshing()) {
      return;
    }
    this.viewModel.deleteLocation(index).then((removed: LocationModel | null) => {
      if (removed === null) {
        return;
      }
      this.refreshRows();
      /*
       * SnackbarHelper.showSnackbar(location_message_deleted, action_undo, ...) — a bar that floats
       * over the list for three seconds and then leaves, NOT a dialog.
       *
       * This was a `promptAction.showDialog`, which is modal and waits indefinitely: it blocked the
       * list, dimmed the screen, and sat there until it was dismissed. Android's blocks nothing and
       * expires on its own, and letting it expire is how a deletion is confirmed.
       */
      this.undoTarget = removed;
      this.undoIndex = index;
      this.undoVisible = true;
    });
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  /* --------------------------------------------------------------- the undo snackbar --------- */

  /**
   * Whether the delete snackbar is up. The location it would restore and the slot it came from are
   * PLAIN fields, for the reason `sourcesTarget` documents: a LocationModel in observable state
   * drags its whole weather graph into the binding registry. The boolean is the render trigger.
   */
  @Local private undoVisible: boolean = false;
  private undoTarget: LocationModel | null = null;
  private undoIndex: number = -1;

  /** CancelDeleteListener (kt:138-145) — addLocation(location, index), back in its old slot. */
  private onUndoDelete(): void {
    const target: LocationModel | null = this.undoTarget;
    if (target === null || this.undoIndex < 0) {
      return;
    }
    this.viewModel.restoreLocation(target, this.undoIndex);
    this.refreshRows();
  }

  /* ------------------------------------------------------------ the weather-sources dialog ---- */

  /**
   * Whether the dialog is up — `viewModel.dialogChooseWeatherSourcesOpen` (kt:181).
   *
   * A BOOLEAN, and the location it is for is kept in the two PLAIN fields below rather than in
   * state. Holding a LocationModel in a `@Local` is what froze the app: ArkUI V2 registers
   * observation bindings across everything the value reaches, a LocationModel reaches its whole
   * weather graph, and the binding registry is a dictionary that `clearBinding` enumerates on every
   * page teardown. See LocationRowModel for the full account. The boolean is the render trigger, so
   * the plain fields are read during the rebuild it causes.
   */
  @Local private sourcesOpen: boolean = false;
  /** The scalars the dialog reads. Plain, so nothing observes it. */
  private sourcesTarget: LocationSources = new LocationSources();
  /**
   * Set only when Save should ADD rather than UPDATE — `viewModel.locationExists(it)` picks between
   * the two branches at kt:459-477. The my-location FAB configures a location that is not saved
   * yet; a swipe configures one that is.
   */
  private pendingLocation: LocationModel | null = null;

  /**
   * ItemTouchHelper.START (LocationItemTouchCallback.kt:91-97) — the per-location weather-sources
   * dialog, refused while a refresh is in flight. The row has already sprung back by the time this
   * runs, which is the port's equivalent of the unconditional `notifyItemChanged` at kt:92.
   */
  private onOpenSettings(formattedId: string): void {
    if (this.refuseWhileRefreshing()) {
      return;
    }
    const index: number = this.viewModel.indexOf(formattedId);
    if (index < 0) {
      return;
    }
    // kt:96 — openChooseWeatherSourcesDialog(location).
    this.pendingLocation = null;
    this.sourcesTarget = LocationSources.from(this.viewModel.getLocations()[index]);
    this.sourcesOpen = true;
  }

  /** `onClose(newLocation)` (kt:455-478) — the add and update branches, with their own messages. */
  private onSourcesClosed(sources: LocationSources | null): void {
    const pending: LocationModel | null = this.pendingLocation;
    this.sourcesOpen = false;
    this.pendingLocation = null;
    if (sources === null) {
      return;
    }

    if (pending === null) {
      // kt:462-469. A forecast-source change cannot produce a duplicate here — the dialog refuses
      // to move off Open-Meteo — so the only branch reachable is the plain update.
      const index: number = this.viewModel.indexOf(sources.formattedId);
      if (index < 0) {
        return;
      }
      if (!sources.changed) {
        return; // kt:880 — nothing changed, so nothing is written and nothing is announced.
      }
      const location: LocationModel = this.viewModel.getLocations()[index];
      sources.applyTo(location);
      /*
       * kt:863-876 nulls every update time so the next refresh is a full one. Here that is
       * `refreshTime`, and clearing it is not cosmetic: LocationRowModel reads it to choose between
       * the condition text and "Last updated x", so a re-sourced location stops claiming its old
       * fetch is current.
       */
      if (location.weather !== null) {
        location.weather.refreshTime = null;
      }
      this.viewModel.updateLocation(location).then(() => {
        this.refreshRows();
        this.toast('Location updated'); // strings.xml `location_message_updated`
      });
      return;
    }

    sources.applyTo(pending);
    this.listLoading = true;
    this.viewModel.addLocation(pending).then((result: AddLocationResult) => {
      this.listLoading = false;
      this.refreshRows();
      if (!result.added) {
        this.toast('Location list already contains this location with this forecast source.');
        return;
      }
      this.toast('Location added');
      // The row is saved with no coordinates yet; selecting it is what triggers the fix, exactly
      // as Android resolves it on the location's first refresh.
      this.viewModel.setCurrentIndex(result.index);
      this.leaveAfterSelection();
    }).catch((error: Error) => {
      this.listLoading = false;
      console.error('Could not add the current position: ' + error.message);
      this.toast('Could not add the current position');
    });
  }

  /** LocationHolder's click listener (kt:127) — pick the location and go back to it. */
  private onSelect(formattedId: string): void {
    const index: number = this.viewModel.indexOf(formattedId);
    if (index >= 0) {
      this.viewModel.setCurrentIndex(index);
    }
    this.leaveAfterSelection();
  }

  /**
   * What follows a selection, which is the one thing the two modes genuinely disagree about.
   *
   * As a pushed page there is a page to pop. As the unfolded drawer pane there is not — the weather
   * page is already beside it and simply changes what it shows, which is what closing a drawer that
   * is permanently open would amount to.
   */
  private leaveAfterSelection(): void {
    if (this.paneMode) {
      this.refreshRows();
      this.onSelected();
      return;
    }
    router.back();
  }

  build() {
    /*
     * The dialog is a SIBLING of the page, not a child of its padded Column — the same reason
     * LocationSearch documents: a scrim nested inside the insets padding starts below the status
     * bar, and a real dialog dims everything.
     */
    Stack({ alignContent: Alignment.Bottom }) {
      this.page()
      /*
       * The bar is a SIBLING of the page and anchored to the bottom, which is where
       * container_snackbar_layout_card.xml puts it (`layout_gravity="bottom|center_horizontal"`).
       * It sits above the page but below the dialog, and it takes no touches beyond its own action,
       * so the list underneath stays usable exactly as Android's does.
       */
      if (this.undoVisible) {
        Snackbar({
          message: 'Location deleted', // strings.xml `location_message_deleted`
          actionLabel: 'Undo',         // strings.xml `action_undo`
          dark: this.dark,
          onAction: () => {
            this.onUndoDelete();
          },
          onDismissed: () => {
            this.undoVisible = false;
            this.undoTarget = null;
            this.undoIndex = -1;
          }
        })
          .padding({ bottom: this.insets.bottom })
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
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
  }

  @Builder
  page() {
    Column() {
      // ---- BWCenterAlignedTopAppBar (kt:180-217): back, centred title, settings ----
      Stack({ alignContent: Alignment.Center }) {
        Row() {
          /*
           * No back arrow while this is the drawer pane — ManagementFragment.kt:198-202 passes a
           * null `onBackPressed` when the drawer is visible, because there is nothing to go back to.
           * The Row still needs its leading slot filled or the settings gear loses its Blank.
           */
          if (!this.paneMode) {
            Image($r('app.media.ic_back'))
              .width(Dimens.MATERIAL_ICON_SIZE)
              .height(Dimens.MATERIAL_ICON_SIZE)
              .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
              .margin({ left: Dimens.NORMAL_MARGIN })
              .onClick(() => {
                // kt:182-186 — the back arrow closes the management screen.
                router.back();
              })
          }

          Blank()

          Image($r('app.media.ic_settings'))
            .width(Dimens.MATERIAL_ICON_SIZE)
            .height(Dimens.MATERIAL_ICON_SIZE)
            .fillColor(AppColors.ON_SURFACE.resolve(this.dark))
            .margin({ right: Dimens.NORMAL_MARGIN })
            .onClick(() => {
              // kt:205 — startSettingsActivity. Screen 3's root is real now, so this is a route.
              router.pushUrl({ url: 'pages/Settings' })
                .catch((error: Error) => {
                  console.error('Settings unavailable: ' + error.message);
                });
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // strings.xml `locations`
        Text('Locations')
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.LARGE_TITLE_TEXT_SIZE)
          .fontColor(AppColors.ON_SURFACE.resolve(this.dark))
          .maxLines(1)
      }
      .width('100%')
      .height(APP_BAR_HEIGHT)

      // ---- the body: the list, or the empty state (kt:267-448) ----
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.rowModels.length === 0) {
          this.emptyState()
        } else {
          this.locationList()
          // The FAB column exists ONLY while the list is non-empty (kt:220) — with no locations
          // the two calls to action are the buttons in the middle of the screen instead.
          this.fabColumn()
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColors.SURFACE.resolve(this.dark))
    /*
     * The side insets are 0 in portrait and non-zero in landscape, where the cutout moves to the
     * edge the rows would otherwise run under. As the LEFT pane only the left inset can apply — the
     * right edge of this view is the weather page, not the screen — so the right one is dropped
     * there and left to the page that actually touches that edge.
     */
    .padding({
      top: this.insets.top,
      bottom: this.insets.bottom,
      left: this.insets.left,
      right: this.paneMode ? 0 : this.insets.right
    })
  }

  /** kt:268-371 — the progress bar (or the spacer standing in for it) above the rows. */
  @Builder
  locationList() {
    Column() {
      /*
       * kt:281-291. The two branches are deliberately the same total height: the indicator is a
       * 4 dp track with small_margin beneath it, and when it is absent the Kotlin puts an explicit
       * `4.dp + small_margin` Spacer there so the rows do not jump when a write starts.
       */
      if (this.listLoading) {
        Progress({ value: 0, total: 100, type: ProgressType.Linear })
          .color(AppColors.PRIMARY.resolve(this.dark))
          .backgroundColor(AppColors.SURFACE_VARIANT.resolve(this.dark))
          .width('100%')
          .height(PROGRESS_HEIGHT)
          .margin({ bottom: Dimens.SMALL_MARGIN })
          .style({ enableSmoothEffect: true })
      } else {
        Column()
          .width('100%')
          .height(PROGRESS_HEIGHT + Dimens.SMALL_MARGIN)
      }

      Scroll() {
        Column({ space: Dimens.SMALL_MARGIN }) {
            ForEach(this.rowModels, (row: LocationRowModel, index: number) => {
              LocationCard({
                /*
                 * The row's fields, not the model.
                 *
                 * LocationCard picks its colours in helper methods (rowBackground, titleColor, …),
                 * and a @Trace read inside a helper does not register as a render dependency — the
                 * same trap this file documents for `rows()` above. A scalar @Param does not have
                 * that problem: when one changes the component re-renders and every helper is
                 * re-evaluated with it. Each binding below reads a @Trace field DIRECTLY here, in
                 * the builder, which is the case V2 tracks reliably.
                 */
                title: row.title,
                body: row.body,
                selected: row.selected,
                alerts: row.alerts,
                currentPosition: row.currentPosition,
                weatherKind: row.weatherKind,
                daylight: row.daylight,
                dark: this.dark,
                lifted: this.dragIndex === index,
                dragOffsetY: this.offsetFor(index),
                onSelect: () => {
                  this.onSelect(row.formattedId);
                },
                onDelete: () => {
                  this.onDelete(row.formattedId);
                },
                onOpenSettings: () => {
                  this.onOpenSettings(row.formattedId);
                },
                onHandleDown: () => {
                  this.beginDrag(index);
                },
                onHandleMoved: (offsetY: number) => {
                  this.updateDrag(offsetY);
                },
                onHandleUp: () => {
                  this.endDrag();
                }
              })
                .onAreaChange((_: Area, area: Area) => {
                  // Every row is the same height, so one measurement drives the drag arithmetic.
                  this.rowHeight = Number(area.height) + Dimens.SMALL_MARGIN;
                })
            }, (row: LocationRowModel, index: number) =>
              /*
               * The SLOT, and nothing else.
               *
               * This used to be `index:formattedId:selected` so that a reorder changed the key set
               * and forced ForEach's diff to act — because ForEach does not re-run an item builder
               * whose key is unchanged, so a stable key meant a stale row. The cost was that every
               * moved slot was destroyed and rebuilt: 116 ms per drop at 12 rows.
               *
               * A reorder is no longer expressed as a change of keys at all. The slot objects are
               * mutated in place (refreshRows) and the card's @Param bindings above read those
               * @Trace fields, so the row updates without ForEach having to do anything. The key
               * only has to be unique and stable, which the index is.
               */
            index.toString())
        }
        .width('100%')
        .padding({
          // Clear of the FAB column so the last row can always be reached.
          bottom: FAB_SIZE + Dimens.NORMAL_MARGIN * 3
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      /*
       * The weather scene behind the pane is held still for the length of a scroll.
       *
       * Only in PANE mode: as a pushed page this list already covers the scene, and MainScreen's
       * `pageVisible` stops the loop outright. Beside the page it covers nothing, so the scene goes
       * on repainting under a gesture — which is the trade NativeApp's `ListScrolling()` makes, and
       * this is the same one. `onScrollStop` fires at the end of a fling as well as a drag, so the
       * scene resumes when the list is actually at rest.
       */
      .onScrollStart(() => {
        if (this.paneMode) {
          this.onScrollActive(true);
        }
      })
      .onScrollStop(() => {
        if (this.paneMode) {
          this.onScrollActive(false);
        }
      })
    }
    .width('100%')
    .height('100%')
    /*
     * kt:274-279 — normal_margin at the sides, set on the Column that wraps BOTH the progress bar
     * and the list, which is where the Kotlin puts it. No horizontal padding is added in landscape,
     * which is why the Kotlin sets start/end rather than a symmetric padding.
     */
    .padding({ left: Dimens.NORMAL_MARGIN, right: Dimens.NORMAL_MARGIN })
  }

  /** ---- the FAB column (kt:219-264) ---- */
  @Builder
  fabColumn() {
    Column({ space: Dimens.NORMAL_MARGIN }) {
      // kt:236-252 — offered only while no current-position entry exists.
      if (!this.hasCurrentPosition()) {
        this.fab($r('app.media.ic_my_location'), () => {
          this.onAddCurrentPosition();
        })
      }
      // kt:253-263 — onSearchBarClicked()
      this.fab($r('app.media.ic_add'), () => {
        this.openSearch();
      })
    }
    .margin({ right: Dimens.NORMAL_MARGIN, bottom: Dimens.NORMAL_MARGIN })
  }

  /**
   * The empty list (kt:372-447) — no rows, no FABs, two centred calls to action instead.
   *
   * Not reachable in this port today: `buildLocations()` seeds three cities on a fresh install and
   * the delete refuses at one row, so the list can never actually empty. On Android a first launch
   * lands straight here. Ported anyway because it is real screen-2 UI, and because dropping the
   * seed — which is what would make it reachable — is a screen-1 decision, not this step's.
   *
   * The debug-location button (kt:425-444) is not here, on the same `BreezyWeather.instance
   * .debugMode` gate that keeps the debug FAB out.
   */
  @Builder
  emptyState() {
    Column({ space: Dimens.LARGE_MARGIN }) {
      // kt:393-403 — a filled Button, so primary / onPrimary.
      Button({ type: ButtonType.Capsule }) {
        // strings.xml `action_add_new_location`
        Text('Add a new location')
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(BUTTON_TEXT_SIZE)
          .fontColor(AppColors.ON_PRIMARY.resolve(this.dark))
          .maxLines(1)
      }
      .height(BUTTON_HEIGHT)
      .padding({ left: BUTTON_H_PADDING, right: BUTTON_H_PADDING })
      .backgroundColor(AppColors.PRIMARY.resolve(this.dark))
      .onClick(() => {
        this.openSearch();
      })

      /*
       * kt:404-424 — an OutlinedButton: transparent container, a 1 dp `outline` border, and the
       * label explicitly coloured `primary` (kt:420). The icon is Icons.Outlined.MyLocation at
       * ButtonDefaults.IconSize, 18 dp, not the 24 dp the FAB uses.
       */
      Button({ type: ButtonType.Capsule }) {
        Row() {
          Image($r('app.media.ic_my_location'))
            .width(BUTTON_ICON_SIZE)
            .height(BUTTON_ICON_SIZE)
            .fillColor(AppColors.PRIMARY.resolve(this.dark))

          // strings.xml `action_add_current_location`
          Text('Add current location')
            .fontFamily(APP_FONT_FAMILY)
            .fontSize(BUTTON_TEXT_SIZE)
            .fontColor(AppColors.PRIMARY.resolve(this.dark))
            .maxLines(1)
            .margin({ left: BUTTON_ICON_SPACING })
        }
        .alignItems(VerticalAlign.Center)
      }
      .height(BUTTON_HEIGHT)
      .padding({ left: BUTTON_H_PADDING, right: BUTTON_H_PADDING })
      .backgroundColor(Color.Transparent)
      .borderWidth(1)
      .borderColor(AppColors.COMPOSE_OUTLINE.resolve(this.dark))
      .borderRadius(BUTTON_HEIGHT / 2)
      .onClick(() => {
        this.onAddCurrentPosition();
      })
    }
    .width('100%')
    .height('100%')
    // `verticalAlignment = Alignment.CenterVertically` on the enclosing Row (kt:385).
    .justifyContent(FlexAlign.Center)
    .padding({
      left: Dimens.NORMAL_MARGIN,
      right: Dimens.NORMAL_MARGIN,
      // kt:382 — the scaffold's bottom padding PLUS large_margin.
      bottom: Dimens.LARGE_MARGIN
    })
  }

  /** onSearchBarClicked (kt:148, 256) — both the FAB and the empty state's filled button. */
  private openSearch(): void {
    router.pushUrl({ url: 'pages/LocationSearch' })
      .catch((error: Error) => {
        console.error('Could not open the location search: ' + error.message);
      });
  }

  /**
   * kt:236-252 gates the my-location FAB on the list already having a current-position entry.
   *
   * Reads the view model, which is a plain array, so nothing here is observable — it is re-evaluated
   * only when something else re-renders this component. As a PAGE that was always enough, because
   * the page is built after the model is loaded. As a PANE it is not: a cold start into landscape
   * builds the pane while the store is still loading, and it would answer for the three-city seed
   * for ever. `refreshTick` is what corrects it; see Index.paneTick.
   */
  private hasCurrentPosition(): boolean {
    const locations: LocationModel[] = this.viewModel.getLocations();
    for (let i = 0; i < locations.length; i++) {
      if (locations[i].isCurrentPosition) {
        return true;
      }
    }
    return false;
  }

  /**
   * The my-location FAB (kt:236-252).
   *
   * Android opens the source picker and adds on close; with one source that dialog has nothing to
   * choose, so this adds directly — the same decision the search screen documents. What it does add
   * is the permission prompt, because a current-position row that can never resolve is worse than
   * not adding one: see `ensureLocationPermission`.
   */
  private onAddCurrentPosition(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ensureLocationPermission(context).then((granted: boolean) => {
      if (!granted) {
        // RefreshErrorType.ACCESS_LOCATION_PERMISSION_MISSING's short message.
        this.toast('Location permission is required');
        return;
      }
      /*
       * kt:240-244 — the FAB does NOT add. It opens the weather-sources dialog on a fresh
       * `Location(isCurrentPosition = true)`, and the location is added only if that dialog is
       * saved. The port used to add directly, which was the honest shortcut while the dialog did
       * not exist.
       */
      // kt:241-243 — Location(isCurrentPosition = true).applyDefaultPreset(sourceManager).
      const fresh: LocationModel = buildCurrentPositionLocation();
      applyDefaultPreset(fresh);
      this.pendingLocation = fresh;
      this.sourcesTarget = LocationSources.from(fresh);
      this.sourcesOpen = true;
    });
  }

  /**
   * A Material3 FloatingActionButton.
   *
   * kt:224 sets containerColor = colorScheme.tertiary — the TERTIARY role, not tertiaryContainer,
   * so it is the deep gold with white content rather than the pale container with dark content.
   * FloatingActionButton derives its content colour with contentColorFor(container), i.e.
   * onTertiary.
   */
  @Builder
  fab(icon: Resource, action: () => void) {
    /*
     * A rounded SQUARE, not a circle.
     *
     * Material3's FloatingActionButton is a 56 dp container with a 16 dp corner — the circle is the
     * Material2 shape. This was drawn as a circle and the reference build's is visibly a squircle
     * (`ref_screen2_light.png`). The search screen's Tune FAB in this same app already had it
     * right, which is what makes it an oversight rather than a decision.
     */
    Button({ type: ButtonType.Normal }) {
      Image(icon)
        .width(Dimens.MATERIAL_ICON_SIZE)
        .height(Dimens.MATERIAL_ICON_SIZE)
        .fillColor(AppColors.ON_TERTIARY.resolve(this.dark))
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    .borderRadius(Dimens.NORMAL_MARGIN)
    .backgroundColor(AppColors.TERTIARY.resolve(this.dark))
    .onClick(action)
  }
}
