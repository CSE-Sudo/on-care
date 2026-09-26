import 'dart:async';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

/// Assigns a routine to a member and reads their assigned routines.
///
/// Assigning is how a member *receives* a routine (the same record the
/// member app reads via `/me/coach/routines`). Two implementations sit
/// behind this contract, selected by [trainerRoutineRepositoryProvider] via
/// [AppConfig.useMockApi]:
///  * [MockTrainerRoutineRepository] — demo / `USE_MOCK_API=true` (no-op
///    send; the demo has no member app to receive it);
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

  /// 배정한 루틴을 고친다(PUT). 보낸 필드만 바뀐다. (#504)
  ///
  /// 없는 루틴·남의 배정은 [StateError] — 배정 실패와 같은 규칙으로, 목과
  /// 실서버가 같은 예외를 낸다.
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    String? type,
    String? reason,
  });

  /// 배정한 루틴을 철회한다(DELETE). 회원 앱에서도 사라진다. (#504)
  Future<void> deleteRoutine(String memberId, String routineId);
}

/// 데모용 배정 저장소 — 메모리에 들고 있는다.
///
/// 예전에는 목록이 늘 비어 있고 취소는 `StateError` 를 던지는 no-op 이었다.
/// 데모에는 루틴을 받을 회원 백엔드가 없다는 이유였는데, 그 바람에 **개인 운동
/// 취소를 데모에서 확인할 방법이 없었다**(#1020). 배정을 실제로 들고 있으면
/// 취소가 목록에서 사라지는 것까지 데모로 보인다.
///
/// 배정(`assignRoutine`)은 여전히 조용히 성공한다 — 데모의 '전송됨' 피드백은
/// 로컬 채팅·스케줄 쓰기가 만든다.
class MockTrainerRoutineRepository implements TrainerRoutineRepository {
  /// Creates the demo repository, seeded for [seedClientId].
  MockTrainerRoutineRepository();

  /// 회원별 배정. 시연에 쓰는 고객만 채워 둔다.
  final Map<String, List<AssignedRoutine>> _byMember =
      <String, List<AssignedRoutine>>{
        for (final String memberId in _seededMembers)
          memberId: List<AssignedRoutine>.from(_seedRoutines),
      };

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

  /// 데모 시드가 만드는 고객 id. 김민수 하나면 시연에 충분하다 — 명단 전원에게
  /// 배정을 뿌리면 어느 고객을 열어도 같은 루틴이 있어 오히려 가짜처럼 보인다.
  static const List<String> _seededMembers = <String>['seed-client-1'];

  /// 배정된 개인 운동 — **공유 픽스처**가 정한다. (#1170)
  ///
  /// 예전에는 이 목록을 여기에 손으로 적어 두었다(`저강도 유산소 20분` ·
  /// `코어 서킷 15분`). 회원 앱과 프로그램 탭도 각자 적어 두어서, 같은 회원의
  /// 같은 날에 세 화면이 서로 다른 운동을 말했다. 이제 셋 다
  /// `shared/demo_fixture` 의 `routines` 하나만 읽는다.
  ///
  /// AI 추천과 트레이너가 보낸 것이 섞여 있어, 두 출처가 화면에서 어떻게
  /// 갈리는지도 그대로 보인다.
  static final List<AssignedRoutine> _seedRoutines = <AssignedRoutine>[
    for (final FixtureRoutine r in DemoFixture.load().routines)
      AssignedRoutine(
        id: r.id,
        name: r.name,
        minutes: r.minutes,
        type: r.type,
        reason: r.reason,
        source: r.source,
        // 근력은 세트·횟수·중량으로 읽는다(#1276) — 픽스처가 그 값을 들지
        // 않던 동안 데모의 근력 배정은 `10분` 한 줄로만 보였다.
        sets: r.sets,
        reps: r.reps,
        weight: r.weight,
      ),
  ];

  List<AssignedRoutine> _listFor(String memberId) =>
      _byMember[memberId] ?? const <AssignedRoutine>[];

  void _emit(String memberId) {
    _controllers[memberId]?.add(
      List<AssignedRoutine>.unmodifiable(_listFor(memberId)),
    );
  }

  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {}

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
    final added = <AssignedRoutine>[
      for (final session in sessions)
        if (session is Map<String, Object?>)
          for (final ex in (session['exercises'] as List<Object?>? ??
              const <Object?>[]))
            if (ex is Map<String, Object?>)
              AssignedRoutine(
                id: 'demo-${DateTime.now().microsecondsSinceEpoch}-'
                    '${(ex['name'] as String?) ?? ''}',
                name: (ex['name'] as String?) ?? '',
                minutes: (ex['duration'] as num?)?.toInt() ?? 0,
                type: (ex['type'] as String?) ?? '기타',
                reason: '',
                source: (ex['source'] as String?) ?? 'trainer',
                date: date,
                sets: (ex['sets'] as num?)?.toInt(),
                reps: (ex['reps'] as num?)?.toInt(),
                holdSeconds: (ex['hold_seconds'] as num?)?.toInt(),
                weight: (ex['weight'] as num?)?.toDouble(),
              ),
    ];
    if (added.isEmpty) return;
    // 새로 보낸 것이 맨 앞이다 — 목록은 최신순이다.
    _byMember[memberId] = <AssignedRoutine>[
      ...added,
      ..._listFor(memberId),
    ];
    _emit(memberId);
  }

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) {
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
      List<AssignedRoutine>.unmodifiable(_listFor(memberId)),
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
    String? type,
    String? reason,
  }) async => throw StateError('routine not found: $routineId');

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {
    final List<AssignedRoutine>? mine = _byMember[memberId];
    final int at =
        mine?.indexWhere((AssignedRoutine r) => r.id == routineId) ?? -1;
    // 실서버와 같은 예외다 — 없는 것을 지우려 하면 404 를 `StateError` 로
    // 옮기므로, 화면이 한 갈래만 다루면 된다.
    if (mine == null || at < 0) {
      throw StateError('routine not found: $routineId');
    }
    mine.removeAt(at);
    _emit(memberId);
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
/// backend, or the demo no-op for `USE_MOCK_API=true`.
final trainerRoutineRepositoryProvider = Provider<TrainerRoutineRepository>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    // 배정을 메모리에 들고 있으므로 const 가 아니다. provider 가 한 번만
    // 만들어 앱이 사는 동안 같은 목록을 보게 한다.
    final MockTrainerRoutineRepository demo = MockTrainerRoutineRepository();
    ref.onDispose(demo.dispose);
    return demo;
  }
  return DioTrainerRoutineRepository(ref.watch(dioProvider));
}, name: 'trainerRoutineRepository');

/// Streams the routines currently assigned to a member (newest first).
///
/// 데모에서도 비어 있지 않다 — [MockTrainerRoutineRepository] 가 아직 하지
/// 않은 개인 운동을 들고 있어, 취소가 목록에서 사라지는 것까지 보인다(#1020).
final assignedRoutinesProvider =
    StreamProvider.family<List<AssignedRoutine>, String>((ref, memberId) {
      return ref
          .watch(trainerRoutineRepositoryProvider)
          .watchAssignedRoutines(memberId);
    });
