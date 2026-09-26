import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
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
  Future<void> updateSession(
    String id, {
    String? date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    required String note,
  });

  /// 완료 세션을 [date](미래)의 예정으로 되돌린다. (#1396)
  ///
  /// 일정 수정에서 완료된 회차의 날짜를 앞으로 옮길 때만 쓴다 — 완료가 남긴
  /// 파생 기록(트레이너 이력·회원 운동기록)을 함께 지운다. 예정 세션이나
  /// 과거·오늘 날짜에는 쓸 수 없다(구현이 거부한다).
  Future<void> reopenSession(String id, {required String date});

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
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  });

  /// 마무리된 PT 의 개인운동을 보내지 않기로 정리한다. (#2224)
  Future<void> dismissScheduledRoutines(String id);

  /// 저장 전에 보여 줄 회차와 충돌. (#870)
  ///
  /// 반복은 한 번에 여러 건을 만든다 — 요일이나 종료일을 잘못 골랐을 때 되돌리는
  /// 비용이 한 건씩 지우는 일이라, 그 전에 보여 주는 편이 싸다.
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
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
/// 데모에서 프로그램과 함께 붙어 있는 개인운동. 실 API 는 서버가 준다.
const List<RoutineExercise> _demoPersonalRoutines = <RoutineExercise>[
  RoutineExercise(name: '저강도 걷기', minutes: 30, type: '유산소', source: 'ai'),
  RoutineExercise(name: '코어 스트레칭', minutes: 10, type: '스트레칭', source: 'ai'),
];

/// 데모에서 개인운동을 이미 보낸 일정.
final Set<String> _sentRoutines = <String>{};

/// 데모에서 개인운동을 보내지 않기로 한 일정 — 목록에서 아예 빠진다.
final Set<String> _dismissedRoutines = <String>{};

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
bool _sameRoutine(RoutineExercise a, RoutineExercise b) =>
    a.name == b.name &&
    a.minutes == b.minutes &&
    a.type == b.type &&
    a.sets == b.sets &&
    a.reps == b.reps &&
    a.holdSeconds == b.holdSeconds &&
    a.weight == b.weight;

/// 데모에서 트레이너가 상세 일정에서 고쳐 둔 개인운동.
final Map<String, List<RoutineExercise>> _editedRoutines =
    <String, List<RoutineExercise>>{};

class DriftScheduleRepository implements ScheduleRepository {
  /// Creates the repository over [_db].
  const DriftScheduleRepository(this._db);

  final AppDatabase _db;

  /// Today's slots in timeline order (including 공백 gaps).
  ///
  /// NOTE: `ymd(nowKst())`는 스트림 구독 시점에 고정된다 — 앱을
  /// 자정 넘겨 켜두면 '오늘'이 갱신되지 않음(예약 카운트와 동일 패턴,
  /// 로컬 mock 데모 범위에선 허용). 실 백엔드 전환 시 서버가 판단한다.
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
  /// 폴백한다. 폴백은 `lower(trim(name))` — `addClient` 의 유일성 가드와 같은
  /// 정규화라, 저장/조회 기준이 어긋나지 않는다.
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

  /// Books a new session on [date]'s timeline (status 예정). The
  /// non-`seed-` id survives the daily re-seed.
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

  /// Edits a booked session's date/time/client/type/duration.
  @override
  Future<void> updateSession(
    String id, {
    String? date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    required String note,
  }) async {
    await (_db.update(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).write(
      TrainerScheduleEntriesCompanion(
        date: date == null ? const Value.absent() : Value(date),
        clientId: Value(clientId),
        clientName: Value(clientName),
        time: Value(time),
        type: Value(type),
        durationMinutes: Value(durationMinutes),
        note: Value(note),
      ),
    );
  }

  /// 완료 세션을 [date](미래)의 예정으로 되돌린다(#1396). 데모 DB에는 완료가
  /// 남긴 파생 기록이 세션 id로 되짚어지지 않는 키를 쓰므로(`hist-$id-시각`),
  /// `deleteSession` 과 같은 한계로 그 이력까지 지우지는 않는다 — 로컬
  /// 데모에서만 남는 흔적이라 실 서버(`DioScheduleRepository`)와 달리 여기는
  /// 상태·날짜만 되돌린다.
  @override
  Future<void> reopenSession(String id, {required String date}) async {
    final table = _db.trainerScheduleEntries;
    final today = ymd(nowKst());
    if (date.compareTo(today) <= 0) {
      throw StateError('reopen requires a future date: $date');
    }
    await _db.transaction(() async {
      final session = await (_db.select(
        table,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (session == null || session.status != ScheduleStatus.done) {
        throw StateError('session not completed: $id');
      }
      await (_db.update(table)..where((t) => t.id.equals(id))).write(
        TrainerScheduleEntriesCompanion(
          date: Value(date),
          status: const Value(ScheduleStatus.upcoming),
        ),
      );
    });
  }

  /// Replaces the exercise program and trainer memo without changing the
  /// booking itself (client, type, time, or duration).
  @override
  Future<void> updateProgram(
    String id, {
    required List<ProgramItem> program,
    required String note,
  }) async {
    await (_db.update(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).write(
      TrainerScheduleEntriesCompanion(
        programJson: Value(jsonEncode(programToJson(program))),
        note: Value(note),
      ),
    );
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

      final encodedProgram = jsonEncode(programToJson(program));
      if (existing != null) {
        await (_db.update(
          table,
        )..where((t) => t.id.equals(existing!.id))).write(
          TrainerScheduleEntriesCompanion(programJson: Value(encodedProgram)),
        );
        // 서버와 같은 규칙 — 다시 붙이면 개인운동도 **새것으로 갈린다**(#2224).
        // 쌓아 두면 두 번 짠 트레이너가 두 배를 보내게 된다.
        _rememberPersonalRoutines(existing.id, personalRoutines);
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
      // API 는 서버가 들고 있고, 데모에는 둘 표가 없어 메모리로 기억한다.
      // 기억하지 않으면 스케줄 카드가 짠 것 대신 늘 같은 데모 두 개를 보여
      // 줘, 데모로는 "내가 짠 것이 그대로 가는가" 를 확인할 수 없다.
      _rememberPersonalRoutines(newId, personalRoutines);
      return false;
    });
  }

  /// 이 일정에 붙은 개인운동을 데모 기억에 남긴다. 비었으면 기억도 지운다 —
  /// 개인운동 없이 다시 붙였는데 옛것이 남아 있으면 안 된다.
  void _rememberPersonalRoutines(
    String sessionId,
    List<RoutineExercise> routines,
  ) {
    _sentRoutines.remove(sessionId);
    _dismissedRoutines.remove(sessionId);
    if (routines.isEmpty) {
      _editedRoutines[sessionId] = const <RoutineExercise>[];
      return;
    }
    _editedRoutines[sessionId] = List<RoutineExercise>.unmodifiable(routines);
  }

  /// Removes a session from the timeline.
  @override
  /// 데모에는 받을 회원 백엔드가 없다. 전송은 이 표시로 끝나지만, 화면이
  /// '전송됨' 을 사실대로 말하고 같은 세션을 두 번 보내지 않으려면 남아야 한다.
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
  }

  @override
  Future<void> deleteSession(String id) async {
    await (_db.delete(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).go();
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
  /// 보내거나 보내지 않기로 한 일정은 메모리 집합에 남는다 — 데모에는 붙여 둘
  /// 표가 없다.
  ///
  /// 서버와 같은 규칙으로 가른다: 프로그램이 붙어 있어야 하고, 보내지 않기로
  /// 한 것은 빠지며, **이미 보낸 것은 `sent` 로 남는다**. 개인운동은 PT
  /// 프로그램과 함께 나가므로 `programSent` 가 곧 개인운동을 보냈다는 뜻이다
  /// — 완료만으로는 아직 보낸 것이 아니다(#2224).
  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async {
    if (_dismissedRoutines.contains(id)) return const <SessionRoutine>[];
    final row = await (_db.select(
      _db.trainerScheduleEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    // `jsonEncode(<Object?>[])` 는 `[]` 라 **빈 문자열이 아니다** — 문자열이
    // 비었는지 보면 프로그램이 없는 일정에도 개인운동이 딸려 나온다.
    if (row == null || _decodedProgramIsEmpty(row.programJson)) {
      return const <SessionRoutine>[];
    }
    final bool sent = _sentRoutines.contains(id) || row.programSent;
    return <SessionRoutine>[
      for (final RoutineExercise e
          in _editedRoutines[id] ?? _demoPersonalRoutines)
        SessionRoutine(exercise: e, sent: sent),
    ];
  }

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    // 서버와 같은 규칙 — 손댄 줄은 트레이너 것이 된다(#2223, #2224).
    final before = _editedRoutines[id] ?? _demoPersonalRoutines;
    _editedRoutines[id] = List<RoutineExercise>.unmodifiable(<RoutineExercise>[
      for (var i = 0; i < items.length; i++)
        if (i < before.length && _sameRoutine(before[i], items[i]))
          items[i]
        else
          items[i].copyWith(source: 'trainer'),
    ]);
  }

  @override
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  }) async {
    _sentRoutines.add(id);
  }

  @override
  Future<void> dismissScheduledRoutines(String id) async {
    _dismissedRoutines.add(id);
  }

  @override
  Future<void> completeSession(String id, {String note = ''}) async {
    final table = _db.trainerScheduleEntries;
    final today = ymd(nowKst());

    await _db.transaction(() async {
      final session = await (_db.select(
        table,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (session == null || session.status != ScheduleStatus.upcoming) return;
      // `YYYY-MM-DD` sorts lexicographically, so a plain compare works.
      if (session.date.compareTo(today) > 0) return;

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
      final program = (jsonDecode(session.programJson) as List<Object?>)
          .map((e) => programItemFromJson(e! as Map<String, Object?>))
          .toList();
      final now = nowKst();
      // Label with the SESSION's calendar day — completing a session
      // browsed on another date must not claim '오늘'.
      final day = DateTime.tryParse(session.date) ?? now;
      final isToday = session.date == ymd(now);
      await _db
          .into(_db.clientRoutineHistory)
          .insert(
            ClientRoutineHistoryCompanion.insert(
              // Include the session id: on web (JS Date) microseconds have
              // only ms resolution, so two same-ms completions would
              // otherwise collide on this PK (review PR 237).
              id: 'hist-$id-${now.microsecondsSinceEpoch}',
              clientId: client.id,
              dateLabel: '${day.month}/${day.day}${isToday ? ' (오늘)' : ''}',
              // 라벨과 같은 날을 견줄 수 있는 형태로도 남긴다 — 고객 상세의
              // 날짜별 기록이 이 값으로 이력을 그날에 붙인다(#1025, #1114).
              completedAt: Value(day),
              label: 'PT 세션 · 트레이너 지도',
              completionRate: 100,
              // 근력은 세트·중량으로, 나머지는 시간으로 읽는다 — 서버의
              // `_program_item_label` 과 같은 규칙이다 (#1276).
              exercisesJson: jsonEncode(<String>[
                for (final m in program) _programItemLabel(m),
              ]),
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
  @override
  Future<void> markNoShow(String id) => _finishSession(
    id,
    TrainerScheduleEntriesCompanion(
      status: const Value(ScheduleStatus.noShow),
      noShowAt: Value(nowKst()),
    ),
  );

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

  @override
  Future<RecurrencePreview> previewRecurring({
    required DateTime start,
    required String time,
    required WeeklyRecurrence rule,
  }) async {
    final dates = seriesOccurrences(start, rule);
    final wanted = dates.map(ymd).toSet();
    // 취소·노쇼 자리는 겹침이 아니다 — 그 시간은 비어 있다(#871).
    final rows =
        await (_db.select(_db.trainerScheduleEntries)..where(
              (t) =>
                  t.date.isIn(wanted) &
                  t.time.equals(time) &
                  t.status.isIn(<String>[
                    ScheduleStatus.upcoming,
                    ScheduleStatus.done,
                  ]),
            ))
            .get();
    return (
      dates: dates,
      conflicts: rows.map(_toEntity).toList(growable: false),
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
    final preview = await previewRecurring(
      start: start,
      time: time,
      rule: rule,
    );
    if (preview.conflicts.isNotEmpty) {
      throw ScheduleSeriesConflictError(preview.conflicts);
    }
    if (preview.dates.isEmpty) return const <ScheduleSession>[];
    // 한 트랜잭션에 넣는다 — 중간에 실패해 몇 주만 남는 상태가 실서버의
    // '전부 아니면 전무' 와 어긋나면, 데모에서 확인한 동작이 거짓이 된다.
    final created = <ScheduleSession>[];
    await _db.transaction(() async {
      for (final day in preview.dates) {
        final companion = TrainerScheduleEntriesCompanion.insert(
          id: 'sched-${day.millisecondsSinceEpoch}-${time.hashCode}',
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
    );
  }
}

/// 이력 목록에 적히는 한 줄. 근력은 세트·횟수·중량, 나머지는 시간으로 읽는다.
///
/// 서버 `_program_item_label` 과 같은 규칙이다(#1276) — 유형마다 재는 단위가
/// 달라서, 근력을 "30분"으로 적으면 다음 무게를 정할 근거가 사라지고 유산소를
/// "3세트"로 적으면 뜻이 없다. 횟수도 함께 적는다: 세트·중량만으로는 근력 한
/// 줄이 회원 기록에서 그대로 재현되지 않는다.
String _programItemLabel(ProgramItem raw) {
  final ProgramItem item = raw.byType;
  final List<String> parts = <String>[];
  if (item.type == '근력') {
    if (item.sets != null) parts.add('${item.sets}세트');
    // 버티는 운동은 회가 아니라 초로 읽는다 — `플랭크 3세트 60초`. 둘은
    // 배타라 한 줄에 함께 서지 않는다. (#1969)
    final int? holdSeconds = item.holdSeconds;
    final int? reps = item.reps;
    if (holdSeconds != null && holdSeconds > 0) {
      parts.add('$holdSeconds초');
    } else if (reps != null && reps > 0) {
      parts.add('$reps회');
    }
    // 맨몸 운동은 `0kg` 이다 — 중량 칸을 비울 수 없으므로 적지 않은 값과
    // 0 은 다른 뜻이다. 값이 없는 것은 규칙 이전의 옛 행뿐이다.
    final double? weight = item.weight;
    if (weight != null) {
      parts.add(
        '${weight == weight.roundToDouble() ? weight.round() : weight}kg',
      );
    }
  } else if (item.duration != null) {
    parts.add('${item.duration}분');
  }
  return <String>[item.name, ...parts].join(' ');
}

/// Provides the [ScheduleRepository]: the real Dio-backed source against
/// the FastAPI backend, or the local drift source for demo /
/// `USE_MOCK_API=true`.
final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return DriftScheduleRepository(ref.watch(appDatabaseProvider));
  }
  final repo = DioScheduleRepository(ref.watch(dioProvider));
  ref.onDispose(repo.dispose);
  return repo;
}, name: 'scheduleRepository');

/// Streams today's timeline for the 스케줄 tab.
final todayScheduleProvider = StreamProvider.autoDispose<List<ScheduleSession>>(
  (ref) {
    return ref.watch(scheduleRepositoryProvider).watchToday();
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
