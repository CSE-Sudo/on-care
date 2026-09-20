import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';

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
    case AlertTarget.consultations:
      // 상담 요청의 승인·거절·만료(#2067). 결과와 사유는 운동 탭이 아니라 내 상담
      // 요청에 있다. 들고 있던 목록은 트레이너가 결정하기 전 것이라 다시 받는다 —
      // 옛 "확인 대기" 가 남으면 알림과 화면이 다른 말을 한다. 화면이 열릴 때도
      // 다시 받지만, 여기서 먼저 시작해 두면 그만큼 빨리 바뀐다.
      unawaited(
        ref.read(consultationRequestControllerProvider.notifier).refresh(),
      );
      if (!context.mounted) return;
      // 기다리지 않는다 — 화면을 닫을 때까지 끝나지 않는 Future 다.
      unawaited(context.push(AppRoutes.consultationHistory));
    case AlertTarget.exercise:
      // 담당 요청 알림이 이 목적지로 온다(서버 category `consultation_result`).
      // 상담 요청의 결과 알림은 내 상담 요청으로 간다(`consult_decision`, #2067).
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
    case AlertTarget.dashboard:
      // 이미 홈에 있을 때 홈 알림을 누르는 것이 가장 흔한 경로다(기본 알림이
      // 전부 이 목적지다). 그때는 셸의 브랜치 전환 갱신이 걸리지 않으므로
      // — `_lastIndex == nextIndex` 면 곧바로 반환한다 — 여기서 직접 다시
      // 읽지 않으면 알림이 말한 변화가 홈에 없는 채로 돌아온다(#1939).
      ref.invalidate(dashboardSummaryProvider);
      if (!context.mounted) return;
      context.go(AppRoutes.dashboard);
    case AlertTarget.diet:
      // 식단 탭에서 식단 알림을 누르는 경우도 같다.
      ref
        ..invalidate(dietTodayProvider)
        ..invalidate(dietByDateProvider(nowKst()));
      if (!context.mounted) return;
      context.go(AppRoutes.diet);
    case AlertTarget.myBenefits:
      // 쿠폰이 방금 사용 처리·취소됐다 — 들고 있던 목록과 잔액을 다시 읽는다.
      ref
        ..invalidate(myCouponsProvider)
        ..invalidate(myHealthStateProvider);
      if (!context.mounted) return;
      await context.push<void>(AppRoutes.myBenefits);
    case AlertTarget.pointsShop:
      // 주간 챌린지가 판정됐다(#1789) — 결과를 보고 다음 주에 다시 참가하거나
      // 돌려받은 포인트를 확인하는 자리가 포인트 사용처다. 들고 있던 챌린지와
      // 잔액은 판정 전 값이라 함께 다시 읽는다.
      ref
        ..invalidate(weeklyChallengeProvider)
        ..invalidate(myHealthStateProvider);
      if (!context.mounted) return;
      await context.push<void>(AppRoutes.myPoints);
    case AlertTarget.healthGoals:
      // 담당 트레이너가 건강 목표를 바꿨다(#1832). 들고 있던 프로필은 바뀌기 전
      // 목표라, 다시 받아 온 뒤 MY 건강 목표를 연다 — 바뀐 목표와 `마지막 변경`
      // 줄이 바로 보여야 알림이 말한 것과 화면이 같다.
      ref.invalidate(profileProvider);
      if (!context.mounted) return;
      context.go(AppRoutes.myHealth);
      await openGoalsPage(context);
    case AlertTarget.unknown:
      return;
  }
}
