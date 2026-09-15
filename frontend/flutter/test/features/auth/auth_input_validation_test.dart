/// 로그인·가입 입력 형식 검사와 칸 아래 오류 문구 — #1784.
///
/// 형식이 틀리면 요청을 보내지 않고 **틀린 칸 아래에** 빨간 문구를 보인다.
/// 첫 제출 전에는 오류를 보이지 않고, 오류를 보인 칸은 고치는 대로 다시
/// 검사한다. 서버가 거절한 실패(인증 실패·이메일 중복)는 예전처럼 토스트다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_up_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 들어온 요청을 적어 두고 [status] 로 거절하는 서버 흉내.
class _FakeServer {
  _FakeServer(this.status);

  final int status;
  final List<RequestOptions> requests = <RequestOptions>[];

  late final Dio dio = Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<Object?>(
                requestOptions: options,
                statusCode: status,
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

  List<RequestOptions> to(String path) =>
      requests.where((RequestOptions r) => r.path == path).toList();
}

Future<_FakeServer> _pump(
  WidgetTester tester,
  Widget page, {
  int status = 401,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final _FakeServer server = _FakeServer(status);
  addTearDown(server.dio.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_config),
        dioProvider.overrideWithValue(server.dio),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await tester.pump();
  return server;
}

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_input(key), text);
  await tester.pump();
  // 도움말이 있는 칸은 오류 문구가 도움말로 서서히 바뀐다(Material 167ms).
  // 전환이 끝나야 사라진 문구가 트리에서도 빠진다.
  await tester.pump(const Duration(milliseconds: 200));
}

String _valueOf(WidgetTester tester, String key) =>
    tester.widget<TextField>(_input(key)).controller!.text;

/// 오류 문구가 늘어 버튼이 화면 밖으로 밀려도 누를 수 있게 끌어온다.
Future<void> _submit(WidgetTester tester, String key) async {
  final Finder submit = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// [key] 칸 **안에**(입력창 아래 오류 자리) [message] 가 그려졌는가.
Finder _errorUnder(String key, String message) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.text(message),
);

const String _nameEmpty = '이름을 입력해 주세요';
const String _emailEmpty = '이메일을 입력해 주세요';
const String _emailInvalid = '이메일 형식이 올바르지 않아요';
const String _passwordEmpty = '비밀번호를 입력해 주세요';
const String _phoneInvalid = '전화번호를 000-0000-0000 형식으로 입력해 주세요';
const String _passwordWeak = '영문과 숫자를 포함해 8자 이상 입력해 주세요';
const String _mismatch = '비밀번호가 일치하지 않아요';

void main() {
  group('로그인', () {
    const String email = 'member-login-email';
    const String password = 'member-login-password';
    const String submit = 'member-login-submit';

    testWidgets('빈칸으로 로그인하면 칸 아래에 빨간 문구를 보이고 요청하지 않는다', (
      WidgetTester tester,
    ) async {
      final _FakeServer server = await _pump(tester, const SignInPage());

      // 제출하기 전에는 아무 칸에도 오류가 없다.
      expect(find.text(_emailEmpty), findsNothing);
      expect(find.text(_passwordEmpty), findsNothing);

      await _submit(tester, submit);

      expect(_errorUnder(email, _emailEmpty), findsOneWidget);
      expect(_errorUnder(password, _passwordEmpty), findsOneWidget);
      // 예전 토스트 문구는 더 이상 뜨지 않는다.
      expect(find.text('이메일과 비밀번호를 입력해 주세요'), findsNothing);
      expect(server.requests, isEmpty);

      final BuildContext context = tester.element(
        find.byKey(const ValueKey<String>(email)),
      );
      final Text error = tester.widget<Text>(find.text(_emailEmpty));
      expect(error.style?.color, Theme.of(context).colorScheme.error);
    });

    testWidgets('이메일 형식이 틀리면 형식 문구를 보이고 요청하지 않는다', (WidgetTester tester) async {
      final _FakeServer server = await _pump(tester, const SignInPage());

      await _type(tester, email, 'minsu@oncare');
      await _type(tester, password, 'oncare123');
      // 입력만으로는 오류를 보이지 않는다 — 첫 제출 전이다.
      expect(find.text(_emailInvalid), findsNothing);

      await _submit(tester, submit);

      expect(_errorUnder(email, _emailInvalid), findsOneWidget);
      expect(find.text(_passwordEmpty), findsNothing);
      expect(server.requests, isEmpty);
    });

    testWidgets('오류를 보인 칸은 고치는 대로 문구가 사라진다', (WidgetTester tester) async {
      final _FakeServer server = await _pump(tester, const SignInPage());

      await _type(tester, email, 'minsu');
      await _submit(tester, submit);
      expect(find.text(_emailInvalid), findsOneWidget);
      expect(find.text(_passwordEmpty), findsOneWidget);

      // 다시 제출하지 않아도 칸마다 지금 값으로 다시 검사한다.
      await _type(tester, email, 'minsu@oncare.com');
      expect(find.text(_emailInvalid), findsNothing);
      expect(find.text(_passwordEmpty), findsOneWidget);

      await _type(tester, password, 'pw');
      expect(find.text(_passwordEmpty), findsNothing);

      // 한 번 오류를 보인 칸은 다시 틀리면 다시 뜬다.
      await _type(tester, email, '');
      expect(_errorUnder(email, _emailEmpty), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('가입 비밀번호 규칙은 걸지 않는다 — 형식이 맞으면 요청을 보낸다', (
      WidgetTester tester,
    ) async {
      // 규칙 이전에 만든 계정(데모 계정 oncare123 포함)이 막히지 않아야 한다.
      final _FakeServer server = await _pump(tester, const SignInPage());

      final List<String> passwords = <String>['pw', '12345678', 'oncare123'];
      for (final String pw in passwords) {
        await _type(tester, email, '  minsu@oncare.com ');
        await _type(tester, password, pw);
        await _submit(tester, submit);
        expect(find.text(_passwordWeak), findsNothing, reason: pw);
      }

      final List<RequestOptions> logins = server.to('/auth/login');
      expect(logins, hasLength(passwords.length));
      for (int i = 0; i < passwords.length; i++) {
        final Map<String, Object?> data =
            logins[i].data! as Map<String, Object?>;
        // 앞뒤 공백은 잘라서 보낸다.
        expect(data['username'], 'minsu@oncare.com');
        expect(data['password'], passwords[i]);
      }
      // 서버가 거절한 실패는 칸 오류가 아니라 예전처럼 토스트다.
      expect(find.text('로그인에 실패했어요. 이메일·비밀번호를 확인해 주세요'), findsOneWidget);
      expect(find.text(_emailInvalid), findsNothing);
    });
  });

  group('회원가입', () {
    const String name = 'member-signup-name';
    const String email = 'member-signup-email';
    const String phone = 'member-signup-phone';
    const String password = 'member-signup-password';
    const String confirm = 'member-signup-password-confirm';
    const String submit = 'member-signup-submit';
    const String phoneHelper = '트레이너가 회원님을 확인할 때 쓰는 연락처예요';

    testWidgets('안내 문구가 새 형식·규칙을 말한다', (WidgetTester tester) async {
      await _pump(tester, const SignUpPage());

      expect(
        find.widgetWithText(TextField, '비밀번호 (영문·숫자 포함 8자 이상)'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, '010-0000-0000'), findsOneWidget);
      expect(find.text(phoneHelper), findsOneWidget);
    });

    testWidgets('빈칸으로 제출하면 칸마다 아래에 문구를 보이고 요청하지 않는다', (
      WidgetTester tester,
    ) async {
      final _FakeServer server = await _pump(tester, const SignUpPage());

      // 제출하기 전에는 이름 칸에도 오류가 없다.
      expect(find.text(_nameEmpty), findsNothing);

      await _submit(tester, submit);

      expect(_errorUnder(name, _nameEmpty), findsOneWidget);
      expect(_errorUnder(email, _emailEmpty), findsOneWidget);
      expect(_errorUnder(phone, _phoneInvalid), findsOneWidget);
      expect(_errorUnder(password, _passwordEmpty), findsOneWidget);
      // 둘 다 비어 있으면 서로 같다 — 확인 칸은 조용하다.
      expect(find.text(_mismatch), findsNothing);
      // 전화번호 도움말 자리를 오류 문구가 대신한다.
      expect(find.text(phoneHelper), findsNothing);
      expect(server.requests, isEmpty);
    });

    testWidgets('이름이 비었거나 공백뿐이면 보내지 않고, 치면 문구가 사라진다', (
      WidgetTester tester,
    ) async {
      final _FakeServer server = await _pump(
        tester,
        const SignUpPage(),
        status: 409,
      );

      // 이름 말고는 모두 맞게 채운다.
      await _type(tester, name, '   ');
      await _type(tester, email, 'minsu@oncare.com');
      await _type(tester, phone, '01012345678');
      await _type(tester, password, '1234567a');
      await _type(tester, confirm, '1234567a');
      expect(find.text(_nameEmpty), findsNothing);

      await _submit(tester, submit);

      expect(_errorUnder(name, _nameEmpty), findsOneWidget);
      expect(find.text(_emailInvalid), findsNothing);
      expect(server.requests, isEmpty);

      // 다시 제출하지 않아도 이름을 치는 대로 문구가 사라진다.
      await _type(tester, name, '김민수');
      expect(find.text(_nameEmpty), findsNothing);

      await _submit(tester, submit);

      final List<RequestOptions> registers = server.to('/auth/register');
      expect(registers, hasLength(1));
      final Map<String, Object?> data =
          registers.single.data! as Map<String, Object?>;
      expect(data['name'], '김민수');
    });

    testWidgets('전화번호는 숫자만 쳐도 000-0000-0000 으로 끊긴다', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const SignUpPage());

      await _type(tester, phone, '010');
      expect(_valueOf(tester, phone), '010');
      await _type(tester, phone, '0101');
      expect(_valueOf(tester, phone), '010-1');
      await _type(tester, phone, '01012345');
      expect(_valueOf(tester, phone), '010-1234-5');
      await _type(tester, phone, '01012345678');
      expect(_valueOf(tester, phone), '010-1234-5678');
      // 11자리를 넘는 숫자와 숫자가 아닌 글자는 받지 않는다.
      await _type(tester, phone, '010 1234 56789');
      expect(_valueOf(tester, phone), '010-1234-5678');
    });

    testWidgets('형식이 틀린 칸마다 문구를 보이고 요청하지 않는다', (WidgetTester tester) async {
      final _FakeServer server = await _pump(tester, const SignUpPage());

      await _type(tester, email, 'minsu@oncare');
      await _type(tester, phone, '0101234');
      await _type(tester, password, 'abcdefgh');
      await _type(tester, confirm, 'abcdefgh1');
      await _submit(tester, submit);

      expect(_errorUnder(email, _emailInvalid), findsOneWidget);
      expect(_errorUnder(phone, _phoneInvalid), findsOneWidget);
      expect(_errorUnder(password, _passwordWeak), findsOneWidget);
      expect(_errorUnder(confirm, _mismatch), findsOneWidget);
      expect(server.requests, isEmpty);
    });

    testWidgets('고치는 대로 문구가 사라지고, 다 고치면 요청을 보낸다', (WidgetTester tester) async {
      final _FakeServer server = await _pump(
        tester,
        const SignUpPage(),
        status: 409,
      );

      await _type(tester, name, '김민수');
      await _type(tester, email, 'minsu@oncare');
      await _type(tester, phone, '0101234');
      await _type(tester, password, '12345678');
      await _type(tester, confirm, '12345678');
      await _submit(tester, submit);
      expect(find.text(_emailInvalid), findsOneWidget);
      expect(find.text(_phoneInvalid), findsOneWidget);
      expect(find.text(_passwordWeak), findsOneWidget);

      await _type(tester, email, 'minsu@oncare.com');
      expect(find.text(_emailInvalid), findsNothing);

      await _type(tester, phone, '01012345678');
      expect(find.text(_phoneInvalid), findsNothing);
      expect(find.text(phoneHelper), findsOneWidget);

      await _type(tester, password, '1234567a');
      expect(find.text(_passwordWeak), findsNothing);
      // 제출 때 맞았던 확인 칸은 다음 제출까지 오류를 보이지 않는다.
      expect(find.text(_mismatch), findsNothing);
      expect(server.requests, isEmpty);

      await _submit(tester, submit);
      expect(_errorUnder(confirm, _mismatch), findsOneWidget);
      expect(server.requests, isEmpty);

      await _type(tester, confirm, '1234567a');
      expect(find.text(_mismatch), findsNothing);

      await _submit(tester, submit);

      final List<RequestOptions> registers = server.to('/auth/register');
      expect(registers, hasLength(1));
      final Map<String, Object?> data =
          registers.single.data! as Map<String, Object?>;
      expect(data['email'], 'minsu@oncare.com');
      expect(data['phone'], '010-1234-5678');
      expect(data['password'], '1234567a');
      // 이메일 중복은 서버가 알려 주는 실패라 예전처럼 토스트다.
      expect(find.text('이미 가입된 이메일이에요. 로그인해 주세요.'), findsOneWidget);
    });
  });
}
