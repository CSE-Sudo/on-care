import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
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
Future<bool> confirmDeleteExerciseSession(
  BuildContext context,
  WidgetRef ref,
  ExerciseSession session,
) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final AppToastHost toast = AppToastHost.of(context);
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
  try {
    await ref.read(exerciseRepositoryProvider).deleteSession(id);
    // 목록·주간 통계·그래프가 한 번에 최신이 된다 — 추가 경로와 같은 무효화다.
    ref.invalidate(exerciseWeekProvider);
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
  late double _minutes = widget.session?.minutes.toDouble() ?? 30;
  // 근력은 시간이 아니라 **세트·횟수·중량**으로 재는 운동이다
  // (#1262, #1276, #1310). 분과 따로 들고 있어야 유형을 근력↔유산소로 오갈 때
  // 각자의 값이 남는다 — 하나로 쓰면 30분이 30세트가 되어 돌아온다.
  late double _sets = _initialSets(widget.session);
  late double _reps = (widget.session?.reps ?? 10).toDouble();
  late double _weight = widget.session?.weight ?? 20;
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
    if (_name.text.trim().isEmpty) {
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

  /// 저장·칼로리 계산이 쓰는 분. 근력이면 세트에서 환산한 값이다.
  int get _effectiveMinutes =>
      _isStrength ? _strengthMinutes : _minutes.round();

  /// 편집 시트 안에서 지운다 — 목록 줄에는 더 이상 휴지통을 두지 않는다.
  /// 지우기는 되돌릴 수 없는 동작이라, 고치는 화면 안에 한 번 더 들어와야만
  /// 닿을 수 있는 자리에 둔다(식단 탭의 끼니 수정 화면과 같은 자리, #1468).
  Future<void> _delete() async {
    final ExerciseSession? session = widget.session;
    if (session == null || _saving) return;
    final bool deleted = await confirmDeleteExerciseSession(
      context,
      ref,
      session,
    );
    if (deleted && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickDate() async {
    final DateTime now = nowKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      // 앞으로 한 기록은 없다 — 아직 하지 않은 운동을 적을 자리가 아니다.
      lastDate: _dateOnly(now),
    );
    if (picked != null && mounted) setState(() => _date = _dateOnly(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final String name = _name.text.trim();
    if (name.isEmpty) {
      toast.show(l.exEnterName, type: AppToastType.error);
      return;
    }
    final int minutes = _effectiveMinutes;
    if (minutes <= 0) {
      toast.show(
        _isStrength ? l.exEnterSets : l.exEnterDuration,
        type: AppToastType.error,
      );
      return;
    }
    // 근력이 아니면 세트·횟수·중량을 싣지 않는다 — 유산소를 세트로 세는
    // 화면은 없고, 유형을 바꾼 수정에서는 null 이 옛 값을 지운다.
    final int? sets = _isStrength ? _sets.round() : null;
    final int? reps = _isStrength ? _reps.round() : null;
    final double? weight = _isStrength ? _weight : null;
    final ExerciseType type = _typeFromIndex(_type);
    final ExerciseSession? editing = widget.session;
    if (editing != null && editing.id == null) {
      // No id → PUT impossible; don't silently create a duplicate session.
      toast.show(l.exCannotEdit, type: AppToastType.error);
      return;
    }
    // Intensity is persisted now, so always recompute calories from the
    // (restored or edited) level — no more preserving stale values.
    final ExerciseIntensity intensity = ExerciseIntensity.values[_level];
    // 화면이 보여 준 값을 그대로 싣는다 — 서버는 이 값을 쓰지 않고 같은 계산을
    // 다시 하지만(#1312), 서버가 없는 경로(목업 저장소)는 이 값을 기록에 남긴다.
    // 미리보기가 아직 안 돌아왔으면 앱이 아는 유형 평균으로 채운다.
    final int calories =
        _estimate?.calories ?? _estimateCalories(type, minutes, _level);

    setState(() => _saving = true);
    try {
      // 서버(mock 모드는 drift)에 저장 → 주간 데이터 무효화로 통계·차트·목록 반영.
      if (editing != null) {
        await ref
            .read(exerciseRepositoryProvider)
            .updateSession(
              id: editing.id!,
              type: type,
              name: name,
              minutes: minutes,
              calories: calories,
              intensity: intensity,
              date: _date,
              sets: sets,
              reps: reps,
              weight: weight,
            );
      } else {
        await ref
            .read(exerciseRepositoryProvider)
            .addSession(
              type: type,
              name: name,
              minutes: minutes,
              calories: calories,
              intensity: intensity,
              date: _date,
              sets: sets,
              reps: reps,
              weight: weight,
            );
      }
      // Sheet dismissed mid-save → don't pop the page below.
      if (!mounted) return;
      ref.invalidate(exerciseWeekProvider);
      navigator.pop(true);
      toast.show(
        widget.isEdit ? l.exUpdated : l.exLogged,
        type: AppToastType.success,
      );
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
      title: widget.isEdit ? l.exEditExercise : l.exAddExercise,
      // 이 시트를 끝내는 동작이다 — 하단에 넓은 주요 버튼으로 둔다. 저장 중에는
      // 비활성이 되어 두 번 눌리지 않는다.
      footer: AppButton(
        key: const Key('exerciseSaveButton'),
        label: l.exSave,
        onPressed: _saving ? null : _save,
        size: OnCareButtonSize.large,
        fullWidth: true,
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
              onChanged: (String _) => _scheduleEstimate(),
              onSubmitted: (String _) => _scheduleEstimate(immediate: true),
            ),
            const SizedBox(height: OnCareSpacing.s20),
            // 근력은 세트·횟수·중량으로, 나머지는 분으로 묻는다
            // (#1262, #1276, #1310).
            // 화면 여러 곳(홈 운동 카드·운동 현황 링·주간 목표)이 근력을
            // 세트로 읽는데 기록만 분이면, 회원이 적지 않은 수가 화면에 뜬다.
            if (_isStrength) ...<Widget>[
              _Label(l.exExerciseSets),
              const SizedBox(height: OnCareSpacing.s8),
              _NumberStepper(
                key: const Key('exerciseSetsStepper'),
                value: _sets,
                min: 1,
                max: 40,
                suffix: l.exUnitSets,
                onChanged: (double v) {
                  setState(() => _sets = v);
                  _scheduleEstimate();
                },
              ),
              const SizedBox(height: OnCareSpacing.s20),
              _Label(l.exExerciseReps),
              const SizedBox(height: OnCareSpacing.s8),
              _NumberStepper(
                key: const Key('exerciseRepsStepper'),
                value: _reps,
                min: 1,
                max: 999,
                suffix: l.exUnitReps,
                onChanged: (double v) => setState(() => _reps = v),
              ),
              const SizedBox(height: OnCareSpacing.s20),
              _Label(l.exExerciseWeight),
              const SizedBox(height: OnCareSpacing.s8),
              _NumberStepper(
                key: const Key('exerciseWeightStepper'),
                value: _weight,
                min: 0,
                max: 500,
                // 원판은 0.5kg 단위로 붙는다 — 버튼 한 번에 1kg 이 실용적인
                // 걸음이고, 소수 자리는 직접 적어 채운다.
                decimals: 1,
                suffix: l.exUnitKg,
                onChanged: (double v) => setState(() => _weight = v),
              ),
            ] else ...<Widget>[
              _Label(l.exExerciseDuration),
              const SizedBox(height: OnCareSpacing.s8),
              _NumberStepper(
                key: const Key('exerciseMinutesStepper'),
                value: _minutes,
                min: 1,
                max: 600,
                suffix: l.exUnitMinutes,
                onChanged: (double v) {
                  setState(() => _minutes = v);
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
                leadingIcon: Icons.delete_rounded,
                fullWidth: true,
              ),
            ],
          ],
        ),
      ),
    );
    // Block back/drag dismiss while the save request is in flight.
    return PopScope(canPop: !_saving, child: sheet);
  }
}

/// 숫자 한 칸 — 직접 입력하는 텍스트 필드와 양옆의 −/+ 버튼. (#1276)
///
/// 회원이 아는 값(45분·12세트·62.5kg)을 그대로 적고, 한 칸씩 고칠 때만 버튼을
/// 쓴다. 공용 스테퍼는 정수만 다루고 직접 입력이 없어, 소수 중량과 타이핑을
/// 받는 이 폼은 공용 입력창·아이콘 버튼으로 같은 규격의 칸을 짠다.
///
/// [decimals] 가 0 보다 크면 소수 입력을 허용하고 그 자리까지 반올림한다.
class _NumberStepper extends StatefulWidget {
  const _NumberStepper({
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.decimals = 0,
    this.suffix,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  /// 소수점 자릿수. 0 이면 정수로 읽고 쓴다.
  final int decimals;

  /// 필드 오른쪽에 붙는 단위 문구("분", "세트", "kg").
  final String? suffix;

  @override
  State<_NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<_NumberStepper> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 포커스를 잃을 때 비워 둔 칸이나 범위 밖 값을 되돌린다. 타이핑 도중에
    // 고치면 "1" 을 지나 "12" 로 가는 길이 막힌다.
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(_controller.text);
    });
  }

  @override
  void didUpdateWidget(_NumberStepper old) {
    super.didUpdateWidget(old);
    // 밖에서 값이 바뀐 경우(유형 전환 등)만 필드를 다시 그린다 — 편집 중인
    // 문자열을 덮어쓰면 커서가 튄다.
    if (widget.value != old.value && !_focus.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(double v) => widget.decimals == 0
      ? v.round().toString()
      : v.toStringAsFixed(widget.decimals);

  double _clamp(double v) => v.clamp(widget.min, widget.max);

  double _round(double v) => widget.decimals == 0
      ? v.roundToDouble()
      : double.parse(v.toStringAsFixed(widget.decimals));

  /// 적히는 대로 값을 올린다. **필드의 글자는 건드리지 않는다** — 정리는
  /// 포커스를 잃을 때 [_commit] 이 한다.
  void _typed(String raw) {
    final double? parsed = double.tryParse(raw.trim());
    if (parsed != null) widget.onChanged(_round(_clamp(parsed)));
  }

  /// 비워 둔 칸이나 범위 밖 값을 되돌리고 글자를 다시 그린다.
  void _commit(String raw) {
    if (!mounted) return;
    final double next = _round(
      _clamp(double.tryParse(raw.trim()) ?? widget.value),
    );
    _controller.text = _format(next);
    widget.onChanged(next);
  }

  void _bump(double delta) {
    _focus.unfocus();
    _commit(
      ((double.tryParse(_controller.text.trim()) ?? widget.value) + delta)
          .toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final String? suffix = widget.suffix;
    return Row(
      children: <Widget>[
        AppIconButton(
          key: const Key('numberStepperDecrement'),
          icon: Icons.remove_rounded,
          tooltip: l.exStepperDecrease,
          color: tokens.brand.primary,
          onPressed: widget.value > widget.min ? () => _bump(-1) : null,
        ),
        const SizedBox(width: OnCareSpacing.s12),
        Expanded(
          child: AppTextField(
            key: const Key('numberStepperField'),
            controller: _controller,
            focusNode: _focus,
            keyboardType: TextInputType.numberWithOptions(
              decimal: widget.decimals > 0,
            ),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(
                widget.decimals > 0 ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
              ),
            ],
            onChanged: _typed,
            onSubmitted: _commit,
            suffix: suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: OnCareSpacing.s12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        suffix,
                        style: tokens
                            .text(OnCareTypography.label)
                            .copyWith(color: OnCareColors.textSecondary),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s12),
        AppIconButton(
          key: const Key('numberStepperIncrement'),
          icon: Icons.add_rounded,
          tooltip: l.exStepperIncrease,
          color: tokens.brand.primary,
          onPressed: widget.value < widget.max ? () => _bump(1) : null,
        ),
      ],
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
              const Icon(
                Icons.local_fire_department_rounded,
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
      color: OnCareColors.surfaceInput,
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
                Icon(
                  Icons.calendar_today_rounded,
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
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
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
