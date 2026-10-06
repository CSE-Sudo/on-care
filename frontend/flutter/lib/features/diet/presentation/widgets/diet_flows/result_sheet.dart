// 사진 분석 완료 — 인식 결과를 확인·수정해 저장하는 시트.

part of '../diet_flows.dart';

/// AI analysis result sheet shown after picking a photo.
/// Runs the real `POST /diet/analyze` on the picked [photo] and shows the
/// recognised foods + nutrition. The backend persists the entry as part of
/// analysis, so a successful result refreshes every diet cache.
///
/// **기록이 남아 있으면 true** — 저장된 기록을 확인할 준비가 됐다는 뜻이다
/// (#1434). 분석 요청이 이미 저장·적립까지 마치므로, 분석이 성공한 뒤에는
/// `저장` 이든 `닫기` 든 끌어내려 닫든 모두 저장 성공이다(#2627). 분석이
/// 실패했거나 결과 시트에서 기록을 지웠으면 false 다.
///
/// 분석 실패 화면의 `다른 사진 고르기` 는 이 시트를 닫고 사진 선택부터 다시
/// 연다. 그 새 흐름의 결과가 곧 이 흐름의 결과다 — 버리면 새 사진으로 저장해도
/// 하단 `+` 로 시작한 흐름이 식단 탭으로 옮겨 가지 않는다.
Future<bool> showDietResultSheet(
  BuildContext context,
  MealPhoto photo,
  String mealType, {
  DateTime? date,
}) async {
  // 하단 바·+ 버튼이 시트 위로 올라오지 않도록 루트에 올린다. 식단 추가 시트와
  // 같은 규칙이다 — 둘이 같은 층에 있어야 한다(#791).
  final BuildContext root = _rootContext(context);
  final DietResultOutcome outcome = DietResultOutcome();
  final Object? closedWith = await showAppSheet<Object>(
    context: root,
    builder: (BuildContext ctx) => _ResultSheet(
      photo: photo,
      mealType: mealType,
      outcome: outcome,
      date: date,
    ),
  );
  if (closedWith == _ResultSheetExit.pickAnother) {
    if (!root.mounted) return false;
    // 다시 고른 사진도 처음 고른 날로 남긴다(#2849).
    return showDietAddSheet(root, date: date);
  }
  if (!outcome.saved && outcome.failed && root.mounted) {
    // 실패 화면으로 닫혀도 서버는 이미 저장했을 수 있다(#2847) — 앱이 응답을
    // 기다리다 끊긴 사이에도 서버는 끝까지 처리해 끼니를 남기고 포인트를
    // 적립한다. 시트가 닫힌 뒤라 시트의 ref 는 쓸 수 없어 컨테이너로 비운다.
    final ProviderContainer container = ProviderScope.containerOf(
      root,
      listen: false,
    );
    refreshDietRecords(container.invalidate, dates: <DateTime>[?_dayOf(date)]);
    invalidatePointsBalance(container.invalidate);
  }
  // 사진으로는 기록할 수 없을 때(음식 없음·오늘 분석 다 씀 등)의 `직접 추가` —
  // 그 화면에서 저장했으면 이 흐름도 저장 성공이다(#2848, #2827).
  if (closedWith == _ResultSheetExit.manual) {
    if (!root.mounted) return false;
    return openDietManualAddPage(root, date: date);
  }
  return outcome.resolve(closedWith);
}

/// 결과 시트가 값 없이 닫혔을 때 무엇을 돌려줄지 정하는 기록. (#2627)
///
/// 시트는 `저장` 말고도 `닫기` 버튼과 끌어내려 닫기로 닫힌다. 뒤의 둘은 값을
/// 싣지 못하므로, 분석이 성공했는지를 시트 바깥에 따로 남겨 둔다.
@visibleForTesting
class DietResultOutcome {
  /// 서버에 기록이 남아 있다 — 분석이 성공했고 시트에서 지우지 않았다.
  bool saved = false;

  /// 분석 요청이 한 번이라도 실패로 끝났다(#2847). 실패로 보인 요청도 서버에서는
  /// 저장됐을 수 있어, 그대로 닫히면 식단 기록·잔액을 한 번 다시 읽는다.
  bool failed = false;

  /// 시트가 닫힌 값. 명시적인 `true`/`false` 는 그대로, 값 없이 닫혔으면
  /// [saved] 다.
  bool resolve(Object? closedWith) => closedWith is bool ? closedWith : saved;
}

/// 결과 시트가 `bool` 말고 돌려주는 것.
enum _ResultSheetExit {
  /// 분석 실패 화면의 `다른 사진 고르기` — 사진 선택부터 다시 연다.
  pickAnother,

  /// 분석 실패 화면의 `직접 추가` — 사진 없이 적는 화면을 연다.
  manual,
}

class _ResultSheet extends ConsumerStatefulWidget {
  const _ResultSheet({
    required this.photo,
    required this.mealType,
    required this.outcome,
    this.date,
  });
  final MealPhoto photo;
  final String mealType;
  final DietResultOutcome outcome;

  /// 기록을 남길 날. null 이면 오늘이다(#2849).
  final DateTime? date;

  @override
  ConsumerState<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends ConsumerState<_ResultSheet>
    with _FoodEditing<_ResultSheet> {
  DietAnalysisResult? _result;
  bool _loading = true;
  DietAnalysisFailure? _failure;

  /// [_failure] 를 만든 원래 오류. 403·429 의 공통 문구와 서버 사유를 고를 때
  /// 쓴다(#2859).
  Object? _failureError;

  /// 이 기록이 놓인 날. 식단 탭에서 지난 날짜를 보며 연 추가면 그 날이고
  /// (#2849), 아니면 오늘이다. 다른 날 먹은 식사의 사진이면 `날짜 변경` 으로
  /// 실제로 먹은 날로 옮긴다(#1241).
  ///
  /// 날짜는 식단 상세처럼 따로 옮긴다(#1947) — 사진을 올린 자리에서 가장 흔히
  /// 고치는 것이 날짜라, 연필을 거치게 하지 않는다. 끼니·음식은 헤더 연필이
  /// 이 시트 안에 여는 수정 모드에서 고친다(#2097).
  late DateTime _date = _startDate(widget.date);

  /// 날짜를 옮기는 중. 두 번 눌러 같은 기록을 두 날짜로 보내지 않게 막는다.
  bool _movingDate = false;

  /// 헤더 연필로 연 수정 모드(#2097). 시트를 떠나지 않고 이 자리에서 끼니·
  /// 음식·영양을 고친 뒤 `저장` 한다 — 아래 `저장` 을 두고 다른 화면으로
  /// 넘어가면, 저장하지 않은 줄 알았던 기록의 수정 화면이 열리는 셈이다.
  bool _editing = false;

  /// 수정 모드에서 고른 끼니. 연필을 누를 때 [_meal] 에서 시작한다.
  late MealType _type = _meal;

  /// 고친 값을 보내거나 기록을 지우는 중. 버튼과 시트 닫기를 막는다.
  bool _saving = false;

  bool get _failed => _failure != null;

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
      _failureError = null;
    });
    final Stopwatch elapsed = Stopwatch()..start();
    // 분석 중에 시트를 끌어내려 닫아도 요청은 끝까지 가고 서버는 저장한다
    // (#2847). 그때는 이 State 의 ref 를 쓸 수 없으므로 컨테이너를 먼저 잡아
    // 두고, 응답이 오면 시트가 남아 있든 없든 기록을 다시 읽게 한다.
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    try {
      final DietAnalysisResult result = await ref
          .read(dietRepositoryProvider)
          .analyze(
            photo: widget.photo,
            mealType: widget.mealType,
            idempotencyKey: _idempotencyKey,
            // 오늘이면 싣지 않는다 — 서버가 저장하는 순간의 날짜를 쓴다. 자정
            // 직전에 연 시트가 앱 시계의 어제로 못 박히지 않는다.
            date: _date == _todayKst() ? null : wireDate(_date),
          );
      // analyze() already persisted the entry → 이 시점부터 기록은 저장돼
      // 있다. 시트를 어떻게 닫든 저장 성공이다(#2627).
      widget.outcome.saved = true;
      // 지난 날짜로 남겼으면 그 날도 비운다(#2849).
      refreshDietRecords(container.invalidate, dates: <DateTime>[_date]);
      // 저장과 함께 포인트도 적립됐다 — MY 잔액을 다시 읽는다(#1786).
      invalidatePointsBalance(container.invalidate);
      if (!mounted) return;
      await _holdAnalyzing(elapsed);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on Object catch (error) {
      widget.outcome.failed = true;
      if (!mounted) return;
      // 실패도 같은 바닥을 쓴다 — 즉시 튀어나오는 실패 문구는 사진을 보지도
      // 않고 거절한 것처럼 읽힌다.
      await _holdAnalyzing(elapsed);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = DietAnalysisFailure.fromError(error);
        _failureError = error;
      });
    }
  }

  /// [_minAnalyzingDelay] 에서 이미 지난 만큼을 뺀 나머지를 기다린다.
  Future<void> _holdAnalyzing(Stopwatch elapsed) {
    final Duration left = _minAnalyzingDelay - elapsed.elapsed;
    if (left <= Duration.zero) return Future<void>.value();
    return Future<void>.delayed(left);
  }

  /// 인식 결과를 이 시트 안에서 고치기 시작한다. (#1564, #2097)
  ///
  /// 예전에는 시트를 닫고 저장된 기록의 식단 상세로 넘어갔다. 시트 아래에
  /// `저장` 이 서 있는데 연필이 저장 뒤의 화면을 여니, 회원에게는 저장하지도
  /// 않은 기록이 이미 저장돼 있는 것으로 보였다.
  void _beginEdit() {
    final DietAnalysisResult? r = _result;
    if (r == null || r.entryId.isEmpty) return;
    final List<DietFood> foods = <DietFood>[
      for (final RecognizedFood f in r.foods) DietFood.fromRecognized(f),
    ];
    setState(() {
      _editing = true;
      _type = _meal;
      _loadFoods(foods);
      _carbsRecorded = _carbsOf(foods) > 0;
    });
  }

  /// 고친 값을 버리고 분석 결과 보기로 돌아간다. 시트는 닫지 않는다 — 고치다
  /// 그만둔 것이지 기록을 그만둔 것이 아니다.
  void _cancelEdit() => setState(() => _editing = false);

  /// 고친 끼니·음식을 기록에 반영하고 시트를 닫는다. (#2097)
  ///
  /// 기록은 분석 때 이미 저장돼 있으므로 새로 만들지 않고 그 기록을 고친다.
  /// 식단 상세의 `저장` 과 같은 요청이다.
  Future<void> _saveEdit() async {
    final DietAnalysisResult? r = _result;
    if (r == null || r.entryId.isEmpty || _saving) return;
    final List<FoodItem> foods = _foodPayload();
    // 음식을 모두 지웠다면 빈 끼니를 남기는 대신 기록을 지울지 묻는다 —
    // 식단 상세와 같다.
    if (foods.isEmpty) {
      await _deleteEmptied(r.entryId);
      return;
    }
    if (!_validateFoods()) return;

    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await _saveFoods(id: r.entryId, mealType: _type, foods: foods);
      if (!mounted) return;
      // 날짜를 옮겨 둔 기록이면 그 날도 비운다.
      refreshDietRecords(ref.invalidate, dates: <DateTime>[_date]);
      _finish();
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.dietSaveFailed, type: AppToastType.error);
    }
  }

  /// 음식을 모두 지우고 저장했을 때 — 기록을 지울지 묻고, 지우면 시트를 닫는다.
  Future<void> _deleteEmptied(String id) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.dietDeleteTitle,
      message: l.dietDeleteWhenEmpty,
      confirmLabel: l.dietDelete,
      cancelLabel: l.dietCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(dietRepositoryProvider).deleteEntry(id);
      if (!mounted) return;
      // 지운 끼니의 적립은 회수된다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      // 기록이 없어졌다 — 어떻게 닫히든 저장 성공이 아니다.
      widget.outcome.saved = false;
      refreshDietRecords(ref.invalidate, dates: <DateTime>[_date]);
      final AppToastHost toast = AppToastHost.of(context);
      // 지웠으니 식단 탭으로 옮겨 갈 기록이 없다 — `false` 로 닫는다.
      Navigator.of(context).pop(false);
      toast.show(l.dietDeleted, type: AppToastType.success);
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.dietDeleteFailed, type: AppToastType.error);
    }
  }

  /// 기록 날짜만 따로 옮긴다. (#1241, #1947)
  ///
  /// 분석이 끝난 시점에 기록은 이미 서버에 남아 있다. 그래서 고른 즉시 옮긴다 —
  /// 시트를 닫는 방법이 여럿인데, 저장을 한 버튼에만 걸어 두면 화면에 보이는
  /// 날짜와 실제로 남은 날짜가 갈린다. 식단 상세의 `날짜 변경` 과 같은 동작이다.
  Future<void> _pickDate() async {
    final DietAnalysisResult? result = _result;
    if (result == null || result.entryId.isEmpty || _movingDate) return;
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      // 기기 시간대가 아니라 KST 오늘에 테두리를 둔다(#3250).
      currentDate: today,
      initialDate: _date,
      // 지난 식사는 얼마든지 올릴 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      showClose: false,
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
      refreshDietRecords(ref.invalidate, dates: <DateTime>[previous, chosen]);
      showAppToast(
        context,
        l.dietRecordDateMoved(_recordDateLabel(context, chosen)),
        type: AppToastType.success,
      );
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _movingDate = false);
      showAppToast(context, l.dietRecordDateFailed, type: AppToastType.error);
    }
  }

  /// 이 기록이 들어갈 끼니. `widget.mealType` 은 사진을 고른 시각으로 추측한
  /// 값이다(`_currentMealType`). 저장한 뒤 끼니 카드가 아침·점심·저녁·간식·야식
  /// 중 어디에 붙을지가 여기서 정해지므로, 저장 전에 보여 준다(#1897).
  MealType get _meal => MealType.values.firstWhere(
    (MealType m) => m.name == widget.mealType,
    orElse: () => MealType.snack,
  );

  /// Sends the user back to the source picker. The photo they have can't be
  /// analysed, so "다시 시도" would just fail again — the useful next step is
  /// choosing a different one.
  ///
  /// 사진 선택은 [showDietResultSheet] 가 이 시트가 닫힌 뒤 연다 — 그래야 새
  /// 흐름의 저장 결과가 처음 흐름의 결과로 돌아간다(#2627).
  void _pickAnother() =>
      Navigator.of(context).pop(_ResultSheetExit.pickAnother);

  /// 사진으로는 이 끼니를 기록할 수 없다 — 사진 없이 적는 화면으로 넘긴다.
  /// 그 화면도 [showDietResultSheet] 가 이 시트가 닫힌 뒤 연다.
  void _openManual() => Navigator.of(context).pop(_ResultSheetExit.manual);

  /// 아래 `닫기`. 기록은 분석 때 이미 저장됐으므로 `저장` 과 같이 저장 성공으로
  /// 닫는다 — 식단 탭 이동과 홈 요약 갱신이 똑같이 일어난다(#2627). 저장 알림은
  /// `저장` 에만 띄운다.
  void _close() => Navigator.of(context).pop(true);

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
        // 권한·동의 부족과 공통 요청 한도는 어느 화면에서나 같은 뜻이라 공통
        // 문구를 쓴다 — 403 에는 서버 사유가 있으면 한국어 화면에서 그것을
        // 보인다(#2859). 사진 분석 전용 분당 한도(`rate_limited`, #2827)만
        // 직접 추가를 함께 권하는 분석 문구다.
        DietAnalysisFailure.rateLimited
            when _failureError is DietAnalysisRejected =>
          l.dietAnalysisRateLimited,
        DietAnalysisFailure.forbidden ||
        DietAnalysisFailure.rateLimited => appErrorMessage(
          l,
          _failureError ?? const UnknownError(),
          fallback: l.dietAnalysisFailedBody,
        ),
        DietAnalysisFailure.notImplemented => l.dietAnalysisNotImplemented,
        DietAnalysisFailure.noFood => l.dietAnalysisNoFood,
        DietAnalysisFailure.dailyLimit => l.dietAnalysisDailyLimit,
        DietAnalysisFailure.unavailable => l.dietAnalysisUnavailable,
        DietAnalysisFailure.aiCapacity => l.dietAnalysisAiCapacity,
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
      DietAnalysisFailure.badRequest ||
      DietAnalysisFailure.noFood => _pickAnother,
      DietAnalysisFailure.unauthorized => () => unawaited(_signInAgain()),
      // 사진 길이 닫혔다(오늘 다 씀·분석 꺼짐·서버 AI 상한) — 기록할 수 있는 길은 직접 추가다.
      DietAnalysisFailure.dailyLimit ||
      DietAnalysisFailure.unavailable ||
      DietAnalysisFailure.aiCapacity => _openManual,
      _ => () => Navigator.of(context).pop(),
    };
  }

  String _failureActionLabel(AppLocalizations l, DietAnalysisFailure failure) {
    if (failure.canRetry) return l.actionRetry;
    return switch (failure) {
      DietAnalysisFailure.unsupportedFormat ||
      DietAnalysisFailure.badRequest ||
      DietAnalysisFailure.noFood => l.dietAnalysisPickAnother,
      DietAnalysisFailure.unauthorized => l.dietAnalysisSignIn,
      DietAnalysisFailure.dailyLimit ||
      DietAnalysisFailure.unavailable ||
      DietAnalysisFailure.aiCapacity => l.dietManualAdd,
      _ => l.dietAnalysisClose,
    };
  }

  /// 왼쪽 버튼. 직접 추가를 권하는 실패에서만 두 버튼이 된다(#2848, #2827).
  /// 주 동작이 이미 `직접 추가` 면 왼쪽은 `닫기` 이고, 아니면(다른 사진·다시
  /// 시도) 왼쪽이 `직접 추가` 다.
  ({String label, VoidCallback onPressed})? _failureSecondary(
    AppLocalizations l,
    DietAnalysisFailure failure,
  ) {
    if (!failure.offersManualEntry) return null;
    final bool manualIsPrimary =
        failure == DietAnalysisFailure.dailyLimit ||
        failure == DietAnalysisFailure.unavailable ||
        failure == DietAnalysisFailure.aiCapacity;
    if (manualIsPrimary) {
      return (
        label: l.dietAnalysisClose,
        onPressed: () => Navigator.of(context).pop(),
      );
    }
    return (label: l.dietManualAdd, onPressed: _openManual);
  }

  /// `_result == null` without a classified failure shouldn't happen, but
  /// treating it as temporary keeps a retry available instead of a dead end.
  DietAnalysisFailure get _shownFailure =>
      _failure ?? DietAnalysisFailure.temporary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget sheet = AppSheet(
      title: _loading
          ? l.dietAnalyzing
          : _failed
          ? l.dietAnalysisFailed
          : l.dietAnalysisDone,
      subtitle: l.dietAiNutritionResult,
      // 닫기는 아래 `닫기` 버튼 하나로 모은다 — 머리의 X 와 둘이 있으면 같은
      // 일을 하는 자리가 화면에 둘이다(#1564).
      showClose: false,
      // 이 시트는 AI 가 읽은 결과를 말한다 — 홈의 `오늘의 AI 통합 조언` 과
      // 같은 아바타를 써서 두 화면이 같은 목소리로 읽히게 한다(#1897).
      leading: const OniAvatar(size: OnCareSize.avatarMedium),
      // 연필은 닫기 X 가 비워 둔 헤더 우측에 둔다. 인식된 음식 줄에 있던 것을
      // 올렸다 — 시트 전체가 "AI 가 읽은 것"이고 연필은 그것을 고치는 문이라,
      // 음식 한 줄보다 머리 쪽이 걸린 범위와 맞는다(#1897).
      trailing: _editButton(l),
      // 버튼을 바닥에 고정하면 코멘트 마지막 줄을 덮는다(#1897). 스크롤 끝으로
      // 보내 다 읽은 뒤에 나오게 한다 — #1432 의 "시트 안에서만 스크롤"은
      // 그대로다.
      pinFooter: false,
      footer: _footer(l),
      child: _body(),
    );
    // 고친 값을 보내는 동안에는 끌어내려 닫지 못하게 한다.
    return PopScope(canPop: !_saving, child: sheet);
  }

  /// 인식된 데이터를 고치는 문. 헤더 우측에 놓이므로 결과가 있을 때만
  /// 만든다 — 분석 중이거나 실패한 시트에는 고칠 것이 없다. 이미 고치는
  /// 중이면 감춘다 — 식단 상세의 연필과 같다.
  Widget? _editButton(AppLocalizations l) {
    final DietAnalysisResult? r = _result;
    if (_loading || _failed || _editing || r == null || r.entryId.isEmpty) {
      return null;
    }
    // 식단 상세가 연필을 쓰므로 여기서도 연필이다 — 같은 곳으로 가는 문이
    // 화면마다 다른 모양이면 다른 동작으로 읽힌다(#1864).
    return AppIconButton(
      key: const Key('diet-result-edit'),
      icon: AppIcons.edit,
      tooltip: l.actionEdit,
      size: AppIconButtonSize.small,
      // 연필은 앱 전체에서 회색이다 — 목록의 `›` 와 같은 색(#2507).
      color: OnCareColors.textTertiary,
      onPressed: _beginEdit,
    );
  }

  Widget? _footer(AppLocalizations l) {
    if (_loading) return null;
    if (_failed || _result == null) {
      final DietAnalysisFailure failure = _shownFailure;
      final ({String label, VoidCallback onPressed})? secondary =
          _failureSecondary(l, failure);
      if (secondary != null) {
        return AppButtonPair(
          cancelKey: const Key('dietAnalysisFailureSecondary'),
          cancelLabel: secondary.label,
          onCancel: secondary.onPressed,
          confirmKey: const Key('dietAnalysisFailureAction'),
          confirmLabel: _failureActionLabel(l, failure),
          onConfirm: _failureAction(failure),
        );
      }
      return AppButton(
        key: const Key('dietAnalysisFailureAction'),
        label: _failureActionLabel(l, failure),
        onPressed: _failureAction(failure),
        fullWidth: true,
      );
    }
    // [취소]·[닫기] 왼쪽, [저장] 오른쪽 — 앱의 모든 하단 두 버튼과 같은 순서다(#1690).
    if (_editing) {
      // 수정 모드의 `취소` 는 고친 값만 버리고 시트에 남는다. `저장` 은 고친
      // 값을 보낸 뒤 닫는다.
      return AppButtonPair(
        cancelLabel: l.dietCancel,
        onCancel: _saving ? null : _cancelEdit,
        confirmLabel: l.dietSave,
        onConfirm: _saving ? null : () => unawaited(_saveEdit()),
      );
    }
    // 분석 요청이 이미 기록을 남겼다 — 왼쪽은 `취소` 가 아니라 `닫기` 다.
    // `취소` 는 저장을 하지 않는 것으로 읽히지만 기록은 이미 남아 있다(#2627).
    return AppButtonPair(
      cancelLabel: l.dietAnalysisClose,
      onCancel: _close,
      confirmLabel: l.dietSave,
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
        .map((RecognizedFood f) => f.label)
        .join(' · ');
    // 수정 중에는 합계가 고치는 음식을 곧바로 따라온다 — 식단 상세와 같다.
    // 보기에서는 서버가 준 합계를 그대로 적는다.
    final String kcal = _editing ? '$_total' : '${r.totalCalories}';
    final double carbs = _editing ? _carbs : r.totalCarbsG;
    final double sugar = _editing ? _sugar : r.totalSugarG;
    final double protein = _editing ? _protein : r.totalProteinG;
    final double fat = _editing ? _fat : r.totalFatG;
    final int sodium = _editing ? _sodium : r.totalSodiumMg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 수정 모드에서는 `인식된 음식` 을 감추고, 음식별 수정 칸이 아래
        // 기록 날짜·끼니 다음에 선다(#2097). 식단 상세의 수정 모드처럼
        // "언제·어느 끼니" 를 먼저 두고 "무엇을 먹었나" 를 그 아래에 둔다.
        if (!_editing) ...<Widget>[
          // 이 시트에서 강조할 것은 AI 가 무엇으로 읽었는지 하나다 — 거기에만
          // 옅은 브랜드 채움을 준다. `0389e572` 가 걷어낸 것은 구획을 여럿
          // 쌓아 카드가 온통 옅은 파랑이 되는 것이고, 그 커밋이 남긴 규칙은
          // "바탕은 강조인 것만"이다. 그래서 박스는 여기 하나뿐이다(#1897).
          AppTile(
            key: const Key('diet-result-recognized'),
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
                // 음식마다 이름 옆에 AI 가 읽은 **양**을 보조색으로 붙인다(#1964).
                // 영양은 모두 이 양으로 환산되므로, 양이 틀리면 칼로리·탄단지가
                // 함께 틀린다 — 저장 전 이 자리에서 보여야 머리의 연필로 바로
                // 고칠 수 있다. 식단 탭 끼니 카드·식단 상세와 같은 자리·같은
                // 모양이다. 양을 모르는 음식은 이름만 적는다(0g 은 안 먹었다).
                Text.rich(
                  key: const Key('diet-result-recognized-foods'),
                  TextSpan(
                    children: recognized.isEmpty
                        ? <InlineSpan>[TextSpan(text: l.dietNoRecognizedFood)]
                        : <InlineSpan>[
                            for (
                              int i = 0;
                              i < r.foods.length;
                              i++
                            ) ...<InlineSpan>[
                              if (i > 0) const TextSpan(text: ' · '),
                              // 한 음식의 이름과 양은 줄이 바뀌어도 붙어 있다 —
                              // 이름 안·이름과 양 사이를 붙는 공백으로 잇고, 줄은
                              // ` · ` 에서만 바뀐다. `그래놀라` / `토핑 50g` 처럼
                              // 한 음식이 두 줄로 갈리면 다른 음식처럼 읽힌다.
                              TextSpan(text: keepTogether(r.foods[i].label)),
                              if (r.foods[i].amountG case final double grams)
                                TextSpan(
                                  text: keepTogether(
                                    '$kNoBreakSpace${_gramsText(grams)}${l.dietUnitG}',
                                  ),
                                  style: OnCareTypography.numeric(
                                    _text(
                                      context,
                                      OnCareTypography.caption,
                                      OnCareColors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                  ),
                  style: _text(
                    context,
                    OnCareTypography.titleSmall,
                    OnCareColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        // 기록 날짜와 끼니. 날짜는 `날짜 변경` 으로 여기서 바로 따로 옮기고
        // (#1241, #1947), 끼니·음식은 헤더 연필이 여는 수정 모드에서 고친다
        // (#2097) — 식단 상세의 `식사 정보` 카드와 같은 나눔이다.
        //
        // 식단 상세의 `식사 정보` 카드와 같은 두 줄이다 — 한 줄에 `날짜 · 끼니`
        // 로 붙여 두면 끼니가 날짜의 꼬리처럼 읽혀, 이 기록이 어느 끼니로
        // 들어가는지(#1897) 눈에 덜 띈다. 두 값이 같은 자리에서 시작하도록
        // 라벨 열 폭을 맞춘다. 시각은 두지 않는다(#1989) — `time_label` 은
        // 계속 저장되지만 그리지 않는다.
        //
        // 위아래가 모두 구획이라 이 줄만 맨바닥이면 라벨이 `인식된 음식`·
        // `칼로리` 보다 한 칸 왼쪽에서 시작한다. 같은 구획에 넣어 시작하는
        // 자리를 맞춘다(#1864).
        AppTile(
          tone: AppTileTone.none,
          child: Table(
            columnWidths: const <int, TableColumnWidth>{
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  _InfoLabel(l.dietRecordDate),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _recordDateLabel(context, _date),
                          key: const Key('diet-result-date'),
                          style: _text(
                            context,
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                            OnCareColors.textPrimary,
                          ),
                        ),
                      ),
                      // 날짜를 옮기는 동안 버튼이 spinner 로 바뀐다. 자리를
                      // 잡아 두지 않으면 줄 높이가 내려앉아 라벨과 값이 함께
                      // 튄다 — 두 상태가 같은 높이를 쓴다(#1864).
                      SizedBox(
                        height: tokens.density.buttonHeight(
                          OnCareButtonSize.small,
                        ),
                        child: Center(
                          child: _movingDate
                              ? const AppLoading.inline()
                              : AppButton(
                                  key: const Key('diet-result-date-change'),
                                  label: l.dietRecordDateChange,
                                  onPressed: () => unawaited(_pickDate()),
                                  variant: AppButtonVariant.text,
                                  size: OnCareButtonSize.small,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const TableRow(
                children: <Widget>[
                  SizedBox(height: OnCareSpacing.s8),
                  SizedBox(height: OnCareSpacing.s8),
                ],
              ),
              TableRow(
                children: <Widget>[
                  _InfoLabel(l.dietMealKind),
                  if (_editing)
                    _MealTypeChips(
                      key: const Key('diet-result-meal'),
                      selected: _type,
                      onSelected: (MealType t) => setState(() => _type = t),
                    )
                  else
                    Align(
                      key: const Key('diet-result-meal'),
                      alignment: Alignment.centerLeft,
                      child: AppTag(
                        label: mealBadge(l, _meal),
                        tone: AppTagTone.brand,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (_editing) ...<Widget>[
          _foodsEditor(l),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        Text(
          l.dietNutritionResult,
          style: _text(
            context,
            OnCareTypography.label,
            OnCareColors.textSecondary,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 탄단지가 기준이다 — 식단 상세의 영양 정보와 같은 순서로 읽힌다.
        // 당류는 탄수화물의 일부라 바로 아래에 들여 붙이고, 나트륨은
        // 탄단지가 아니라 맨 끝이다(#1864).
        Column(
          key: const Key('diet-result-nutrition'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ResultRow(label: l.dietCalories, value: kcal, unit: l.unitKcal),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.homeMacroCarbs,
              value: _gramsText(carbs),
              unit: l.dietUnitG,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.dietSugar,
              // 서버가 준 double 을 그대로 문자열로 만들면 29.497999999999998
              // 이 찍힌다 — 칼로리·나트륨과 같은 서식으로 맞춘다(#1564).
              value: _gramsText(sugar),
              unit: l.dietUnitG,
              sub: true,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.homeMacroProtein,
              value: _gramsText(protein),
              unit: l.dietUnitG,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.homeMacroFat,
              value: _gramsText(fat),
              unit: l.dietUnitG,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.dietSodium,
              value: '$sodium',
              unit: l.dietUnitMg,
            ),
          ],
        ),
      ],
    );
  }

  /// 수정 모드의 `먹은 음식` 구획 — 음식마다 이름·내용량·영양 칸과, 음식을
  /// 더하는 버튼. 칸은 식단 상세의 수정 모드와 같은 편집기다(#2097).
  Widget _foodsEditor(AppLocalizations l) {
    return Column(
      key: const Key('diet-result-foods-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l.dietEatenFood,
          style: _text(
            context,
            OnCareTypography.label,
            OnCareColors.textSecondary,
          ),
        ),
        Text(
          l.dietEditFoodHint,
          style: _text(
            context,
            OnCareTypography.caption,
            OnCareColors.textSecondary,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        for (int i = 0; i < _foods.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: OnCareSpacing.s8),
          _foodEditor(i),
        ],
        // 음식 한 건을 다 채운 자리에서 다음 음식을 이어 적도록 목록 맨
        // 아래에 둔다 — 운동 추가 시트와 같은 모양이다(#2544, #2607).
        const SizedBox(height: OnCareSpacing.s8),
        _AddFoodButton(
          key: const Key('diet-result-add-food'),
          onPressed: _addFood,
        ),
      ],
    );
  }
}

/// `먹은 음식` 목록 맨 아래의 `+ 음식 추가`. 음식 한 건의 칸을 다 채운
/// 자리에서 바로 다음 음식을 적도록 제목 줄이 아니라 목록 아래에 둔다 —
/// 운동 추가 시트의 `+ 운동 추가` 와 같은 모양이다(#2544, #2607). 직접 추가·
/// 분석 결과·상세 수정 세 화면이 함께 쓴다.
class _AddFoodButton extends StatelessWidget {
  const _AddFoodButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: AppLocalizations.of(context).dietAddFood,
      leadingIcon: AppIcons.add,
      variant: AppButtonVariant.text,
      fullWidth: true,
      onPressed: onPressed,
    );
  }
}

/// 분석 결과의 영양 한 줄. 식단 상세의 [_NutrientRow] 와 같은 구성이고,
/// 숫자만 브랜드 색이다 — 여기 값은 아직 저장 전이라 고친 값이 아니다.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.unit,
    this.sub = false,
  });

  /// 한 칸 들여쓰는 폭. 하위 항목이 상위 항목 라벨보다 안쪽에서 시작해야
  /// `당류` 가 `탄수화물` 에 딸린 값으로 읽힌다 — 식단 상세와 같은 값이다.
  static const double _subIndent = 16;

  final String label;
  final String value;
  final String unit;

  /// 바로 위 항목의 하위 값인가 — 들여쓰고 앞에 `↳` 를 붙인다.
  final bool sub;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
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
