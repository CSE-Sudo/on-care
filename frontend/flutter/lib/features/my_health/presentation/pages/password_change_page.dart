import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/features/auth/presentation/controllers/password_providers.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 비밀번호 변경 화면의 칸.
enum PasswordChangeField { current, next, confirm }

/// MY → 비밀번호 변경(#2824).
///
/// 트레이너 웹의 비밀번호 변경(#2766)과 같은 규약이다. 현재 비밀번호를 확인하고,
/// 새 비밀번호는 가입과 같은 규칙으로 본다. 바꾸면 서버가 토큰 세대를 올려 다른
/// 기기의 세션을 끊고, 이 기기는 응답에 실린 새 토큰으로 갈아 끼워 로그인을
/// 유지한다.
///
/// 바꿀 수 없는 계정은 칸을 비활성으로 두고 이유를 먼저 말한다 — 데모 빌드에는
/// 서버 계정이 없고, 소셜 로그인 전용 계정에는 바꿀 비밀번호가 없다.
class PasswordChangePage extends ConsumerStatefulWidget {
  const PasswordChangePage({super.key});

  @override
  ConsumerState<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends ConsumerState<PasswordChangePage> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  /// 서버가 돌려준 칸 오류. 그 칸을 고치면 지운다.
  String? _currentServerError;
  String? _nextServerError;

  late final AppFieldErrors<PasswordChangeField> _errors =
      AppFieldErrors<PasswordChangeField>(_check);

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _check(PasswordChangeField field) {
    final AppLocalizations l = AppLocalizations.of(context);
    switch (field) {
      case PasswordChangeField.current:
        return authInputErrorText(
          l,
          AppInputRules.signInPassword(_current.text),
        );
      case PasswordChangeField.next:
        final String? rule = authInputErrorText(
          l,
          AppInputRules.signUpPassword(_next.text),
        );
        if (rule != null) return rule;
        // 같은 비밀번호는 서버도 400 으로 막지만, 그 400 은 "현재 비밀번호
        // 불일치" 와 같은 상태 코드다. 보내기 전에 걸러 칸을 헷갈리지 않게 한다.
        return _current.text.isNotEmpty && _next.text == _current.text
            ? l.passwordChangeSameAsCurrent
            : null;
      case PasswordChangeField.confirm:
        return authInputErrorText(
          l,
          AppInputRules.passwordConfirm(_next.text, _confirm.text),
        );
    }
  }

  void _onEdited(PasswordChangeField field) {
    setState(() {
      if (field == PasswordChangeField.current) _currentServerError = null;
      if (field == PasswordChangeField.next) _nextServerError = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final AppLocalizations l = AppLocalizations.of(context);
    if (!_errors.validate(PasswordChangeField.values)) {
      setState(() {});
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    final SessionController session = ref.read(
      sessionControllerProvider.notifier,
    );
    setState(() => _saving = true);
    final ReissuedTokens? tokens;
    try {
      tokens = await ref
          .read(passwordRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
    } on PasswordChangeError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        switch (e.kind) {
          case PasswordChangeFailure.wrongCurrent:
            _currentServerError = l.passwordChangeWrongCurrent;
          case PasswordChangeFailure.newRejected:
            _nextServerError = authInputErrorText(l, e.reason);
          case PasswordChangeFailure.noPassword:
          case PasswordChangeFailure.unavailable:
          case PasswordChangeFailure.tooMany:
          case PasswordChangeFailure.temporary:
            break;
        }
      });
      final String? toastText = switch (e.kind) {
        PasswordChangeFailure.noPassword => l.passwordChangeSocialTitle,
        PasswordChangeFailure.unavailable => l.passwordChangeDemoTitle,
        PasswordChangeFailure.tooMany => l.passwordTooManyAttempts,
        PasswordChangeFailure.temporary => l.passwordTemporaryFailure,
        PasswordChangeFailure.wrongCurrent ||
        PasswordChangeFailure.newRejected => null,
      };
      if (toastText != null) toast.show(toastText, type: AppToastType.error);
      return;
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      toast.show(l.passwordTemporaryFailure, type: AppToastType.error);
      return;
    }
    // 비밀번호는 이미 바뀌었다. 새 토큰을 넣지 못하면 이 기기도 다음 요청에서
    // 만료 안내와 함께 로그인 화면으로 간다 — 실패로 알리지는 않는다.
    if (tokens != null) {
      try {
        await session.adoptReissuedTokens(
          access: tokens.access,
          refresh: tokens.refresh,
        );
      } on Object {
        // 위 주석 참고.
      }
    }
    toast.show(l.passwordChangeDone, type: AppToastType.success);
    if (navigator.mounted && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final bool supported = ref
        .watch(passwordRepositoryProvider)
        .supportsPasswordChange;
    // 프로필을 못 읽었다고 막지는 않는다 — 소셜 계정이면 서버가 409 로 알린다.
    final bool hasPassword = switch (ref.watch(profileProvider)) {
      AsyncData<UserProfile>(:final UserProfile value) => value.hasPassword,
      _ => true,
    };
    final bool enabled = supported && hasPassword && !_saving;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        key: const Key('passwordChangePage'),
        backgroundColor: tokens.pageBackground,
        appBar: AppTopBar(title: l.passwordChangeTitle),
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
                      children: <Widget>[
                        if (!supported) ...<Widget>[
                          AppBanner(
                            key: const Key('passwordChangeDemoNotice'),
                            icon: AppIcons.lock,
                            title: l.passwordChangeDemoTitle,
                            message: l.passwordChangeDemoBody,
                          ),
                          const SizedBox(height: OnCareSpacing.s12),
                        ] else if (!hasPassword) ...<Widget>[
                          AppBanner(
                            key: const Key('passwordChangeSocialNotice'),
                            icon: AppIcons.lock,
                            title: l.passwordChangeSocialTitle,
                            message: l.passwordChangeSocialBody,
                          ),
                          const SizedBox(height: OnCareSpacing.s12),
                        ],
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _field(
                                l,
                                PasswordChangeField.current,
                                _current,
                                l.passwordChangeCurrentHint,
                                enabled: enabled,
                                serverError: _currentServerError,
                                autofill: AutofillHints.password,
                              ),
                              const SizedBox(height: OnCareSpacing.s12),
                              _field(
                                l,
                                PasswordChangeField.next,
                                _next,
                                l.passwordChangeNewHint,
                                enabled: enabled,
                                serverError: _nextServerError,
                                autofill: AutofillHints.newPassword,
                              ),
                              const SizedBox(height: OnCareSpacing.s12),
                              _field(
                                l,
                                PasswordChangeField.confirm,
                                _confirm,
                                l.passwordChangeConfirmHint,
                                enabled: enabled,
                                autofill: AutofillHints.newPassword,
                                last: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: OnCareSpacing.s12),
                        Text(
                          l.passwordChangeNote,
                          key: const Key('passwordChangeNote'),
                          style: tokens
                              .text(OnCareTypography.bodySmall)
                              .copyWith(color: OnCareColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: AppButton(
                      key: const Key('passwordChangeSubmit'),
                      label: l.passwordChangeAction,
                      onPressed: supported && hasPassword ? _submit : null,
                      loading: _saving,
                      fullWidth: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    AppLocalizations l,
    PasswordChangeField field,
    TextEditingController controller,
    String hint, {
    required bool enabled,
    required String autofill,
    String? serverError,
    bool last = false,
  }) {
    return AppTextField(
      key: ValueKey<String>('passwordChange-${field.name}'),
      controller: controller,
      hint: hint,
      enabled: enabled,
      errorText: _errors.of(field) ?? serverError,
      prefixIcon: AppIcons.lock,
      obscureText: _obscure,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      autofillHints: <String>[autofill],
      onChanged: (_) => _onEdited(field),
      onSubmitted: last ? (_) => _submit() : null,
      suffix: AppPasswordToggle(
        obscure: _obscure,
        showLabel: l.a11yShowPassword,
        hideLabel: l.a11yHidePassword,
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}
