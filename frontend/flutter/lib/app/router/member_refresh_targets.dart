import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

/// 홈 탭으로 **다시 들어올 때** 비우는 캐시. (#2842)
///
/// 홈 한 화면 안에서 같은 시점의 값이어야 하는 것들이다.
/// - 칼로리 목표는 [dashboardSummaryProvider] 가 서버에서 매번 새로 받는데,
///   같은 카드의 탄단지 목표와 운동 카드 목표는 프로필에서 온다. 요약만 비우면
///   한 카드 안에서 새 칼로리 목표와 옛 탄단지 목표가 섞인다. 프로필은 이
///   목록이 아니라 [refreshProfileQuietly] 로 함께 새로 받는다.
/// - 트레이너 카드·헤더 대화 버튼·`트레이너 추천` 배지는 [memberCoachProvider]
///   를 본다. 담당 연결이 바뀌어도 앱을 다시 켜기 전까지 옛 연결이 남았다.
///
/// 목록으로 모아 둔 까닭은 `_refreshMemberData`·`_refreshBranch` 두 자리에
/// 흩어 적다가 한쪽에서 빠진 일이 반복됐기 때문이다(#1938, #2625, #2842).
/// 테스트가 이 목록을 직접 확인한다.
final List<ProviderOrFamily> kHomeReentryRefreshTargets = <ProviderOrFamily>[
  dashboardSummaryProvider,
  // 앱을 켠 순간의 추천이 하루 종일 고정되지 않게(#1938).
  dietRecommendationsProvider,
  coachSessionsProvider,
  memberCoachProvider,
];

/// 앱이 백그라운드에서 **돌아올 때**(`AppLifecycleState.resumed`) 비우는 캐시.
/// (#1938, #2625, #2161, #2842)
///
/// 앱을 떠난 사이 다른 기기에서 기록했거나, 트레이너가 웹에서 목표·연결을
/// 바꿨거나, 날이 바뀌었을 수 있다. autoDispose 가 아닌 provider 는 비우지
/// 않으면 앱 수명 내내 처음 읽은 값에 머문다.
///
/// [today] 는 KST 오늘이다 — 식단 탭의 날짜별 캐시가 오늘 칸을 따로 들고 있어
/// 그 칸까지 비운다(`refreshDietRecords` 와 같은 규칙). 부르는 쪽이 `nowKst()`
/// 를 넘기고, 테스트는 고정한 날을 넘긴다.
///
/// 비워도 화면이 깜빡이지 않는다: Riverpod 은 다시 읽는 동안 이전 값을 함께
/// 들고 있고, 이 값들을 읽는 화면은 `valueOrNull` 로 그 값을 계속 그린다.
List<ProviderOrFamily> memberResumeRefreshTargets(DateTime today) =>
    <ProviderOrFamily>[
      ...kHomeReentryRefreshTargets,
      // 식단 기간 집계와 기록 시작일 — 옛 그래프가 남지 않게(#2625).
      dietPeriodProvider,
      recordSpanProvider,
      // 식단 탭 오늘 기록 — 다른 기기에서 적은 끼니가 홈 요약과 함께 보이게.
      dietTodayProvider,
      dietByDateProvider(today),
      exerciseWeekProvider,
      // 추천 개인운동은 날이 바뀌면 다시 미완료로 시작한다(#2161).
      coachRoutinesProvider,
      coachRoutinesOnDayProvider,
    ];

/// 프로필(탄단지·운동 목표의 원본)을 **비우지 않고** 서버 값으로 바꾼다. (#2842)
///
/// [profileProvider] 를 invalidate 하면 다시 읽는 동안은 이전 값을 들고 있지만,
/// 그 조회가 실패하면 오류 상태가 된다. MY `프로필`·`건강 목표` 화면은 오류
/// 상태에서 폼 대신 다시 시도 안내를 그리므로(빈 폼 저장 방지, #789), 앱 복귀
/// 직후 잠깐 끊긴 네트워크 하나로 고치던 폼이 사라진다. 그래서 프로필은 새 값을
/// 받았을 때만 바꾸고, 실패하면 들고 있던 값을 그대로 둔다 — 다음 복귀나 홈
/// 재진입 때 다시 시도된다.
Future<void> refreshProfileQuietly(ProfileController profile) async {
  try {
    await profile.refreshFromServer();
  } on Object {
    // 들고 있던 목표를 그대로 보여 준다. 실패를 알릴 자리는 홈이 아니다.
  }
}
