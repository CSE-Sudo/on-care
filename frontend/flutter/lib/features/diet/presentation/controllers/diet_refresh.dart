import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

/// provider 하나를 비우는 함수. `WidgetRef.invalidate`·`Ref.invalidate`·
/// `ProviderContainer.invalidate` 가 모두 이 모양이라, 부르는 쪽이 무엇을
/// 들고 있든 그대로 넘긴다.
typedef DietCacheInvalidator = void Function(ProviderOrFamily provider);

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
  invalidate(dietTodayProvider);
  invalidate(dietByDateProvider(nowKst()));
  for (final DateTime date in dates) {
    invalidate(dietByDateProvider(date));
  }
  // 기간 집계는 autoDispose 가 아니다 — 비우지 않으면 앱 수명 내내 남는다.
  // 회원 리포트도 같은 family 를 읽으므로 통째로 비운다.
  invalidate(dietPeriodProvider);
  // 조언도 새 합계로 다시 받는다 — 들고 있으면 옛 합계를 말한다(#2078).
  invalidate(dietAdviceProvider);
  // 첫 기록을 남기거나 더 이른 날로 옮기면 `전체` 의 시작일이 바뀐다.
  invalidate(recordSpanProvider);
  // 홈 요약. 목업 경로는 [dietTodayProvider] 를 따라오지만 실서버 경로는
  // 따라오지 않는다.
  invalidate(dashboardSummaryProvider);
}
