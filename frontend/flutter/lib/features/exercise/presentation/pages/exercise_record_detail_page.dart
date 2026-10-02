import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_limits.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_load.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_refresh.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// [date] 에 회원이 직접 적은 운동 기록을 한 화면에 연다. (#2507)
///
/// 식단 탭의 끼니 카드와 같은 흐름이다 — 목록 카드 `›` 를 누르면 한 단계
/// 들어가 세부를 **보고**, 연필을 눌러야 고친다(#1848). 끼니 상세가 음식
/// 여러 개를 함께 보이듯 그날 기록을 모두 보인다: 여러 운동을 한 번에 적을 수
/// 있는데(#2544) 하나씩 열면 화면이 비고, 같이 한 운동을 오가며 봐야 했다.
Future<void> openExerciseDayDetail(BuildContext context, DateTime date) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(builder: (_) => ExerciseDayDetailPage(date: date)),
  );
}

/// 그날 직접 기록한 운동 상세.
///
/// 식단 끼니 상세처럼 상자를 나눈다 — `운동 정보`(날짜), 운동마다 상자 하나,
/// 맨 아래 `총 소모 칼로리`. 운동 상자는 식단 `영양 정보` 처럼 `항목 … 값 단위`
/// 줄로 세부를 보인다(운동 시간 40분, 세트 수 4세트 …).
///
/// 고치기도 식단 끼니 상세와 같다(#2964). `운동 정보` 머리의 연필을 누르면
/// 같은 줄의 값 자리가 그대로 입력 칸이 되고, 아래 `취소`·`저장` 으로 마친다.
/// 예전처럼 운동마다 수정 시트(모달)를 띄우지 않는다. 날짜는 연필과 따로
/// `날짜 변경` 을 눌러야 옮겨지고, 고른 즉시 저장된다.
class ExerciseDayDetailPage extends ConsumerStatefulWidget {
  /// 화면은 같은 주의 자료에서 그날 기록을 다시 거른다 — 저장하면 고친 값이,
  /// 지우면 그 상자가 사라진 것이 바로 보인다.
  const ExerciseDayDetailPage({super.key, required this.date});

  final DateTime date;

  @override
  ConsumerState<ExerciseDayDetailPage> createState() =>
      _ExerciseDayDetailPageState();
}

class _ExerciseDayDetailPageState extends ConsumerState<ExerciseDayDetailPage> {
  /// 지금 보고 있는 날. `날짜 변경` 으로 옮기면 화면이 옮긴 날을 따라간다.
  late DateTime _date = widget.date;

  bool _editing = false;
  bool _saving = false;
  bool _movingDate = false;

  /// 운동 상자마다 하나. 수정 모드에서 저장할 값을 모은다.
  final Map<String, GlobalKey<_ExerciseCardState>> _cards =
      <String, GlobalKey<_ExerciseCardState>>{};

  /// 목록과 **같은 주 자료**를 읽는다 — 이번 주면 이번 주, 아니면 그 주.
  AsyncValue<ExerciseWeek> _weekOf(DateTime date) {
    final DateTime weekStart = mondayOfWeek(date);
    if (weekStart == mondayOfWeek(nowKst())) {
      return ref.watch(exerciseWeekProvider);
    }
    return ref.watch(exercisePastWeekProvider(weekStart));
  }

  GlobalKey<_ExerciseCardState> _cardKey(String id) => _cards.putIfAbsent(
    id,
    () => GlobalKey<_ExerciseCardState>(debugLabel: 'exercise-$id'),
  );

  Widget _card(ExerciseSession s, bool busy) => _ExerciseCard(
    key: s.id == null ? null : _cardKey(s.id!),
    session: s,
    editing: _editing && s.id != null,
    busy: busy,
    onChanged: () => setState(() {}),
  );

  _ExerciseCardState? _stateOf(ExerciseSession s) =>
      s.id == null ? null : _cards[s.id!]?.currentState;

  /// 그날 운동의 소모 칼로리 합. 수정 중이면 상자가 고치고 있는 값이다.
  int _liveTotal(List<ExerciseSession> sessions) => sessions.fold<int>(
    0,
    (int sum, ExerciseSession s) =>
        sum + (_stateOf(s)?.liveCalories ?? s.calories),
  );

  void _beginEdit() => setState(() => _editing = true);

  /// 수정을 접는다. 고치던 값은 버리고 저장된 값으로 돌아간다 — 화면을
  /// 나가지는 않고 보기로만 돌아간다.
  void _cancelEdit() {
    for (final GlobalKey<_ExerciseCardState> key in _cards.values) {
      key.currentState?.reset();
    }
    setState(() => _editing = false);
  }

  /// 그날 기록을 모두 고른 날로 옮긴다. 연필을 누르지 않아도 되고, 고른 즉시
  /// 저장한다 — 식단 끼니 상세의 `날짜 변경` 과 같다(#1947, #2964).
  ///
  /// 수정 중에 옮겨도 고치던 값은 그대로 남고, `취소` 가 날짜를 되돌리지 않는다.
  Future<void> _pickDate(List<ExerciseSession> sessions) async {
    if (_movingDate || _saving) return;
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      // 앞으로 한 기록은 없다 — 아직 하지 않은 운동을 적을 자리가 아니다.
      lastDate: today,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    final DateTime chosen = DateTime(picked.year, picked.month, picked.day);
    if (chosen == _date) return;

    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final String label = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).format(chosen);
    setState(() => _movingDate = true);
    try {
      await ref.read(exerciseChangeRunnerProvider).run((
        ExerciseRepository r,
      ) async {
        for (final ExerciseSession s in sessions) {
          final String? id = s.id;
          if (id == null) continue;
          await r.updateSession(
            id: id,
            type: s.type,
            name: s.name,
            minutes: s.minutes,
            calories: s.calories,
            intensity: s.intensity,
            date: chosen,
            sets: s.sets,
            reps: s.reps,
            holdSeconds: s.holdSeconds,
            durationSeconds: s.durationSeconds,
            weight: s.weight,
          );
        }
      });
      if (!mounted) return;
      setState(() {
        _date = chosen;
        _movingDate = false;
      });
      // 목록으로 돌아가면 이 기록이 원래 날에서 사라진다 — 어디로 갔는지 말한다.
      toast.show(l.exRecordDateMoved(label), type: AppToastType.success);
    } on Object {
      if (mounted) setState(() => _movingDate = false);
      toast.show(l.exRecordDateFailed, type: AppToastType.error);
    }
  }

  /// 수정 모드의 상자를 모두 저장한다. 하나라도 비었으면 아무것도 보내지 않는다.
  /// 고치지 않은 상자는 보내지 않는다.
  Future<void> _save(List<ExerciseSession> sessions) async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final List<(String, ExerciseSessionDraft)> drafts =
        <(String, ExerciseSessionDraft)>[];
    for (final ExerciseSession s in sessions) {
      final String? id = s.id;
      final _ExerciseCardState? card = id == null
          ? null
          : _cards[id]?.currentState;
      if (id == null || card == null) continue;
      final String? problem = card.problem(l);
      if (problem != null) {
        toast.show(problem, type: AppToastType.error);
        return;
      }
      if (card.changed) drafts.add((id, card.draft(_date)));
    }
    FocusScope.of(context).unfocus();
    if (drafts.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(exerciseChangeRunnerProvider).run((
        ExerciseRepository r,
      ) async {
        for (final (String id, ExerciseSessionDraft d) in drafts) {
          await r.updateSession(
            id: id,
            type: d.type,
            name: d.name,
            minutes: d.minutes,
            calories: d.calories,
            intensity: d.intensity,
            date: d.date,
            sets: d.sets,
            reps: d.reps,
            holdSeconds: d.holdSeconds,
            durationSeconds: d.durationSeconds,
            weight: d.weight,
          );
        }
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      toast.show(l.exUpdated, type: AppToastType.success);
    } on Object {
      if (mounted) setState(() => _saving = false);
      toast.show(l.exSaveFailed, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<ExerciseWeek> async = _weekOf(_date);
    final ExerciseWeek? week = async.valueOrNull;
    final List<ExerciseSession> sessions = week == null
        ? const <ExerciseSession>[]
        : ownExerciseSessionsOn(week, _date);
    // 마지막 기록을 지웠다 — 볼 것이 없으니 목록으로 돌아간다. 날짜를 옮긴
    // 직후 새 자료를 받는 중에는 옛 자료에 그날 기록이 없을 뿐이라 기다린다.
    if (week != null && sessions.isEmpty && !async.isLoading && !_movingDate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    final double side = context.oncare.density.pagePadding;
    final bool busy = _saving || _movingDate;
    final Widget page = Scaffold(
      key: const Key('exerciseRecordDetailPage'),
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: l.exExerciseLog),
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
                  child: GestureDetector(
                    // 칸 밖을 누르면 키보드를 닫는다.
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        OnCareSpacing.s8,
                        side,
                        OnCareSpacing.sectionGap,
                      ),
                      children: <Widget>[
                        _RecordInfoCard(
                          date: _date,
                          editing: _editing,
                          movingDate: _movingDate,
                          onEdit: sessions.isEmpty || busy ? null : _beginEdit,
                          onChangeDate: sessions.isEmpty || busy
                              ? null
                              : () => _pickDate(sessions),
                        ),
                        // 식단 `먹은 음식` 처럼 흰 카드 하나에 운동을 잇는다 — 보기는
                        // 운동마다 한 줄, 수정은 운동마다 회색 칸. 맨 아래 합계 한 줄.
                        if (sessions.isNotEmpty) ...<Widget>[
                          const SizedBox(height: OnCareSpacing.cardGap),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _CardTitle(l.exOwnRecords),
                                const SizedBox(height: OnCareSpacing.s12),
                                for (
                                  int i = 0;
                                  i < sessions.length;
                                  i++
                                ) ...<Widget>[
                                  // 보기는 줄 사이에 얇은 선을 둬 운동마다 한
                                  // 칸으로 읽히게 한다. 수정은 회색 칸끼리 띄운다.
                                  if (i > 0)
                                    _editing
                                        ? const SizedBox(
                                            height: OnCareSpacing.s8,
                                          )
                                        : const AppDivider(),
                                  _card(sessions[i], busy),
                                ],
                                const SizedBox(height: OnCareSpacing.s12),
                                const AppDivider(),
                                const SizedBox(height: OnCareSpacing.s12),
                                _TotalCaloriesRow(total: _liveTotal(sessions)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // 취소·저장은 수정 중일 때만 있다 — 식단 끼니 상세와 같은 자리다.
                if (_editing)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: AppButtonPair(
                      cancelKey: const Key('exerciseCancelButton'),
                      cancelLabel: l.actionCancel,
                      onCancel: busy ? null : _cancelEdit,
                      confirmKey: const Key('exerciseSaveButton'),
                      confirmLabel: l.exSave,
                      onConfirm: busy ? null : () => _save(sessions),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // 저장·날짜 이동 중에는 뒤로 가지 않는다.
    return PopScope(canPop: !busy, child: page);
  }
}

TextStyle _style(BuildContext context, TextStyle base, Color color) =>
    context.oncare.text(base).copyWith(color: color);

String _kcal(AppLocalizations l, int kcal) =>
    '${NumberFormat('#,###').format(kcal)} ${l.unitKcal}';

/// 상자 제목 — 식단 끼니 상세의 `식사 정보`·`먹은 음식` 과 같은 모양.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: _style(
      context,
      OnCareTypography.titleSmall,
      OnCareColors.textPrimary,
    ),
  );
}

/// `운동 정보` — 언제 한 운동인가. 머리에 연필, 날짜 줄에 `날짜 변경`.
///
/// 연필은 첫 상자에 둔다 — 식단 끼니 상세의 `식사 정보` 와 같은 자리다(#2964).
class _RecordInfoCard extends StatelessWidget {
  const _RecordInfoCard({
    required this.date,
    required this.editing,
    required this.movingDate,
    required this.onEdit,
    required this.onChangeDate,
  });

  final DateTime date;
  final bool editing;
  final bool movingDate;
  final VoidCallback? onEdit;
  final VoidCallback? onChangeDate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    // 연필 자리 높이를 수정 중에도 잡아 둔다 — 연필이 빠지며 상자가 줄면
    // 아래 상자들이 한꺼번에 위로 튄다.
    final double iconSlot = tokens.density.buttonHeight(OnCareButtonSize.small);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: iconSlot,
            child: Row(
              children: <Widget>[
                Expanded(child: _CardTitle(l.exRecordDetailInfo)),
                if (!editing)
                  AppIconButton(
                    key: const Key('exercise-detail-edit'),
                    icon: AppIcons.edit,
                    tooltip: l.exEditExercise,
                    size: AppIconButtonSize.small,
                    // 연필은 앱 전체에서 회색이다 — 목록의 `›` 와 같은 색(#2507).
                    color: OnCareColors.textTertiary,
                    onPressed: onEdit,
                  ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Row(
            children: <Widget>[
              Text(
                l.exExerciseDate,
                style: _style(
                  context,
                  OnCareTypography.bodySmall,
                  OnCareColors.textSecondary,
                ),
              ),
              const SizedBox(width: OnCareSpacing.s16),
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatFullDate(date),
                  key: const Key('exercise-detail-date'),
                  style: _style(
                    context,
                    OnCareTypography.strong(OnCareTypography.bodySmall),
                    OnCareColors.textPrimary,
                  ),
                ),
              ),
              // 옮기는 동안 버튼이 spinner 로 바뀌어도 줄 높이가 튀지 않게
              // 자리를 잡는다 — 식단 끼니 상세와 같다.
              SizedBox(
                height: iconSlot,
                child: Center(
                  child: movingDate
                      ? const AppLoading.inline()
                      : AppButton(
                          key: const Key('exercise-detail-date-change'),
                          label: l.exRecordDateChange,
                          onPressed: onChangeDate,
                          variant: AppButtonVariant.text,
                          size: OnCareButtonSize.small,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 수정 모드에서 고를 수 있는 운동 종류 — 추가 시트의 칩과 같은 네 가지다.
const List<ExerciseType> _types = <ExerciseType>[
  ExerciseType.cardio,
  ExerciseType.strength,
  ExerciseType.stretching,
  ExerciseType.other,
];

/// 운동 하나 — 머리 `[유형] 이름 kcal`, 아래로 식단 `영양 정보` 같은
/// `항목 … 값 단위` 줄.
///
/// 보기와 수정이 **같은 줄**이다(#2964). 연필을 누르면 값 자리만 입력 칸·칩으로
/// 바뀐다 — 식단 상세에서 음식 줄이 그 자리에서 수정 칸이 되는 것과 같다.
/// 지우기는 수정 모드에서만 상자 맨 아래에 있다(#1468).
class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({
    super.key,
    required this.session,
    required this.editing,
    required this.busy,
    this.onChanged,
  });

  final ExerciseSession session;
  final bool editing;
  final bool busy;

  /// 수정 중 값이 바뀌었다 — 화면이 `총 소모 칼로리` 를 다시 그린다.
  final VoidCallback? onChanged;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  late ExerciseType _type;
  late ExerciseIntensity _intensity;
  late bool _isHold;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _hours = TextEditingController();
  final TextEditingController _minutes = TextEditingController();
  final TextEditingController _seconds = TextEditingController();
  final TextEditingController _sets = TextEditingController();
  final TextEditingController _reps = TextEditingController();
  final TextEditingController _hold = TextEditingController();
  final TextEditingController _weight = TextEditingController();

  ExerciseSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    reset();
  }

  @override
  void didUpdateWidget(covariant _ExerciseCard old) {
    super.didUpdateWidget(old);
    // 저장 뒤 새 값이 들어오면 칸도 그 값으로 맞춘다. 고치는 중에는 건드리지
    // 않는다 — 날짜를 옮겨 목록이 다시 그려져도 적던 값이 남는다.
    if (!widget.editing && old.session != widget.session) reset();
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name,
      _hours,
      _minutes,
      _seconds,
      _sets,
      _reps,
      _hold,
      _weight,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 걸린 시간(초). 초를 모르는 옛 기록은 분에서 환산한다.
  int get _savedSeconds {
    final int? s = _s.durationSeconds;
    return s != null && s > 0 ? s : _s.minutes * 60;
  }

  /// 칸을 저장된 값으로 되돌린다.
  void reset() {
    _type = _types.contains(_s.type)
        ? _s.type
        : (_s.type == ExerciseType.yoga
              ? ExerciseType.stretching
              : ExerciseType.cardio);
    _intensity = _s.intensity;
    _isHold = _s.holdSeconds != null;
    _name.text = _s.name;
    _hours.text = '${_savedSeconds ~/ 3600}';
    _minutes.text = '${_savedSeconds % 3600 ~/ 60}';
    _seconds.text = '${_savedSeconds % 60}';
    _sets.text = '${_s.sets ?? setsFromStrengthMinutes(_s.minutes.toDouble())}';
    _reps.text = '${_s.reps ?? 10}';
    _hold.text = '${_s.holdSeconds ?? 60}';
    _weight.text = _weightText(_s.weight ?? 20);
    if (mounted) setState(() {});
  }

  static String _weightText(double kg) =>
      kg == kg.roundToDouble() ? '${kg.round()}' : '$kg';

  static int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  bool get _isStrength => _type == ExerciseType.strength;

  int get _durationSeconds => math.min(
    _int(_hours) * 3600 + _int(_minutes) * 60 + _int(_seconds),
    kMaxExerciseMinutes * 60,
  );

  int get _setCount => _int(_sets).clamp(0, kMaxExerciseSets);

  /// 저장·칼로리 계산이 쓰는 분 — 추가 시트와 같은 환산이다(근력은 세트에서,
  /// 아니면 초에서. 서버 `_minutes_from_seconds` 와 같은 규칙).
  int get _effectiveMinutes {
    if (_isStrength) {
      return (_setCount * kStrengthMinutesPerSetWithRest).round();
    }
    final int s = _durationSeconds;
    return s <= 0 ? 0 : math.max(1, (s / 60).round());
  }

  /// 저장할 수 없는 까닭. 저장할 수 있으면 null.
  String? problem(AppLocalizations l) {
    if (!widget.editing) return null;
    if (_name.text.trim().isEmpty) return l.exEnterName;
    if (_effectiveMinutes <= 0) {
      return _isStrength ? l.exEnterSets : l.exEnterDuration;
    }
    return null;
  }

  /// 고친 값의 소모 칼로리 어림값. 서버는 저장할 때 같은 계산을 다시 한다(#1312).
  ///
  /// 종류·강도가 그대로면 저장된 값을 시간에 비례해 늘리고 줄인다 — 표의 평균으로
  /// 새로 어림하면 시간만 조금 고쳐도 숫자가 크게 튀어, 무엇이 바뀌었는지 읽히지
  /// 않는다. 종류·강도가 바뀌면 그 종류의 어림값이다.
  int _caloriesFor(int minutes) {
    if (_type == _s.type && _intensity == _s.intensity && _s.minutes > 0) {
      return (_s.calories * minutes / _s.minutes).round();
    }
    return estimateExerciseCalories(_type, minutes, intensity: _intensity);
  }

  ExerciseSessionDraft draft(DateTime date) {
    final int minutes = _effectiveMinutes;
    return ExerciseSessionDraft(
      type: _type,
      name: _name.text.trim(),
      minutes: minutes,
      calories: _caloriesFor(minutes),
      intensity: _intensity,
      date: date,
      sets: _isStrength ? _setCount : null,
      reps: _isStrength && !_isHold
          ? _int(_reps).clamp(1, kMaxExerciseReps)
          : null,
      holdSeconds: _isStrength && _isHold
          ? _int(_hold).clamp(1, kMaxExerciseHoldSeconds)
          : null,
      durationSeconds: _isStrength ? null : _durationSeconds,
      weight: _isStrength
          ? snapExerciseWeight(
              (double.tryParse(_weight.text.trim()) ?? 0).clamp(
                0,
                kMaxExerciseWeightKg,
              ),
            )
          : null,
    );
  }

  int get liveCalories {
    if (!widget.editing) return _s.calories;
    // 고치지 않은 운동은 저장된 값 그대로다.
    if (!changed) return _s.calories;
    if (_effectiveMinutes <= 0) return 0;
    return _caloriesFor(_effectiveMinutes);
  }

  /// 저장된 값과 다른가 — 고치지 않은 상자는 저장하지 않는다.
  bool get changed {
    if (!widget.editing) return false;
    final ExerciseSessionDraft d = draft(_s.date ?? nowKst());
    return d.type != _s.type ||
        d.name != _s.name ||
        d.intensity != _s.intensity ||
        d.sets != (_isStrength ? _s.sets : null) ||
        d.reps != (_isStrength && !_isHold ? _s.reps : null) ||
        d.holdSeconds != (_isStrength && _isHold ? _s.holdSeconds : null) ||
        d.weight != (_isStrength ? _s.weight : null) ||
        (!_isStrength && d.durationSeconds != _savedSeconds);
  }

  Future<void> _delete() async {
    await confirmDeleteExerciseSession(context, ref, _s);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String id = _s.id ?? '';
    final bool editing = widget.editing;
    final String name = _s.name.isNotEmpty
        ? _s.name
        : exerciseTypeLabel(l, _s.type);
    // 고친 값은 화면 아래 `총 소모 칼로리` 에도 바로 반영한다.
    void changed() {
      setState(() {});
      widget.onChanged?.call();
    }

    final List<Widget> rows = <Widget>[
      if (_isStrength) ...<Widget>[
        _DetailRow(
          label: l.exExerciseSets,
          value: _sets,
          unit: l.exUnitSets,
          editing: editing,
          fieldKey: 'exercise-detail-sets-$id',
          onChanged: changed,
        ),
        if (_isHold)
          _DetailRow(
            label: l.exExerciseHold,
            value: _hold,
            unit: l.exUnitSeconds,
            editing: editing,
            fieldKey: 'exercise-detail-hold-$id',
            onChanged: changed,
          )
        else
          _DetailRow(
            label: l.exExerciseReps,
            value: _reps,
            unit: l.exUnitReps,
            editing: editing,
            fieldKey: 'exercise-detail-reps-$id',
            onChanged: changed,
          ),
        _DetailRow(
          label: l.exExerciseWeight,
          value: _weight,
          unit: l.exUnitKg,
          decimal: true,
          editing: editing,
          fieldKey: 'exercise-detail-weight-$id',
          onChanged: changed,
        ),
      ] else
        // 시간은 추가 시트의 휠처럼 시·분·초 세 칸이다 — 45초짜리도, 한 시간이
        // 넘는 운동도 환산 없이 적는다(#2071). 세 칸이 라벨 옆에 서지 못해
        // 수정 중에는 라벨 아래 줄에 둔다. 보기에서는 0 인 시간·초를 뺀다.
        _DetailRow(
          label: l.exExerciseDuration,
          editing: editing,
          stacked: true,
          parts: <(TextEditingController, String, String)>[
            if (editing || _int(_hours) > 0)
              (_hours, l.exUnitHours, 'exercise-detail-hours-$id'),
            (_minutes, l.exUnitMinutes, 'exercise-detail-minutes-$id'),
            if (editing || _int(_seconds) > 0)
              (_seconds, l.exUnitSeconds, 'exercise-detail-seconds-$id'),
          ],
          onChanged: changed,
        ),
      _DetailRow(
        label: l.exExerciseIntensity,
        editing: editing,
        child: editing
            ? Wrap(
                alignment: WrapAlignment.end,
                spacing: OnCareSpacing.s4,
                children: <Widget>[
                  for (final ExerciseIntensity v in ExerciseIntensity.values)
                    AppChoiceChip(
                      label: exerciseIntensityLabel(l, v),
                      selected: _intensity == v,
                      onSelected: (bool _) {
                        _intensity = v;
                        changed();
                      },
                    ),
                ],
              )
            : Text(
                exerciseIntensityLabel(l, _s.intensity),
                key: ValueKey<String>('exercise-detail-intensity-$id'),
                style: _style(
                  context,
                  OnCareTypography.strong(OnCareTypography.bodySmall),
                  OnCareColors.textPrimary,
                ),
              ),
      ),
    ];
    final List<Widget> spaced = <Widget>[
      for (int i = 0; i < rows.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: OnCareSpacing.s8),
        rows[i],
      ],
    ];

    // 수정 모드는 식단 `먹은 음식` 의 수정 칸과 같은 회색 상자다(#2964). 상자들은
    // 화면이 흰 카드 하나에 이어 붙인다. 위쪽은 운동 추가 시트와 같은 순서다 —
    // `운동 종류` 아래 칩 넷, 그 아래 이름 칸. 아래로 같은 `항목 … 값 단위` 줄.
    if (editing) {
      final TextStyle labelStyle = _style(
        context,
        OnCareTypography.strong(OnCareTypography.bodySmall),
        OnCareColors.textPrimary,
      );
      return AppTile(
        key: ValueKey<String>('exercise-detail-editor-$id'),
        tone: AppTileTone.neutral,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l.exExerciseType, style: labelStyle),
            const SizedBox(height: OnCareSpacing.s8),
            Wrap(
              spacing: OnCareSpacing.s8,
              runSpacing: OnCareSpacing.s8,
              children: <Widget>[
                for (final ExerciseType t in _types)
                  AppChoiceChip(
                    key: ValueKey<String>('exercise-detail-type-${t.name}-$id'),
                    label: exerciseTypeLabel(l, t),
                    selected: _type == t,
                    onSelected: (bool _) {
                      _type = t;
                      changed();
                    },
                  ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s12),
            // 예시 문구는 고른 종류를 따라간다 — 추가 시트와 같다(#1460).
            Row(
              children: <Widget>[
                Expanded(
                  child: AppTextField(
                    key: ValueKey<String>('exercise-detail-name-field-$id'),
                    controller: _name,
                    hint: _nameHint(l),
                    maxLength: 100,
                    onChanged: (_) => changed(),
                  ),
                ),
                // 지우기는 식단 음식 칸처럼 이름 옆 휴지통이다(#1468) —
                // 확인창을 거친 뒤에만 지운다.
                AppIconButton(
                  key: const Key('exerciseDeleteButton'),
                  icon: AppIcons.delete,
                  tooltip: l.exDeleteExercise,
                  size: AppIconButtonSize.small,
                  color: OnCareColors.textTertiary,
                  onPressed: widget.busy ? null : _delete,
                ),
              ],
            ),
            const SizedBox(height: OnCareSpacing.s8),
            ...spaced,
            const SizedBox(height: OnCareSpacing.s12),
            _CalorieBox(
              key: ValueKey<String>('exercise-detail-calorie-box-$id'),
              calories: liveCalories,
            ),
          ],
        ),
      );
    }

    // 보기는 운동마다 한 줄이다 — 식단 보기의 음식 줄(`이름 양 … kcal`)과
    // 같다(#2964). 항목별 세부는 연필을 눌러야 펼쳐진다. 강도는 운동 탭 목록
    // 줄이 이미 보여 주므로 여기서는 운동량과 소모 칼로리만 둔다. 운동량은
    // 목록 줄과 같은 표기 함수를 써, 목록에서 본 것과 같게 읽힌다.
    // 칸마다 위아래 여백을 둔다 — 줄이 붙어 보였다.
    return Padding(
      key: ValueKey<String>('exercise-detail-card-$id'),
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s16),
      child: Row(
        children: <Widget>[
          // 태그 자리 폭을 가장 긴 `스트레칭` 에 맞춰 고정한다 — 태그 폭을 따라가면
          // 이름이 시작하는 자리가 줄마다 어긋났다.
          SizedBox(
            width: _typeTagWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppTag(
                label: exerciseTypeLabel(l, _s.type),
                tone: AppTagTone.brand,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  key: ValueKey<String>('exercise-detail-name-$id'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(
                    context,
                    OnCareTypography.strong(OnCareTypography.body),
                    OnCareColors.textPrimary,
                  ),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                // 개인 기록 태그는 운동량 옆 하나다(#2971) — 그 운동량에 대한
                // 사실이고, 이름 옆에 두면 오른쪽 칼로리와 자리를 다퉈 이름이
                // 잘렸다. 운동 현황의 `N일 연속` 과 같은 주황이다.
                Wrap(
                  spacing: OnCareSpacing.s8,
                  runSpacing: OnCareSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      exerciseAmountLabel(l, _s),
                      key: ValueKey<String>('exercise-detail-amount-$id'),
                      style: _style(
                        context,
                        OnCareTypography.caption,
                        OnCareColors.textSecondary,
                      ),
                    ),
                    if (_s.record case final ExerciseRecord record)
                      AppTag(
                        key: ValueKey<String>('exercise-detail-record-$id'),
                        label: exerciseRecordLabel(l, record),
                        icon: exerciseRecordIcon(record),
                        tone: AppTagTone.caution,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          // 숫자 앞에 `소모` 를 붙인다 — 운동 줄의 kcal 가 먹은 열량이 아니라 태운
          // 열량이라는 것을 숫자만으로는 가를 수 없다.
          Text(
            l.exBurnedPrefix,
            style: _style(
              context,
              OnCareTypography.caption,
              OnCareColors.textPrimary,
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            _kcal(l, _s.calories),
            key: ValueKey<String>('exercise-detail-calories-$id'),
            style: OnCareTypography.numeric(
              _style(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 운동 종류 태그 자리 — 가장 긴 `스트레칭` 태그가 들어가는 폭.
  static const double _typeTagWidth = 60;

  String _nameHint(AppLocalizations l) => switch (_type) {
    ExerciseType.cardio || ExerciseType.walking => l.exExerciseNameHintCardio,
    ExerciseType.strength => l.exExerciseNameHintStrength,
    ExerciseType.stretching ||
    ExerciseType.yoga => l.exExerciseNameHintFlexibility,
    ExerciseType.other => l.exExerciseNameHintOther,
  };
}

/// `항목 … 값 단위` 한 줄 — 식단 `영양 정보` 의 줄과 같은 모양이다(#2964).
///
/// 보기에서는 값이 글자, 수정에서는 같은 자리가 숫자 칸이 된다. [child] 를
/// 주면 값 자리에 그것(칩·이름 칸)을 그대로 둔다.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    this.value,
    this.unit,
    this.parts,
    this.child,
    this.editing = false,
    this.decimal = false,
    this.fieldKey,
    this.onChanged,
    this.stacked = false,
  });

  final String label;
  final TextEditingController? value;
  final String? unit;

  /// 값이 여러 칸인 줄(분·초). (칸, 단위, 키)
  final List<(TextEditingController, String, String)>? parts;
  final Widget? child;
  final bool editing;
  final bool decimal;
  final String? fieldKey;
  final VoidCallback? onChanged;

  /// 수정 중에는 값 칸을 라벨 아래 줄에 둔다 — 칸이 여럿이라 라벨 옆에 서지
  /// 못하는 줄(시·분·초).
  final bool stacked;

  /// 식단 수정 칸과 같은 폭이다.
  static const double _fieldWidth = 72;

  Widget _part(
    BuildContext context,
    TextEditingController c,
    String unit,
    String? key,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (editing)
          SizedBox(
            width: _fieldWidth,
            child: AppTextField(
              key: key == null ? null : ValueKey<String>(key),
              controller: c,
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
              onChanged: (_) => onChanged?.call(),
            ),
          )
        else
          Text(
            c.text,
            key: key == null ? null : ValueKey<String>(key),
            style: OnCareTypography.numeric(
              _style(
                context,
                OnCareTypography.titleSmall,
                OnCareColors.textPrimary,
              ),
            ),
          ),
        const SizedBox(width: OnCareSpacing.s4),
        Text(
          unit,
          style: _style(
            context,
            OnCareTypography.caption,
            OnCareColors.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<(TextEditingController, String, String)> all =
        parts ??
        <(TextEditingController, String, String)>[
          if (value != null) (value!, unit ?? '', fieldKey ?? ''),
        ];
    final Widget row = Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: _style(
              context,
              OnCareTypography.strong(OnCareTypography.bodySmall),
              OnCareColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: OnCareSpacing.s8),
        if (child != null)
          Flexible(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: child),
          )
        else
          for (int i = 0; i < all.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: OnCareSpacing.s8),
            _part(context, all[i].$1, all[i].$2, all[i].$3),
          ],
      ],
    );
    if (editing && stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            label,
            style: _style(
              context,
              OnCareTypography.strong(OnCareTypography.bodySmall),
              OnCareColors.textPrimary,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final (TextEditingController c, String u, String k) in all)
                _part(context, c, u, k),
            ],
          ),
        ],
      );
    }
    // 수정 모드는 이미 회색 상자 안이다 — 줄마다 타일 여백을 또 두면 식단 수정
    // 칸보다 줄 사이가 두 배로 벌어진다.
    if (editing) return row;
    return AppTile(tone: AppTileTone.none, child: row);
  }
}

/// 운동 칸 안의 소모 칼로리 — 운동 추가 시트의 `예상 소모 칼로리` 와 같은
/// 파란 상자다(#2964). 식단 음식 칸의 칼로리 줄 자리지만, 운동은 칼로리를 직접
/// 적지 않고 시간·세트·강도를 따라 바뀌는 값이라 입력 칸이 아니다.
class _CalorieBox extends StatelessWidget {
  const _CalorieBox({super.key, required this.calories});

  final int calories;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppTile(
      child: Row(
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
              style: _style(
                context,
                OnCareTypography.label,
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            l.unitKcalValue(calories),
            style: OnCareTypography.numeric(
              _style(
                context,
                OnCareTypography.titleSmall,
                context.oncare.brand.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `총 소모 칼로리` 한 줄. 수정 중에는 식단 `먹은 음식` 카드처럼 운동 카드
/// 맨 아래에, 보기에서는 따로 카드 하나로 선다.
class _TotalCaloriesRow extends StatelessWidget {
  const _TotalCaloriesRow({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(child: _CardTitle(l.exRecordDetailTotalCalories)),
        Text(
          _kcal(l, total),
          key: const Key('exercise-detail-calories'),
          style: _style(
            context,
            OnCareTypography.strong(OnCareTypography.titleSmall),
            context.oncare.brand.primary,
          ),
        ),
      ],
    );
  }
}
