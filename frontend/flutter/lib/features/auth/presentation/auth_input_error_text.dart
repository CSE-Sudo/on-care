import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 공용 입력 규칙의 오류 종류 → 칸 아래에 그릴 회원앱 문구(#1784).
///
/// 규칙은 두 앱이 `oncare_ui` 의 [AppInputRules] 를 함께 쓰고, 문구만 앱마다
/// 로케일 파일에 둔다. 오류가 없으면 null — [AppTextField.errorText] 에 그대로
/// 넘기면 된다.
String? authInputErrorText(AppLocalizations l, AppInputError? error) =>
    switch (error) {
      null => null,
      AppInputError.nameEmpty => l.signUpNameEmpty,
      AppInputError.emailEmpty => l.authEmailEmpty,
      AppInputError.emailInvalid => l.authEmailInvalid,
      AppInputError.phoneInvalid => l.signUpPhoneFormatInvalid,
      AppInputError.passwordEmpty => l.authPasswordEmpty,
      AppInputError.passwordWeak => l.signUpPasswordWeak,
      AppInputError.passwordMismatch => l.signUpPasswordMismatch,
    };
