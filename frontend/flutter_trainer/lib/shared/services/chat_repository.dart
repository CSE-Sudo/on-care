import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_chat_repository.dart';
import 'package:oncare_trainer/features/clients/domain/chat_thread_paging.dart';
import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart'
    show clientsProvider, demoUnregisteredClientIdsSnapshot;
import 'package:oncare_trainer/shared/services/demo_chat_files.dart';
import 'package:oncare_trainer/shared/utils/roster_unread.dart';

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
  /// 대화의 **최신 쪽**(최대 [chatPageSize] 건, 오래된→최신). (#2749)
  ///
  /// 서버는 대화 전부가 아니라 최신 한 쪽만 준다. 그 앞은 [fetchOlder] 로
  /// 이어 받고, 화면은 둘을 [mergeChatThread] 로 합쳐 그린다.
  Stream<List<ClientChatMessage>> watchThread(String clientId);

  /// [before] 보다 앞선 한 쪽 — 그 앞의 최신 [chatPageSize] 건(오래된→최신).
  /// (#2749)
  ///
  /// [before] 는 지금 가진 가장 오래된 메시지다. 서버 커서와 같이 시각과 id 를
  /// 함께 본다. 받은 것이 [chatPageSize] 건보다 적으면 그 앞에는 없다.
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  });

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

  /// Streams the newest page of a client's messages in chronological order.
  ///
  /// 서버와 같은 계약이다(#2749) — 최신 [chatPageSize] 건만 흘리고, 그 앞은
  /// [fetchOlder] 로 준다. 데모가 언제나 전부를 주면 쪽 사이의 경계가 데모에서만
  /// 없어 보여, 이어 받기가 데모로는 확인되지 않는다.
  @override
  Stream<List<ClientChatMessage>> watchThread(String clientId) {
    final query = _db.select(_db.clientChatMessages)
      ..where((t) => t.clientId.equals(clientId))
      ..orderBy(_newestFirst)
      ..limit(chatPageSize);
    return query.watch().asyncMap(
      (rows) => _toEntities(rows.reversed.toList(growable: false)),
    );
  }

  /// [before] 앞의 한 쪽. 서버의 (`created_at`, `id`) 복합 커서와 같은 경계다.
  @override
  Future<List<ClientChatMessage>> fetchOlder(
    String clientId, {
    required ClientChatMessage before,
  }) async {
    final query = _db.select(_db.clientChatMessages)
      ..where(
        (t) =>
            t.clientId.equals(clientId) &
            (t.createdAt.isSmallerThanValue(before.createdAt) |
                (t.createdAt.equals(before.createdAt) &
                    t.id.isSmallerThanValue(before.id))),
      )
      ..orderBy(_newestFirst)
      ..limit(chatPageSize);
    final rows = await query.get();
    return _toEntities(rows.reversed.toList(growable: false));
  }

  /// 최신 것부터 — 같은 시각이면 id 로 가른다([compareChatMessages] 의 반대).
  static final List<OrderingTerm Function($ClientChatMessagesTable)>
  _newestFirst = <OrderingTerm Function($ClientChatMessagesTable)>[
    (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
  ];

  /// 행(오래된→최신)을 첨부 표시와 함께 메시지로 푼다.
  Future<List<ClientChatMessage>> _toEntities(
    List<ClientChatMessageRow> rows,
  ) async {
    final ids = rows.map((r) => r.id).toList();
    final weeks = await _markers(_reportKeyPrefix, ids);
    final images = await _markers(_imageKeyPrefix, ids);
    // 회원이 보낸 것으로 시드한 사진·PDF(#2669).
    final files = <String, ChatAttachment>{};
    for (final MapEntry<String, String> e in (await _markers(
      demoChatFileKeyPrefix,
      ids,
    )).entries) {
      final ChatAttachment? file =
          _demoImages[e.key] ?? await decodeDemoChatFile(e.key, e.value);
      if (file == null) continue;
      files[e.key] = _demoImages[e.key] = file;
    }
    return rows
        .map(
          (row) => _toEntity(
            row,
            weeks[row.id],
            files[row.id] ?? _imageAttachment(row.id, images[row.id]),
          ),
        )
        .toList();
  }

  /// 이 배치의 메시지 중 [prefix] 표시가 붙은 것의 값.
  ///
  /// 별도 컬럼 없이 [AppKeyValues] 행 하나로 표시한다(#1378) — 안읽음 마킹과
  /// 같은 방식(위 [watchUnreadCounts] 주석). 스키마 마이그레이션이 없다.
  /// 리포트 전송 안내는 그 주(YYYY-MM-DD)를, 사진은 파일 이름과 바이트를 담는다.
  Future<Map<String, String>> _markers(
    String prefix,
    List<String> messageIds,
  ) async {
    final keys = <String>[for (final id in messageIds) '$prefix$id'];
    if (keys.isEmpty) return const <String, String>{};
    final rows = await (_db.select(
      _db.appKeyValues,
    )..where((t) => t.key.isIn(keys))).get();
    return <String, String>{
      for (final row in rows) row.key.substring(prefix.length): row.value,
    };
  }

  /// 데모 대화에 붙은 사진 표시를 첨부로 푼다. (#2493)
  ///
  /// 한 번 푼 것은 메시지 id 로 들고 있는다. 스레드는 메시지가 오갈 때마다 다시
  /// 흘러오는데, 그때마다 새 바이트 배열을 만들면 화면이 같은 사진을 매번 새로
  /// 디코딩해 깜빡인다.
  ChatAttachment? _imageAttachment(String messageId, String? stored) {
    if (stored == null) return null;
    final cached = _demoImages[messageId];
    if (cached != null) return cached;
    final Uint8List bytes;
    final String fileName;
    try {
      final decoded = jsonDecode(stored) as Map<String, Object?>;
      fileName = decoded['name'] as String? ?? 'photo.jpg';
      bytes = base64Decode(decoded['data'] as String? ?? '');
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    final fileId = 'demo-photo-$messageId';
    return _demoImages[messageId] = ChatAttachment(
      kind: ChatAttachmentKind.image,
      fileName: fileName,
      fileId: fileId,
      fileSize: bytes.length,
      downloadPath: '/chat/attachments/$fileId',
      localBytes: bytes,
    );
  }

  /// 데모 트레이너가 고른 사진 한 장을 대화에 붙인다. (#2493)
  ///
  /// 데모에는 받아 줄 서버가 없어, 바이트를 로컬 DB 에 표시 행으로 함께 둔다 —
  /// 메모리에만 두면 새로고침한 뒤 말풍선만 남고 사진은 "불러오지 못했어요" 가
  /// 된다. [message] 는 비어도 된다(실서버 `/chat/image` 와 같다).
  Future<void> sendTrainerImage({
    required String clientId,
    required Uint8List bytes,
    required String fileName,
    String message = '',
  }) async {
    final caption = message.trim();
    final now = nowKst();
    final id = 'chat-$clientId-${now.microsecondsSinceEpoch}';
    // 한 트랜잭션으로 묶는다 — 스레드는 커밋 뒤에 다시 흘러오므로, 사진 없는
    // 빈 말풍선이 한 번 스치지 않는다.
    await _db.transaction(() async {
      await _db.putValue(
        '$_imageKeyPrefix$id',
        jsonEncode(<String, String>{
          'name': fileName,
          'data': base64Encode(bytes),
        }),
      );
      await _db
          .into(_db.clientChatMessages)
          .insert(
            ClientChatMessagesCompanion.insert(
              id: id,
              clientId: clientId,
              sender: 'trainer',
              body: caption,
              timeLabel: _timeLabel(now),
              createdAt: now,
            ),
          );
      await (_db.update(
        _db.trainerClients,
      )..where((t) => t.id.equals(clientId))).write(
        TrainerClientsCompanion(
          lastMessage: Value(caption.isEmpty ? ChatPreviewCode.photo : caption),
          lastTime: const Value(ChatPreviewCode.justNow),
        ),
      );
    });
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
              // 글 없는 이모티콘은 본문을 비워 둔다. 대화는 그림을 그리고,
              // 고객 목록은 아래의 [ChatPreviewCode.emote] 로 로케일 문구를
              // 그린다 — 본문에 한국어를 적어 두면 영어 화면에도 남는다.
              body: trimmed,
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
          lastMessage: Value(trimmed.isEmpty ? ChatPreviewCode.emote : trimmed),
          lastTime: const Value(ChatPreviewCode.justNow),
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
  static const String _imageKeyPrefix = 'chat_image_';

  /// 풀어 둔 데모 사진·파일. 메시지 id 가 키다([_imageAttachment]).
  static final Map<String, ChatAttachment> _demoImages =
      <String, ChatAttachment>{};

  ClientChatMessage _toEntity(
    ClientChatMessageRow row,
    String? weekStart,
    ChatAttachment? attachment,
  ) {
    return ClientChatMessage(
      id: row.id,
      sender: row.sender == 'trainer' ? ChatSender.trainer : ChatSender.client,
      body: row.body,
      timeLabel: row.timeLabel,
      createdAt: row.createdAt,
      attachment: attachment,
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
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
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

/// 명단 회원만 더한 안읽음 합계 — 사이드바 배지가 읽는다. (#2868)
///
/// 명단(`clientsProvider`)이나 안읽음 맵이 아직 없으면 `null` — 사이드바는
/// 배지를 그리지 않고 기다린다. 대시보드·메시지 탭은 이미 명단을 들고 있어
/// [rosterUnreadOf] 를 직접 부른다.
final rosterUnreadProvider = Provider.autoDispose<RosterUnread?>((ref) {
  final unread = ref.watch(unreadCountsProvider).valueOrNull;
  final clients = ref.watch(clientsProvider).valueOrNull;
  if (unread == null || clients == null) return null;
  return rosterUnreadOf(
    rosterIds: clients.map((client) => client.id),
    unread: unread,
  );
});
