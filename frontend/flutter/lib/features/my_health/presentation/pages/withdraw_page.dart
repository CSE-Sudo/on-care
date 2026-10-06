import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/observability/handled_error.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/my_health/presentation/controllers/withdraw_preview_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/account_reauth_dialog.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 탈퇴 사유. 값은 서버가 받는 코드 그대로다 — 화면 글은 번역되고 바뀌지만
/// 집계는 이 코드로 이어져야 한다. `DELETION_REASONS` 와 같은 집합이다.
enum WithdrawReason {
  privacy('privacy'),
  rarelyUsed('rarely_used'),
  hardToUse('hard_to_use'),
  notifications('too_many_notifications'),
  alternative('found_alternative'),
  other('other');

  const WithdrawReason(this.code);

  final String code;

  String label(AppLocalizations l) => switch (this) {
    WithdrawReason.privacy => l.myWithdrawReasonPrivacy,
    WithdrawReason.rarelyUsed => l.myWithdrawReasonRarelyUsed,
    WithdrawReason.hardToUse => l.myWithdrawReasonHardToUse,
    WithdrawReason.notifications => l.myWithdrawReasonNotifications,
    WithdrawReason.alternative => l.myWithdrawReasonAlternative,
    WithdrawReason.other => l.myWithdrawReasonOther,
  };

  /// 그 불편이 탈퇴 말고 무엇으로 풀리는지. 사유를 묻고 아무 답도 하지 않으면
  /// 묻는 쪽만 얻어 가는 절차가 된다.
  String keepText(AppLocalizations l) => switch (this) {
    WithdrawReason.privacy => l.myWithdrawKeepPrivacy,
    WithdrawReason.rarelyUsed => l.myWithdrawKeepRarelyUsed,
    WithdrawReason.hardToUse => l.myWithdrawKeepHardToUse,
    WithdrawReason.notifications => l.myWithdrawKeepNotifications,
    WithdrawReason.alternative => l.myWithdrawKeepAlternative,
    WithdrawReason.other => l.myWithdrawKeepOther,
  };
}

/// 회원 탈퇴. 고객 지원 목록에서 열린다. (#2019)
///
/// 탈퇴 자체의 동작은 #1935 그대로다 — `deleteAccount()` 를 부르고, 성공하면
/// 계정에 매인 기기 기록을 지운 뒤 세션을 비우고 로그인 화면으로 보낸다. 앞에
/// 두 칸이 붙었을 뿐이다.
///
/// 1. 무엇이 불편했는지 고르게 한다(복수 선택, 건너뛸 수 있다).
/// 2. 고른 것마다 탈퇴 말고 무엇으로 풀리는지 답한 뒤에 탈퇴를 이어 간다.
///
/// 사유는 탈퇴를 막는 조건이 아니다. 하나도 고르지 않아도 다음 칸으로 넘어가고,
/// 마지막 확인창은 그대로 뜬다 — 떠나기로 한 사람을 붙잡는 화면이 아니라
/// 고칠 수 있는 것을 한 번 말하는 자리다.
class WithdrawPage extends ConsumerStatefulWidget {
  const WithdrawPage({super.key});

  @override
  ConsumerState<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends ConsumerState<WithdrawPage> {
  final Set<WithdrawReason> _picked = <WithdrawReason>{};
  bool _keepStep = false;
  bool _busy = false;

  void _toggle(WithdrawReason reason) {
    setState(() {
      if (!_picked.remove(reason)) _picked.add(reason);
    });
  }

  /// 되돌릴 수 없는 동작 앞의 마지막 확인이다. 확인창은 #1935 의 것 그대로 —
  /// 무엇이 사라지는지 말하고, 빨간 채움 버튼에서 확정한다.
  ///
  /// 그 창에서 본인 확인도 한다(#3039). 잠기지 않은 폰을 누가 잠깐 집어 들어도
  /// 기록 전체를 지우지 못하게, 현재 비밀번호(소셜 전용 계정은 다시 로그인)를
  /// 거쳐야 빨간 버튼이 켜진다. 비밀번호가 틀리면 창 안에 알리고 세션은 그대로다.
  ///
  /// 확인창 앞에서 이 계정의 포인트·쿠폰·예약·상담 요청 건수를 읽어 0 이 아닌
  /// 것만 덧붙인다(#3006). 읽기가 실패하거나 늦으면 일반 문구로 띄운다.
  Future<void> _confirmAndDelete() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    // 세션을 비우면 이 화면은 그 자리에서 사라진다 — 옮길 곳을 먼저 붙들어 둔다.
    final GoRouter? router = GoRouter.maybeOf(context);
    final List<String> reasons = <String>[
      for (final WithdrawReason r in WithdrawReason.values)
        if (_picked.contains(r)) r.code,
    ];
    // 읽는 동안 두 버튼을 잠근다 — 두 번 눌러 확인창이 겹쳐 뜨지 않게.
    setState(() => _busy = true);
    final preview = await loadWithdrawPreview(
      ref.read(withdrawPreviewLoaderProvider),
      reporter: ref.read(handledErrorReporterProvider),
    );
    // 비밀번호 칸을 보일지, 소셜 다시 로그인을 보일지. 프로필을 못 읽으면
    // 비밀번호 계정으로 본다 — 대부분이 그렇고, 소셜 전용 계정이면 서버가
    // `reauth_required` 로 알려 준다.
    bool hasPassword = true;
    try {
      final UserProfile profile = await ref.read(profileProvider.future);
      hasPassword = profile.hasPassword;
    } on Object {
      // 위 주석 참고.
    }
    if (!mounted) return;
    // 탈퇴가 끝나면 이 화면이 이미 사라졌어도 기록을 지우고 로그아웃해야 한다 —
    // 쓸 것을 미리 붙들어 둔다(#3245).
    final AccountRepository repository = ref.read(accountRepositoryProvider);
    final AppPrefs prefs = ref.read(appPrefsProvider);
    final SessionController session = ref.read(
      sessionControllerProvider.notifier,
    );
    Future<void>? request;
    final AccountReauthDialogOutcome outcome = await showAccountReauthDialog(
      context: context,
      message: withdrawConfirmMessage(l, preview),
      confirmLabel: l.myWithdrawAction,
      hasPassword: hasPassword,
      destructive: true,
      onSubmit: (AccountReauth reauth) =>
          request = repository.deleteAccount(reasons: reasons, reauth: reauth),
    );
    AccountReauthDialogResult result = outcome.result;
    // 창이 요청 도중 다른 길로 닫혔다면 `취소` 로 온다. 서버에서는 계정이 지워졌을
    // 수 있다 — 그 요청의 끝을 보고 판단한다. 지워졌는데 로그아웃하지 않으면 다음
    // 요청의 401 에서야 "세션 만료" 로 튕긴다(#3245).
    final Future<void>? pending = request;
    if (result == AccountReauthDialogResult.cancelled && pending != null) {
      try {
        await pending;
        result = AccountReauthDialogResult.done;
      } on Object {
        // 거절·실패면 계정은 그대로다 — 취소로 둔다.
      }
    }
    switch (result) {
      case AccountReauthDialogResult.done:
        break;
      case AccountReauthDialogResult.cancelled:
        if (mounted) setState(() => _busy = false);
        return;
      case AccountReauthDialogResult.failed:
        if (mounted) setState(() => _busy = false);
        toast.show(l.myWithdrawFailed, type: AppToastType.error);
        return;
    }
    // 계정이 사라졌으니 계정에 매인 기기 기록도 남기지 않는다. 언어 설정은
    // 기기의 것이라 그대로 둔다.
    try {
      await prefs.clearAccountScoped();
    } on Object {
      // 기록을 못 지워도 탈퇴 자체는 끝났다 — 로그인 화면으로는 나가야 한다.
    }
    // 토큰·기기 저장값·기능 상태를 비우는 일은 로그아웃과 같다.
    await session.signOut();
    router?.go(AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        key: const Key('myWithdrawPage'),
        backgroundColor: tokens.pageBackground,
        appBar: AppTopBar(title: l.myWithdrawTitle),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: OnCareLayout.mobileContentMaxWidth,
              ),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        side,
                        OnCareSpacing.s8,
                        side,
                        OnCareSpacing.sectionGap,
                      ),
                      children: _keepStep ? _keepBody(l) : _reasonBody(l),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: _keepStep ? _keepFooter(l) : _reasonFooter(l),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 1. 사유 고르기 ──────────────────────────────

  List<Widget> _reasonBody(AppLocalizations l) {
    final OnCareTokens tokens = context.oncare;
    return <Widget>[
      Text(
        l.myWithdrawReasonTitle,
        style: tokens
            .text(OnCareTypography.strong(OnCareTypography.titleSmall))
            .copyWith(color: OnCareColors.textPrimary),
      ),
      // 한 칸 띄우고 묻는다 — 확인과 질문은 다른 말이다.
      const SizedBox(height: OnCareSpacing.s16),
      Text(
        l.myWithdrawReasonQuestion,
        style: tokens
            .text(OnCareTypography.bodyLarge)
            .copyWith(color: OnCareColors.textPrimary),
      ),
      const SizedBox(height: OnCareSpacing.s4),
      Text(
        l.myWithdrawReasonHint,
        style: tokens
            .text(OnCareTypography.caption)
            .copyWith(color: OnCareColors.textTertiary),
      ),
      const SizedBox(height: OnCareSpacing.s12),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < WithdrawReason.values.length; i++) ...<Widget>[
              if (i > 0) const AppDivider(),
              _reasonRow(l, WithdrawReason.values[i]),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _reasonRow(AppLocalizations l, WithdrawReason reason) {
    final bool on = _picked.contains(reason);
    return AppListRow(
      key: ValueKey<String>('withdrawReason-${reason.code}'),
      title: reason.label(l),
      selected: on,
      // 고르지 않은 줄에도 같은 자리를 비워 둔다 — 체크가 들고 날 때 글이
      // 좌우로 밀리지 않게.
      trailing: SizedBox(
        width: OnCareSize.iconMedium,
        height: OnCareSize.iconMedium,
        child: on
            ? AppIcon(
                AppIcons.checkCircle,
                size: OnCareSize.iconMedium,
                color: context.oncare.brand.primary,
              )
            : null,
      ),
      onTap: () => _toggle(reason),
    );
  }

  Widget _reasonFooter(AppLocalizations l) => AppButton(
    key: const ValueKey<String>('withdrawNextButton'),
    label: l.myWithdrawNext,
    size: OnCareButtonSize.large,
    fullWidth: true,
    // 아무것도 고르지 않아도 넘어간다 — 사유는 묻는 것이지 받아 내는 것이 아니다.
    onPressed: () => setState(() => _keepStep = true),
  );

  // ── 2. 탈퇴 말고 풀 수 있는 것 ──────────────────

  List<Widget> _keepBody(AppLocalizations l) {
    final OnCareTokens tokens = context.oncare;
    final List<WithdrawReason> picked = <WithdrawReason>[
      for (final WithdrawReason r in WithdrawReason.values)
        if (_picked.contains(r)) r,
    ];
    return <Widget>[
      Text(
        l.myWithdrawKeepTitle,
        style: tokens
            .text(OnCareTypography.strong(OnCareTypography.titleSmall))
            .copyWith(color: OnCareColors.textPrimary),
      ),
      const SizedBox(height: OnCareSpacing.s12),
      if (picked.isEmpty)
        // 하나도 고르지 않았으면 할 말이 하나뿐이다 — 무엇이 사라지는지.
        AppCard(
          key: const ValueKey<String>('withdrawKeep-default'),
          child: _keepText(l.myWithdrawKeepDefault),
        )
      else
        for (final WithdrawReason r in picked) ...<Widget>[
          AppCard(
            key: ValueKey<String>('withdrawKeep-${r.code}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  r.label(l),
                  style: tokens
                      .text(OnCareTypography.strong(OnCareTypography.body))
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                _keepText(r.keepText(l)),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
        ],
    ];
  }

  Widget _keepText(String text) => Text(
    text,
    style: context.oncare
        .text(OnCareTypography.body)
        .copyWith(color: OnCareColors.textSecondary),
  );

  Widget _keepFooter(AppLocalizations l) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      AppButton(
        key: const ValueKey<String>('withdrawStayButton'),
        label: l.myWithdrawStay,
        size: OnCareButtonSize.large,
        fullWidth: true,
        onPressed: _busy ? null : () => context.pop(),
      ),
      const SizedBox(height: OnCareSpacing.s8),
      // 위험 동작은 화면 안에서 빨간 글자 버튼으로 두고, 확정은 확인창의 빨간
      // 채움 버튼에서 한다(#1690).
      AppButton(
        key: const ValueKey<String>('withdrawContinueButton'),
        label: l.myWithdrawContinue,
        variant: AppButtonVariant.destructiveText,
        size: OnCareButtonSize.large,
        fullWidth: true,
        onPressed: _busy ? null : _confirmAndDelete,
      ),
    ],
  );
}
