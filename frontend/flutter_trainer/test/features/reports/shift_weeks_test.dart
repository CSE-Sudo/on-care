/// 리포트의 주 이동 — 서머타임이 있는 시간대에서도 정확히 한 주씩. (#2774)
///
/// 서머타임이 시작된 주는 168시간이 아니라 167시간이다. 월요일 0시에서
/// `Duration(days: 7)` 을 빼면 전 주 월요일이 아니라 그 전날 일요일 23시가 되고,
/// 그 날짜는 2주 전 주에 속한다. 그래서 PDF 전주 비교와 칼로리 기준선이 엉뚱한
/// 주를 읽었다.
///
/// 결과는 연·월·일로 견준다 — 테스트를 돌리는 곳의 시간대와 상관없이 같은 답이
/// 나와야 한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

final TrainerClient _client = makeClient();

void main() {
  group('shiftWeeks', () {
    test('미국 서머타임 시작 주(2026-03-08)를 넘어 정확히 직전 월요일로 간다', () {
      expect(ymd(shiftWeeks(DateTime(2026, 3, 9), -1)), '2026-03-02');
      expect(ymd(shiftWeeks(DateTime(2026, 3, 16), -1)), '2026-03-09');
    });

    test('유럽 서머타임 시작 주(2026-03-29)를 넘어 정확히 직전 월요일로 간다', () {
      expect(ymd(shiftWeeks(DateTime(2026, 3, 30), -1)), '2026-03-23');
      expect(ymd(shiftWeeks(DateTime(2026, 4, 6), -2)), '2026-03-23');
    });

    test('서머타임이 끝나는 주를 넘어 앞으로 가도 정확히 다음 월요일이다', () {
      // 미국 2026-11-01, 유럽 2026-10-25.
      expect(ymd(shiftWeeks(DateTime(2026, 10, 26), 1)), '2026-11-02');
      expect(ymd(shiftWeeks(DateTime(2026, 10, 19), 1)), '2026-10-26');
    });

    test('여러 주를 뒤로 가면 주마다 서로 다른 월요일이 하나씩 나온다', () {
      final DateTime week = DateTime(2026, 3, 23);
      final List<String> back = <String>[
        for (int n = 1; n <= 4; n++) ymd(shiftWeeks(week, -n)),
      ];

      expect(back, <String>[
        '2026-03-16',
        '2026-03-09',
        '2026-03-02',
        '2026-02-23',
      ]);
    });

    test('달·해 경계를 넘는다', () {
      expect(ymd(shiftWeeks(DateTime(2026, 1, 5), -1)), '2025-12-29');
      expect(ymd(shiftWeeks(DateTime(2025, 12, 29), 1)), '2026-01-05');
    });

    test('주 중간 날짜를 받으면 그 주 월요일 기준으로 옮긴다', () {
      final DateTime moved = shiftWeeks(DateTime(2026, 3, 12, 15, 30), -1);

      expect(ymd(moved), '2026-03-02');
      expect(moved.weekday, DateTime.monday);
      expect(moved.hour, 0);
    });

    test('0 주는 그 주 월요일이다 — KST 결과는 이전과 같다', () {
      final DateTime monday = DateTime(2026, 8, 10);

      expect(shiftWeeks(monday, 0), monday);
      expect(
        shiftWeeks(monday, -1),
        monday.subtract(const Duration(days: 7)),
        reason: '서머타임이 없는 곳에서는 예전 계산과 같은 날이다',
      );
    });
  });

  group('WeeklyReport.weekEnd', () {
    test('서머타임 전환이 있는 주에도 그 주 일요일이다', () {
      for (final DateTime monday in <DateTime>[
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 23),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
      ]) {
        final WeeklyReport report = WeeklyReport(
          client: _client,
          weekStart: monday,
          sessionsBooked: 0,
          sessionsDone: 0,
          completionAvg: null,
          sodiumOverDays: 0,
          sodiumAvg: null,
          isCurrentWeek: false,
        );
        expect(report.weekEnd.weekday, DateTime.sunday, reason: ymd(monday));
        expect(report.weekEnd.hour, 0, reason: ymd(monday));
      }
    });
  });

  test('리포트 코드에 Duration 으로 주를 옮기는 곳이 남지 않는다', () {
    // `x.subtract(Duration(days: 7 * n))` · `x.add(const Duration(days: 7))`
    // 처럼 주 단위로 옮기는 호출만 잡는다. 설명 주석의 인용은 대상이 아니다.
    final RegExp weekByDuration = RegExp(
      r'\.(add|subtract)\(\s*(const\s+)?Duration\(\s*days:\s*7',
    );
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib/features/reports',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String source = entity.readAsStringSync();
      if (weekByDuration.hasMatch(source)) {
        offenders.add(entity.path.replaceAll(r'\', '/'));
      }
    }

    expect(offenders, isEmpty);
  });
}
