import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/benefits/presentation/widgets/purchased_report_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 포인트로 받은 리포트의 감지 기록은 그 주(KST 월~일) 것만 싣는다. (#2022)
void main() {
  ChatInsightRecord at(DateTime utc) => ChatInsightRecord(
    messageId: utc.toIso8601String(),
    createdAt: utc,
    insight: const ChatInsight(
      kind: ChatInsightKind.discomfort,
      bodyPart: '무릎',
    ),
    text: '무릎이 아파요',
  );

  test('KST 로 날짜를 잘라 그 주 것만 종류별 횟수로 센다', () {
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    final List<String> lines = weeklyInsightLines(l, <ChatInsightRecord>[
      at(DateTime.utc(2026, 9, 16, 3)), // 9/16 12시
      at(DateTime.utc(2026, 9, 13, 16)), // 9/14 월요일 1시 — 그 주 첫날
      at(DateTime.utc(2026, 9, 13, 14)), // 9/13 일요일 23시 — 앞 주
      at(DateTime.utc(2026, 9, 20, 15)), // 9/21 월요일 0시 — 다음 주
    ], DateTime(2026, 9, 14));

    expect(lines, <String>['무릎 통증 감지 2회']);
  });
}
