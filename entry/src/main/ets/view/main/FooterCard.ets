/*
 * The attribution line closing the card list.
 *
 * Port of FooterViewHolder.kt:115-162. MainAdapter.kt:173 appends ViewType.FOOTER
 * unconditionally, so it is the last row on every location page.
 *
 * The Compose row is centred, padded by normal_margin / 2 (:117), bold (:160), and coloured
 * with the weather theme's on-background colour (:152-158) — the same colour the toolbar and
 * header text use. Both the source name and "More" are underlined links:
 *   source name -> the source's attribution link (:128-144)
 *   More        -> the data-sources dialog (:105-113, 149)
 * The dot between them is R.string.dot_separator (:148).
 */

import { Dimens } from '../../theme/Dimens';
import { APP_FONT_FAMILY } from '../../common/Typography';

/** strings.xml dot_separator */
const DOT_SEPARATOR: string = ' • ';

@ComponentV2
export struct FooterCard {
  /** The forecast source's attribution string, e.g. "Open-Meteo". */
  @Param sourceName: string = '';
  @Param contentColor: string = '#FF191C1E';
  /** FooterViewHolder.kt:128-144 — tapping the source name opens its attribution link. */
  @Event onSourceClick: () => void = () => {
  };
  /** FooterViewHolder.kt:105-113 — tapping "More" opens the data-sources dialog. */
  @Event onMoreClick: () => void = () => {
  };

  build() {
    Row() {
      if (this.sourceName.length > 0) {
        Text(this.sourceName)
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(this.contentColor)
          .fontWeight(FontWeight.Bold)
          .decoration({ type: TextDecorationType.Underline, color: this.contentColor })
          .onClick(() => {
            this.onSourceClick();
          })
        Text(DOT_SEPARATOR)
          .fontFamily(APP_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(this.contentColor)
          .fontWeight(FontWeight.Bold)
      }
      // strings.xml action_more, or data_sources when the source has no attribution (:150).
      Text(this.sourceName.length > 0 ? 'More' : 'Data sources')
        .fontFamily(APP_FONT_FAMILY)
        .fontSize(Dimens.CONTENT_TEXT_SIZE)
        .fontColor(this.contentColor)
        .fontWeight(FontWeight.Bold)
        .decoration({ type: TextDecorationType.Underline, color: this.contentColor })
        .onClick(() => {
          this.onMoreClick();
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    // FooterViewHolder.kt:117 — normal_margin / 2.
    .padding(Dimens.NORMAL_MARGIN / 2)
  }
}
