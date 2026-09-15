import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';

/// 알림을 눌렀을 때 관련 화면으로 보내고, **그 화면이 읽는 값을 다시 받게 한다.**
///
/// 이동만 하면 방금 알림이 알려 준 변화가 화면에 없을 수 있다 — 트레이너가 배정한
/// 루틴을 보러 갔는데 앱이 들고 있던 옛 목록이 그대로면, 알림이 거짓말을 한 것처럼
/// 보인다. 그래서 이동 직전에 그 화면의 provider 를 무효화한다.
///
/// 서버가 준 target 을 앱이 모르면 아무 데도 가지 않는다. 목록에서 빼거나 엉뚱한
/// 화면으로 보내는 것보다, 읽음 처리만 하고 제자리에 두는 편이 낫다.
Future<void> openAlertTarget(
  BuildContext context,
  WidgetRef ref,
  AlertItem item,
) async {
  final AlertAction? action = item.action;
  if (action == null || !action.isNavigable) return;

  switch (action.target) {
    case AlertTarget.coachChat:
      ref
        ..invalidate(coachChatProvider)
        ..invalidate(coachUnreadProvider);
      // 대화는 코치 정보를 알아야 열 수 있다. 들고 있는 값을 그냥 읽으면 안 된다 —
      // 아직 로딩 중이거나, 트레이너가 붙기 전에 받아 둔 `null` 이 남아 있으면
      // 눌러도 아무 일이 없다. 코치가 보낸 알림인데 코치를 모른다고 답하는 꼴이다.
      // 그래서 새로 받아 온 뒤에 판단한다.
      String? name;
      try {
        name = (await ref.refresh(memberCoachProvider.future))?.name;
      } on Exception {
        // 못 받으면 이동하지 않는다. 이름 없는 빈 대화창을 여느니 제자리가 낫다.
        return;
      }
      if (name == null || !context.mounted) return;
      await openTrainerChatPage(context, trainerName: name);
    case AlertTarget.exercise:
      // 담당 요청 알림도 이 목적지로 온다(서버 category `consultation_result`).
      // 요청은 이제 운동 탭 카드가 아니라 앱 어디서든 뜨는 창이라(#1801), 요청
      // 목록을 곧바로 다시 받게 해 아직 대기 중이면 창이 바로 뜨게 한다. 알림에는
      // 요청 id 가 없어 어느 요청의 알림인지는 가리지 못한다 — 대기 중인 요청이
      // 없으면 예전처럼 운동 탭으로 갈 뿐이다.
      ref
        ..invalidate(exerciseWeekProvider)
        ..invalidate(coachRoutinesProvider)
        ..invalidate(coachInvitesProvider);
      if (!context.mounted) return;
      context.go(AppRoutes.exercise);
    case AlertTarget.schedule:
      ref
        ..invalidate(scheduleEventsProvider)
        ..invalidate(scheduleMonthProvider)
        ..invalidate(coachSessionsProvider);
      if (!context.mounted) return;
      context.go(AppRoutes.dashboard);
    case AlertTarget.dashboard:
      if (!context.mounted) return;
      context.go(AppRoutes.dashboard);
    case AlertTarget.diet:
      if (!context.mounted) return;
      context.go(AppRoutes.diet);
    case AlertTarget.myBenefits:
      // 쿠폰이 방금 사용 처리·취소됐다 — 들고 있던 목록과 잔액을 다시 읽는다.
      // 챌린지 결과 알림(#1789)도 이리로 온다 — 판정된 챌린지를 다시 읽는다.
      ref
        ..invalidate(myCouponsProvider)
        ..invalidate(myChallengesProvider)
        ..invalidate(weeklyChallengeProvider)
        ..invalidate(myHealthStateProvider);
      if (!context.mounted) return;
      await context.push<void>(AppRoutes.myBenefits);
    case AlertTarget.unknown:
      return;
  }
}
