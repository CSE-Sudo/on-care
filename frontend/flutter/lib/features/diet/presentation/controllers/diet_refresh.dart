import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/shared/services/record_span_provider.dart';
import 'package:oncare_core/clock.dart';

/// provider 하나를 비우는 함수. `WidgetRef.invalidate`·`Ref.invalidate`·
/// `ProviderContainer.invalidate` 가 모두 이 모양이라, 부르는 쪽이 무엇을
/// 들고 있든 그대로 넘긴다.
typedef DietCacheInvalidator = void Function(ProviderOrFamily provider);

/// 식단 기록이 바뀐 뒤 날짜와 상관없이 비울 것들. (#2625, #2852)
///
/// 날짜별 캐시(`dietByDateProvider`)는 그 날을 알아야 해서 [refreshDietRecords]
/// 가 따로 비운다. 테스트가 대상 목록을 그대로 확인할 수 있도록 밖에 둔다 —
/// 운동의 `kExerciseChangeRefreshTargets` 와 같은 모양이다.
final List<ProviderOrFamily> kDietChangeRefreshTargets = <ProviderOrFamily>[
  dietTodayProvider,
  // 기간 집계는 autoDispose 가 아니다 — 비우지 않으면 앱 수명 내내 남는다.
  // 회원 리포트도 같은 family 를 읽으므로 통째로 비운다.
  dietPeriodProvider,
  // 조언도 새 합계로 다시 받는다 — 들고 있으면 옛 합계를 말한다(#2078).
  dietAdviceProvider,
  // 첫 기록을 남기거나 더 이른 날로 옮기면 `전체` 의 시작일이 바뀐다.
  recordSpanProvider,
  // 홈 요약. 목업 경로는 [dietTodayProvider] 를 따라오지만 실서버 경로는
  // 따라오지 않는다.
  dashboardSummaryProvider,
  // MY 기록 그래프와 연속 기록 보호권 — 식단을 적은 날도 칸이 칠해지고 연속
  // 기록일이 이어진다(#2852). 운동만 비우고 있어, 오늘 식단만 적은 회원에게
  // 연속 기록이 끊긴 것처럼 보였다.
  activityCalendarProvider,
  myStreakShieldsProvider,
];

/// 식단 기록이 바뀐 뒤(저장·수정·삭제·날짜 이동) 비워야 할 캐시를 한 번에
/// 비운다. (#2625)
///
/// 자리마다 invalidate 를 흩어 두면 새 캐시가 생길 때 어느 한 자리가 빠진다.
/// 기간 집계가 `GET /diet/days` 한 번으로 바뀐 뒤(#2236) 실제로 그랬다 — 날짜별
/// 캐시만 비우던 자리들이 남아 `이번 주`·`전체` 그래프가 옛 값에 머물렀다.
///
/// [dates] 는 오늘 말고 그 기록이 놓였던 날·옮겨 간 날이다. 지난 날짜의 끼니를
/// 지우고 그 날을 비우지 않으면 돌아온 목록에 지운 끼니가 남는다(#2626).
void refreshDietRecords(
  DietCacheInvalidator invalidate, {
  Iterable<DateTime> dates = const <DateTime>[],
}) {
  invalidate(dietByDateProvider(nowKst()));
  for (final DateTime date in dates) {
    invalidate(dietByDateProvider(date));
  }
  for (final ProviderOrFamily target in kDietChangeRefreshTargets) {
    invalidate(target);
  }
}
