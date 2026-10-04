import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/domain/password_reset_code.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/features/auth/presentation/controllers/password_providers.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 재설정 화면의 단계.
enum PasswordResetStep {
  /// 이메일을 넣고 코드를 받는다.
  request,

  /// 받은 코드와 새 비밀번호를 넣는다.
  confirm,

  /// 바꿨다 — 로그인하러 간다.
  done,
}

/// 재설정 화면의 칸.
enum PasswordResetField { email, code, next, confirm }

/// 비밀번호 재설정(#2824) — 로그인 화면의 `비밀번호를 잊으셨나요?` 와 메일 링크
/// (`/auth/password-reset?token=…`)가 연다.
///
/// 1. 이메일을 넣으면 그 계정 앞으로 일회용 코드가 간다. 가입되지 않은 이메일도
///    같은 안내를 본다 — 화면이 다르면 아무 이메일이나 넣어 가입 여부를 알 수 있다.
/// 2. 메일의 코드와 새 비밀번호를 넣는다. 모바일에서는 메일 링크가 앱을 열지
///    못하므로 코드를 붙여 넣는다. 웹에서 링크로 들어오면 코드 칸이 채워져 있다.
/// 3. 바꾸면 모든 기기의 로그인이 끝난다. 새 비밀번호로 다시 로그인한다.
class PasswordResetPage extends ConsumerStatefulWidget {
  const PasswordResetPage({super.key, this.initialCode});

  /// 메일 링크의 `token`. 있으면 코드 입력 단계에서 시작한다.
  final String? initialCode;

  @override
  ConsumerState<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends ConsumerState<PasswordResetPage> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  late PasswordResetStep _step;
  bool _busy = false;
  bool _obscure = true;

  /// 코드를 보냈다는 안내 — 요청 단계를 거쳐 왔을 때만 있다.
  PasswordResetRequested? _sent;

  /// 서버가 돌려준 칸 오류. 그 칸을 고치면 지운다.
  String? _codeServerError;
  String? _nextServerError;

  late final AppFieldErrors<PasswordResetField> _errors =
      AppFieldErrors<PasswordResetField>(_check);

  @override
  void initState() {
    super.initState();
    final String code = widget.initialCode?.trim() ?? '';
    if (code.isNotEmpty) {
      _code.text = PasswordResetCode.format(code);
      _step = PasswordResetStep.confirm;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _dropTokenFromAddress(),
      );
    } else {
      _step = PasswordResetStep.request;
    }
  }

  /// 메일 링크로 들어왔으면 주소에서 `token` 을 지운다(#3089). 30분 동안 쓸 수 있는
  /// 일회용 코드가 주소창·방문 기록·화면 공유에 남지 않게 한다. 코드는 이미 칸에
  /// 옮겨 두었다.
  ///
  /// 같은 경로로 다시 가되 [Router.neglect] 로 감싸 방문 기록에 새 항목을 쌓지 않고
  /// 지금 항목을 바꾼다. 경로가 같아 이 화면과 입력은 그대로 남는다(새로고침하면 코드
  /// 없이 요청 단계부터 다시 한다). 라우터가 기억하는 주소도 바뀌므로 나중에 라우터가
  /// 주소를 다시 알려도 코드가 되살아나지 않는다.
  void _dropTokenFromAddress() {
    if (!mounted) return;
    final GoRouter? router = GoRouter.maybeOf(context);
    if (router == null) return;
    final Uri uri = router.routerDelegate.currentConfiguration.uri;
    if (!uri.queryParameters.containsKey('token')) return;
    final Map<String, String> rest = Map<String, String>.of(uri.queryParameters)
      ..remove('token');
    final Uri clean = Uri(
      path: uri.path,
      queryParameters: rest.isEmpty ? null : rest,
    );
    Router.neglect(context, () => router.go(clean.toString()));
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _check(PasswordResetField field) {
    final AppLocalizations l = AppLocalizations.of(context);
    switch (field) {
      case PasswordResetField.email:
        return authInputErrorText(l, AppInputRules.email(_email.text));
      case PasswordResetField.code:
        if (_code.text.trim().isEmpty) return l.passwordResetCodeEmpty;
        return PasswordResetCode.isWellFormed(_code.text)
            ? null
            : l.passwordResetCodeMalformed;
      case PasswordResetField.next:
        return authInputErrorText(l, AppInputRules.signUpPassword(_next.text));
      case PasswordResetField.confirm:
        return authInputErrorText(
          l,
          AppInputRules.passwordConfirm(_next.text, _confirm.text),
        );
    }
  }

  void _onEdited(PasswordResetField field) {
    setState(() {
      if (field == PasswordResetField.code) _codeServerError = null;
      if (field == PasswordResetField.next) _nextServerError = null;
    });
  }

  void _back() {
    if (_busy) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.signIn);
    }
  }

  /// 실패 이유 → 칸 오류 또는 알림.
  void _showFailure(PasswordResetError e) {
    final AppLocalizations l = AppLocalizations.of(context);
    switch (e.kind) {
      case PasswordResetFailure.invalidCode:
        setState(() => _codeServerError = l.passwordResetCodeInvalid);
      case PasswordResetFailure.newRejected:
        setState(() => _nextServerError = authInputErrorText(l, e.reason));
      case PasswordResetFailure.unavailable:
        showAppToast(
          context,
          l.passwordResetUnavailable,
          type: AppToastType.error,
        );
      case PasswordResetFailure.tooMany:
        showAppToast(
          context,
          l.passwordTooManyAttempts,
          type: AppToastType.error,
        );
      case PasswordResetFailure.temporary:
        showAppToast(
          context,
          l.passwordTemporaryFailure,
          type: AppToastType.error,
        );
    }
  }

  Future<void> _request() async {
    if (_busy) return;
    if (!_errors.validate(const <PasswordResetField>[
      PasswordResetField.email,
    ])) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      final PasswordResetRequested sent = await ref
          .read(passwordRepositoryProvider)
          .requestReset(email: _email.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = sent;
        _step = PasswordResetStep.confirm;
        _codeServerError = null;
        final String? demo = sent.demoCode;
        if (demo != null) _code.text = demo;
      });
    } on PasswordResetError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFailure(e);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFailure(const PasswordResetError(PasswordResetFailure.temporary));
    }
  }

  Future<void> _confirmReset() async {
    if (_busy) return;
    if (!_errors.validate(const <PasswordResetField>[
      PasswordResetField.code,
      PasswordResetField.next,
      PasswordResetField.confirm,
    ])) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(passwordRepositoryProvider)
          .confirmReset(code: _code.text, newPassword: _next.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = PasswordResetStep.done;
      });
    } on PasswordResetError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFailure(e);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFailure(const PasswordResetError(PasswordResetFailure.temporary));
    }
  }

  /// 재설정은 모든 세션을 끝냈다. 이 기기가 아직 로그인 상태(링크를 로그인한
  /// 채로 열었다)라면 그 세션도 정리하고 로그인 화면으로 간다.
  Future<void> _goToSignIn() async {
    final GoRouter router = GoRouter.of(context);
    final SessionController session = ref.read(
      sessionControllerProvider.notifier,
    );
    if (ref.read(sessionControllerProvider).canEnterApp) {
      await session.signOut();
    }
    router.go(AppRoutes.signIn);
  }

  void _toStep(PasswordResetStep step) {
    if (_busy) return;
    setState(() {
      _step = step;
      _codeServerError = null;
      _nextServerError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: AppAuthLayout(
        key: const Key('passwordResetPage'),
        leading: AppBackButton(onPressed: _back),
        title: _step == PasswordResetStep.done
            ? l.passwordResetDoneTitle
            : l.passwordResetTitle,
        subtitle: switch (_step) {
          PasswordResetStep.request => l.passwordResetRequestSubtitle,
          PasswordResetStep.confirm => l.passwordResetConfirmSubtitle,
          PasswordResetStep.done => l.passwordResetDoneBody,
        },
        child: switch (_step) {
          PasswordResetStep.request => _requestBody(l),
          PasswordResetStep.confirm => _confirmBody(l),
          PasswordResetStep.done => _doneBody(l),
        },
      ),
    );
  }

  Widget _requestBody(AppLocalizations l) {
    return Column(
      key: const Key('passwordResetRequestStep'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTextField(
          key: const ValueKey<String>('passwordReset-email'),
          controller: _email,
          hint: l.authEmailHint,
          errorText: _errors.of(PasswordResetField.email),
          prefixIcon: AppIcon.setOf(context).mail,
          size: AppFieldSize.large,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.email],
          onChanged: (_) => _onEdited(PasswordResetField.email),
          onSubmitted: (_) => _request(),
        ),
        const SizedBox(height: OnCareSpacing.s24),
        AppButton(
          key: const ValueKey<String>('passwordReset-send'),
          label: l.passwordResetSendAction,
          onPressed: _request,
          loading: _busy,
          size: OnCareButtonSize.large,
          fullWidth: true,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Center(
          child: AppButton(
            key: const ValueKey<String>('passwordReset-have-code'),
            label: l.passwordResetHaveCode,
            onPressed: _busy ? null : () => _toStep(PasswordResetStep.confirm),
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ),
      ],
    );
  }

  Widget _confirmBody(AppLocalizations l) {
    final PasswordResetRequested? sent = _sent;
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        key: const Key('passwordResetConfirmStep'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (sent != null) ...<Widget>[
            AppBanner(
              key: const Key('passwordResetSentNotice'),
              tone: AppBannerTone.success,
              title: l.passwordResetSentTitle,
              message: l.passwordResetSentBody(
                _email.text.trim(),
                sent.expiresInMinutes,
              ),
            ),
            if (sent.demoCode != null) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              AppBanner(
                key: const Key('passwordResetDemoNotice'),
                title: l.passwordResetDemoNote,
                density: AppBannerDensity.compact,
              ),
            ],
            const SizedBox(height: OnCareSpacing.s16),
          ],
          AppTextField(
            key: const ValueKey<String>('passwordReset-code'),
            controller: _code,
            hint: l.passwordResetCodeHint,
            errorText: _errors.of(PasswordResetField.code) ?? _codeServerError,
            prefixIcon: AppIcon.setOf(context).lock,
            size: AppFieldSize.large,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.oneTimeCode],
            onChanged: (_) => _onEdited(PasswordResetField.code),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _passwordField(
            l,
            PasswordResetField.next,
            _next,
            l.passwordChangeNewHint,
            serverError: _nextServerError,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          _passwordField(
            l,
            PasswordResetField.confirm,
            _confirm,
            l.passwordChangeConfirmHint,
            last: true,
          ),
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
            key: const ValueKey<String>('passwordReset-submit'),
            label: l.passwordResetConfirmAction,
            onPressed: _confirmReset,
            loading: _busy,
            size: OnCareButtonSize.large,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Center(
            child: AppButton(
              key: const ValueKey<String>('passwordReset-resend'),
              label: l.passwordResetResend,
              onPressed: _busy
                  ? null
                  : () => _toStep(PasswordResetStep.request),
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneBody(AppLocalizations l) {
    return Column(
      key: const Key('passwordResetDoneStep'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppButton(
          key: const ValueKey<String>('passwordReset-to-sign-in'),
          label: l.passwordResetBackToSignIn,
          onPressed: _goToSignIn,
          size: OnCareButtonSize.large,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _passwordField(
    AppLocalizations l,
    PasswordResetField field,
    TextEditingController controller,
    String hint, {
    String? serverError,
    bool last = false,
  }) {
    return AppTextField(
      key: ValueKey<String>('passwordReset-${field.name}'),
      controller: controller,
      hint: hint,
      errorText: _errors.of(field) ?? serverError,
      prefixIcon: AppIcon.setOf(context).lock,
      size: AppFieldSize.large,
      obscureText: _obscure,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      autofillHints: const <String>[AutofillHints.newPassword],
      onChanged: (_) => _onEdited(field),
      onSubmitted: last ? (_) => _confirmReset() : null,
      suffix: AppPasswordToggle(
        obscure: _obscure,
        showLabel: l.a11yShowPassword,
        hideLabel: l.a11yHidePassword,
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}
