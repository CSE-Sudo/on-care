import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/chat_controller.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
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
      ref.invalidate(myHealthStateProvider);
      ref.invalidate(notificationControllerProvider);
      ref.invalidate(notificationListProvider);
      // 알림 수신 설정은 실 백엔드에서 계정 단위다. 여기 없으면 앞 계정의 토글이
      // 앱을 다시 켤 때까지 남는다.
      ref.invalidate(notificationSettingsProvider);
    };
  });
}
