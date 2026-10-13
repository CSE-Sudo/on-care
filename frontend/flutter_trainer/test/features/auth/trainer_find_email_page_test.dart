/// 트레이너 웹 로그인의 `아이디 찾기` 와 아이디 찾기 화면.
///
/// 회원 앱과 같은 화면이다. 찾는 경로가 생기기 전이라 입력만 검사하고 준비 중이라고
/// 토스트로 알린다(리포지토리·네트워크를 쓰지 않는다).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/app_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_find_email_page.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_password_reset_page.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

String? _errorOf(WidgetTester tester, String key) =>
    tester.widget<AppTextField>(_key(key)).errorText;

AppLocalizations _l(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Navigator).first));

void main() {
  testWidgets('로그인 화면의 아이디 찾기가 비밀번호 찾기 옆에서 화면을 연다', (tester) async {
    await pumpTrainerApp(tester);
    await settle(tester);
    final AppLocalizations l = _l(tester);

    expect(find.text(l.authFindEmail), findsOneWidget);
    expect(find.text(l.authForgotPassword), findsOneWidget);
    final Rect findEmail = tester.getRect(_key('trainer-login-find-email'));
    final Rect forgot = tester.getRect(_key('trainer-login-forgot-password'));
    expect(findEmail.center.dy, forgot.center.dy);
    expect(findEmail.right, lessThanOrEqualTo(forgot.left));

    await _tap(tester, _key('trainer-login-find-email'));
    expect(find.byType(TrainerFindEmailPage), findsOneWidget);
    expect(find.text(l.findEmailSubtitle), findsOneWidget);
    // 준비 중 문구는 화면에 늘 띄워 두지 않는다.
    expect(find.text(l.findEmailComingSoon), findsNothing);

    await _tap(tester, find.byType(AppBackButton));
    expect(find.byType(TrainerSignInPage), findsOneWidget);
  });

  testWidgets('비어 있거나 형식이 틀리면 칸 아래에 오류, 맞으면 준비 중 토스트', (tester) async {
    await pumpTrainerApp(tester, at: AppRoutes.findEmail);
    await settle(tester);
    final AppLocalizations l = _l(tester);
    expect(find.byType(TrainerFindEmailPage), findsOneWidget);

    await _tap(tester, _key('trainerFindEmail-submit'));
    expect(_errorOf(tester, 'trainerFindEmail-name'), isNotNull);
    expect(_errorOf(tester, 'trainerFindEmail-phone'), isNotNull);
    expect(find.text(l.findEmailComingSoon), findsNothing);

    await tester.enterText(_key('trainerFindEmail-name'), '김트레이너');
    await tester.enterText(_key('trainerFindEmail-phone'), '01012345678');
    await settle(tester);
    expect(find.text('010-1234-5678'), findsOneWidget);
    await _tap(tester, _key('trainerFindEmail-submit'));

    expect(_errorOf(tester, 'trainerFindEmail-name'), isNull);
    expect(_errorOf(tester, 'trainerFindEmail-phone'), isNull);
    expect(find.text(l.findEmailComingSoon), findsOneWidget);
    expect(find.byType(TrainerFindEmailPage), findsOneWidget);
  });

  testWidgets('비밀번호도 잊었으면 재설정 화면으로 넘어간다', (tester) async {
    await pumpTrainerApp(tester, at: AppRoutes.findEmail);
    await settle(tester);

    await _tap(tester, _key('trainerFindEmail-to-password-reset'));
    expect(find.byType(TrainerPasswordResetPage), findsOneWidget);
  });

  test('아이디 찾기는 가입처럼 로그아웃 상태에서만 머문다', () {
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
