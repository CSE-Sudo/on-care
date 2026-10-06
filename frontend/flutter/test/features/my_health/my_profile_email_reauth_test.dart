/// 내 프로필에서 이메일을 바꿀 때만 본인 확인을 거친다 — #3039.
///
/// 이메일은 로그인 아이디이자 비밀번호 재설정 메일이 가는 주소다. 로그인
/// 토큰만으로 바꿀 수 있으면, 잠기지 않은 폰을 잠깐 집어 든 사람이 이메일을
/// 자기 것으로 바꾸고 비밀번호 재설정으로 계정을 가져간다. 그래서 이메일이
/// 바뀌는 저장에서만 현재 비밀번호(소셜 전용 계정은 다시 로그인)를 묻는다.
///
/// 본인 확인 앞에서 새 주소의 주인인지도 본다(#3230) — 새 주소로 보낸 6자리
/// 코드를 받아 온 뒤에야 본인 확인 창이 뜬다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/measure_update.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/domain/repositories/password_repository.dart'
    show ReissuedTokens;
import 'package:oncare/features/auth/domain/signup_email_code.dart';
import 'package:oncare/features/my_health/presentation/widgets/account_reauth_dialog.dart';
import 'package:oncare/features/my_health/presentation/widgets/email_change_code_dialog.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

/// 본인 확인에서 맞다고 보는 현재 비밀번호. 테스트 전용 값이다.
const String _currentPassword = 'pw-current-1';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

const Key _name = ValueKey<String>('my-profile-name');
const Key _email = ValueKey<String>('my-profile-email');
Finder _dialog() => find.byType(AccountReauthDialog);
Finder _password() => find.byKey(const ValueKey<String>('reauth-password'));
Finder _confirm() => find.byKey(const ValueKey<String>('reauth-confirm'));

AppButton _confirmButton(WidgetTester tester) =>
    tester.widget<AppButton>(_confirm());

Finder _codeDialog() => find.byType(EmailChangeCodeDialog);
Finder _code() => find.byKey(const ValueKey<String>('email-change-code'));
Finder _codeConfirm() =>
    find.byKey(const ValueKey<String>('email-change-code-confirm'));

/// 새 이메일 인증 창에 코드를 적고 넘어간다(#3230). 대역은 데모 코드를 받는다.
Future<void> _passCode(
  WidgetTester tester, {
  String code = SignupEmailCode.demoCode,
}) async {
  expect(_codeDialog(), findsOneWidget);
  await tester.enterText(_code(), code);
  await tester.pump();
  await tester.tap(_codeConfirm());
  await tester.pumpAndSettle();
}

const UserProfile _socialOnly = UserProfile(
  id: 'user-social',
  name: '김민수',
  email: 'minsu@oncare.com',
  phone: '010-1234-5678',
  hasPassword: false,
);

/// 저장 요청을 [gate] 가 풀릴 때까지 붙드는 대역 — 요청 도중 창이 닫히는 경우를 본다.
class _HeldAccountRepository extends MockAccountRepository {
  _HeldAccountRepository() : super(currentPassword: _currentPassword);

  Completer<void>? gate;

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? birthDate,
    String? gender,
    MeasureUpdate? heightCm,
    MeasureUpdate? weightKg,
    AccountReauth? reauth,
    String? emailCode,
    void Function(ReissuedTokens tokens)? onTokensReissued,
  }) async {
    await gate?.future;
    return super.updateProfile(
      name: name,
      email: email,
      phone: phone,
      birthDate: birthDate,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      reauth: reauth,
      emailCode: emailCode,
      onTokensReissued: onTokensReissued,
    );
  }
}

Future<(AppLocalizations, MockAccountRepository)> _openProfile(
  WidgetTester tester, {
  UserProfile? profile,
  Locale locale = const Locale('ko'),
  MockAccountRepository? repository,
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  repository ??= profile == null
      ? MockAccountRepository(currentPassword: _currentPassword)
      : MockAccountRepository(
          profile: profile,
          currentPassword: _currentPassword,
        );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
        // 소셜 다시 로그인은 기기 안 목업 설정에서만 열린다.
        appConfigProvider.overrideWithValue(_mockConfig),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProfileSettingsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('profileEditButton')));
  await tester.pumpAndSettle();
  return (
    AppLocalizations.of(tester.element(find.byType(ProfileSettingsPage))),
    repository,
  );
}

Future<void> _tapSave(WidgetTester tester, AppLocalizations l) async {
  await tester.ensureVisible(find.text(l.mySave));
  await tester.tap(find.text(l.mySave));
  await tester.pumpAndSettle();
}

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastErrorVisible);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이메일을 그대로 두면 본인 확인 없이 저장한다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_name), '김민수2');
    await _tapSave(tester, l);

    expect(_dialog(), findsNothing);
    expect(find.text(l.myProfileSaved), findsOneWidget);
    expect((await repo.fetchProfile()).name, '김민수2');
    expect(repo.lastReauth, isNull);
    await _drainToast(tester);
  });

  testWidgets('대소문자만 다른 이메일은 같은 주소라 묻지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'Minsu@OnCare.com');
    await _tapSave(tester, l);

    expect(_dialog(), findsNothing);
    expect(repo.lastReauth, isNull);
    await _drainToast(tester);
  });

  testWidgets('이메일을 바꾸면 무엇이 바뀌는지 말하고 현재 비밀번호를 묻는다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await _passCode(tester);

    expect(_dialog(), findsOneWidget);
    expect(find.text(l.reauthTitle), findsOneWidget);
    expect(find.text(l.reauthEmailMessage), findsOneWidget);
    expect(_password(), findsOneWidget);
    // 비밀번호를 적기 전에는 확정할 수 없다.
    expect(_confirmButton(tester).onPressed, isNull);
    // 창이 떠 있는 동안에는 아직 저장되지 않았다.
    expect((await repo.fetchProfile()).email, 'minsu@oncare.com');

    await tester.enterText(_password(), _currentPassword);
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(_dialog(), findsNothing);
    expect(find.text(l.myProfileSaved), findsOneWidget);
    expect((await repo.fetchProfile()).email, 'minsu.new@oncare.com');
    expect(repo.lastReauth?.currentPassword, _currentPassword);
    // 새 주소로 받은 코드를 함께 보낸다(#3230).
    expect(repo.lastEmailCode, SignupEmailCode.demoCode);
    // 서버가 새로 준 토큰을 받아 넣을 자리를 함께 넘긴다.
    expect(repo.lastTokensReissued, isNotNull);
    await _drainToast(tester);
  });

  testWidgets('비밀번호가 틀리면 창 안에 알리고 저장하지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await _passCode(tester);
    await tester.enterText(_password(), 'wrong-password');
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(_dialog(), findsOneWidget);
    expect(
      tester.widget<AppTextField>(_password()).errorText,
      l.passwordChangeWrongCurrent,
    );
    expect((await repo.fetchProfile()).email, 'minsu@oncare.com');
    expect(find.text(l.mySaveFailed), findsNothing);
  });

  testWidgets('요청 중 창이 다른 길로 닫혀도 저장이 끝나면 저장된 것으로 다룬다 (#3245)', (
    WidgetTester tester,
  ) async {
    final _HeldAccountRepository held = _HeldAccountRepository();
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
      repository: held,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await _passCode(tester);
    held.gate = Completer<void>();
    await tester.enterText(_password(), _currentPassword);
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pump();

    // 창만 걷어 낸다 — 결과 없이 닫히면 부른 쪽은 `취소` 로 받는다.
    Navigator.of(tester.element(_dialog())).pop();
    await tester.pumpAndSettle();
    expect(_dialog(), findsNothing);

    held.gate!.complete();
    await tester.pumpAndSettle();

    // 서버에서는 바뀌었으니 편집 상태로 남지 않고 저장됨을 알린다.
    expect((await repo.fetchProfile()).email, 'minsu.new@oncare.com');
    expect(find.text(l.myProfileSaved), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('취소하면 저장하지 않고 편집 상태로 돌아간다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await _passCode(tester);
    await tester.tap(find.byKey(const ValueKey<String>('reauth-cancel')));
    await tester.pumpAndSettle();

    expect(_dialog(), findsNothing);
    expect((await repo.fetchProfile()).email, 'minsu@oncare.com');
    // 바꾼 값이 칸에 그대로 남아 다시 저장할 수 있다.
    expect(find.text('minsu.new@oncare.com'), findsOneWidget);
    expect(find.text(l.mySave), findsOneWidget);
  });

  testWidgets('소셜 전용 계정은 비밀번호 칸 대신 소셜 다시 로그인을 보인다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
      profile: _socialOnly,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await _passCode(tester);

    expect(_dialog(), findsOneWidget);
    expect(_password(), findsNothing);
    expect(find.text(l.reauthSocialAction), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('reauth-social-google')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l.reauthSocialConfirmed), findsOneWidget);

    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(_dialog(), findsNothing);
    expect(repo.lastReauth?.socialProvider, 'google');
    expect(repo.lastReauth?.socialToken, 'demo-google-token');
    expect(repo.lastReauth?.currentPassword, isNull);
    expect((await repo.fetchProfile()).email, 'minsu.new@oncare.com');
    await _drainToast(tester);
  });

  testWidgets('영어 화면에서는 영어 문구다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openProfile(
      tester,
      locale: const Locale('en'),
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    expect(find.text('Verify your new email'), findsOneWidget);
    await _passCode(tester);

    expect(
      find.text(
        'Changing your email changes your sign-in ID and the address '
        'password reset emails go to.',
      ),
      findsOneWidget,
    );
    expect(find.text("Confirm it's you"), findsOneWidget);
  });

  testWidgets('이메일을 바꾸면 본인 확인보다 먼저 새 주소로 인증 코드를 받는다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);

    expect(_codeDialog(), findsOneWidget);
    expect(_dialog(), findsNothing);
    expect(find.text(l.emailChangeCodeTitle), findsOneWidget);
    expect(
      find.text(l.emailChangeCodeMessage('minsu.new@oncare.com')),
      findsOneWidget,
    );
    // 창이 뜨자마자 새 주소로 코드를 요청한다 — 옛 주소가 아니다.
    expect(repo.emailCodeRequests, <String>['minsu.new@oncare.com']);
    // 여섯 자리를 다 적기 전에는 넘어갈 수 없다.
    await tester.enterText(_code(), '123');
    await tester.pump();
    expect(tester.widget<AppButton>(_codeConfirm()).onPressed, isNull);
    await tester.enterText(_code(), '000000');
    await tester.pump();
    expect(tester.widget<AppButton>(_codeConfirm()).onPressed, isNotNull);
    // 데모(기기 안 목업)는 메일을 보내지 않으므로 받아 주는 코드를 안내한다.
    expect(
      find.byKey(const ValueKey<String>('email-change-code-demo')),
      findsOneWidget,
    );
    // 다시 받기는 기다린 뒤에만 켜진다.
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey<String>('email-change-code-resend')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(_codeConfirm());
    await tester.pumpAndSettle();
    expect(_codeDialog(), findsNothing);
    expect(_dialog(), findsOneWidget);
  });

  testWidgets('코드 창에서 취소하면 본인 확인도 저장도 하지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await tester.tap(
      find.byKey(const ValueKey<String>('email-change-code-cancel')),
    );
    await tester.pumpAndSettle();

    expect(_codeDialog(), findsNothing);
    expect(_dialog(), findsNothing);
    expect((await repo.fetchProfile()).email, 'minsu@oncare.com');
    expect(repo.lastReauth, isNull);
    // 편집 상태 그대로라 다시 저장할 수 있다.
    expect(find.text(l.mySave), findsOneWidget);
  });

  testWidgets('코드가 틀리면 이메일은 그대로이고 코드를 다시 받으라고 알린다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await _passCode(tester, code: '123456');
    await tester.enterText(_password(), _currentPassword);
    await tester.pump();
    await tester.tap(_confirm());
    await tester.pumpAndSettle();

    expect(_dialog(), findsNothing);
    expect(find.text(l.signUpEmailCodeInvalid), findsOneWidget);
    expect((await repo.fetchProfile()).email, 'minsu@oncare.com');
    expect(find.text(l.mySave), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('코드를 보낼 수 없으면 창 안에 이유를 보이고 넘어가지 않는다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );
    repo.failNextEmailCode = const SignupEmailCodeError(
      SignupEmailCodeFailure.unavailable,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);

    expect(_codeDialog(), findsOneWidget);
    expect(find.text(l.signUpEmailCodeUnavailable), findsOneWidget);
    expect(tester.widget<AppButton>(_codeConfirm()).onPressed, isNull);
    // 다시 받기로 이어 갈 수 있다.
    await tester.tap(
      find.byKey(const ValueKey<String>('email-change-code-resend')),
    );
    await tester.pumpAndSettle();
    expect(repo.emailCodeRequests, hasLength(2));
    expect(find.text(l.signUpEmailCodeUnavailable), findsNothing);
  });

  // 적던 코드와 요청 결과가 사라지지 않게 `취소` 로만 닫는다(#3245).
  testWidgets('코드 창은 바깥을 눌러도 닫히지 않는다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _openProfile(tester);

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(_codeDialog(), findsOneWidget);

    // 다시 받기 카운트다운을 멈추려고 창을 닫는다.
    await tester.tap(
      find.byKey(const ValueKey<String>('email-change-code-cancel')),
    );
    await tester.pumpAndSettle();
    expect(_codeDialog(), findsNothing);
  });
}
