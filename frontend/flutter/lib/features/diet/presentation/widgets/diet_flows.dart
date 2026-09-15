import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
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
                  icon: Icons.image_rounded,
                  title: l.dietAddPhoto,
                  subtitle: l.dietAddPhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                )
              else ...<Widget>[
                _SourceOption(
                  icon: Icons.image_rounded,
                  title: l.dietPickPhoto,
                  subtitle: l.dietPickPhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                ),
                const SizedBox(height: OnCareSpacing.s12),
                _SourceOption(
                  icon: Icons.photo_camera_rounded,
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
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.brand.surface,
            borderRadius: OnCareRadius.mdAll,
          ),
          child: SizedBox.square(
            dimension: tokens.density.iconButton,
            child: Icon(
              icon,
              size: OnCareSize.iconLarge,
              color: tokens.brand.primary,
            ),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
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
                Icon(
                  Icons.auto_awesome_rounded,
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
      body: AppEmptyState(title: message, icon: Icons.error_outline_rounded),
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

  /// 수정 화면 상단의 큰 끼니 사진 높이 (#1125) — 이 화면에 들어온 이유가 대개
  /// "무엇을 먹었는지 다시 보려고" 라, 사진이 주인공이다.
  static const double _photoHeight = 300;

  int get _total => _foods.fold(0, (int a, DietFood f) => a + f.kcal);

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
      appBar: AppTopBar(
        title: l.dietMealSheetTitle(mealBadge(l, widget.meal.mealType)),
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
                            ),
                            const SizedBox(height: OnCareSpacing.s16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                _FieldLabel(l.dietEatenTime),
                                AppTag(
                                  label: widget.meal.time,
                                  icon: Icons.schedule_rounded,
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
                                AppButton(
                                  label: l.dietAddFood,
                                  leadingIcon: Icons.add_rounded,
                                  variant: AppButtonVariant.text,
                                  size: OnCareButtonSize.small,
                                  onPressed: () => setState(
                                    () => _foods = <DietFood>[
                                      ..._foods,
                                      // Empty draft name; the localized label is
                                      // shown only as a placeholder and is
                                      // validated out on save.
                                      const DietFood('', 0),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
                              _FoodRow(
                                index: i + 1,
                                food: _foods[i],
                                onDelete: () => setState(
                                  () =>
                                      _foods = <DietFood>[..._foods]
                                        ..removeAt(i),
                                ),
                              ),
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
                            _NutrientRow(
                              label: l.dietSodium,
                              hint: l.dietSodiumHint,
                              value: '${widget.meal.sodium}',
                              unit: l.dietUnitMg,
                            ),
                            const SizedBox(height: OnCareSpacing.s8),
                            _NutrientRow(
                              label: l.dietSugar,
                              hint: l.dietSugarHint,
                              value: '${widget.meal.sugar}',
                              unit: l.dietUnitG,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s16),
                      // 화면 안에서 삭제 확인창을 여는 버튼은 빨간 글자다(#1690).
                      Center(
                        child: AppButton(
                          label: l.dietDeleteMeal,
                          leadingIcon: Icons.delete_outline_rounded,
                          variant: AppButtonVariant.destructiveText,
                          onPressed: _busy ? null : _confirmDelete,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    OnCareSpacing.s8,
                    side,
                    OnCareSpacing.s16,
                  ),
                  child: AppButtonPair(
                    cancelLabel: l.dietCancel,
                    onCancel: _busy ? null : () => Navigator.of(context).pop(),
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
    return AppTile(
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
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: l.a11yRemoveFood,
            color: OnCareColors.textTertiary,
            onPressed: onDelete,
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
    return AppTile(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: _text(
                    context,
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                    OnCareColors.textPrimary,
                  ),
                ),
                Text(
                  hint,
                  style: _text(
                    context,
                    OnCareTypography.caption,
                    OnCareColors.textSecondary,
                  ),
                ),
              ],
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
