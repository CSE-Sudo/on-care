import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_repeat_preview.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Bottom sheet for booking or editing a session: client, type, time
/// (15-minute steps), and duration.
class SessionSheet extends ConsumerStatefulWidget {
  const SessionSheet({
    required this.clientNames,
    required this.date,
    required this.existing,
    this.inline = false,
    this.onSaved,
    this.onCancel,
    super.key,
  });

  final List<String> clientNames;

  /// The browsed calendar day new sessions are booked on (`YYYY-MM-DD`).
  final String date;

  final ScheduleSession? existing;
  final bool inline;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<SessionSheet> {
  static const List<String> _types = SessionType.all;

  late String _client;
  late String _type;
  late DateTime _date;
  late int _hour;
  late int _minute;
  late int _endHour;
  late int _endMinute;
  bool _saving = false;
  late final TextEditingController _note;

  // ---- 반복(#870) — 새 일정에서만 쓴다. 수정은 그 회차 하나의 일이다. ----

  /// 반복 요일(ISO: 월=1 … 일=7). 비어 있으면 `반복 없음`이다.
  final Set<int> _repeatDays = <int>{};

  /// 반복 종료일. 요일을 고르면 하단 미리보기에서 총 회차가 그대로
  /// 계산되므로 횟수를 따로 받지 않는다 — 종료일 하나만이 종료 기준이다.
  DateTime? _repeatUntil;

  /// 저장 시도가 찾아낸 겹치는 회차. 비어 있지 않으면 아무것도 만들어지지 않았다.
  List<ScheduleSession> _conflicts = const <ScheduleSession>[];

  // Option lists always CONTAIN the edited session's own values. Falling
  // back to a default instead would silently rewrite the session on an
  // otherwise no-op save — e.g. a 상담 booked for a prospect who is not
  // on the roster would be reassigned to the first client, and a 50-minute
  // session would become 60 (review PR 218).
  late List<String> _clientOptions;
  late List<String> _typeOptions;

  /// 수정하는 회차의 고객이 트레이너의 등록 고객 목록에 없는가(상담 신청자
  /// 등). 그렇다면 드롭다운으로 **고를 수 있는 옵션**처럼 보이면 안 된다 —
  /// 예약 슬롯의 `typeLocked`와 같은 자리다: 값만 보여주고 잠근다(#1396).
  late bool _clientLocked;

  /// [base] plus [current] when it isn't already offered.
  static List<T> _withCurrent<T>(List<T> base, T? current) {
    if (current == null || base.contains(current)) return List<T>.of(base);
    return <T>[...base, current];
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _note = TextEditingController(text: e?.note ?? '');

    _client = e?.clientName.isNotEmpty ?? false
        ? e!.clientName
        : widget.clientNames.first;
    _clientOptions = _withCurrent(widget.clientNames, _client);
    _clientLocked = e != null && !widget.clientNames.contains(_client);

    _type = e != null && e.type.isNotEmpty ? e.type : _types.first;
    _typeOptions = _withCurrent(_types, _type);

    _date = DateTime.parse(e?.date ?? widget.date);

    final parts = e?.time.split(':');
    _hour = parts != null ? int.tryParse(parts[0]) ?? 10 : 10;
    _minute = parts != null && parts.length > 1
        ? int.tryParse(parts[1]) ?? 0
        : 0;

    // 종료 시간은 시작 시간 + 소요 시간에서 거꾸로 구한다 — 기존 세션은
    // 소요 시간(`durationMinutes`)만 들고 있어 화면에 보일 종료 시간이
    // 저장돼 있지 않다(#1090).
    final endTotal = _hour * 60 + _minute + (e?.durationMinutes ?? 60);
    _endHour = endTotal ~/ 60;
    _endMinute = endTotal % 60;
  }

  Future<void> _pickTimeRange() async {
    final picked = await showScheduleTimeRangePicker(
      context: context,
      start: TimeOfDay(hour: _hour, minute: _minute),
      end: TimeOfDay(hour: _endHour, minute: _endMinute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hour = picked.start.hour;
      _minute = picked.start.minute;
      _endHour = picked.end.hour;
      _endMinute = picked.end.minute;
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _time =>
      '${_hour.toString().padLeft(2, '0')}:'
      '${_minute.toString().padLeft(2, '0')}';

  String get _endTime =>
      '${_endHour.toString().padLeft(2, '0')}:'
      '${_endMinute.toString().padLeft(2, '0')}';

  int get _startTotalMinutes => _hour * 60 + _minute;
  int get _endTotalMinutes => _endHour * 60 + _endMinute;

  /// 지금 화면이 나타내는 반복 규칙.
  WeeklyRecurrence get _rule =>
      WeeklyRecurrence(weekdays: _repeatDays, until: _repeatUntil);

  /// 저장하면 만들어질 날짜들. 서버와 같은 규칙을 쓰므로(`seriesOccurrences`)
  /// 화면이 보여 준 회차 수와 실제로 만들어지는 수가 어긋나지 않는다.
  List<DateTime> get _occurrences => seriesOccurrences(_date, _rule);

  /// 반복 등록 시도 하나의 멱등키. 재시도에 같은 값을 다시 보내야 회차가 두 벌
  /// 생기지 않는다 — 시트를 여는 동안 고정한다.
  late final String _requestId = newClientRequestId();

  Future<void> _save() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final int duration = _endTotalMinutes - _startTotalMinutes;
    if (duration <= 0) {
      showAppToast(context, l.schedEndBeforeStart);
      return;
    }
    if (_repeatDays.isNotEmpty && _repeatUntil == null) {
      showAppToast(context, l.schedRepeatNeedsEndDate);
      return;
    }
    final e = widget.existing;
    final String newDate = ymd(_date);
    final bool reopening =
        e != null && e.status == ScheduleStatus.done && newDate != e.date;
    if (reopening) {
      // 완료 세션은 미래로만 되돌린다 — 오늘·과거는 "완료 취소"이지 반복
      // 시작 회차를 다시 잡는 일이 아니다(#1396).
      if (newDate.compareTo(ymd(todayKst())) <= 0) {
        showAppToast(context, l.schedReopenPastBlocked);
        return;
      }
      final confirmed = await _confirmReopen(l);
      if (!confirmed || !mounted) return;
    }
    setState(() => _saving = true);
    final repo = ref.read(scheduleRepositoryProvider);
    final navigator = Navigator.of(context);
    try {
      if (e == null && _repeatDays.isNotEmpty) {
        final start = _date;
        final rule = _rule;
        // 만들기 전에 충돌을 먼저 본다. 서버도 같은 검사로 409 를 주지만, 화면이
        // 겹친 회차를 짚어 주려면 목록이 필요하다(#870).
        final preview = await repo.previewRecurring(
          start: start,
          time: _time,
          rule: rule,
        );
        if (preview.conflicts.isNotEmpty) {
          if (mounted) {
            setState(() {
              _saving = false;
              _conflicts = preview.conflicts;
            });
          }
          return;
        }
        await repo.addRecurringSessions(
          start: start,
          time: _time,
          rule: rule,
          clientName: _client,
          type: _type,
          durationMinutes: duration,
          note: _note.text.trim(),
          clientRequestId: _requestId,
        );
      } else if (e == null) {
        await repo.addSession(
          date: ymd(_date),
          clientName: _client,
          time: _time,
          type: _type,
          durationMinutes: duration,
          note: _note.text.trim(),
        );
      } else if (_repeatDays.isNotEmpty) {
        // 수정 + 반복: 이 회차를 시리즈의 시작으로 삼는다. 이 회차 자체는
        // 새로 만들지 않고 그대로 고친 뒤, 그다음 회차부터 반복으로
        // 만든다(#1396).
        await _saveEditAsRepeatStart(repo, e, duration, newDate, reopening);
      } else {
        if (reopening) await repo.reopenSession(e.id, date: newDate);
        await repo.updateSession(
          e.id,
          date: newDate == e.date ? null : newDate,
          clientName: _client,
          time: _time,
          type: _type,
          durationMinutes: duration,
          note: _note.text.trim(),
        );
      }
    } on ScheduleSeriesConflictError catch (error) {
      // 서버가 막은 경우(미리보기 뒤에 다른 일정이 생겼을 때)도 같은 자리에
      // 같은 목록을 보여 준다.
      if (mounted) {
        setState(() {
          _saving = false;
          _conflicts = error.conflicts;
        });
      }
      return;
    } catch (_) {
      // Surface the failure and keep the sheet open so the input isn't
      // lost (review PR 218).
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.schedSaveFailed, type: AppToastType.error);
      return;
    }
    if (mounted) setState(() => _saving = false);
    if (!mounted) return;
    if (widget.inline) {
      widget.onSaved?.call();
    } else {
      navigator.pop();
    }
  }

  /// [e] 를 반복의 시작 회차로 고치고, 그다음 날부터 나머지 회차를 만든다.
  /// 과거·오늘 날짜로 만들어진 회차는 이어서 완료 처리한다 — "반복하면
  /// 지난 회차는 완료로, 앞으로는 예정으로" 규칙이다(#1396).
  Future<void> _saveEditAsRepeatStart(
    ScheduleRepository repo,
    ScheduleSession e,
    int duration,
    String newDate,
    bool reopening,
  ) async {
    if (reopening) await repo.reopenSession(e.id, date: newDate);
    await repo.updateSession(
      e.id,
      date: newDate == e.date ? null : newDate,
      clientName: _client,
      time: _time,
      type: _type,
      durationMinutes: duration,
      note: _note.text.trim(),
    );

    // 이 회차가 이미 시리즈의 첫 회차다 — 나머지는 그다음 날부터, 같은
    // 종료일까지 만든다.
    final until = _repeatUntil;
    if (until == null) return;
    final nextStart = _date.add(const Duration(days: 1));
    if (nextStart.isAfter(until)) return;
    final rule = WeeklyRecurrence(weekdays: _repeatDays, until: until);
    final preview = await repo.previewRecurring(
      start: nextStart,
      time: _time,
      rule: rule,
    );
    if (preview.conflicts.isNotEmpty) {
      throw ScheduleSeriesConflictError(preview.conflicts);
    }
    final created = await repo.addRecurringSessions(
      start: nextStart,
      time: _time,
      rule: rule,
      clientName: _client,
      type: _type,
      durationMinutes: duration,
      note: '',
      clientRequestId: _requestId,
    );
    final today = ymd(todayKst());
    for (final session in created) {
      if (session.date.compareTo(today) <= 0) {
        await repo.completeSession(session.id);
      }
    }
  }

  /// 완료 세션을 미래로 옮기기 전 확인. 되돌리면 완료가 남긴 운동 기록이
  /// 사라진다는 것을 미리 말해 준다(#1396).
  Future<bool> _confirmReopen(AppLocalizations l) {
    return showAppConfirmDialog(
      context: context,
      title: l.schedReopenTitle,
      message: l.schedReopenBody,
      confirmLabel: l.schedReopenConfirm,
      cancelLabel: l.actionCancel,
    );
  }

  /// 날짜를 고른다 — 새 일정은 시트를 연 시점의 선택된 날짜가 기본값이고,
  /// 수정은 그 회차의 날짜가 기본값이다. 지난 기록을 남기려는 경우도 있어
  /// (#870 반복과 달리) 과거 날짜도 막지 않는다 — 완료 세션을 미래로 옮기는
  /// 특별한 경우는 `_save` 가 별도로 확인을 받는다(#1396).
  ///
  /// 반복(`매주`)이 켜져 있으면 이 필드가 시작·종료 날짜를 함께 고르는
  /// 범위 선택으로 바뀐다 — 시작일 따로, 종료일 따로 각자의 필드를 두지
  /// 않는다.
  Future<void> _pickDate() async {
    final today = todayKst();
    final first = _date.isBefore(today) ? _date : today;
    if (_repeatDays.isNotEmpty) {
      final range = await showAppDateRangePicker(
        context: context,
        initialRange: DateTimeRange(
          start: _date,
          end: _repeatUntil ?? _date.add(const Duration(days: 56)),
        ),
        firstDate: first.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 7 * maxSeriesOccurrences)),
      );
      if (range == null || !mounted) return;
      setState(() {
        _date = DateTime(range.start.year, range.start.month, range.start.day);
        _repeatUntil = DateTime(range.end.year, range.end.month, range.end.day);
        if (_repeatDays.length == 1) {
          _repeatDays
            ..clear()
            ..add(_date.weekday);
        }
      });
      return;
    }
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
    });
  }

  /// 일정 입력 내용. `showAppDialog` + `AppDialog(size: medium)` 본문에
  /// 들어간다 — 제목(`schedAddTitle`/`schedEditTitle`)·닫기(X)·스크롤은
  /// 다이얼로그 틀이 맡고, 이 위젯은 틀 없이 내용만 세로로 쌓는다.
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 고객·유형은 같은 층위의 선택이라 한 줄에 묶는다 — 세로로
        // 나란한 두 드롭다운이 각자 한 줄을 다 쓸 이유가 없다(#1090).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              // 등록된 고객이 아니면(상담 신청자 등) 고를 수 없게 값만
              // 보여준다 — 드롭다운은 실제로 옮길 수 있는 고객 목록만
              // 옵션으로 내놓는다(#1396).
              child: AppSelectField<String>(
                label: l.schedFieldClient,
                value: _client,
                items: <DropdownMenuItem<String>>[
                  for (final name
                      in _clientLocked ? <String>[_client] : _clientOptions)
                    DropdownMenuItem<String>(value: name, child: Text(name)),
                ],
                onChanged: _clientLocked
                    ? null
                    : (v) => setState(() => _client = v ?? _client),
              ),
            ),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(
              child: AppSelectField<String>(
                label: l.schedFieldType,
                value: _type,
                items: <DropdownMenuItem<String>>[
                  for (final t in _typeOptions)
                    // 값은 계약값 그대로, 보이는 문구만 로케일에서 가져온다.
                    DropdownMenuItem<String>(
                      value: t,
                      child: Text(sessionTypeLabel(l, t)),
                    ),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        // 소요 시간 대신 시작·종료 시간을 직접 고른다 — 시간표에 뜨는 것도,
        // 예약 슬롯이 세션을 만들 때 넘기는 것도 결국 "언제부터 언제까지"라
        // 그 형태로 바로 고르는 편이 낫다(#1090). 날짜도 수정에서 고칠 수
        // 있다(#1396).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _dateField(l)),
            const SizedBox(width: OnCareSpacing.s8),
            Expanded(child: _timeField(l)),
          ],
        ),
        const SizedBox(height: OnCareSpacing.s12),
        // 반복은 수정에서도 켤 수 있다(#1396) — 이 회차를 반복의 시작
        // 회차로 삼고, 나머지는 새로 만든다(`_save` 참고).
        _fieldLabel(l.schedRepeat),
        const SizedBox(height: OnCareSpacing.s8),
        // `반복 없음` 이 기본값이다 — `매주` 하나를 껐다 켰다 하는 토글로
        // 둔다. 켜면 옆에 요일 칩이 붙는다.
        Wrap(
          spacing: OnCareSpacing.s4,
          runSpacing: OnCareSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            AppChoiceChip(
              key: const ValueKey<String>('repeat-weekly'),
              label: l.schedRepeatWeekly,
              selected: _repeatDays.isNotEmpty,
              onSelected: (_) => setState(() {
                if (_repeatDays.isNotEmpty) {
                  _repeatDays.clear();
                  _repeatUntil = null;
                } else {
                  // 켜는 순간의 기본값은 **시작일의 요일**이다. 빈 상태로
                  // 켜면 "매주" 를 골랐는데 아무 회차도 없는 화면이 된다.
                  _repeatDays.add(_date.weekday);
                  // 종료일도 바로 채워 미리보기가 곧장 뜨게 한다 — 위 날짜
                  // 필드를 눌러 언제든 다시 고를 수 있다.
                  _repeatUntil ??= _date.add(const Duration(days: 56));
                }
              }),
            ),
            if (_repeatDays.isNotEmpty)
              for (var day = 1; day <= 7; day++)
                AppChoiceChip(
                  key: ValueKey<String>('repeat-day-$day'),
                  label: weekdayNames(l)[day - 1],
                  selected: _repeatDays.contains(day),
                  onSelected: (_) => setState(() {
                    if (_repeatDays.contains(day)) {
                      if (_repeatDays.length > 1) {
                        // 마지막 요일까지 끄면 `매주` 인데 회차가 없는
                        // 상태가 된다 — 끄려면 `매주` 를 다시 눌러 반복
                        // 자체를 끈다.
                        _repeatDays.remove(day);
                      }
                    } else {
                      _repeatDays.add(day);
                    }
                  }),
                ),
          ],
        ),
        if (_repeatDays.isNotEmpty) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          // 종료일은 위 날짜 필드에서 시작일과 함께 범위로 고른다 — 요일을
          // 고르면 회차 수는 아래 미리보기가 그대로 계산해 준다.
          SessionRepeatPreview(dates: _occurrences),
          if (_conflicts.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s8),
            SessionRepeatConflicts(
              total: _occurrences.length,
              conflicts: _conflicts,
            ),
          ],
        ],
        if (widget.existing == null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('schedule-trainer-note'),
            controller: _note,
            label: l.schedNote,
            hint: l.schedNoteHint,
            minLines: 2,
            maxLines: 4,
          ),
        ],
        const SizedBox(height: OnCareSpacing.s24),
        AppButtonPair(
          cancelLabel: l.actionCancel,
          onCancel: _saving
              ? null
              : widget.onCancel ?? () => Navigator.of(context).maybePop(),
          confirmLabel: widget.existing == null
              ? l.schedAddAction
              : l.schedSaveAction,
          onConfirm: _saving ? null : _save,
          confirmLoading: _saving,
        ),
      ],
    );
  }

  /// 필드 위 라벨 — `AppTextField`/`AppSelectField` 의 라벨과 같은 모양이다.
  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: context.oncare
          .text(OnCareTypography.label)
          .copyWith(color: OnCareColors.textSecondary),
    );
  }

  /// 눌러서 선택창을 여는 필드 — 입력창과 같은 틀(위 라벨, 채움 + 테두리
  /// 상자)이지만 글자 입력은 받지 않는다.
  Widget _pickerField({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final OnCareTokens tokens = context.oncare;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _fieldLabel(label),
          const SizedBox(height: OnCareSpacing.s8),
          InputDecorator(
            decoration: InputDecoration(
              suffixIcon: Icon(icon, size: OnCareSize.iconSmall),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OnCareTypography.numeric(
                tokens.text(OnCareTypography.body),
              ).copyWith(color: OnCareColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// 시작·종료 시간 필드 — 눌러서 한 번에 고르는 모달을 연다(#1229, #1250).
  Widget _timeField(AppLocalizations l) {
    return _pickerField(
      key: const ValueKey<String>('session-time-range-field'),
      label: l.schedFieldTime,
      value: l.schedTimeRange(_time, _endTime),
      icon: Icons.schedule_rounded,
      onTap: _pickTimeRange,
    );
  }

  /// 날짜 필드 — 눌러서 다른 날짜로 바꿀 수 있다. 반복을 켜면 이 값이 반복
  /// 시리즈의 시작일도 겸하고, 같은 필드에서 종료일까지 범위로 함께
  /// 고른다 — 시작·종료를 각자 다른 필드에 두지 않는다(#1396).
  Widget _dateField(AppLocalizations l) {
    final bool repeating = _repeatDays.isNotEmpty;
    return _pickerField(
      key: const ValueKey<String>('session-date-field'),
      label: repeating ? l.schedFieldDateRange : l.schedFieldDate,
      // 프로그램 등록 날짜 칩(`program-register-date`)과 같이 연도까지
      // 보이는 `ymd` 표기로 맞춘다 — 월·일만 있으면 해가 바뀌는 반복에서
      // 헷갈린다.
      value: repeating
          ? l.schedTimeRange(
              ymd(_date),
              _repeatUntil == null ? '-' : ymd(_repeatUntil!),
            )
          : ymd(_date),
      icon: Icons.calendar_today_rounded,
      onTap: _pickDate,
    );
  }
}
