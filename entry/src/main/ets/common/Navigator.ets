/*
 * Every main-screen action whose destination is not ported yet routes through here.
 * The placeholder page just names the screen that would have opened, so the handler
 * mapping stays verifiable while later steps fill the screens in.
 */

import { router } from '@kit.ArkUI';

export class PlaceholderParams {
  screenName: string = '';
  detail: string = '';
}

/**
 * Screen 4 — `IntentHelper.startDetailsActivity`, the destination of every tile and trend column.
 *
 * `screen` is a DetailScreen id and `dayIndex` the day the tap was on, which the pager opens at
 * (DetailsViewModel's `initialIndex`).
 */
export class DetailsParams {
  locationId: string = '';
  screen: string = '';
  dayIndex: number = 0;
}

export function goDetails(locationId: string, screen: string, dayIndex: number): void {
  const params = new DetailsParams();
  params.locationId = locationId;
  params.screen = screen;
  params.dayIndex = dayIndex;
  router.pushUrl({ url: 'pages/Details', params: params })
    .catch((error: Error) => {
      console.error(`Failed to open details for ${screen}: ${error.message}`);
    });
}

/**
 * The alert screen — `IntentHelper.startAlertActivity(activity, formattedId, alertId)`.
 *
 * `alertId` is empty when the whole card was tapped and set when one of its rows was
 * (AlertViewHolder.kt:80 vs :149); the screen scrolls to that alert.
 */
export class AlertListParams {
  locationId: string = '';
  alertId: string = '';
}

export function goAlertList(locationId: string, alertId: string = ''): void {
  const params = new AlertListParams();
  params.locationId = locationId;
  params.alertId = alertId;
  router.pushUrl({ url: 'pages/AlertList', params: params })
    .catch((error: Error) => {
      console.error(`Failed to open the alert list: ${error.message}`);
    });
}

export function goPlaceholder(screenName: string, detail: string = ''): void {
  const params = new PlaceholderParams();
  params.screenName = screenName;
  params.detail = detail;
  router.pushUrl({ url: 'pages/Placeholder', params: params })
    .catch((error: Error) => {
      console.error(`Failed to open placeholder for ${screenName}: ${error.message}`);
    });
}
