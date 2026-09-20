import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_chat_repository.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart'
    show demoUnregisteredClientIdsSnapshot;

/// Reads and sends messages in a trainer↔member chat thread.
///
/// Two implementations sit behind this contract (selected by
/// [chatRepositoryProvider] via [AppConfig.useMockApi]):
///  * [DriftChatRepository] — local drift, demo / `USE_MOCK_API=true`;
///  * [DioChatRepository] — the real FastAPI backend (thread shared with
///    the member app).
///
/// The drift source is reactive (streams re-emit on write); the Dio source
/// emits a single fetch, so callers invalidate the thread/unread providers
/// after send/read (see [ChatView]).
abstract interface class ChatRepository {
  Stream<List<ClientChatMessage>> watchThread(String clientId);

  /// [reportWeekStart]가 있으면 이 메시지는 리포트 PDF 전송 안내다(#1378) —
  /// 데모/드리프트 구현만 이 값을 저장한다. 실서버는 `/report/send-pdf`가
  /// 첨부 메타데이터를 직접 만들어 붙이므로 여기로 오지 않는다.
  /// [emoteId] 를 주면 이모티콘 메시지다(#2020). 트레이너는 이용권 없이 보낸다 —
  /// 이용권은 회원이 포인트를 쓰는 자리다.
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  });
  Stream<Map<String, int>> watchUnreadCounts();
  Future<void> markThreadRead(String clientId);
}

/// Reads and appends messages in a client's chat thread (drift-backed).
class DriftChatRepository implements ChatRepository {
  /// Creates the repository over [_db].
  const DriftChatRepository(this._db);

  final AppDatabase _db;

  /// Streams a client's messages in chronological order.
  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) {
    final query = _db.select(_db.clientChatMessages)
      ..where((t) => t.clientId.equals(clientId))
      ..orderBy(<OrderingTerm Function($ClientChatMessagesTable)>[
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
    return query.watch().asyncMap((rows) async {
      final markers = await _reportWeekStarts(rows.map((r) => r.id));
      return rows.map((row) => _toEntity(row, markers[row.id])).toList();
    });
  }

  /// 이 배치의 메시지 중 리포트 전송 안내인 것의 그 주(YYYY-MM-DD).
  ///
  /// 별도 컬럼 없이 [AppKeyValues] 행 하나로 표시한다(#1378) — 안읽음 마킹과
  /// 같은 방식(위 [watchUnreadCounts] 주석). 스키마 마이그레이션이 없다.
  Future<Map<String, String>> _reportWeekStarts(
    Iterable<String> messageIds,
  ) async {
    final keys = <String>[for (final id in messageIds) '$_reportKeyPrefix$id'];
    if (keys.isEmpty) return const <String, String>{};
    final rows = await (_db.select(
      _db.appKeyValues,
    )..where((t) => t.key.isIn(keys))).get();
    return <String, String>{
      for (final row in rows)
        row.key.substring(_reportKeyPrefix.length): row.value,
    };
  }

  /// Appends a trainer message and refreshes the client's list-card
  /// preview (`lastMessage`/`lastTime`) in one transaction. The `chat-`
  /// id (no `seed-` prefix) means it survives re-seeding, and `now()`
  /// sorts it after the seed thread.
  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
    String? emoteId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && emoteId == null) return;
    final now = nowKst();
    final id = 'chat-$clientId-${now.microsecondsSinceEpoch}';
    await _db.transaction(() async {
      await _db
          .into(_db.clientChatMessages)
          .insert(
            ClientChatMessagesCompanion.insert(
              id: id,
              clientId: clientId,
              sender: 'trainer',
              // 본문은 이모티콘을 그리지 못하는 자리(고객 목록의 마지막
              // 메시지)가 읽는 글이다.
              body: trimmed.isEmpty ? '(이모티콘)' : trimmed,
              timeLabel: _timeLabel(now),
              createdAt: now,
              emoteId: Value<String?>(emoteId),
            ),
          );
      if (reportWeekStart != null) {
        await _db.putValue('$_reportKeyPrefix$id', ymd(reportWeekStart));
      }
      await (_db.update(
        _db.trainerClients,
      )..where((t) => t.id.equals(clientId))).write(
        TrainerClientsCompanion(
          lastMessage: Value(trimmed),
          lastTime: const Value('방금'),
        ),
      );
    });
  }

  /// Per-client unread counts — client-sent messages after the trainer's
  /// last-read marker (an `AppKeyValues` row per client, so no schema
  /// migration). Clients with zero unread are absent.
  ///
  /// 담당을 종료한(미등록) 고객의 메시지는 원본을 지우지 않고 여기서만
  /// 걸러낸다(#1623) — 지우면 사이드바 전체 안읽음 배지가 트레이너가 다시는
  /// 열어 읽을 수 없는 수를 영영 안고 가게 된다.
  @override
  Stream<Map<String, int>> watchUnreadCounts() {
    // The marker is a monotonic `rowid`, not an epoch second: two client
    // messages that land in the same second share a `created_at` value,
    // so a timestamp marker can't tell them apart — after reading the
    // first, the second would look already-read. `rowid` is unique and
    // increasing, so it distinguishes same-second messages (review 241).
    final query = _db.customSelect(
      'SELECT m.client_id AS cid, COUNT(*) AS cnt '
      'FROM client_chat_messages m '
      "LEFT JOIN app_key_values k ON k.\"key\" = '$_readKeyPrefix' || m.client_id "
      "WHERE m.sender = 'client' "
      'AND (k.value IS NULL OR m.rowid > CAST(k.value AS INTEGER)) '
      'GROUP BY m.client_id',
      readsFrom: <ResultSetImplementation<Object?, Object?>>{
        _db.clientChatMessages,
        _db.appKeyValues,
      },
    );
    return query.watch().map((rows) {
      final unregistered = demoUnregisteredClientIdsSnapshot(_db);
      return <String, int>{
        for (final row in rows)
          if (!unregistered.contains(row.read<String>('cid')))
            row.read<String>('cid'): row.read<int>('cnt'),
      };
    });
  }

  /// Marks a client's thread read up to its newest client message.
  ///
  /// Idempotent and write-free when there is nothing new: the marker is
  /// the newest client message's `rowid` (not `now()`), so calling this
  /// again with no new messages computes the same value and skips the
  /// write entirely. That matters because `watchUnreadCounts` watches
  /// `app_key_values` — an unconditional write would emit on that stream
  /// and rebuild the list on every call (review PR 241).
  @override
  Future<void> markThreadRead(String clientId) async {
    final row = await _db
        .customSelect(
          'SELECT MAX(rowid) AS r FROM client_chat_messages '
          "WHERE client_id = ?1 AND sender = 'client'",
          variables: <Variable<Object>>[Variable<String>(clientId)],
          readsFrom: <ResultSetImplementation<Object?, Object?>>{
            _db.clientChatMessages,
          },
        )
        .getSingleOrNull();
    // MAX over no client message returns NULL — nothing could be unread.
    final marker = row?.read<int?>('r');
    if (marker == null) return;

    final key = '$_readKeyPrefix$clientId';
    final stored = int.tryParse(await _db.readValue(key) ?? '');
    if (stored != null && stored >= marker) return; // already read

    await _db.putValue(key, '$marker');
  }

  static const String _readKeyPrefix = 'chat_read_';
  static const String _reportKeyPrefix = 'report_msg_';

  ClientChatMessage _toEntity(ClientChatMessageRow row, String? weekStart) {
    return ClientChatMessage(
      id: row.id,
      sender: row.sender == 'trainer' ? ChatSender.trainer : ChatSender.client,
      body: row.body,
      timeLabel: row.timeLabel,
      createdAt: row.createdAt,
      reportWeekStart: weekStart == null ? null : DateTime.tryParse(weekStart),
      emoteId: row.emoteId,
    );
  }

  static String _timeLabel(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// Provides the [ChatRepository]: the real Dio-backed source (thread shared
/// with the member app) or the local drift source for demo / `USE_MOCK_API`.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return DriftChatRepository(ref.watch(appDatabaseProvider));
  }
  return DioChatRepository(ref.watch(dioProvider));
});

/// Streams per-client unread message counts for the 고객 list badges.
final unreadCountsProvider = StreamProvider.autoDispose<Map<String, int>>((
  ref,
) {
  return ref.watch(chatRepositoryProvider).watchUnreadCounts();
});

/// Streams a client's chat thread by client id.
final chatThreadProvider = StreamProvider.autoDispose
    .family<List<ClientChatMessage>, String>((ref, clientId) {
      return ref.watch(chatRepositoryProvider).watchThread(clientId);
    });
