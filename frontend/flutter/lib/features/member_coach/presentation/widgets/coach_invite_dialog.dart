import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 담당 요청 창에서 회원이 고른 답.
enum CoachInviteDecision { accepted, rejected }

/// 트레이너가 보낸 담당 요청 [invite] 를 가운데 창으로 띄운다. (#1801)
///
/// 답은 `거절 / 수락` 둘뿐이다. 닫기 X·바깥 누르기·뒤로가기로는 닫히지 않는다 —
/// 창을 치운 채 앱을 쓰게 두면, 운동 탭 맨 아래 카드 시절처럼 요청이 온 줄 모르고
/// 지나친다.
///
/// 회원이 답하면 그 답을 돌려준다. 답 없이 창이 사라지면(트레이너가 요청을
/// 거둬들였거나, 화면 이동으로 창이 함께 치워졌을 때) `null` 이다.
Future<CoachInviteDecision?> showCoachInviteDialog(
  BuildContext context, {
  required CoachInvite invite,
}) {
  return showAppDialog<CoachInviteDecision>(
    context: context,
    dismissible: false,
    builder: (BuildContext _) => CoachInviteDialog(invite: invite),
  );
}

/// 담당 요청 창의 내용 — 누가 보냈는지, 무엇이 열리는지, 그리고 두 답.
///
/// 수락 버튼 위에 **무엇이 열리는지**를 함께 적는 것은 의도다. 담당 관계는 내
/// 식단·운동 기록을 그 사람에게 여는 일이라, 무엇에 동의하는지 모르고 누르는
/// 버튼이 되어서는 안 된다.
class CoachInviteDialog extends ConsumerStatefulWidget {
  const CoachInviteDialog({required this.invite, super.key});

  final CoachInvite invite;

  @override
  ConsumerState<CoachInviteDialog> createState() => _CoachInviteDialogState();
}

class _CoachInviteDialogState extends ConsumerState<CoachInviteDialog> {
  /// 서버에 보내는 중인 답. 그동안 두 버튼을 모두 막는다.
  CoachInviteDecision? _sending;

  /// 데이터 공유 동의창이 이 창 위에 떠 있는가.
  bool _consentOpen = false;

  /// 이미 닫았는가. 닫히는 동안 목록이 갱신돼 한 번 더 닫는 일을 막는다 — 두 번째
  /// pop 은 이 창이 아니라 그 아래 화면을 닫는다.
  bool _closed = false;

  CoachInvite get _invite => widget.invite;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<List<CoachInvite>>>(
      coachInvitesProvider,
      (_, _) => _closeIfWithdrawn(),
    );
  }

  /// 트레이너가 요청을 거둬들이면 목록에서 빠진다. 닫히지 않는 창이라, 사라진
  /// 요청을 붙들고 있으면 회원은 수락도 거절도 할 수 없는 창에 갇힌다.
  void _closeIfWithdrawn() {
    if (_closed || _sending != null || _consentOpen || !mounted) return;
    // 새로 받는 중이거나 받지 못한 값으로는 판단하지 않는다. 연결이 한 번 끊겼다고
    // 멀쩡한 요청의 창을 닫으면 안 된다.
    final AsyncValue<List<CoachInvite>> invites = ref.read(
      coachInvitesProvider,
    );
    if (invites is! AsyncData<List<CoachInvite>>) return;
    if (invites.value.any((CoachInvite i) => i.id == _invite.id)) return;
    _close(null);
  }

  void _close(CoachInviteDecision? decision) {
    if (_closed || !mounted) return;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null) return;
    _closed = true;
    final NavigatorState navigator = Navigator.of(context);
    // 위에 다른 창이 떠 있으면 pop 은 그 창을 닫는다. 이 창만 정확히 뺀다.
    if (route.isCurrent) {
      navigator.pop(decision);
    } else {
      navigator.removeRoute(route, decision);
    }
  }

  /// 수락은 먼저 무엇이 넘어가는지 알리고 동의를 받는다. (#1022)
  ///
  /// 수락하는 순간 트레이너가 회원의 식단·운동·신체 정보를 읽는다. 안내로
  /// 지나가지 않고 동의를 받아야, 회원이 무엇에 동의했는지 나중에도 말할 수 있다.
  /// 서버도 동의 없는 수락은 400 으로 막는다. 동의창에서 취소하면 이 창으로
  /// 돌아온다 — 요청은 그대로다.
  Future<void> _accept() async {
    if (_sending != null || _consentOpen || _closed) return;
    final AppLocalizations l = AppLocalizations.of(context);
    _consentOpen = true;
    final bool agreed = await showAppConfirmDialog(
      context: context,
      title: l.coachInviteConsentTitle,
      message: l.coachInviteConsentBody(_invite.trainerName),
      confirmLabel: l.coachInviteConsentAgree,
      cancelLabel: l.actionCancel,
    );
    _consentOpen = false;
    if (!mounted) return;
    if (!agreed) {
      // 동의창이 떠 있는 동안 요청이 거둬들여졌다면 그때는 닫지 못했다.
      _closeIfWithdrawn();
      return;
    }
    await _send(CoachInviteDecision.accepted);
  }

  /// 거절은 되묻지 않는다. 아무것도 열지 않는 답이고, 잘못 거절해도 트레이너가
  /// 다시 요청하면 된다(#1801).
  Future<void> _reject() => _send(CoachInviteDecision.rejected);

  Future<void> _send(CoachInviteDecision decision) async {
    if (_sending != null || _closed) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    // 답을 기다리는 사이 창이 치워져도 목록은 다시 받아야 한다. `ref` 는 창과 함께
    // 사라지므로 컨테이너를 잡아 둔다.
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final MemberCoachRepository repository = container.read(
      memberCoachRepositoryProvider,
    );
    final bool accept = decision == CoachInviteDecision.accepted;
    setState(() => _sending = decision);
    bool done = false;
    try {
      if (accept) {
        await repository.acceptInvite(_invite.id, dataSharingConsent: true);
      } else {
        await repository.rejectInvite(_invite.id);
      }
      done = true;
    } on AppError {
      toast.show(l.coachInviteFailed, type: AppToastType.error);
    } finally {
      if (!done && mounted) setState(() => _sending = null);
    }

    // 실패해도 목록은 다시 받는다 — 이미 거둬들여진 요청이라 실패했을 수 있다.
    // 사라졌으면 창이 닫히고, 남아 있으면 창은 그대로라 다시 누르면 된다.
    container.invalidate(coachInvitesProvider);
    if (!done) return;
    // 수락은 담당을 만든다 — 코치 카드·루틴·일정이 모두 그 관계 위에 있으므로
    // 함께 다시 읽는다. 거절은 목록만 바뀐다.
    if (accept) {
      container
        ..invalidate(memberCoachProvider)
        ..invalidate(coachRoutinesProvider)
        ..invalidate(coachSessionsProvider);
    }
    toast.show(
      accept
          ? l.coachInviteAccepted(_invite.trainerName)
          : l.coachInviteRejected,
      type: AppToastType.success,
    );
    _close(decision);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final CoachInvite invite = _invite;
    final bool sending = _sending != null;

    return AppDialog(
      key: ValueKey<String>('coach-invite-${invite.id}'),
      showClose: false,
      footer: AppButtonPair(
        cancelKey: ValueKey<String>('coach-invite-reject-${invite.id}'),
        confirmKey: ValueKey<String>('coach-invite-accept-${invite.id}'),
        cancelLabel: l.coachInviteReject,
        onCancel: sending ? null : _reject,
        confirmLabel: l.coachInviteAccept,
        onConfirm: sending ? null : _accept,
        confirmLoading: _sending == CoachInviteDecision.accepted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.coachInviteTitle,
            style: tokens
                .text(OnCareTypography.strong(OnCareTypography.caption))
                .copyWith(color: OnCareColors.textTertiary),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          Row(
            children: <Widget>[
              AppAvatar(name: invite.trainerName),
              const SizedBox(width: OnCareSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l.coachInviteFrom(invite.trainerName),
                      style: tokens
                          .text(OnCareTypography.titleSmall)
                          .copyWith(color: OnCareColors.textPrimary),
                    ),
                    if (invite.gymName case final String gym
                        when gym.isNotEmpty)
                      Text(
                        l.coachInviteGym(gym),
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textTertiary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (invite.message case final String message
              when message.isNotEmpty) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            Text(
              message,
              style: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ],
          const SizedBox(height: OnCareSpacing.s12),
          // 무엇에 동의하는지 버튼 위에 적는다.
          Text(
            l.coachInviteExplain,
            style: tokens
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
