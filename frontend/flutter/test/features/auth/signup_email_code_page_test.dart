/// 가입 화면의 이메일 인증 코드 단계 — #3038.
///
/// 확인 안 된 이메일로 계정이 생기지 않게, 가입 전에 그 주소로 받은 6자리
/// 코드를 넣게 한다. 남의 주소로 계정을 먼저 만들어 두는 일을 막는다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/pages/sign_up_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/signup_email_code.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 인증을 실서버로 보내는 데모 — 진짜 메일이 가므로 데모 코드를 안내하지 않는다.
const AppConfig _realAuthConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
  realApiFeatures: <String>{'auth'},
);

const String _submit = 'member-signup-submit';

/// 경로별 (상태, 본문)으로 답하는 서버 흉내. 나간 요청을 적어 둔다.
class _Server {
  _Server({
    this.codeStatus = 202,
    this.registerStatus = 409,
    this.registerBody = const <String, Object?>{'detail': 'taken'},
  });

  final int codeStatus;
  final int registerStatus;
  final Object? registerBody;
  final List<RequestOptions> requests = <RequestOptions>[];

  late final Dio dio = Dio(BaseOptions(baseUrl: _mockConfig.apiBaseUrl))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          final Response<Object?> response = options.path == signupCodePath
              ? (codeStatus == 202
                    ? signupCodeAccepted(options)
                    : Response<Object?>(
                        requestOptions: options,
                        statusCode: codeStatus,
                        data: const <String, Object?>{'detail': 'nope'},
                      ))
              : Response<Object?>(
                  requestOptions: options,
                  statusCode: options.path == '/auth/register'
                      ? registerStatus
                      : 404,
                  data: registerBody,
                );
          if (response.statusCode! >= 400) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          handler.resolve(response);
        },
      ),
    );

  List<RequestOptions> to(String path) =>
      requests.where((RequestOptions r) => r.path == path).toList();
}

Future<(AppLocalizations, _Server)> _pump(
  WidgetTester tester, {
  _Server? server,
  AppConfig config = _mockConfig,
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final _Server backend = server ?? _Server();
  addTearDown(backend.dio.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        dioProvider.overrideWithValue(backend.dio),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SignUpPage(),
      ),
    ),
  );
  await tester.pump();
  return (
    AppLocalizations.of(tester.element(find.byType(SignUpPage))),
    backend,
  );
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 가입에 필요한 칸을 모두 맞게 채우고 동의까지 마친다. 코드는 넣지 않는다.
Future<void> _fillAll(WidgetTester tester) async {
  await _type(tester, 'member-signup-name', '김민수');
  await _type(tester, 'member-signup-email', 'new@oncare.com');
  await _type(tester, 'member-signup-phone', '01012345678');
  await _type(tester, 'member-signup-password', 'signup-pw-1234');
  await _type(tester, 'member-signup-password-confirm', 'signup-pw-1234');
  await _tap(tester, 'consent-all');
}

AppButton _button(WidgetTester tester, Key key) =>
    tester.widget<AppButton>(find.byKey(key));

String? _codeError(WidgetTester tester) =>
    tester.widget<AppTextField>(find.byKey(signupCodeFieldKey)).errorText;

/// 토스트·타이머가 남지 않게 흘려보낸다.
Future<void> _drain(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  testWidgets('코드를 받기 전에는 받기 버튼만 있고, 받으면 코드 칸이 나온다', (tester) async {
    final (AppLocalizations l, _Server server) = await _pump(tester);

    expect(find.byKey(signupCodeSendKey), findsOneWidget);
    expect(find.text(l.signUpEmailCodeSend), findsOneWidget);
    expect(find.byKey(signupCodeFieldKey), findsNothing);

    await _type(tester, 'member-signup-email', 'New@OnCare.com');
    await tapSignupCodeSend(tester);

    expect(find.byKey(signupCodeFieldKey), findsOneWidget);
    expect(find.byKey(signupCodeSendKey), findsNothing);
    expect(find.text(l.signUpEmailCodeRemaining('10:00')), findsOneWidget);
    final List<RequestOptions> sent = server.to(signupCodePath);
    expect(sent, hasLength(1));
    expect(sent.single.data, <String, Object?>{
      'email': 'New@OnCare.com',
      'purpose': 'member_signup',
    });
  });

  testWidgets('다시 받기는 대기 시간 동안 꺼져 있고 초를 센다', (tester) async {
    final (AppLocalizations l, _Server server) = await _pump(tester);
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(find.text(l.signUpEmailCodeResendIn(60)), findsOneWidget);
    expect(_button(tester, signupCodeResendKey).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l.signUpEmailCodeResendIn(59)), findsOneWidget);
    expect(find.text(l.signUpEmailCodeRemaining('9:59')), findsOneWidget);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text(l.signUpEmailCodeResend), findsOneWidget);
    expect(_button(tester, signupCodeResendKey).onPressed, isNotNull);

    await tester.tap(find.byKey(signupCodeResendKey));
    await tester.pump();
    await tester.pump();
    expect(server.to(signupCodePath), hasLength(2));
    // 새 코드라 대기 시간이 다시 시작한다.
    expect(find.text(l.signUpEmailCodeResendIn(60)), findsOneWidget);
  });

  testWidgets('유효 시간이 지나면 만료됐다고 알린다', (tester) async {
    final (AppLocalizations l, _) = await _pump(tester);
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    for (int i = 0; i < 600; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text(l.signUpEmailCodeExpired), findsOneWidget);
  });

  testWidgets('이메일을 고치면 코드 칸을 비우고 다시 받게 한다', (tester) async {
    final (AppLocalizations l, _) = await _pump(tester);
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);
    await typeSignupCode(tester, '123456');

    // 대소문자만 바꾸면 같은 주소라 코드는 그대로다.
    await _type(tester, 'member-signup-email', 'NEW@oncare.com');
    expect(find.byKey(signupCodeFieldKey), findsOneWidget);

    await _type(tester, 'member-signup-email', 'other@oncare.com');
    expect(find.byKey(signupCodeFieldKey), findsNothing);
    expect(find.text(l.signUpEmailCodeSend), findsOneWidget);

    // 다시 받으면 빈 칸에서 시작한다.
    await tapSignupCodeSend(tester);
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(signupCodeFieldKey),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('동의를 마쳐도 코드 여섯 자리를 넣어야 가입 버튼이 켜진다', (tester) async {
    final (_, _) = await _pump(tester);
    await _fillAll(tester);
    const Key submit = ValueKey<String>(_submit);
    expect(_button(tester, submit).onPressed, isNull);

    await tapSignupCodeSend(tester);
    expect(_button(tester, submit).onPressed, isNull);

    await typeSignupCode(tester, '12345');
    expect(_button(tester, submit).onPressed, isNull);

    await typeSignupCode(tester, '123456');
    expect(_button(tester, submit).onPressed, isNotNull);

    // 숫자가 아닌 글자는 칸에 들어가지 않는다.
    await typeSignupCode(tester, '12ab56');
    expect(_button(tester, submit).onPressed, isNull);
  });

  testWidgets('넣은 코드가 가입 본문에 실린다', (tester) async {
    final (_, _Server server) = await _pump(tester);
    await _fillAll(tester);
    await passSignupCode(tester, '482913');
    await _tap(tester, _submit);

    final List<RequestOptions> registers = server.to('/auth/register');
    expect(registers, hasLength(1));
    expect(
      (registers.single.data! as Map<String, Object?>)['email_code'],
      '482913',
    );
    await _drain(tester);
  });

  testWidgets('틀린 코드(400 invalid_email_code)는 코드 칸 아래에 알리고 화면에 머문다', (
    tester,
  ) async {
    final (AppLocalizations l, _) = await _pump(
      tester,
      server: _Server(
        registerStatus: 400,
        registerBody: const <String, Object?>{
          'detail': <String, Object?>{
            'code': 'invalid_email_code',
            'message': '인증 코드가 맞지 않거나 만료되었습니다. 코드를 다시 받아 주세요.',
          },
        },
      ),
    );
    await _fillAll(tester);
    await passSignupCode(tester, '111111');
    await _tap(tester, _submit);

    expect(_codeError(tester), l.signUpEmailCodeInvalid);
    expect(find.byType(SignUpPage), findsOneWidget);
    // 쓴 값은 그대로 남아 코드만 고쳐 다시 보낼 수 있다.
    expect(find.text('new@oncare.com'), findsOneWidget);

    // 코드를 고치면 이유는 걷힌다.
    await typeSignupCode(tester, '222222');
    expect(_codeError(tester), isNull);
    await _drain(tester);
  });

  testWidgets('코드 없음(422 email_code_required)도 코드 칸 아래에 알린다', (tester) async {
    final (AppLocalizations l, _) = await _pump(
      tester,
      server: _Server(
        registerStatus: 422,
        registerBody: const <String, Object?>{
          'detail': <String, Object?>{
            'code': 'email_code_required',
            'message': '이메일 인증 코드를 입력해 주세요.',
          },
        },
      ),
    );
    await _fillAll(tester);
    await passSignupCode(tester);
    await _tap(tester, _submit);

    expect(_codeError(tester), l.signUpEmailCodeEmpty);
    expect(find.byType(SignUpPage), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('코드 요청이 너무 잦으면(429) 알리고 코드 칸을 열지 않는다', (tester) async {
    final (AppLocalizations l, _) = await _pump(
      tester,
      server: _Server(codeStatus: 429),
    );
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(find.text(l.passwordTooManyAttempts), findsOneWidget);
    expect(find.byKey(signupCodeFieldKey), findsNothing);
    await _drain(tester);
  });

  testWidgets('메일을 보낼 수 없으면(503) 그렇게 알린다', (tester) async {
    final (AppLocalizations l, _) = await _pump(
      tester,
      server: _Server(codeStatus: 503),
    );
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(find.text(l.signUpEmailCodeUnavailable), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('기기 안 목업 데모에서만 데모 코드를 안내한다', (tester) async {
    final (AppLocalizations l, _) = await _pump(tester);
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(
      find.byKey(const ValueKey<String>('member-signup-code-demo')),
      findsOneWidget,
    );
    expect(find.text(l.signUpEmailCodeDemoNote('000000')), findsOneWidget);
  });

  testWidgets('인증을 실서버로 보내는 설정에서는 데모 코드를 말하지 않는다', (tester) async {
    await _pump(tester, config: _realAuthConfig);
    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(find.byKey(signupCodeFieldKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('member-signup-code-demo')),
      findsNothing,
    );
  });

  testWidgets('영어 화면에서는 영어 문구다', (tester) async {
    await _pump(tester, locale: const Locale('en'));

    expect(find.text('Send code'), findsOneWidget);

    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(find.text('Verification code'), findsOneWidget);
    expect(find.text('Resend in 60s'), findsOneWidget);
    expect(
      find.text('6-digit code from the email · expires in 10:00'),
      findsOneWidget,
    );
    expect(
      find.text("Demo mode doesn't send email. Enter 000000 as the code."),
      findsOneWidget,
    );
  });

  testWidgets('한국어 화면 문구', (tester) async {
    await _pump(tester);

    expect(find.text('인증 코드 받기'), findsOneWidget);

    await _type(tester, 'member-signup-email', 'new@oncare.com');
    await tapSignupCodeSend(tester);

    expect(find.text('인증 코드'), findsOneWidget);
    expect(find.text('60초 뒤 다시 받기'), findsOneWidget);
  });
}
