import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/ai_routine_item.dart';

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
            ),
          )
          .toList();
    });
  }
}

/// Real mode deliberately starts without bundled suggestions. Fresh options
/// come from `POST /trainer/clients/{id}/routine-options`; falling back to
/// drift here would make a live member look as if they had demo recommendations.
class EmptyAiRoutineRepository implements AiRoutineRepository {
  /// Creates the real-mode empty initial source.
  const EmptyAiRoutineRepository();

  @override
  Stream<List<AiRoutineItem>> watchRoutine(
    String clientId, {
    String? clientName,
  }) => Stream<List<AiRoutineItem>>.value(const <AiRoutineItem>[]);
}

/// Selects bundled suggestions only for mock mode. Real mode never touches
/// [appDatabaseProvider] through this provider.
final aiRoutineRepositoryProvider = Provider<AiRoutineRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return DriftAiRoutineRepository(ref.watch(appDatabaseProvider));
  }
  return const EmptyAiRoutineRepository();
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
