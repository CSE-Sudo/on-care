import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/coach_photo_send_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너에게 보낼 사진을 고른다. 고르지 않았거나 쓸 수 없으면 null. (#1665)
///
/// 사진을 여는 길은 식단 추가와 같다 — 같은 선택기([mealPhotoPickerProvider])가
/// 형식을 바이트로 가리고 HEIC 를 걸러 준다. 웹은 갈래를 나누지 않고 바로
/// 보관함 입력을 연다: iOS Safari 가 그 입력에 보관함·촬영·파일 메뉴를 스스로
/// 띄우므로 앱이 촬영을 따로 두면 같은 갈래가 두 번 나온다(#1433). 네이티브는
/// 보관함과 카메라가 다른 시스템 화면이라 시트에서 고르게 한다.
///
/// 쓸 수 없는 사진(권한 거부·형식·크기)은 그 자리에서 알림으로 말한다 — 올려
/// 봐야 서버가 거절할 사진을 기다리게 하지 않는다.
Future<MealPhoto?> pickCoachPhoto(BuildContext context, WidgetRef ref) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final AppToastHost toast = AppToastHost.of(context);
  final MealPhotoChoiceLayout layout = ref.read(mealPhotoChoiceLayoutProvider);

  final MealPhotoSource? source = layout == MealPhotoChoiceLayout.systemMenu
      ? MealPhotoSource.gallery
      : await showAppSheet<MealPhotoSource>(
          context: Navigator.of(context, rootNavigator: true).context,
          builder: (BuildContext _) => const CoachPhotoSourceSheet(),
        );
  if (source == null) return null;

  final MealPhoto? photo;
  try {
    photo = await ref.read(mealPhotoPickerProvider).pick(source);
  } on MealPhotoException catch (e) {
    toast.show(
      coachPhotoFailureMessage(l, e.failure),
      type: AppToastType.error,
    );
    return null;
  } on Object {
    toast.show(l.coachPhotoReadFailed, type: AppToastType.error);
    return null;
  }
  if (photo == null) return null;
  if (photo.bytes.length > CoachPhotoSendController.maxBytes) {
    toast.show(l.dietPhotoTooLarge, type: AppToastType.error);
    return null;
  }
  return photo;
}

/// 사진을 쓸 수 없는 까닭을 회원에게 할 말로 옮긴다.
///
/// 식단 문구는 "음식 사진"이라 쓰지 않는다 — 여기서는 자세·인바디 사진도 보낸다.
String coachPhotoFailureMessage(AppLocalizations l, MealPhotoFailure failure) =>
    switch (failure) {
      MealPhotoFailure.cameraPermissionDenied ||
      MealPhotoFailure.photoPermissionDenied => l.coachPhotoPermissionDenied,
      MealPhotoFailure.cameraPermissionPermanentlyDenied ||
      MealPhotoFailure.photoPermissionPermanentlyDenied =>
        l.coachPhotoPermissionPermanentlyDenied,
      MealPhotoFailure.cameraPermissionRestricted ||
      MealPhotoFailure.photoPermissionRestricted =>
        l.dietPhotoPermissionRestricted,
      MealPhotoFailure.unsupportedFormat => l.dietPhotoUnsupportedFormat,
      MealPhotoFailure.tooLarge => l.dietPhotoTooLarge,
      MealPhotoFailure.readFailed => l.coachPhotoReadFailed,
    };

/// 네이티브에서 보관함과 카메라 중 하나를 고르는 시트. 고른 갈래를 돌려준다.
///
/// 모양은 식단 추가 시트의 사진 갈래와 같다 — 같은 앱에서 사진을 여는 두 자리가
/// 다르게 생기면 회원은 둘이 다른 일을 한다고 읽는다.
class CoachPhotoSourceSheet extends StatelessWidget {
  const CoachPhotoSourceSheet({super.key});

  static const Key sheetKey = Key('coachPhotoSourceSheet');
  static const Key galleryKey = Key('coachPhotoGallery');
  static const Key cameraKey = Key('coachPhotoCamera');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppSheet(
      key: sheetKey,
      title: l.coachPhotoAttach,
      subtitle: l.coachPhotoSheetSubtitle,
      // 회원 앱의 부분 창은 끌어내려 닫는다 — 식단 추가 시트와 같다.
      showClose: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SourceOption(
            key: galleryKey,
            icon: AppIcons.image,
            title: l.dietPickPhoto,
            subtitle: l.coachPhotoPickSub,
            onTap: () => Navigator.of(context).pop(MealPhotoSource.gallery),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _SourceOption(
            key: cameraKey,
            icon: AppIcons.camera,
            title: l.dietTakePhoto,
            subtitle: l.coachPhotoTakeSub,
            onTap: () => Navigator.of(context).pop(MealPhotoSource.camera),
          ),
        ],
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: AppListRow(
        title: title,
        subtitle: subtitle,
        leading: SizedBox.square(
          dimension: tokens.density.iconButton,
          child: AppIcon(
            icon,
            size: OnCareSize.iconLarge,
            color: tokens.brand.primary,
          ),
        ),
        trailing: const AppIcon(
          AppIcons.chevronRight,
          size: OnCareSize.iconMedium,
          color: OnCareColors.textTertiary,
        ),
      ),
    );
  }
}
