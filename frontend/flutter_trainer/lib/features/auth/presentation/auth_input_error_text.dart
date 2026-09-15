import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 공용 입력 규칙의 오류 종류 → 칸 아래에 그릴 트레이너웹 문구(#1784).
///
/// 규칙은 두 앱이 `oncare_ui` 의 [AppInputRules] 를 함께 쓰고, 문구만 앱마다
/// 로케일 파일에 둔다. 오류가 없으면 null — [AppTextField.errorText] 에 그대로
/// 넘기면 된다.
String? authInputErrorText(AppLocalizations l, AppInputError? error) =>
    switch (error) {
      null => null,
      AppInputError.nameEmpty => l.authErrNameEmpty,
      AppInputError.emailEmpty => l.authErrEmailEmpty,
      AppInputError.emailInvalid => l.authErrEmailInvalid,
      // 트레이너 가입에는 전화번호 칸이 없다. 공용 종류를 빠짐없이 옮기려고 둔다.
      AppInputError.phoneInvalid => l.authErrPhoneInvalid,
      AppInputError.passwordEmpty => l.authErrPasswordEmpty,
      AppInputError.passwordWeak => l.authErrPasswordWeak,
      AppInputError.passwordMismatch => l.authErrPasswordMismatch,
    };
