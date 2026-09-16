import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 모든 메인 탭 헤더 오른쪽의 대화 입구다.
///
/// 담당 트레이너가 있으면 그 트레이너 채팅으로 들어간다. 받아 봤더니 담당이 없으면
/// 같은 자리가 **AI 챗봇 입구**로 바뀐다(#1823) — 트레이너가 있는 회원은 AI 챗봇을
/// 쓰지 않고, 없는 회원은 이 자리 말고는 AI 챗봇으로 가는 길이 코칭 시트뿐이었다.
///
/// 조회 중이거나 조회에 실패하면 담당이 있는지 모른다. 그때는 AI 입구로 단정하지
/// 않고 트레이너 버튼을 흐리게(비활성 모양) 그린 채, 눌렀을 때 왜 지금은 쓸 수
/// 없는지 한 줄로 알린다. 예전에는 이 상태에서 `onTap: null` 만 넘겨서 모양은
/// 그대로인 채 아무 반응도 없었다 — 고장 난 버튼으로 읽혔다(#786).
class TrainerChatHeaderButton extends ConsumerWidget {
  const TrainerChatHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final AsyncValue<MemberCoach?> coachAsync = ref.watch(memberCoachProvider);
    final MemberCoach? coach = coachAsync.valueOrNull;

    if (coachAsync.hasValue && !coachAsync.hasError && coach == null) {
      return AppIconButton(
        key: const Key('aiChatHeaderButton'),
        // 말풍선 안에 별 — 대화 입구라는 것과 AI 라는 것을 함께 말한다(#1900).
        // 반짝이 하나만 있을 때는 "AI 가 만든 값" 표시로 읽혀 눌러 볼 자리로
        // 보이지 않았다.
        icon: AppIcons.aiChat,
        tooltip: l.coachCtaChat,
        color: context.oncare.brand.primary,
        onPressed: () => context.push(AppRoutes.aiCoach),
      );
    }

    final int unread = ref.watch(coachUnreadProvider).valueOrNull ?? 0;
    final bool ready = coach != null;

    // 아직 받아 오는 중인지, 받아 보지 못했는지는 다른 사정이다. 안내 문구도 달라야
    // 한다 — 로딩 중에 "트레이너가 없다" 고 말하면 거짓이 된다.
    final String unavailableReason = coachAsync.isLoading
        ? l.coachTrainerLoading
        : l.coachTrainerNone;

    return Semantics(
      button: true,
      enabled: ready,
      label: l.coachChatWithTrainer,
      // 쓸 수 없을 때 버튼은 비활성 모양이지만, 비활성 버튼은 탭을 받지 않으므로
      // 바깥에서 받아 이유를 알린다.
      child: GestureDetector(
        key: const Key('trainerChatHeaderButton'),
        behavior: HitTestBehavior.opaque,
        onTap: ready ? null : () => showAppToast(context, unavailableReason),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            AppIconButton(
              icon: AppIcons.chat,
              tooltip: l.coachChatWithTrainer,
              color: context.oncare.brand.primary,
              onPressed: ready
                  ? () => openTrainerChatPage(context, trainerName: coach.name)
                  : null,
            ),
            if (unread > 0)
              Positioned(
                top: 0,
                right: 0,
                child: IgnorePointer(child: AppCountBadge(count: unread)),
              ),
          ],
        ),
      ),
    );
  }
}
