import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/core/utils/portrait_date_picker.dart';
import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/tokens/breakpoints.dart';
import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/meal_photo_view.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_toast.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart' show wireDate;
import 'package:url_launcher/url_launcher.dart';

/// A single logged food item, with the per-food nutrition shown on the meal
/// card ([sodiumMg] / [sugarG] default to 0 for draft rows in the edit sheet).
class DietFood {
  const DietFood(this.name, this.kcal, {this.sodiumMg = 0, this.sugarG = 0});
  final String name;
  final int kcal;
  final int sodiumMg;
  final double sugarG;
}

/// A nutrient chip on a meal card (`over` = above the daily target → red).
class DietTag {
  const DietTag(this.label, {this.over = false});
  final String label;
  final bool over;
}

/// One meal in the daily log. [id] is the backend entry id (null for a
/// not-yet-persisted draft) and is required to edit or delete the entry.
class DietMeal {
  const DietMeal({
    required this.mealType,
    required this.time,
    required this.total,
    required this.emoji,
    required this.thumbBg,
    required this.items,
    required this.tags,
    required this.sodium,
    required this.sugar,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.aiComment = '',
    this.photoAsset,
    this.photoUrl,
    this.id,
  });

  final MealType mealType;
  final String time;
  final int total;
  final String emoji;
  final Color thumbBg;
  final List<DietFood> items;
  final List<DietTag> tags;
  final int sodium;
  final double sugar;

  /// 그 끼니의 탄·단·지(g). 끼니 카드 아래에 한 줄로 작게 적는다 (#1170) —
  /// 하루 합계는 영양 요약 카드가 말하지만, 어느 끼니가 그 합계를 만들었는지는
  /// 끼니 단위로 봐야 알 수 있다. 트레이너 화면의 같은 카드와 짝이다.
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// Short per-meal AI feedback line shown under the food breakdown.
  final String aiComment;

  /// Bundled photo asset for the thumbnail; null falls back to [emoji].
  final String? photoAsset;

  /// API path of the photo the member uploaded (#699). Wins over
  /// [photoAsset] when present.
  final String? photoUrl;
  final String? id;
}

/// Localized meal-type badge label. The API `meal_type` string is always
/// derived from [MealType.name], never from this display label.
String mealBadge(AppLocalizations l, MealType t) => switch (t) {
  MealType.breakfast => l.dietMealBreakfast,
  MealType.lunch => l.dietMealLunch,
  MealType.dinner => l.dietMealDinner,
  MealType.snack => l.dietMealSnack,
};

/// Best-guess meal type for a new entry, based on the current time of day.
String _currentMealType() {
  final int h = nowKst().hour;
  if (h < 11) return 'breakfast';
  if (h < 15) return 'lunch';
  if (h < 21) return 'dinner';
  return 'snack';
}

Widget _sheetShell(BuildContext context, Widget child, {Key? key}) {
  return ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      // Match the main content width so the sheet scales with the viewport
      // like the tab pages. The theme lifts the modal route cap to this
      // width too (see AppTheme._bottomSheetTheme); this centres the child.
      maxWidth: AppBreakpoints.contentMaxWidth,
    ),
    child: Container(
      key: key,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(top: false, child: child),
    ),
  );
}

Widget _pageShell(Widget child) {
  return Scaffold(
    key: const Key('mealDetailPage'),
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.contentMaxWidth,
          ),
          child: SizedBox.expand(child: child),
        ),
      ),
    ),
  );
}

Widget _sheetHandle() => Container(
  margin: const EdgeInsets.only(top: 12, bottom: 4),
  width: 36,
  height: 4,
  decoration: BoxDecoration(
    color: const Color(0xFFDDE3EA),
    borderRadius: BorderRadius.circular(999),
  ),
);

/// 시트 바닥의 동작 버튼 높이. `저장하기`·`취소` 가 폭만 다르고 세로는 같아야
/// 한 행으로 읽힌다(#1564).
const double _actionHeight = 48;

/// 그램 수치 한 줄. 소수 첫째 자리까지만, 정수는 콤마만 — 칼로리·나트륨 행과
/// 같은 서식이다. 당류와 탄·단·지가 이 함수를 같이 쓴다(#1564).
String _gramsText(double grams) => grams == grams.roundToDouble()
    ? NumberFormat('#,###').format(grams)
    : NumberFormat('#,##0.#').format(grams);

// ─────────────────────────────────────────────────── 식단 추가하기 ──

/// 고른 사진과 끼니. 사진 선택 시트가 닫히면서 부르는 쪽에 넘긴다.
typedef DietPickedPhoto = ({MealPhoto photo, String mealType});

/// Opens the short photo-source choice as a content-sized bottom sheet.
///
/// **기록이 저장되면 true.** 하단 `+` 로 연 흐름이 저장 성공에만 식단 탭으로
/// 옮겨 가려면, 취소·권한 거부·분석 실패와 저장 성공을 구분해야 한다(#1434).
Future<bool> showDietAddSheet(BuildContext context) async {
  final DietPickedPhoto? picked = await showModalBottomSheet<DietPickedPhoto>(
    context: context,
    // Keep the sheet above the main shell's floating buttons even when it is
    // opened from a tab page that has its own nested Navigator.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: FigmaColors.sheetScrim,
    builder: (BuildContext ctx) => const _DietAddSheet(),
  );
  if (picked == null) return false;
  if (!context.mounted) return false;
  // 결과 시트는 사진 선택 시트가 **닫힌 뒤** 열린다 — 두 시트가 겹치면 뒤엣
  // 것이 스크림 위로 비친다.
  return showDietResultSheet(context, picked.photo, picked.mealType);
}

/// Photo-source choice for 식단 추가.
///
/// Owns the picker outcome so a failure can be shown *inside* the sheet: a
/// SnackBar would sit behind this sheet, and the sheet staying open is what
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
    return _sheetShell(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(child: _sheetHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l.dietAddSheetTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: FigmaColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.dietAddSheetSubtitle,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                _CircleClose(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _PhotoFailureNotice(failure: failure),
            ),
          Padding(
            key: const Key('dietAddOptions'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: <Widget>[
                if (layout == MealPhotoChoiceLayout.systemMenu)
                  // 웹: 브라우저가 보관함·촬영·파일을 묻는 메뉴를 스스로 띄운다.
                  // 앱에 촬영을 따로 두면 그 메뉴의 `사진 찍기`와 겹친다(#1433).
                  _SourceOption(
                    icon: Icons.image_outlined,
                    iconBg: FigmaColors.primaryA(0.10),
                    iconColor: FigmaColors.primaryA(0.55),
                    title: l.dietAddPhoto,
                    subtitle: l.dietAddPhotoSub,
                    onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                  )
                else ...<Widget>[
                  // 두 갈래 모두 브랜드 파랑의 농담이다 — 촬영이 진한 쪽(주된
                  // 경로), 갤러리가 옅은 쪽이다.
                  _SourceOption(
                    icon: Icons.image_outlined,
                    iconBg: FigmaColors.primaryA(0.10),
                    iconColor: FigmaColors.primaryA(0.55),
                    title: l.dietPickPhoto,
                    subtitle: l.dietPickPhotoSub,
                    onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                  ),
                  const SizedBox(height: 12),
                  _SourceOption(
                    icon: Icons.photo_camera_outlined,
                    iconBg: FigmaColors.primaryA(0.12),
                    iconColor: FigmaColors.primary,
                    title: l.dietTakePhoto,
                    subtitle: l.dietTakePhotoSub,
                    onTap: () => _pickAndAnalyze(MealPhotoSource.camera),
                  ),
                ],
              ],
            ),
          ),
          // 마지막 카드가 화면 끝(홈 인디케이터)에 닿아 잘려 보이던 것을
          // 띄운다 — 시스템 인셋이 없는 기기에서도 남는 여백이다.
          const SizedBox(height: 20),
        ],
      ),
      key: const Key('dietAddSheet'),
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
  static const Color _warningBg = Color(0xFFFFF1EF);
  static const Color _warningInk = Color(0xFFD1442C);

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
    return Container(
      key: const Key('dietPhotoFailureNotice'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: _warningInk),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _message(l),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _warningInk,
                  ),
                ),
                if (_canOpenAppSettings)
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      onTap: _openSettings,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          l.dietOpenSettings,
                          key: const Key('dietOpenSettingsLink'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: FigmaColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_openSettingsFailed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l.dietOpenSettingsFailed,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: _warningInk,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FigmaColors.primaryA(0.15)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: FigmaColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: FigmaColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────── 분석 완료 ──

/// AI analysis result sheet shown after picking a photo.
/// Runs the real `POST /diet/analyze` on the picked [photo] and shows the
/// recognised foods + nutrition. The backend persists the entry as part of
/// analysis, so a successful result refreshes [dietTodayProvider].
/// 결과 시트. `완료` 까지 마치면 true — 저장된 기록을 확인할 준비가 됐다는
/// 뜻이다(#1434).
Future<bool> showDietResultSheet(
  BuildContext context,
  MealPhoto photo,
  String mealType,
) async {
  final bool? done = await showModalBottomSheet<bool>(
    context: context,
    // 하단 바·+ 버튼이 시트 위로 올라오지 않도록 루트에 올린다. 식단 추가 시트와
    // 같은 규칙이다 — 그 시트가 이 시트를 열므로 둘이 같은 층에 있어야 한다(#791).
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: FigmaColors.sheetScrim,
    builder: (BuildContext ctx) =>
        _ResultSheet(photo: photo, mealType: mealType),
  );
  return done ?? false;
}

class _ResultSheet extends ConsumerStatefulWidget {
  const _ResultSheet({required this.photo, required this.mealType});
  final MealPhoto photo;
  final String mealType;

  @override
  ConsumerState<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends ConsumerState<_ResultSheet> {
  DietAnalysisResult? _result;
  bool _loading = true;
  DietAnalysisFailure? _failure;

  /// 이 기록이 놓인 날. 분석은 저장한 시각의 날짜로 남기므로 처음은 늘 오늘이고,
  /// 지난 식사의 사진을 올린 경우 여기서 실제로 먹은 날로 옮긴다(#1241).
  late DateTime _date = _todayKst();

  /// 날짜를 옮기는 중. 두 번 눌러 같은 기록을 두 날짜로 보내지 않게 막는다.
  bool _movingDate = false;

  bool get _failed => _failure != null;

  static DateTime _todayKst() {
    final DateTime now = nowKst();
    return DateTime(now.year, now.month, now.day);
  }

  // One key per capture, reused across retries so a lost response followed by
  // 「다시 시도」 doesn't record the same meal twice (server dedupes on it).
  late final String _idempotencyKey =
      'diet-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// 분석 중 화면을 최소한 이만큼은 보여 준다.
  ///
  /// 데모(로컬 인터셉터)와 캐시된 재시도는 응답이 즉시 온다. 그대로 두면
  /// 결과가 촬영 직후 튀어나와 AI 가 무엇을 했는지 보이지 않는다(#1564).
  /// 실제 분석이 더 걸리면 기다린 만큼이 그대로 노출 시간이라 이 값은
  /// 아무 일도 하지 않는다 — 늦추는 것이 아니라 바닥을 깔아 두는 값이다.
  static const Duration _minAnalyzing = Duration(milliseconds: 2200);

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      final DietAnalysisResult result = await ref
          .read(dietRepositoryProvider)
          .analyze(
            photo: widget.photo,
            mealType: widget.mealType,
            idempotencyKey: _idempotencyKey,
          );
      if (!mounted) return;
      // analyze() already persisted the entry → refresh the day's summary/list.
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·이번 달)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      await _holdAnalyzing(elapsed);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      // 실패도 같은 바닥을 쓴다 — 즉시 튀어나오는 실패 문구는 사진을 보지도
      // 않고 거절한 것처럼 읽힌다.
      await _holdAnalyzing(elapsed);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = DietAnalysisFailure.fromError(error);
      });
    }
  }

  /// [_minAnalyzing] 에서 이미 지난 만큼을 뺀 나머지를 기다린다.
  Future<void> _holdAnalyzing(Stopwatch elapsed) {
    final Duration left = _minAnalyzing - elapsed.elapsed;
    if (left <= Duration.zero) return Future<void>.value();
    return Future<void>.delayed(left);
  }

  /// 인식 결과를 고치러 그 기록의 수정 화면으로 간다. (#1564)
  ///
  /// 분석이 끝난 시점에 기록은 이미 저장돼 있으므로 여기서 새로 저장할 것은
  /// 없다. 시트는 `false` 로 닫는다 — `true` 는 부르는 쪽에 "식단 탭으로
  /// 옮겨 가라" 는 뜻이라, 수정 화면을 여는 것과 탭 이동이 겹친다.
  void _openEdit() {
    final DietAnalysisResult? result = _result;
    if (result == null || result.entryId.isEmpty) return;
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    unawaited(router.push<void>(AppRoutes.dietEntryDetailPath(result.entryId)));
  }

  /// 기록 날짜를 고쳐 그 날의 식단으로 옮긴다. (#1241)
  ///
  /// 분석이 끝난 시점에 기록은 이미 서버에 남아 있다. 그래서 고른 즉시 옮긴다 —
  /// 시트를 닫는 방법(완료·X·바깥 누르기)이 여럿인데, 저장을 완료 버튼에만
  /// 걸어 두면 화면에 보이는 날짜와 실제로 남은 날짜가 갈린다.
  Future<void> _pickDate() async {
    final DietAnalysisResult? result = _result;
    if (result == null || result.entryId.isEmpty || _movingDate) return;
    final DateTime today = _todayKst();
    final DateTime? picked = await showPortraitDatePicker(
      context: context,
      initialDate: _date,
      // 지난 식사는 얼마든지 올릴 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    final DateTime chosen = DateTime(picked.year, picked.month, picked.day);
    if (chosen == _date) return;

    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime previous = _date;
    setState(() => _movingDate = true);
    try {
      await ref
          .read(dietRepositoryProvider)
          .updateEntry(id: result.entryId, date: wireDate(chosen));
      if (!mounted) return;
      setState(() {
        _date = chosen;
        _movingDate = false;
      });
      // 떠난 날과 도착한 날을 모두 비운다 — 한쪽만 비우면 합계가 두 날에
      // 겹쳐 보이거나 어느 쪽에서도 보이지 않는다.
      ref.invalidate(dietTodayProvider);
      ref.invalidate(dietByDateProvider(previous));
      ref.invalidate(dietByDateProvider(chosen));
      showAppToast(
        context,
        l.dietRecordDateMoved(_dateLabel(context, chosen)),
        kind: AppToastKind.success,
      );
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _movingDate = false);
      showAppToast(context, l.dietRecordDateFailed, kind: AppToastKind.error);
    }
  }

  String _dateLabel(BuildContext context, DateTime date) =>
      DateFormat.yMMMd(
        Localizations.localeOf(context).toString(),
      ).format(date);

  /// Sends the user back to the source picker. The photo they have can't be
  /// analysed, so "다시 시도" would just fail again — the useful next step is
  /// choosing a different one.
  void _pickAnother() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    unawaited(showDietAddSheet(navigator.context));
  }

  /// Takes an expired session back to sign-in.
  ///
  /// Signing out *is* the navigation: `appRouterProvider` refreshes the guard
  /// on every session change, and `sessionRedirect` sends a signed-out user
  /// to `/auth/sign-in`. Pushing that route directly would not work — while
  /// the session still reads as authenticated the guard bounces anyone off
  /// the auth routes back to the dashboard. Clearing the dead token is also
  /// the point: it is what made the request fail.
  Future<void> _signInAgain() async {
    // Read before popping; this State is gone right after.
    final NavigatorState navigator = Navigator.of(context);
    final SessionController session = ref.read(
      sessionControllerProvider.notifier,
    );
    navigator.pop();
    await session.signOut();
  }

  String _failureMessage(AppLocalizations l, DietAnalysisFailure failure) =>
      switch (failure) {
        DietAnalysisFailure.unsupportedFormat =>
          l.dietAnalysisUnsupportedFormat,
        DietAnalysisFailure.badRequest => l.dietAnalysisBadRequest,
        DietAnalysisFailure.unauthorized => l.dietAnalysisUnauthorized,
        DietAnalysisFailure.notImplemented => l.dietAnalysisNotImplemented,
        // 502 and transport failures share the "try again shortly" wording —
        // from the user's side both are "it broke, not your photo".
        DietAnalysisFailure.recognitionFailed ||
        DietAnalysisFailure.temporary => l.dietAnalysisFailedBody,
      };

  /// The button only offers a retry when one can actually succeed; otherwise
  /// it moves the user to the step that can (a different photo), or just
  /// closes when nothing in this sheet will help.
  VoidCallback _failureAction(DietAnalysisFailure failure) {
    if (failure.canRetry) return _run;
    return switch (failure) {
      DietAnalysisFailure.unsupportedFormat ||
      DietAnalysisFailure.badRequest => _pickAnother,
      DietAnalysisFailure.unauthorized => () => unawaited(_signInAgain()),
      _ => () => Navigator.of(context).pop(),
    };
  }

  String _failureActionLabel(AppLocalizations l, DietAnalysisFailure failure) {
    if (failure.canRetry) return l.actionRetry;
    return switch (failure) {
      DietAnalysisFailure.unsupportedFormat ||
      DietAnalysisFailure.badRequest => l.dietAnalysisPickAnother,
      DietAnalysisFailure.unauthorized => l.dietAnalysisSignIn,
      _ => l.dietAnalysisClose,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return _sheetShell(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(child: _sheetHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: <Widget>[
                const OniAvatar(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _loading
                            ? l.dietAnalyzing
                            : _failed
                            ? l.dietAnalysisFailed
                            : l.dietAnalysisDone,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: FigmaColors.ink,
                        ),
                      ),
                      Text(
                        l.dietAiNutritionResult,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: FigmaColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // 닫기는 아래 `취소` 버튼 하나로 모은다 — 머리의 X 와 둘이
                // 있으면 같은 일을 하는 자리가 화면에 둘이다(#1564).
              ],
            ),
          ),
          // 결과가 길어지면 시트 안에서 스크롤한다 — 탄·단·지 줄이 붙으면서
          // 작은 화면에서는 버튼이 시트 밖으로 밀렸다(#1432).
          Flexible(
            child: SingleChildScrollView(
              // 아래 여백이 없으면 버튼이 시트 끝에 붙는다(#1564).
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final AppLocalizations l = AppLocalizations.of(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          key: const Key('diet-result-analyzing'),
          children: <Widget>[
            const _AnalyzingPulse(),
            const SizedBox(height: 18),
            Text(
              l.dietAnalyzingBody,
              style: const TextStyle(fontSize: 14, color: AppColors.foreground),
            ),
            const SizedBox(height: 10),
            const _AnalyzingDots(),
          ],
        ),
      );
    }
    if (_failed || _result == null) {
      // `_result == null` without a classified failure shouldn't happen, but
      // treating it as temporary keeps a retry available instead of a dead end.
      final DietAnalysisFailure failure =
          _failure ?? DietAnalysisFailure.temporary;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: <Widget>[
            Text(
              _failureMessage(l, failure),
              key: const Key('dietAnalysisFailureBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('dietAnalysisFailureAction'),
                onPressed: _failureAction(failure),
                style: FilledButton.styleFrom(
                  backgroundColor: FigmaColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _failureActionLabel(l, failure),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final DietAnalysisResult r = _result!;
    final String recognized = r.foods
        .map((RecognizedFood f) => f.name)
        .join(' · ');
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          decoration: BoxDecoration(
            color: FigmaColors.softBlue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.dietRecognizedFood,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: FigmaColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recognized.isEmpty ? l.dietNoRecognizedFood : recognized,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: FigmaColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              // 잘못 읽은 메뉴를 그 자리에서 고치러 간다(#1564). 인식 결과 옆이
              // 아니면 저장한 뒤 목록에서 다시 찾아 들어가야 한다.
              TextButton(
                key: const Key('diet-result-edit'),
                onPressed: r.entryId.isEmpty ? null : _openEdit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l.actionEdit,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: FigmaColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 기록 날짜 — 기본은 오늘이고, 지난 식사의 사진이면 그 날로 옮긴다(#1241).
        Row(
          children: <Widget>[
            Text(
              l.dietRecordDate,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _dateLabel(context, _date),
                key: const Key('diet-result-date'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: FigmaColors.ink,
                ),
              ),
            ),
            if (_movingDate)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                key: const Key('diet-result-date-change'),
                onPressed: () => unawaited(_pickDate()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  l.dietRecordDateChange,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: FigmaColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l.dietNutritionResult,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.foreground,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ResultRow(
          label: l.dietCalories,
          value: '${r.totalCalories}',
          unit: l.unitKcal,
        ),
        const SizedBox(height: 8),
        _ResultRow(
          label: l.dietSodium,
          value: '${r.totalSodiumMg}',
          unit: l.dietUnitMg,
        ),
        const SizedBox(height: 8),
        _ResultRow(
          label: l.dietSugar,
          // 서버가 준 double 을 그대로 문자열로 만들면 29.497999999999998 이
          // 찍힌다 — 칼로리·나트륨과 같은 서식으로 맞춘다(#1564).
          value: _gramsText(r.totalSugarG),
          unit: l.dietUnitG,
        ),
        const SizedBox(height: 8),
        // 탄·단·지는 칼로리를 나눈 것이라 한 줄에 묶는다 — 나트륨·당류처럼
        // 따로 세우면 같은 칼로리를 설명하는 값이라는 것이 보이지 않는다.
        // 색·이름·단위는 식단 탭의 기존 규칙 그대로다(#1432).
        _MacroRow(
          key: const Key('diet-result-macros'),
          carbsG: r.totalCarbsG,
          proteinG: r.totalProteinG,
          fatG: r.totalFatG,
        ),
        if (r.coachComment.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            key: const Key('diet-result-coach-comment'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // AI 가 쓴 말은 수치 카드와 같은 회색이면 서버가 잰 값처럼
              // 읽힌다. AI 조언 카드와 같은 옅은 파랑을 쓴다(#1432).
              color: FigmaColors.softBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: 8),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 15,
                    color: FigmaColors.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    r.coachComment,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // 저장하기가 넓고 취소가 좁다 — 둘이 같은 폭이면 무엇이 기본 동작인지
        // 사라진다. 세로는 같게 맞춘다(#1564).
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: SizedBox(
                height: _actionHeight,
                child: FilledButton(
                  key: const Key('diet-result-save'),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                    showAppToast(
                      context,
                      l.dietSaved,
                      kind: AppToastKind.success,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: FigmaColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l.dietSaveEntry,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: _actionHeight,
                child: OutlinedButton(
                  key: const Key('diet-result-cancel'),
                  // 머리에 있던 X 와 같은 동작 — 저장은 이미 끝났고, 이 버튼은
                  // 시트를 닫기만 한다.
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FigmaColors.primary,
                    side: const BorderSide(color: FigmaColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l.dietCancel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 탄·단·지 한 줄. 값 셋이 한 칼로리를 나눈 것이라 한 상자 안에 나란히 선다.
///
/// 색 네모(그래프 범례)는 두지 않는다 — 이 줄에는 대응하는 그래프가 없어
/// 색이 가리킬 곳이 없고, 라벨만 오른쪽으로 밀어냈다(#1564). 수치는 칼로리·
/// 나트륨·당류 행과 같은 규칙이다: 숫자는 파랑 볼드, 단위는 회색.
///
/// 서버가 0 을 주면 0 을 적는다: 값을 감추면 분석이 그 영양소를 재지 못한
/// 것인지 정말 0 인지 알 수 없다.
class _MacroRow extends StatelessWidget {
  const _MacroRow({
    super.key,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });

  final double carbsG;
  final double proteinG;
  final double fatG;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<({String label, double grams})> parts =
        <({String label, double grams})>[
          (label: l.homeMacroCarbs, grams: carbsG),
          (label: l.homeMacroProtein, grams: proteinG),
          (label: l.homeMacroFat, grams: fatG),
        ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: FigmaColors.statBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          for (final part in parts)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    part.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          _gramsText(part.grams),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: FigmaColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        l.dietUnitG,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 분석 중 링. 브랜드 색 링이 돌면서 옅은 원이 함께 숨을 쉰다 — 멈춘 그림이
/// 아니라 지금 무언가 돌아가고 있다는 신호다(#1564).
class _AnalyzingPulse extends StatefulWidget {
  const _AnalyzingPulse();

  @override
  State<_AnalyzingPulse> createState() => _AnalyzingPulseState();
}

class _AnalyzingPulseState extends State<_AnalyzingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _c,
            builder: (BuildContext context, Widget? child) {
              final double t = Curves.easeInOut.transform(_c.value);
              return Container(
                width: 40 + 20 * t,
                height: 40 + 20 * t,
                decoration: BoxDecoration(
                  color: FigmaColors.softBlue.withValues(alpha: 1 - 0.7 * t),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: FigmaColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 분석 중 점 셋. 차례로 밝아지며 흐른다.
class _AnalyzingDots extends StatefulWidget {
  const _AnalyzingDots();

  @override
  State<_AnalyzingDots> createState() => _AnalyzingDotsState();
}

class _AnalyzingDotsState extends State<_AnalyzingDots>
    with SingleTickerProviderStateMixin {
  static const int _count = 3;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int i = 0; i < _count; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Opacity(
                  // 점마다 위상을 어긋내 한 방향으로 흐르게 한다.
                  opacity: 0.25 + 0.75 * _wave((_c.value + i / _count) % 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: FigmaColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 0→1→0 한 번. 앞뒤가 이어져야 매 바퀴 눈에 띄는 끊김이 없다.
  static double _wave(double t) =>
      Curves.easeInOut.transform(t < 0.5 ? t * 2 : (1 - t) * 2);
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: FigmaColors.statBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: FigmaColors.ink,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: FigmaColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────── 식사 수정 ──

/// Opens meal details as a full page above the member tab shell.
Future<void> openMealDetailPage(BuildContext context, DietMeal meal) {
  final String? id = meal.id;
  if (id == null) return Future<void>.value();
  return context.push<void>(AppRoutes.dietEntryDetailPath(id), extra: meal);
}

/// Full-page meal editor. [initialMeal] makes the first transition immediate;
/// when a web URL is refreshed, the same meal is restored from today's data.
class DietMealDetailPage extends ConsumerWidget {
  const DietMealDetailPage({
    super.key,
    required this.entryId,
    this.initialMeal,
  });

  final String entryId;
  final DietMeal? initialMeal;

  DietMeal _fromEntry(DietEntry entry) => DietMeal(
    id: entry.id,
    mealType: entry.mealType,
    time: entry.timeLabel,
    total: entry.totalCalories,
    emoji: '',
    thumbBg: Colors.white,
    photoAsset: entry.photoAsset,
    photoUrl: entry.photoUrl,
    aiComment: entry.aiComment,
    items: <DietFood>[
      for (final FoodItem food in entry.foods)
        DietFood(
          food.name,
          food.calories,
          sodiumMg: food.sodiumMg,
          sugarG: food.sugarG,
        ),
    ],
    tags: const <DietTag>[],
    sodium: entry.sodiumMg,
    sugar: entry.sugarG,
    carbsG: entry.carbsG,
    proteinG: entry.proteinG,
    fatG: entry.fatG,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DietMeal? supplied = initialMeal;
    if (supplied != null && supplied.id == entryId) {
      return _MealEditSheet(meal: supplied);
    }

    final AppLocalizations l = AppLocalizations.of(context);
    return ref
        .watch(dietTodayProvider)
        .when(
          data: (DietDay day) {
            for (final DietEntry entry in day.entries) {
              if (entry.id == entryId) {
                return _MealEditSheet(meal: _fromEntry(entry));
              }
            }
            return _MealDetailUnavailable(message: l.dietLoadError);
          },
          loading: () => const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _MealDetailUnavailable(message: l.dietLoadError),
        );
  }
}

class _MealDetailUnavailable extends StatelessWidget {
  const _MealDetailUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white),
      body: Center(child: Text(message)),
    );
  }
}

class _MealEditSheet extends ConsumerStatefulWidget {
  const _MealEditSheet({required this.meal});
  final DietMeal meal;

  @override
  ConsumerState<_MealEditSheet> createState() => _MealEditSheetState();
}

class _MealEditSheetState extends ConsumerState<_MealEditSheet> {
  static const List<MealType> _types = MealType.values;
  late MealType _type = widget.meal.mealType;
  late List<DietFood> _foods = List<DietFood>.of(widget.meal.items);
  bool _busy = false;

  int get _total => _foods.fold(0, (int a, DietFood f) => a + f.kcal);

  Future<void> _save() async {
    final String? id = widget.meal.id;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    if (id == null) {
      navigator.pop();
      return;
    }
    setState(() => _busy = true);
    try {
      // Drop empty draft rows (see `dietNewFood` placeholder) so a
      // translation string never lands in stored food names.
      final List<FoodItem> foods = <FoodItem>[
        for (final DietFood f in _foods)
          if (f.name.trim().isNotEmpty)
            FoodItem(name: f.name.trim(), calories: f.kcal),
      ];
      await ref
          .read(dietRepositoryProvider)
          .updateEntry(
            id: id,
            mealType: _type.name,
            foods: foods,
            totalCalories: foods.fold<int>(
              0,
              (int a, FoodItem f) => a + f.calories,
            ),
          );
      // Sheet dismissed mid-save → don't pop the page below.
      if (!mounted) return;
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·이번 달)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      navigator.pop();
      toast.show(l.dietSaved, kind: AppToastKind.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      toast.show(l.dietSaveFailed, kind: AppToastKind.error);
    }
  }

  Future<void> _confirmDelete() async {
    final String? id = widget.meal.id;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(l.dietDeleteTitle),
            content: Text(l.dietDeleteConfirm),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.dietCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B30),
                ),
                child: Text(l.dietDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).deleteEntry(id);
      // Sheet dismissed mid-delete → don't pop the page below.
      if (!mounted) return;
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·이번 달)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      navigator.pop();
      toast.show(l.dietDeleted, kind: AppToastKind.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      toast.show(l.dietDeleteFailed, kind: AppToastKind.error);
    }
  }

  /// 수정 화면 상단의 큰 끼니 사진. 200 → 300 으로 키웠다 (#1125) — 이 화면에
  /// 들어온 이유가 대개 "무엇을 먹었는지 다시 보려고" 라, 사진이 주인공이다.
  MealPhotoView get _photo => MealPhotoView(
    photoUrl: widget.meal.photoUrl,
    photoAsset: widget.meal.photoAsset,
    emoji: widget.meal.emoji,
    background: widget.meal.thumbBg,
    width: double.infinity,
    height: 300,
    borderRadius: 16,
    emojiSize: 96,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // Block back/drag dismiss while a save/delete request is in flight.
    final Widget page = _pageShell(
      Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: <Widget>[
                _CircleClose(
                  icon: Icons.arrow_back,
                  onTap: _busy ? null : () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    l.dietMealSheetTitle(mealBadge(l, widget.meal.mealType)),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: FigmaColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _save,
                  child: Text(
                    l.dietSave,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: FigmaColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: <Widget>[
                // 무엇을 고치는 끼니인지 사진으로 먼저 알아본다 — 숫자를
                // 고치기 전에 눈으로 확인하는 순서가 자연스럽다. 사진이 없는
                // 끼니는 큰 이모지 자리를 만들지 않고 지금까지처럼 연다. (#1053)
                if (_photo.hasPhoto) ...<Widget>[
                  _photo,
                  const SizedBox(height: 12),
                ],
                _card(<Widget>[
                  _FieldLabel(l.dietMealInfo),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      for (final MealType t in _types) ...<Widget>[
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: _type == t,
                            child: GestureDetector(
                              onTap: () => setState(() => _type = t),
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _type == t
                                      ? FigmaColors.primaryA(0.10)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _type == t
                                        ? FigmaColors.primary
                                        : FigmaColors.hairline,
                                  ),
                                ),
                                child: Text(
                                  mealBadge(l, t),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _type == t
                                        ? FigmaColors.primary
                                        : AppColors.mutedForeground,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (t != _types.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _FieldLabel(l.dietEatenTime),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: FigmaColors.statBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.schedule,
                              size: 14,
                              color: FigmaColors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.meal.time,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: FigmaColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 12),
                _card(<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: _FieldLabel(l.dietEatenFood)),
                      Semantics(
                        button: true,
                        child: GestureDetector(
                          onTap: () => setState(
                            () => _foods = <DietFood>[
                              ..._foods,
                              // Empty draft name; the localized label is shown
                              // only as a placeholder and is validated out on save.
                              const DietFood('', 0),
                            ],
                          ),
                          child: Text(
                            l.dietAddFood,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: FigmaColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.dietEditFoodHint,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (int i = 0; i < _foods.length; i++) ...<Widget>[
                    _FoodRow(
                      index: i + 1,
                      food: _foods[i],
                      onDelete: () => setState(
                        () => _foods = <DietFood>[..._foods]..removeAt(i),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Divider(height: 16, color: FigmaColors.hairline),
                  Row(
                    children: <Widget>[
                      Text(
                        l.dietTotalCalories,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$_total ${l.unitKcal}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: FigmaColors.primary,
                        ),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 12),
                _card(<Widget>[
                  _FieldLabel(l.dietNutritionInfo),
                  const SizedBox(height: 4),
                  Text(
                    l.dietEditNutritionHint,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _NutrientRow(
                    label: l.dietSodium,
                    hint: l.dietSodiumHint,
                    value: '${widget.meal.sodium}',
                    unit: l.dietUnitMg,
                  ),
                  const SizedBox(height: 10),
                  _NutrientRow(
                    label: l.dietSugar,
                    hint: l.dietSugarHint,
                    value: '${widget.meal.sugar}',
                    unit: l.dietUnitG,
                  ),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _confirmDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B30),
                  side: const BorderSide(color: Color(0x33FF3B30)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                  l.dietDeleteMeal,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return PopScope(canPop: !_busy, child: page);
  }

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: FigmaColors.statBg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: FigmaColors.ink,
    ),
  );
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.index,
    required this.food,
    required this.onDelete,
  });
  final int index;
  final DietFood food;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FigmaColors.hairline),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: FigmaColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              food.name.trim().isEmpty ? l.dietNewFood : food.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: FigmaColors.ink,
              ),
            ),
          ),
          Text(
            '${food.kcal}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: FigmaColors.ink,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            l.unitKcal,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: l.a11yRemoveFood,
            child: GestureDetector(
              onTap: onDelete,
              child: const Icon(
                Icons.cancel,
                size: 18,
                color: Color(0xFFFFB4A8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.unit,
  });
  final String label;
  final String hint;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FigmaColors.hairline),
      ),
      child: Row(
        children: <Widget>[
          Container(width: 3, height: 34, color: FigmaColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FigmaColors.ink,
                  ),
                ),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: FigmaColors.ink,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleClose extends StatelessWidget {
  const _CircleClose({required this.onTap, this.icon = Icons.close});
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F6F8),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // 아이콘만 있는 버튼이라 무엇을 닫는지 말할 데가 없다(#972).
        child: Tooltip(
          message: MaterialLocalizations.of(context).closeButtonTooltip,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 16, color: FigmaColors.textSub),
          ),
        ),
      ),
    );
  }
}
