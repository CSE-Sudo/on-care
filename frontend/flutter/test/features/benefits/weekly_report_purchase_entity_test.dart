import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_report_purchase.dart';

/// 포인트로 받은 리포트 목록이 살 때의 감지 기록을 싣는다. (#3349)
///
/// 감지가 없던 주(빈 목록)와 남겨 둔 것이 없는 주(null)를 가르는 것이 핵심이다 —
/// 섞이면 옛 리포트가 "감지된 것이 없어요" 로 열린다.
void main() {
  Map<String, Object?> listOf(List<Map<String, Object?>> reports) =>
      <String, Object?>{
        'reports': reports,
        'next_week_start': '2026-09-21',
        'cost': 300,
      };

  test('살 때의 감지 기록을 주별로 읽는다', () {
    final WeeklyReportPurchases purchases = WeeklyReportPurchases.fromJson(
      listOf(<Map<String, Object?>>[
        <String, Object?>{
          'week_start': '2026-09-14',
          'purchased_at': '2026-09-21T01:00:00Z',
          'insights': <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'discomfort',
              'body_part': '무릎',
              'created_at': '2026-09-16T03:00:00Z',
            },
            <String, Object?>{
              'kind': 'negative_feedback',
              'body_part': null,
              'created_at': '2026-09-18T03:00:00Z',
            },
          ],
        },
      ]),
    );

    final List<ChatInsightRecord> kept = purchases.insightsOf(
      DateTime(2026, 9, 14),
    )!;
    expect(kept, hasLength(2));
    expect(kept.first.insight.kind, ChatInsightKind.discomfort);
    expect(kept.first.insight.bodyPart, '무릎');
    expect(kept.first.createdAt, DateTime(2026, 9, 16, 12));
    expect(kept.last.insight.kind, ChatInsightKind.negativeFeedback);
  });

  test('감지가 없던 주는 빈 목록, 남겨 둔 것이 없는 주는 null 이다', () {
    final WeeklyReportPurchases purchases = WeeklyReportPurchases.fromJson(
      listOf(<Map<String, Object?>>[
        <String, Object?>{
          'week_start': '2026-09-14',
          'purchased_at': '2026-09-21T01:00:00Z',
          'insights': <Object?>[],
        },
        <String, Object?>{
          'week_start': '2026-09-07',
          'purchased_at': '2026-09-14T01:00:00Z',
          'insights': null,
        },
        // 옛 서버 — 칸 자체가 없다.
        <String, Object?>{
          'week_start': '2026-08-31',
          'purchased_at': '2026-09-07T01:00:00Z',
        },
      ]),
    );

    expect(purchases.weeks, <DateTime>[
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 7),
      DateTime(2026, 8, 31),
    ]);
    expect(purchases.insightsOf(DateTime(2026, 9, 14)), isEmpty);
    expect(purchases.insightsOf(DateTime(2026, 9, 7)), isNull);
    expect(purchases.insightsOf(DateTime(2026, 8, 31)), isNull);
  });

  test('모르는 종류의 감지는 건너뛰고 나머지는 읽는다', () {
    final WeeklyReportPurchases purchases = WeeklyReportPurchases.fromJson(
      listOf(<Map<String, Object?>>[
        <String, Object?>{
          'week_start': '2026-09-14',
          'purchased_at': '2026-09-21T01:00:00Z',
          'insights': <Object?>[
            <String, Object?>{
              'kind': 'something_new',
              'created_at': '2026-09-16T03:00:00Z',
            },
            'not a row',
            <String, Object?>{
              'kind': 'discomfort',
              'created_at': '2026-09-16T03:00:00Z',
            },
          ],
        },
      ]),
    );
    expect(purchases.insightsOf(DateTime(2026, 9, 14)), hasLength(1));
  });

  test('주를 시각이 붙은 값으로 물어도 그 날짜로 찾는다', () {
    final WeeklyReportPurchases purchases = WeeklyReportPurchases.fromJson(
      listOf(<Map<String, Object?>>[
        <String, Object?>{
          'week_start': '2026-09-14',
          'purchased_at': '2026-09-21T01:00:00Z',
          'insights': <Object?>[],
        },
      ]),
    );
    expect(purchases.insightsOf(DateTime(2026, 9, 14, 15, 30)), isEmpty);
  });
}
