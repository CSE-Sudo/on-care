import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/benefits/presentation/widgets/purchased_report_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 포인트로 받은 리포트의 감지 기록은 그 주(KST 월~일) 것만 싣는다. (#2022)
///
/// 기록은 실제처럼 [ChatInsightRecord.fromJson] 을 거쳐 만든다 — 엔티티는 서버의
/// UTC 를 KST 벽시계(UTC 아님)로 바꿔 담으므로, UTC 값을 그대로 넣으면 실제와
/// 모양이 달라 기기 시간대에 기대는 오류를 놓친다(#3098).
void main() {
  ChatInsightRecord at(String utc) =>
      ChatInsightRecord.fromJson(<String, Object?>{
        'message_id': utc,
        'created_at': utc,
        'kind': 'discomfort',
        'body_part': '무릎',
        'text': '무릎이 아파요',
      })!;

  final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));

  test('KST 로 날짜를 잘라 그 주 것만 종류별 횟수로 센다', () {
    final List<String> lines = weeklyInsightLines(l, <ChatInsightRecord>[
      at('2026-09-16T03:00:00Z'), // 9/16 12시
      at('2026-09-13T16:00:00Z'), // 9/14 월요일 1시 — 그 주 첫날
      at('2026-09-13T14:00:00Z'), // 9/13 일요일 23시 — 앞 주
      at('2026-09-20T15:00:00Z'), // 9/21 월요일 0시 — 다음 주
    ], DateTime(2026, 9, 14));

    expect(lines, <String>['무릎 통증 감지 2회']);
  });

  test('일요일 15시(KST) 이후 감지는 기기 시간대와 상관없이 그 주에 든다 (#3098)', () {
    // 9/20 06:00Z = 일요일 15:00 KST. 예전에는 KST 벽시계를 다시 toUtc() 로
    // 옮겨 기기가 UTC 면 월요일 0시로 밀려 다음 주에 들어갔다.
    final List<ChatInsightRecord> records = <ChatInsightRecord>[
      at('2026-09-20T06:00:00Z'),
      at('2026-09-20T14:59:00Z'), // 일요일 23:59 KST
    ];

    expect(weeklyInsightLines(l, records, DateTime(2026, 9, 14)), <String>[
      '무릎 통증 감지 2회',
    ]);
    expect(weeklyInsightLines(l, records, DateTime(2026, 9, 21)), isEmpty);
  });

  test('월요일 0시(KST) 감지는 다음 주에 든다', () {
    final List<ChatInsightRecord> records = <ChatInsightRecord>[
      at('2026-09-20T15:00:00Z'),
    ];

    expect(weeklyInsightLines(l, records, DateTime(2026, 9, 14)), isEmpty);
    expect(weeklyInsightLines(l, records, DateTime(2026, 9, 21)), <String>[
      '무릎 통증 감지 1회',
    ]);
  });
}
