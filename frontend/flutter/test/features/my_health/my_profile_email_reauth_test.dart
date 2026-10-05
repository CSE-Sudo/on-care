/// 내 프로필에서 이메일을 바꿀 때만 본인 확인을 거친다 — #3039.
///
/// 이메일은 로그인 아이디이자 비밀번호 재설정 메일이 가는 주소다. 로그인
/// 토큰만으로 바꿀 수 있으면, 잠기지 않은 폰을 잠깐 집어 든 사람이 이메일을
/// 자기 것으로 바꾸고 비밀번호 재설정으로 계정을 가져간다. 그래서 이메일이
/// 바뀌는 저장에서만 현재 비밀번호(소셜 전용 계정은 다시 로그인)를 묻는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/account_reauth_dialog.dart';
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

const UserProfile _socialOnly = UserProfile(
  id: 'user-social',
  name: '김민수',
  email: 'minsu@oncare.com',
  phone: '010-1234-5678',
  hasPassword: false,
);

Future<(AppLocalizations, MockAccountRepository)> _openProfile(
  WidgetTester tester, {
  UserProfile? profile,
  Locale locale = const Locale('ko'),
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final MockAccountRepository repository = profile == null
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

  testWidgets('취소하면 저장하지 않고 편집 상태로 돌아간다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _openProfile(
      tester,
    );

    await tester.enterText(find.byKey(_email), 'minsu.new@oncare.com');
    await _tapSave(tester, l);
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

    expect(
      find.text(
        'Changing your email changes your sign-in ID and the address '
        'password reset emails go to.',
      ),
      findsOneWidget,
    );
    expect(find.text("Confirm it's you"), findsOneWidget);
  });
}
