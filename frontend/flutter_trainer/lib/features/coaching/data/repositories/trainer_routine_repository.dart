import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

/// Assigns a routine to a member and reads their assigned routines.
///
/// Assigning is how a member *receives* a routine (the same record the
/// member app reads via `/me/coach/routines`). Two implementations sit
/// behind this contract, selected by [trainerRoutineRepositoryProvider] via
/// [AppConfig.useMockApi]:
///  * [MockTrainerRoutineRepository] — demo / `USE_MOCK_API=true` (keeps
///    assignments in the local drift DB; there is no member app to receive
///    them);
///  * [DioTrainerRoutineRepository] — the real FastAPI backend.
abstract interface class TrainerRoutineRepository {
  /// Assigns [routine] to [memberId] (POST /trainer/clients/{id}/routines).
  ///
  /// [clientRequestId] 는 **전송 시도**의 멱등키다. 재시도할 때 같은 값을 다시
  /// 넘기면 회원에게 같은 루틴이 두 번 배정되지 않는다(#581). 새 내용을 보낼
  /// 때만 새로 만든다 — 매 호출 새로 만들면 아무것도 막지 못한다.
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  });

  /// Assigns a whole program — one routine per session (#709).
  ///
  /// [payload] comes from `programAssignToJson`, which carries the session
  /// order and each session's exercises. A program with one session lands as
  /// the same single routine the flat path produces, so the member's screen
  /// does not suddenly grow a session label.
  Future<void> assignProgram(String memberId, Map<String, Object?> payload);

  /// The member's currently assigned routines (newest first).
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId);

  /// 이 회원에게 **가장 최근에 보낸 것** 한 묶음. 보낸 적이 없으면 null. (#2225)
  ///
  /// 이력이 PT 프로그램과 개인운동을 따로 나열하면, PT 완료 때 함께 보낸
  /// 개인운동이 어느 PT 와 짝인지 알 수 없다(#2224).
  Future<SentDelivery?> fetchLatestDelivery(String memberId);

  /// 배정한 루틴을 고친다(PUT). 보낸 필드만 바뀐다. (#504)
  ///
  /// 없는 루틴·남의 배정은 [StateError] — 배정 실패와 같은 규칙으로, 목과
  /// 실서버가 같은 예외를 낸다.
  ///
  /// [durationSeconds] 를 주면 서버가 분을 초에서 다시 접는다. [minutes] 만
  /// 주면 예전 초는 지워진다(#2547).
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    int? durationSeconds,
    String? type,
    String? reason,
  });

  /// 배정한 루틴을 철회한다(DELETE). 회원 앱에서도 사라진다. (#504)
  Future<void> deleteRoutine(String memberId, String routineId);
}

/// 데모용 배정 저장소.
///
/// 예전에는 목록이 늘 비어 있고 취소는 `StateError` 를 던지는 no-op 이었다.
/// 데모에는 루틴을 받을 회원 백엔드가 없다는 이유였는데, 그 바람에 **개인 운동
/// 취소를 데모에서 확인할 방법이 없었다**(#1020). 배정을 실제로 들고 있으면
/// 취소가 목록에서 사라지는 것까지 데모로 보인다.
///
/// [db] 를 주면 배정·마지막 전달을 drift 에 남긴다(#2668) — 새로고침해도
/// 그대로이고, 스케줄에서 PT 와 함께 보낸 개인운동(`DriftScheduleRepository`
/// 가 같은 [DemoRoutineStore] 에 남긴다)도 이 목록과 마지막 전달에 보인다.
/// 회원마다 처음 배정은 시드가 정한다([DemoRoutineStore.seedAssigned]).
///
/// [db] 가 없으면(단위 테스트) 메모리에 들고, 김민수만 픽스처 배정을 갖는다.
class MockTrainerRoutineRepository implements TrainerRoutineRepository {
  /// Creates the demo repository.
  MockTrainerRoutineRepository({AppDatabase? db})
    : _db = db,
      _store = db == null ? null : DemoRoutineStore(db);

  final AppDatabase? _db;
  final DemoRoutineStore? _store;

  /// 회원별 배정 — [_store] 가 없을 때만 쓴다.
  final Map<String, List<AssignedRoutine>> _byMember =
      <String, List<AssignedRoutine>>{};

  /// 데모에서 마지막으로 보낸 묶음 — [_store] 가 없을 때만 쓴다.
  final Map<String, SentDelivery> _lastDelivery = <String, SentDelivery>{};

  /// 회원별로 마지막에 `개인운동만` 으로 보낸 줄 id — 다음에 보낼 때 내린다.
  /// [_store] 가 없을 때만 쓴다.
  final Map<String, Set<String>> _personalIds = <String, Set<String>>{};

  final Map<String, StreamController<List<AssignedRoutine>>> _controllers =
      <String, StreamController<List<AssignedRoutine>>>{};

  /// 열어 둔 스트림을 모두 닫는다. provider 가 버려질 때 불린다.
  void dispose() {
    for (final StreamController<List<AssignedRoutine>> c
        in _controllers.values) {
      c.close();
    }
    _controllers.clear();
  }

  /// 메모리 모드의 회원 목록. 처음 읽을 때 시드한다 — 김민수만 픽스처 배정이
  /// 있다.
  List<AssignedRoutine> _memoryListFor(String memberId) =>
      _byMember.putIfAbsent(
        memberId,
        () => memberId == demoFixtureMemberId
            ? demoFixtureAssignedRoutines()
            : <AssignedRoutine>[],
      );

  Future<List<AssignedRoutine>> _listFor(String memberId) async {
    final DemoRoutineStore? store = _store;
    if (store != null) return store.assigned(memberId);
    return _memoryListFor(memberId);
  }

  Future<void> _writeList(String memberId, List<AssignedRoutine> rows) async {
    final DemoRoutineStore? store = _store;
    if (store != null) {
      // 지켜보는 쪽은 drift 가 깨운다([DemoRoutineStore.watchAssigned]).
      await store.writeAssigned(memberId, rows);
      return;
    }
    _byMember[memberId] = rows;
    _controllers[memberId]?.add(List<AssignedRoutine>.unmodifiable(rows));
  }

  /// 새 배정 id. 웹의 시각은 밀리초 해상도라 같은 순간의 두 줄이 겹치지 않게
  /// 순번을 붙인다.
  String _newId(String name) =>
      'demo-${DateTime.now().microsecondsSinceEpoch}-${_seq++}-$name';
  int _seq = 0;

  /// 한 건 배정 — AI 제안 승인이 이 길로 온다(#2668). 실서버에서 승인하면 그
  /// 회원에게 배정되듯, 데모도 배정 목록 맨 앞에 넣는다. 아무것도 하지 않던
  /// 동안에는 승인한 제안이 목록에서 빠질 뿐 어디에도 들어가지 않았다.
  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {
    final AssignedRoutine added = AssignedRoutine(
      id: routine.id.isEmpty ? _newId(routine.name) : routine.id,
      name: routine.name,
      minutes: routine.minutes,
      type: routine.type,
      reason: routine.reason,
      source: routine.source,
      date: routine.date,
      intensity: routine.intensity,
      sets: routine.sets,
      reps: routine.reps,
      holdSeconds: routine.holdSeconds,
      durationSeconds: routine.durationSeconds,
      weight: routine.weight,
    );
    await _writeList(memberId, <AssignedRoutine>[
      added,
      ...await _listFor(memberId),
    ]);
    // 채팅에도 남긴다(#2672) — 실서버 단건 배정·제안 승인과 같다.
    await _store?.postDeliveryCard(
      memberId,
      RoutineDeliveryNotice(
        kind: 'routine',
        routineNames: <String>[added.name],
      ),
    );
  }

  @override
  /// 데모에는 받을 회원 백엔드가 없지만 **배정 목록에는 남긴다**(#2224).
  ///
  /// 아무것도 하지 않던 동안에는 `개인운동만 전송` 이 성공했다고 말해 놓고
  /// 전송 이력이 그대로였다 — 같은 탭의 PT 등록은 실제로 반영되므로, 두 경로가
  /// 다르게 움직여 데모로 흐름을 확인할 수 없었다.
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {
    final sessions = payload['sessions'];
    if (sessions is! List) return;
    final DateTime? date = _parseDate(payload['start_date']);
    final bool personal = payload['delivery_kind'] != null;
    final added = <AssignedRoutine>[
      for (final session in sessions)
        if (session is Map<String, Object?>)
          for (final ex in (session['exercises'] as List<Object?>? ??
              const <Object?>[]))
            if (ex is Map<String, Object?>)
              AssignedRoutine(
                id: _newId((ex['name'] as String?) ?? ''),
                name: (ex['name'] as String?) ?? '',
                minutes: (ex['duration'] as num?)?.toInt() ?? 0,
                type: (ex['type'] as String?) ?? '기타',
                reason: '',
                source: (ex['source'] as String?) ?? 'trainer',
                date: date,
                sets: (ex['sets'] as num?)?.toInt(),
                reps: (ex['reps'] as num?)?.toInt(),
                holdSeconds: (ex['hold_seconds'] as num?)?.toInt(),
                // 초를 함께 남겨야 `45초` 가 분으로 접혀 `1분` 으로 보이지
                // 않는다 — 실서버도 초를 저장한다(#2521, #2755). 근력은
                // 세트로 재므로 비운다.
                durationSeconds: ex['type'] == '근력'
                    ? null
                    : (ex['duration_seconds'] as num?)?.toInt(),
                weight: (ex['weight'] as num?)?.toDouble(),
                deliveryKind: personal ? DeliveryKinds.routineOnly : null,
              ),
    ];
    if (added.isEmpty) return;
    // `개인운동만` 을 새로 보내면 이전에 보낸 개인운동은 내려간다(#2514) —
    // 서버와 같은 규칙이다. 씨앗 배정은 서버 시드처럼 기한 없는 배정이라
    // 그대로 둔다.
    final Set<String> newIds = <String>{
      for (final AssignedRoutine r in added) r.id,
    };
    final DemoRoutineStore? store = _store;
    if (store != null) {
      // 이 전송의 개인운동을 채운 AI 제안을 닫는다 — 실서버가 배정과 같은
      // 트랜잭션에서 하는 일이다(#2747). 데모 제안 저장소는 검토한 제안을
      // 이 기억에서 걸러 낸다.
      await store.addReviewedSuggestions(<String>[
        for (final Object? id
            in payload['suggestion_ids'] as List<Object?>? ?? const <Object?>[])
          if (id is String) id,
      ]);
      final Set<String> previous = personal
          ? await store.readPersonalIds(memberId)
          : const <String>{};
      // 직전 전송으로도 기억한다(#2225). 이 길은 PT 일정이 붙지 않는
      // `개인운동만` 이다 — PT 와 함께 가는 것은 스케줄 저장소가 남긴다.
      await store.recordDelivery(
        memberId,
        StoredDelivery(
          kind: DeliveryKinds.routineOnly,
          sentOn: date,
          routines: added,
        ),
        replacing: previous,
      );
      if (personal) await store.writePersonalIds(memberId, newIds);
      return;
    }
    final Set<String> previous = _personalIds[memberId] ?? const <String>{};
    // 새로 보낸 것이 맨 앞이다 — 목록은 최신순이다.
    await _writeList(memberId, <AssignedRoutine>[
      ...added,
      for (final AssignedRoutine r in _memoryListFor(memberId))
        if (!personal || !previous.contains(r.id)) r,
    ]);
    if (personal) _personalIds[memberId] = newIds;
    _lastDelivery[memberId] = SentDelivery(
      kind: DeliveryKinds.routineOnly,
      sentOn: date,
      routines: added,
    );
  }

  /// 마지막 전달. PT 와 함께 간 것·취소된 PT 뒤에 보낸 것도 스케줄 저장소가
  /// 남긴 그대로 돌려준다(#2668) — 예전에는 늘 `개인운동만` 이라 전송 이력의
  /// PT 동반·취소 표시를 데모에서 볼 수 없었다.
  @override
  Future<SentDelivery?> fetchLatestDelivery(String memberId) async {
    final DemoRoutineStore? store = _store;
    if (store == null) {
      return _lastDelivery[memberId] ??
          _seededDelivery(_memoryListFor(memberId));
    }
    final StoredDelivery? stored = await store.readDelivery(memberId);
    if (stored == null) return _seededDelivery(await store.assigned(memberId));
    final String? sessionId = stored.sessionId;
    return SentDelivery(
      kind: stored.kind,
      sentOn: stored.sentOn,
      // 일정은 지금 모습으로 다시 읽는다 — 보낸 뒤 바뀐 상태가 그대로 보인다.
      session: sessionId == null
          ? null
          : await DriftScheduleRepository(_db!).sessionById(sessionId),
      routines: stored.routines,
    );
  }

  /// 아직 아무것도 보내지 않았을 때의 직전 전송. (#2225)
  ///
  /// 씨앗 배정은 **이미 회원에게 간 것**이다. 그런데 기억해 둔 전송이 없다고
  /// 비워 두면, 데모를 처음 연 트레이너는 전송 이력이 늘 비어 있는 화면을 본다
  /// — 실제 백엔드는 지난 전송을 보여 주므로 두 곳이 다르게 움직인다.
  ///
  /// 씨앗 배정은 PT 일정에 붙지 않은 배정이라 종류는 `개인운동만` 이다.
  static SentDelivery? _seededDelivery(List<AssignedRoutine> rows) {
    if (rows.isEmpty) return null;
    DateTime? sentOn;
    for (final r in rows) {
      final DateTime? d = r.date;
      if (d != null && (sentOn == null || d.isAfter(sentOn))) sentOn = d;
    }
    return SentDelivery(
      kind: DeliveryKinds.routineOnly,
      sentOn: sentOn,
      routines: rows,
    );
  }

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) {
    final DemoRoutineStore? store = _store;
    if (store != null) {
      return store
          .watchAssigned(memberId)
          .map(List<AssignedRoutine>.unmodifiable);
    }
    // 수명은 [dispose] 가 쥔다 — provider 가 버려질 때 한꺼번에 닫는다. 여기서
    // 닫으면 다음 구독자가 죽은 스트림을 받는다.
    // ignore: close_sinks
    final StreamController<List<AssignedRoutine>> controller = _controllers
        .putIfAbsent(
          memberId,
          () => StreamController<List<AssignedRoutine>>.broadcast(),
        );
    // 구독하는 쪽이 첫 값을 곧바로 받아야 한다 — 브로드캐스트 스트림은 지난
    // 값을 다시 주지 않는다.
    return controller.stream.startWith(
      List<AssignedRoutine>.unmodifiable(_memoryListFor(memberId)),
    );
  }

  // 데모에는 배정을 고치는 화면이 없다. 조용히 성공하면 화면이 '고쳤다'고
  // 말하게 되므로 없는 것을 지적한다.
  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    int? durationSeconds,
    String? type,
    String? reason,
  }) async => throw StateError('routine not found: $routineId');

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {
    final List<AssignedRoutine> mine = await _listFor(memberId);
    // 실서버와 같은 예외다 — 없는 것을 지우려 하면 404 를 `StateError` 로
    // 옮기므로, 화면이 한 갈래만 다루면 된다.
    if (!mine.any((AssignedRoutine r) => r.id == routineId)) {
      throw StateError('routine not found: $routineId');
    }
    await _writeList(memberId, <AssignedRoutine>[
      for (final AssignedRoutine r in mine)
        if (r.id != routineId) r,
    ]);
  }
}

/// 브로드캐스트 스트림에 첫 값을 얹는다. 구독 시점의 현재 목록을 곧바로
/// 흘려보내야 화면이 빈 채로 기다리지 않는다.
extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}

/// Selects the real Dio-backed routine repository against the FastAPI
/// backend, or the demo repository for `USE_MOCK_API=true`.
final trainerRoutineRepositoryProvider = Provider<TrainerRoutineRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    // 배정은 데모 DB 에 남는다(#2668) — 새로고침해도, 스케줄에서 보낸 것도
    // 같은 목록에 보인다.
    final MockTrainerRoutineRepository demo = MockTrainerRoutineRepository(
      db: ref.watch(appDatabaseProvider),
    );
    ref.onDispose(demo.dispose);
    return demo;
  }
  return DioTrainerRoutineRepository(
    ref.watch(dioProvider),
    // 이름 없는 배정은 회원에게 그대로 보인다 — 보내는 순간의 화면 언어로(#2301).
    fallbackName: () => lookupAppLocalizations(
      ref.read(trainerResolvedLocaleProvider),
    ).aiCustomRoutineName,
  );
}, name: 'trainerRoutineRepository');

/// Streams the routines currently assigned to a member (newest first).
///
/// 데모에서도 비어 있지 않다 — [MockTrainerRoutineRepository] 가 아직 하지
/// 않은 개인 운동을 들고 있어, 취소가 목록에서 사라지는 것까지 보인다(#1020).
final assignedRoutinesProvider = StreamProvider.autoDispose
    .family<List<AssignedRoutine>, String>((ref, memberId) {
      keepAliveForAccount(ref);
      return ref
          .watch(trainerRoutineRepositoryProvider)
          .watchAssignedRoutines(memberId);
    });
