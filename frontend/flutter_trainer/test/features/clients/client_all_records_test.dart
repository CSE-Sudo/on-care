/// 트레이너 웹 `전체` 도 **모든 기록**을 그린다. (#2079)
///
/// 회원 앱과 같은 회원의 같은 이력을 두 화면이 다른 길이로 말하면 안 된다
/// (#1170 에서 겪은 일이다). 시작점은 그 회원의 첫 기록일이고, 식단과 운동이
/// 각자 제 첫 기록일을 가진다 — 운동만 해 온 회원의 식단 그래프가 빈 칸으로
/// 길어지지 않게.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';

void main() {
  final DateTime today = DateTime(2026, 9, 24);

  group('식단 `전체`', () {
    test('첫 기록일부터 오늘까지다 — 1년을 넘겨도 자르지 않는다', () {
      final ClientDateRange range = clientRangeFor(
        ClientPeriod.month,
        today,
        firstRecord: DateTime(2024, 5, 2),
      );

      expect(range.from, DateTime(2024, 5, 2));
      expect(range.to, today);
    });

    test('첫 기록일이 없으면 오늘 하루다', () {
      final ClientDateRange range = clientRangeFor(ClientPeriod.month, today);

      expect(range.from, today);
      expect(range.to, today);
    });

    test('첫 기록일이 오늘보다 뒤면 오늘 하루로 본다', () {
      final ClientDateRange range = clientRangeFor(
        ClientPeriod.month,
        today,
        firstRecord: DateTime(2027),
      );

      expect(range.from, today);
    });
  });

  group('운동 `전체`', () {
    test('첫 기록 주의 월요일부터다 — 주 한가운데 기록도 그 주가 한 칸이다', () {
      final ClientDateRange range = clientRangeFor(
        ClientPeriod.month,
        today,
        exercise: true,
        // 2026-06-03 은 수요일이다.
        firstRecord: DateTime(2026, 6, 3),
      );

      expect(range.from, DateTime(2026, 6));
      expect(range.from.weekday, DateTime.monday);
      expect(range.to, today);
    });

    test('첫 기록일이 없으면 이번 주 한 주다', () {
      final ClientDateRange range = clientRangeFor(
        ClientPeriod.month,
        today,
        exercise: true,
      );

      expect(range.from, DateTime(2026, 9, 21));
      expect(clientRangeWeekStarts(range).length, 1);
    });
  });

  group('기록 시작일 응답', () {
    test('식단·운동이 각자 제 날짜를 가진다', () {
      final ClientRecordSpan span = ClientRecordSpan.fromJson(<String, Object?>{
        'diet_first_date': '2026-05-04',
        'exercise_first_date': '2026-07-13',
      });

      expect(span.dietFirstDate, DateTime(2026, 5, 4));
      expect(span.exerciseFirstDate, DateTime(2026, 7, 13));
    });

    test('기록이 없으면 null 이다 — 오늘로 지어내지 않는다', () {
      final ClientRecordSpan span = ClientRecordSpan.fromJson(<String, Object?>{
        'diet_first_date': null,
        'exercise_first_date': null,
      });

      expect(span.dietFirstDate, isNull);
      expect(span.exerciseFirstDate, isNull);
      expect(ClientRecordSpan.empty.dietFirstDate, isNull);
    });
  });
}
