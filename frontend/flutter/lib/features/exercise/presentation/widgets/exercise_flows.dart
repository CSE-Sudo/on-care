import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_limits.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_refresh.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/features/my_health/presentation/points_reward.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_rules/oncare_rules.dart' show minutesFromSeconds;
import 'package:oncare_ui/oncare_ui.dart';

/// 조작이 멎은 뒤 칼로리 미리보기를 부르기까지 기다리는 시간. 애니메이션이
/// 아니라 요청을 모으는 창이다.
const Duration _estimateDebounceDelay = Duration(milliseconds: 400);

// Backend value sent as `dayLabel` — DO NOT localize (persisted to the server).
/// The "운동 종류" chip display labels — 유산소 / 근력 / 스트레칭 / 기타 네 가지다
/// (#996). 걷기는 유산소로, 요가·스트레칭은 스트레칭으로 접혀 있다: 유형은 집계
/// 축이지 운동 이름이 아니라, 서버·트레이너 앱도 이 네 가지만 쓴다.
/// Only the display strings are localized — the index→type mapping is fixed.
List<String> _exerciseTypeLabels(AppLocalizations l) => <String>[
  l.exTypeCardio, // cardio
  l.exTypeStrength, // strength
  l.exTypeFlexibility, // flexibility (= ExerciseType.stretching)
  l.exTypeOtherChip, // other
];

/// Intensity chip display labels (가벼움 / 보통 / 높음), index-1:1 with
/// [_intensityFactor]. Only the display strings are localized.
List<String> _levelLabels(AppLocalizations l) => <String>[
  l.exLevelLight,
  l.exLevelModerate,
  l.exLevelHigh,
];

/// Chip index → backend [ExerciseType] (1:1 with [_exerciseTypeLabels]).
ExerciseType _typeFromIndex(int i) => switch (i) {
  0 => ExerciseType.cardio,
  1 => ExerciseType.strength,
  2 => ExerciseType.stretching, // 스트레칭 버킷
  _ => ExerciseType.other,
};

/// [ExerciseType] → chip index. 옛 값(걷기·요가)으로 저장된 기록도 자기 버킷
/// 칩을 켠 채 열린다 — 유형이 넷으로 접힌 뒤에도 예전 기록은 남아 있다.
int _indexFromType(ExerciseType t) => switch (t) {
  ExerciseType.cardio || ExerciseType.walking => 0,
  ExerciseType.strength => 1,
  ExerciseType.stretching || ExerciseType.yoga => 2,
  ExerciseType.other => 3,
};

/// 칩 index → 강도. `_levelLabels` 와 1:1 이다.
ExerciseIntensity _intensityFromIndex(int level) => switch (level) {
  0 => ExerciseIntensity.light,
  2 => ExerciseIntensity.high,
  _ => ExerciseIntensity.moderate,
};

/// 어림 칼로리. 표는 [estimateExerciseCalories] 한 곳에 있다 — 추천 개인운동
/// 체크(#1131)도 같은 값을 써야 같은 운동이 화면마다 다른 칼로리로 적히지 않는다.
int _estimateCalories(ExerciseType type, int minutes, int level) =>
    estimateExerciseCalories(
      type,
      minutes,
      intensity: _intensityFromIndex(level),
    );

// ─────────────────────────────────────────────────────── 운동 추가 ──

/// A compact "운동 추가" sheet: pick a type + duration/intensity, then save.
/// Pass [session] to open in edit mode (pre-filled → PUT); omit it to add.
/// **기록이 저장되면 true.** 하단 `+` 로 연 흐름이 저장 성공에만 운동 탭으로
/// 옮겨 가려면 취소와 저장을 구분해야 한다(#1434).
Future<bool> showExerciseAddSheet(
  BuildContext context, {
  ExerciseSession? session,
  DateTime? initialDate,
}) async {
  final bool? saved = await showAppSheet<bool>(
    // 하단 바·+ 버튼이 시트 위로 올라오지 않도록 루트에 올린다(#791).
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (BuildContext ctx) =>
        _ExerciseAddSheet(session: session, initialDate: initialDate),
  );
  return saved ?? false;
}

/// 기록 하나를 지운다 — 확인창을 거친 뒤에만 지운다. (#1428)
///
/// 목록에서 바로 지울 수 있어야 추가한 기록을 되돌릴 자리가 생긴다. 서버가 준
/// id 가 없는 기록(데모 시드의 옛 행)은 지울 수 없다 — 조용히 실패하는 대신
/// 그렇다고 말한다.
///
/// 지우기와 갱신은 저장(#2879)처럼 앱 수명의 [ExerciseChangeRunner] 가 한다
/// (#3096). 요청 중에 부른 화면이 닫혀도 [ref] 를 다시 쓰지 않으므로, 서버가
/// 지웠는데 `삭제하지 못했어요` 가 뜨거나 목록·그래프가 옛 값으로 남지 않는다.
/// [onDeleteStart] 는 확인 뒤 요청을 보내기 직전에 부른다 — 부른 화면이 그동안
/// 닫히지 않게 막는 자리다.
Future<bool> confirmDeleteExerciseSession(
  BuildContext context,
  WidgetRef ref,
  ExerciseSession session, {
  VoidCallback? onDeleteStart,
}) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final AppToastHost toast = AppToastHost.of(context);
  final ExerciseChangeRunner runner = ref.read(exerciseChangeRunnerProvider);
  final String? id = session.id;
  if (id == null) {
    toast.show(l.exCannotDelete, type: AppToastType.error);
    return false;
  }
  // 되돌릴 수 없는 쪽은 파괴적 색으로 말한다.
  final bool confirmed = await showAppConfirmDialog(
    context: context,
    title: l.exDeleteExercise,
    message: l.exDeleteExerciseBody,
    confirmLabel: l.actionDelete,
    cancelLabel: l.actionCancel,
    destructive: true,
  );
  if (!confirmed) return false;
  onDeleteStart?.call();
  try {
    // 추가 경로와 같은 갱신이다(#2634) — 이번 주·지난 주 목록과 그래프, AI
    // 조언, MY 기록 달력·보호권, 회수된 적립(#1786)과 주간 챌린지가 함께
    // 최신이 된다.
    await runner.run((ExerciseRepository r) => r.deleteSession(id));
    toast.show(l.exDeleted, type: AppToastType.success);
    return true;
  } on Object {
    toast.show(l.exDeleteFailed, type: AppToastType.error);
    return false;
  }
}

class _ExerciseAddSheet extends ConsumerStatefulWidget {
  const _ExerciseAddSheet({this.session, this.initialDate});

  final ExerciseSession? session;

  /// 새 기록의 기본 날짜. 운동 탭 안에서 열면 그 탭에서 보고 있는 날이다 —
  /// 어제를 보다가 추가했는데 오늘로 저장되면 방금 적은 기록이 목록에서
  /// 사라진다(#1428). 하단 `+` 로 열면 null 이라 오늘이 기본값이다.
  final DateTime? initialDate;

  bool get isEdit => session != null;

  @override
  ConsumerState<_ExerciseAddSheet> createState() => _ExerciseAddSheetState();
}

class _ExerciseAddSheetState extends ConsumerState<_ExerciseAddSheet> {
  late int _type = widget.session != null
      ? _indexFromType(widget.session!.type)
      : 0; // 기본값은 유산소 — 칩 목록의 첫 칸이다.
  // Intensity is persisted on ExerciseSession, so an edit reopens at the
  // saved level (가벼움/보통/높음); a new session defaults to 보통.
  late int _level = widget.session?.intensity.index ?? 1;
  // 유산소·스트레칭·기타의 걸린 시간. 분이 아니라 **초**로 들고 있다 —
  // 분 단위 스테퍼로는 45초짜리 운동을 적을 수 없었고, 한 시간이 넘는 운동은
  // 90분처럼 분으로 환산해 올려야 했다(#2071). 초를 모르는 옛 기록은
  // `minutes × 60` 으로 읽는다.
  late Duration _duration = _initialDuration(widget.session);
  // 근력은 시간이 아니라 **세트·횟수·중량**으로 재는 운동이다
  // (#1262, #1276, #1310). 분과 따로 들고 있어야 유형을 근력↔유산소로 오갈 때
  // 각자의 값이 남는다 — 하나로 쓰면 30분이 30세트가 되어 돌아온다.
  late double _sets = _initialSets(widget.session);
  late double _reps = (widget.session?.reps ?? 10).toDouble();
  // 버티는 운동은 한 세트를 회가 아니라 초로 잰다(#1969). 횟수와 따로 들고
  // 있어야 회↔초를 오갈 때 각자의 값이 남는다 — 한 칸을 같이 쓰면 10회가
  // 10초로 돌아온다.
  late double _holdSeconds = (widget.session?.holdSeconds ?? 60).toDouble();
  // 지금 이 운동을 초로 재는가. 수정 시트는 기록이 든 칸을 그대로 따르고,
  // 새 기록은 이름을 적으면 종목표가 말해 준다(`_fetchEstimate`).
  late bool _isHold = widget.session?.holdSeconds != null;
  // 회원이 직접 회↔초를 고른 뒤에는 이름 해석이 그 선택을 덮지 않는다 —
  // 종목표는 **기본값**일 뿐이고, 고르는 것은 적는 사람이다.
  bool _holdChosenByUser = false;
  // 휠은 0.5kg 칸에만 선다(#2545). 그 칸에 맞지 않는 옛 기록(62.3kg)은 여는
  // 순간 가장 가까운 칸으로 맞춘다 — 휠에 보이는 값과 저장되는 값이 같아야 한다.
  late double _weight = snapExerciseWeight(widget.session?.weight ?? 20);
  // 기본값은 오늘. 지난 기록을 고치면 그 기록의 날짜로 열린다 — 오늘로
  // 되돌리면 기록을 고치기만 해도 이번 주로 옮겨 간다.
  late DateTime _date = _dateOnly(
    widget.session?.date ?? widget.initialDate ?? nowKst(),
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.session?.name ?? '',
  );
  final FocusNode _nameFocus = FocusNode();
  bool _saving = false;

  /// `운동 하나 더` 로 모아 둔, 아직 저장하지 않은 운동. (#2544)
  ///
  /// 하루치 운동 여러 개를 시트 한 번에 적는다. 예전에는 저장할 때마다 시트가
  /// 닫혀, 서너 가지를 했으면 시트를 서너 번 다시 열고 날짜를 다시 골라야
  /// 했다. 날짜는 모아 둔 운동 전부에 공통이라 저장하는 순간의 [_date] 로
  /// 맞춘다. 수정 시트에는 쓰지 않는다.
  final List<ExerciseSessionDraft> _queue = <ExerciseSessionDraft>[];

  /// 모아 둔 목록의 자리. 담은 뒤 폼이 비워지면 그 목록이 보이게 올린다 —
  /// 긴 시트의 아래쪽에서 누르면 무엇이 담겼는지 화면 밖에서 일어난다.
  final GlobalKey _queueKey = GlobalKey();

  /// 지금 화면이 보여 줄 소모 칼로리. **이름이 차기 전에는 null 이다.**
  ///
  /// 예전에는 시트를 여는 순간 기본값(유산소·30분·보통)만으로 숫자가 떠 있었다 —
  /// 이름 칸은 계산에 아무 영향이 없었으므로, 확정된 듯한 값이 무엇을 근거로
  /// 나왔는지도 이름 칸이 왜 필수인지도 화면에서 읽히지 않았다(#1312).
  ExerciseCalorieEstimate? _estimate;

  /// 마지막으로 계산을 요청한 입력. 늦게 도착한 응답이 새 입력의 값을 덮지
  /// 않도록, 응답을 쓸 때 이 값과 견준다.
  String? _requestedKey;

  /// 계산이 도는 중. 이름을 막 적은 직후의 빈 칸을 "값이 없다" 로 읽히지 않게
  /// 한다 — 곧 채워질 자리다.
  bool _estimating = false;

  /// 조작이 멎은 뒤에 부른다. 스테퍼 한 칸마다 요청을 보내면 이름 하나 적는
  /// 동안 수십 번이 나간다.
  Timer? _estimateDebounce;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 편집 시트가 열릴 걸린 시간. 기록이 초를 들고 있으면 그 값, 초를 모르는
  /// 옛 기록이면 분에서 환산한 값, **새 기록이면 0** 이다. (#2071)
  ///
  /// 새 기록을 0 에서 시작하는 것은 타이머의 규칙이다 — 미리 채워 둔 30분은
  /// 회원이 한 번도 건드리지 않고 저장할 수 있는 값이고, 그러면 아무도 적은
  /// 적 없는 시간이 기록에 남는다. 0 이면 저장이 막히므로(`exEnterDuration`)
  /// 시간은 반드시 적은 값이 된다.
  static Duration _initialDuration(ExerciseSession? session) {
    if (session == null) return Duration.zero;
    final int? seconds = session.durationSeconds;
    if (seconds != null && seconds > 0) return Duration(seconds: seconds);
    return Duration(minutes: session.minutes);
  }

  /// 편집 시트가 열릴 세트 수. 기록이 세트를 들고 있으면 그 값, 세트를 모르는
  /// 옛 근력 기록이면 분에서 환산한 값, 새 기록이면 12세트다.
  static double _initialSets(ExerciseSession? session) {
    if (session == null || session.type != ExerciseType.strength) return 12;
    final int? recorded = session.sets;
    if (recorded != null && recorded > 0) return recorded.toDouble();
    return setsFromStrengthMinutes(
      session.minutes.toDouble(),
    ).clamp(1, 40).toDouble();
  }

  @override
  void initState() {
    super.initState();
    // 이름 칸을 벗어나면(다른 곳을 누르거나 키보드를 닫으면) 기다리지 않고
    // 바로 계산한다(#1312).
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _scheduleEstimate(immediate: true);
    });
    // 수정 시트는 이름이 이미 차 있다 — 열자마자 그 이름의 값을 보여 준다.
    if (_name.text.trim().isNotEmpty) _scheduleEstimate(immediate: true);
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  /// 계산을 가르는 입력 전부. 하나라도 달라지면 값이 달라진다.
  String get _estimateKey =>
      '${_name.text.trim()}|${_typeFromIndex(_type).name}|'
      '$_effectiveMinutes|$_level';

  /// 소모 칼로리를 다시 받아 온다. 이름이 비어 있으면 값을 지운다 —
  /// 이름을 지웠는데 아까 숫자가 남아 있으면 그 값이 무엇의 값인지 알 수 없다.
  void _scheduleEstimate({bool immediate = false}) {
    _estimateDebounce?.cancel();
    if (!mounted) return;
    // 시간이 0 이면 계산할 것이 없다. 서버는 `minutes > 0` 을 요구하므로
    // 그대로 부르면 422 가 돌아온다 — 아직 시간을 적지 않은 상태이지
    // 오류가 아니다. (#2071)
    if (_name.text.trim().isEmpty || _effectiveMinutes <= 0) {
      if (_estimate != null || _estimating) {
        setState(() {
          _estimate = null;
          _estimating = false;
          _requestedKey = null;
        });
      }
      return;
    }
    if (_estimateKey == _requestedKey) return;
    if (immediate) {
      unawaited(_fetchEstimate());
      return;
    }
    _estimateDebounce = Timer(
      _estimateDebounceDelay,
      () => unawaited(_fetchEstimate()),
    );
  }

  Future<void> _fetchEstimate() async {
    if (!mounted) return;
    final String key = _estimateKey;
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _requestedKey = key;
      _estimating = true;
    });
    try {
      final ExerciseCalorieEstimate result = await ref
          .read(exerciseRepositoryProvider)
          .previewCalories(
            type: _typeFromIndex(_type),
            name: name,
            minutes: _effectiveMinutes,
            intensity: _intensityFromIndex(_level),
          );
      // 그 사이 입력이 또 바뀌었으면 이 응답은 낡은 값이다.
      if (!mounted || key != _requestedKey) return;
      setState(() {
        _estimate = result;
        _estimating = false;
        // 종목표가 버티는 운동이라고 하면 `횟수` 대신 `초` 를 묻는다(#1969).
        // 회원이 이미 직접 골랐으면 그 선택이 이긴다.
        if (!_holdChosenByUser) _isHold = result.isometric;
      });
    } on Object {
      // 미리보기가 실패해도 기록은 적을 수 있어야 한다 — 서버가 저장할 때 다시
      // 계산하므로, 여기서 막을 이유가 없다. 앱이 아는 유형 평균으로 채운다.
      if (!mounted || key != _requestedKey) return;
      setState(() {
        _estimate = ExerciseCalorieEstimate(
          calories: _estimateCalories(
            _typeFromIndex(_type),
            _effectiveMinutes,
            _level,
          ),
        );
        _estimating = false;
      });
    }
  }

  /// 지금 고른 유형이 근력인가 — 세트·횟수·중량으로 묻고 그렇게 저장할지
  /// 가른다.
  bool get _isStrength => _typeFromIndex(_type) == ExerciseType.strength;

  /// 이름 입력의 예시 문구. 고른 유형을 따라간다 (#1460).
  String _nameHint(AppLocalizations l) => switch (_typeFromIndex(_type)) {
    ExerciseType.cardio || ExerciseType.walking => l.exExerciseNameHintCardio,
    ExerciseType.strength => l.exExerciseNameHintStrength,
    ExerciseType.stretching ||
    ExerciseType.yoga => l.exExerciseNameHintFlexibility,
    ExerciseType.other => l.exExerciseNameHintOther,
  };

  /// 근력 기록의 분. 세트 수에 세트당 벽시계 시간(휴식 포함)을 곱한 값이다 —
  /// 서버는 여전히 분(>0)을 요구하고, 주간 운동 시간도 분으로 센다.
  int get _strengthMinutes =>
      (_sets.round() * kStrengthMinutesPerSetWithRest).round();

  /// 저장·칼로리 계산이 쓰는 분. 근력이면 세트에서, 아니면 초에서 환산한다.
  ///
  /// 환산 규칙이 서버(`ExerciseSessionCreate._minutes_from_seconds`)와 **같아야**
  /// 한다. 미리보기로 받은 칼로리를 그대로 저장하는 것이 #1312 의 요구인데,
  /// 앱과 서버가 같은 초를 다른 분으로 읽으면 저장 뒤 숫자가 달라진다.
  /// 45초짜리 운동이 반올림으로 0분이 되어 거절되지도 않는다. 반올림도 서버와
  /// 같은 짝수 쪽이라 2분 30초는 저장 뒤와 같은 2분이다 — 공용 규칙
  /// [minutesFromSeconds] 한 곳을 쓴다(#2860).
  int get _effectiveMinutes => _isStrength
      ? _strengthMinutes
      : minutesFromSeconds(_duration.inSeconds);

  /// 편집 시트 안에서 지운다 — 목록 줄에는 더 이상 휴지통을 두지 않는다.
  /// 지우기는 되돌릴 수 없는 동작이라, 고치는 화면 안에 한 번 더 들어와야만
  /// 닿을 수 있는 자리에 둔다(식단 탭의 끼니 수정 화면과 같은 자리, #1468).
  Future<void> _delete() async {
    final ExerciseSession? session = widget.session;
    if (session == null || _saving) return;
    // 지우는 동안 `_saving` 을 세워 뒤로 가기·바깥 탭으로 시트가 닫히지 않게
    // 한다(#3096).
    final bool deleted = await confirmDeleteExerciseSession(
      context,
      ref,
      session,
      onDeleteStart: () {
        if (mounted) setState(() => _saving = true);
      },
    );
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final DateTime now = nowKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      // 기기 시간대가 아니라 KST 오늘에 테두리를 둔다(#3250).
      currentDate: now,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      // 앞으로 한 기록은 없다 — 아직 하지 않은 운동을 적을 자리가 아니다.
      lastDate: _dateOnly(now),
      showClose: false,
    );
    if (picked != null && mounted) setState(() => _date = _dateOnly(picked));
  }

  /// 이름 칸이 찼는가. 모아 둔 운동이 있을 때 저장이 폼의 운동도 함께 실을지
  /// 가른다 — 비어 있으면 모아 둔 것만 저장한다.
  bool get _formHasName => _name.text.trim().isNotEmpty;

  /// 모아 둔 운동을 날려도 되는지 묻고 시트를 닫는다. 모아 둔 것이 없으면
  /// 묻지 않는다 — 폼 하나를 적다 닫는 것은 지금까지처럼 바로 닫힌다.
  Future<void> _requestClose() async {
    if (_saving) return;
    final NavigatorState navigator = Navigator.of(context);
    if (_queue.isNotEmpty) {
      final AppLocalizations l = AppLocalizations.of(context);
      final bool discard = await showAppConfirmDialog(
        context: context,
        title: l.exQueueDiscardTitle,
        message: l.exQueueDiscardBody(_queue.length),
        confirmLabel: l.exQueueDiscard,
        cancelLabel: l.actionCancel,
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    navigator.pop();
  }

  /// 폼의 운동 한 건. 이름이나 시간이 비었으면 그렇다고 알리고 null 이다.
  ExerciseSessionDraft? _draftFromForm() {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final String name = _name.text.trim();
    if (name.isEmpty) {
      toast.show(l.exEnterName, type: AppToastType.error);
      return null;
    }
    // 0초는 저장하지 않는다 — 지금까지 최소 1분이 하던 일이다(#2071).
    final int minutes = _effectiveMinutes;
    if (minutes <= 0) {
      toast.show(
        _isStrength ? l.exEnterSets : l.exEnterDuration,
        type: AppToastType.error,
      );
      return null;
    }
    // 근력이 아니면 세트·횟수·중량을 싣지 않는다 — 유산소를 세트로 세는
    // 화면은 없고, 유형을 바꾼 수정에서는 null 이 옛 값을 지운다.
    // 한 세트는 회로든 초로든 **한 번만** 잰다(#1969). 고르지 않은 쪽은
    // null 로 실어 보내야, 회↔초를 되돌린 수정에서 옛 값이 남지 않는다.
    // 초는 시간으로 재는 유형에만 싣는다. 근력의 분은 세트에서 환산한 값이라
    // 회원이 적은 시간이 아니다 — 초를 함께 보내면 서버가 그 초로 분을 다시
    // 계산해, 세트에서 나온 분을 덮는다. (#2071)
    final ExerciseType type = _typeFromIndex(_type);
    return ExerciseSessionDraft(
      type: type,
      name: name,
      minutes: minutes,
      // 화면이 보여 준 값을 그대로 싣는다 — 서버는 이 값을 쓰지 않고 같은
      // 계산을 다시 하지만(#1312), 서버가 없는 경로(목업 저장소)는 이 값을
      // 기록에 남긴다. 미리보기가 아직 안 돌아왔으면 앱이 아는 유형 평균이다.
      // 입력을 고친 뒤 디바운스가 끝나기 전이면 들고 있는 값은 고치기 전 입력의
      // 것이다 — 그 값도 쓰지 않는다(#3244).
      calories: _estimate != null && _requestedKey == _estimateKey
          ? _estimate!.calories
          : _estimateCalories(type, minutes, _level),
      // Intensity is persisted now, so always recompute calories from the
      // (restored or edited) level — no more preserving stale values.
      intensity: ExerciseIntensity.values[_level],
      date: _date,
      sets: _isStrength ? _sets.round() : null,
      reps: _isStrength && !_isHold ? _reps.round() : null,
      holdSeconds: _isStrength && _isHold ? _holdSeconds.round() : null,
      durationSeconds: _isStrength ? null : _duration.inSeconds,
      weight: _isStrength ? _weight : null,
    );
  }

  /// 폼의 운동을 목록에 담고 폼을 비운다. (#2544)
  ///
  /// 날짜·유형·강도와 근력의 세트·횟수·중량은 그대로 둔다 — 이어서 적는 운동은
  /// 같은 날, 비슷한 운동인 경우가 많다. 이름과 시간은 비운다: 남겨 두면 같은
  /// 운동을 한 번 더 담기 쉽다.
  void _addAnother() {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    if (_queue.length >= kMaxExerciseSessionsPerSave) {
      AppToastHost.of(context).show(
        l.exQueueFull(kMaxExerciseSessionsPerSave),
        type: AppToastType.error,
      );
      return;
    }
    final ExerciseSessionDraft? draft = _draftFromForm();
    if (draft == null) return;
    _estimateDebounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _queue.add(draft);
      _name.clear();
      _duration = Duration.zero;
      _estimate = null;
      _estimating = false;
      _requestedKey = null;
      _isHold = false;
      _holdChosenByUser = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _queueKey.currentContext;
      if (target == null || !target.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: OnCareMotion.normal,
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// 저장 버튼의 문구. 한 건이면 `저장`, 여럿이면 몇 개를 저장하는지 말한다.
  String _saveLabel(AppLocalizations l) {
    final int count = _queue.length + (_formHasName ? 1 : 0);
    return count > 1 ? l.exSaveCount(count) : l.exSave;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (widget.isEdit) return _saveEdit();
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    // 모아 둔 운동이 있으면 폼은 이름이 찼을 때만 함께 싣는다 — 마지막 운동을
    // `운동 하나 더` 로 담은 뒤 곧바로 저장하는 흐름이 막히지 않는다. 모아 둔
    // 것이 없으면 지금까지처럼 폼의 한 건이 저장 대상이다.
    final List<ExerciseSessionDraft> drafts = <ExerciseSessionDraft>[..._queue];
    if (_queue.isEmpty || _formHasName) {
      final ExerciseSessionDraft? draft = _draftFromForm();
      if (draft == null) return;
      drafts.add(draft);
    }
    if (drafts.length > kMaxExerciseSessionsPerSave) {
      toast.show(
        l.exQueueFull(kMaxExerciseSessionsPerSave),
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // 한 요청으로 보낸다 — 서버가 전부 저장하거나 하나도 저장하지 않는다.
      // 날짜는 모아 둔 것까지 지금 고른 날로 맞춘다.
      // 저장이 성공하면 주간 그래프·조언 등을 비우는 것까지 runner 가 한다 —
      // 저장 중에 시트를 내려도 빠지지 않는다(#2879).
      final ExerciseSessionsAdded added = await ref
          .read(exerciseChangeRunnerProvider)
          .run(
            (ExerciseRepository repository) => repository.addSessions(
              <ExerciseSessionDraft>[
                for (final ExerciseSessionDraft d in drafts) d.withDate(_date),
              ],
            ),
          );
      // Sheet dismissed mid-save → don't pop the page below. 저장 알림(받은
      // 포인트)은 앱 맨 위 오버레이에 뜨므로 시트가 없어도 띄운다.
      if (mounted) navigator.pop(true);
      toast.show(
        drafts.length > 1 ? l.exLoggedCount(drafts.length) : l.exLogged,
        type: AppToastType.success,
        // 받은 포인트가 있으면 ★ +20P 가 반짝인다. 한도를 넘었으면 저장 알림만.
        rewardLabel: pointsRewardLabel(l, added.points),
      );
    } catch (_) {
      // 모아 둔 목록은 그대로 남는다. 응답만 잃고 서버에는 저장됐을 수 있지만,
      // 같은 목록을 다시 누르면 같은 멱등키로 나가 서버가 처음 결과를 돌려준다
      // (#3095) — 기록·포인트가 두 벌 생기지 않는다.
      if (mounted) setState(() => _saving = false);
      toast.show(l.exSaveFailed, type: AppToastType.error);
    }
  }

  Future<void> _saveEdit() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final ExerciseSession editing = widget.session!;
    final ExerciseSessionDraft? draft = _draftFromForm();
    if (draft == null) return;
    if (editing.id == null) {
      // No id → PUT impossible; don't silently create a duplicate session.
      toast.show(l.exCannotEdit, type: AppToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      // 저장·수정 뒤에 다시 읽을 것들은 삭제·추천 개인운동 완료와 같은 함수로
      // 비운다(#2634). 시트가 아니라 runner 가 비워 저장 중에 시트를 내려도
      // 빠지지 않는다(#2879).
      await ref
          .read(exerciseChangeRunnerProvider)
          .run(
            (ExerciseRepository repository) => repository.updateSession(
              id: editing.id!,
              type: draft.type,
              name: draft.name,
              minutes: draft.minutes,
              calories: draft.calories,
              intensity: draft.intensity,
              date: draft.date,
              sets: draft.sets,
              reps: draft.reps,
              holdSeconds: draft.holdSeconds,
              durationSeconds: draft.durationSeconds,
              weight: draft.weight,
            ),
          );
      // Sheet dismissed mid-save → don't pop the page below.
      if (mounted) navigator.pop(true);
      toast.show(l.exUpdated, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      toast.show(l.exSaveFailed, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<String> types = _exerciseTypeLabels(l);
    final List<String> levels = _levelLabels(l);
    final Widget sheet = AppSheet(
      key: const Key('exerciseAddSheet'),
      showClose: false,
      title: widget.isEdit ? l.exEditExercise : l.exAddExercise,
      // [취소] 왼쪽, [저장] 오른쪽 — 식단 수정 화면과 같은 두 버튼이다(#1782).
      // 취소는 저장하지 않고 시트만 닫는다. 저장 중에는 둘 다 비활성이 되어
      // 두 번 눌리거나 저장 도중 닫히지 않는다.
      footer: AppButtonPair(
        cancelKey: const Key('exerciseCancelButton'),
        cancelLabel: l.actionCancel,
        // 모아 둔 운동이 있으면 버릴지 먼저 묻는다(#2544).
        onCancel: _saving ? null : _requestClose,
        confirmKey: const Key('exerciseSaveButton'),
        // 여럿을 저장하면 몇 개인지 말한다 — `3개 저장`.
        confirmLabel: _saveLabel(l),
        onConfirm: _saving ? null : _save,
      ),
      child: GestureDetector(
        // 이름 칸 밖을 누르면 키보드를 닫는다 — 포커스를 잃는 순간 칼로리를
        // 바로 계산한다(위 `_nameFocus` 리스너).
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          key: const Key('exerciseAddContent'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Label(l.exExerciseDate),
            const SizedBox(height: OnCareSpacing.s8),
            _DateField(
              key: const Key('exerciseDateField'),
              date: _date,
              onTap: _pickDate,
            ),
            // `운동 하나 더` 로 모아 둔 운동. 날짜 바로 아래에 둔다 — 날짜는
            // 이 목록 전부에 걸리는 값이고, 그 아래 폼은 다음 한 건이다.
            if (_queue.isNotEmpty) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s20),
              Column(
                key: _queueKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Label(l.exQueueTitle(_queue.length)),
                  const SizedBox(height: OnCareSpacing.s8),
                  for (int i = 0; i < _queue.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        top: i == 0 ? 0 : OnCareSpacing.s8,
                      ),
                      child: _QueuedExerciseTile(
                        key: ValueKey<String>('exerciseQueueItem-$i'),
                        draft: _queue[i],
                        onRemove: _saving
                            ? null
                            : () => setState(() => _queue.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: OnCareSpacing.s20),
            _Label(l.exExerciseType),
            const SizedBox(height: OnCareSpacing.s8),
            Wrap(
              spacing: OnCareSpacing.s8,
              runSpacing: OnCareSpacing.s8,
              children: <Widget>[
                for (int i = 0; i < types.length; i++)
                  AppChoiceChip(
                    label: types[i],
                    selected: _type == i,
                    onSelected: (bool _) {
                      setState(() => _type = i);
                      _scheduleEstimate();
                    },
                  ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s20),
            _Label(l.exExerciseName),
            const SizedBox(height: OnCareSpacing.s8),
            AppTextField(
              key: const Key('exerciseNameField'),
              controller: _name,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.done,
              maxLength: 100,
              // 고른 종류의 예시를 보여 준다 — 근력을 고른 사람에게
              // `러닝머신` 을 예로 들면 무엇을 적어야 하는지 되레
              // 헷갈린다(#1460). 이미 적은 이름은 건드리지 않는다.
              hint: _nameHint(l),
              // 글자마다 부르지 않는다 — 이름 해석이 외부 호출을 탈 수 있어,
              // 조작이 멎은 뒤 한 번이면 된다(#1312). 비우면 그 자리에서
              // 숫자를 지운다.
              onChanged: (String _) {
                // 모아 둔 운동이 있으면 저장 버튼의 개수가 이름 칸을 따라간다
                // — 이름이 차면 폼의 운동도 함께 저장된다.
                if (_queue.isNotEmpty) setState(() {});
                _scheduleEstimate();
              },
              onSubmitted: (String _) => _scheduleEstimate(immediate: true),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 근력은 세트·횟수·중량으로, 나머지는 분으로 묻는다
            // (#1262, #1276, #1310).
            // 화면 여러 곳(홈 운동 카드·운동 현황 링·주간 목표)이 근력을
            // 세트로 읽는데 기록만 분이면, 회원이 적지 않은 수가 화면에 뜬다.
            if (_isStrength) ...<Widget>[
              // 버티는 운동은 `횟수` 자리를 `버티는 시간` 이 대신한다 — 칸을
              // 하나 더 두지 않고 **바꿔 가며** 쓴다(#1969). 플랭크를 `3회` 로
              // 적으면 45초를 "3회" 라고 말하는 뜻이 틀린 기록이 남는다.
              _MeasureToggle(
                label: _isHold
                    ? l.exExerciseStrengthAmountHold
                    : l.exExerciseStrengthAmount,
                repsLabel: l.exUnitReps,
                secondsLabel: l.exUnitSeconds,
                semanticsLabel: l.exExerciseMeasure,
                isHold: _isHold,
                onChanged: (bool hold) => setState(() {
                  _isHold = hold;
                  _holdChosenByUser = true;
                }),
              ),
              const SizedBox(height: OnCareSpacing.s8),
              // 유산소의 시간 휠과 같은 띠·같은 높이의 한 줄이다(#2545) —
              // 유형을 바꿔도 시트의 모양이 그대로다.
              AppNumberWheel(
                key: const Key('exerciseStrengthWheel'),
                columns: <AppNumberWheelColumn>[
                  AppNumberWheelColumn(
                    key: const Key('exerciseSetsWheel'),
                    value: _sets,
                    min: 1,
                    max: kMaxExerciseSets.toDouble(),
                    unit: l.exUnitSets,
                    onChanged: (double v) {
                      setState(() => _sets = v);
                      _scheduleEstimate();
                    },
                  ),
                  if (_isHold)
                    AppNumberWheelColumn(
                      key: const Key('exerciseHoldWheel'),
                      value: _holdSeconds,
                      min: 1,
                      max: kMaxExerciseHoldSeconds.toDouble(),
                      unit: l.exUnitSeconds,
                      onChanged: (double v) => setState(() => _holdSeconds = v),
                    )
                  else
                    AppNumberWheelColumn(
                      key: const Key('exerciseRepsWheel'),
                      value: _reps,
                      min: 1,
                      max: kMaxExerciseReps.toDouble(),
                      unit: l.exUnitReps,
                      onChanged: (double v) => setState(() => _reps = v),
                    ),
                  AppNumberWheelColumn(
                    key: const Key('exerciseWeightWheel'),
                    value: _weight,
                    min: 0,
                    max: kMaxExerciseWeightKg,
                    // 원판은 0.5kg 단위로 붙는다.
                    step: kExerciseWeightStepKg,
                    unit: l.exUnitKg,
                    onChanged: (double v) => setState(() => _weight = v),
                  ),
                ],
              ),
            ] else ...<Widget>[
              _Label(l.exExerciseDuration),
              const SizedBox(height: OnCareSpacing.s8),
              // 아이폰 타이머처럼 시·분·초를 굴려 고른다(#2071). 분 단위
              // 스테퍼로는 45초짜리 운동을 적을 수 없었고, 한 시간이 넘는
              // 운동은 90분처럼 분으로 환산해 올려야 했다.
              AppDurationWheel(
                key: const Key('exerciseDurationWheel'),
                duration: _duration,
                maxSeconds: kMaxExerciseMinutes * 60,
                labels: AppDurationWheelLabels(
                  hours: l.exUnitHours,
                  minutes: l.exUnitMinutes,
                  seconds: l.exUnitSeconds,
                ),
                onChanged: (Duration v) {
                  setState(() => _duration = v);
                  _scheduleEstimate();
                },
              ),
            ],
            const SizedBox(height: OnCareSpacing.s20),
            _Label(l.exExerciseIntensity),
            const SizedBox(height: OnCareSpacing.s8),
            // 개인운동 완료창의 강도 선택도 같은 칩을 쓴다 — 모양을 한 벌만
            // 둔다(#1457).
            Wrap(
              spacing: OnCareSpacing.s8,
              runSpacing: OnCareSpacing.s8,
              children: <Widget>[
                for (int i = 0; i < levels.length; i++)
                  AppChoiceChip(
                    label: levels[i],
                    selected: _level == i,
                    onSelected: (bool _) {
                      setState(() => _level = i);
                      _scheduleEstimate();
                    },
                  ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s16),
            _CalorieBox(
              key: const Key('exerciseCalorieBox'),
              estimate: _estimate,
              loading: _estimating,
            ),
            // 하루치 운동을 시트 한 번에 적는다(#2544). 폼의 운동을 위 목록에
            // 담고 폼을 비운다. 폼을 다 적은 자리에서 누르도록 폼 맨 아래에
            // 한 줄을 채워 두고, 파란 글씨 버튼으로 둔다 — 채움 버튼이면 바로
            // 아래 `저장` 과 무게가 겹친다. 수정 시트는 한 건만 고치므로 두지
            // 않는다.
            if (!widget.isEdit) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              AppButton(
                key: const Key('exerciseAddAnotherButton'),
                label: l.exAddExercise,
                onPressed: _saving ? null : _addAnother,
                variant: AppButtonVariant.text,
                leadingIcon: AppIcons.add,
                fullWidth: true,
              ),
            ],
            // 지우기는 고치는 화면 맨 아래에서만 한다 — 목록 줄의 휴지통은
            // 없앴다. 새로 적는 시트에는(수정이 아니면) 지울 기록 자체가
            // 없으니 두지 않는다.
            if (widget.isEdit) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s20),
              AppButton(
                key: const Key('exerciseDeleteButton'),
                label: l.exDeleteExercise,
                onPressed: _saving ? null : _delete,
                variant: AppButtonVariant.destructiveText,
                leadingIcon: AppIcons.delete,
                fullWidth: true,
              ),
            ],
          ],
        ),
      ),
    );
    // Block back/drag dismiss while the save request is in flight. 모아 둔
    // 운동이 있으면 뒤로 가기도 버릴지 먼저 묻는다(#2544).
    return PopScope(
      canPop: !_saving && _queue.isEmpty,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && !_saving) unawaited(_requestClose());
      },
      child: sheet,
    );
  }
}

/// `추가할 운동` 목록의 한 줄 — 이름과 유형·운동량·강도·칼로리, 그리고 빼기.
/// (#2544)
///
/// 저장된 기록 줄(`직접 기록한 운동`)과 같은 흰 카드·같은 표기 함수를 쓴다.
/// 저장하기 전에 본 줄과 저장한 뒤 목록에 선 줄이 같은 모양으로 읽혀야 한다.
class _QueuedExerciseTile extends StatelessWidget {
  const _QueuedExerciseTile({
    super.key,
    required this.draft,
    required this.onRemove,
  });

  final ExerciseSessionDraft draft;

  /// 목록에서 뺀다. 저장 중에는 null 이다.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ExerciseSession preview = draft.toPreview();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        OnCareSpacing.s16,
        OnCareSpacing.s12,
        OnCareSpacing.s4,
        OnCareSpacing.s12,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  draft.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Wrap(
                  spacing: OnCareSpacing.s4,
                  runSpacing: OnCareSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    AppTag(label: exerciseTypeLabel(l, draft.type)),
                    AppTag(label: exerciseAmountLabel(l, preview)),
                    AppTag(label: exerciseIntensityLabel(l, draft.intensity)),
                    Text(
                      l.unitKcalValue(draft.calories),
                      style: tokens
                          .text(OnCareTypography.bodySmall)
                          .copyWith(color: OnCareColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppIconButton(
            key: const Key('exerciseQueueRemoveButton'),
            // 식단 직접 추가의 음식 줄 빼기와 같은 휴지통이다.
            icon: AppIcons.delete,
            tooltip: l.exQueueRemove,
            size: AppIconButtonSize.small,
            color: OnCareColors.textTertiary,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 예상 소모 칼로리 상자. (#1312)
///
/// 이름이 차기 전에는 **숫자를 띄우지 않는다.** 예전에는 시트를 여는 순간
/// 기본값만으로 확정된 듯한 값이 떠 있었고, 이름 칸은 계산에 아무 영향이
/// 없었다 — 그 숫자가 무엇을 근거로 나왔는지도 이름이 왜 필수인지도 화면에서
/// 읽히지 않았다.
///
/// 값이 있을 때는 근거를 함께 적는다. 종목 참조표와 회원 체중에서 나온 값과,
/// 이름이 종목으로 접히지 않아 유형 평균으로 때운 값은 같은 굵기로 적혀서는
/// 안 된다 — 식단이 공공 DB 값과 추정값을 나눠 보여 주는 것과 같은 규약이다.
class _CalorieBox extends StatelessWidget {
  const _CalorieBox({super.key, required this.estimate, required this.loading});

  final ExerciseCalorieEstimate? estimate;

  /// 계산이 도는 중. 이름을 막 적은 직후의 빈 칸을 "값이 없다" 로 읽히지 않게
  /// 한다 — 곧 채워질 자리다.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final ExerciseCalorieEstimate? value = estimate;
    return AppTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIcon(
                AppIcons.calories,
                color: OnCareColors.cautionFill,
                size: OnCareSize.iconMedium,
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: Text(
                  l.exEstimatedCalories,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
              ),
              if (value == null)
                Text(
                  loading ? l.exCaloriesCalculating : l.exCaloriesNeedName,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                )
              else
                Text(
                  l.unitKcalValue(value.calories),
                  style: OnCareTypography.numeric(
                    tokens.text(OnCareTypography.titleSmall),
                  ).copyWith(color: tokens.brand.primary),
                ),
            ],
          ),
          if (value != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s4),
            Text(
              // 참조표로 계산했으면 무엇으로 계산했는지까지 말한다 — 회원이 적은
              // 말과 종목 이름이 다를 수 있다("런닝머신" → "러닝머신").
              value.source.isGrounded && value.matchedName.isNotEmpty
                  ? l.exCaloriesFromCatalog(value.matchedName)
                  : l.exCaloriesRoughEstimate,
              style: tokens
                  .text(OnCareTypography.caption)
                  .copyWith(color: OnCareColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 날짜 한 칸 — 눌러서 달력을 연다. 기본값은 오늘이다.
class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap, super.key});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Material(
      color: OnCareColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: OnCareRadius.mdAll,
        side: BorderSide(color: OnCareColors.lineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tokens.density.inputMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OnCareSpacing.s12),
            child: Row(
              children: <Widget>[
                AppIcon(
                  AppIcons.calendar,
                  size: OnCareSize.iconMedium,
                  color: tokens.brand.primary,
                ),
                const SizedBox(width: OnCareSpacing.s8),
                Expanded(
                  child: Text(
                    // 로케일이 정하는 날짜 문구. 하드코딩한 'yyyy.MM.dd' 로 적으면
                    // 영어 화면에도 한국식 표기가 남는다.
                    MaterialLocalizations.of(context).formatFullDate(date),
                    style: tokens
                        .text(OnCareTypography.strong(OnCareTypography.body))
                        .copyWith(color: OnCareColors.textPrimary),
                  ),
                ),
                const AppIcon(
                  AppIcons.expandMore,
                  size: OnCareSize.iconMedium,
                  color: OnCareColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `횟수`/`버티는 시간` 라벨과 그 오른쪽의 **회 / 초** 전환 칩.
///
/// 칸을 하나 더 두지 않고 한 칸을 바꿔 가며 쓴다(#1969). 근력 폼은 이미
/// 세트·횟수·중량 세 칸인데 대부분의 운동에 쓰이지 않는 네 번째 칸을 늘 띄워
/// 두면, 비어 있는 칸이 적어야 할 값처럼 읽힌다.
class _MeasureToggle extends StatelessWidget {
  const _MeasureToggle({
    required this.label,
    required this.repsLabel,
    required this.secondsLabel,
    required this.semanticsLabel,
    required this.isHold,
    required this.onChanged,
  });

  /// 지금 고른 단위의 칸 이름 — `횟수` 또는 `버티는 시간`.
  final String label;
  final String repsLabel;
  final String secondsLabel;

  /// 전환 칩 묶음이 무엇을 고르는 것인지 — 화면에는 칩의 단위만 보이므로,
  /// 읽어 주는 쪽에는 이 말이 있어야 `회` 가 무엇의 회인지 전해진다.
  final String semanticsLabel;
  final bool isHold;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: _Label(label)),
      Semantics(
        label: semanticsLabel,
        container: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppChoiceChip(
              key: const Key('exerciseMeasureReps'),
              label: repsLabel,
              selected: !isHold,
              onSelected: (bool _) => onChanged(false),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            AppChoiceChip(
              key: const Key('exerciseMeasureSeconds'),
              label: secondsLabel,
              selected: isHold,
              onSelected: (bool _) => onChanged(true),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.oncare
        .text(OnCareTypography.titleSmall)
        .copyWith(color: OnCareColors.textPrimary),
  );
}
