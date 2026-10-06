import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/kst_clock_provider.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/dio_schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart'
    show demoUnregisteredClientIdsSnapshot;

/// Identifies a client for [ScheduleRepository.watchClientSessions].
///
/// The two sources key sessions differently: drift stores the client's
/// display NAME on the row, the API filters by member id. Carrying both
/// keeps each implementation honest instead of forcing one to guess.
typedef ScheduleClientKey = ({String id, String name});

/// The trainer's timeline: reads, booking CRUD, and session completion.
///
/// Two implementations sit behind this, selected by
/// [scheduleRepositoryProvider] via [AppConfig.useMockApi]:
///  * [DriftScheduleRepository] — local drift, demo / `USE_MOCK_API=true`;
///  * [DioScheduleRepository] — the real FastAPI backend.
///
/// Reads are streams so the drift source can stay reactive; the Dio
/// source emits a single fetched value and re-reads after each mutation.
abstract interface class ScheduleRepository {
  /// Today's slots in timeline order (including 공백 gaps).
  ///
  /// 화면은 이 메서드 대신 [todayScheduleProvider] 를 쓴다 — 그 provider 는 KST
  /// 날짜 시계(`kstTodayProvider`)를 따라 자정에 새 날짜로 다시 구독한다(#2865).
  Stream<List<ScheduleSession>> watchToday();

  /// The timeline for one calendar [date] (`YYYY-MM-DD`).
  Stream<List<ScheduleSession>> watchDate(String date);

  /// Dates that have at least one booked session (week-strip dots).
  Stream<Set<String>> watchBookedDates();

  /// Every slot between [fromDate] and [toDate] inclusive.
  Stream<List<ScheduleSession>> watchRange(String fromDate, String toDate);

  /// One client's booked sessions, newest first.
  Stream<List<ScheduleSession>> watchClientSessions(ScheduleClientKey client);

  /// [client] 의 [date] 세션을 한 번 읽는다(공백 제외, 시작 시각 순).
  ///
  /// `일정 추가` 확인창이 저장 전에 연결 후보를 보여 주려고 부른다(#1581) —
  /// 계속 지켜볼 화면이 아니라 누른 순간의 한 장면이면 된다.
  Future<List<ScheduleSession>> fetchClientSessionsOn(
    ScheduleClientKey client,
    String date,
  );

  /// Books a new session (status 예정).
  Future<void> addSession({
    required String date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    String note,
  });

  /// Edits a booked session's date/time/client/type/duration/note.
  ///
  /// [date] is omitted for most edits — a booked session's day doesn't
  /// normally move. It's accepted here so an already-완료 session can be
  /// rescheduled forward via [reopenSession] without a second, parallel
  /// update path for every other field.
  ///
  /// [clientId] 가 null 이면 담당 회원을 **그대로 둔다** — 서버의 부분 수정과
  /// 같은 뜻이다. 회원을 바꿀 때만 넘긴다(#2586).
  ///
  /// 다른 칸도 같다 — null 은 '그대로'이고 실서버에는 보내지 않는다(#2754).
  /// 서버는 마무리된(완료·취소·노쇼) 세션과 회원 예약 일정에서 메모·프로그램
  /// 말고 다른 칸이 **오기만 해도** 409 로 거절한다. 그래서 화면은 바뀐 칸만
  /// 넘긴다 — 메모만 고쳤는데 시간·종류까지 실어 보내면 그 거절에 걸린다.
  ///
  /// 거절은 [ServerError](409, 서버 사유)로 온다. 데모 저장소도 같은 사유로
  /// 던진다.
  Future<void> updateSession(
    String id, {
    String? date,
    String? clientName,
    String? clientId,
    String? time,
    String? type,
    int? durationMinutes,
    String? note,
  });

  /// 완료 세션을 [date](미래)의 예정으로 되돌린다. (#1396)
  ///
  /// 일정 수정에서 완료된 회차의 날짜를 앞으로 옮길 때만 쓴다 — 완료가 남긴
  /// 파생 기록(트레이너 이력·회원 운동기록)을 함께 지운다. 예정 세션이나
  /// 과거·오늘 날짜에는 쓸 수 없다(구현이 거부한다).
  ///
  /// 옮길 시각·길이([time]·[durationMinutes])도 이 한 번에 함께 받는다
  /// (#2757). 서버는 그 자리가 다른 일정과 겹치는지 **기록을 지우기 전에**
  /// 본다 — 겹치면 [ScheduleOverlapError] 이고 세션·기록은 그대로다. 예전처럼
  /// 날짜만 먼저 되돌리고 시간은 이어지는 수정에서 바꾸면, 그 수정이 겹침으로
  /// 거절돼도 완료 기록은 이미 지워진 뒤였다. null 이면 지금 값 그대로다.
  Future<void> reopenSession(
    String id, {
    required String date,
    String? time,
    int? durationMinutes,
  });

  /// Replaces the exercise program and trainer memo without changing the
  /// booking itself.
  Future<void> updateProgram(
    String id, {
    required List<ProgramItem> program,
    required String note,
  });

  /// 프로그램 탭 `일정 추가` 한 번 — 회원 배정과 PT 일정 등록을 한 명령으로
  /// 처리한다(#1580). 둘 중 하나만 반영되는 경우가 없다.
  ///
  /// [assignment] 는 `programAssignToJson` 이 만든 배정 본문(이름·세션·멱등키)
  /// 이다. 같은 멱등키로 다시 보내면 배정도 일정도 두 번 생기지 않는다.
  /// [program] 은 같은 구성을 일정 항목으로 펼친 것으로, 로컬(데모) 구현만
  /// 쓴다 — 서버는 세션에서 직접 펼친다.
  ///
  /// 연결 대상은 [time] 부터 [durationMinutes] 동안과 겹치는 그날 예정
  /// 세션이다(#1581). 없으면 그 시간으로 새로 만들고 `false`, 하나면 거기에
  /// 붙이고 `true`. 여럿이면 [sessionId] 로 고른 것에만 붙이며, 고르지
  /// 않았거나 고른 것이 후보가 아니면 [ProgramAttachConflictError].
  ///
  /// [personalRoutines] 는 그 PT 사이에 회원이 혼자 할 개인운동이다(#2223).
  /// 같은 명령으로 그 일정에 붙기만 하고 회원에게는 가지 않는다 — 보내는 것은
  /// PT 완료 때다(#2224).
  Future<bool> registerProgramSchedule({
    required String date,
    required String clientId,
    required String clientName,
    required String time,
    required int durationMinutes,
    required Map<String, Object?> assignment,
    required List<ProgramItem> program,
    String? sessionId,
    List<RoutineExercise> personalRoutines,
  });

  /// Removes a session from the timeline.
  Future<void> deleteSession(String id);

  /// Marks an 예정 session 완료 with the trainer's [note].
  Future<void> completeSession(String id, {String note});

  /// 그 PT 에 붙어 있는 개인운동 — **보낸 것까지 함께**. (#2224)
  ///
  /// 일정 상세의 `개인운동` 갈래가 이 목록을 그린다. 보낸 뒤에 목록에서
  /// 빼 버리면 트레이너가 그 PT 에 무엇을 딸려 보냈는지 볼 데가 없어진다 —
  /// 그래서 건마다 [SessionRoutine.sent] 로 가른다.
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id);

  /// 이 회원의 PT 에 붙여만 두고 **아직 보내지 않은** 개인운동. (#2225)
  ///
  /// 지금은 그 사실이 스케줄 탭의 그 일정을 열어야만 보인다 — 프로그램 탭에서도
  /// 알리고 거기서 보낼 수 있어야 한다. 줄마다 붙은 일정 id 로 어느 PT 의
  /// 것인지 안다.
  Future<List<UnsentRoutine>> fetchUnsentRoutinesFor(String clientId);

  /// 그 PT 에 붙은 개인운동을 고친다 — 보내지는 않는다. (#2224)
  ///
  /// 일정 상세에서 바로 고치는 길이다. 프로그램 만들기로 돌아가지 않고 운동
  /// 하나를 빼거나 시간을 줄일 수 있어야 한다 — PT 직전에 회원 상태를 보고
  /// 손보는 일이 흔하다. **이미 보낸 것은 손댈 수 없다.**
  Future<void> updateScheduledRoutines(String id, List<RoutineExercise> items);

  /// 마무리된 PT 에 남은 개인운동을 회원에게 보낸다. (#2224)
  ///
  /// [items] 를 주면 그 내용으로 고쳐서 보낸다 — 취소된 PT 에는 프로그램
  /// 만들기로 다시 붙일 수 없어 고치는 자리가 여기뿐이다.
  Future<void> sendScheduledRoutines(String id, {List<RoutineExercise>? items});

  /// 마무리된 PT 의 개인운동을 보내지 않기로 정리한다. (#2224)
  Future<void> dismissScheduledRoutines(String id);

  /// 저장 전에 보여 줄 회차와 충돌. (#870)
  ///
  /// 반복은 한 번에 여러 건을 만든다 — 요일이나 종료일을 잘못 골랐을 때 되돌리는
  /// 비용이 한 건씩 지우는 일이라, 그 전에 보여 주는 편이 싸다.
  ///
  /// [durationMinutes] 는 회차 하나의 길이다. 겹침은 시작 시각이 아니라 시간
  /// 구간으로 본다(#2284).
  ///
  /// [clientRequestId] 는 [addRecurringSessions] 에 보낼 것과 같은 키다. 그
  /// 키로 이미 만들어진 회차는 충돌에서 빼고 `alreadyCreated` 로 알린다 —
  /// 응답만 잃은 재시도가 방금 만든 자기 회차와 겹친다고 막히지 않게(#3102).
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    int durationMinutes = 0,
    String? clientRequestId,
  });

  /// 반복 규칙대로 회차를 한 번에 만든다. (#870)
  ///
  /// **전부 만들거나 하나도 만들지 않는다** — 겹치는 회차가 있으면
  /// [ScheduleSeriesConflictError] 로 멈춘다. 겹친 것만 빼고 나머지를 만들면
  /// 트레이너는 몇 회차가 생겼는지 화면을 세어 봐야 알고, 빠진 주는 나중에
  /// 발견된다.
  ///
  /// 만들어진 세션들을 돌려준다 — 일정 수정에서 기존 회차를 반복의 시작으로
  /// 만들 때, 오늘 이전 날짜의 회차를 [completeSession] 으로 이어서 완료
  /// 처리하려면 그 id 가 필요하다(#1396).
  Future<List<ScheduleSession>> addRecurringSessions({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    required String clientName,
    String? clientId,
    required String type,
    required int durationMinutes,
    String note,
    String? clientRequestId,
  });

  /// 예정 세션을 `취소` 로 남긴다. **삭제와 다른 동작이다** — 삭제는 잘못 만든
  /// 일정을 없애고, 이쪽은 실제로 있었던 약속이 진행되지 않았다는 기록을
  /// 남긴다(#871).
  ///
  /// [source] 는 취소 주체(`CancellationSource`)다. 트레이너 사정의 취소를
  /// 회원의 미이행으로 읽지 않으려면 주체가 남아야 해서 필수로 받는다.
  Future<void> cancelSession(
    String id, {
    required String source,
    String reason,
  });

  /// 예정 세션을 `노쇼` 로 남긴다 — 약속은 그대로였고 회원이 오지 않았다.
  Future<void> markNoShow(String id);

  /// 완료한 세션의 프로그램을 그 회원에게 보낸다. (#822)
  ///
  /// [clientRequestId] 는 전송 시도의 멱등키다 — 실패해서 다시 눌러도 회원의
  /// 루틴이 두 벌 생기지 않는다. 보낼 상대(회원)나 보낼 내용(프로그램)이 없거나
  /// 아직 완료 전이면 예외다. 이미 보낸 세션에 다시 부르면 조용히 성공한다.
  Future<void> sendProgram(String id, {String? clientRequestId});
}

/// 아직 보내지 않은 개인운동 한 건과 그것이 붙은 PT. (#2225)
class UnsentRoutine {
  /// Creates an unsent routine row.
  const UnsentRoutine({
    required this.exercise,
    required this.scheduleId,
    this.scheduleDate = '',
  });

  final RoutineExercise exercise;

  /// 이 개인운동이 붙은 PT 일정 — 보내는 것은 그 일정의 전송이 맡는다.
  final String scheduleId;

  /// 그 일정의 날짜(`YYYY-MM-DD`). 스케줄 탭의 **그 주**를 열어야 일정 상세에
  /// 닿는다 — 일정 id 만으로는 이번 주에서 찾지 못한다. (#2225)
  final String scheduleDate;
}

/// PT 일정에 붙어 있는 개인운동 한 건과 그 처지. (#2224)
///
/// 보낸 것과 보낼 것이 한 목록에 섞여 오므로 [sent] 로 가른다 — 전송 버튼이
/// 무엇을 실을지, 상세가 어느 줄에 `전송됨` 을 붙일지가 이 값으로 갈린다.
class SessionRoutine {
  /// Creates a routine row for a PT session.
  const SessionRoutine({required this.exercise, required this.sent});

  final RoutineExercise exercise;

  /// 이미 회원에게 나갔는가.
  final bool sent;
}

/// Reads the trainer's daily timeline from the local drift DB.
/// 데모에서 프로그램과 함께 붙어 있는 개인운동 — 그 회원에게 심어 둔 AI 개인
/// 운동이 없을 때만 쓴다. 실 API 는 서버가 준다.
const List<RoutineExercise> _demoPersonalRoutines = <RoutineExercise>[
  RoutineExercise(name: '저강도 걷기', minutes: 30, type: '유산소', source: 'ai'),
  RoutineExercise(name: '코어 스트레칭', minutes: 10, type: '스트레칭', source: 'ai'),
];

/// 한 PT 에 처음 붙어 있는 개인운동 수.
const int _seedRoutinesPerSession = 2;

/// 저장된 프로그램에 운동이 하나도 없는가 — 깨진 값도 비어 있는 것으로 읽는다.
bool _decodedProgramIsEmpty(String programJson) {
  if (programJson.isEmpty) return true;
  try {
    return (jsonDecode(programJson) as List<Object?>).isEmpty;
  } catch (_) {
    return true;
  }
}

/// 두 개인운동이 트레이너가 손대지 않은 같은 줄인가 — 출처는 보지 않는다.
///
/// 시간은 초로 비교한다(#2547) — 분은 초에서 반올림한 값이라, `45초` 를
/// `50초` 로 고쳐도 둘 다 1분이어서 손대지 않은 줄로 읽혔다.
bool samePersonalRoutine(RoutineExercise a, RoutineExercise b) =>
    a.name == b.name &&
    a.seconds == b.seconds &&
    a.type == b.type &&
    a.sets == b.sets &&
    a.reps == b.reps &&
    a.holdSeconds == b.holdSeconds &&
    a.weight == b.weight;

class DriftScheduleRepository implements ScheduleRepository {
  /// Creates the repository over [_db].
  const DriftScheduleRepository(this._db);

  final AppDatabase _db;

  /// PT 에 붙은 개인운동의 보냄·숨김·수정 상태와, 보낸 것의 배정·전달 기록을
  /// 남기는 곳(#2668). 메모리 집합이던 동안에는 새로고침하면 처음으로 돌아갔다.
  DemoRoutineStore get _routineStore => DemoRoutineStore(_db);

  /// 일정 하나를 지금 모습으로 읽는다. 없으면 `null`.
  ///
  /// 데모의 마지막 전달이 딸린 PT 를 id 로만 기억해 두고 여기서 다시 읽는다
  /// — 보낸 뒤 바뀐 일정 상태가 전달에도 그대로 보인다.
  Future<ScheduleSession?> sessionById(String id) async {
    final row = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  /// 이 PT 에 처음 붙어 있는 개인운동 — 그 회원에게 심어 둔 AI 개인운동에서
  /// 고른다(#2668).
  ///
  /// 예전에는 모든 PT 가 같은 두 개(저강도 걷기·코어 스트레칭)였다. 회원마다
  /// 목록이 다르고, 같은 회원이라도 일정마다 시작 자리를 달리해 PT 마다 다른
  /// 조합이 붙는다. 자리는 일정 id 로 정해 다시 읽어도 같다.
  Future<List<RoutineExercise>> _seedSessionRoutines(
    TrainerScheduleRow row,
  ) async {
    final String? clientId = row.clientId;
    if (clientId == null) return _demoPersonalRoutines;
    final pool =
        await (_db.select(_db.clientAiRoutines)
              ..where((t) => t.clientId.equals(clientId))
              ..orderBy(<OrderingTerm Function($ClientAiRoutinesTable)>[
                (t) => OrderingTerm(expression: t.sortOrder),
              ]))
            .get();
    if (pool.isEmpty) return _demoPersonalRoutines;
    final int start =
        row.id.codeUnits.fold<int>(0, (int sum, int c) => sum + c) %
        pool.length;
    return <RoutineExercise>[
      for (var i = 0; i < _seedRoutinesPerSession && i < pool.length; i++)
        // 근력은 세트·횟수까지 싣는다 — 없으면 `0세트 · 0회` 로 그려진다.
        seedAiRoutineExercise(pool[(start + i) % pool.length]),
    ];
  }

  /// 이 일정에 지금 붙어 있는 개인운동 — 손댄 것이 있으면 그것, 없으면 시드.
  Future<List<RoutineExercise>> _sessionRoutines(
    TrainerScheduleRow row,
    SessionRoutineState? state,
  ) async => state?.items ?? await _seedSessionRoutines(row);

  /// 이 일정에 붙은 개인운동이 회원에게 갔다 — 배정 목록에 넣고 마지막
  /// 전달로 남긴다(#2668). 실서버가 전송 한 번에 둘을 함께 남기는 것과 같다.
  ///
  /// 예전에는 `sent` 표시만 남아, 트레이너 웹의 전송 이력은 PT 와 함께 간 것도
  /// 취소된 PT 뒤에 보낸 것도 늘 `개인운동만` 으로 그렸다.
  Future<void> _recordDelivery(
    TrainerScheduleRow row,
    String kind,
    List<RoutineExercise> routines, {
    List<String> programNames = const <String>[],
  }) async {
    final String? clientId = row.clientId;
    if (clientId == null) return;
    final DateTime now = nowKst();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<AssignedRoutine> sent = <AssignedRoutine>[
      for (var i = 0; i < routines.length; i++)
        assignedFromExercise(
          routines[i],
          id: 'demo-${row.id}-${now.microsecondsSinceEpoch}-$i',
          deliveryKind: kind,
          date: today,
          scheduleId: row.id,
        ),
    ];
    await _routineStore.recordDelivery(
      clientId,
      StoredDelivery(
        kind: kind,
        sentOn: today,
        sessionId: row.id,
        routines: sent,
      ),
      programNames: programNames,
    );
  }

  /// Today's slots in timeline order (including 공백 gaps).
  ///
  /// drift 질의는 날짜를 조건으로 거는 반응형 스트림이라 구독한 날의 표를
  /// 본다. 대시보드는 이 메서드가 아니라 [todayScheduleProvider] 를 쓰고, 그
  /// provider 가 날짜 시계를 따라 자정에 새 날짜로 다시 구독한다(#2865).
  @override
  Stream<List<ScheduleSession>> watchToday() => watchDate(ymd(nowKst()));

  /// The timeline for one calendar [date] (`YYYY-MM-DD`).
  ///
  /// 미등록(담당 종료) 고객의 슬롯은 원본 행을 지우지 않고 걸러낸다(#1623)
  /// — 트레이너 화면에서만 빠지고, 다시 등록하면 그대로 돌아온다.
  @override
  Stream<List<ScheduleSession>> watchDate(String date) {
    final query = _db.select(_db.trainerScheduleEntries)
      ..where((t) => t.date.equals(date))
      // Time first (zero-padded HH:MM sorts lexicographically) so
      // trainer-added sessions land at the right timeline position;
      // sortOrder only breaks ties between seed rows.
      ..orderBy(<OrderingTerm Function($TrainerScheduleEntriesTable)>[
        (t) => OrderingTerm(expression: t.time),
        (t) => OrderingTerm(expression: t.sortOrder),
      ]);
    return _watchExcludingUnregistered(
      query,
      (rows) => rows.map(_toEntity).toList(),
      keyOf: (s) => s.clientId,
    );
  }

  /// Dates (`YYYY-MM-DD`) that have at least one booked (non-공백)
  /// session — drives the week strip's dot markers. 미등록 고객의 슬롯만
  /// 있는 날은 점을 찍지 않는다(#1623).
  @override
  Stream<Set<String>> watchBookedDates() {
    final t = _db.trainerScheduleEntries;
    final query = _db.selectOnly(t)
      ..addColumns(<Expression<Object>>[t.date, t.clientId])
      ..where(t.status.equals(ScheduleStatus.gap).not());
    return query.watch().map((rows) {
      final unregistered = demoUnregisteredClientIdsSnapshot(_db);
      final dates = <String>{};
      for (final row in rows) {
        final clientId = row.read(t.clientId);
        if (clientId != null && unregistered.contains(clientId)) continue;
        dates.add(row.read(t.date)!);
      }
      return dates;
    });
  }

  /// Every slot between [fromDate] and [toDate] inclusive (`YYYY-MM-DD`),
  /// ordered by day then time. Backs the week calendar — one query for
  /// the whole week rather than seven day subscriptions.
  @override
  Stream<List<ScheduleSession>> watchRange(String fromDate, String toDate) {
    final query = _db.select(_db.trainerScheduleEntries)
      // `YYYY-MM-DD` is lexicographically ordered, so a string BETWEEN
      // is a correct date-range filter here.
      ..where(
        (t) =>
            t.date.isBiggerOrEqualValue(fromDate) &
            t.date.isSmallerOrEqualValue(toDate),
      )
      ..orderBy(<OrderingTerm Function($TrainerScheduleEntriesTable)>[
        (t) => OrderingTerm(expression: t.date),
        (t) => OrderingTerm(expression: t.time),
        (t) => OrderingTerm(expression: t.sortOrder),
      ]);
    return _watchExcludingUnregistered(
      query,
      (rows) => rows.map(_toEntity).toList(),
      keyOf: (s) => s.clientId,
    );
  }

  /// Re-runs [query] whenever the table it reads from changes, then drops
  /// entries whose [keyOf] id is currently unregistered. `null` ids
  /// (공백 슬롯 등, 특정 고객에 속하지 않는 행) always pass through.
  Stream<List<T>> _watchExcludingUnregistered<Row extends Object, T>(
    Selectable<Row> query,
    List<T> Function(List<Row> rows) toEntities, {
    required String? Function(T entity) keyOf,
  }) {
    return query.watch().map((rows) {
      final unregistered = demoUnregisteredClientIdsSnapshot(_db);
      return toEntities(rows)
          .where((e) => keyOf(e) == null || !unregistered.contains(keyOf(e)))
          .toList();
    });
  }

  /// A client's booked sessions, newest first. Drives the 고객 상세 루틴
  /// tab (what programs this person has been given).
  ///
  /// Sessions belonging to [client] — matched by **id**, not name (#386).
  ///
  /// 이름 매칭은 조용히 실패했다. 고객 이름을 바꾸거나 공백·대소문자가 어긋나면
  /// 크래시도 오류 표시도 없이 주간 리포트가 "세션 0건" 이 되고, 트레이너가
  /// 그걸 그대로 회원에게 전송할 수 있었다.
  ///
  /// v3 이전에 저장된 행은 `client_id` 가 null 이라 예전처럼 정규화된 이름으로
  /// 폴백한다. 폴백은 `lower(trim(name))` — 시드 회원 이름 유일성 검사
  /// (`seed_data_test`)와 같은 정규화라, 저장/조회 기준이 어긋나지 않는다.
  @override
  Stream<List<ScheduleSession>> watchClientSessions(ScheduleClientKey client) {
    final query = _db.select(_db.trainerScheduleEntries)
      ..where(
        (t) =>
            (t.clientId.equals(client.id) |
                (t.clientId.isNull() &
                    t.clientName.lower().trim().equals(
                      client.name.trim().toLowerCase(),
                    ))) &
            t.status.equals(ScheduleStatus.gap).not(),
      )
      ..orderBy(<OrderingTerm Function($TrainerScheduleEntriesTable)>[
        (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.time, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  /// [watchClientSessions] 와 같은 회원 매칭으로 그날 세션을 한 번 읽는다(#1581).
  @override
  Future<List<ScheduleSession>> fetchClientSessionsOn(
    ScheduleClientKey client,
    String date,
  ) async {
    final query = _db.select(_db.trainerScheduleEntries)
      ..where(
        (t) =>
            t.date.equals(date) &
            (t.clientId.equals(client.id) |
                (t.clientId.isNull() &
                    t.clientName.lower().trim().equals(
                      client.name.trim().toLowerCase(),
                    ))) &
            t.status.equals(ScheduleStatus.gap).not(),
      )
      ..orderBy(<OrderingTerm Function($TrainerScheduleEntriesTable)>[
        (t) => OrderingTerm(expression: t.time),
      ]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  /// [date] 에서 [time]부터 [durationMinutes] 동안과 겹치는 예정·완료 세션
  /// (#2284). 취소·노쇼·공백은 그 시간을 차지하지 않는다. [excludeId] 는
  /// 옮기는 세션 자신이다.
  ///
  /// 데모는 같은 날만 본다 — 자정을 넘기는 세션까지 따지는 것은 서버 몫이다.
  Future<List<ScheduleSession>> _overlapping({
    required String date,
    required String time,
    required int durationMinutes,
    String? excludeId,
  }) async {
    final rows =
        await (_db.select(_db.trainerScheduleEntries)..where(
              (t) =>
                  t.date.equals(date) &
                  t.status.isIn(<String>[
                    ScheduleStatus.upcoming,
                    ScheduleStatus.done,
                  ]),
            ))
            .get();
    return <ScheduleSession>[
      for (final row in rows)
        if (row.id != excludeId &&
            timeRangesOverlap(
              row.time,
              row.durationMinutes,
              time,
              durationMinutes,
            ))
          _toEntity(row),
    ];
  }

  Future<void> _ensureNoOverlap({
    required String date,
    required String time,
    required int durationMinutes,
    String? excludeId,
  }) async {
    final conflicts = await _overlapping(
      date: date,
      time: time,
      durationMinutes: durationMinutes,
      excludeId: excludeId,
    );
    if (conflicts.isNotEmpty) throw ScheduleOverlapError(conflicts);
  }

  /// Books a new session on [date]'s timeline (status 예정). The
  /// non-`seed-` id survives the daily re-seed. 다른 일정과 시간이 겹치면
  /// [ScheduleOverlapError] 로 멈춘다(#2284).
  @override
  Future<void> addSession({
    required String date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    String note = '',
  }) async {
    await _ensureNoOverlap(
      date: date,
      time: time,
      durationMinutes: durationMinutes,
    );
    await _db
        .into(_db.trainerScheduleEntries)
        .insert(
          TrainerScheduleEntriesCompanion.insert(
            id: 'sched-${DateTime.now().microsecondsSinceEpoch}',
            date: date,
            time: time,
            clientId: Value(clientId),
            clientName: Value(clientName),
            type: Value(type),
            durationMinutes: Value(durationMinutes),
            status: ScheduleStatus.upcoming,
            programJson: const Value('[]'),
            note: Value(note),
          ),
        );
  }

  /// Edits a booked session's date/time/client/type/duration. 옮긴 시간이
  /// 자기 말고 다른 일정과 겹치면 [ScheduleOverlapError] 로 멈춘다(#2284).
  ///
  /// 서버와 같은 상태 규칙(#2754·#2756) — 마무리된 세션과 회원 예약 일정은
  /// 메모만 고칠 수 있다. 예약 시각·회원·종류·길이를 **바꾸려 하면** 서버와 같은
  /// 사유의 [ServerError](409)로 멈춘다. 지금 값과 같은 값은 바꾸는 것이 아니라
  /// 통과시킨다(화면은 바뀐 칸만 넘긴다).
  @override
  Future<void> updateSession(
    String id, {
    String? date,
    String? clientName,
    String? clientId,
    String? time,
    String? type,
    int? durationMinutes,
    String? note,
  }) async {
    final current = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (current != null) {
      final bool changesBooking =
          (date != null && date != current.date) ||
          (clientName != null && clientName != current.clientName) ||
          (clientId != null && clientId != current.clientId) ||
          (time != null && time != current.time) ||
          (type != null && type != current.type) ||
          (durationMinutes != null &&
              durationMinutes != current.durationMinutes);
      if (changesBooking && isDemoReservationScheduleId(id)) {
        throw const ServerError(
          statusCode: 409,
          message: demoReservationEditRejected,
        );
      }
      if (changesBooking && current.status != ScheduleStatus.upcoming) {
        throw const ServerError(
          statusCode: 409,
          message: demoFinishedEditRejected,
        );
      }
      await _ensureNoOverlap(
        date: date ?? current.date,
        time: time ?? current.time,
        durationMinutes: durationMinutes ?? current.durationMinutes,
        excludeId: id,
      );
    }
    await (_db.update(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).write(
      TrainerScheduleEntriesCompanion(
        date: date == null ? const Value.absent() : Value(date),
        // null 은 '그대로' 다 — 덮어쓰면 회원을 고르지 않은 수정이 담당 회원을
        // 지운다(#2586).
        clientId: clientId == null ? const Value.absent() : Value(clientId),
        clientName: clientName == null
            ? const Value.absent()
            : Value(clientName),
        time: time == null ? const Value.absent() : Value(time),
        type: type == null ? const Value.absent() : Value(type),
        durationMinutes: durationMinutes == null
            ? const Value.absent()
            : Value(durationMinutes),
        note: note == null ? const Value.absent() : Value(note),
      ),
    );
    if (current != null &&
        current.status == ScheduleStatus.done &&
        note != null &&
        note != current.note) {
      await _syncCompletionHistory(id, note: note);
    }
    if (current != null) {
      await _moveDemoConsultationLink(
        current,
        clientId: clientId ?? current.clientId,
        date: date ?? current.date,
        time: time ?? current.time,
      );
    }
  }

  /// 상담 일정을 옮기면 상담 연결도 새 날짜·시각으로 옮긴다(#2758).
  ///
  /// 연결은 회원·날짜·시각을 키로 붙는다. 그대로 두면 옮긴 일정이 상담 요청
  /// 내용을 잃고, 상담함은 그 신청의 일정이 사라진 것으로 읽는다. 서버처럼
  /// 신청의 시각은 이 일정을 따른다 — 예전 자리는 일정이 떠나 다시 빈다.
  Future<void> _moveDemoConsultationLink(
    TrainerScheduleRow before, {
    required String? clientId,
    required String date,
    required String time,
  }) async {
    if (before.type != SessionType.consultation) return;
    final String from = demoConsultationKey(
      clientId: before.clientId,
      date: before.date,
      time: before.time,
    );
    final String to = demoConsultationKey(
      clientId: clientId,
      date: date,
      time: time,
    );
    if (from == to) return;
    final ScheduleConsultation? link = demoScheduleConsultations.remove(from);
    if (link == null) return;
    demoScheduleConsultations[to] = link;
    await writeDemoScheduleConsultations(_db);
  }

  /// 완료 세션을 [date](미래)의 예정으로 되돌린다(#1396). 완료가 남긴 이력
  /// (`hist-$id-시각`)도 서버처럼 함께 지운다(#3093) — 남겨 두면 되돌린 PT 가
  /// 고객 운동 기록에 "이미 한 운동" 으로 남는다.
  ///
  /// 옮길 자리가 다른 일정과 겹치는지는 **아무것도 바꾸기 전에** 본다(#2757) —
  /// 겹치면 [ScheduleOverlapError] 이고 세션은 완료 그대로다. 회원 예약 일정은
  /// 서버처럼 되돌리지 않는다(409).
  @override
  Future<void> reopenSession(
    String id, {
    required String date,
    String? time,
    int? durationMinutes,
  }) async {
    final table = _db.trainerScheduleEntries;
    final today = ymd(nowKst());
    if (date.compareTo(today) <= 0) {
      throw StateError('reopen requires a future date: $date');
    }
    if (isDemoReservationScheduleId(id)) {
      throw const ServerError(
        statusCode: 409,
        message: demoReservationReopenRejected,
      );
    }
    await _db.transaction(() async {
      final session = await (_db.select(
        table,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (session == null || session.status != ScheduleStatus.done) {
        throw StateError('session not completed: $id');
      }
      final String newTime = time ?? session.time;
      final int newDuration = durationMinutes ?? session.durationMinutes;
      await _ensureNoOverlap(
        date: date,
        time: newTime,
        durationMinutes: newDuration,
        excludeId: id,
      );
      await (_db.update(table)..where((t) => t.id.equals(id))).write(
        TrainerScheduleEntriesCompanion(
          date: Value(date),
          time: Value(newTime),
          durationMinutes: Value(newDuration),
          status: const Value(ScheduleStatus.upcoming),
        ),
      );
      await _deleteCompletionHistory(id);
    });
  }

  /// 완료가 남긴 이 세션의 이력 행 id(`hist-$id-<마이크로초>`, [completeSession]).
  ///
  /// 서버의 `sched-hist-{id}` 자리다. 키에 시각이 붙어 접두어로 찾고, 다른
  /// 세션 id 가 이 id 로 시작하는 경우에 걸리지 않게 꼬리가 숫자뿐인 것만
  /// 고른다. 시드 이력은 세션과 이어져 있지 않아 걸리지 않는다.
  Future<List<String>> _completionHistoryIds(String id) async {
    final String prefix = 'hist-$id-';
    final rows = await (_db.select(
      _db.clientRoutineHistory,
    )..where((t) => t.id.like('$prefix%'))).get();
    final RegExp digits = RegExp(r'^\d+$');
    return <String>[
      for (final row in rows)
        if (row.id.startsWith(prefix) &&
            digits.hasMatch(row.id.substring(prefix.length)))
          row.id,
    ];
  }

  /// 완료한 세션의 프로그램·메모를 고치면 완료가 남긴 이력도 같은 값으로
  /// 고친다(#3093) — 서버가 같은 저장에서 트레이너 이력을 다시 쓴다. null 은
  /// '그대로' 다.
  Future<void> _syncCompletionHistory(
    String id, {
    String? programJson,
    String? note,
  }) async {
    if (programJson == null && note == null) return;
    final List<String> ids = await _completionHistoryIds(id);
    if (ids.isEmpty) return;
    await (_db.update(
      _db.clientRoutineHistory,
    )..where((t) => t.id.isIn(ids))).write(
      ClientRoutineHistoryCompanion(
        exercisesJson: programJson == null
            ? const Value.absent()
            : Value(_historyExercisesJson(programJson)),
        trainerNote: note == null ? const Value.absent() : Value(note),
      ),
    );
  }

  /// 완료가 남긴 이력을 지운다 — 세션 삭제·되돌리기(#3093).
  Future<void> _deleteCompletionHistory(String id) async {
    final List<String> ids = await _completionHistoryIds(id);
    if (ids.isEmpty) return;
    await (_db.delete(
      _db.clientRoutineHistory,
    )..where((t) => t.id.isIn(ids))).go();
  }

  /// 일정 프로그램을 이력의 운동 목록으로 옮긴다. 완료와 완료 뒤 수정이 같은
  /// 값을 쓰도록 한 곳에 둔다(#3093). 문장이 아니라 값으로 남긴다 — 단위는
  /// 화면이 로케일에 맞춰 붙인다(#2300). 읽는 규칙은 서버
  /// `_program_item_label` 과 같다.
  static String _historyExercisesJson(String programJson) {
    final program = (jsonDecode(programJson) as List<Object?>)
        .map((e) => programItemFromJson(e! as Map<String, Object?>))
        .toList();
    return jsonEncode(<Map<String, Object?>>[
      for (final m in program) programHistoryItem(m).toJson(),
    ]);
  }

  /// Replaces the exercise program and trainer memo without changing the
  /// booking itself (client, type, time, or duration).
  ///
  /// 마무리된 세션에서도 쓸 수 있다(#2754). 다만 회원에게 이미 보낸 프로그램은
  /// 서버처럼 내용을 바꾸지 못한다(409) — 같은 프로그램에 메모만 고치는 것은
  /// 통과한다.
  @override
  Future<void> updateProgram(
    String id, {
    required List<ProgramItem> program,
    required String note,
  }) async {
    final current = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (current != null &&
        current.programSent &&
        jsonEncode(programToJson(program)) !=
            jsonEncode(jsonDecode(current.programJson))) {
      throw const ServerError(
        statusCode: 409,
        message: demoSentProgramEditRejected,
      );
    }
    final String programJson = jsonEncode(programToJson(program));
    await (_db.update(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).write(
      TrainerScheduleEntriesCompanion(
        programJson: Value(programJson),
        note: Value(note),
      ),
    );
    if (current != null && current.status == ScheduleStatus.done) {
      await _syncCompletionHistory(
        id,
        programJson: programJson == current.programJson ? null : programJson,
        note: note == current.note ? null : note,
      );
    }
  }

  /// 데모에는 루틴을 받을 회원 백엔드가 없어 배정은 쓰지 않는다
  /// (`MockTrainerRoutineRepository.assignProgram` 도 no-op) — 일정 쪽만
  /// 로컬에 한 트랜잭션으로 반영한다.
  @override
  Future<bool> registerProgramSchedule({
    required String date,
    required String clientId,
    required String clientName,
    required String time,
    required int durationMinutes,
    required Map<String, Object?> assignment,
    required List<ProgramItem> program,
    String? sessionId,
    List<RoutineExercise> personalRoutines = const <RoutineExercise>[],
  }) {
    final table = _db.trainerScheduleEntries;
    return _db.transaction(() async {
      final sameDay =
          await (_db.select(table)
                ..where(
                  (t) =>
                      t.date.equals(date) &
                      t.status.equals(ScheduleStatus.upcoming),
                )
                ..orderBy(<OrderingTerm Function($TrainerScheduleEntriesTable)>[
                  (t) => OrderingTerm(expression: t.time),
                ]))
              .get();

      // 서버와 같은 규칙 — 이 회원의, 고른 시간대와 겹치는 예정 세션(#1581).
      final normalizedName = clientName.trim().toLowerCase();
      final candidates = <TrainerScheduleRow>[
        for (final row in sameDay)
          if ((row.clientId == clientId ||
                  (row.clientId == null &&
                      row.clientName.trim().toLowerCase() == normalizedName)) &&
              timeRangesOverlap(
                row.time,
                row.durationMinutes,
                time,
                durationMinutes,
              ))
            row,
      ];
      TrainerScheduleRow? existing;
      if (sessionId != null) {
        for (final row in candidates) {
          if (row.id == sessionId) existing = row;
        }
        if (existing == null) throw const ProgramAttachConflictError();
      } else if (candidates.length > 1) {
        throw const ProgramAttachConflictError();
      } else if (candidates.isNotEmpty) {
        existing = candidates.single;
      }

      // 붙일 PT 가 없어 새로 잡는 자리 — 다른 회원 일정과도 겹치면 안 된다
      // (#2284). 이 회원의 겹치는 PT 는 위에서 이미 후보로 걸렀다.
      if (existing == null) {
        await _ensureNoOverlap(
          date: date,
          time: time,
          durationMinutes: durationMinutes,
        );
      }

      final encodedProgram = jsonEncode(programToJson(program));
      if (existing != null) {
        await (_db.update(
          table,
        )..where((t) => t.id.equals(existing!.id))).write(
          TrainerScheduleEntriesCompanion(programJson: Value(encodedProgram)),
        );
        // 서버와 같은 규칙 — 다시 붙이면 개인운동도 **새것으로 갈린다**(#2224).
        // 쌓아 두면 두 번 짠 트레이너가 두 배를 보내게 된다.
        await _rememberPersonalRoutines(existing.id, personalRoutines);
        return true;
      }

      final now = nowKst();
      final String newId = 'sched-${now.microsecondsSinceEpoch}';
      await _db
          .into(table)
          .insert(
            TrainerScheduleEntriesCompanion.insert(
              id: newId,
              date: date,
              time: time,
              clientId: Value(clientId),
              clientName: Value(clientName),
              type: const Value(SessionType.personalTraining),
              durationMinutes: Value(durationMinutes),
              status: ScheduleStatus.upcoming,
              programJson: Value(encodedProgram),
            ),
          );
      // 트레이너가 방금 짠 개인운동이 그대로 이 PT 에 붙는다(#2224) — 실
      // API 는 서버가 들고 있고, 데모는 키-값 표에 남긴다(#2668).
      // 기억하지 않으면 스케줄 카드가 짠 것 대신 늘 같은 데모 두 개를 보여
      // 줘, 데모로는 "내가 짠 것이 그대로 가는가" 를 확인할 수 없다.
      await _rememberPersonalRoutines(newId, personalRoutines);
      return false;
    });
  }

  /// 이 일정에 붙은 개인운동을 데모 기억에 남긴다. 비었으면 기억도 지운다 —
  /// 개인운동 없이 다시 붙였는데 옛것이 남아 있으면 안 된다.
  ///
  /// 보냄·숨김 표시도 함께 지운다 — 새로 붙인 개인운동은 아직 아무 데도 가지
  /// 않았다.
  ///
  /// 그 개인운동을 채운 AI 제안은 검토한 것으로 남긴다(#2747) — 실서버가 등록
  /// 트랜잭션에서 그 제안을 닫는 것과 같다.
  Future<void> _rememberPersonalRoutines(
    String sessionId,
    List<RoutineExercise> routines,
  ) async {
    await _routineStore.writeSession(
      sessionId,
      SessionRoutineState(items: List<RoutineExercise>.unmodifiable(routines)),
    );
    await _routineStore.addReviewedSuggestions(suggestionIdsOf(routines));
  }

  /// Removes a session from the timeline.
  @override
  /// 데모에는 받을 회원 백엔드가 없다. 전송은 이 표시와 전송 기록으로 끝나지만,
  /// 화면이 '전송됨' 을 사실대로 말하고 같은 세션을 두 번 보내지 않으려면 남아야
  /// 한다.
  @override
  Future<void> sendProgram(String id, {String? clientRequestId}) async {
    final table = _db.trainerScheduleEntries;
    final session = await (_db.select(
      table,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (session == null) throw StateError('session not found: $id');
    if (session.programSent) return; // 이미 보냈다 — 멱등.
    if (session.status != ScheduleStatus.done) {
      throw StateError('session not completed: $id');
    }
    if ((jsonDecode(session.programJson) as List<Object?>).isEmpty) {
      throw StateError('session has no program: $id');
    }
    await (_db.update(table)..where((t) => t.id.equals(id))).write(
      const TrainerScheduleEntriesCompanion(programSent: Value(true)),
    );
    // 개인운동은 PT 프로그램과 함께 나간다(#2224) — 전송 이력에도 `PT 와 함께`
    // 로 남는다(#2668). 보내지 않기로 정리한 것은 싣지 않는다.
    final SessionRoutineState? state = await _routineStore.readSession(id);
    await _recordDelivery(
      session,
      DeliveryKinds.ptWithRoutine,
      (state?.dismissed ?? false)
          ? const <RoutineExercise>[]
          : await _sessionRoutines(session, state),
      // 프로그램과 개인운동을 채팅 안내 하나로 남긴다(#2672).
      programNames: <String>[
        for (final Object? item in jsonDecode(session.programJson) as List)
          if (item is Map && item['name'] is String) item['name']! as String,
      ],
    );
  }

  /// 회원 예약 일정은 지우지 않는다 — 예약·남은 횟수와 어긋난다. 서버와 같은
  /// 사유의 409 다(#2756). 그 약속을 없애려면 취소한다.
  @override
  Future<void> deleteSession(String id) async {
    if (isDemoReservationScheduleId(id)) {
      throw const ServerError(
        statusCode: 409,
        message: demoReservationDeleteRejected,
      );
    }
    final TrainerScheduleRow? row = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await (_db.delete(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).go();
    // 완료 세션이면 완료가 남긴 이력도 지운다 — 서버와 같다(#3093).
    if (row != null && row.status == ScheduleStatus.done) {
      await _deleteCompletionHistory(id);
    }
    // 서버는 예정·취소인 상담 일정을 지울 때만 신청을 철회한다(#2758). 상담함은
    // 연결된 일정이 없어진 신청을 철회로 읽으므로, 이미 치른(완료·노쇼) 상담을
    // 지울 때는 연결을 먼저 떼어 신청을 수락된 채로 둔다.
    if (row != null &&
        row.type == SessionType.consultation &&
        (row.status == ScheduleStatus.done ||
            row.status == ScheduleStatus.noShow)) {
      final ScheduleConsultation? removed = demoScheduleConsultations.remove(
        demoConsultationKey(
          clientId: row.clientId,
          date: row.date,
          time: row.time,
        ),
      );
      if (removed != null) await writeDemoScheduleConsultations(_db);
    }
  }

  /// Marks an 예정 session 완료 (with the trainer's [note]) and, when the
  /// client exists, logs it to their 운동기록 history — closing the
  /// 예약 → 수업 → 기록 loop.
  ///
  /// Idempotent: the read, the status-guarded update and the history
  /// insert all run inside ONE transaction, and history is written only
  /// when this call is the one that flipped 예정 → 완료. Two concurrent
  /// completions would otherwise both observe 예정 and insert duplicate
  /// history rows (review PR 237).
  ///
  /// A session dated in the FUTURE can't be completed — it hasn't
  /// happened yet. The UI hides the 완료 action for future days, and this
  /// guard rejects it even if reached another way (review PR 245).
  /// 데모의 **아직 보내지 않은** 개인운동. (#2224)
  ///
  /// 두 조건을 실제와 같게 둔다.
  /// * **프로그램이 있는 일정에만** 붙는다 — 개인운동은 프로그램 만들기에서
  ///   프로그램과 함께 정해져 그 일정에 붙는다(#2223). 달력에서 바로 잡아
  ///   프로그램이 없는 PT 는 붙은 것도 없다.
  /// * **완료된 PT 는 비어 있다** — 완료하는 순간 회원에게 나가 `approved` 로
  ///   옮겨 가므로 미전송으로 남지 않는다. 남는 것은 취소·노쇼처럼 **완료가
  ///   일어나지 않은** PT 뿐이다.
  ///
  /// 보내거나 보내지 않기로 한 일정·고친 개인운동은 [DemoRoutineStore] 에
  /// 남는다(#2668) — 새로고침해도 그대로다.
  ///
  /// 서버와 같은 규칙으로 가른다: 프로그램이 붙어 있어야 하고, 보내지 않기로
  /// 한 것은 빠지며, **이미 보낸 것은 `sent` 로 남는다**. 개인운동은 PT
  /// 프로그램과 함께 나가므로 `programSent` 가 곧 개인운동을 보냈다는 뜻이다
  /// — 완료만으로는 아직 보낸 것이 아니다(#2224).
  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async {
    final SessionRoutineState? state = await _routineStore.readSession(id);
    if (state?.dismissed ?? false) return const <SessionRoutine>[];
    final row = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    // `jsonEncode(<Object?>[])` 는 `[]` 라 **빈 문자열이 아니다** — 문자열이
    // 비었는지 보면 프로그램이 없는 일정에도 개인운동이 딸려 나온다.
    if (row == null || _decodedProgramIsEmpty(row.programJson)) {
      return const <SessionRoutine>[];
    }
    final bool sent = (state?.sent ?? false) || row.programSent;
    return <SessionRoutine>[
      for (final RoutineExercise e in await _sessionRoutines(row, state))
        SessionRoutine(exercise: e, sent: sent),
    ];
  }

  /// 이 회원의 **끝난** PT 를 돌며 아직 보내지 않은 개인운동을 모은다. 실
  /// API 는 서버가 한 번에 준다.
  ///
  /// 서버와 같은 규칙 — 예정인 PT 에 붙은 것은 미전송이 아니다. 그것은 그 PT 를
  /// 완료할 때 함께 나가고, 지금 보내려 하면 거절당한다(#2224).
  @override
  Future<List<UnsentRoutine>> fetchUnsentRoutinesFor(String clientId) async {
    final rows =
        await (_db.select(_db.trainerScheduleEntries)..where(
              (t) =>
                  t.clientId.equals(clientId) &
                  t.status.equals(ScheduleStatus.upcoming).not(),
            ))
            .get();
    final out = <UnsentRoutine>[];
    for (final row in rows) {
      for (final r in await fetchScheduledRoutines(row.id)) {
        if (!r.sent) {
          out.add(
            UnsentRoutine(
              exercise: r.exercise,
              scheduleId: row.id,
              scheduleDate: row.date,
            ),
          );
        }
      }
    }
    return out;
  }

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    final row = await _row(id);
    final SessionRoutineState? state = await _routineStore.readSession(id);
    // 서버와 같은 규칙 — 손댄 줄은 트레이너 것이 된다(#2223, #2224).
    final before = row == null
        ? state?.items ?? _demoPersonalRoutines
        : await _sessionRoutines(row, state);
    await _routineStore.writeSession(
      id,
      (state ?? const SessionRoutineState()).copyWith(
        items: List<RoutineExercise>.unmodifiable(<RoutineExercise>[
          for (var i = 0; i < items.length; i++)
            if (i < before.length && samePersonalRoutine(before[i], items[i]))
              items[i]
            else
              items[i].copyWith(source: 'trainer'),
        ]),
      ),
    );
    // 코칭 탭에서 짠 개인운동을 이 PT 에 붙인 것이면 그 개인운동을 채운 AI
    // 제안은 검토한 것으로 남긴다(#2747) — 실서버가 같은 요청에서 닫는다.
    await _routineStore.addReviewedSuggestions(suggestionIdsOf(items));
  }

  /// 마무리된 PT 의 개인운동을 보낸다. 취소·노쇼 PT 뒤에 보낸 것은 그 종류로
  /// 전송 이력에 남는다(#2668).
  @override
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  }) async {
    final SessionRoutineState? state = await _routineStore.readSession(id);
    if (state?.sent ?? false) return; // 이미 보냈다 — 멱등.
    if (items != null) await updateScheduledRoutines(id, items);
    final SessionRoutineState? edited = items == null
        ? state
        : await _routineStore.readSession(id);
    await _routineStore.writeSession(
      id,
      (edited ?? const SessionRoutineState()).copyWith(sent: true),
    );
    final row = await _row(id);
    if (row == null) return;
    final List<RoutineExercise> routines = await _sessionRoutines(row, edited);
    await _recordDelivery(
      row,
      row.status == ScheduleStatus.cancelled ||
              row.status == ScheduleStatus.noShow
          ? DeliveryKinds.cancelledRoutineOnly
          : DeliveryKinds.routineOnly,
      routines,
    );
  }

  @override
  Future<void> dismissScheduledRoutines(String id) async {
    final SessionRoutineState? state = await _routineStore.readSession(id);
    await _routineStore.writeSession(
      id,
      (state ?? const SessionRoutineState()).copyWith(dismissed: true),
    );
  }

  Future<TrainerScheduleRow?> _row(String id) => (_db.select(
    _db.trainerScheduleEntries,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  @override
  Future<void> completeSession(String id, {String note = ''}) async {
    final table = _db.trainerScheduleEntries;
    final DateTime now = nowKst();

    await _db.transaction(() async {
      final session = await (_db.select(
        table,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (session == null || session.status != ScheduleStatus.upcoming) return;
      // 시작 시각 전이면 완료하지 않는다(#2760) — 날짜만 보던 때에는 오늘
      // 저녁 PT 를 오전에 완료해 하지 않은 운동이 회원 기록에 미리 남았다.
      // 서버는 400 으로 거절한다.
      if (!hasStartedAt(session.date, session.time, now)) return;

      // Conditional update: `changed` is 0 when a concurrent call already
      // completed this session, in which case we must not log again.
      final changed =
          await (_db.update(table)..where(
                (t) =>
                    t.id.equals(id) & t.status.equals(ScheduleStatus.upcoming),
              ))
              .write(
                TrainerScheduleEntriesCompanion(
                  status: const Value(ScheduleStatus.done),
                  // An empty memo must not wipe an existing note.
                  note: note.isEmpty ? const Value.absent() : Value(note),
                ),
              );
      if (changed != 1) return;

      // 기록을 남길 고객도 id 로 찾는다. v3 이전 행만 이름으로 폴백한다.
      final clientId = session.clientId;
      final client =
          await (_db.select(_db.trainerClients)
                ..where(
                  (t) => clientId != null
                      ? t.id.equals(clientId)
                      : t.name.lower().trim().equals(
                          session.clientName.trim().toLowerCase(),
                        ),
                )
                ..limit(1))
              .getSingleOrNull();

      // 상담 등 미등록 고객은 기록 없이 완료만 처리한다.
      if (client == null) return;
      // Label with the SESSION's calendar day — completing a session
      // browsed on another date must not claim '오늘'.
      final day = DateTime.tryParse(session.date) ?? now;
      await _db
          .into(_db.clientRoutineHistory)
          .insert(
            ClientRoutineHistoryCompanion.insert(
              // Include the session id: on web (JS Date) microseconds have
              // only ms resolution, so two same-ms completions would
              // otherwise collide on this PK (review PR 237).
              id: 'hist-$id-${now.microsecondsSinceEpoch}',
              clientId: client.id,
              // 화면은 이 문자열이 아니라 아래 날짜(`completedAt`)로 `9/27
              // (오늘)` 을 화면 언어에 맞춰 그린다(#2300). 칸이 필수라 언어가
              // 없는 날짜만 남긴다.
              dateLabel: '${day.month}/${day.day}',
              // 라벨과 같은 날을 견줄 수 있는 형태로도 남긴다 — 고객 상세의
              // 날짜별 기록이 이 값으로 이력을 그날에 붙인다(#1025, #1114).
              completedAt: Value(day),
              // 서버가 저장하는 이름과 같다. 화면은 이 이름에서 종류 코드를
              // 되짚어 화면 언어로 그린다(`routineKindLabel`).
              label: 'PT 세션 · 트레이너 지도',
              completionRate: 100,
              exercisesJson: _historyExercisesJson(session.programJson),
              trainerNote: Value(note),
              // Seed rows use ascending sortOrder from 0; a negative,
              // decreasing key keeps runtime completions newest-first.
              sortOrder: Value(-now.millisecondsSinceEpoch),
            ),
          );
    });
  }

  /// 예정 → 취소. 상태만이 아니라 **언제·누가·왜** 를 함께 남긴다(#906).
  ///
  /// 데모도 실서버와 같은 것을 저장하는 이유는, 데모가 이 기능을 실제로 눌러 보는
  /// 자리이기 때문이다 — 취소한 쪽을 고르고도 카드에 그 사실이 남지 않으면 취소가
  /// 삭제와 어떻게 다른지가 화면에서 전달되지 않는다.
  ///
  /// 상태 규칙도 실서버와 같다 — 예정인 세션만 전이하고, 이미 마무리된 세션은
  /// 조용히 아무것도 하지 않는다(화면은 그 동작을 내놓지 않는다).
  @override
  Future<void> cancelSession(
    String id, {
    required String source,
    String reason = '',
  }) => _finishSession(
    id,
    TrainerScheduleEntriesCompanion(
      status: const Value(ScheduleStatus.cancelled),
      cancelledAt: Value(nowKst()),
      cancellationSource: Value(source),
      cancellationReason: Value(reason),
    ),
  );

  /// 예정 → 노쇼. 취소와 달리 주체가 없다 — 약속은 그대로였고 회원이 오지 않았다.
  ///
  /// 시작 시각 전에는 아무것도 하지 않는다(#2760) — 아직 오지 않은 약속에 불참을
  /// 적을 수 없다. 서버는 400 으로 거절하고, 화면은 그 전에 노쇼를 내놓지 않는다.
  @override
  Future<void> markNoShow(String id) async {
    final row = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || !hasStartedAt(row.date, row.time, nowKst())) return;
    await _finishSession(
      id,
      TrainerScheduleEntriesCompanion(
        status: const Value(ScheduleStatus.noShow),
        noShowAt: Value(nowKst()),
      ),
    );
  }

  Future<void> _finishSession(
    String id,
    TrainerScheduleEntriesCompanion values,
  ) async {
    final table = _db.trainerScheduleEntries;
    await (_db.update(table)..where(
          (t) => t.id.equals(id) & t.status.equals(ScheduleStatus.upcoming),
        ))
        .write(values);
  }

  /// 같은 시도(멱등키 [clientRequestId])가 만든 회차 id 의 머리. 실서버의
  /// `series_id`(키에서 만든 결정론적 값) 자리다 — 데모 표에는 그 칸이 없어
  /// id 에 싣는다. 뒤에 회차 순번이 붙는다(#3102).
  static String _seriesIdPrefix(String clientRequestId) =>
      'sched-s.$clientRequestId.';

  /// 키 없이 만드는 회차의 id — 실서버와 같은 `sched-` + 무작위 12자리다.
  /// 날짜·시각에서 만들면 같은 자리의 취소·노쇼·옮긴 행과 id 가 겹쳐 저장이
  /// 기본키 충돌로 실패했다(#3102).
  static String _randomSessionId() {
    final Random rng = Random.secure();
    final StringBuffer buffer = StringBuffer('sched-');
    for (int i = 0; i < 12; i++) {
      buffer.write(rng.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// [clientRequestId] 시도가 이미 만든 회차(날짜·시각 순).
  Future<List<TrainerScheduleRow>> _seriesRows(String clientRequestId) async {
    final prefix = _seriesIdPrefix(clientRequestId);
    final rows = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.like('sched-s.%'))).get();
    // LIKE 의 와일드카드가 키에 섞여도 다른 시도의 회차를 줍지 않게 머리와
    // 순번을 직접 확인한다.
    return <TrainerScheduleRow>[
      for (final row in rows)
        if (row.id.startsWith(prefix) &&
            int.tryParse(row.id.substring(prefix.length)) != null)
          row,
    ]..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.time.compareTo(b.time);
    });
  }

  @override
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    int durationMinutes = 0,
    String? clientRequestId,
  }) async {
    final dates = seriesOccurrences(start, rule);
    final wanted = dates.map(ymd).toSet();
    // 같은 시도가 이미 만든 회차는 충돌이 아니다 — 실서버와 같은 규칙(#3102).
    final Set<String> ownIds = clientRequestId == null
        ? const <String>{}
        : <String>{
            for (final row in await _seriesRows(clientRequestId)) row.id,
          };
    // 취소·노쇼 자리는 겹침이 아니다 — 그 시간은 비어 있다(#871).
    final rows =
        await (_db.select(_db.trainerScheduleEntries)..where(
              (t) =>
                  t.date.isIn(wanted) &
                  t.status.isIn(<String>[
                    ScheduleStatus.upcoming,
                    ScheduleStatus.done,
                  ]),
            ))
            .get();
    // 시작 시각이 같을 때만이 아니라 시간 구간이 겹치면 겹침이다(#2284).
    return (
      dates: dates,
      conflicts: <ScheduleSession>[
        for (final row in rows)
          if (!ownIds.contains(row.id) &&
              timeRangesOverlap(
                row.time,
                row.durationMinutes,
                time,
                durationMinutes,
              ))
            _toEntity(row),
      ],
      alreadyCreated: ownIds.isNotEmpty,
    );
  }

  @override
  Future<List<ScheduleSession>> addRecurringSessions({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
    required String clientName,
    String? clientId,
    required String type,
    required int durationMinutes,
    String note = '',
    String? clientRequestId,
  }) async {
    // 같은 키의 재시도는 새로 만들지 않고 그 시도가 만든 회차를 돌려준다 —
    // 실서버 `create_recurring_sessions` 의 멱등 규칙과 같다(#3102).
    if (clientRequestId != null) {
      final existing = await _seriesRows(clientRequestId);
      if (existing.isNotEmpty) {
        return <ScheduleSession>[for (final row in existing) _toEntity(row)];
      }
    }
    final preview = await previewRecurring(
      start: start,
      time: time,
      rule: rule,
      durationMinutes: durationMinutes,
    );
    if (preview.conflicts.isNotEmpty) {
      throw ScheduleSeriesConflictError(preview.conflicts);
    }
    if (preview.dates.isEmpty) return const <ScheduleSession>[];
    // 한 트랜잭션에 넣는다 — 중간에 실패해 몇 주만 남는 상태가 실서버의
    // '전부 아니면 전무' 와 어긋나면, 데모에서 확인한 동작이 거짓이 된다.
    final created = <ScheduleSession>[];
    await _db.transaction(() async {
      for (final (index, day) in preview.dates.indexed) {
        final companion = TrainerScheduleEntriesCompanion.insert(
          id: clientRequestId == null
              ? _randomSessionId()
              : '${_seriesIdPrefix(clientRequestId)}$index',
          date: ymd(day),
          time: time,
          clientId: Value(clientId),
          clientName: Value(clientName),
          type: Value(type),
          durationMinutes: Value(durationMinutes),
          status: ScheduleStatus.upcoming,
          note: Value(note),
        );
        await _db.into(_db.trainerScheduleEntries).insert(companion);
        created.add(
          ScheduleSession(
            id: companion.id.value,
            date: companion.date.value,
            time: time,
            clientId: clientId,
            clientName: clientName,
            type: type,
            durationMinutes: durationMinutes,
            status: ScheduleStatus.upcoming,
            note: note,
            program: const <ProgramItem>[],
          ),
        );
      }
    });
    return created;
  }

  ScheduleSession _toEntity(TrainerScheduleRow row) {
    final program = (jsonDecode(row.programJson) as List<Object?>)
        .map((e) => e! as Map<String, Object?>)
        .map(programItemFromJson)
        .toList();
    return ScheduleSession(
      consultation: row.type == SessionType.consultation
          ? demoScheduleConsultations[demoConsultationKey(
              clientId: row.clientId,
              date: row.date,
              time: row.time,
            )]
          : null,
      id: row.id,
      date: row.date,
      time: row.time,
      clientId: row.clientId,
      clientName: row.clientName,
      type: row.type,
      durationMinutes: row.durationMinutes,
      status: row.status,
      note: row.note,
      program: program,
      programSent: row.programSent,
      cancelledAt: row.cancelledAt,
      cancellationSource: row.cancellationSource,
      cancellationReason: row.cancellationReason,
      noShowAt: row.noShowAt,
      isReservation: isDemoReservationScheduleId(row.id),
    );
  }
}

/// 데모에서 회원 예약으로 생긴 일정 행의 id 앞머리(#2756).
///
/// 서버는 예약 표(`trainer_reservations.schedule_id`)로 예약 일정을 알아보지만
/// 데모 저장소(drift)의 일정 표에는 그 칸이 없다. 그래서 예약이 만든 일정은
/// id 를 이 앞머리로 짓고, 그것으로 같은 잠금을 건다.
const String demoReservationScheduleIdPrefix = 'resv-';

/// [id] 가 데모의 회원 예약 일정인가. 시드 행(`seed-` 앞머리)도 본다.
bool isDemoReservationScheduleId(String id) =>
    id.startsWith(demoReservationScheduleIdPrefix) ||
    id.startsWith('seed-$demoReservationScheduleIdPrefix');

// 데모 저장소가 서버와 같은 사유로 거절할 때 쓰는 문구 — 서버 `trainer.schedule`
// 의 ScheduleConflict 문구와 같다. 화면은 한국어일 때 이 사유를 그대로 보인다.
const String demoFinishedEditRejected =
    '완료·취소·노쇼로 마무리된 PT는 피드백·프로그램만 수정할 수 있어요.';
const String demoSentProgramEditRejected = '이미 보낸 프로그램은 수정할 수 없어요.';
const String demoReservationEditRejected =
    '예약으로 생성된 일정은 일반 일정 화면에서 수정할 수 없어요.';
const String demoReservationDeleteRejected =
    '예약으로 생성된 일정은 일반 일정 화면에서 삭제할 수 없어요.';
const String demoReservationReopenRejected =
    '예약으로 생성된 일정은 일반 일정 화면에서 되돌릴 수 없어요.';

/// 데모 상담 일정의 `상담 요청 내용`(#2584).
///
/// 서버는 일정에 상담 요청을 잇는 칸(`consultation_id`)을 두지만, 데모 저장소
/// (drift)는 그 칸 없이 일정만 저장한다. 그래서 같은 회원·날짜·시각의 상담
/// 일정에 붙여 읽는다. 일정 행을 읽는 자리([DriftScheduleRepository])가 동기라
/// 이 표를 메모리에 두되, 새로고침해도 남도록 키-값 저장소
/// ([demoScheduleConsultationsKey])에 함께 적는다(#2669) — 앱이 뜰 때
/// [loadDemoScheduleConsultations] 가 다시 읽어 온다.
final Map<String, ScheduleConsultation> demoScheduleConsultations =
    <String, ScheduleConsultation>{};

/// [demoScheduleConsultations] 의 키.
String demoConsultationKey({
  required String? clientId,
  required String date,
  required String time,
}) => '${clientId ?? ''}|$date|$time';

/// [demoScheduleConsultations] 를 적어 두는 키-값 저장소의 키.
const String demoScheduleConsultationsKey = 'demo_schedule_consultations';

/// 저장해 둔 상담 연결을 [demoScheduleConsultations] 로 읽어 온다. 깨진 값은
/// 버린다 — 상담 내용 한 블록 때문에 일정 화면이 멈추면 안 된다.
Future<void> loadDemoScheduleConsultations(AppDatabase db) async {
  demoScheduleConsultations.clear();
  final String? saved = await db.readValue(demoScheduleConsultationsKey);
  if (saved == null) return;
  final Object? decoded;
  try {
    decoded = jsonDecode(saved);
  } on FormatException {
    return;
  }
  if (decoded is! Map<String, Object?>) return;
  for (final MapEntry<String, Object?> e in decoded.entries) {
    final Object? v = e.value;
    if (v is! Map<String, Object?>) continue;
    final Object? id = v['id'];
    final Object? goal = v['goal_code'];
    if (id is! String || goal is! String) continue;
    final Object? message = v['message'];
    demoScheduleConsultations[e.key] = ScheduleConsultation(
      id: id,
      goalCode: goal,
      message: message is String ? message : null,
    );
  }
}

/// 상담 연결 하나를 메모리와 저장소에 함께 적는다. [db] 가 없으면(테스트의
/// 메모리 저장소) 메모리에만 둔다.
Future<void> saveDemoScheduleConsultation(
  AppDatabase? db,
  String key,
  ScheduleConsultation consultation,
) async {
  demoScheduleConsultations[key] = consultation;
  if (db != null) await writeDemoScheduleConsultations(db);
}

/// [demoScheduleConsultations] 전체를 저장소에 적는다.
Future<void> writeDemoScheduleConsultations(AppDatabase db) => db.putValue(
  demoScheduleConsultationsKey,
  jsonEncode(<String, Object?>{
    for (final MapEntry<String, ScheduleConsultation> e
        in demoScheduleConsultations.entries)
      e.key: <String, Object?>{
        'id': e.value.id,
        'goal_code': e.value.goalCode,
        'message': e.value.message,
      },
  }),
);

/// 완료한 PT 의 프로그램 한 항목 → 이력의 운동 한 종목. (#2300)
///
/// 서버 `_program_item_label` 과 같은 규칙을 **값으로** 남긴다(#1276) — 근력은
/// 세트·횟수(버티는 운동은 초, #1969)·중량, 나머지는 시간이다. 예전에는
/// `스쿼트 3세트 12회 40kg` 문장으로 저장해 영어 화면에도 `세트`·`회` 가 나왔다.
ClientExerciseItem programHistoryItem(ProgramItem raw) {
  final ProgramItem item = raw.byType;
  final String type = switch (item.type) {
    '근력' => 'strength',
    '유산소' => 'cardio',
    '스트레칭' => 'stretching',
    _ => 'other',
  };
  if (type != 'strength') {
    return ClientExerciseItem(
      name: item.name,
      type: type,
      minutes: item.duration ?? 0,
    );
  }
  final int? holdSeconds = item.holdSeconds;
  final int? reps = item.reps;
  final bool holds = holdSeconds != null && holdSeconds > 0;
  return ClientExerciseItem(
    name: item.name,
    type: type,
    sets: item.sets,
    // 버티는 운동은 회가 아니라 초로 읽는다. 둘은 배타다.
    holdSeconds: holds ? holdSeconds : null,
    reps: !holds && reps != null && reps > 0 ? reps : null,
    // 값은 그대로 남긴다 — 맨몸(0)의 중량을 적지 않는 것은 화면의 일이다(#2533).
    weight: item.weight,
  );
}

/// Provides the [ScheduleRepository]: the real Dio-backed source against
/// the FastAPI backend, or the local drift source for demo /
/// `USE_MOCK_API=true`.
final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return DriftScheduleRepository(ref.watch(appDatabaseProvider));
  }
  final repo = DioScheduleRepository(ref.watch(dioProvider));
  ref.onDispose(repo.dispose);
  return repo;
}, name: 'scheduleRepository');

/// Streams today's timeline (대시보드 `오늘 일정`, 오늘 수업 수).
///
/// 날짜는 KST 날짜 시계([kstTodayProvider])에서 읽는다. 예전에는 구독할 때의
/// 날짜를 고정해, 대시보드를 켠 채 자정을 넘기면 어제 일정이 남았다(#2865).
/// 날짜가 바뀌면 이 provider 가 다시 만들어지고 새 날짜를 구독한다. 실서버
/// 저장소의 날짜 조회는 회원 앱에서 생긴 예약·취소를 짧은 주기로 다시 읽는다.
final todayScheduleProvider = StreamProvider.autoDispose<List<ScheduleSession>>(
  (ref) {
    final String today = ref.watch(kstTodayProvider);
    return ref.watch(scheduleRepositoryProvider).watchDate(today);
  },
);

/// Streams the timeline for one calendar date (`YYYY-MM-DD`).
final scheduleForDateProvider = StreamProvider.autoDispose
    .family<List<ScheduleSession>, String>((ref, date) {
      return ref.watch(scheduleRepositoryProvider).watchDate(date);
    });

/// Streams the set of dates that have booked sessions (strip dots).
final bookedDatesProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  return ref.watch(scheduleRepositoryProvider).watchBookedDates();
});

/// An inclusive `YYYY-MM-DD` date range, used to key the week query.
typedef ScheduleRange = ({String from, String to});

/// Streams every slot in a date range (week calendar).
final scheduleRangeProvider = StreamProvider.autoDispose
    .family<List<ScheduleSession>, ScheduleRange>((ref, range) {
      return ref
          .watch(scheduleRepositoryProvider)
          .watchRange(range.from, range.to);
    });

/// Streams one client's booked sessions, newest first.
final clientSessionsProvider = StreamProvider.autoDispose
    .family<List<ScheduleSession>, ScheduleClientKey>((ref, client) {
      return ref.watch(scheduleRepositoryProvider).watchClientSessions(client);
    });
