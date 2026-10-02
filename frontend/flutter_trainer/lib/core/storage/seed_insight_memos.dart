import 'dart:convert';

import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/features/messages/domain/chat_context_insight.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 데모에서 프로그램 탭의 `최근 7일 확인 필요` 칸이 비어 보이지 않게,
/// 이미 심어 둔 대화의 감지 결과를 메모로 옮겨 둔다 (#1655).
///
/// 지어낸 메모가 아니다 — 채팅 화면이 붉은 배너로 띄우는 것과 **같은 감지**를
/// (`ChatContextInsightDetector`) 같은 요약 규칙으로 옮긴 것이라, 트레이너가
/// 배너의 `메모에 추가` 를 눌렀을 때와 결과가 같다. 그래서 `insightId` 도 그대로
/// 붙는다: 데모에서 그 배너를 눌러도 같은 메모가 두 번 쌓이지 않는다.
///
/// 트레이너가 이미 메모를 손댄 고객은 건드리지 않는다(키가 있으면 통과). 지운
/// 메모가 앱을 다시 열 때마다 되살아나면 그건 데모가 아니라 버그다.
Future<void> seedDemoInsightMemos(
  AppDatabase db,
  SharedPreferences prefs,
  AppLocalizations l,
) async {
  const ChatContextInsightDetector detector = ChatContextInsightDetector();
  final DateTime today = nowKst();
  final DateTime from = DateTime(today.year, today.month, today.day - 6);

  final List<ClientChatMessageRow> rows = await (db.select(
    db.clientChatMessages,
  )..where((t) => t.sender.equals('client'))).get();

  final Map<String, List<TrainerMemo>> byClient = <String, List<TrainerMemo>>{};
  for (final ClientChatMessageRow row in rows) {
    final DateTime at = row.createdAt;
    if (DateTime(at.year, at.month, at.day).isBefore(from)) continue;
    final ChatContextInsight? insight = detector.detect(
      ClientChatMessage(
        id: row.id,
        sender: ChatSender.client,
        body: row.body,
        timeLabel: row.timeLabel,
        createdAt: at,
      ),
    );
    if (insight == null) continue;
    byClient
        .putIfAbsent(row.clientId, () => <TrainerMemo>[])
        .add(
          TrainerMemo(
            id: 'memo-seed-${insight.id}',
            body: chatInsightMemoSummary(l, insight),
            source: TrainerMemoSource.chatInsight,
            insightId: insight.id,
            insightKind: insight.kind.name,
            createdAt: at,
            updatedAt: at,
          ),
        );
  }

  for (final MapEntry<String, List<TrainerMemo>> entry in byClient.entries) {
    final String key = 'trainer_memos:${entry.key}';
    if (prefs.getString(key) != null) continue;
    await prefs.setString(
      key,
      jsonEncode(<Map<String, Object?>>[
        for (final TrainerMemo memo in entry.value) memo.toJson(),
      ]),
    );
  }
}
