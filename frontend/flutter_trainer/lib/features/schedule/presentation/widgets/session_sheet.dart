import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_core/request_id.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/errors/app_error_message.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_overlap_banner.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_repeat_preview.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/time_range_picker_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Bottom sheet for booking or editing a session: client, type, time
/// (15-minute steps), and duration.
class SessionSheet extends ConsumerStatefulWidget {
  const SessionSheet({
    required this.title,
    required this.clients,
    required this.date,
    required this.existing,
    this.inline = false,
    this.onSaved,
    this.onCancel,
    super.key,
  });

  /// 창 제목(`schedAddTitle`/`schedEditTitle`).
  final String title;

  /// 고를 수 있는 등록 회원. 이름만으로는 동명이인을 가를 수 없어 id 를 함께
  /// 받고, 저장할 때 그 id 를 `member_id` 로 보낸다(#2586).
  final List<ScheduleClientKey> clients;

  /// The browsed calendar day new sessions are booked on (`YYYY-MM-DD`).
  final String date;

  final ScheduleSession? existing;
  final bool inline;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<SessionSheet> createState() => _SessionSheetState();
}

/// 수정하는 회차의 **서버에 반영된** 값 — 바뀐 칸을 가를 기준이다(#3102).
///
/// 저장은 여러 요청(되돌리기 → 고치기 → 반복 만들기 → 완료)으로 나뉜다. 앞
/// 요청만 반영된 뒤 실패한 창에서 다시 저장할 때, 창을 열 때 받은 값과 비교하면
/// 이미 끝난 되돌리기를 또 보내 서버가 거절한다. 요청이 성공할 때마다 이 값을
/// 그 결과로 옮겨 재시도가 남은 단계만 보내게 한다.
typedef _SavedFields = ({
  bool done,
  String date,
  String time,
  int durationMinutes,
  String clientName,
  String? clientId,
  String type,
  String note,
});

class _SessionSheetState extends ConsumerState<SessionSheet> {
  static const List<String> _types = SessionType.all;

  late String _client;

  /// 고객 드롭다운의 값 — 등록 회원은 그 회원 id, 아직 회원 id 가 없는 지금
  /// 이름(이름만 가진 옛 회차·가망 고객)은 [_unlinked] 다(#2586).
  late String _clientValue;

  /// 회원 id 는 비어 있지 않으므로 빈 문자열이 '연결 안 됨' 자리와 섞이지 않는다.
  static const String _unlinked = '';
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

  /// 한 건 저장이 다른 일정과 시간이 겹쳐 막혔다(#2284). null 이면 막히지
  /// 않았다 — 겹친 목록이 비어 있어도 막힌 것은 막힌 것이라 null 로 구분한다.
  List<ScheduleSession>? _overlaps;

  // Option lists always CONTAIN the edited session's own values. Falling
  // back to a default instead would silently rewrite the session on an
  // otherwise no-op save — e.g. a 상담 booked for a prospect who is not
  // on the roster would be reassigned to the first client, and a 50-minute
  // session would become 60 (review PR 218).
  late List<ScheduleClientKey> _clientOptions;
  late List<String> _typeOptions;

  /// 수정하는 회차의 고객이 트레이너의 등록 고객 목록에 없는가(상담 신청자
  /// 등). 그렇다면 드롭다운으로 **고를 수 있는 옵션**처럼 보이면 안 된다 —
  /// 예약 슬롯의 `typeLocked`와 같은 자리다: 값만 보여주고 잠근다(#1396).
  late bool _clientLocked;

  /// 취소·노쇼로 끝난 세션인가 — 일정 칸을 모두 읽기 전용으로 그린다(#2889).
  ///
  /// 서버는 마무리된 세션의 메모·프로그램 밖의 변경을 409 로 거절한다. 메뉴가
  /// 이미 `일정 수정` 을 잠그지만, 다른 진입로가 생겨도 같은 규칙이 되도록 창도
  /// 스스로 잠근다.
  bool get _endedLocked {
    final e = widget.existing;
    return e != null && (e.isCancelled || e.isNoShow);
  }

  /// 완료 세션인데 날짜를 앞으로 옮기지 않았는가(#2889).
  ///
  /// 완료 세션의 일정은 날짜를 미래로 옮겨 예정으로 되돌릴 때만 바꿀 수 있다
  /// (#1396). 그 전에는 날짜 칸만 열고, 회원·종류·시각·반복은 잠근다 —
  /// 그대로 저장하면 서버가 409 로 거절한다.
  bool get _doneLocked {
    final e = widget.existing;
    if (e == null || !e.isDone) return false;
    final String picked = ymd(_date);
    return picked == e.date || picked.compareTo(ymd(todayKst())) <= 0;
  }

  /// 일정 칸(회원·종류·시각·반복)이 잠겼는가.
  bool get _scheduleLocked => _endedLocked || _doneLocked;

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
    if (e != null) {
      _saved = (
        done: e.status == ScheduleStatus.done,
        date: e.date,
        time: e.time,
        durationMinutes: e.durationMinutes,
        clientName: e.clientName,
        clientId: e.clientId,
        type: e.type,
        note: e.note,
      );
    }

    final roster = widget.clients;
    if (e != null && e.clientName.isNotEmpty) {
      _client = e.clientName;
      final linked = roster.any((c) => c.id == e.clientId);
      _clientValue = linked ? e.clientId! : _unlinked;
      _clientOptions = linked
          ? List<ScheduleClientKey>.of(roster)
          : <ScheduleClientKey>[(id: _unlinked, name: _client), ...roster];
    } else {
      _client = roster.first.name;
      _clientValue = roster.first.id;
      _clientOptions = List<ScheduleClientKey>.of(roster);
    }
    _clientLocked =
        e != null &&
        _clientValue == _unlinked &&
        !roster.any((c) => c.name == _client);

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

  /// 고른 회원의 id. 이름만 가진 지금 값 그대로면 null 이다.
  String? get _pickedClientId =>
      _clientValue == _unlinked ? null : _clientValue;

  /// 수정에서 보낼 회원 id — 고른 회원이 바뀌었을 때만 보낸다. 그대로면 서버의
  /// 값을 건드리지 않는다: 담당이 해제된 회원의 옛 회차를 고치다 404 를 받거나,
  /// 이름만 가진 회차의 비어 있는 id 를 지우는 일이 없게(#2586).
  String? _changedClientId(_SavedFields e) {
    final id = _pickedClientId;
    return id == e.clientId ? null : id;
  }

  void _pickClient(String? value) {
    if (value == null) return;
    final picked = _clientOptions.firstWhere((c) => c.id == value);
    setState(() {
      _clientValue = picked.id;
      _client = picked.name;
    });
  }

  /// 지금 화면이 나타내는 반복 규칙.
  WeeklyRecurrence get _rule =>
      WeeklyRecurrence(weekdays: _repeatDays, until: _repeatUntil);

  /// 저장하면 만들어질 날짜들. 서버와 같은 규칙을 쓰므로(`seriesOccurrences`)
  /// 화면이 보여 준 회차 수와 실제로 만들어지는 수가 어긋나지 않는다.
  List<DateTime> get _occurrences => seriesOccurrences(_date, _rule);

  /// 지난 반복 등록 시도의 (입력 지문, 멱등키).
  ({String fingerprint, String id})? _seriesRequest;

  /// 반복 등록 시도 하나의 멱등키. 재시도에 같은 값을 다시 보내야 회차가 두 벌
  /// 생기지 않는다 — 입력이 지난 시도와 같으면 그 키를 다시 쓴다.
  ///
  /// 입력(시작일·시각·요일·종료일·회원·종류·메모)을 바꿨으면 다른 요청이므로
  /// 새 키를 만든다. 창 하나에 키를 고정하면, 응답만 잃은 뒤 시간을 바꿔 다시
  /// 저장한 요청을 서버가 같은 시도로 보고 옛 시간의 회차를 돌려준다 —
  /// 트레이너가 고른 새 시간이 조용히 버려진다(#3102). 코칭 화면의
  /// `_requestIdFor` 와 같은 방식이다.
  String _seriesRequestIdFor({
    required DateTime start,
    required WeeklyRecurrence rule,
    required int durationMinutes,
    required String note,
  }) {
    final until = rule.until;
    final fingerprint = jsonEncode(<Object?>[
      ymd(start),
      _time,
      rule.weekdays.toList()..sort(),
      until == null ? null : ymd(until),
      durationMinutes,
      _client,
      _pickedClientId,
      _type,
      note,
    ]);
    final pending = _seriesRequest;
    if (pending != null && pending.fingerprint == fingerprint) {
      return pending.id;
    }
    final id = newClientRequestId();
    _seriesRequest = (fingerprint: fingerprint, id: id);
    return id;
  }

  /// 수정하는 회차의 서버에 반영된 값. 새 일정이면 null.
  _SavedFields? _saved;

  /// 수정 + 반복에서 이미 만든 회차(그 시도의 멱등키와 함께). 재시도는 미리보기·
  /// 만들기를 건너뛰고 남은 완료 처리만 이어 간다(#3102).
  ({String requestId, List<ScheduleSession> sessions})? _createdSeries;

  /// 수정 + 반복에서 완료 처리까지 끝낸 회차 id.
  final Set<String> _completedIds = <String>{};

  /// 반복 미리보기 뒤 만들기. 같은 키로 이미 만들어졌으면(응답만 잃은 재시도)
  /// 미리보기 충돌을 보지 않고 같은 키로 다시 불러 그 회차를 돌려받는다 — 미리
  /// 보기가 방금 만든 자기 회차와 겹친다고 막으면 재시도가 영원히 통과하지
  /// 못한다(#3102). 그 밖의 충돌은 [ScheduleSeriesConflictError] 로 올린다.
  Future<List<ScheduleSession>> _previewThenCreate(
    ScheduleRepository repo, {
    required DateTime start,
    required WeeklyRecurrence rule,
    required int durationMinutes,
    required String note,
    required String requestId,
  }) async {
    // 만들기 전에 충돌을 먼저 본다. 서버도 같은 검사로 409 를 주지만, 화면이
    // 겹친 회차를 짚어 주려면 목록이 필요하다(#870).
    final preview = await repo.previewRecurring(
      start: start,
      time: _time,
      rule: rule,
      durationMinutes: durationMinutes,
      clientRequestId: requestId,
    );
    if (!preview.alreadyCreated && preview.conflicts.isNotEmpty) {
      throw ScheduleSeriesConflictError(preview.conflicts);
    }
    return repo.addRecurringSessions(
      start: start,
      time: _time,
      rule: rule,
      clientName: _client,
      clientId: _pickedClientId,
      type: _type,
      durationMinutes: durationMinutes,
      note: note,
      clientRequestId: requestId,
    );
  }

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
    // 창을 열 때 받은 값이 아니라 서버에 반영된 값과 비교한다 — 되돌리기만
    // 성공하고 다음 단계가 실패한 재시도가 되돌리기를 또 보내지 않게(#3102).
    final saved = _saved;
    final bool reopening = saved != null && saved.done && newDate != saved.date;
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
    setState(() {
      _saving = true;
      _overlaps = null;
    });
    final repo = ref.read(scheduleRepositoryProvider);
    final navigator = Navigator.of(context);
    try {
      if (e == null && _repeatDays.isNotEmpty) {
        final start = _date;
        final rule = _rule;
        final note = _note.text.trim();
        await _previewThenCreate(
          repo,
          start: start,
          rule: rule,
          durationMinutes: duration,
          note: note,
          requestId: _seriesRequestIdFor(
            start: start,
            rule: rule,
            durationMinutes: duration,
            note: note,
          ),
        );
      } else if (e == null) {
        await repo.addSession(
          date: ymd(_date),
          clientName: _client,
          clientId: _pickedClientId,
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
        await _applyEdit(repo, e, duration, newDate, reopening);
      }
    } on ScheduleSeriesConflictError catch (error) {
      // 미리보기가 찾은 충돌과, 서버가 막은 경우(미리보기 뒤에 다른 일정이
      // 생겼을 때) 모두 같은 자리에 같은 목록을 보여 준다.
      if (mounted) {
        setState(() {
          _saving = false;
          _conflicts = error.conflicts;
        });
      }
      return;
    } on ScheduleOverlapError catch (error) {
      // 시간이 겹쳐 아무것도 저장되지 않았다(#2284). 토스트는 금방 사라져
      // 무엇과 겹쳤는지 다시 볼 수 없다 — 버튼 바로 위에 남겨 두고, 입력은
      // 그대로 둔 채 시간만 바꿔 다시 저장하게 한다.
      if (mounted) {
        setState(() {
          _saving = false;
          _overlaps = error.conflicts;
        });
      }
      return;
    } catch (error) {
      // Surface the failure and keep the sheet open so the input isn't
      // lost (review PR 218). 서버가 사유를 주면(마무리된 세션·회원 예약
      // 일정의 409 등) 그 사유를 보인다 — 일반 문구만으로는 왜 안 되는지,
      // 무엇을 하면 되는지 알 수 없다(#2754·#2756).
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(
        context,
        appErrorMessage(l, error, fallback: l.schedSaveFailed),
        type: AppToastType.error,
      );
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
    await _applyEdit(repo, e, duration, newDate, reopening);

    // 이 회차가 이미 시리즈의 첫 회차다 — 나머지는 그다음 날부터, 같은
    // 종료일까지 만든다.
    final until = _repeatUntil;
    if (until == null) return;
    // 달력의 다음 날이다 — 24시간을 더하면 서머타임이 끝나는 날 같은 날
    // 23:00 이 되어 첫 회차와 겹친다는 충돌로 저장이 막혔다(#2890).
    final nextStart = addCalendarDays(_date, 1);
    if (nextStart.isAfter(until)) return;
    final rule = WeeklyRecurrence(weekdays: _repeatDays, until: until);
    final requestId = _seriesRequestIdFor(
      start: nextStart,
      rule: rule,
      durationMinutes: duration,
      note: '',
    );
    // 같은 시도로 이미 만들었으면 다시 만들지 않고 남은 완료만 이어 간다 —
    // 완료 처리 중간에 실패한 재시도가 자기 회차와 겹친다고 멈추지 않게(#3102).
    final made = _createdSeries;
    final List<ScheduleSession> created;
    if (made != null && made.requestId == requestId) {
      created = made.sessions;
    } else {
      created = await _previewThenCreate(
        repo,
        start: nextStart,
        rule: rule,
        durationMinutes: duration,
        note: '',
        requestId: requestId,
      );
      _createdSeries = (requestId: requestId, sessions: created);
    }
    // 이미 시작한 회차만 완료한다 — 오늘이라도 시작 전이면 서버가 완료를
    // 거절한다(#2760). 그 회차는 예정으로 남는다. 앞선 시도에서 완료한 회차는
    // 건너뛴다 — 다시 보내면 서버가 이미 완료라고 거절한다.
    final DateTime now = nowKst();
    for (final session in created) {
      if (_completedIds.contains(session.id) ||
          session.status == ScheduleStatus.done) {
        continue;
      }
      if (sessionHasStarted(session, now)) {
        await repo.completeSession(session.id);
        _completedIds.add(session.id);
      }
    }
  }

  /// 기존 회차 [e] 에 시트의 입력을 반영한다 — **바뀐 칸만** 보낸다(#2754).
  ///
  /// 서버는 마무리된 세션·회원 예약 일정에서 메모·프로그램 말고 다른 칸이
  /// 오기만 해도 거절한다. 메모만 고친 저장에 시간·종류까지 실으면 그 거절에
  /// 걸리므로, 값이 그대로인 칸은 null('그대로')로 둔다.
  ///
  /// 완료 회차를 미래로 옮길 때는([reopening]) 날짜·시각·길이를 되돌리기
  /// 요청 하나에 함께 싣는다(#2757). 서버가 그 자리의 겹침을 기록을 지우기
  /// 전에 보므로, 겹치면 완료 기록이 그대로 남는다. 나머지 칸(회원·종류·
  /// 메모)은 되돌린 뒤 이어서 고친다 — 그때는 예정 세션이라 거절되지 않는다.
  ///
  /// 바뀐 칸은 창을 열 때 받은 값이 아니라 [_saved](서버에 반영된 값)와
  /// 비교하고, 요청이 성공할 때마다 [_saved] 를 옮긴다 — 되돌리기만 반영된 뒤
  /// 실패한 재시도가 되돌리기를 다시 보내지 않고 남은 칸만 고친다(#3102).
  Future<void> _applyEdit(
    ScheduleRepository repo,
    ScheduleSession session,
    int duration,
    String newDate,
    bool reopening,
  ) async {
    var e = _saved!;
    if (reopening) {
      await repo.reopenSession(
        session.id,
        date: newDate,
        time: _time == e.time ? null : _time,
        durationMinutes: duration == e.durationMinutes ? null : duration,
      );
      e = (
        done: false,
        date: newDate,
        time: _time,
        durationMinutes: duration,
        clientName: e.clientName,
        clientId: e.clientId,
        type: e.type,
        note: e.note,
      );
      _saved = e;
    }
    final String note = _note.text.trim();
    final String? clientName = _client == e.clientName ? null : _client;
    final String? clientId = _changedClientId(e);
    final String? type = _type == e.type ? null : _type;
    final String? changedNote = note == e.note ? null : note;
    // 되돌리기가 날짜·시각·길이를 이미 옮겼으면 [e] 가 그 값이라 여기서는
    // 비어 나간다.
    final String? date = newDate == e.date ? null : newDate;
    final String? changedTime = _time == e.time ? null : _time;
    final int? changedDuration = duration == e.durationMinutes
        ? null
        : duration;
    if (date == null &&
        clientName == null &&
        clientId == null &&
        changedTime == null &&
        type == null &&
        changedDuration == null &&
        changedNote == null) {
      return;
    }
    await repo.updateSession(
      session.id,
      date: date,
      clientName: clientName,
      clientId: clientId,
      time: changedTime,
      type: type,
      durationMinutes: changedDuration,
      note: changedNote,
    );
    _saved = (
      done: e.done,
      date: newDate,
      time: _time,
      durationMinutes: duration,
      clientName: _client,
      clientId: clientId ?? e.clientId,
      type: _type,
      note: note,
    );
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
          end: _repeatUntil ?? addCalendarDays(_date, 56),
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

  /// 일정 입력 창. `showAppDialog` 로 띄우는 `AppDialog(size: medium)` 을
  /// 이 위젯이 직접 짓는다 — `추가`·`저장` 은 저장 중 상태를 이 위젯이 쥐고
  /// 있어, 버튼을 창 아래(footer)에 고정하려면 틀까지 여기서 그려야 한다.
  /// 본문 끝에 두면 긴 폼에서 버튼이 스크롤 끝으로 밀려 보이지 않았다(#2465).
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppDialog(
      title: widget.title,
      size: AppDialogSize.medium,
      footer: AppButtonPair(
        cancelLabel: l.actionCancel,
        onCancel: _saving
            ? null
            : widget.onCancel ?? () => Navigator.of(context).maybePop(),
        confirmLabel: widget.existing == null
            ? l.schedAddAction
            : l.schedSaveAction,
        // 취소·노쇼 세션은 이 창에서 바꿀 수 있는 칸이 없다(#2889).
        onConfirm: _saving || _endedLocked ? null : _save,
        confirmLoading: _saving,
      ),
      child: _fields(l),
    );
  }

  Widget _fields(AppLocalizations l) {
    final bool locked = _scheduleLocked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 끝난 세션은 왜 칸이 잠겼는지 먼저 말한다(#2889).
        if (locked) ...<Widget>[
          Text(
            _endedLocked ? l.schedEndedLockedHint : l.schedDoneLockedHint,
            key: const ValueKey<String>('session-sheet-locked-hint'),
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        // 고객·유형은 같은 층위의 선택이라 한 줄에 묶는다 — 세로로
        // 나란한 두 드롭다운이 각자 한 줄을 다 쓸 이유가 없다(#1090).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              // 등록된 고객이 아니면(상담 신청자 등) 고를 수 없게 값만
              // 보여준다 — 드롭다운은 실제로 옮길 수 있는 고객 목록만
              // 옵션으로 내놓는다(#1396).
              // 값은 회원 id 라 동명이인도 서로 다른 자리다(#2586).
              child: AppSelectField<String>(
                label: l.schedFieldClient,
                value: _clientValue,
                items: <DropdownMenuItem<String>>[
                  for (final c in _clientOptions)
                    if (!_clientLocked || c.id == _clientValue)
                      DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                ],
                onChanged: _clientLocked || locked ? null : _pickClient,
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
                onChanged: locked
                    ? null
                    : (v) => setState(() => _type = v ?? _type),
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
        // 회차로 삼고, 나머지는 새로 만든다(`_save` 참고). 끝난 세션은
        // 반복의 시작 회차가 될 수 없어 세우지 않는다(#2889).
        if (!locked) ..._repeatFields(l),
        if (widget.existing == null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          // PT 에 적는 글은 PT 를 마친 뒤 회원 앱에 가는 트레이너 피드백이고,
          // 상담에 적는 글은 트레이너만 보는 상담 메모다(#2515, #2574).
          if (_type == SessionType.consultation)
            AppTextField(
              key: const ValueKey<String>('schedule-trainer-note'),
              controller: _note,
              label: l.schedConsultNote,
              hint: l.schedConsultNoteHint,
              helper: l.schedConsultNotePrivate,
              minLines: 2,
              maxLines: 4,
              maxLength: AppTextLimits.entry,
              showCounter: true,
            )
          else
            AppTextField(
              key: const ValueKey<String>('schedule-trainer-note'),
              controller: _note,
              label: l.schedNote,
              hint: l.schedNoteHint,
              helper: l.schedNoteVisibleToMember,
              minLines: 2,
              maxLines: 4,
              maxLength: AppTextLimits.entry,
              showCounter: true,
            ),
        ],
        if (_overlaps != null) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s12),
          ScheduleOverlapBanner(conflicts: _overlaps!),
        ],
      ],
    );
  }

  /// 반복 칸 — 라벨·`매주` 토글·요일·미리보기. 끝난 세션에는 세우지 않는다(#2889).
  List<Widget> _repeatFields(AppLocalizations l) => <Widget>[
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
              _repeatUntil ??= addCalendarDays(_date, 56);
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
  ];

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
    bool enabled = true,
  }) {
    final OnCareTokens tokens = context.oncare;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      // 잠긴 칸은 눌러도 선택창을 열지 않는다(#2889).
      onTap: enabled ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _fieldLabel(label),
          const SizedBox(height: OnCareSpacing.s8),
          InputDecorator(
            decoration: InputDecoration(
              enabled: enabled,
              suffixIcon: AppIcon(icon, size: OnCareSize.iconSmall),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  OnCareTypography.numeric(
                    tokens.text(OnCareTypography.body),
                  ).copyWith(
                    color: enabled
                        ? OnCareColors.textPrimary
                        : OnCareColors.textTertiary,
                  ),
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
      icon: AppIcons.clock,
      onTap: _pickTimeRange,
      enabled: !_scheduleLocked,
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
      // 헷갈린다. 다만 종료일은 시작과 같은 해면 연도를 뺀다 — 반 칸 폭에
      // 두 날짜를 모두 연도까지 적으면 종료일이 잘린다.
      value: repeating
          ? l.schedTimeRange(
              ymd(_date),
              _repeatUntil == null ? '-' : ymdRangeEnd(_date, _repeatUntil!),
            )
          : ymd(_date),
      icon: AppIcons.calendar,
      onTap: _pickDate,
      // 완료 세션은 날짜를 앞으로 옮겨 예정으로 되돌릴 수 있다(#1396) —
      // 취소·노쇼만 날짜까지 잠근다(#2889).
      enabled: !_endedLocked,
    );
  }
}
