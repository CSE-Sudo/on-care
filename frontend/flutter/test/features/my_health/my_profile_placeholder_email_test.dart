/// 소셜 가입의 대체 이메일은 내 프로필에 보이지 않는다 — #3338.
///
/// 이메일을 주지 않는 소셜 계정으로 가입하면 서버가 계정 이메일 자리에
/// `kakao_…@social.oncare` 꼴의 내부용 주소를 넣는다. 회원에게는 자기 것이 아닌
/// 낯선 주소라, 보기에서는 가입 수단과 "이메일 미등록" 을, 수정에서는 빈 칸을
/// 보여 준다. 칸을 비워 둔 채 다른 칸만 고치는 저장은 이메일을 건드리지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/account_reauth_dialog.dart';
import 'package:oncare/features/my_health/presentation/widgets/email_change_code_dialog.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/mock_account_repository.dart';

const String _placeholder = 'kakao_4242@social.oncare';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

const Key _name = ValueKey<String>('my-profile-name');
const Key _email = ValueKey<String>('my-profile-email');

UserProfile _social({String? provider = 'kakao'}) => UserProfile(
  id: 'user-social',
  name: '김민수',
  email: _placeholder,
  emailIsPlaceholder: true,
  emailPlaceholderProvider: provider,
  phone: '010-1234-5678',
);

Future<(AppLocalizations, MockAccountRepository)> _open(
  WidgetTester tester, {
  required UserProfile profile,
  Locale locale = const Locale('ko'),
  bool edit = true,
}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final MockAccountRepository repository = MockAccountRepository(
    profile: profile,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repository),
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
  if (edit) {
    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
  }
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
  testWidgets('보기에서는 주소 대신 가입 수단과 미등록 안내를 보여 준다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _open(
      tester,
      profile: _social(),
      edit: false,
    );

    expect(find.text(_placeholder), findsNothing);
    expect(find.textContaining('social.oncare'), findsNothing);
    expect(find.text(l.myEmailUnregistered('kakao')), findsOneWidget);
    expect(l.myEmailUnregistered('kakao'), '카카오로 가입 · 이메일 미등록');
  });

  testWidgets('가입 수단을 모르면 소셜 로그인이라고만 말한다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _open(
      tester,
      profile: _social(provider: null),
      edit: false,
    );

    expect(find.textContaining('social.oncare'), findsNothing);
    expect(find.text(l.myEmailUnregistered('')), findsOneWidget);
    expect(l.myEmailUnregistered(''), '소셜 로그인으로 가입 · 이메일 미등록');
    expect(l.myEmailUnregistered('google'), '구글로 가입 · 이메일 미등록');
  });

  testWidgets('수정에서는 이메일 칸을 비운 채로 연다', (WidgetTester tester) async {
    final (AppLocalizations l, _) = await _open(tester, profile: _social());

    final AppTextField field = tester.widget<AppTextField>(find.byKey(_email));
    expect(field.controller?.text, isEmpty);
    expect(field.hint, l.myProfileEmailEmptyHint);
    expect(find.textContaining('social.oncare'), findsNothing);
  });

  testWidgets('이메일 칸을 비워 둔 채 이름만 고치면 이메일을 건드리지 않는다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _open(
      tester,
      profile: _social(),
    );

    await tester.enterText(find.byKey(_name), '김민수2');
    await _tapSave(tester, l);

    // 빈 칸을 형식 오류로 막지 않고, 본인 확인도 묻지 않는다.
    expect(find.text(l.authEmailInvalid), findsNothing);
    expect(find.byType(EmailChangeCodeDialog), findsNothing);
    expect(find.byType(AccountReauthDialog), findsNothing);
    expect(find.text(l.myProfileSaved), findsOneWidget);
    final UserProfile saved = await repo.fetchProfile();
    expect(saved.name, '김민수2');
    expect(saved.email, _placeholder);
    expect(saved.emailIsPlaceholder, isTrue);
    expect(repo.emailCodeRequests, isEmpty);
    await _drainToast(tester);
  });

  testWidgets('실제 주소를 넣으면 이메일 변경으로 보고 새 주소 확인부터 한다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _open(
      tester,
      profile: _social(),
    );

    await tester.enterText(find.byKey(_email), 'minsu.real@oncare.com');
    await _tapSave(tester, l);

    expect(repo.emailCodeRequests, <String>['minsu.real@oncare.com']);
    expect(find.byType(EmailChangeCodeDialog), findsOneWidget);
  });

  testWidgets('넣은 주소의 형식이 틀리면 칸 아래에 알린다', (WidgetTester tester) async {
    final (AppLocalizations l, MockAccountRepository repo) = await _open(
      tester,
      profile: _social(),
    );

    await tester.enterText(find.byKey(_email), 'not-an-email');
    await _tapSave(tester, l);

    expect(find.text(l.authEmailInvalid), findsOneWidget);
    expect(repo.emailCodeRequests, isEmpty);
  });

  testWidgets('실제 이메일이 있는 회원의 화면은 그대로다', (WidgetTester tester) async {
    const UserProfile real = UserProfile(
      id: 'user-real',
      name: '김민수',
      email: 'minsu@oncare.com',
      phone: '010-1234-5678',
    );
    final (AppLocalizations l, _) = await _open(
      tester,
      profile: real,
      edit: false,
    );

    expect(find.text('minsu@oncare.com'), findsOneWidget);
    expect(find.text(l.myEmailUnregistered('')), findsNothing);

    await tester.tap(find.byKey(const Key('profileEditButton')));
    await tester.pumpAndSettle();
    final AppTextField field = tester.widget<AppTextField>(find.byKey(_email));
    expect(field.controller?.text, 'minsu@oncare.com');
    expect(field.hint, isNull);
  });
}
