// 식단 추가하기 — 사진·직접 입력을 고르는 시트.

part of '../diet_flows.dart';

/// 고른 사진과 끼니. 사진 선택 시트가 닫히면서 부르는 쪽에 넘긴다.
typedef DietPickedPhoto = ({MealPhoto photo, String mealType});

/// Opens the short photo-source choice as a content-sized bottom sheet.
///
/// **기록이 저장되면 true.** 하단 `+` 로 연 흐름이 저장 성공에만 식단 탭으로
/// 옮겨 가려면, 취소·권한 거부·분석 실패와 저장 성공을 구분해야 한다(#1434).
///
/// [date] 는 새 기록을 남길 날이다(#2849). 식단 탭에서 지난 날짜를 보며 연
/// `식단 추가` 는 그 날짜를 넘긴다 — 사진 분석도 직접 입력도 그 날로 시작한다.
/// 빠지면(하단 `+`) 오늘이다.
Future<bool> showDietAddSheet(BuildContext context, {DateTime? date}) async {
  final Object? choice = await showAppSheet<Object>(
    context: _rootContext(context),
    builder: (BuildContext ctx) => const _DietAddSheet(),
  );
  if (!context.mounted) return false;
  // 다음 화면은 사진 선택 시트가 **닫힌 뒤** 열린다 — 두 시트가 겹치면 뒤엣
  // 것이 스크림 위로 비친다.
  return switch (choice) {
    final DietPickedPhoto picked => showDietResultSheet(
      context,
      picked.photo,
      picked.mealType,
      date: date,
    ),
    _DietAddChoice.manual => openDietManualAddPage(context, date: date),
    _ => false,
  };
}

/// 사진 선택 시트가 사진 말고 돌려주는 것. 머리의 `+ 직접 추가` 다(#2151).
enum _DietAddChoice { manual }

/// Photo-source choice for 식단 추가.
///
/// Owns the picker outcome so a failure can be shown *inside* the sheet: a
/// toast would sit apart from this sheet, and the sheet staying open is what
/// lets the user retry (or open Settings) without restarting the flow.
/// Cancelling the camera/gallery is not a failure — nothing is shown.
class _DietAddSheet extends ConsumerStatefulWidget {
  const _DietAddSheet();

  @override
  ConsumerState<_DietAddSheet> createState() => _DietAddSheetState();
}

class _DietAddSheetState extends ConsumerState<_DietAddSheet> {
  MealPhotoFailure? _failure;

  /// Guards a second tap while the OS picker is up — image_picker rejects a
  /// concurrent request with `multiple_request`.
  bool _picking = false;

  Future<void> _pickAndAnalyze(MealPhotoSource source) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _failure = null;
    });
    final NavigatorState navigator = Navigator.of(context);

    final MealPhoto? photo;
    try {
      photo = await ref.read(mealPhotoPickerProvider).pick(source);
    } on MealPhotoException catch (error) {
      _settle(error.failure);
      return;
    } on Object {
      _settle(MealPhotoFailure.readFailed);
      return;
    }
    // `navigator.mounted` is still true after this sheet is dismissed, so it
    // can't tell us whether the route we're about to pop is ours. Only this
    // State being mounted proves the sheet is still up — without the check a
    // dismiss during the OS picker would pop the page underneath instead.
    if (!mounted) return;
    _settle(null);
    if (photo == null) return; // user cancelled

    // 고른 사진을 부르는 쪽에 넘기고 닫힌다 — 결과 시트는 그쪽이 연다. 이
    // 시트가 직접 열면 부르는 쪽 future 가 결과보다 먼저 끝나, 저장 성공을
    // 알 방법이 없다(#1434).
    navigator.pop((photo: photo, mealType: _currentMealType()));
  }

  void _settle(MealPhotoFailure? failure) {
    if (!mounted) return;
    setState(() {
      _picking = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MealPhotoFailure? failure = _failure;
    final MealPhotoChoiceLayout layout = ref.watch(
      mealPhotoChoiceLayoutProvider,
    );
    return AppSheet(
      key: const Key('dietAddSheet'),
      title: l.dietAddSheetTitle,
      subtitle: l.dietAddSheetSubtitle,
      // 닫기는 끌어내리기 하나로 둔다 — 비운 X 자리에 사진 없이 적는 문을
      // 둔다(#2151). 파란 글씨 `+` 버튼이다.
      showClose: false,
      trailing: AppButton(
        key: const Key('dietManualAddButton'),
        label: l.dietManualAdd,
        leadingIcon: AppIcons.add,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
        // OS 사진 선택기가 떠 있는 동안에는 막는다 — 그 사이 시트를 닫으면
        // 고른 사진이 돌아올 자리가 없다.
        onPressed: _picking
            ? null
            : () => Navigator.of(context).pop(_DietAddChoice.manual),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (failure != null) ...<Widget>[
            _PhotoFailureNotice(failure: failure),
            const SizedBox(height: OnCareSpacing.s12),
          ],
          Column(
            key: const Key('dietAddOptions'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (layout == MealPhotoChoiceLayout.systemMenu)
                // 웹: 브라우저가 보관함·촬영·파일을 묻는 메뉴를 스스로 띄운다.
                // 앱에 촬영을 따로 두면 그 메뉴의 `사진 찍기`와 겹친다(#1433).
                _SourceOption(
                  icon: AppIcons.image,
                  title: l.dietAddPhoto,
                  subtitle: l.dietAddPhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                )
              else ...<Widget>[
                _SourceOption(
                  icon: AppIcons.image,
                  title: l.dietPickPhoto,
                  subtitle: l.dietPickPhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                ),
                const SizedBox(height: OnCareSpacing.s12),
                _SourceOption(
                  icon: AppIcons.camera,
                  title: l.dietTakePhoto,
                  subtitle: l.dietTakePhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.camera),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// In-sheet explanation of why the photo couldn't be used. Only a permanent
/// iOS denial offers Settings; retryable denials and policy restrictions do
/// not send the user somewhere that cannot fix them.
class _PhotoFailureNotice extends StatefulWidget {
  const _PhotoFailureNotice({required this.failure});

  final MealPhotoFailure failure;

  @override
  State<_PhotoFailureNotice> createState() => _PhotoFailureNoticeState();
}

class _PhotoFailureNoticeState extends State<_PhotoFailureNotice> {
  /// Settings wouldn't open — fall back to telling the user the manual path.
  /// A tap that silently does nothing reads as a broken app (#507).
  bool _openSettingsFailed = false;

  bool get _isPermanentlyDenied =>
      widget.failure == MealPhotoFailure.cameraPermissionPermanentlyDenied ||
      widget.failure == MealPhotoFailure.photoPermissionPermanentlyDenied;

  /// Only iOS has a URL that lands on this app's permission screen;
  /// elsewhere the message alone has to do.
  bool get _canOpenAppSettings =>
      _isPermanentlyDenied &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  String _message(AppLocalizations l) => switch (widget.failure) {
    MealPhotoFailure.cameraPermissionDenied => l.dietCameraPermissionDenied,
    MealPhotoFailure.cameraPermissionPermanentlyDenied =>
      l.dietCameraPermissionPermanentlyDenied,
    MealPhotoFailure.cameraPermissionRestricted =>
      l.dietPhotoPermissionRestricted,
    MealPhotoFailure.photoPermissionDenied => l.dietPhotoPermissionDenied,
    MealPhotoFailure.photoPermissionPermanentlyDenied =>
      l.dietPhotoPermissionPermanentlyDenied,
    MealPhotoFailure.photoPermissionRestricted =>
      l.dietPhotoPermissionRestricted,
    MealPhotoFailure.unsupportedFormat => l.dietPhotoUnsupportedFormat,
    MealPhotoFailure.tooLarge => l.dietPhotoTooLarge,
    MealPhotoFailure.readFailed => l.dietPhotoLoadError,
  };

  Future<void> _openSettings() async {
    bool opened = false;
    try {
      // `app-settings:` is a system scheme, so the platform default mode is
      // what lands on this app's permission screen (no external webview).
      opened = await launchUrl(Uri.parse('app-settings:'));
    } on Object {
      opened = false;
    }
    if (!mounted || opened) return;
    setState(() => _openSettingsFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppBanner(
      key: const Key('dietPhotoFailureNotice'),
      tone: AppBannerTone.danger,
      title: _message(l),
      message: _openSettingsFailed ? l.dietOpenSettingsFailed : null,
      actionLabel: _canOpenAppSettings ? l.dietOpenSettings : null,
      onAction: _canOpenAppSettings ? _openSettings : null,
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
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
        // 아이콘 배경은 두지 않는다 — 칸 크기만 남겨 글줄 정렬을 지킨다(#1781).
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
