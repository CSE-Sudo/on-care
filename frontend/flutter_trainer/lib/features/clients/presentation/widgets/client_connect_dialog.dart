import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_invite.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/pairing_code_input.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_identity.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원이 자기 앱에 띄운 6자리 동기화 코드로 연결하는 신규 고객 등록 창.
/// (#919·#1634)
///
/// 예전에는 회원 ID(`User.id`)를 완전 일치로 받았다. `user-<12자리 hex>` 는
/// 마주 앉아 불러 주거나 받아 적을 수 있는 형태가 아니었다.
///
/// 두 단계다 — 코드로 **찾고**, 찾은 사람과 **연결한다**. 회원이 코드를
/// 불러 준 것 자체가 동의라 회원에게 한 번 더 물을 일은 없지만, 여섯 자리를
/// 잘못 누르면 **남의** 식단·건강 기록이 열린다. 되돌릴 수 없는 사고라
/// 이름·성별·나이·목표를 눈으로 확인하고 나서 누르게 한다.
///
/// 확인만으로 코드가 사라지지는 않는다 — 확인하고 그만두는 것이 정상
/// 흐름이고, 그때마다 회원이 다시 띄워야 할 이유가 없다.
///
/// 성별·나이·신체 정보는 여기서 입력받지 않는다 — 연결되면 회원이 이미 자기
/// 앱에 등록해 둔 값을 그대로 쓴다.
///
/// 창 아래쪽의 **답을 기다리는 요청**은 옛 담당 요청 경로가 남긴 것이다. 보낸
/// 요청은 고객 목록에 나타나지 않으므로, 여기가 아니면 트레이너는 자기가
/// 무엇을 보냈는지 볼 곳이 없다. 데모에는 기다릴 답이 없어 그 목록이 없다
/// ([connectsImmediately]).
///
/// 가운데 뜨는 작은 창이다 — 상담 요청 인박스(`showConsultationsDialog`)와
/// 같은 자리(다른 작업으로 잠깐 넘어갔다 돌아오는 자리)에서 열리는 창이라
/// 같은 형식을 쓴다. 바닥에서 올라오는 시트로 두면 같은 성격의 두 진입점이
/// 서로 다른 화면처럼 읽힌다.
class ClientConnectDialog extends ConsumerStatefulWidget {
  const ClientConnectDialog({super.key});

  @override
  ConsumerState<ClientConnectDialog> createState() =>
      _ClientConnectDialogState();
}

class _ClientConnectDialogState extends ConsumerState<ClientConnectDialog> {
  final TextEditingController _code = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  /// 코드로 찾은 회원. 아직 연결하지 않았다 — 확인 카드가 이 값을 보여 준다.
  PairedMember? _found;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 창이 열리면 바로 칠 수 있어야 한다 — 회원이 코드를 불러 주고 있는 자리다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _codeFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// 여섯 자리가 다 차면 곧바로 찾는다 — 따로 누를 버튼을 두지 않는다.
  /// 찾기만 하고 연결은 트레이너가 확인한 뒤에 한다.
  void _onCodeChanged(String value) {
    if (_error != null || _found != null) {
      setState(() {
        _error = null;
        _found = null;
      });
    }
    if (value.length == PairingCodeInput.length) _lookup();
  }

  Future<void> _lookup() async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final String code = _code.text.trim();
    if (code.length != PairingCodeInput.length) {
      setState(() => _error = l.clientConnectCodeRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await ref
          .read(clientInviteRepositoryProvider)
          .previewPairingCode(code);
      if (!mounted || _code.text.trim() != code) return;
      setState(() => _found = found);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(PairedMember found) async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final repository = ref.read(clientInviteRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.redeemPairingCode(_code.text.trim());
      ref.invalidate(pendingClientInvitesProvider);
      // 데모(즉시 연결)와 실 API 모두 고객 탭과 고객 관리가 같은 목록을 보므로
      // 두 provider 를 함께 새로고침한다.
      ref.invalidate(clientsProvider);
      ref.invalidate(managedClientsProvider);
      // 미등록 동안 걸러졌던 오늘 일정·안읽음 배지도 다시 보인다(#1623).
      invalidateClientVisibilityDependentViews(ref);
      if (!mounted) return;
      navigator.pop();
      showAppToast(
        context,
        l.clientInviteConnected(found.name),
        type: AppToastType.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // 확인과 연결 사이에 코드가 만료됐거나 남이 먼저 썼을 수 있다.
        // 그러면 확인 카드도 거둔다 — 누를 수 없는 버튼을 남기지 않는다.
        _found = null;
        _error = _messageFor(l, error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 실패를 화면 문구로 옮긴다. 서버가 이유를 문장으로 준 경우에는 그 문장이
  /// 트레이너가 다음에 할 일을 정한다(한국어 로케일에서만 — 영어 화면에
  /// 한국어가 새지 않게 한다).
  String _messageFor(AppLocalizations l, Object error) => switch (error) {
    NotFoundError() => l.clientConnectCodeInvalid,
    AppError(:final String? message) => serverDetailOr(
      l,
      message,
      l.clientInviteFailed,
    ),
    _ => l.clientInviteFailed,
  };

  Future<void> _cancel(ClientInvite invite) async {
    if (_busy) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(clientInviteRepositoryProvider).cancel(invite.id);
      ref.invalidate(pendingClientInvitesProvider);
      if (!mounted) return;
      showAppToast(
        context,
        l.clientInviteCancelled,
        type: AppToastType.success,
      );
    } on AppError catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        serverDetailOr(l, error.message, l.clientInviteCancelFailed),
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final bool connectsImmediately = ref.watch(
      clientInviteRepositoryProvider.select((r) => r.connectsImmediately),
    );
    final TextStyle sectionTitle = tokens
        .text(OnCareTypography.titleSmall)
        .copyWith(color: OnCareColors.textPrimary);

    // 헤더의 닫기 X 는 [AppDialog] 가 둔다 — 가운데 뜨는 창은 아래로 끌어
    // 내려 닫을 수 없으므로 배경을 눌러 닫는 것과 별개로 명시적인 닫기가 있다.
    return AppDialog(
      key: const ValueKey<String>('client-connect-dialog'),
      title: l.clientInviteTitle,
      size: AppDialogSize.medium,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 수락해야 고객이 된다는 것(실 API)을, 또는 바로 연결된다는 것
          // (데모)을 창이 먼저 말한다 — 연결한 뒤 명단을 새로고침하며
          // 기다리는 일이 없도록.
          Text(
            connectsImmediately
                ? l.clientInviteIntroImmediate
                : l.clientInviteIntro,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s16),
          Text(
            l.clientConnectCodeLabel,
            style: tokens
                .text(OnCareTypography.label)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          PairingCodeInput(
            controller: _code,
            focusNode: _codeFocus,
            enabled: !_busy,
            onChanged: _onCodeChanged,
          ),
          if (_error case final String error) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            AppBanner(title: error, tone: AppBannerTone.danger),
          ],
          if (_busy) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s12),
            const AppLoading.inline(),
          ],
          if (_found case final PairedMember found) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            // 바로 잇지 않고 한 번 더 확인시킨다 — 여섯 자리가 하나만
            // 틀려도 남의 식단·건강 기록이 열린다.
            Text(l.clientInviteConfirmPrompt, style: sectionTitle),
            const SizedBox(height: OnCareSpacing.s8),
            _PairedMemberCard(paired: found),
            const SizedBox(height: OnCareSpacing.s12),
            AppButton(
              key: const ValueKey<String>('client-connect-register'),
              label: l.clientInviteConnectAction,
              onPressed: _busy ? null : () => _connect(found),
              leadingIcon: Icons.person_add_alt_1_rounded,
              size: OnCareButtonSize.large,
              fullWidth: true,
            ),
          ],
          if (!connectsImmediately) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s24),
            Text(l.clientInvitePendingTitle, style: sectionTitle),
            const SizedBox(height: OnCareSpacing.s8),
            _PendingInvitesList(busy: _busy, onCancel: _cancel),
          ],
        ],
      ),
    );
  }
}

/// 답을 기다리는 요청 목록 — 실 API 전용([ClientInviteRepository.connectsImmediately]
/// 가 `false`)이라 별도 위젯으로 뺀다. 데모는 이 provider 를 구독조차 하지
/// 않는다.
class _PendingInvitesList extends ConsumerWidget {
  const _PendingInvitesList({required this.busy, required this.onCancel});

  final bool busy;
  final ValueChanged<ClientInvite> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final pending = ref.watch(pendingClientInvitesProvider);
    return pending.when(
      loading: () => const AppLoading.inline(),
      error: (_, _) => AppErrorState(
        title: l.clientInviteFailed,
        retryLabel: l.actionRetry,
        onRetry: () => ref.invalidate(pendingClientInvitesProvider),
        placement: AppStatePlacement.card,
      ),
      data: (rows) => rows.isEmpty
          ? Text(
              l.clientInvitePendingEmpty,
              style: context.oncare
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textTertiary),
            )
          : Column(
              children: <Widget>[
                for (final invite in rows)
                  _PendingInviteRow(
                    invite: invite,
                    onCancel: busy ? null : () => onCancel(invite),
                  ),
              ],
            ),
    );
  }
}

/// 코드로 찾은 회원 — 아바타·이름·성별/나이·목표. (#1634)
///
/// 이름만 보여 주지 않는 것은, 여섯 자리가 하나만 틀려도 **다른 사람**이
/// 나오기 때문이다. 이름 하나로는 "이 고객이 맞나요?" 에 답할 수 없다.
///
/// 여기 있는 값은 모두 회원이 자기 앱에 등록해 둔 것이다 — 트레이너가 지금
/// 입력하는 값이 아니다. 키·몸무게·질환은 고객 상세의 건강 프로필에서 본다.
class _PairedMemberCard extends StatelessWidget {
  const _PairedMemberCard({required this.paired});

  final PairedMember paired;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    // 고객 목록과 같은 함수로 적는다 — 표기가 갈리면 견주기 어렵다.
    final String demographics = demographicsLabel(
      context,
      gender: paired.rosterGender,
      age: paired.rosterAge,
    );
    final TextStyle detail = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textTertiary);

    return AppCard(
      key: const ValueKey<String>('client-connect-result'),
      selected: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppAvatar(name: paired.name, size: AppAvatarSize.large),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        paired.name,
                        overflow: TextOverflow.ellipsis,
                        style: tokens
                            .text(OnCareTypography.titleSmall)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.s4),
                    Flexible(
                      child: Text(
                        demographics,
                        overflow: TextOverflow.ellipsis,
                        style: OnCareTypography.strong(detail),
                      ),
                    ),
                  ],
                ),
                if (paired.goal.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OnCareSpacing.s4),
                  Text(paired.goal, style: detail),
                ],
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            size: OnCareSize.iconMedium,
            color: tokens.brand.primary,
          ),
        ],
      ),
    );
  }
}

/// 답을 기다리는 요청 한 줄.
class _PendingInviteRow extends StatelessWidget {
  const _PendingInviteRow({required this.invite, this.onCancel});

  final ClientInvite invite;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              invite.memberName,
              style: context.oncare
                  .text(OnCareTypography.strong(OnCareTypography.bodySmall))
                  .copyWith(color: OnCareColors.textPrimary),
            ),
          ),
          AppButton(
            label: l.clientInviteCancelAction,
            onPressed: onCancel,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ],
      ),
    );
  }
}
