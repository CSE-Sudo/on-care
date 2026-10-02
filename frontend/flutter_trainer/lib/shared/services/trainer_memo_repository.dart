import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_trainer_memo_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads and writes the memos a trainer keeps about one member.
///
/// Two implementations sit behind this contract (selected by
/// [trainerMemoRepositoryProvider] via [AppConfig.useMockApi]):
///  * [LocalTrainerMemoRepository] — browser-local prefs, demo /
///    `USE_MOCK_API=true`;
///  * [DioTrainerMemoRepository] — the real FastAPI backend, where memos
///    survive a re-login and follow the trainer to another browser.
///
/// Both the client detail screen and the chat-insight action write through
/// this one contract, so a memo saved from chat shows up in the client's
/// memo list and vice versa.
abstract interface class TrainerMemoRepository {
  /// This client's memos, newest first.
  Future<List<TrainerMemo>> fetch(String clientId);

  /// Adds a memo.
  ///
  /// Passing [insightId] makes the write idempotent for that chat insight —
  /// saving the same signal again returns the memo that is already stored
  /// instead of adding a duplicate.
  ///
  /// [ref] points an [TrainerMemoSource.exerciseMemo] at the workout record
  /// it was left from (#2332). The server reads the record itself and keeps
  /// only the id or day from it; the demo stores [ref] as given.
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
    TrainerMemoRef? ref,
    TrainerMemoCategory category = TrainerMemoCategory.none,
  });

  /// Rewrites a memo's body, and its [category] when given (#2622). Its
  /// source is never rewritten — nor the category of a memo whose source
  /// fixes it (exercise record, chat insight).
  Future<TrainerMemo> update(
    String clientId,
    String memoId,
    String body, {
    TrainerMemoCategory? category,
  });

  Future<void> delete(String clientId, String memoId);
}

/// Keeps memos in browser-local prefs for the demo build.
///
/// The demo has no account behind it, so there is nowhere else to put them.
/// The insight-id de-duplication is applied here too, which keeps the demo's
/// "메모 추가됨" state stable across rebuilds of the chat screen.
class LocalTrainerMemoRepository implements TrainerMemoRepository {
  const LocalTrainerMemoRepository(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String clientId) => 'trainer_memos:$clientId';

  /// This client's stored memos.
  ///
  /// Always a **fresh growable list**: every caller below sorts, edits or
  /// removes in place. Returning `const []` for the empty cases made the
  /// first read of a client with no memos throw on `..sort()`, so the memo
  /// dialog showed a load failure instead of its empty state (#814).
  List<TrainerMemo> _read(String clientId) {
    final raw = _prefs.getString(_key(clientId));
    if (raw == null) return <TrainerMemo>[];
    try {
      return (jsonDecode(raw) as List<Object?>)
          .map(
            (item) => TrainerMemo.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList();
    } on Object {
      // A payload written by an older build is not worth crashing the
      // screen over — the demo starts from an empty list instead.
      return <TrainerMemo>[];
    }
  }

  Future<void> _write(String clientId, List<TrainerMemo> memos) {
    return _prefs.setString(
      _key(clientId),
      jsonEncode(memos.map((memo) => memo.toJson()).toList()),
    );
  }

  @override
  Future<List<TrainerMemo>> fetch(String clientId) async {
    final memos = _read(clientId)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return memos;
  }

  @override
  Future<TrainerMemo> create(
    String clientId, {
    required String body,
    TrainerMemoSource source = TrainerMemoSource.trainer,
    String? insightId,
    String insightKind = '',
    TrainerMemoRef? ref,
    TrainerMemoCategory category = TrainerMemoCategory.none,
  }) async {
    final memos = _read(clientId);
    if (insightId != null) {
      final existing = memos.where((memo) => memo.insightId == insightId);
      if (existing.isNotEmpty) return existing.first;
    }
    final now = nowKst();
    final memo = TrainerMemo(
      id: 'memo-local-${now.microsecondsSinceEpoch}',
      body: body,
      source: source,
      insightId: insightId,
      insightKind: insightKind,
      ref: ref,
      // 서버와 같은 규칙 — 출처가 분류를 정하면 그것을 쓴다(#2622).
      category: switch (source) {
        TrainerMemoSource.exerciseMemo => TrainerMemoCategory.exercise,
        TrainerMemoSource.chatInsight => TrainerMemoCategory.none,
        TrainerMemoSource.trainer => category,
      },
      createdAt: now,
      updatedAt: now,
    );
    await _write(clientId, <TrainerMemo>[...memos, memo]);
    return memo;
  }

  @override
  Future<TrainerMemo> update(
    String clientId,
    String memoId,
    String body, {
    TrainerMemoCategory? category,
  }) async {
    final memos = _read(clientId);
    final index = memos.indexWhere((memo) => memo.id == memoId);
    // 실서버 구현과 같은 도메인 오류로 던진다 — 리포지토리는 로케일을 모르므로
    // 사람이 읽을 문구는 화면이 붙인다(#501). 문구 없는 [NotFoundError] 는
    // 화면의 지역화된 기본 안내로 떨어진다.
    if (index < 0) throw const NotFoundError();
    final TrainerMemo current = memos[index];
    // 직접 쓴 메모만 분류를 바꾼다 — 실서버는 다른 출처의 변경을 400 으로 막는다.
    if (category != null &&
        category != current.category &&
        current.source != TrainerMemoSource.trainer) {
      throw const ValidationError();
    }
    final updated = current.copyWith(
      body: body,
      category: category,
      updatedAt: nowKst(),
    );
    memos[index] = updated;
    await _write(clientId, memos);
    return updated;
  }

  @override
  Future<void> delete(String clientId, String memoId) async {
    final memos = _read(clientId)..removeWhere((memo) => memo.id == memoId);
    await _write(clientId, memos);
  }
}

/// Provides the [TrainerMemoRepository]: the backend-backed source, or the
/// browser-local one for demo / `USE_MOCK_API=true`.
final trainerMemoRepositoryProvider = Provider<TrainerMemoRepository>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return LocalTrainerMemoRepository(ref.watch(sharedPreferencesProvider));
  }
  return DioTrainerMemoRepository(ref.watch(dioProvider));
});

/// This client's memos, newest first. Invalidate after a write.
final trainerMemosProvider = FutureProvider.autoDispose
    .family<List<TrainerMemo>, String>((ref, clientId) async {
      return ref.watch(trainerMemoRepositoryProvider).fetch(clientId);
    });
