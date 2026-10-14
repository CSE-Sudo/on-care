import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/data/repositories/find_email_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/find_email_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 이메일 찾기 화면의 칸.
enum FindEmailField { name, phone }

/// 이메일(가입 이메일) 찾기(#3439) — 로그인 화면의 `이메일 찾기` 가 연다.
///
/// 회원 앱(#3337)과 같은 화면이다. 비밀번호 재설정(#2824)과 같은 틀로, 가입할 때
/// 받은 이름과 휴대폰 번호를 넣는다. 번호를 넣지 않고 가입한 기존 트레이너는 MY
/// 프로필에서 번호를 채워 두어야 찾을 수 있다.
///
/// 서버는 트레이너 계정만 찾고(`/auth/trainer/find-email`), 번호의 주인을 확인할
/// 수단(문자 인증)이 없어 **가려진 이메일**만 준다. 결과는 세 가지다.
///
/// - 찾음 — 가려진 이메일(`ab***@example.com`)을 보여 준다. 같은 이름·번호의
///   계정이 여럿이면 모두 보여 준다.
/// - 소셜 가입 — 이메일 대신 가입 수단(카카오·구글)을 알려 준다.
/// - 없음 — 오류가 아니라 "찾지 못했어요" 안내다.
///
/// 결과에서 로그인·비밀번호 재설정으로 바로 넘어갈 수 있다.
class TrainerFindEmailPage extends ConsumerStatefulWidget {
  const TrainerFindEmailPage({super.key});

  @override
  ConsumerState<TrainerFindEmailPage> createState() =>
      _TrainerFindEmailPageState();
}

class _TrainerFindEmailPageState extends ConsumerState<TrainerFindEmailPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  bool _busy = false;

  /// 찾은 결과. null 이면 아직 찾기 전(입력 단계)이고, 빈 목록이면 찾지 못했다.
  List<FoundEmailAccount>? _found;

  late final AppFieldErrors<FindEmailField> _errors =
      AppFieldErrors<FindEmailField>(_check);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _check(FindEmailField field) {
    final AppLocalizations l = AppLocalizations.of(context);
    return authInputErrorText(l, switch (field) {
      FindEmailField.name => AppInputRules.name(_name.text),
      FindEmailField.phone => AppInputRules.phone(_phone.text),
    });
  }

  void _onEdited(String _) => setState(() {});

  void _back() {
    if (_busy) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.signIn);
    }
  }

  void _toPasswordReset() => context.pushReplacement(AppRoutes.passwordReset);

  /// 결과를 지우고 입력 단계로 돌아간다. 넣었던 이름·번호는 그대로 둔다.
  void _retry() => setState(() => _found = null);

  void _showFailure(FindEmailFailure kind) {
    final AppLocalizations l = AppLocalizations.of(context);
    showAppToast(context, switch (kind) {
      FindEmailFailure.tooMany => l.passwordResetTooMany,
      FindEmailFailure.invalidInput ||
      FindEmailFailure.temporary => l.passwordResetTemporaryFailure,
    }, type: AppToastType.error);
  }

  Future<void> _find() async {
    if (_busy) return;
    if (!_errors.validate(FindEmailField.values)) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      final List<FoundEmailAccount> found = await ref
          .read(findEmailRepositoryProvider)
          .find(name: _name.text.trim(), phone: _phone.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _found = found;
      });
    } on FindEmailError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFailure(e.kind);
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
      _showFailure(FindEmailFailure.temporary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<FoundEmailAccount>? found = _found;
    return PopScope(
      canPop: !_busy,
      child: AppAuthLayout(
        key: const Key('trainerFindEmailPage'),
        leading: AppBackButton(onPressed: _back),
        title: l.findEmailTitle,
        subtitle: found == null || found.isEmpty
            ? l.findEmailSubtitle
            : l.findEmailFoundSubtitle,
        child: found == null ? _formBody(l) : _resultBody(l, found),
      ),
    );
  }

  Widget _formBody(AppLocalizations l) {
    return Column(
      key: const Key('trainerFindEmailFormStep'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppTextField(
          key: const ValueKey<String>('trainerFindEmail-name'),
          controller: _name,
          hint: l.authName,
          errorText: _errors.of(FindEmailField.name),
          prefixIcon: AppIcons.person,
          size: AppFieldSize.large,
          textInputAction: TextInputAction.next,
          autofillHints: const <String>[AutofillHints.name],
          onChanged: _onEdited,
        ),
        const SizedBox(height: OnCareSpacing.s12),
        AppTextField(
          key: const ValueKey<String>('trainerFindEmail-phone'),
          controller: _phone,
          hint: l.signUpPhoneHint,
          errorText: _errors.of(FindEmailField.phone),
          prefixIcon: AppIcons.phone,
          size: AppFieldSize.large,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          // 가입 화면과 같은 국내 번호 — 숫자만 쳐도 하이픈이 들어간다.
          autofillHints: const <String>[AutofillHints.telephoneNumberNational],
          inputFormatters: const <TextInputFormatter>[
            AppPhoneNumberFormatter(),
          ],
          onChanged: _onEdited,
          onSubmitted: (_) => _find(),
        ),
        const SizedBox(height: OnCareSpacing.s24),
        AppButton(
          key: const ValueKey<String>('trainerFindEmail-submit'),
          label: l.findEmailAction,
          onPressed: _find,
          size: OnCareButtonSize.large,
          fullWidth: true,
        ),
        const SizedBox(height: OnCareSpacing.s8),
        Center(
          child: AppButton(
            key: const ValueKey<String>('trainerFindEmail-to-password-reset'),
            label: l.authForgotPassword,
            onPressed: _toPasswordReset,
            variant: AppButtonVariant.text,
            size: OnCareButtonSize.small,
          ),
        ),
      ],
    );
  }

  /// 가입 수단 이름. 모르는 수단은 뭉뚱그려 말한다 — 서버가 새 수단을 먼저 내도
  /// 화면이 원문 키(`naver`)를 그대로 그리지 않는다.
  String _providerLabel(AppLocalizations l, String provider) =>
      switch (provider) {
        'kakao' => l.findEmailProviderKakao,
        'google' => l.findEmailProviderGoogle,
        _ => l.findEmailProviderOther,
      };

  Widget _accountBanner(AppLocalizations l, int index, FoundEmailAccount a) {
    final String? masked = a.maskedEmail;
    if (masked != null) {
      return AppBanner(
        key: ValueKey<String>('trainerFindEmail-account-$index'),
        tone: AppBannerTone.success,
        icon: AppIcons.mail,
        title: masked,
        message: l.findEmailMaskedNote,
      );
    }
    final Set<String> labels = <String>{
      for (final String p in a.providers) _providerLabel(l, p),
    };
    return AppBanner(
      key: ValueKey<String>('trainerFindEmail-social-$index'),
      icon: AppIcons.person,
      title: l.findEmailSocialTitle(labels.join(' · ')),
      message: l.findEmailSocialBody,
    );
  }

  Widget _resultBody(AppLocalizations l, List<FoundEmailAccount> found) {
    // 재설정할 비밀번호가 있는 계정(이메일 가입)이 있을 때만 재설정으로 보낸다.
    final bool hasEmailAccount = found.any(
      (FoundEmailAccount a) => !a.isSocialOnly,
    );
    return Column(
      key: Key(
        found.isEmpty
            ? 'trainerFindEmailNotFoundStep'
            : 'trainerFindEmailFoundStep',
      ),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (found.isEmpty)
          AppBanner(
            key: const Key('trainerFindEmailNotFoundNotice'),
            tone: AppBannerTone.caution,
            title: l.findEmailNotFoundTitle,
            message: l.findEmailNotFoundBody,
          )
        else
          for (int i = 0; i < found.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: OnCareSpacing.s8),
            _accountBanner(l, i, found[i]),
          ],
        const SizedBox(height: OnCareSpacing.s24),
        if (found.isEmpty)
          AppButton(
            key: const ValueKey<String>('trainerFindEmail-retry'),
            label: l.findEmailRetry,
            onPressed: _retry,
            size: OnCareButtonSize.large,
            fullWidth: true,
          )
        else
          AppButton(
            key: const ValueKey<String>('trainerFindEmail-to-sign-in'),
            label: l.passwordResetBackToSignIn,
            onPressed: () => context.go(AppRoutes.signIn),
            size: OnCareButtonSize.large,
            fullWidth: true,
          ),
        const SizedBox(height: OnCareSpacing.s8),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: <Widget>[
              if (found.isEmpty)
                AppButton(
                  key: const ValueKey<String>('trainerFindEmail-to-sign-in'),
                  label: l.passwordResetBackToSignIn,
                  onPressed: () => context.go(AppRoutes.signIn),
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                )
              else
                AppButton(
                  key: const ValueKey<String>('trainerFindEmail-retry'),
                  label: l.findEmailRetry,
                  onPressed: _retry,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                ),
              if (hasEmailAccount)
                AppButton(
                  key: const ValueKey<String>(
                    'trainerFindEmail-result-password-reset',
                  ),
                  label: l.authForgotPassword,
                  onPressed: _toPasswordReset,
                  variant: AppButtonVariant.text,
                  size: OnCareButtonSize.small,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
