import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

/// Connects session transitions to account-specific feature state.
///
/// Register every feature reset here. Riverpod overrides replace each other,
/// so this must remain the single app-level registry.
/// Keep `docs/SESSION_PROVIDER_AUDIT.md` in sync with this registry.
Override sessionFeatureResetOverride() {
  return sessionFeatureResetProvider.overrideWith((ref) {
    return () {
      // Stateful demo repositories must be recreated so one demo/account
      // cannot inherit another one's local mutations.
      ref.invalidate(dietRepositoryProvider);
      ref.invalidate(exerciseRepositoryProvider);
      ref.invalidate(gymRepositoryProvider);
      ref.invalidate(memberCoachRepositoryProvider);

      // Explicitly invalidate account data shown by each feature. Depending
      // only on a repository root is unsafe when it rebuilds to the same const
      // instance because Riverpod may keep its dependents unchanged.
      ref.invalidate(profileProvider);
      ref.invalidate(aiCoachStateProvider);
      ref.invalidate(chatControllerProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(dietTodayProvider);
      ref.invalidate(dietRecommendationsProvider);
      ref.invalidate(exerciseWeekProvider);
      ref.invalidate(exerciseRoutineDoneProvider);
      ref.invalidate(myGymProvider);
      ref.invalidate(myTrainerProvider);
      // 예약 내역은 헬스장 저장소를 통해 이미 함께 무효화되지만, 같은 뿌리를 보는
      // 위 두 잎처럼 명시해 둔다 — 전이에 기대면 뿌리 구조가 바뀔 때 조용히 새어 나간다.
      ref.invalidate(myReservationsProvider);
      ref.invalidate(consultationRequestControllerProvider);
      ref.invalidate(memberCoachProvider);
      ref.invalidate(coachRoutinesProvider);
      ref.invalidate(coachSessionsProvider);
      ref.invalidate(coachChatProvider);
      ref.invalidate(coachUnreadProvider);
      // 받은 담당 요청은 셸이 듣는 동안 살아 있다. 데모에서 로그인해도 셸이 그대로면
      // 앞 세션의 목록이 남는다(#1801).
      ref.invalidate(coachInvitesProvider);
      ref.invalidate(selectedCoachInviteProvider);
      ref.invalidate(myHealthStateProvider);
      // 포인트 사용처·내 쿠폰(#1787). auto-dispose 지만 화면을 연 채 전환하면
      // 앞 계정의 잔액·교환 가능 여부·쿠폰이 남는다.
      ref.invalidate(pointsShopProvider);
      ref.invalidate(myCouponsProvider);
      // MY 프로필 펫(#2021) — auto-dispose 가 아니라 되짚지 않으면 앞 계정의 펫이
      // 이름 옆에 남는다.
      ref.invalidate(profilePetProvider);
      // 포인트로 받은 주간 리포트(#2022) — 내 혜택을 연 채 전환하면 앞 계정의 주가 남는다.
      ref.invalidate(myWeeklyReportsProvider);
      // 연속 기록 보호권(#1788) — 앞 계정의 보유 수·보호한 날이 남지 않게 한다.
      ref.invalidate(myStreakShieldsProvider);
      // 기록 그래프·그래프 색(#2075, #2076) — 보호권과 같은 이유다. auto-dispose 가
      // 아니라 되짚지 않으면 앞 계정의 기록과 색이 그대로 남는다.
      ref.invalidate(activityCalendarProvider);
      // 주간 챌린지(#1789) — 같은 이유로 앞 계정의 참가·진행이 남지 않게 한다.
      ref.invalidate(weeklyChallengeProvider);
      // 목 저장소는 읽음 처리를 세션 동안 기억한다 — 다시 만들지 않으면 앞
      // 계정의 읽음 상태로 시작한다(#1936).
      ref.invalidate(notificationRepositoryProvider);
      ref.invalidate(notificationControllerProvider);
      ref.invalidate(notificationListProvider);
      // 알림 수신 설정은 실 백엔드에서 계정 단위다. 여기 없으면 앞 계정의 토글이
      // 앱을 다시 켤 때까지 남는다.
      ref.invalidate(notificationSettingsProvider);
      // 벨의 빨간 점. 목 모드는 한 번 내보내고 끝이라, 되짚지 않으면 앞 계정의
      // 점이 앱을 다시 켤 때까지 남는다(#1936).
      ref.invalidate(notificationUnreadProvider);
    };
  });
}
