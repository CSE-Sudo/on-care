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

  group('남겨 둔 감지가 없는 옛 리포트 (#3349)', () {
    ChatInsightHistory history(List<ChatInsightRecord> records) =>
        ChatInsightHistory(records: records);

    test('감지 창 안의 주는 지금의 기록에서 센다', () {
      final List<String>? lines = liveInsightLines(
        l,
        history(<ChatInsightRecord>[at('2026-09-16T03:00:00Z')]),
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 24, 21),
      );
      expect(lines, <String>['무릎 통증 감지 1회']);
    });

    test('창 안인데 감지가 없으면 빈 목록이다 — 감지가 없던 주다', () {
      expect(
        liveInsightLines(
          l,
          history(const <ChatInsightRecord>[]),
          DateTime(2026, 9, 14),
          DateTime(2026, 9, 24, 21),
        ),
        isEmpty,
      );
    });

    test('창 밖의 주는 알 수 없다 — "감지 없음" 이 아니라 칸을 비운다', () {
      expect(
        liveInsightLines(
          l,
          history(const <ChatInsightRecord>[]),
          DateTime(2026, 9, 14),
          DateTime(2026, 11, 2, 9),
        ),
        isNull,
      );
    });

    test('월요일이 창의 첫 순간보다 앞이면 한 주가 다 들지 않아 알 수 없다', () {
      // 창은 30일 — 10/14 12시에 읽으면 9/14 12시부터다. 9/14 월요일 0시는 그 앞이다.
      final List<ChatInsightRecord> records = <ChatInsightRecord>[
        at('2026-09-16T03:00:00Z'),
      ];
      expect(
        liveInsightLines(
          l,
          history(records),
          DateTime(2026, 9, 14),
          DateTime(2026, 10, 14, 12),
        ),
        isNull,
      );
      expect(
        liveInsightLines(
          l,
          history(records),
          DateTime(2026, 9, 14),
          DateTime(2026, 10, 14),
        ),
        <String>['무릎 통증 감지 1회'],
      );
    });

    test('서버가 알려 준 창 길이를 따른다', () {
      expect(
        liveInsightLines(
          l,
          const ChatInsightHistory(windowDays: 7),
          DateTime(2026, 9, 14),
          DateTime(2026, 9, 24, 21),
        ),
        isNull,
      );
    });
  });
}
