import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

/// provider 하나를 비우는 함수 — `WidgetRef.invalidate`·`Ref.invalidate`·
/// `ProviderContainer.invalidate` 를 그대로 넘긴다.
typedef ProviderInvalidator = void Function(ProviderOrFamily provider);

/// 운동 기록이 바뀐 뒤 함께 달라지는 것들. (#2629, #2631, #2634)
///
/// 테스트가 대상 목록을 그대로 확인할 수 있도록 밖에 둔다.
final List<ProviderOrFamily> kExerciseChangeRefreshTargets = <ProviderOrFamily>[
  // 이번 주 — 목록·통계·그래프. `전체` 그래프도 이 값을 watch 한다.
  exerciseWeekProvider,
  // 지난 주 — 지난 주 하루 화면과 주간 리포트의 지난 주 집계(#2629).
  // 수정은 옛 날짜와 새 날짜가 다른 주일 수 있어 family 전체를 비운다.
  // 화면에 붙어 있는 주만 다시 읽히고, 나머지는 다음에 볼 때 읽힌다.
  exercisePastWeekProvider,
  // AI 맞춤 조언 — 기간마다 따로 선 값 전부(#2631).
  exerciseAdviceProvider,
  // MY 기록 달력과 연속 기록 보호권(#1788, #2075, #2634).
  activityCalendarProvider,
  myStreakShieldsProvider,
  // 포인트 잔액(#1786)과 주간 챌린지 진행 — 운동한 날 수(#1789, #2634).
  myHealthStateProvider,
  weeklyChallengeProvider,
  // 첫 기록일 — 더 이른 날짜로 적거나 첫 기록을 지우면 `전체` 가 달라진다.
  recordSpanProvider,
];

/// 운동 기록을 **저장·수정·삭제**하거나 추천 개인운동을 **완료·완료 취소**한
/// 뒤에 부른다. (#2634)
///
/// 예전에는 경로마다 비울 목록을 따로 적어, 저장은 활동 달력을 비우는데 삭제는
/// 빠지고, 새 추가만 주간 챌린지를 비우고 날짜를 옮긴 수정은 빠지는 식으로
/// 한쪽씩 어긋났다. 다섯 경로가 이 함수 하나를 부르면 빠지는 자리가 없다.
///
/// 보고 있는 화면이 없는 provider 는 비워도 요청이 나가지 않는다 — 한 번에
/// 비워도 왕복이 늘지 않는다.
void refreshAfterExerciseChange(ProviderInvalidator invalidate) {
  for (final ProviderOrFamily target in kExerciseChangeRefreshTargets) {
    invalidate(target);
  }
}
