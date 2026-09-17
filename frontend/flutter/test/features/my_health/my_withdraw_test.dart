/// MY 탭의 회원 탈퇴. (#1935)
///
/// 계정을 지우는 길이 화면에 없어, 떠나려는 회원은 로그아웃밖에 못 하고 계정과
/// 건강 기록은 그대로 남았다. 서버(`DELETE /users/me`)와 저장소는 이미 준비돼
/// 있었고 **부르는 곳만 0건**이었다.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 탈퇴 요청을 세고, 원하면 실패시키는 저장소.
class _CountingAccountRepository extends MockAccountRepository {
  _CountingAccountRepository({this.fails = false});

  final bool fails;
  int deletes = 0;

  @override
  Future<void> deleteAccount() async {
    deletes++;
    if (fails) throw Exception('offline');
  }
}

Finder _withdraw() => find.byKey(const ValueKey<String>('my-withdraw-button'));

Future<(AppLocalizations, _CountingAccountRepository, AppPrefs)> _pumpMyTab(
  WidgetTester tester, {
  bool fails = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // 탈퇴가 끝나면 로그아웃과 같은 정리가 돈다 — 저장된 토큰과, 그 토큰을
  // 폐기하는 `POST /auth/logout` 을 받아 줄 자리가 있어야 끝까지 간다.
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'access_token': 'stored-access',
    'refresh_token': 'stored-refresh',
  });
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Map<String, Object?>>(
            requestOptions: options,
            statusCode: 200,
            data: <String, Object?>{'id': 'u1'},
          ),
        );
      },
    ),
  );

  // 탈퇴는 계정에 매인 기기 기록도 지운다 — 남아 있는 상태에서 시작한다.
  SharedPreferences.setMockInitialValues(<String, Object>{
    'onboarding_done': true,
    'home_guide_done': true,
    'locale_code': 'ko',
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final _CountingAccountRepository repository = _CountingAccountRepository(
    fails: fails,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/my',
    routes: <RouteBase>[
      GoRoute(path: '/my', builder: (_, _) => const MyHealthPage()),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (_, _) => const Scaffold(body: Text('로그인 화면')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
        accountRepositoryProvider.overrideWithValue(repository),
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        myHealthRepositoryProvider.overrideWithValue(
          const MockMyHealthRepository(),
        ),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    AppLocalizations.of(tester.element(find.byType(MyHealthPage))),
    repository,
    AppPrefs(prefs),
  );
}

Future<void> _openConfirm(WidgetTester tester) async {
  await tester.ensureVisible(_withdraw());
  await tester.pumpAndSettle();
  await tester.tap(_withdraw());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('설정 목록 끝에 탈퇴 자리가 있다', (WidgetTester tester) async {
    final (AppLocalizations l, _, _) = await _pumpMyTab(tester);

    expect(_withdraw(), findsOneWidget);
    expect(
      find.descendant(of: _withdraw(), matching: find.text(l.myWithdrawTitle)),
      findsOneWidget,
    );
  });

  testWidgets('누르자마자 지우지 않는다 — 무엇이 사라지는지 먼저 말한다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo, _) =
        await _pumpMyTab(tester);

    await _openConfirm(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text(l.myWithdrawConfirm), findsOneWidget);
    expect(repo.deletes, 0);
    // 되돌릴 수 없는 동작이므로 확정은 빨간 버튼이다.
    expect(
      tester.widget<AppButtonPair>(find.byType(AppButtonPair)).destructive,
      isTrue,
    );

    await tester.tap(find.text(l.myCancel));
    await tester.pumpAndSettle();
    expect(repo.deletes, 0, reason: '취소하면 아무것도 지우지 않는다');
    expect(find.byType(MyHealthPage), findsOneWidget);
  });

  testWidgets('확인하면 계정을 지우고 기기 기록을 비운 뒤 로그인 화면으로 간다', (
    WidgetTester tester,
  ) async {
    final (
      AppLocalizations l,
      _CountingAccountRepository repo,
      AppPrefs prefs,
    ) = await _pumpMyTab(
      tester,
    );

    await _openConfirm(tester);
    await tester.tap(find.text(l.myWithdrawAction));
    // 탈퇴는 서버 요청 → 기기 기록 정리 → 세션 비우기를 차례로 기다린다.
    for (int i = 0; i < 5; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    }

    expect(repo.deletes, 1);
    expect(prefs.onboardingDone, isFalse);
    expect(prefs.homeGuideDone, isFalse);
    // 언어는 기기 설정이라 남는다.
    expect(prefs.localeCode, 'ko');
    expect(find.text('로그인 화면'), findsOneWidget);
  });

  testWidgets('지우지 못하면 알리고 그 자리에 머문다', (WidgetTester tester) async {
    final (
      AppLocalizations l,
      _CountingAccountRepository repo,
      AppPrefs prefs,
    ) = await _pumpMyTab(
      tester,
      fails: true,
    );

    await _openConfirm(tester);
    await tester.tap(find.text(l.myWithdrawAction));
    // 탈퇴는 서버 요청 → 기기 기록 정리 → 세션 비우기를 차례로 기다린다.
    for (int i = 0; i < 5; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    }

    expect(repo.deletes, 1);
    expect(find.text(l.myWithdrawFailed), findsOneWidget);
    // 계정이 남아 있는데 기기 기록만 지우면 다음 로그인에서 첫 설정을 다시 묻는다.
    expect(prefs.onboardingDone, isTrue);
    expect(find.byType(MyHealthPage), findsOneWidget);
  });
}
