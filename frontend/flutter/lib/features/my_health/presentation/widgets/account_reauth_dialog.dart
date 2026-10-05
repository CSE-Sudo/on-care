import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/auth/presentation/social_provider_token.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 본인 확인 창이 닫힌 이유.
enum AccountReauthDialogResult {
  /// 확인을 마치고 작업도 끝났다.
  done,

  /// 회원이 취소했다.
  cancelled,

  /// 본인 확인 말고 다른 이유로 작업이 실패했다 — [AccountReauthDialogOutcome.error]
  /// 를 부른 쪽이 원래 하던 대로 알린다.
  failed,
}

/// [showAccountReauthDialog] 의 결과.
class AccountReauthDialogOutcome {
  const AccountReauthDialogOutcome(this.result, [this.error]);

  final AccountReauthDialogResult result;

  /// [AccountReauthDialogResult.failed] 일 때 작업이 던진 것.
  final Object? error;
}

/// 이메일 변경·탈퇴 앞의 본인 확인 창(#3039).
///
/// 비밀번호 계정은 현재 비밀번호 칸을, 비밀번호 없는 소셜 전용 계정은 그 칸
/// 대신 카카오·구글 다시 로그인 버튼을 보인다. 확정 버튼은 비밀번호를 적었거나
/// 다시 로그인을 마쳤을 때만 켜진다.
///
/// [onSubmit] 이 실제 작업(저장·탈퇴)을 한다. 서버가 본인 확인을 받아 주지
/// 않으면([AccountReauthRejected]) 창을 닫지 않고 그 자리에 이유를 적는다 —
/// 400 이라 세션은 그대로이고 로그아웃하지 않는다. 다른 실패는 창을 닫고
/// [AccountReauthDialogResult.failed] 로 돌려준다.
Future<AccountReauthDialogOutcome> showAccountReauthDialog({
  required BuildContext context,
  required String message,
  required String confirmLabel,
  required bool hasPassword,
  required Future<void> Function(AccountReauth reauth) onSubmit,
  bool destructive = false,
}) async {
  final AccountReauthDialogOutcome? outcome =
      await showAppDialog<AccountReauthDialogOutcome>(
        context: context,
        builder: (_) => AccountReauthDialog(
          message: message,
          confirmLabel: confirmLabel,
          hasPassword: hasPassword,
          destructive: destructive,
          onSubmit: onSubmit,
        ),
      );
  return outcome ??
      const AccountReauthDialogOutcome(AccountReauthDialogResult.cancelled);
}

/// [showAccountReauthDialog] 가 띄우는 창. 테스트가 직접 찾을 수 있게 공개한다.
class AccountReauthDialog extends ConsumerStatefulWidget {
  const AccountReauthDialog({
    super.key,
    required this.message,
    required this.confirmLabel,
    required this.hasPassword,
    required this.onSubmit,
    this.destructive = false,
  });

  final String message;
  final String confirmLabel;
  final bool hasPassword;
  final bool destructive;
  final Future<void> Function(AccountReauth reauth) onSubmit;

  @override
  ConsumerState<AccountReauthDialog> createState() =>
      _AccountReauthDialogState();
}

class _AccountReauthDialogState extends ConsumerState<AccountReauthDialog> {
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  AccountReauthFailure? _failure;

  /// 소셜 전용 계정이 방금 다시 로그인해 받은 provider·토큰.
  ({String provider, String token})? _social;
  bool _socialBusy = false;
  bool _socialFailed = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  AccountReauth? get _reauth {
    if (widget.hasPassword) {
      final String password = _password.text;
      return password.isEmpty ? null : AccountReauth.password(password);
    }
    final ({String provider, String token})? social = _social;
    return social == null
        ? null
        : AccountReauth.social(provider: social.provider, token: social.token);
  }

  Future<void> _relogin(String provider) async {
    if (_busy || _socialBusy) return;
    setState(() {
      _socialBusy = true;
      _socialFailed = false;
      _failure = null;
    });
    String? token;
    try {
      // 로그인 화면과 같은 길로 provider 토큰을 받는다. 계정에 연결된
      // provider 인지는 서버가 본다 — 다르면 `invalid_reauth` 다.
      token = await obtainSocialProviderToken(
        ref.read(appConfigProvider),
        provider,
      );
    } on Object {
      token = null;
    }
    if (!mounted) return;
    setState(() {
      _socialBusy = false;
      _socialFailed = token == null;
      _social = token == null ? null : (provider: provider, token: token);
    });
  }

  Future<void> _submit() async {
    final AccountReauth? reauth = _reauth;
    if (reauth == null || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final NavigatorState navigator = Navigator.of(context);
    try {
      await widget.onSubmit(reauth);
    } on AccountReauthRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = e.kind;
        // 소셜 토큰은 한 번 쓰면 다시 받아야 한다 — 확인이 막혔으면 비운다.
        if (!widget.hasPassword) _social = null;
      });
      return;
    } on Object catch (e) {
      if (navigator.mounted) {
        navigator.pop(
          AccountReauthDialogOutcome(AccountReauthDialogResult.failed, e),
        );
      }
      return;
    }
    if (navigator.mounted) {
      navigator.pop(
        const AccountReauthDialogOutcome(AccountReauthDialogResult.done),
      );
    }
  }

  String? _failureText(AppLocalizations l) => switch (_failure) {
    null => null,
    AccountReauthFailure.required =>
      widget.hasPassword ? l.reauthPasswordRequired : l.reauthSocialRequired,
    AccountReauthFailure.wrongPassword => l.passwordChangeWrongCurrent,
    AccountReauthFailure.invalidSocial => l.reauthSocialInvalid,
    AccountReauthFailure.tooMany => l.passwordTooManyAttempts,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final TextStyle prompt = tokens
        .text(OnCareTypography.bodySmall)
        .copyWith(color: OnCareColors.textSecondary);
    return AppDialog(
      key: const ValueKey<String>('reauth-dialog'),
      title: l.reauthTitle,
      showClose: false,
      footer: AppButtonPair(
        cancelKey: const ValueKey<String>('reauth-cancel'),
        confirmKey: const ValueKey<String>('reauth-confirm'),
        cancelLabel: l.myCancel,
        onCancel: _busy
            ? null
            : () => Navigator.pop(
                context,
                const AccountReauthDialogOutcome(
                  AccountReauthDialogResult.cancelled,
                ),
              ),
        confirmLabel: widget.confirmLabel,
        onConfirm: _reauth == null || _busy || _socialBusy ? null : _submit,
        confirmLoading: _busy,
        destructive: widget.destructive,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(widget.message),
          const SizedBox(height: OnCareSpacing.s12),
          if (widget.hasPassword)
            ..._passwordStep(l, prompt)
          else
            ..._socialStep(l, prompt),
        ],
      ),
    );
  }

  List<Widget> _passwordStep(AppLocalizations l, TextStyle prompt) => <Widget>[
    Text(l.reauthPasswordPrompt, style: prompt),
    const SizedBox(height: OnCareSpacing.s8),
    AppTextField(
      key: const ValueKey<String>('reauth-password'),
      controller: _password,
      hint: l.passwordChangeCurrentHint,
      enabled: !_busy,
      autofocus: true,
      errorText: _failureText(l),
      prefixIcon: AppIcons.lock,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      autofillHints: const <String>[AutofillHints.password],
      // 다시 입력하면 지난 거절 문구는 걷는다.
      onChanged: (_) => setState(() => _failure = null),
      onSubmitted: (_) => _submit(),
      suffix: AppPasswordToggle(
        obscure: _obscure,
        showLabel: l.a11yShowPassword,
        hideLabel: l.a11yHidePassword,
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
  ];

  List<Widget> _socialStep(AppLocalizations l, TextStyle prompt) {
    final bool available = ref.watch(appConfigProvider).usesMockSocialLogin;
    final bool enabled = available && !_busy && !_socialBusy;
    final String? failure = _failureText(l);
    return <Widget>[
      Text(l.reauthSocialPrompt, style: prompt),
      const SizedBox(height: OnCareSpacing.s12),
      AppLabeledDivider(label: l.reauthSocialAction),
      const SizedBox(height: OnCareSpacing.s12),
      // 로그인 화면과 같은 원형 버튼이다 — 같은 동작은 같은 모양이다.
      AppSocialLoginRow(
        children: <Widget>[
          AppSocialLoginButton(
            key: const ValueKey<String>('reauth-social-kakao'),
            provider: AppSocialProvider.kakao,
            label: l.authKakaoAction,
            onPressed: enabled ? () => _relogin('kakao') : null,
          ),
          AppSocialLoginButton(
            key: const ValueKey<String>('reauth-social-google'),
            provider: AppSocialProvider.google,
            label: l.authGoogleAction,
            onPressed: enabled ? () => _relogin('google') : null,
          ),
          AppSocialLoginButton(
            key: const ValueKey<String>('reauth-social-naver'),
            provider: AppSocialProvider.naver,
            label: l.authNaverAction,
            onPressed: enabled ? () => _relogin('naver') : null,
          ),
          AppSocialLoginButton(
            key: const ValueKey<String>('reauth-social-apple'),
            provider: AppSocialProvider.apple,
            label: l.authAppleAction,
            onPressed: enabled ? () => _relogin('apple') : null,
          ),
        ],
      ),
      if (!available) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s8),
        Text(
          l.reauthSocialUnavailable,
          key: const ValueKey<String>('reauth-social-unavailable'),
          textAlign: TextAlign.center,
          style: prompt,
        ),
      ],
      if (_social != null) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s12),
        AppBanner(
          key: const ValueKey<String>('reauth-social-confirmed'),
          title: l.reauthSocialConfirmed,
          tone: AppBannerTone.success,
          density: AppBannerDensity.compact,
        ),
      ],
      if (_socialFailed || failure != null) ...<Widget>[
        const SizedBox(height: OnCareSpacing.s12),
        AppBanner(
          key: const ValueKey<String>('reauth-social-error'),
          title: failure ?? l.authSocialSignInFailed,
          tone: AppBannerTone.danger,
          density: AppBannerDensity.compact,
        ),
      ],
    ];
  }
}
