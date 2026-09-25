import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

/// 테스트가 그리는 `전체` 기간의 길이 — 84칸(12주).
///
/// `전체` 는 첫 기록일부터다(#2079). 길이를 상수로 박아 둔 곳은 이제 없고,
/// 화면이 `GET /me/records/span` 을 읽어 정한다. 그래프의 생김새를 보는 테스트는
/// 길이가 고정이어야 하므로, 여기서 첫 기록일을 정해 그만큼을 만든다.
const int kTestAllPeriodDays = 84;

/// [today] 에서 [kTestAllPeriodDays] 칸이 되는 첫 기록일.
DateTime testFirstRecordDate([DateTime? today]) {
  final DateTime day = today ?? nowKst();
  return DateTime(day.year, day.month, day.day - (kTestAllPeriodDays - 1));
}

/// 운동 `전체` 테스트가 쓰는 주 수 — 데모 픽스처가 들고 있는 35주다.
const int kTestAllPeriodWeeks = 35;

/// [today] 에서 [kTestAllPeriodWeeks] 칸이 되는 첫 운동 기록일(그 주 월요일).
DateTime testFirstExerciseRecordDate([DateTime? today]) {
  final DateTime day = today ?? nowKst();
  final DateTime monday = DateTime(
    day.year,
    day.month,
    day.day - (day.weekday - 1),
  );
  return DateTime(
    monday.year,
    monday.month,
    monday.day - (kTestAllPeriodWeeks - 1) * 7,
  );
}

/// 기록 시작일 provider 를 고정한다 — 테스트는 서버를 타지 않는다.
///
/// 주지 않으면 식단·운동 모두 [testFirstRecordDate] 다.
/// 값은 **동기로** 준다 — `async` 로 두면 첫 프레임에 값이 없어 `전체` 가 하루로
/// 그려지고, 값이 온 뒤 다시 그려지며 등장 애니메이션이 처음부터 다시 돈다.
Override testRecordSpanOverride({DateTime? diet, DateTime? exercise}) =>
    recordSpanProvider.overrideWith(
      (Ref ref) => RecordSpan(
        dietFirstDate: diet ?? testFirstRecordDate(),
        exerciseFirstDate: exercise ?? testFirstRecordDate(),
      ),
    );
