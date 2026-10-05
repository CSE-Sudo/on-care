/// 가입 화면의 동의 묶음과 로그인 뒤 동의 화면 — #2819.
///
/// 필수 동의를 체크해야만 가입·계속 버튼이 켜지고, 건강정보 처리 동의는 따로
/// 체크하며, 문서 보기는 MY 탭과 같은 문서 화면을 연다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/consent_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_up_page.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/signup_email_code.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// `METHOD /path` → (상태, 본문). 없는 경로는 404. 나간 요청을 적어 둔다.
class _Server {
  _Server(this.routes);

  final Map<String, (int, Object?)> routes;
  final List<RequestOptions> requests = <RequestOptions>[];

  late final Dio dio = Dio(BaseOptions(baseUrl: _config.apiBaseUrl))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          requests.add(options);
          // 가입 인증 코드 요청(#3038)은 늘 받아 준다 — 이 파일은 동의를 본다.
          if (options.path == signupCodePath) {
            handler.resolve(signupCodeAccepted(options));
            return;
          }
          final (int, Object?)? hit =
              routes['${options.method.toUpperCase()} ${options.path}'];
          final int status = hit?.$1 ?? 404;
          final Response<Object?> response = Response<Object?>(
            requestOptions: options,
            statusCode: status,
            data: hit?.$2,
          );
          if (status >= 400) {
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

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget page,
  _Server server, {
  Locale locale = const Locale('ko'),
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  addTearDown(server.dio.close);
  // 로그인하면 세션 초기화가 로컬 DB 를 연다 — 기기 경로를 찾는 플러그인이
  // 테스트에는 없으니 메모리 DB 로 대신한다.
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(_config),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(server.dio),
      sessionFeatureResetOverride(),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final Finder target = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey<String>(key))).onPressed !=
    null;

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

/// 이메일을 채우고 인증 코드를 받아 넣는다(#3038). 가입 버튼은 동의와 코드가
/// 함께 갖춰져야 켜진다.
Future<void> _withCode(WidgetTester tester) async {
  await _type(tester, 'member-signup-email', 'new@oncare.com');
  await passSignupCode(tester);
}

/// 토스트 타이머가 남지 않게 흘려보낸다.
Future<void> _drain(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  group('가입 화면', () {
    const String submit = 'member-signup-submit';

    testWidgets('필수·선택 항목이 각각 체크로 있고, 건강정보 동의가 따로 있다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );

      expect(find.text('전체 동의'), findsOneWidget);
      expect(find.text('[필수] 이용약관 동의'), findsOneWidget);
      expect(find.text('[필수] 개인정보 수집·이용 동의'), findsOneWidget);
      expect(find.text('[필수] 건강정보(민감정보) 처리 동의'), findsOneWidget);
      expect(find.text('[필수] 만 14세 이상이에요'), findsOneWidget);
      for (final String id in <String>['terms', 'privacy', 'health', 'age14']) {
        expect(find.byKey(ValueKey<String>('consent-$id')), findsOneWidget);
      }
      // 마케팅 수신 동의는 더는 묻지 않는다(#3007) — 선택 항목이 없다.
      expect(
        find.byKey(const ValueKey<String>('consent-marketing')),
        findsNothing,
      );
      expect(find.textContaining('[선택]'), findsNothing);
    });

    testWidgets('필수 동의 전에는 가입 버튼이 꺼져 있고 이유를 알린다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );

      expect(_enabled(tester, submit), isFalse);
      expect(
        find.byKey(const ValueKey<String>('consent-required-hint')),
        findsOneWidget,
      );
    });

    testWidgets('전체 동의를 켜면 버튼이 켜지고, 다시 끄면 꺼진다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );
      await _withCode(tester);

      await _tap(tester, 'consent-all');
      expect(_enabled(tester, submit), isTrue);
      expect(
        find.byKey(const ValueKey<String>('consent-required-hint')),
        findsNothing,
      );

      await _tap(tester, 'consent-all');
      expect(_enabled(tester, submit), isFalse);
    });

    testWidgets('전체 동의 뒤 필수를 하나라도 끄면 가입할 수 없다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );
      await _withCode(tester);
      await _tap(tester, 'consent-all');
      expect(_enabled(tester, submit), isTrue);

      for (final String id in <String>['terms', 'privacy', 'health', 'age14']) {
        await _tap(tester, 'consent-$id');
        expect(_enabled(tester, submit), isFalse, reason: id);
        await _tap(tester, 'consent-$id');
        expect(_enabled(tester, submit), isTrue, reason: id);
      }
    });

    testWidgets('만 14세 확인 없이는 가입할 수 없다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );
      await _withCode(tester);

      for (final String id in <String>['terms', 'privacy', 'health']) {
        await _tap(tester, 'consent-$id');
      }
      expect(_enabled(tester, submit), isFalse);
      expect(find.text('만 14세 미만은 가입할 수 없어요.'), findsOneWidget);

      await _tap(tester, 'consent-age14');
      expect(_enabled(tester, submit), isTrue);
    });

    testWidgets('동의를 마쳐도 인증 코드 여섯 자리 전에는 꺼져 있다 (#3038)', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );
      await _tap(tester, 'consent-all');
      expect(_enabled(tester, submit), isFalse);

      await _type(tester, 'member-signup-email', 'new@oncare.com');
      await tapSignupCodeSend(tester);
      await typeSignupCode(tester, '12345');
      expect(_enabled(tester, submit), isFalse);

      await typeSignupCode(tester, '123456');
      expect(_enabled(tester, submit), isTrue);
    });

    testWidgets('약관 보기는 이용약관 문서를 연다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );

      await _tap(tester, 'consent-view-terms');
      await tester.pumpAndSettle();

      final LegalDocumentPage doc = tester.widget<LegalDocumentPage>(
        find.byType(LegalDocumentPage),
      );
      expect(doc.document, 'terms');
      // 문서를 연 것만으로 동의한 것은 아니다.
      await tester.tap(find.byType(AppBackButton).last);
      await tester.pumpAndSettle();
      expect(_enabled(tester, submit), isFalse);
    });

    testWidgets('개인정보·건강정보 보기는 처리방침을 연다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
      );

      for (final String id in <String>['privacy', 'health']) {
        await _tap(tester, 'consent-view-$id');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<LegalDocumentPage>(find.byType(LegalDocumentPage))
              .document,
          'privacy',
          reason: id,
        );
        await tester.tap(find.byType(AppBackButton).last);
        await tester.pumpAndSettle();
      }
      // 만 14세 확인은 문서가 없다.
      expect(
        find.byKey(const ValueKey<String>('consent-view-age14')),
        findsNothing,
      );
    });

    testWidgets('가입 요청에 체크한 항목을 싣는다', (tester) async {
      final _Server server = _Server(<String, (int, Object?)>{
        // 중복으로 거절해 화면을 이동시키지 않는다 — 실린 값만 본다.
        'POST /auth/register': (409, <String, Object?>{'detail': 'taken'}),
      });
      await _pump(tester, const SignUpPage(), server);

      await _type(tester, 'member-signup-name', '김민수');
      await _type(tester, 'member-signup-email', 'new@oncare.com');
      await _type(tester, 'member-signup-phone', '01012345678');
      await _type(tester, 'member-signup-password', 'signup-pw-1234');
      await _type(tester, 'member-signup-password-confirm', 'signup-pw-1234');
      for (final String id in <String>['terms', 'privacy', 'health', 'age14']) {
        await _tap(tester, 'consent-$id');
      }
      await passSignupCode(tester);
      await _tap(tester, submit);

      final List<RequestOptions> sent = server.to('/auth/register');
      expect(sent, hasLength(1));
      expect((sent.single.data as Map<String, Object?>)['consents'], <String>[
        'terms',
        'privacy',
        'health',
        'age14',
      ]);
      await _drain(tester);
    });

    testWidgets('영어 화면에서도 같은 항목이 선다', (tester) async {
      await _pump(
        tester,
        const SignUpPage(),
        _Server(<String, (int, Object?)>{}),
        locale: const Locale('en'),
      );

      expect(find.text('Agree to all'), findsOneWidget);
      expect(
        find.text(
          '[Required] Processing of health information (sensitive data)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('[Required] I am 14 years of age or older'),
        findsOneWidget,
      );
      expect(find.textContaining('[Optional]'), findsNothing);
    });
  });

  group('로그인 뒤 동의 화면', () {
    _Server server({int consentStatus = 200}) =>
        _Server(<String, (int, Object?)>{
          'POST /auth/login': (
            200,
            <String, Object?>{
              'access_token': 'access-1',
              'refresh_token': 'refresh-1',
              'consent_required': true,
            },
          ),
          'POST /auth/logout': (204, null),
          'POST /users/me/consents': (
            consentStatus,
            consentStatus == 200
                ? <String, Object?>{
                    'consent_required': false,
                    'consent_pending': <String>[],
                  }
                : <String, Object?>{
                    'detail': <String, Object?>{'code': 'consent_required'},
                  },
          ),
        });

    Future<ProviderContainer> signedIn(WidgetTester tester, _Server s) async {
      final ProviderContainer container = await _pump(
        tester,
        const ConsentPage(),
        s,
      );
      await tester.runAsync(
        () => container
            .read(sessionControllerProvider.notifier)
            .login(email: 'm@oncare.com', password: 'pw-12345678'),
      );
      await tester.pump();
      expect(container.read(sessionControllerProvider).consentRequired, isTrue);
      return container;
    }

    testWidgets('필수 동의 전에는 계속 버튼이 꺼져 있다', (tester) async {
      await signedIn(tester, server());

      expect(find.text('서비스 이용 동의'), findsOneWidget);
      expect(_enabled(tester, 'consent-submit'), isFalse);
      await _tap(tester, 'consent-all');
      expect(_enabled(tester, 'consent-submit'), isTrue);
    });

    testWidgets('동의하고 계속하면 항목을 저장하고 동의 요구가 풀린다', (tester) async {
      final _Server s = server();
      final ProviderContainer container = await signedIn(tester, s);

      for (final String id in <String>['terms', 'privacy', 'health', 'age14']) {
        await _tap(tester, 'consent-$id');
      }
      await _tap(tester, 'consent-submit');
      await _drain(tester);

      final List<RequestOptions> sent = s.to('/users/me/consents');
      expect(sent, hasLength(1));
      expect((sent.single.data as Map<String, Object?>)['consents'], <String>[
        'terms',
        'privacy',
        'health',
        'age14',
      ]);
      expect(
        container.read(sessionControllerProvider).consentRequired,
        isFalse,
      );
    });

    testWidgets('저장이 실패하면 알리고 화면에 남는다', (tester) async {
      final ProviderContainer container = await signedIn(
        tester,
        server(consentStatus: 500),
      );

      await _tap(tester, 'consent-all');
      await _tap(tester, 'consent-submit');

      expect(find.text('동의를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(container.read(sessionControllerProvider).consentRequired, isTrue);
      expect(_enabled(tester, 'consent-submit'), isTrue);
      await _drain(tester);
    });

    testWidgets('동의하지 않을 길 — 로그아웃', (tester) async {
      final ProviderContainer container = await signedIn(tester, server());

      await _tap(tester, 'consent-sign-out');
      await _drain(tester);

      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
    });
  });
}
