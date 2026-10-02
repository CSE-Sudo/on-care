import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';

/// Supplies the initial AI-suggested exercises shown before a trainer asks
/// the backend to generate fresh A/B options.
abstract interface class AiRoutineRepository {
  /// Watches the initial suggestions for one client.
  Stream<List<AiRoutineItem>> watchRoutine(
    String clientId, {
    String? clientName,
  });
}

/// Reads the bundled demo suggestions from the local drift DB.
class DriftAiRoutineRepository implements AiRoutineRepository {
  /// Creates the repository over [_db].
  const DriftAiRoutineRepository(this._db);

  final AppDatabase _db;

  /// The AI suggestions for [clientId], in seeded order.
  ///
  /// Real API clients use backend ids (`user-7d4e9a2c5f18`) while the bundled
  /// suggestions use demo ids (`seed-client-1`). [clientName] lets a live
  /// roster resolve the corresponding local suggestion set.
  @override
  Stream<List<AiRoutineItem>> watchRoutine(
    String clientId, {
    String? clientName,
  }) {
    final routines = _db.clientAiRoutines;
    final clients = _db.trainerClients;
    // 타입 인자를 적지 않는다 — drift 의 `innerJoin` 이 돌려주는
    // `Join<HasResultSet, dynamic>` 을 추론이 채운다. `<Join>` 이라고 쓰면
    // raw type 이라 `strict-raw-types` 에 걸린다.
    final query = _db.select(routines).join([
      innerJoin(
        clients,
        clients.id.equalsExp(routines.clientId),
        useColumns: false,
      ),
    ]);
    query.where(
      routines.clientId.equals(clientId) |
          (clientName == null
              ? const Constant<bool>(false)
              : clients.name.equals(clientName)),
    );
    return query.watch().map((rows) {
      final localRows = rows.map((row) => row.readTable(routines)).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return localRows
          .map(
            (row) => AiRoutineItem(
              id: row.id,
              name: row.name,
              minutes: row.minutes,
              type: row.type,
              reason: row.reason,
              // 근력의 양(#2705) — 초기 AI 루틴도 세트·횟수로 읽는다.
              sets: row.sets,
              reps: row.reps,
              holdSeconds: row.holdSeconds,
              weight: row.weight,
            ),
          )
          .toList();
    });
  }
}

/// 실서버의 `기존 AI 추천` — 그 회원에게 **지금 배정돼 있는 AI 개인운동**. (#2673)
///
/// A/B 비교 화면의 세 번째 카드(`기존안 · 기존 AI 추천`)가 읽는다. 예전 실서버는
/// 늘 빈 목록이라 이 카드가 데모에만 있었다. 데모의 목록(시드 AI 운동)은 회원의
/// 첫 배정과 같은 목록이라(#2668), 실서버에서는 배정 목록(`GET /trainer/clients/
/// {id}/routines`)에서 AI 가 고른 것 중 아직 하지 않은 것을 쓴다 — 새 API 없이
/// 같은 뜻이 된다. 데모 시드를 실서버 회원에게 보이지 않는 것은 그대로다.
class AssignedAiRoutineRepository implements AiRoutineRepository {
  /// Creates the real-mode source over the member's assignments.
  const AssignedAiRoutineRepository(this._routines);

  final TrainerRoutineRepository _routines;

  /// 배정을 읽지 못하면 빈 목록이다 — 이 카드는 없어도 되는 보조 후보인데,
  /// 오류를 그대로 흘리면 코칭 화면이 A/B 흐름 대신 오류 상자를 띄운다.
  @override
  Stream<List<AiRoutineItem>> watchRoutine(
    String clientId, {
    String? clientName,
  }) async* {
    try {
      await for (final List<AssignedRoutine> rows
          in _routines.watchAssignedRoutines(clientId)) {
        yield <AiRoutineItem>[
          for (final AssignedRoutine r in rows)
            if (r.source == 'ai' && !r.completed)
              AiRoutineItem(
                id: r.id,
                name: r.name,
                minutes: r.minutes,
                type: r.type,
                reason: r.reason,
                durationSeconds: r.durationSeconds,
                sets: r.sets ?? 0,
                reps: r.reps ?? 0,
                holdSeconds: r.holdSeconds ?? 0,
                weight: r.weight ?? 0,
              ),
        ];
      }
    } catch (_) {
      yield const <AiRoutineItem>[];
    }
  }
}

/// 데모는 시드 AI 운동(drift), 실서버는 그 회원에게 배정된 AI 개인운동이다.
/// 실서버는 이 provider 로 [appDatabaseProvider] 를 건드리지 않는다.
final aiRoutineRepositoryProvider = Provider<AiRoutineRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return DriftAiRoutineRepository(ref.watch(appDatabaseProvider));
  }
  return AssignedAiRoutineRepository(
    ref.watch(trainerRoutineRepositoryProvider),
  );
}, name: 'aiRoutineRepository');

/// A stable key for local suggestions when the live and demo ids differ.
typedef AiRoutineClientKey = ({String id, String name});

/// Streams a client's AI routine suggestions.
final aiRoutineProvider = StreamProvider.autoDispose
    .family<List<AiRoutineItem>, AiRoutineClientKey>((ref, key) {
      keepAliveForAccount(ref);
      return ref
          .watch(aiRoutineRepositoryProvider)
          .watchRoutine(key.id, clientName: key.name);
    });
