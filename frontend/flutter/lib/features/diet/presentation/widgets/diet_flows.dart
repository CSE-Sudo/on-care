import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/meal_photo_view.dart';
import 'package:oncare/features/my_health/presentation/points_reward.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart'
    show wireDate;
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A single logged food item, with the per-food nutrition shown on the meal
/// card (all nutrition defaults to 0 for draft rows in the edit sheet).
///
/// 끼니 단위 탄단지는 이 값들의 합계로 만들어진다(`local_api_interceptor` 의
/// `_sumMacro`). 그래서 수정 화면이 이 필드를 하나라도 흘리면 저장한 순간
/// 그 끼니의 영양 정보가 통째로 0 이 된다(#1853).
class DietFood {
  const DietFood(
    this.name,
    this.kcal, {
    this.sodiumMg = 0,
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });
  final String name;
  final int kcal;
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;
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

/// 역할 글자 + 색. 크기·굵기 숫자는 적지 않는다(#1690).
TextStyle _text(BuildContext context, TextStyle role, Color color) =>
    context.oncare.text(role).copyWith(color: color);

/// 그램 수치 한 줄. 소수 첫째 자리까지만, 정수는 콤마만 — 칼로리·나트륨 행과
/// 같은 서식이다. 당류와 탄·단·지가 이 함수를 같이 쓴다(#1564).
String _gramsText(double grams) => grams == grams.roundToDouble()
    ? NumberFormat('#,###').format(grams)
    : NumberFormat('#,##0.#').format(grams);

/// 하단 내비·`+` 버튼 위에 뜨도록 루트 내비게이터에서 연다(#791). 탭 페이지는
/// 자기 내비게이터를 따로 갖고 있어, 그 안에서 열면 하단 바가 시트 위로 올라온다.
BuildContext _rootContext(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).context;

// ─────────────────────────────────────────────────── 식단 추가하기 ──

/// 고른 사진과 끼니. 사진 선택 시트가 닫히면서 부르는 쪽에 넘긴다.
typedef DietPickedPhoto = ({MealPhoto photo, String mealType});

/// Opens the short photo-source choice as a content-sized bottom sheet.
///
/// **기록이 저장되면 true.** 하단 `+` 로 연 흐름이 저장 성공에만 식단 탭으로
/// 옮겨 가려면, 취소·권한 거부·분석 실패와 저장 성공을 구분해야 한다(#1434).
Future<bool> showDietAddSheet(BuildContext context) async {
  final DietPickedPhoto? picked = await showAppSheet<DietPickedPhoto>(
    context: _rootContext(context),
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

// ─────────────────────────────────────────────────── 분석 완료 ──

/// AI analysis result sheet shown after picking a photo.
/// Runs the real `POST /diet/analyze` on the picked [photo] and shows the
/// recognised foods + nutrition. The backend persists the entry as part of
/// analysis, so a successful result refreshes [dietTodayProvider].
/// 결과 시트. `저장하기` 까지 마치면 true — 저장된 기록을 확인할 준비가 됐다는
/// 뜻이다(#1434).
Future<bool> showDietResultSheet(
  BuildContext context,
  MealPhoto photo,
  String mealType,
) async {
  final bool? done = await showAppSheet<bool>(
    // 하단 바·+ 버튼이 시트 위로 올라오지 않도록 루트에 올린다. 식단 추가 시트와
    // 같은 규칙이다 — 둘이 같은 층에 있어야 한다(#791).
    context: _rootContext(context),
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
  static const Duration _minAnalyzingDelay = Duration(milliseconds: 2200);

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
      // 저장과 함께 포인트도 적립됐다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
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

  /// [_minAnalyzingDelay] 에서 이미 지난 만큼을 뺀 나머지를 기다린다.
  Future<void> _holdAnalyzing(Stopwatch elapsed) {
    final Duration left = _minAnalyzingDelay - elapsed.elapsed;
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
  /// 시트를 닫는 방법이 여럿인데, 저장을 한 버튼에만 걸어 두면 화면에 보이는
  /// 날짜와 실제로 남은 날짜가 갈린다.
  Future<void> _pickDate() async {
    final DietAnalysisResult? result = _result;
    if (result == null || result.entryId.isEmpty || _movingDate) return;
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
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
        type: AppToastType.success,
      );
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _movingDate = false);
      showAppToast(context, l.dietRecordDateFailed, type: AppToastType.error);
    }
  }

  String _dateLabel(BuildContext context, DateTime date) =>
      DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);

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

  /// 저장은 분석 때 이미 끝났다 — 시트를 `true` 로 닫고 알린다.
  void _finish() {
    final AppLocalizations l = AppLocalizations.of(context);
    // 시트가 닫힌 뒤에도 토스트를 띄울 수 있는 자리를 먼저 잡아 둔다. 내비게이터
    // 자신의 context 는 그 내비게이터의 오버레이보다 위라, 거기서 오버레이를 찾으면
    // 바깥 내비게이터가 없는 화면에서 실패한다 — 닫기 전에 손잡이를 잡는다.
    final AppToastHost toast = AppToastHost.of(context);
    Navigator.of(context).pop(true);
    toast.show(
      l.dietSaved,
      type: AppToastType.success,
      // 받은 포인트가 있으면 ★ +50P 가 반짝인다. 한도를 넘었으면 저장 알림만.
      rewardLabel: pointsRewardLabel(l, _result?.points),
    );
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

  /// `_result == null` without a classified failure shouldn't happen, but
  /// treating it as temporary keeps a retry available instead of a dead end.
  DietAnalysisFailure get _shownFailure =>
      _failure ?? DietAnalysisFailure.temporary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppSheet(
      title: _loading
          ? l.dietAnalyzing
          : _failed
          ? l.dietAnalysisFailed
          : l.dietAnalysisDone,
      subtitle: l.dietAiNutritionResult,
      // 닫기는 아래 `취소` 버튼 하나로 모은다 — 머리의 X 와 둘이 있으면 같은
      // 일을 하는 자리가 화면에 둘이다(#1564).
      showClose: false,
      // 결과가 길어지면 시트 안에서만 스크롤하고 버튼은 바닥에 붙어 있다(#1432).
      footer: _footer(l),
      child: _body(),
    );
  }

  Widget? _footer(AppLocalizations l) {
    if (_loading) return null;
    if (_failed || _result == null) {
      final DietAnalysisFailure failure = _shownFailure;
      return AppButton(
        key: const Key('dietAnalysisFailureAction'),
        label: _failureActionLabel(l, failure),
        onPressed: _failureAction(failure),
        fullWidth: true,
      );
    }
    // [취소] 왼쪽, [저장하기] 오른쪽 — 앱의 모든 하단 두 버튼과 같은 순서다(#1690).
    return AppButtonPair(
      cancelLabel: l.dietCancel,
      // 저장은 이미 끝났고, 이 버튼은 시트를 닫기만 한다.
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: l.dietSaveEntry,
      onConfirm: _finish,
    );
  }

  Widget _body() {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    if (_loading) {
      return Column(
        key: const Key('diet-result-analyzing'),
        children: <Widget>[
          const AppLoading(placement: AppStatePlacement.card),
          Text(
            l.dietAnalyzingBody,
            textAlign: TextAlign.center,
            style: _text(
              context,
              OnCareTypography.body,
              OnCareColors.textPrimary,
            ),
          ),
        ],
      );
    }
    if (_failed || _result == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s20),
        child: Text(
          _failureMessage(l, _shownFailure),
          key: const Key('dietAnalysisFailureBody'),
          textAlign: TextAlign.center,
          style: _text(
            context,
            OnCareTypography.body,
            OnCareColors.textPrimary,
          ),
        ),
      );
    }

    final DietAnalysisResult r = _result!;
    final String recognized = r.foods
        .map((RecognizedFood f) => f.name)
        .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTile(
          tone: AppTileTone.none,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.dietRecognizedFood,
                      style: _text(
                        context,
                        OnCareTypography.strong(OnCareTypography.caption),
                        tokens.brand.primary,
                      ),
                    ),
                    const SizedBox(height: OnCareSpacing.s4),
                    Text(
                      recognized.isEmpty ? l.dietNoRecognizedFood : recognized,
                      style: _text(
                        context,
                        OnCareTypography.titleSmall,
                        OnCareColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              // 잘못 읽은 메뉴를 그 자리에서 고치러 간다(#1564).
              AppButton(
                key: const Key('diet-result-edit'),
                label: l.actionEdit,
                onPressed: r.entryId.isEmpty ? null : _openEdit,
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
              ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        // 기록 날짜 — 기본은 오늘이고, 지난 식사의 사진이면 그 날로 옮긴다(#1241).
        Row(
          children: <Widget>[
            Text(
              l.dietRecordDate,
              style: _text(
                context,
                OnCareTypography.label,
                OnCareColors.textSecondary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s12),
            Expanded(
              child: Text(
                _dateLabel(context, _date),
                key: const Key('diet-result-date'),
                style: _text(
                  context,
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                  OnCareColors.textPrimary,
                ),
              ),
            ),
            if (_movingDate)
              const AppLoading.inline()
            else
              AppButton(
                key: const Key('diet-result-date-change'),
                label: l.dietRecordDateChange,
                onPressed: () => unawaited(_pickDate()),
                variant: AppButtonVariant.text,
                size: OnCareButtonSize.small,
              ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        Text(
          l.dietNutritionResult,
          style: _text(
            context,
            OnCareTypography.label,
            OnCareColors.textSecondary,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        _ResultRow(
          label: l.dietCalories,
          value: '${r.totalCalories}',
          unit: l.unitKcal,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        _ResultRow(
          label: l.dietSodium,
          value: '${r.totalSodiumMg}',
          unit: l.dietUnitMg,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        _ResultRow(
          label: l.dietSugar,
          // 서버가 준 double 을 그대로 문자열로 만들면 29.497999999999998 이
          // 찍힌다 — 칼로리·나트륨과 같은 서식으로 맞춘다(#1564).
          value: _gramsText(r.totalSugarG),
          unit: l.dietUnitG,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 탄·단·지는 칼로리를 나눈 것이라 한 줄에 묶는다(#1432).
        _MacroRow(
          key: const Key('diet-result-macros'),
          carbsG: r.totalCarbsG,
          proteinG: r.totalProteinG,
          fatG: r.totalFatG,
        ),
        if (r.coachComment.isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          // AI 가 쓴 말은 AI 조언 카드와 같은 옅은 브랜드 채움이다(#1432).
          AppTile(
            key: const Key('diet-result-coach-comment'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppIcon(
                  AppIcons.ai,
                  size: OnCareSize.iconSmall,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    r.coachComment,
                    style: _text(
                      context,
                      OnCareTypography.bodySmall,
                      OnCareColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 탄·단·지 한 줄. 값 셋이 한 칼로리를 나눈 것이라 한 타일 안에 나란히 선다.
///
/// 색 견본은 두지 않는다 — 이 줄에는 대응하는 그래프가 없다(#1564). 수치는
/// 칼로리·나트륨·당류 행과 같은 규칙이다: 숫자는 브랜드 색, 단위는 보조 색.
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
    final OnCareTokens tokens = context.oncare;
    final List<({String label, double grams})> parts =
        <({String label, double grams})>[
          (label: l.homeMacroCarbs, grams: carbsG),
          (label: l.homeMacroProtein, grams: proteinG),
          (label: l.homeMacroFat, grams: fatG),
        ];
    return AppTile(
      tone: AppTileTone.none,
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
                    style: _text(
                      context,
                      OnCareTypography.strong(OnCareTypography.caption),
                      OnCareColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: OnCareSpacing.s2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          _gramsText(part.grams),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OnCareTypography.numeric(
                            _text(
                              context,
                              OnCareTypography.titleSmall,
                              tokens.brand.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: OnCareSpacing.s4),
                      Text(
                        l.dietUnitG,
                        style: _text(
                          context,
                          OnCareTypography.bodySmall,
                          OnCareColors.textSecondary,
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
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: OnCareTypography.numeric(
              _text(context, OnCareTypography.titleSmall, tokens.brand.primary),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: _text(
              context,
              OnCareTypography.bodySmall,
              OnCareColors.textSecondary,
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
    thumbBg: OnCareColors.surfaceInput,
    photoAsset: entry.photoAsset,
    photoUrl: entry.photoUrl,
    aiComment: entry.aiComment,
    // 웹에서 새로고침해 들어오면 `initialMeal` 없이 이 경로로 복원된다 —
    // 여기서도 영양을 하나도 흘리지 않아야 저장 뒤에 합계가 남는다(#1853).
    items: <DietFood>[
      for (final FoodItem food in entry.foods)
        DietFood(
          food.name,
          food.calories,
          sodiumMg: food.sodiumMg,
          sugarG: food.sugarG,
          carbsG: food.carbsG,
          proteinG: food.proteinG,
          fatG: food.fatG,
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
            backgroundColor: OnCareColors.surfaceCard,
            body: AppLoading(),
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
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: ''),
      body: AppEmptyState(title: message, icon: AppIcons.error),
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

  /// 이 화면은 보기로 열리고, 머리의 연필을 눌러야 입력 칸이 된다(#1856).
  /// 대부분은 무엇을 먹었는지 다시 보려고 들어오지 고치려고 들어오지 않는다.
  bool _editing = false;

  /// 음식 줄마다 하나씩. 컨트롤러를 줄 위젯이 아니라 시트가 들고 있어야
  /// 한 자 칠 때마다 새로 만들어지지 않는다 — 새로 만들면 커서가 맨 앞으로
  /// 튄다. 목록 순서와 1:1 로 붙어 다닌다(#1844).
  late final List<_FoodEditors> _editors = <_FoodEditors>[
    for (final DietFood f in _foods) _FoodEditors.of(f),
  ];

  /// 수정 화면 상단의 큰 끼니 사진 높이 (#1125) — 이 화면에 들어온 이유가 대개
  /// "무엇을 먹었는지 다시 보려고" 라, 사진이 주인공이다.
  static const double _photoHeight = 300;

  int get _total => _foods.fold(0, (int a, DietFood f) => a + f.kcal);

  // 영양 합계는 저장된 끼니가 아니라 지금 화면의 음식에서 낸다. 서버도 같은
  // 규칙으로 합치므로(`_sumMacro`), 음식을 고치면 저장 전에도 합계가 따라와야
  // 한 화면에 서로 다른 숫자가 남지 않는다(#1856).
  double _sumOf(double Function(DietFood) pick) =>
      _foods.fold<double>(0, (double a, DietFood f) => a + pick(f));

  double get _carbs => _sumOf((DietFood f) => f.carbsG);
  double get _protein => _sumOf((DietFood f) => f.proteinG);
  double get _fat => _sumOf((DietFood f) => f.fatG);
  double get _sugar => _sumOf((DietFood f) => f.sugarG);
  int get _sodium => _foods.fold(0, (int a, DietFood f) => a + f.sodiumMg);

  @override
  void dispose() {
    for (final _FoodEditors e in _editors) {
      e.dispose();
    }
    super.dispose();
  }

  /// 빈 칸과 알아볼 수 없는 글자는 0 으로 읽는다 — 칸을 비워 지우는 것이
  /// 0 을 적는 것과 같은 뜻이 되게.
  static int _asInt(TextEditingController c) =>
      int.tryParse(c.text.trim()) ?? 0;
  static double _asDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  /// 그 음식의 입력 칸을 모두 읽어 `_foods` 에 반영한다. 한 칸만 바뀌어도
  /// 전부 다시 읽는 편이 칸마다 따로 갈래를 두는 것보다 흘릴 값이 없다.
  /// 매 글자마다 부르는 이유는 아래 총 칼로리와 영양 정보 합계가 입력을
  /// 곧바로 따라와야 하기 때문이다.
  void _syncFood(int index) {
    final _FoodEditors e = _editors[index];
    setState(() {
      _foods = <DietFood>[..._foods]
        ..[index] = DietFood(
          e.name.text,
          _asInt(e.kcal),
          sodiumMg: _asInt(e.sodium),
          sugarG: _asDouble(e.sugar),
          carbsG: _asDouble(e.carbs),
          proteinG: _asDouble(e.protein),
          fatG: _asDouble(e.fat),
        );
    });
  }

  void _beginEdit() => setState(() => _editing = true);

  /// 수정을 접고 처음 값으로 되돌린다. 화면을 나가지는 않는다 — 보기 모드로만
  /// 돌아간다. 컨트롤러는 그 줄이 트리에서 물러난 다음 프레임에 버린다.
  void _cancelEdit() {
    final List<_FoodEditors> stale = List<_FoodEditors>.of(_editors);
    setState(() {
      _editing = false;
      _type = widget.meal.mealType;
      _foods = List<DietFood>.of(widget.meal.items);
      _editors
        ..clear()
        ..addAll(<_FoodEditors>[
          for (final DietFood f in _foods) _FoodEditors.of(f),
        ]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final _FoodEditors e in stale) {
        e.dispose();
      }
    });
  }

  void _addFood() {
    // Empty draft name; the localized label is shown only as a placeholder
    // and is validated out on save.
    const DietFood draft = DietFood('', 0);
    setState(() {
      _foods = <DietFood>[..._foods, draft];
      _editors.add(_FoodEditors.of(draft));
    });
  }

  void _removeFood(int index) {
    final _FoodEditors removed = _editors.removeAt(index);
    setState(() => _foods = <DietFood>[..._foods]..removeAt(index));
    // 이번 프레임에는 아직 지워진 줄이 트리에 남아 있다 — 그 줄이 물러난
    // 뒤에 버린다.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Future<void> _save() async {
    final String? id = widget.meal.id;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // 페이지를 닫은 뒤에 결과를 알리므로, 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = navigator.context;
    if (id == null) {
      navigator.pop();
      return;
    }
    setState(() => _busy = true);
    try {
      // Drop empty draft rows (see `dietNewFood` placeholder) so a
      // translation string never lands in stored food names.
      // 영양은 이름·칼로리와 함께 되돌려 보낸다. 빠뜨리면 이 저장 한 번으로
      // 그 끼니의 탄단지·나트륨·당류가 0 이 된다 — 합계가 음식별 값에서
      // 계산되기 때문이다(#1853).
      final List<FoodItem> foods = <FoodItem>[
        for (final DietFood f in _foods)
          if (f.name.trim().isNotEmpty)
            FoodItem(
              name: f.name.trim(),
              calories: f.kcal,
              sodiumMg: f.sodiumMg,
              sugarG: f.sugarG,
              carbsG: f.carbsG,
              proteinG: f.proteinG,
              fatG: f.fatG,
            ),
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
      // Page dismissed mid-save → don't pop the page below.
      if (!mounted) return;
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      navigator.pop();
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietSaved, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(toastContext, l.dietSaveFailed, type: AppToastType.error);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final String? id = widget.meal.id;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.dietDeleteTitle,
      message: l.dietDeleteConfirm,
      confirmLabel: l.dietDelete,
      cancelLabel: l.dietCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final BuildContext toastContext = navigator.context;
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).deleteEntry(id);
      // Page dismissed mid-delete → don't pop the page below.
      if (!mounted) return;
      // 지운 끼니의 적립은 회수된다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      navigator.pop();
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietDeleted, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(
          toastContext,
          l.dietDeleteFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  MealPhotoView get _photo => MealPhotoView(
    photoUrl: widget.meal.photoUrl,
    photoAsset: widget.meal.photoAsset,
    emoji: widget.meal.emoji,
    width: double.infinity,
    height: _photoHeight,
    large: true,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final Widget page = Scaffold(
      key: const Key('mealDetailPage'),
      backgroundColor: OnCareColors.surfaceCard,
      // 뒤로는 앱바 한 곳, 저장은 하단 한 곳이다 — 머리의 글자 저장은 없다(#1700).
      // 머리의 연필은 저장이 아니라 보기↔수정 전환이라 그 규칙과 어긋나지 않는다.
      appBar: AppTopBar(
        title: l.dietMealSheetTitle(mealBadge(l, widget.meal.mealType)),
        actions: <Widget>[
          if (!_editing)
            AppIconButton(
              key: const Key('mealDetailEditButton'),
              icon: AppIcons.edit,
              tooltip: l.dietEditMeal,
              onPressed: _beginEdit,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.sectionGap,
                    ),
                    children: <Widget>[
                      // 무엇을 고치는 끼니인지 사진으로 먼저 알아본다. 사진이 없는
                      // 끼니는 큰 이모지 자리를 만들지 않는다. (#1053)
                      if (_photo.hasPhoto) ...<Widget>[
                        _photo,
                        const SizedBox(height: OnCareSpacing.cardGap),
                      ],
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel(l.dietMealInfo),
                            const SizedBox(height: OnCareSpacing.s12),
                            // 보기 모드에서는 고른 끼니 하나만 보인다. 고를 수
                            // 없는 칩 넷을 늘어놓으면 누를 수 있는 것처럼 읽힌다.
                            if (_editing)
                              Wrap(
                                spacing: OnCareSpacing.s8,
                                runSpacing: OnCareSpacing.s8,
                                children: <Widget>[
                                  for (final MealType t in _types)
                                    AppChoiceChip(
                                      label: mealBadge(l, t),
                                      selected: _type == t,
                                      onSelected: (_) =>
                                          setState(() => _type = t),
                                    ),
                                ],
                              )
                            else
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AppTag(
                                  label: mealBadge(l, _type),
                                  tone: AppTagTone.brand,
                                ),
                              ),
                            const SizedBox(height: OnCareSpacing.s16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                _FieldLabel(l.dietEatenTime),
                                AppTag(
                                  label: widget.meal.time,
                                  icon: AppIcons.clock,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(child: _FieldLabel(l.dietEatenFood)),
                                if (_editing)
                                  AppButton(
                                    label: l.dietAddFood,
                                    leadingIcon: AppIcons.add,
                                    variant: AppButtonVariant.text,
                                    size: OnCareButtonSize.small,
                                    onPressed: _addFood,
                                  ),
                              ],
                            ),
                            if (_editing)
                              Text(
                                l.dietEditFoodHint,
                                style: _text(
                                  context,
                                  OnCareTypography.caption,
                                  OnCareColors.textSecondary,
                                ),
                              ),
                            const SizedBox(height: OnCareSpacing.s12),
                            for (int i = 0; i < _foods.length; i++) ...<Widget>[
                              if (_editing)
                                _FoodEditBlock(
                                  index: i + 1,
                                  editors: _editors[i],
                                  onChanged: () => _syncFood(i),
                                  onDelete: () => _removeFood(i),
                                )
                              else
                                _FoodViewRow(index: i + 1, food: _foods[i]),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            const AppDivider(),
                            const SizedBox(height: OnCareSpacing.s12),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    l.dietTotalCalories,
                                    style: _text(
                                      context,
                                      OnCareTypography.strong(
                                        OnCareTypography.bodySmall,
                                      ),
                                      OnCareColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$_total ${l.unitKcal}',
                                  style: OnCareTypography.numeric(
                                    _text(
                                      context,
                                      OnCareTypography.titleSmall,
                                      tokens.brand.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel(l.dietNutritionInfo),
                            const SizedBox(height: OnCareSpacing.s4),
                            Text(
                              l.dietEditNutritionHint,
                              style: _text(
                                context,
                                OnCareTypography.caption,
                                OnCareColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: OnCareSpacing.s12),
                            // 탄단지가 기준이다. 당류는 탄수화물의 일부라
                            // 바로 아래에 들여 붙이고, 나트륨은 탄단지가
                            // 아니라 맨 끝에 둔다. 지방은 포화·트랜스까지
                            // 나누지 않는다 — 분석이 그만큼 재지 못한다.
                            _NutrientRow(
                              label: l.homeMacroCarbs,
                              value: _gramsText(_carbs),
                              unit: l.dietUnitG,
                            ),
                            const SizedBox(height: OnCareSpacing.s8),
                            _NutrientRow(
                              label: l.dietSugar,
                              value: _gramsText(_sugar),
                              unit: l.dietUnitG,
                              sub: true,
                            ),
                            const SizedBox(height: OnCareSpacing.s8),
                            _NutrientRow(
                              label: l.homeMacroProtein,
                              value: _gramsText(_protein),
                              unit: l.dietUnitG,
                            ),
                            const SizedBox(height: OnCareSpacing.s8),
                            _NutrientRow(
                              label: l.homeMacroFat,
                              value: _gramsText(_fat),
                              unit: l.dietUnitG,
                            ),
                            const SizedBox(height: OnCareSpacing.s8),
                            _NutrientRow(
                              label: l.dietSodium,
                              value: '$_sodium',
                              unit: l.dietUnitMg,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s16),
                      // 화면 안에서 삭제 확인창을 여는 버튼은 빨간 글자다(#1690).
                      Center(
                        child: AppButton(
                          label: l.dietDeleteMeal,
                          leadingIcon: AppIcons.delete,
                          variant: AppButtonVariant.destructiveText,
                          onPressed: _busy ? null : _confirmDelete,
                        ),
                      ),
                    ],
                  ),
                ),
                // 취소·저장은 수정 중일 때만 있다. 보기로 들어왔을 뿐인데
                // 저장 버튼이 서 있으면 무엇이 바뀌었는지 묻게 된다.
                if (_editing)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: AppButtonPair(
                      cancelLabel: l.dietCancel,
                      onCancel: _busy ? null : _cancelEdit,
                      confirmLabel: l.dietSave,
                      onConfirm: _busy ? null : _save,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Block back/drag dismiss while a save/delete request is in flight.
    return PopScope(canPop: !_busy, child: page);
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: _text(
      context,
      OnCareTypography.titleSmall,
      OnCareColors.textPrimary,
    ),
  );
}

/// 음식 한 줄이 쓰는 입력 컨트롤러 한 쌍. [_MealEditSheetState] 가 목록으로
/// 들고 다닌다.
class _FoodEditors {
  _FoodEditors({
    required this.name,
    required this.kcal,
    required this.carbs,
    required this.sugar,
    required this.protein,
    required this.fat,
    required this.sodium,
  });

  /// 0 은 빈 칸으로 연다 — 새로 추가한 줄에 `0` 이 적혀 있으면 지우고 쓰는
  /// 일이 한 번 더 늘어난다.
  factory _FoodEditors.of(DietFood food) => _FoodEditors(
    name: TextEditingController(text: food.name),
    kcal: _intField(food.kcal),
    carbs: _gramField(food.carbsG),
    sugar: _gramField(food.sugarG),
    protein: _gramField(food.proteinG),
    fat: _gramField(food.fatG),
    sodium: _intField(food.sodiumMg),
  );

  static TextEditingController _intField(int v) =>
      TextEditingController(text: v == 0 ? '' : '$v');

  static TextEditingController _gramField(double v) =>
      TextEditingController(text: v == 0 ? '' : _gramsText(v));

  final TextEditingController name;
  final TextEditingController kcal;
  final TextEditingController carbs;
  final TextEditingController sugar;
  final TextEditingController protein;
  final TextEditingController fat;
  final TextEditingController sodium;

  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      name,
      kcal,
      carbs,
      sugar,
      protein,
      fat,
      sodium,
    ]) {
      c.dispose();
    }
  }
}

/// 먹은 음식 한 줄 — 보기 모드의 읽기 전용 표시.
class _FoodViewRow extends StatelessWidget {
  const _FoodViewRow({required this.index, required this.food});

  final int index;
  final DietFood food;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        children: <Widget>[
          AppTag(label: '$index', tone: AppTagTone.brand),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Text(
              food.name.trim().isEmpty ? l.dietNewFood : food.name,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${food.kcal}',
            style: OnCareTypography.numeric(
              _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            l.unitKcal,
            style: _text(
              context,
              OnCareTypography.caption,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 수정 모드의 음식 한 덩이 — 이름·칼로리와 그 음식의 영양을 한자리에서
/// 고친다(#1856).
///
/// 끼니 단위 탄단지는 음식별 값의 합계라 영양 정보 카드에서는 고칠 자리가
/// 없다. 값이 실제로 사는 곳이 여기다.
class _FoodEditBlock extends StatelessWidget {
  const _FoodEditBlock({
    required this.index,
    required this.editors,
    required this.onChanged,
    required this.onDelete,
  });

  /// 숫자 칸 폭. 못 박아 두어야 라벨 칸이 자릿수에 따라 늘었다 줄었다 하지
  /// 않는다.
  static const double _valueWidth = 88;

  final int index;
  final _FoodEditors editors;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTile(
      tone: AppTileTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(label: '$index', tone: AppTagTone.brand),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: AppTextField(
                  key: ValueKey<String>('diet-food-name-$index'),
                  controller: editors.name,
                  hint: l.dietNewFood,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => onChanged(),
                ),
              ),
              AppIconButton(
                icon: AppIcons.close,
                tooltip: l.a11yRemoveFood,
                color: OnCareColors.textTertiary,
                onPressed: onDelete,
              ),
            ],
          ),
          _field(
            context,
            fieldKey: 'diet-food-kcal-$index',
            label: l.dietCalories,
            unit: l.unitKcal,
            controller: editors.kcal,
            decimal: false,
          ),
          _field(
            context,
            fieldKey: 'diet-food-carbs-$index',
            label: l.homeMacroCarbs,
            unit: l.dietUnitG,
            controller: editors.carbs,
          ),
          _field(
            context,
            fieldKey: 'diet-food-sugar-$index',
            label: l.dietSugar,
            unit: l.dietUnitG,
            controller: editors.sugar,
            sub: true,
          ),
          _field(
            context,
            fieldKey: 'diet-food-protein-$index',
            label: l.homeMacroProtein,
            unit: l.dietUnitG,
            controller: editors.protein,
          ),
          _field(
            context,
            fieldKey: 'diet-food-fat-$index',
            label: l.homeMacroFat,
            unit: l.dietUnitG,
            controller: editors.fat,
          ),
          _field(
            context,
            fieldKey: 'diet-food-sodium-$index',
            label: l.dietSodium,
            unit: l.dietUnitMg,
            controller: editors.sodium,
            decimal: false,
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String fieldKey,
    required String label,
    required String unit,
    required TextEditingController controller,
    bool decimal = true,
    bool sub = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      child: Row(
        children: <Widget>[
          if (sub) ...<Widget>[
            const SizedBox(width: OnCareSpacing.s16),
            Text(
              '↳',
              style: _text(
                context,
                OnCareTypography.bodySmall,
                OnCareColors.textTertiary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Expanded(
            child: Text(
              label,
              style: _text(
                context,
                OnCareTypography.bodySmall,
                OnCareColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: _valueWidth,
            child: AppTextField(
              key: ValueKey<String>(fieldKey),
              controller: controller,
              hint: '0',
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              // 숫자만 받는다 — 빈 칸은 0 으로 읽힌다.
              inputFormatters: <TextInputFormatter>[
                if (decimal)
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                else
                  FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.end,
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: _text(
              context,
              OnCareTypography.caption,
              OnCareColors.textSecondary,
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
    required this.value,
    required this.unit,
    this.sub = false,
  });

  /// 한 칸 들여쓰는 폭. 하위 항목이 상위 항목 라벨보다 안쪽에서 시작해야
  /// `당류` 가 `탄수화물` 에 딸린 값으로 읽힌다.
  static const double _subIndent = 16;

  final String label;
  final String value;
  final String unit;

  /// 바로 위 항목의 하위 값인가 — 들여쓰고 앞에 `↳` 를 붙인다.
  final bool sub;

  @override
  Widget build(BuildContext context) {
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        children: <Widget>[
          if (sub) ...<Widget>[
            const SizedBox(width: _subIndent),
            Text(
              '↳',
              style: _text(
                context,
                OnCareTypography.bodySmall,
                OnCareColors.textTertiary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Expanded(
            child: Text(
              label,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.bodySmall),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: OnCareTypography.numeric(
              _text(
                context,
                OnCareTypography.titleSmall,
                OnCareColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: _text(
              context,
              OnCareTypography.bodySmall,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
