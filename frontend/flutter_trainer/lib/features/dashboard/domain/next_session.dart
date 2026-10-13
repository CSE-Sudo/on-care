/// 대시보드 `오늘 일정` 배너가 가리킬 수업을 고르는 규칙. (#2865)
///
/// 예전에는 저장된 상태가 `예정` 인 첫 세션을 골랐다. 상태는 시각이 아니라
/// 트레이너가 완료 처리했는지라, 오전 10시 수업을 완료 처리하지 않으면 오후에도
/// 배너가 "다음 수업 10:00 · 0분 뒤" 를 가리켰고 정작 곧 시작할 수업은 나오지
/// 않았다. 이제는 **끝나는 시각이 지금 이후인** `예정` 세션 중 가장 이른 것을
/// 고른다. 이미 시작했지만 아직 끝나지 않은 세션은 "진행 중" 이다.
library;

import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

/// 배너가 가리키는 수업의 단계.
enum NextSessionPhase {
  /// 시작 전 — 남은 시간은 시작까지.
  upcoming,

  /// 시작했고 아직 끝나지 않음 — 남은 시간은 끝까지.
  inProgress,
}

/// 배너에 띄울 수업과 그 단계, 남은 분.
typedef NextSession = ({
  ScheduleSession session,
  NextSessionPhase phase,
  int minutesLeft,
});

/// [sessions] 중 [now](KST 벽시계) 기준으로 배너에 띄울 수업. 없으면 null.
///
/// - 빈 시간·담당이 끊긴 회원의 일정(#2589)·`예정` 이 아닌 세션은 뺀다.
/// - 오늘이 아닌 날의 세션은 뺀다(자정 직후 아직 어제 목록이 남아 있을 때).
/// - 시각 형식이 깨진 세션은 언제인지 알 수 없어 뺀다.
/// - 길이가 0 이면 시작 1분으로 본다([sessionEndMinutes]).
/// - 끝난 시각이 지금과 같거나 지났으면 지난 수업이다 — 완료 처리를 잊은 것이지
///   준비할 수업이 아니다. 검색의 다음 예약·스케줄 탭 회원 선택과 같은
///   [sessionHasEnded] 로 판정한다(#3261).
NextSession? pickNextSession(List<ScheduleSession> sessions, DateTime now) {
  final String today = ymd(now);
  final int nowMinutes = now.hour * 60 + now.minute;
  NextSession? best;
  int? bestStart;
  for (final ScheduleSession s in sessions) {
    if (s.isGap || !s.isUpcoming || s.memberDetached) continue;
    if (s.date != today) continue;
    final int? start = clockMinutes(s.time);
    final int? end = sessionEndMinutes(s);
    if (start == null || end == null || sessionHasEnded(s, now)) continue;
    if (bestStart != null && start >= bestStart) continue;
    bestStart = start;
    best = start <= nowMinutes
        ? (
            session: s,
            phase: NextSessionPhase.inProgress,
            minutesLeft: end - nowMinutes,
          )
        : (
            session: s,
            phase: NextSessionPhase.upcoming,
            minutesLeft: start - nowMinutes,
          );
  }
  return best;
}
