import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// 테스트가 그리는 `전체` 식단 기간의 길이 — 84칸(12주).
///
/// `전체` 는 첫 기록일부터다(#2079). 길이를 상수로 박아 둔 곳은 이제 없고,
/// 화면이 `GET /trainer/clients/{id}/records/span` 을 읽어 정한다. 그래프의
/// 생김새를 보는 테스트는 길이가 고정이어야 하므로 여기서 첫 기록일을 정한다.
const int kTestClientAllPeriodDays = 84;

/// 테스트가 그리는 `전체` 운동 기간의 주 수 — 35주. 데모 픽스처가 들고 있는
/// 기간과 같다.
const int kTestClientAllExerciseWeeks = 35;

/// [today] 에서 [kTestClientAllPeriodDays] 칸이 되는 첫 식단 기록일.
DateTime testClientDietFirstDate([DateTime? today]) {
  final DateTime day = today ?? todayKst();
  return DateTime(
    day.year,
    day.month,
    day.day - (kTestClientAllPeriodDays - 1),
  );
}

/// [today] 에서 [kTestClientAllExerciseWeeks] 칸이 되는 첫 운동 기록일.
DateTime testClientExerciseFirstDate([DateTime? today]) {
  final DateTime monday = clientMondayOf(today ?? todayKst());
  return DateTime(
    monday.year,
    monday.month,
    monday.day - (kTestClientAllExerciseWeeks - 1) * 7,
  );
}

/// 대역 저장소가 돌려줄 기록 시작일.
ClientRecordSpan testClientRecordSpan({DateTime? diet, DateTime? exercise}) =>
    ClientRecordSpan(
      dietFirstDate: diet ?? testClientDietFirstDate(),
      exerciseFirstDate: exercise ?? testClientExerciseFirstDate(),
    );

/// 기록 시작일 provider 를 고정한다 — 값은 **동기로** 준다. `async` 로 두면 첫
/// 프레임에 값이 없어 `전체` 가 하루(운동은 한 주)로 그려진다.
Override testClientRecordSpanOverride({
  DateTime? diet,
  DateTime? exercise,
  String clientId = '',
}) => clientId.isEmpty
    ? clientRecordSpanProvider.overrideWith(
        (Ref ref, String _) =>
            testClientRecordSpan(diet: diet, exercise: exercise),
      )
    : clientRecordSpanProvider(clientId).overrideWith(
        (Ref ref) => testClientRecordSpan(diet: diet, exercise: exercise),
      );
