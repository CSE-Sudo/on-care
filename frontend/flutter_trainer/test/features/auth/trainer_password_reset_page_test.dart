/// 트레이너 웹 로그인의 `비밀번호를 잊으셨나요?` 와 비밀번호 재설정 화면(#2824).
///
/// 앱 라우터를 그대로 띄워 본다 — 로그아웃 상태에서 재설정 주소가 로그인
/// 화면으로 튕기지 않는지, 메일 링크(`?token=`)로 바로 열리는지까지가 대상이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/data/repositories/password_reset_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/password_reset_repository.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_password_reset_page.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

const String _code = 'ABCD-EFGH-JKMN-PQRS';
const String _newPw = 'new-pass-2';

/// 받은 요청을 적고, 정해 둔 대로 답하는 리포지토리.
class _FakeReset implements PasswordResetRepository {
  _FakeReset({this.requestError, this.confirmError});

  final PasswordResetError? requestError;
  final PasswordResetError? confirmError;
  final List<String> requested = <String>[];
  final List<(String, String)> confirmed = <(String, String)>[];

  @override
  Future<PasswordResetRequested> requestReset({required String email}) async {
    requested.add(email);
    final PasswordResetError? e = requestError;
    if (e != null) throw e;
    return const PasswordResetRequested(expiresInMinutes: 30);
  }

  @override
  Future<void> confirmReset({
    required String code,
    required String newPassword,
  }) async {
    confirmed.add((code, newPassword));
    final PasswordResetError? e = confirmError;
    if (e != null) throw e;
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  PasswordResetRepository? repository,
  String? bootAt,
}) async {
  await pumpTrainerApp(
    tester,
    seed: false,
    bootAt: bootAt,
    extraOverrides: <Override>[
      if (repository != null)
        passwordResetRepositoryProvider.overrideWithValue(repository),
    ],
  );
  return AppLocalizations.of(tester.element(find.byType(Navigator).first));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(of: _key(key), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

Future<void> _fillConfirm(
  WidgetTester tester, {
  String? code,
  String next = _newPw,
}) async {
  if (code != null) await _enter(tester, 'passwordReset-code', code);
  await _enter(tester, 'passwordReset-next', next);
  await _enter(tester, 'passwordReset-confirm', next);
}

void main() {
  testWidgets('로그인 화면의 비밀번호 찾기가 재설정 화면을 연다', (tester) async {
    final AppLocalizations l = await _pump(tester, repository: _FakeReset());
    expect(find.byType(TrainerSignInPage), findsOneWidget);
    expect(find.text(l.authForgotPassword), findsOneWidget);
    await _tap(tester, _key('trainer-login-forgot-password'));
    expect(find.byType(TrainerPasswordResetPage), findsOneWidget);
    expect(find.byKey(const Key('passwordResetRequestStep')), findsOneWidget);
  });

  testWidgets('뒤로 가면 로그인 화면으로 돌아간다', (tester) async {
    await _pump(tester, repository: _FakeReset());
    await _tap(tester, _key('trainer-login-forgot-password'));
    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(TrainerSignInPage), findsOneWidget);
  });

  testWidgets('로그아웃 상태로 재설정 주소를 열어도 로그인 화면으로 튕기지 않는다', (tester) async {
    await _pump(
      tester,
      repository: _FakeReset(),
      bootAt: AppRoutes.passwordReset,
    );
    expect(find.byType(TrainerPasswordResetPage), findsOneWidget);
    expect(find.byType(TrainerSignInPage), findsNothing);
  });

  testWidgets('이메일 형식이 틀리면 요청하지 않는다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      bootAt: AppRoutes.passwordReset,
    );
    await _enter(tester, 'passwordReset-email', 'not-an-email');
    await _tap(tester, _key('passwordReset-send'));
    expect(repo.requested, isEmpty);
    expect(find.text(l.authErrEmailInvalid), findsOneWidget);
  });

  testWidgets('요청하면 같은 안내와 함께 코드 입력 단계로 간다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      bootAt: AppRoutes.passwordReset,
    );
    await _enter(tester, 'passwordReset-email', ' trainer@example.com ');
    await _tap(tester, _key('passwordReset-send'));
    expect(repo.requested, <String>['trainer@example.com']);
    expect(find.byKey(const Key('passwordResetConfirmStep')), findsOneWidget);
    expect(
      find.text(l.passwordResetSentBody('trainer@example.com', 30)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('passwordResetDemoNotice')), findsNothing);
  });

  testWidgets('코드를 넣고 바꾸면 완료 단계에서 로그인하러 간다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      bootAt: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: 'abcd efgh jkmn pqrs');
    await _tap(tester, _key('passwordReset-submit'));
    expect(repo.confirmed, <(String, String)>[('abcd efgh jkmn pqrs', _newPw)]);
    expect(find.byKey(const Key('passwordResetDoneStep')), findsOneWidget);
    expect(find.text(l.passwordResetDoneBody), findsOneWidget);

    await _tap(tester, _key('passwordReset-to-sign-in'));
    expect(find.byType(TrainerSignInPage), findsOneWidget);
  });

  testWidgets('모양이 틀린 코드는 보내지 않는다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      bootAt: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: 'ABCD-1234');
    await _tap(tester, _key('passwordReset-submit'));
    expect(repo.confirmed, isEmpty);
    expect(find.text(l.passwordResetCodeMalformed), findsOneWidget);
  });

  testWidgets('틀리거나 만료된 코드는 코드 칸에 알리고 다시 받게 한다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      repository: _FakeReset(
        confirmError: const PasswordResetError(
          PasswordResetFailure.invalidCode,
        ),
      ),
      bootAt: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: _code);
    await _tap(tester, _key('passwordReset-submit'));
    expect(find.text(l.passwordResetCodeInvalid), findsOneWidget);
    expect(find.byKey(const Key('passwordResetConfirmStep')), findsOneWidget);

    await _tap(tester, _key('passwordReset-resend'));
    expect(find.byKey(const Key('passwordResetRequestStep')), findsOneWidget);
  });

  testWidgets('새 비밀번호는 가입과 같은 규칙으로 본다', (tester) async {
    final _FakeReset repo = _FakeReset();
    final AppLocalizations l = await _pump(
      tester,
      repository: repo,
      bootAt: AppRoutes.passwordReset,
    );
    await _tap(tester, _key('passwordReset-have-code'));
    await _fillConfirm(tester, code: _code, next: '12345678');
    await _tap(tester, _key('passwordReset-submit'));
    expect(repo.confirmed, isEmpty);
    expect(find.text(l.authErrPasswordWeak), findsOneWidget);
  });

  testWidgets('메일 링크의 코드로 들어오면 코드 칸이 채워진 채 시작한다', (tester) async {
    await _pump(
      tester,
      repository: _FakeReset(),
      bootAt: '${AppRoutes.passwordReset}?token=abcdefghjkmnpqrs',
    );
    expect(find.byKey(const Key('passwordResetConfirmStep')), findsOneWidget);
    expect(find.text(_code), findsOneWidget);
  });

  testWidgets('발송 수단이 없는 서버면 알리고 요청 단계에 머문다', (tester) async {
    final AppLocalizations l = await _pump(
      tester,
      repository: _FakeReset(
        requestError: const PasswordResetError(
          PasswordResetFailure.unavailable,
        ),
      ),
      bootAt: AppRoutes.passwordReset,
    );
    await _enter(tester, 'passwordReset-email', 'trainer@example.com');
    await _tap(tester, _key('passwordReset-send'));
    expect(find.text(l.passwordResetUnavailable), findsOneWidget);
    expect(find.byKey(const Key('passwordResetRequestStep')), findsOneWidget);
  });

  testWidgets('데모는 메일 대신 코드 칸을 채워 끝까지 갈 수 있게 한다', (tester) async {
    // 리포지토리를 갈지 않는다 — 데모 빌드가 실제로 고르는 목업이다.
    final AppLocalizations l = await _pump(
      tester,
      bootAt: AppRoutes.passwordReset,
    );
    await _enter(tester, 'passwordReset-email', 'demo@example.com');
    await _tap(tester, _key('passwordReset-send'));
    expect(find.text(l.passwordResetDemoNote), findsOneWidget);
    expect(find.text(MockPasswordResetRepository.demoCode), findsOneWidget);

    await _fillConfirm(tester);
    await _tap(tester, _key('passwordReset-submit'));
    expect(find.byKey(const Key('passwordResetDoneStep')), findsOneWidget);
  });
}
