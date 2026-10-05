import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/auth_input_error_text.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 아이디 찾기 화면의 칸.
enum FindEmailField { name, phone }

/// 아이디(가입 이메일) 찾기 — 로그인 화면의 `아이디 찾기` 가 연다.
///
/// 비밀번호 재설정(#2824)과 같은 틀이다. 가입할 때 받은 이름과 휴대폰 번호를
/// 넣는다(트레이너 가입은 번호를 받지 않아 회원 앱에만 있다).
///
/// **아직 찾기는 동작하지 않는다.** 서버에 찾는 경로가 없고, 번호의 주인을
/// 확인할 수단(문자 인증)도 없다. 확인 없이 이메일을 알려 주면 남의 번호로 가입
/// 여부와 이메일을 알아낼 수 있으므로, 어떻게 알려 줄지(가린 이메일·안내 메일 등)
/// 정하기 전까지는 입력만 검사하고 요청을 보내지 않은 채 준비 중이라고 안내한다.
class FindEmailPage extends StatefulWidget {
  const FindEmailPage({super.key});

  @override
  State<FindEmailPage> createState() => _FindEmailPageState();
}

class _FindEmailPageState extends State<FindEmailPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();

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
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.signIn);
    }
  }

  /// 입력만 검사한다 — 찾는 경로가 생기기 전이라 요청은 보내지 않는다.
  void _find() {
    if (!_errors.validate(FindEmailField.values)) {
      setState(() {});
      return;
    }
    showAppToast(context, AppLocalizations.of(context).findEmailComingSoon);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppAuthLayout(
      key: const Key('findEmailPage'),
      leading: AppBackButton(onPressed: _back),
      title: l.findEmailTitle,
      subtitle: l.findEmailSubtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppTextField(
            key: const ValueKey<String>('findEmail-name'),
            controller: _name,
            hint: l.signUpNameHint,
            errorText: _errors.of(FindEmailField.name),
            prefixIcon: AppIcons.person,
            size: AppFieldSize.large,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.name],
            onChanged: _onEdited,
          ),
          const SizedBox(height: OnCareSpacing.s12),
          AppTextField(
            key: const ValueKey<String>('findEmail-phone'),
            controller: _phone,
            hint: l.signUpPhoneHint,
            errorText: _errors.of(FindEmailField.phone),
            prefixIcon: AppIcons.phone,
            size: AppFieldSize.large,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            // 가입 화면과 같은 국내 번호 — 숫자만 쳐도 하이픈이 들어간다.
            autofillHints: const <String>[
              AutofillHints.telephoneNumberNational,
            ],
            inputFormatters: const <TextInputFormatter>[
              AppPhoneNumberFormatter(),
            ],
            onChanged: _onEdited,
            onSubmitted: (_) => _find(),
          ),
          const SizedBox(height: OnCareSpacing.s24),
          AppButton(
            key: const ValueKey<String>('findEmail-submit'),
            label: l.findEmailAction,
            onPressed: _find,
            size: OnCareButtonSize.large,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          // 로그인 화면의 소셜 '준비 중' 안내와 같은 자리·모양이다(#2769).
          Text(
            l.findEmailComingSoon,
            key: const ValueKey<String>('findEmail-soon'),
            textAlign: TextAlign.center,
            style: context.oncare
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Center(
            child: AppButton(
              key: const ValueKey<String>('findEmail-to-password-reset'),
              label: l.authForgotPassword,
              onPressed: () => context.pushReplacement(AppRoutes.passwordReset),
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
            ),
          ),
        ],
      ),
    );
  }
}
