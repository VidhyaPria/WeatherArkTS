/*
 * Destination for every main-screen action whose real screen is not ported yet.
 *
 * Naming the target screen keeps the click-handler mapping verifiable: tapping the toolbar's
 * list icon must land on "Location list", the edit icon on "Edit this location", and a trend
 * column on "Daily details" with the detail screen the Kotlin adapter would have passed.
 */

import { router } from '@kit.ArkUI';
import { PlaceholderParams } from '../common/Navigator';
import { Dimens } from '../theme/Dimens';
import { AppColors } from '../theme/AppColors';
import { SETTINGS_FONT_FAMILY } from '../common/Typography';

@Entry
@ComponentV2
struct Placeholder {
  @Local private screenName: string = '';
  @Local private detail: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as PlaceholderParams;
    if (params !== null && params !== undefined) {
      this.screenName = params.screenName;
      this.detail = params.detail;
    }
  }

  build() {
    Column({ space: Dimens.SMALL_MARGIN }) {
      Text('Not ported yet')
        .fontFamily(SETTINGS_FONT_FAMILY)
        .fontSize(Dimens.CONTENT_TEXT_SIZE)
        .fontColor(AppColors.BODY_TEXT.light)

      Text(this.screenName)
        .fontFamily(SETTINGS_FONT_FAMILY)
        .fontSize(Dimens.LARGE_TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.ON_BACKGROUND.light)

      if (this.detail.length > 0) {
        Text(this.detail)
          .fontFamily(SETTINGS_FONT_FAMILY)
          .fontSize(Dimens.CONTENT_TEXT_SIZE)
          .fontColor(AppColors.BODY_TEXT.light)
      }

      Button('Back')
        .margin({ top: Dimens.LARGE_MARGIN })
        .onClick(() => {
          router.back();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(Dimens.LARGE_MARGIN)
    .backgroundColor(AppColors.BACKGROUND.light)
  }
}
