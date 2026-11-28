import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_weekly_reports.dart';

/// 데모의 주간 리포트 교환이 살 때의 감지 기록을 남긴다. (#3349)
///
/// 실서버가 구매 기록에 굳히는 것과 같다 — 감지 기록은 최근 대화에서 매번 계산하는
/// 값이라, 남겨 두지 않으면 한 달 뒤에 연 리포트에서 사라진다.
void main() {
  // 9/15(화) — 받는 주는 지난주 9/7(월)~9/13(일)이다.
  final DateTime now = DateTime(2026, 9, 15, 10);

  DemoWeeklyReportBook book() => DemoWeeklyReportBook(
    ledger: DemoPointsLedger(openingBalance: 1000),
    now: () => now,
    hasTrainer: () => false,
  );

  Map<String, Object?> row(String createdAt, {String part = '무릎'}) =>
      <String, Object?>{
        'message_id': createdAt,
        'created_at': createdAt,
        'kind': 'discomfort',
        'body_part': part,
        'text': '$part이 아파요',
      };

  List<Object?> insightsOf(DemoWeeklyReportBook b) =>
      ((b.listJson()['reports']! as List<Object?>).single!
              as Map<String, Object?>)['insights']!
          as List<Object?>;

  test('받는 주의 감지만, 오래된 것 먼저, 문장 없이 남긴다', () {
    final DemoWeeklyReportBook b = book();
    b.exchange(
      insights: <Map<String, Object?>>[
        row('2026-09-14T03:00:00Z', part: '손목'), // 이번 주 — 뺀다
        row('2026-09-11T03:00:00Z', part: '허리'),
        row('2026-09-06T15:00:00Z'), // 9/7 월요일 0시(KST) — 그 주 첫 순간
        row('2026-09-06T14:59:00Z', part: '어깨'), // 9/6 일요일 — 앞 주
      ],
    );

    expect(insightsOf(b), <Map<String, Object?>>[
      <String, Object?>{
        'kind': 'discomfort',
        'body_part': '무릎',
        'created_at': '2026-09-06T15:00:00Z',
      },
      <String, Object?>{
        'kind': 'discomfort',
        'body_part': '허리',
        'created_at': '2026-09-11T03:00:00Z',
      },
    ]);
  });

  test('감지가 없던 주는 빈 목록으로 남는다 — 모르는 것(null)과 다르다', () {
    final DemoWeeklyReportBook b = book()..exchange();
    expect(insightsOf(b), isEmpty);
  });

  test('새로고침 뒤에도 남긴 감지가 그대로다', () {
    final DemoWeeklyReportBook first = book()
      ..exchange(insights: <Map<String, Object?>>[row('2026-09-11T03:00:00Z')]);
    final DemoWeeklyReportBook restored = book()..restore(first.toJson());

    expect(insightsOf(restored), insightsOf(first));
    expect(insightsOf(restored), hasLength(1));
  });

  test('감지를 남기기 전에 받은 주는 되살려도 모르는 것으로 나간다', () {
    final DemoWeeklyReportBook restored = book()
      ..restore(<String, Object?>{
        'sequence': 1,
        'weeks': <Map<String, Object?>>[
          <String, Object?>{
            'week_start': DateTime(2026, 9, 7).toIso8601String(),
            'purchased_at': DateTime(2026, 9, 15, 9).toIso8601String(),
          },
        ],
      });

    final Map<String, Object?> listed =
        (restored.listJson()['reports']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(listed.containsKey('insights'), isTrue);
    expect(listed['insights'], isNull);
  });

  test('같은 요청의 재시도는 처음 남긴 감지를 바꾸지 않는다', () {
    final DemoWeeklyReportBook b = book()
      ..exchange(
        clientRequestId: 'req-1',
        insights: <Map<String, Object?>>[row('2026-09-11T03:00:00Z')],
      )
      ..exchange(clientRequestId: 'req-1');
    expect(insightsOf(b), hasLength(1));
  });
}
