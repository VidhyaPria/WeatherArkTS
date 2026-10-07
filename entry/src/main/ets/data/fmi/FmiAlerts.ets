/*
 * FMI weather warnings, from the Common Alerting Protocol feed.
 *
 * Open-Meteo publishes no alerts — OpenMeteoService.kt declares FORECAST, CURRENT, AIR_QUALITY,
 * POLLEN and MINUTELY and no SourceFeature.ALERT — so Breezy's alert card is fed by a SECOND
 * source. On the reference Android device that source is FMI, which is why its home page shows
 * "Upcoming alerts, tap here to see them" and this port did not.
 *
 * Ported from src_nonfreenet/.../fmi/FmiService.kt (getAlertList) plus FmiAlertsApi:
 *   1. GET alerts.fmi.fi/cap/feed/rss_en-GB.rss   — an index of <item><link> CAP documents
 *   2. GET each link                              — one CAP XML per warning
 *   3. skip msgType=Cancel, take the English <info>, match the location by <areaDesc>
 *
 * CAP documents are ~650 KB each, of which almost all is <polygon> coordinate soup this never
 * reads, so the elements are scanned by name rather than parsed into a tree.
 */

import { http } from '@kit.NetworkKit';
import { Alert } from '../../model/Weather';

/** FmiAlertsApi.kt:@GET("cap/feed/rss_en-GB.rss") */
const FEED_URL: string = 'https://alerts.fmi.fi/cap/feed/rss_en-GB.rss';
const TIMEOUT_MS: number = 20000;

/** The bounds FmiServiceStub checks before offering the feature at all — Finland only. */
export function coveredByFmi(latitude: number, longitude: number): boolean {
  return latitude >= 59.0 && latitude <= 70.5 && longitude >= 19.0 && longitude <= 32.0;
}

/** The inner text range of the first `<name>` at or after `from`, or null. */
class Element {
  readonly innerStart: number;
  readonly innerEnd: number;
  readonly afterClose: number;

  constructor(innerStart: number, innerEnd: number, afterClose: number) {
    this.innerStart = innerStart;
    this.innerEnd = innerEnd;
    this.afterClose = afterClose;
  }
}

function findElement(doc: string, name: string, from: number): Element | null {
  const open: string = '<' + name;
  const close: string = '</' + name + '>';
  let at: number = from;
  while (true) {
    at = doc.indexOf(open, at);
    if (at < 0) {
      return null;
    }
    // Guard against <areaDesc> matching a search for <area>.
    const next: string = doc.charAt(at + open.length);
    if (next === '>' || next === ' ' || next === '\t' || next === '\n' || next === '/') {
      break;
    }
    at += open.length;
  }
  const tagEnd: number = doc.indexOf('>', at);
  if (tagEnd < 0) {
    return null;
  }
  if (doc.charAt(tagEnd - 1) === '/') {
    return new Element(tagEnd, tagEnd, tagEnd + 1);
  }
  const closeAt: number = doc.indexOf(close, tagEnd);
  if (closeAt < 0) {
    return null;
  }
  return new Element(tagEnd + 1, closeAt, closeAt + close.length);
}

function textOf(doc: string, name: string, from: number, limit: number): string {
  const element: Element | null = findElement(doc, name, from);
  if (element === null || element.innerStart >= limit) {
    return '';
  }
  return doc.substring(element.innerStart, element.innerEnd).trim();
}

/**
 * CAP text → what the alert screen prints.
 *
 * Android runs `AnnotatedString.fromHtml(text.replace("\n", "<br />"))` (AlertScreen.kt:182-184),
 * so the description is HTML. For FMI it is plain prose, but the CAP payload still arrives
 * XML-escaped, and a source that does emit markup must not leak raw tags into the text. So: block
 * tags become line breaks, every other tag is dropped, then the entities are decoded — the plain
 * text that `fromHtml` would render, minus the bold/italic spans neither port styles.
 *
 * `formatAlertText` (CapAlert.kt:245-280) also has an NWS and a CWA branch; both are keyed off
 * `senderName` and neither can fire on the FMI feed, which is the only alert source either port
 * implements.
 */
function decodeCapText(raw: string): string {
  let text: string = raw;
  text = text.replace(/<br\s*\/?>/gi, '\n');
  text = text.replace(/<\/(p|div|li|h[1-6])>/gi, '\n');
  text = text.replace(/<[^>]*>/g, '');
  text = text.replace(/&lt;/g, '<');
  text = text.replace(/&gt;/g, '>');
  text = text.replace(/&quot;/g, '"');
  text = text.replace(/&apos;/g, "'");
  text = text.replace(/&#39;/g, "'");
  text = text.replace(/&nbsp;/g, ' ');
  // Last: an escaped ampersand must not re-open one of the entities above.
  text = text.replace(/&amp;/g, '&');
  return text.trim();
}

/** An ISO-8601 instant with an offset, CAP's onset/expires form. Null when unparseable. */
function parseIso(text: string): Date | null {
  if (text.length < 19) {
    return null;
  }
  const parsed: number = Date.parse(text);
  return isNaN(parsed) ? null : new Date(parsed);
}

/** AlertSeverity → the triangle's tint, colorLevel_* worst first (FmiService.kt). */
function severityColor(severity: string): string {
  const value: string = severity.toLowerCase();
  if (value === 'extreme') {
    return '#FFE52F35';
  }
  if (value === 'severe') {
    return '#FFFFA726';
  }
  if (value === 'moderate') {
    return '#FFFFCA28';
  }
  return '#FF72D572';
}

async function getBody(url: string): Promise<string> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200) {
      throw new Error('HTTP ' + response.responseCode.toString());
    }
    return response.result as string;
  } finally {
    request.destroy();
  }
}

/** The CAP document URLs the RSS index names, in feed order. */
export function parseAlertFeed(rss: string): string[] {
  const links: string[] = [];
  let at: number = 0;
  while (true) {
    const item: Element | null = findElement(rss, 'item', at);
    if (item === null) {
      break;
    }
    const link: string = textOf(rss, 'link', item.innerStart, item.innerEnd);
    if (link.length > 0) {
      links.push(link);
    }
    at = item.afterClose;
  }
  return links;
}

/** One CAP document → zero or more alerts for `region` (Location.admin1 on Android). */
export function parseCapAlert(cap: string, region: string, now: Date): Alert[] {
  const alerts: Alert[] = [];
  // A Cancel message withdraws a warning rather than raising one.
  if (textOf(cap, 'msgType', 0, cap.length).toLowerCase() === 'cancel') {
    return alerts;
  }

  let at: number = 0;
  while (true) {
    const info: Element | null = findElement(cap, 'info', at);
    if (info === null) {
      break;
    }
    at = info.afterClose;

    // One <info> per language; take English, as getInfoForContext does for an en locale.
    if (!textOf(cap, 'language', info.innerStart, info.innerEnd).startsWith('en')) {
      continue;
    }

    // The warning applies here only if one of its areas names this region — the fast path
    // FmiService takes before falling back to polygon containment.
    let matches: boolean = false;
    let areaAt: number = info.innerStart;
    while (!matches) {
      const area: Element | null = findElement(cap, 'area', areaAt);
      if (area === null || area.innerStart >= info.innerEnd) {
        break;
      }
      areaAt = area.afterClose;
      const areaDesc: string = textOf(cap, 'areaDesc', area.innerStart, area.innerEnd);
      if (areaDesc.length > 0 && region.length > 0 && areaDesc.includes(region)) {
        matches = true;
      }
    }
    if (!matches) {
      continue;
    }

    const alert = new Alert();
    // <event> is the short name Breezy shows ("Wind warning for land areas"); <headline> is the
    // feed's long title with region and times baked in, which the card would truncate.
    alert.headline = decodeCapText(textOf(cap, 'event', info.innerStart, info.innerEnd));
    if (alert.headline.length === 0) {
      alert.headline = decodeCapText(textOf(cap, 'headline', info.innerStart, info.innerEnd));
    }
    /*
     * `capAlert.identifier` (FmiService.kt:396). The document-level <identifier> sits OUTSIDE
     * <info>, so it is searched from 0, not from the info block. It keys the ForEach on the main
     * card and tells the alert screen which row to scroll to.
     */
    alert.alertId = textOf(cap, 'identifier', 0, cap.length);
    alert.description = decodeCapText(textOf(cap, 'description', info.innerStart, info.innerEnd));
    alert.instruction = decodeCapText(textOf(cap, 'instruction', info.innerStart, info.innerEnd));
    alert.source = decodeCapText(textOf(cap, 'senderName', info.innerStart, info.innerEnd));
    alert.startDate = parseIso(textOf(cap, 'onset', info.innerStart, info.innerEnd));
    alert.endDate = parseIso(textOf(cap, 'expires', info.innerStart, info.innerEnd));
    const severity: string = textOf(cap, 'severity', info.innerStart, info.innerEnd);
    alert.color = severityColor(severity);
    if (alert.alertId.length === 0) {
      // `Objects.hash(title, severity, start)` (kt:396) — any stable per-alert key will do.
      const startMs: string = alert.startDate === null ? '' : alert.startDate.getTime().toString();
      alert.alertId = alert.headline + '|' + severity + '|' + startMs;
    }

    // An expired warning is not shown.
    if (alert.endDate !== null && alert.endDate.getTime() <= now.getTime()) {
      break;
    }
    if (alert.headline.length > 0) {
      alerts.push(alert);
    }
    break;  // One English info block per document.
  }
  return alerts;
}

/**
 * Every warning in force for a location.
 *
 * Two round trips as FmiAlertsApi does: the RSS index, then one document per warning. A failure
 * yields an empty list rather than throwing — a failed alert leg must not disturb a forecast
 * already on screen, the rule OpenMeteoService.kt:327-330 applies to any failed feature.
 */
export async function fetchAlerts(
  latitude: number,
  longitude: number,
  region: string
): Promise<Alert[]> {
  if (!coveredByFmi(latitude, longitude)) {
    return [];
  }
  try {
    const links: string[] = parseAlertFeed(await getBody(FEED_URL));
    const now = new Date();
    const alerts: Alert[] = [];
    for (let i = 0; i < links.length; i++) {
      const document: string = await getBody(links[i]);
      const parsed: Alert[] = parseCapAlert(document, region, now);
      for (let j = 0; j < parsed.length; j++) {
        alerts.push(parsed[j]);
      }
    }
    return alerts;
  } catch (error) {
    return [];
  }
}
