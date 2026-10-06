/// 소셜 버튼은 항상 노출하고 목업·실 인증 경로를 구분한다(#2069).
///
/// 실 인증 설정에서는 버튼이 자리를 지킨 채 꺼지고 '준비 중' 안내가 뜬다 — 눌러도
/// 어떤 로그인 요청도 나가지 않는다(#2769). 전에는 고정된 계정으로 바로 로그인했다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppSocialLoginButton;

import '../../helpers/mock_account_repository.dart';

Future<void> _pumpSignIn(
  WidgetTester tester,
  AppConfig config, {
  Dio? dio,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
        if (dio != null) dioProvider.overrideWithValue(dio),
        accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SignInPage(),
      ),
    ),
  );
  await tester.pump();
}

void _expectSocialButtons(Matcher matcher) {
  expect(find.byKey(const ValueKey<String>('member-login-kakao')), matcher);
  expect(find.byKey(const ValueKey<String>('member-login-google')), matcher);
  // 그림만 있는 원형 버튼이라 이름은 화면 읽기 라벨로 찾는다(#1783).
  expect(find.bySemanticsLabel('카카오로 시작하기'), matcher);
  expect(find.bySemanticsLabel('구글로 시작하기'), matcher);
  expect(find.text('SNS 계정으로 로그인'), matcher);
  // 옛 구분선 문구는 어느 설정에서도 남지 않는다.
  expect(find.text('또는'), findsNothing);
}

void main() {
  for (final provider in <String>['kakao', 'google']) {
    for (final fail in <bool>[false, true]) {
      testWidgets('$provider 목업 fail=$fail 소셜 교환으로 로그인한다', (tester) async {
        final requests = <RequestOptions>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                requests.add(options);
                if (fail) {
                  handler.reject(DioException(requestOptions: options));
                } else {
                  handler.resolve(
                    Response<Object?>(
                      requestOptions: options,
                      data: <String, Object?>{
                        'access_token': 'demo-access',
                        'refresh_token': 'demo-refresh',
                      },
                    ),
                  );
                }
              },
            ),
          );
        addTearDown(dio.close);
        await _pumpSignIn(
          tester,
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://api.test',
            useMockApi: true,
          ),
          dio: dio,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SignInPage)),
        );
        container.read(sessionControllerProvider);
        await tester.pumpAndSettle();
        final button = find.byKey(ValueKey<String>('member-login-$provider'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final request = requests.single;
        expect(request.path, '/auth/social/$provider');
        expect(request.data, <String, Object?>{
          'token': 'demo-$provider-token',
        });
        expect(
          container.read(sessionControllerProvider).status,
          fail ? SessionStatus.signedOut : SessionStatus.authenticated,
        );
        // 데모에서는 안내 문구가 없다 — 버튼이 그대로 동작한다.
        expect(
          find.byKey(const ValueKey<String>('member-login-social-soon')),
          findsNothing,
        );
        if (fail) {
          expect(find.byType(SignInPage), findsOneWidget);
          expect(
            find.text(
              AppLocalizations.of(
                tester.element(find.byType(SignInPage)),
              ).authSocialSignInFailed,
            ),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('$provider 실 인증 설정에서는 눌러도 아무 요청도 나가지 않는다', (tester) async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  data: <String, Object?>{
                    'access_token': 'live-access',
                    'refresh_token': 'live-refresh',
                  },
                ),
              );
            },
          ),
        );
      addTearDown(dio.close);
      await _pumpSignIn(
        tester,
        const AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'https://api.test',
          useMockApi: false,
        ),
        dio: dio,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SignInPage)),
      );
      container.read(sessionControllerProvider);
      await tester.pumpAndSettle();
      requests.clear(); // 복구(세션 확인) 요청은 이 테스트의 관심이 아니다.

      final button = find.byKey(ValueKey<String>('member-login-$provider'));
      await tester.ensureVisible(button);
      await tester.tap(button, warnIfMissed: false);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        requests.where(
          (RequestOptions r) =>
              r.path == '/auth/login' || r.path.startsWith('/auth/social'),
        ),
        isEmpty,
      );
      expect(
        container.read(sessionControllerProvider).status,
        isNot(SessionStatus.authenticated),
      );
      expect(find.byType(SignInPage), findsOneWidget);
    });
  }

  testWidgets('같은 이메일 계정이 있으면 처음 가입한 방법으로 로그인하라고 알린다 (#1551)', (
    WidgetTester tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<Object?>(
                  requestOptions: options,
                  statusCode: 409,
                  data: <String, Object?>{
                    'detail': <String, Object?>{
                      'code': 'social_email_in_use',
                      'message': '이 이메일로 가입한 계정이 있어요.',
                    },
                  },
                ),
              ),
            );
          },
        ),
      );
    addTearDown(dio.close);
    await _pumpSignIn(
      tester,
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://api.test',
        useMockApi: true,
      ),
      dio: dio,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SignInPage)),
    );
    container.read(sessionControllerProvider);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey<String>('member-login-kakao'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final l = AppLocalizations.of(tester.element(find.byType(SignInPage)));
    expect(find.text(l.authSocialEmailInUse), findsOneWidget);
    expect(find.text(l.authSocialSignInFailed), findsNothing);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
  });

  testWidgets('목업 데모 설정에서는 소셜 로그인 버튼이 보인다', (WidgetTester tester) async {
    await _pumpSignIn(
      tester,
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
      ),
    );

    _expectSocialButtons(findsOneWidget);
    for (final String key in <String>[
      'member-login-kakao',
      'member-login-google',
    ]) {
      expect(
        tester
            .widget<AppSocialLoginButton>(find.byKey(ValueKey<String>(key)))
            .onPressed,
        isNotNull,
        reason: key,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('member-login-social-soon')),
      findsNothing,
    );
  });

  testWidgets('영어 실 인증 설정에서도 안내가 영어로 뜬다', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://dev.api.test',
              useMockApi: false,
            ),
          ),
          accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SignInPage(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Social sign-in is coming soon. Please sign in with your email',
      ),
      findsOneWidget,
    );
  });

  for (final (String name, AppConfig config) in <(String, AppConfig)>[
    (
      'USE_MOCK_API=false',
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: false,
      ),
    ),
    (
      'REAL_API=auth',
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://dev.api.test',
        useMockApi: true,
        realApiFeatures: <String>{'auth'},
      ),
    ),
    (
      'ENV=prod',
      const AppConfig(
        environment: Environment.prod,
        apiBaseUrl: 'https://api.test',
        useMockApi: false,
      ),
    ),
  ]) {
    testWidgets('$name 에서는 소셜 버튼을 자리만 지키고 꺼 둔다', (WidgetTester tester) async {
      await _pumpSignIn(tester, config);

      // 배치는 그대로다 — 숨기지 않고 끈다(#2769).
      _expectSocialButtons(findsOneWidget);
      for (final String key in <String>[
        'member-login-kakao',
        'member-login-google',
      ]) {
        expect(
          tester
              .widget<AppSocialLoginButton>(find.byKey(ValueKey<String>(key)))
              .onPressed,
          isNull,
          reason: key,
        );
      }
      expect(
        find.byKey(const ValueKey<String>('member-login-social-soon')),
        findsOneWidget,
      );
      expect(find.text('소셜 로그인은 준비 중이에요. 이메일로 로그인해 주세요'), findsOneWidget);
      // 일반 로그인과 회원가입도 계속 사용할 수 있다.
      expect(
        find.byKey(const ValueKey<String>('member-login-submit')),
        findsOneWidget,
      );
      expect(find.text('회원가입'), findsWidgets);
    });
  }
}
