import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';

/// 날짜(KST)가 바뀌면 다시 읽을 것들. (#2852)
///
/// 셋 다 "오늘" 이 기준이다 — 기록 그래프는 오늘로 끝나는 격자, 보호권은 어제부터
/// 거슬러 30일, 주간 챌린지는 오늘이 든 주다. 기록 그래프와 보호권은 autoDispose
/// 가 아니라(데모에서 한 해치 기록을 순회하는 비용 때문) 앱을 켜 둔 채 자정을
/// 넘기면 "오늘" 칸이 어제에 머물렀다.
final List<ProviderOrFamily> kDayChangeRefreshTargets = <ProviderOrFamily>[
  activityCalendarProvider,
  myStreakShieldsProvider,
  weeklyChallengeProvider,
];

/// 마지막으로 갱신한 날을 기억했다가 날이 바뀐 계기(앱 복귀·MY 탭 재진입)에만
/// [kDayChangeRefreshTargets] 를 비운다. (#2852)
///
/// 같은 날 안의 단순 복귀에서는 비우지 않는다 — 기록 그래프를 다시 만드는 순회를
/// 피하려는 기존 의도를 지킨다. 기록이 바뀐 계기는 저장·삭제 쪽이 이미 비운다.
class DayChangeRefresher {
  /// [today] 는 KST 오늘(0시)을 돌려준다. 테스트가 시계를 넣는다.
  DayChangeRefresher({DateTime Function()? today})
    : _today = today ?? todayKst {
    _lastDay = _today();
  }

  final DateTime Function() _today;
  late DateTime _lastDay;

  /// 마지막으로 본 날과 오늘이 다르면 대상을 비우고 true.
  bool refreshIfDayChanged(
    void Function(ProviderOrFamily provider) invalidate,
  ) {
    final DateTime today = _today();
    final bool sameDay =
        today.year == _lastDay.year &&
        today.month == _lastDay.month &&
        today.day == _lastDay.day;
    if (sameDay) return false;
    _lastDay = today;
    for (final ProviderOrFamily target in kDayChangeRefreshTargets) {
      invalidate(target);
    }
    return true;
  }
}
