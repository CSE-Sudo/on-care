/// 트레이너 웹 로그인의 `이메일 찾기` 와 이메일 찾기 화면(#3439).
///
/// 회원 앱(#3337)과 같은 화면이다. 입구·뒤로 가기·입력 검사와, 찾은 결과(찾음·
/// 소셜 가입·없음)·실패 안내·결과에서 로그인·비밀번호 재설정으로 가는 길을 본다.
/// 요청은 대역 저장소가 받고, 데모 빌드의 목업이 데모 트레이너를 찾는지도 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/data/repositories/find_email_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/find_email_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_find_email_page.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_password_reset_page.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// 정해 둔 결과를 돌려주고 받은 요청을 적어 두는 대역.
class _FakeFindEmail implements FindEmailRepository {
  _FakeFindEmail({this.accounts = const <FoundEmailAccount>[], this.error});

  final List<FoundEmailAccount> accounts;
  final Object? error;
  final List<(String, String)> calls = <(String, String)>[];

  @override
  Future<List<FoundEmailAccount>> find({
    required String name,
    required String phone,
  }) async {
    calls.add((name, phone));
    final Object? e = error;
    if (e != null) throw e;
    return accounts;
  }
}

/// 앱을 띄운다. [repository] 를 주지 않으면 데모 빌드의 목업을 그대로 쓴다.
Future<AppLocalizations> _pump(
  WidgetTester tester, {
  FindEmailRepository? repository,
  String? at,
}) async {
  await pumpTrainerApp(
    tester,
    at: at,
    extraOverrides: <Override>[
      if (repository != null)
        findEmailRepositoryProvider.overrideWithValue(repository),
    ],
  );
  await settle(tester);
  return AppLocalizations.of(tester.element(find.byType(Navigator).first));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// 이름·번호를 넣고 찾기를 누른다.
Future<void> _submit(
  WidgetTester tester, {
  String name = ' 김코치 ',
  String phone = '01012345678',
}) async {
  await tester.enterText(_key('trainerFindEmail-name'), name);
  await tester.enterText(_key('trainerFindEmail-phone'), phone);
  await settle(tester);
  await _tap(tester, _key('trainerFindEmail-submit'));
}

String? _errorOf(WidgetTester tester, String key) =>
    tester.widget<AppTextField>(_key(key)).errorText;

void main() {
  testWidgets('로그인 화면의 이메일 찾기가 비밀번호 찾기 옆에서 화면을 연다', (tester) async {
    final AppLocalizations l = await _pump(tester);

    expect(find.text(l.authFindEmail), findsOneWidget);
    expect(find.text(l.authForgotPassword), findsOneWidget);
    final Rect findEmail = tester.getRect(_key('trainer-login-find-email'));
    final Rect forgot = tester.getRect(_key('trainer-login-forgot-password'));
    expect(findEmail.center.dy, forgot.center.dy);
    expect(findEmail.right, lessThanOrEqualTo(forgot.left));

    await _tap(tester, _key('trainer-login-find-email'));
    expect(find.byType(TrainerFindEmailPage), findsOneWidget);
    expect(find.text(l.findEmailSubtitle), findsOneWidget);
    // 찾기 전에는 결과가 없다.
    expect(find.byKey(const Key('trainerFindEmailFormStep')), findsOneWidget);
    expect(find.byKey(const Key('trainerFindEmailFoundStep')), findsNothing);
    expect(find.byKey(const Key('trainerFindEmailNotFoundStep')), findsNothing);

    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(TrainerSignInPage), findsOneWidget);
  });

  testWidgets('비어 있거나 형식이 틀리면 칸 아래에 오류를 띄우고 요청하지 않는다', (tester) async {
    final _FakeFindEmail repo = _FakeFindEmail();
    await _pump(tester, at: AppRoutes.findEmail, repository: repo);
    expect(find.byType(TrainerFindEmailPage), findsOneWidget);

    await _tap(tester, _key('trainerFindEmail-submit'));
    expect(_errorOf(tester, 'trainerFindEmail-name'), isNotNull);
    expect(_errorOf(tester, 'trainerFindEmail-phone'), isNotNull);

    await tester.enterText(_key('trainerFindEmail-name'), '김코치');
    await tester.enterText(_key('trainerFindEmail-phone'), '0101234');
    await settle(tester);
    await _tap(tester, _key('trainerFindEmail-submit'));
    expect(_errorOf(tester, 'trainerFindEmail-name'), isNull);
    expect(_errorOf(tester, 'trainerFindEmail-phone'), isNotNull);
    expect(repo.calls, isEmpty);
  });

  testWidgets('맞으면 가려진 이메일을 보여 준다', (tester) async {
    final _FakeFindEmail repo = _FakeFindEmail(
      accounts: const <FoundEmailAccount>[
        FoundEmailAccount(maskedEmail: 'co***@oncare.com'),
      ],
    );
    final AppLocalizations l = await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: repo,
    );

    await tester.enterText(_key('trainerFindEmail-name'), ' 김코치 ');
    // 숫자만 쳐도 가입 화면처럼 하이픈이 들어간다.
    await tester.enterText(_key('trainerFindEmail-phone'), '01012345678');
    await settle(tester);
    expect(find.text('010-1234-5678'), findsOneWidget);
    await _tap(tester, _key('trainerFindEmail-submit'));

    // 앞뒤 공백을 자른 이름과 하이픈이 든 번호를 보낸다.
    expect(repo.calls, <(String, String)>[('김코치', '010-1234-5678')]);
    expect(find.byKey(const Key('trainerFindEmailFoundStep')), findsOneWidget);
    expect(find.byKey(const Key('trainerFindEmailFormStep')), findsNothing);
    expect(find.text('co***@oncare.com'), findsOneWidget);
    expect(find.text(l.findEmailMaskedNote), findsOneWidget);
    expect(find.text(l.findEmailFoundSubtitle), findsOneWidget);
  });

  testWidgets('같은 번호의 계정이 여럿이면 모두 보여 준다', (tester) async {
    await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(maskedEmail: 'al***@oncare.com'),
          FoundEmailAccount(maskedEmail: 'br***@example.com'),
        ],
      ),
    );
    await _submit(tester);

    expect(_key('trainerFindEmail-account-0'), findsOneWidget);
    expect(_key('trainerFindEmail-account-1'), findsOneWidget);
    expect(find.text('al***@oncare.com'), findsOneWidget);
    expect(find.text('br***@example.com'), findsOneWidget);
  });

  testWidgets('소셜 가입 계정은 이메일 대신 가입 수단을 안내한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(providers: <String>['google']),
        ],
      ),
    );
    await _submit(tester);

    expect(_key('trainerFindEmail-social-0'), findsOneWidget);
    expect(
      find.text(l.findEmailSocialTitle(l.findEmailProviderGoogle)),
      findsOneWidget,
    );
    expect(find.text(l.findEmailSocialBody), findsOneWidget);
    // 재설정할 비밀번호가 없는 계정뿐이면 재설정으로 보내지 않는다.
    expect(_key('trainerFindEmail-result-password-reset'), findsNothing);
    expect(_key('trainerFindEmail-to-sign-in'), findsOneWidget);
  });

  testWidgets('맞는 계정이 없으면 오류가 아니라 찾지 못했다고 안내한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: _FakeFindEmail(),
    );
    await _submit(tester);

    expect(
      find.byKey(const Key('trainerFindEmailNotFoundStep')),
      findsOneWidget,
    );
    expect(find.text(l.findEmailNotFoundTitle), findsOneWidget);
    expect(find.text(l.findEmailNotFoundBody), findsOneWidget);
    expect(find.text(l.passwordResetTemporaryFailure), findsNothing);
    expect(_key('trainerFindEmail-result-password-reset'), findsNothing);
  });

  testWidgets('다시 찾기를 누르면 넣었던 값이 남은 입력 단계로 돌아간다', (tester) async {
    await _pump(tester, at: AppRoutes.findEmail, repository: _FakeFindEmail());
    await _submit(tester);
    await _tap(tester, _key('trainerFindEmail-retry'));

    expect(find.byKey(const Key('trainerFindEmailFormStep')), findsOneWidget);
    expect(find.text('010-1234-5678'), findsOneWidget);
  });

  testWidgets('결과에서 로그인 화면으로 간다', (tester) async {
    await _pump(
      tester,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(maskedEmail: 'co***@oncare.com'),
        ],
      ),
    );
    await _tap(tester, _key('trainer-login-find-email'));
    await _submit(tester);
    await _tap(tester, _key('trainerFindEmail-to-sign-in'));
    expect(find.byType(TrainerSignInPage), findsOneWidget);
    expect(find.byType(TrainerFindEmailPage), findsNothing);
  });

  testWidgets('이메일로 가입한 계정을 찾았으면 결과에서 비밀번호 재설정으로 간다', (tester) async {
    await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        accounts: const <FoundEmailAccount>[
          FoundEmailAccount(maskedEmail: 'co***@oncare.com'),
        ],
      ),
    );
    await _submit(tester);
    await _tap(tester, _key('trainerFindEmail-result-password-reset'));
    expect(find.byType(TrainerPasswordResetPage), findsOneWidget);
  });

  testWidgets('연속 시도로 막히면 그 안내를 띄우고 입력 단계에 머문다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: _FakeFindEmail(
        error: const FindEmailError(FindEmailFailure.tooMany),
      ),
    );
    await _submit(tester);

    expect(find.text(l.passwordResetTooMany), findsOneWidget);
    expect(find.byKey(const Key('trainerFindEmailFormStep')), findsOneWidget);
    expect(find.byKey(const Key('trainerFindEmailNotFoundStep')), findsNothing);
  });

  testWidgets('연결 실패는 찾지 못함이 아니라 다시 시도 안내다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      at: AppRoutes.findEmail,
      repository: _FakeFindEmail(error: StateError('offline')),
    );
    await _submit(tester);

    expect(find.text(l.passwordResetTemporaryFailure), findsOneWidget);
    expect(find.text(l.findEmailNotFoundTitle), findsNothing);
    expect(find.byKey(const Key('trainerFindEmailFormStep')), findsOneWidget);
  });

  testWidgets('데모 빌드는 데모 트레이너의 이름·번호로 가린 이메일을 찾는다', (tester) async {
    await _pump(tester, at: AppRoutes.findEmail);
    await _submit(
      tester,
      name: seedTrainerProfile.name,
      phone: seedTrainerProfile.phone.replaceAll('-', ''),
    );

    expect(find.byKey(const Key('trainerFindEmailFoundStep')), findsOneWidget);
    expect(
      find.text(MockFindEmailRepository.maskEmail(seedTrainerProfile.email)),
      findsOneWidget,
    );
    expect(find.text(seedTrainerProfile.email), findsNothing);
  });

  testWidgets('비밀번호도 잊었으면 재설정 화면으로 넘어간다', (tester) async {
    await _pump(tester, at: AppRoutes.findEmail, repository: _FakeFindEmail());

    await _tap(tester, _key('trainerFindEmail-to-password-reset'));
    expect(find.byType(TrainerPasswordResetPage), findsOneWidget);
  });

  test('이메일 찾기는 가입처럼 로그아웃 상태에서만 머문다', () {
    expect(
      sessionRedirect(SessionStatus.signedOut, AppRoutes.findEmail),
      isNull,
    );
    expect(sessionRedirect(SessionStatus.unknown, AppRoutes.findEmail), isNull);
    expect(
      sessionRedirect(SessionStatus.demo, AppRoutes.findEmail),
      AppRoutes.dashboard,
    );
    expect(
      sessionRedirect(SessionStatus.authenticated, AppRoutes.findEmail),
      AppRoutes.dashboard,
    );
    // 로그인 뒤 이어 갈 자리로 남지 않는다.
    expect(AppRoutes.isRestorable(AppRoutes.findEmail), isFalse);
  });
}
