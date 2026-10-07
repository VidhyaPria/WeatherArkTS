/*
 * The About screen's static tables — data/Contributors.kt plus AboutViewModel's link list.
 *
 * Transcribed here once and re-transcribed into the NDK's data/AboutCatalogue.{h,cpp}, the same
 * arrangement `SourceCatalogue` has with the weather-sources screen: one file per port carrying the
 * same rows, so the two cannot drift.
 *
 * `appContributors` is Contributors.kt:47-170 in ITS ORDER — the screen does not sort it. Only two
 * entries carry a `contribution` line, and one is a URL rather than a GitHub handle.
 */

/** ContributorItem (Contributors.kt:22-37). `link` is the first non-empty of the four. */
export class ContributorItem {
  readonly name: string;
  /** The resolved link — github/weblate/mail/url in that order, "" when there is none. */
  readonly link: string;
  /** The `contribution` string, or "" — only two contributors have one. */
  readonly contribution: string;

  constructor(name: string, link: string, contribution: string = '') {
    this.name = name;
    this.link = link;
    this.contribution = contribution;
  }
}

/** github = "x" → https://github.com/x (Contributors.kt:30). */
function gh(handle: string): string {
  return 'https://github.com/' + handle;
}

/* strings.xml — the only two contribution lines in the list. */
const CONTRIBUTION_GEOMETRIC: string = 'Developer of the original project Geometric Weather';
const CONTRIBUTION_DESIGNER: string = 'Logo designer';

/** Contributors.kt:47-170, in order. */
export const APP_CONTRIBUTORS: ContributorItem[] = [
  new ContributorItem('Julien Papasian', gh('papjul')),
  new ContributorItem('WangDaYeeeeee', gh('WangDaYeeeeee'), CONTRIBUTION_GEOMETRIC),
  new ContributorItem('min7-i', gh('min7-i')),
  new ContributorItem('chunshek', gh('chunshek')),
  new ContributorItem('Cod3d.', gh('Cod3dDOT')),
  new ContributorItem('ecawthorne', gh('ecawthorne')),
  new ContributorItem('Romain Théry', gh('rthery')),
  new ContributorItem('Mark Bestavros', gh('mbestavros')),
  new ContributorItem('Suyash Gupta', gh('suyashgupta25')),
  new ContributorItem('Coelacanthus', gh('CoelacanthusHex')),
  new ContributorItem('danielzhang130', gh('danielzhang130')),
  new ContributorItem('majjejjam', gh('majjejjam')),
  new ContributorItem('bunburya', gh('bunburya')),
  new ContributorItem('Willem Schipper', gh('willem640')),
  new ContributorItem('Sven', gh('SKBotNL')),
  new ContributorItem('jayyuz', gh('jayyuz')),
  new ContributorItem('JiunnTarn', gh('JiunnTarn')),
  new ContributorItem('mags0ft', gh('mags0ft')),
  new ContributorItem('Devy Ballard', gh('devycarol')),
  new ContributorItem('Mushfiq1060', gh('Mushfiq1060')),
  new ContributorItem('ccyybn', gh('ccyybn')),
  new ContributorItem('Doğaç Tanrıverdi', gh('DogacTanriverdi')),
  new ContributorItem('Nero Nguyen', gh('neronguyenvn')),
  new ContributorItem('Dipesh Pal', gh('codewithdipesh')),
  new ContributorItem('Cactric', gh('Cactric')),
  new ContributorItem('ntzb', gh('ntzb')),
  new ContributorItem('mu', gh('4eUeP')),
  new ContributorItem('Anthony Dégrange', 'https://anthony-degrange-design.fr/',
    CONTRIBUTION_DESIGNER)
];

/**
 * `appTranslators` filtered to the device language, which for this port is English
 * (AboutScreen.kt:103-112).
 *
 * The full table is 296 rows covering every language Breezy ships; the screen shows only those whose
 * `lang` array contains the current language, and falls back to the English set when a language has
 * none. Only the English three are carried here — every other row is unreachable on an
 * English-only build, and transcribing 296 rows to render three would be inventing work, not
 * fidelity. If the port ever gains other languages this table has to grow with them.
 */
export const APP_TRANSLATORS: ContributorItem[] = [
  new ContributorItem('Julien Papasian', gh('papjul')),
  new ContributorItem('WangDaYeeeeee', gh('WangDaYeeeeee')),
  new ContributorItem('kilimov25', gh('kilimov25'))
];

/** One tappable link row — AboutAppLinkItem (AboutScreen.kt:80-84). */
export class AboutLinkItem {
  readonly icon: string;
  readonly title: string;
  /** A URL to confirm and open, or "" when the row opens a screen instead. */
  readonly url: string;
  /** The screen this row opens when it has no URL — routed to the placeholder. */
  readonly screen: string;

  constructor(icon: string, title: string, url: string, screen: string = '') {
    this.icon = icon;
    this.title = title;
    this.url = url;
    this.screen = screen;
  }
}

/*
 * BuildConfig's links. These are the shipped app's own URLs, which is what the reference device
 * shows under "Contact" — see ref_about_top.png.
 */
export const SOURCE_CODE_LINK: string = 'https://github.com/breezy-weather/breezy-weather';
export const MATRIX_LINK: string = 'https://matrix.to/#/#breezy-weather:matrix.org';
export const RELEASES_LINK: string =
  'https://github.com/breezy-weather/breezy-weather/releases';

/**
 * `HttpSource.privacyPolicyUrl`, keyed by source id — the Privacy policy screen's whole content.
 *
 * Kept here rather than as a field on all 29 `SourceSpec`s because it is used by exactly one screen
 * and reads as one table, which is also how it is checked against the reference.
 *
 * ENGLISH branches: MET Norway, China, FMI, IPMA and JMA each pick their URL from the locale
 * (`by lazy { with(currentLocale.code) { … } }`), and this port is English-only, so the `else` arm
 * is the one that applies. A source whose `privacyPolicyUrl` is "" — the freenet stubs, and the
 * three non-HTTP sources — is absent here and the screen skips it, which is what
 * `filter { it.privacyPolicyUrl.startsWith("http") }` does (PrivacyPolicyActivity.kt:79).
 */
export const PRIVACY_POLICY_URLS: Map<string, string> = new Map<string, string>([
  ['ipsb', 'https://ip.sb/privacy-policy/'],
  ['baidu_ip', 'https://lbs.baidu.com/index.php?title=openprivacy'],
  ['nominatim', 'https://osmfoundation.org/wiki/Privacy_Policy'],
  ['openmeteo', 'https://open-meteo.com/en/terms#privacy'],
  ['accu', 'https://www.accuweather.com/en/privacy'],
  ['fpas', 'https://invent.kde.org/webapps/foss-public-alert-server/-/wikis/Terms-of-Service'],
  ['infoplaza', 'https://www.infoplaza.com/en/disclaimer-and-privacy'],
  ['metno', 'https://www.met.no/en/About-us/privacy'],
  ['ncei', 'https://www.ncei.noaa.gov/privacy'],
  ['openweather', 'https://openweather.co.uk/privacy-policy'],
  ['pirateweather', 'https://pirate-weather.apiable.io/privacy'],
  ['wmosevereweather', 'https://wmo.int/privacy-policy'],
  ['atmofrance', 'https://www.atmo-france.org/article/politique-de-confidentialite'],
  ['china', 'https://privacy.mi.com/all/en_US'],
  ['dmi', 'https://www.dmi.dk/om-hjemmesiden/privatliv/'],
  ['fmi', 'https://en.ilmatieteenlaitos.fi/data-protection'],
  ['geosphereat', 'https://www.geosphere.at/de/legal'],
  ['knmi', 'https://www.knmi.nl/privacy'],
  ['metoffice', 'https://www.metoffice.gov.uk/policies/privacy'],
  ['meteoam', 'https://www.meteoam.it/it/privacy-policy'],
  ['mf', 'https://meteofrance.com/application-meteo-france-politique-de-confidentialite'],
  ['ncdr', 'https://ncdr.nat.gov.tw/Page?itemid=40&mid=7'],
  ['nlsc', 'https://www.nlsc.gov.tw/cp.aspx?n=1633'],
  ['polleninfo', 'https://www.polleninformation.at/en/our-terms-of-use'],
  ['recosante', 'https://recosante.beta.gouv.fr/donnees-personnelles/'],

  /*
   * The remaining national and regional sources.
   *
   * This table used to stop here, at 25 rows, and the screen's own comment blamed "the port's
   * catalogue carries 29 sources where the reference has ~60". That was wrong twice over: the
   * source catalogue is COMPLETE (all 75 ids, verified against the Kotlin), and the short screen
   * was this table. Android's row set is every source whose `privacyPolicyUrl` starts with "http"
   * — 47 of the 75; the other 28 declare `privacyPolicyUrl = ""` and are skipped.
   *
   * Multi-language URLs take their `else` branch, as everywhere else in this port.
   */
  ['aemet', 'https://www.aemet.es/es/nota_legal'],
  ['atmoaura', 'https://www.atmo-auvergnerhonealpes.fr/article/politique-de-confidentialite'],
  ['atmograndest', 'https://www.atmo-grandest.eu/article/politique-de-confidentialite'],
  ['atmohdf', 'https://www.atmo-hdf.fr/article/donnees-personnelles'],
  ['atmosud', 'https://www.atmosud.org/article/politique-de-confidentialite'],
  ['brightsky', 'https://brightsky.dev/'],
  ['cwa', 'https://www.cwa.gov.tw/V8/E/private.html'],
  ['eccc', 'https://app.weather.gc.ca/privacy-en.html'],
  ['epdhk', 'https://www.aqhi.gov.hk/en/privacy-policy.html'],
  ['hko', 'https://www.hko.gov.hk/en/privacy/policy.htm'],
  ['ilmateenistus', 'https://www.ilmateenistus.ee/meist/kasutustingimused/?lang=en'],
  ['ims', 'https://ims.gov.il/en/termOfuse'],
  ['ipma', 'https://www.ipma.pt/en/siteinfo/index.html'],
  ['jma', 'https://www.jma.go.jp/jma/en/copyright.html'],
  ['lhmt', 'https://www.meteo.lt/istaiga/asmens-duomenu-apsauga/privatumo-politika/'],
  ['meteolux', 'https://ana.gouvernement.lu/en/support/politique-confidentialite-meteolux.html'],
  ['metie', 'https://www.met.ie/about-us/privacy'],
  ['mgm', 'https://www.mgm.gov.tr/site/gizlilik-politikasi.aspx'],
  ['nws', 'https://www.weather.gov/privacy'],
  ['smg', 'https://www.smg.gov.mo/en/subpage/21/page/21'],
  ['smhi', 'https://www.smhi.se/om-smhi/smhis-hantering-av-personuppgifter-och-integritetspolicy'],
  ['veduris', 'https://vedur.is/um-vi/vefurinn/personuvernd/']
]);

/**
 * One row of the Dependencies screen — an AboutLibraries `Library`: name, author, version and the
 * licence badges (DependenciesActivity.kt:62-66, `showLicenseBadges = true`).
 */
export class DependencyItem {
  readonly name: string;
  readonly author: string;
  readonly version: string;
  readonly license: string;

  constructor(name: string, author: string, version: string, license: string) {
    this.name = name;
    this.author = author;
    this.version = version;
    this.license = license;
  }
}

/**
 * What THIS app is built on.
 *
 * The Kotlin renders `R.raw.aboutlibraries`, a manifest the AboutLibraries Gradle plugin generates
 * from the app's own dependency graph — Retrofit, OkHttp, Vico, Hilt and the rest. **Transcribing
 * that list would be a lie about this app**: neither port links any of it. Both have an empty
 * `dependencies` in oh-package.json5, hand-written JSON readers, and exactly one bundled third-party
 * asset — the Roboto family.
 *
 * So this screen lists what the ports actually ship, which is what the screen MEANS. It is short
 * because the ports are, not because anything was left out.
 */
export const APP_DEPENDENCIES: DependencyItem[] = [
  new DependencyItem('Roboto', 'Christian Robertson', '', 'Apache-2.0')
];

/** BuildConfig.PRIVACY_POLICY_LINK — the app's own row, read off the reference screen. */
export const PRIVACY_POLICY_LINK: string =
  'https://github.com/breezy-weather/breezy-weather/blob/main/PRIVACY.md';

/** The "Contact" group (AboutScreen.kt:114-151). */
export const ABOUT_CONTACT_LINKS: AboutLinkItem[] = [
  new AboutLinkItem('ic_code', 'Source code', SOURCE_CODE_LINK),
  new AboutLinkItem('ic_forum', 'Matrix room', MATRIX_LINK)
];

/**
 * The "About app" group — `getAboutAppLinks` (AboutViewModel.kt:33-48).
 *
 * Both open activities this port has not ported, so both go to the placeholder carrying their own
 * name, per CLAUDE.md.
 */
export const ABOUT_APP_LINKS: AboutLinkItem[] = [
  new AboutLinkItem('ic_shield_lock', 'Privacy policy', '', 'Privacy policy'),
  new AboutLinkItem('ic_contract', 'Dependencies', '', 'Dependencies')
];
