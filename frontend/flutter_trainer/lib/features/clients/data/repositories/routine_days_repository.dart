import 'dart:convert';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_days.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

/// 날짜별 개인운동 이행을 읽는다. (#2508)
///
/// 배정 저장소([TrainerRoutineRepository])와 나눠 둔다 — 그 계약을 구현하는
/// 테스트 대역이 여럿이라, 읽기 하나를 더하려고 모두를 고치지 않는다.
abstract interface class RoutineDaysRepository {
  /// [memberId] 의 [from]~[to] 날짜별 개인운동. [from] 을 비우면 처음 걸린
  /// 날부터, [to] 는 기본 오늘이다.
  Future<RoutineDays> fetch(String memberId, {DateTime? from, DateTime? to});
}

/// `GET /trainer/clients/{id}/routine-days`.
class DioRoutineDaysRepository implements RoutineDaysRepository {
  /// Creates the repository over [_dio].
  DioRoutineDaysRepository(this._dio);

  final Dio _dio;

  @override
  Future<RoutineDays> fetch(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .get<Map<String, Object?>>(
            '/trainer/clients/${Uri.encodeComponent(memberId)}/routine-days',
            queryParameters: <String, Object?>{
              if (from != null) 'from': ymd(from),
              if (to != null) 'to': ymd(to),
            },
          );
      return routineDaysFromJson(res.data ?? const <String, Object?>{});
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

/// 서버 응답 → [RoutineDays]. 모르는 값·깨진 줄은 건너뛴다.
RoutineDays routineDaysFromJson(Map<String, Object?> json) {
  final List<RoutineDayRoutine> routines = <RoutineDayRoutine>[
    for (final Object? raw in json['routines'] as List<Object?>? ?? const [])
      if (raw is Map<String, Object?>)
        if (_date(raw['active_from']) case final DateTime activeFrom)
          RoutineDayRoutine(
            id: (raw['id'] as String?) ?? '',
            name: (raw['name'] as String?) ?? '',
            type: (raw['type'] as String?) ?? '',
            source: (raw['source'] as String?) ?? 'trainer',
            sortOrder: (raw['sort_order'] as num?)?.toInt() ?? 0,
            activeFrom: activeFrom,
            endedOn: _date(raw['ended_on']),
            sentOn: _date(raw['sent_on']) ?? activeFrom,
            personal: raw['personal'] != false,
            minutes: (raw['minutes'] as num?)?.toInt() ?? 0,
            durationSeconds: (raw['duration_seconds'] as num?)?.toInt(),
            sets: (raw['sets'] as num?)?.toInt(),
            reps: (raw['reps'] as num?)?.toInt(),
            holdSeconds: (raw['hold_seconds'] as num?)?.toInt(),
            weight: (raw['weight'] as num?)?.toDouble(),
            effect: (raw['effect'] as String?) ?? '',
          ),
  ];
  return RoutineDays(
    start: _date(json['start']),
    end: _date(json['end']),
    routines: routines,
    days: <RoutineDay>[
      for (final Object? raw in json['days'] as List<Object?>? ?? const [])
        if (raw is Map<String, Object?>)
          if (_date(raw['date']) case final DateTime date)
            RoutineDay(
              date: date,
              items: <RoutineDayItem>[
                for (final Object? item
                    in raw['items'] as List<Object?>? ?? const [])
                  if (item is Map<String, Object?>)
                    RoutineDayItem(
                      routineId: (item['routine_id'] as String?) ?? '',
                      status: RoutineDayStatus.parse(item['status']),
                      sessionId: item['session_id'] as String?,
                    ),
              ],
            ),
    ],
  );
}

DateTime? _date(Object? raw) {
  if (raw is! String) return null;
  final DateTime? d = DateTime.tryParse(raw);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// 데모의 날짜별 개인운동 — 실서버와 같은 규칙을 시드에서 만든다.
///
/// - 배정은 데모 배정 저장소([DemoRoutineStore]) 그대로다. 씨앗 배정은 서버
///   시드처럼 4주 전부터 걸린 기한 없는 배정이고, 데모에서 보낸 `개인운동만`
///   은 시작일부터 7일이다.
/// - 김민수(공유 픽스처)는 그날 한 운동 중 이름이 같은 것을 완료로 잇는다 —
///   백엔드 시드(`_seed_from_fixture`)와 같은 규칙이다. PT 날과 오늘은 잇지
///   않는다.
/// - 다른 회원은 그날 이행률(`ClientDailyMetrics.completion`)만큼 배정 순서대로
///   완료로 둔다. 기록이 하나도 없는 회원은 아직 시작하지 않은 것으로 본다.
class MockRoutineDaysRepository implements RoutineDaysRepository {
  /// Creates the demo repository over [_db].
  MockRoutineDaysRepository(this._db);

  final AppDatabase _db;

  @override
  Future<RoutineDays> fetch(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final DateTime today = _dayOf(nowKst());
    final DateTime end = to == null || to.isAfter(today) ? today : _dayOf(to);
    final DemoRoutineStore store = DemoRoutineStore(_db);
    final List<AssignedRoutine> assigned = await store.assigned(memberId);
    // 새 개인운동에 밀려 내려간 것도 지난 날의 이행으로 읽는다 — 실서버처럼
    // 보낸 기간마다 링이 남는다.
    final List<(AssignedRoutine, DateTime)> retired = await store.readRetired(
      memberId,
    );
    if (assigned.isEmpty && retired.isEmpty) return RoutineDays.empty;
    final List<RoutineDayRoutine> routines = demoRoutineWindows(
      assigned,
      today,
      retired: retired,
    );
    DateTime start = from == null
        ? routines
              .map((RoutineDayRoutine r) => r.activeFrom)
              .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b)
        : _dayOf(from);
    final DateTime earliest = end.subtract(const Duration(days: 370));
    if (start.isBefore(earliest)) start = earliest;
    if (end.isBefore(start)) return RoutineDays.empty;

    final _DoneRule rule;
    if (memberId == demoFixtureMemberId) {
      rule = _FixtureDone(DemoFixture.load().daysFor(nowKst()));
    } else {
      final Map<String, int> completion = <String, int>{
        for (final ClientDailyMetricRow row in await (_db.select(
          _db.clientDailyMetrics,
        )..where((t) => t.clientId.equals(memberId))).get())
          row.date: row.completion,
      };
      if (!completion.values.any((int c) => c > 0)) return RoutineDays.empty;
      rule = _RateDone(memberId, completion);
    }

    // 오늘은 회원이 체크한 만큼이다 — 실서버에서 체크는 그날 운동 행(출처
    // `assigned_routine`)을 남긴다. 데모는 오늘 운동 행 중 걸린 개인운동과
    // 이름이 같은 것을 그 체크로 읽는다([demoTodayAssignedRoutines] 와 같은 규칙).
    final Set<String> doneToday = await _todayRowNames(memberId);
    final List<RoutineDay> days = <RoutineDay>[];
    for (
      DateTime day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final List<RoutineDayRoutine> on = <RoutineDayRoutine>[
        for (final RoutineDayRoutine r in routines)
          if (r.activeOn(day)) r,
      ];
      days.add(
        RoutineDay(
          date: day,
          items: day == today
              ? _todayItems(on, doneToday, day)
              : rule.items(on, day, today),
        ),
      );
    }
    return RoutineDays(
      start: start,
      end: end,
      routines: <RoutineDayRoutine>[
        for (final RoutineDayRoutine r in routines)
          if (days.any((RoutineDay d) => d.itemFor(r.id) != null)) r,
      ],
      days: days,
    );
  }
}

/// 데모 오늘 운동 행의 이름들.
extension on MockRoutineDaysRepository {
  Future<Set<String>> _todayRowNames(String memberId) =>
      demoRowNamesOn(_db, memberId, nowKst());
}

/// 오늘 칸 — 운동 행 하나가 개인운동 하나의 체크다. 같은 이름의 개인운동이
/// 둘 걸려 있으면 배정 순서대로 하나만 한 것이 된다.
List<RoutineDayItem> _todayItems(
  List<RoutineDayRoutine> on,
  Set<String> rowNames,
  DateTime day,
) {
  final List<String> rows = <String>[...rowNames];
  final List<RoutineDayRoutine> ordered = <RoutineDayRoutine>[...on]
    ..sort(
      (RoutineDayRoutine a, RoutineDayRoutine b) =>
          a.sortOrder.compareTo(b.sortOrder),
    );
  final Set<String> done = <String>{};
  for (final RoutineDayRoutine r in ordered) {
    final int at = rows.indexWhere(
      (String row) => demoRowIsRoutine(row, r.name),
    );
    if (at < 0) continue;
    rows.removeAt(at);
    done.add(r.id);
  }
  return <RoutineDayItem>[
    for (final RoutineDayRoutine r in on)
      RoutineDayItem(
        routineId: r.id,
        status: done.contains(r.id)
            ? RoutineDayStatus.done
            : RoutineDayStatus.pending,
        sessionId: done.contains(r.id)
            ? 'demo-session-${r.id}-${ymd(day)}'
            : null,
      ),
  ];
}

/// 데모 운동 행 이름이 그 개인운동인가. 옛 시드 행은 이름 뒤에 양을 붙여
/// 적었다(`인터벌 런닝 25분`).
bool demoRowIsRoutine(String rowName, String routineName) {
  final String row = rowName.trim();
  final String routine = routineName.trim();
  return routine.isNotEmpty && (row == routine || row.startsWith('$routine '));
}

/// 데모 하루 운동 행(하루 지표에 실린 것)의 이름들.
Future<Set<String>> demoRowNamesOn(
  AppDatabase db,
  String memberId,
  DateTime day,
) async {
  final ClientDailyMetricRow? row =
      await (db.select(db.clientDailyMetrics)
            ..where((t) => t.clientId.equals(memberId))
            ..where((t) => t.date.equals(ymd(day))))
          .getSingleOrNull();
  if (row == null) return const <String>{};
  final Object? decoded = jsonDecode(row.exercisesJson);
  if (decoded is! List<Object?>) return const <String>{};
  return <String>{
    for (final Object? item in decoded)
      if (item is Map<String, Object?> && item['name'] is String)
        (item['name']! as String).trim()
      else if (item is String)
        item.replaceAll('✓', '').trim(),
  };
}

/// 데모 오늘 지금 걸린 개인운동 — 이름 → 배정 id. (#2508)
///
/// 실서버에서 회원이 개인운동을 체크하면 그 운동 행이 출처 `assigned_routine`
/// 으로 남는다. 데모의 오늘 운동 행은 출처 없이 시드되므로, 걸린 개인운동과
/// 이름이 같은 행을 그 체크로 읽는다 — 날짜별 이행([MockRoutineDaysRepository])
/// 과 운동 행이 같은 규칙으로 한 것을 말한다.
Future<Map<String, String>> demoTodayAssignedRoutines(
  AppDatabase db,
  String memberId,
) async {
  final DateTime today = _dayOf(nowKst());
  final List<AssignedRoutine> assigned = await DemoRoutineStore(
    db,
  ).assigned(memberId);
  final Map<String, String> byName = <String, String>{};
  for (final RoutineDayRoutine r in demoRoutineWindows(assigned, today)) {
    if (r.activeOn(today)) byName.putIfAbsent(r.name.trim(), () => r.id);
  }
  return byName;
}

/// 데모 배정 → 걸린 기간. 서버 시드와 같은 규칙이다.
///
/// 씨앗 배정(날짜·종류 없음)은 오늘 포함 4주 전부터 걸린 기한 없는 배정이다
/// (백엔드 `_seed_routine_since`). 데모에서 보낸 개인운동은 시작일부터 7일이다
/// (#2656).
List<RoutineDayRoutine> demoRoutineWindows(
  List<AssignedRoutine> assigned,
  DateTime today, {
  List<(AssignedRoutine, DateTime)> retired =
      const <(AssignedRoutine, DateTime)>[],
}) {
  final DateTime seedSince = today.subtract(const Duration(days: 27));
  final List<(AssignedRoutine, DateTime?)> rows =
      <(AssignedRoutine, DateTime?)>[
        for (final AssignedRoutine r in assigned) (r, null),
        for (final (AssignedRoutine r, DateTime end) in retired) (r, end),
      ];
  return <RoutineDayRoutine>[
    for (final (int i, (AssignedRoutine r, DateTime? retiredOn))
        in rows.indexed)
      () {
        final bool personal = r.deliveryKind != null;
        final DateTime? date = r.date == null ? null : _dayOf(r.date!);
        final DateTime from = date ?? (personal ? today : seedSince);
        return RoutineDayRoutine(
          id: r.id,
          name: r.name,
          type: r.type,
          source: r.source,
          // 한 전송 안은 보낸 순서 그대로 목록에 들어 있다 — 묶음은 보낸
          // 날로 갈리므로 목록 순서가 곧 배정 순서다.
          sortOrder: i,
          activeFrom: from,
          // 내려간 개인운동은 다음 묶음이 걸린 날에 끝난다(7일보다 이르면).
          endedOn: personal
              ? _earlier(from.add(const Duration(days: 7)), retiredOn)
              : retiredOn,
          sentOn: from.isAfter(today) ? today : from,
          personal: personal,
          minutes: r.minutes,
          durationSeconds: r.durationSeconds,
          sets: r.sets,
          reps: r.reps,
          holdSeconds: r.holdSeconds,
          weight: r.weight,
          // 데모 배정 저장소가 빈 효과를 문구표로 채워 둔다.
          effect: r.effect,
        );
      }(),
  ];
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _earlier(DateTime a, DateTime? b) =>
    b == null || !b.isBefore(a) ? a : _dayOf(b);

/// 하루치 칸을 만드는 규칙.
abstract class _DoneRule {
  List<RoutineDayItem> items(
    List<RoutineDayRoutine> on,
    DateTime day,
    DateTime today,
  );
}

/// 김민수 — 그날 한 운동 중 이름이 같은 것을 완료로 잇는다.
class _FixtureDone implements _DoneRule {
  _FixtureDone(List<FixtureDay> days)
    : _done = <String, Set<String>>{
        for (final FixtureDay d in days)
          if (!d.isPt)
            d.date: <String>{
              for (final FixtureExercise e in d.exercises)
                if (e.done) e.name,
            },
      };

  final Map<String, Set<String>> _done;

  @override
  List<RoutineDayItem> items(
    List<RoutineDayRoutine> on,
    DateTime day,
    DateTime today,
  ) {
    final bool isToday = day == today;
    final Set<String> done = isToday
        ? const <String>{}
        : _done[ymd(day)] ?? const <String>{};
    return <RoutineDayItem>[
      for (final RoutineDayRoutine r in on)
        RoutineDayItem(
          routineId: r.id,
          status: done.contains(r.name)
              ? RoutineDayStatus.done
              : isToday
              ? RoutineDayStatus.pending
              : RoutineDayStatus.missed,
          sessionId: done.contains(r.name)
              ? 'demo-session-${r.id}-${ymd(day)}'
              : null,
        ),
    ];
  }
}

/// 다른 회원 — 그날 이행률만큼 배정 순서대로 완료.
///
/// 회원마다 정해진 요일에는 마지막 완료를 다음 날 체크한 것으로 둔다 — 데모에서도
/// `다음 날 이후 체크` 칸이 보여야 한다. 날짜와 회원 id 로만 정해 새로고침해도
/// 같다.
class _RateDone implements _DoneRule {
  _RateDone(this._memberId, this._completion);

  final String _memberId;
  final Map<String, int> _completion;

  @override
  List<RoutineDayItem> items(
    List<RoutineDayRoutine> on,
    DateTime day,
    DateTime today,
  ) {
    final List<RoutineDayRoutine> ordered = <RoutineDayRoutine>[...on]
      ..sort(
        (RoutineDayRoutine a, RoutineDayRoutine b) =>
            a.sortOrder.compareTo(b.sortOrder),
      );
    final int rate = _completion[ymd(day)] ?? 0;
    final int done = (ordered.length * rate / 100).round();
    final bool isToday = day == today;
    final bool lateDay =
        !isToday && done > 0 && (day.day + _memberId.length) % 4 == 0;
    return <RoutineDayItem>[
      for (final (int i, RoutineDayRoutine r) in ordered.indexed)
        RoutineDayItem(
          routineId: r.id,
          status: i < done
              ? (lateDay && i == done - 1
                    ? RoutineDayStatus.late
                    : RoutineDayStatus.done)
              : isToday
              ? RoutineDayStatus.pending
              : RoutineDayStatus.missed,
          sessionId: i < done ? 'demo-session-${r.id}-${ymd(day)}' : null,
        ),
    ];
  }
}

/// 실서버 또는 데모.
final routineDaysRepositoryProvider = Provider<RoutineDaysRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return MockRoutineDaysRepository(ref.watch(appDatabaseProvider));
  }
  return DioRoutineDaysRepository(ref.watch(dioProvider));
}, name: 'routineDaysRepository');

/// 날짜별 개인운동 조회 키 — 누구의, **어느 날 기준으로**. 자정을 넘기면 새
/// 날짜로 다시 묻는다([ClientPeriodKey] 와 같은 이유).
typedef RoutineDaysKey = ({String clientId, DateTime day});

/// 지금(KST) 기준의 조회 키.
RoutineDaysKey routineDaysKeyNow(String clientId) {
  final DateTime now = nowKst();
  return (clientId: clientId, day: DateTime(now.year, now.month, now.day));
}

/// 처음 걸린 날부터 오늘까지 — `오늘`·`이번 주`·`전체` 와 프로그램 화면이
/// 이 한 번의 응답을 나눠 그린다.
final clientRoutineDaysProvider = FutureProvider.autoDispose
    .family<RoutineDays, RoutineDaysKey>((ref, key) {
      keepAliveForAccount(ref);
      return ref
          .watch(routineDaysRepositoryProvider)
          .fetch(key.clientId, to: key.day);
    });
