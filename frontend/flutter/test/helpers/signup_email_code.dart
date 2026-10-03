import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/auth/domain/signup_email_code.dart';

/// 가입 화면의 이메일 인증 코드 단계(#3038)를 지나가는 테스트 도우미.
///
/// 가입 버튼은 인증 코드 여섯 자리를 넣어야 켜진다. 가입 화면의 다른 동작을
/// 보는 테스트가 이 단계에서 멈추지 않게 코드를 받고 넣어 준다.

/// 코드 요청 경로.
const String signupCodePath = '/auth/register/email-code';

const Key signupCodeSendKey = ValueKey<String>('member-signup-code-send');
const Key signupCodeFieldKey = ValueKey<String>('member-signup-code');
const Key signupCodeResendKey = ValueKey<String>('member-signup-code-resend');

/// 서버 흉내가 코드 요청에 돌려줄 202 응답.
Response<Object?> signupCodeAccepted(RequestOptions options) =>
    Response<Object?>(
      requestOptions: options,
      statusCode: 202,
      data: const <String, Object?>{
        'expires_in_minutes': 10,
        'resend_after_seconds': 60,
      },
    );

/// "인증 코드 받기" 를 누르고 요청이 돌아올 때까지 흘려보낸다.
///
/// 요청은 Dio 를 거쳐 몇 차례 비동기로 돌아온다 — 프레임 두 번으로는 응답이
/// 화면에 닿지 않는다. 다시 받기 카운트다운(1초)이 흐르기 전에 끝나도록 짧게
/// 나눠 흘린다.
Future<void> tapSignupCodeSend(WidgetTester tester) async {
  final Finder send = find.byKey(signupCodeSendKey);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(send);
  await tester.pump();
  await tester.tap(send);
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 코드 칸에 [code] 를 넣는다.
Future<void> typeSignupCode(
  WidgetTester tester, [
  String code = SignupEmailCode.demoCode,
]) async {
  final Finder field = find.byKey(signupCodeFieldKey);
  await tester.ensureVisible(field);
  await tester.enterText(field, code);
  await tester.pump();
}

/// 코드를 아직 받지 않았으면 받고, 칸이 있으면 [code] 를 넣는다.
///
/// 이메일 칸이 틀렸으면 코드를 받지 못한다 — 화면처럼 이메일 칸 아래에 이유가
/// 붙고 코드 칸은 나오지 않는다.
Future<void> passSignupCode(
  WidgetTester tester, [
  String code = SignupEmailCode.demoCode,
]) async {
  if (find.byKey(signupCodeFieldKey).evaluate().isEmpty) {
    if (find.byKey(signupCodeSendKey).evaluate().isEmpty) return;
    await tapSignupCodeSend(tester);
  }
  if (find.byKey(signupCodeFieldKey).evaluate().isEmpty) return;
  final TextField field = tester.widget<TextField>(
    find.descendant(
      of: find.byKey(signupCodeFieldKey),
      matching: find.byType(TextField),
    ),
  );
  if (field.controller?.text == code) return;
  await typeSignupCode(tester, code);
}
