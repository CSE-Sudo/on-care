/// 소셜 버튼은 항상 노출하고 목업·실 인증 경로를 구분한다(#2069).
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

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
  for (final mock in <bool>[true, false]) {
    for (final provider in <String>['kakao', 'google']) {
      for (final fail in <bool>[false, true]) {
        testWidgets('$provider mock=$mock fail=$fail 로그인 경로와 세션', (
          tester,
        ) async {
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
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'https://api.test',
              useMockApi: mock,
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
          expect(request.path, mock ? '/auth/social/$provider' : '/auth/login');
          expect(
            request.data,
            mock
                ? <String, Object?>{'token': 'demo-$provider-token'}
                : <String, Object?>{
                    'username': 'minsu@oncare.com',
                    'password': 'oncare123',
                  },
          );
          expect(
            container.read(sessionControllerProvider).status,
            fail ? SessionStatus.signedOut : SessionStatus.authenticated,
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
    }
  }

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
    testWidgets('$name 에서는 소셜 버튼을 보여 준다', (WidgetTester tester) async {
      await _pumpSignIn(tester, config);

      _expectSocialButtons(findsOneWidget);
      // 일반 로그인과 회원가입도 계속 사용할 수 있다.
      expect(
        find.byKey(const ValueKey<String>('member-login-submit')),
        findsOneWidget,
      );
      expect(find.text('회원가입'), findsWidgets);
    });
  }
}
