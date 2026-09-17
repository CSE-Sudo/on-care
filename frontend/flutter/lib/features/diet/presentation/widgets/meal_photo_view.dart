import 'package:flutter/material.dart';
import 'package:oncare/features/diet/presentation/widgets/stored_meal_photo.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 끼니 사진 — 회원이 올린 사진, 없으면 번들 자산, 그것도 없으면 끼니 이모지.
///
/// 목록의 작은 썸네일과 수정 화면 상단의 큰 사진이 **같은 순서**로 고르도록
/// 한곳에 둔다. 두 화면이 각자 고르면, 같은 끼니가 목록에서는 사진으로
/// 보이는데 수정 화면에서는 이모지로 열리는 일이 생긴다. (#699, #1053)
///
/// 틀은 [AppImageFrame] 이다 — 반경은 12(기본) 또는 20([large]) 둘뿐이다(#1690).
class MealPhotoView extends StatelessWidget {
  /// Creates the photo view at [width] × [height].
  const MealPhotoView({
    super.key,
    required this.photoUrl,
    required this.photoAsset,
    required this.emoji,
    required this.width,
    required this.height,
    this.large = false,
  });

  /// API path of the photo the member uploaded (`/diet/photos/<id>`).
  final String? photoUrl;

  /// Bundled demo asset — 실서버에 붙으면 늘 비어 있어 뒤로 물린다.
  final String? photoAsset;

  /// 사진이 하나도 없을 때 그리는 끼니 이모지.
  final String emoji;

  final double width;
  final double height;

  /// 수정 화면 상단처럼 카드급 큰 사진이면 반경 20.
  final bool large;

  /// 실제 사진(회원이 올린 것이든 번들 자산이든)이 있는지.
  bool get hasPhoto =>
      (photoUrl != null && photoUrl!.isNotEmpty) || photoAsset != null;

  @override
  Widget build(BuildContext context) {
    final String? url = photoUrl;
    return AppImageFrame(
      width: width,
      height: height,
      large: large,
      child: url != null && url.isNotEmpty
          ? StoredMealPhoto(
              path: url,
              width: width,
              height: height,
              fallback: _assetOrEmoji(context),
            )
          : _assetOrEmoji(context),
    );
  }

  Widget _assetOrEmoji(BuildContext context) {
    final String? asset = photoAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        width: width,
        height: height,
        // 번들 자산도 회원이 올린 사진과 같게 읽힌다 — 어느 쪽이 그려졌는지는
        // 음성 안내로 읽는 회원에게 차이가 없다(#1942).
        semanticLabel: AppLocalizations.of(context).a11yMealPhoto,
        fit: BoxFit.cover,
        // 번들 자산이 빠져 있어도 카드는 그려야 한다.
        errorBuilder: (BuildContext _, Object _, StackTrace? _) => _emoji(),
      );
    }
    return _emoji();
  }

  /// 이모지는 틀 크기를 따라 커진다 — 글자 크기를 따로 적지 않는다.
  Widget _emoji() => Padding(
    padding: const EdgeInsets.all(OnCareSpacing.s12),
    child: Center(child: FittedBox(child: Text(emoji))),
  );
}
