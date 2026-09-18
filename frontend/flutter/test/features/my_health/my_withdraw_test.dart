/// 회원 탈퇴 — 고객 지원 안의 두 칸. (#1935·#2019)
///
/// 탈퇴 동작 자체는 #1935 그대로다: `DELETE /users/me` 를 부르고, 성공하면
/// 계정에 매인 기기 기록을 지운 뒤 세션을 비우고 로그인 화면으로 보낸다.
/// #2019 에서 그 앞에 두 칸이 붙었다 — 무엇이 불편했는지 묻고(건너뛸 수 있다),
/// 고른 것마다 탈퇴 말고 무엇으로 풀리는지 답한다.
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
import 'package:oncare/features/my_health/presentation/pages/withdraw_page.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 탈퇴 요청을 받아 적고, 원하면 실패시키는 저장소.
class _CountingAccountRepository extends MockAccountRepository {
  _CountingAccountRepository({this.fails = false});

  final bool fails;
  int deletes = 0;
  List<String> lastReasons = const <String>[];

  @override
  Future<void> deleteAccount({List<String> reasons = const <String>[]}) async {
    deletes++;
    lastReasons = reasons;
    if (fails) throw Exception('offline');
  }
}

Finder _reason(String code) =>
    find.byKey(ValueKey<String>('withdrawReason-$code'));
Finder _keep(String code) => find.byKey(ValueKey<String>('withdrawKeep-$code'));
Finder _next() => find.byKey(const ValueKey<String>('withdrawNextButton'));
Finder _continue() =>
    find.byKey(const ValueKey<String>('withdrawContinueButton'));

Future<(AppLocalizations, _CountingAccountRepository, AppPrefs)> _pumpWithdraw(
  WidgetTester tester, {
  bool fails = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
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
    initialLocation: AppRoutes.mySettingsPath('support'),
    routes: <RouteBase>[
      // 실제 경로 그대로다 — 고객 지원의 줄이 미는 곳과 한 글자라도 어긋나면
      // 테스트만 통과하고 앱에서는 아무 데도 가지 않는다.
      GoRoute(
        path: AppRoutes.mySettingsPath('support'),
        builder: (_, _) => const SupportPage(),
      ),
      GoRoute(
        path: AppRoutes.mySettingsPath('withdraw'),
        builder: (_, _) => const WithdrawPage(),
      ),
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
    AppLocalizations.of(tester.element(find.byType(SupportPage))),
    repository,
    AppPrefs(prefs),
  );
}

/// 고객 지원 목록의 회원 탈퇴 줄을 눌러 첫 칸까지 간다.
Future<void> _openWithdraw(WidgetTester tester, AppLocalizations l) async {
  await tester.tap(find.text(l.myWithdrawTitle));
  await tester.pumpAndSettle();
}

/// 되돌릴 수 없다는 확인창까지 간다.
Future<void> _reachConfirm(WidgetTester tester) async {
  await tester.tap(_next());
  await tester.pumpAndSettle();
  await tester.tap(_continue());
  await tester.pumpAndSettle();
}

/// 탈퇴는 서버 요청 → 기기 기록 정리 → 세션 비우기를 차례로 기다린다.
Future<void> _settleDeletion(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('탈퇴는 고객 지원 안에 있다 (#2019)', (WidgetTester tester) async {
    final (AppLocalizations l, _, _) = await _pumpWithdraw(tester);

    // 개인정보 처리방침 다음 줄 — 계정을 정리하는 칸으로 묶는다.
    expect(find.text(l.myWithdrawTitle), findsOneWidget);

    await _openWithdraw(tester, l);

    expect(find.byType(WithdrawPage), findsOneWidget);
    expect(find.text(l.myWithdrawReasonTitle), findsOneWidget);
    expect(find.text(l.myWithdrawReasonQuestion), findsOneWidget);
    expect(find.text(l.myWithdrawReasonHint), findsOneWidget);
  });

  testWidgets('사유는 묻는 것이지 받아 내는 것이 아니다 — 안 골라도 넘어간다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo, _) =
        await _pumpWithdraw(tester);
    await _openWithdraw(tester, l);

    await tester.tap(_next());
    await tester.pumpAndSettle();

    expect(_keep('default'), findsOneWidget);
    expect(find.text(l.myWithdrawKeepDefault), findsOneWidget);
    expect(repo.deletes, 0);
  });

  testWidgets('고른 사유마다 탈퇴 말고 풀 길을 하나씩 답한다', (WidgetTester tester) async {
    final (AppLocalizations l, _, _) = await _pumpWithdraw(tester);
    await _openWithdraw(tester, l);

    await tester.tap(_reason('privacy'));
    await tester.tap(_reason('too_many_notifications'));
    await tester.pumpAndSettle();
    await tester.tap(_next());
    await tester.pumpAndSettle();

    expect(_keep('privacy'), findsOneWidget);
    expect(_keep('too_many_notifications'), findsOneWidget);
    expect(find.text(l.myWithdrawKeepPrivacy), findsOneWidget);
    expect(find.text(l.myWithdrawKeepNotifications), findsOneWidget);
    // 고르지 않은 것까지 늘어놓으면 답이 아니라 목록이 된다.
    expect(_keep('hard_to_use'), findsNothing);
    expect(_keep('default'), findsNothing);
  });

  testWidgets('두 번째 칸에서도 바로 지우지 않는다 — 무엇이 사라지는지 먼저 말한다', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo, _) =
        await _pumpWithdraw(tester);
    await _openWithdraw(tester, l);

    await _reachConfirm(tester);

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
    expect(find.byType(WithdrawPage), findsOneWidget);
  });

  testWidgets('확인하면 고른 사유와 함께 지우고, 기기 기록을 비운 뒤 로그인 화면으로 간다', (
    WidgetTester tester,
  ) async {
    final (
      AppLocalizations l,
      _CountingAccountRepository repo,
      AppPrefs prefs,
    ) = await _pumpWithdraw(
      tester,
    );
    await _openWithdraw(tester, l);

    await tester.tap(_reason('hard_to_use'));
    await tester.pumpAndSettle();
    await _reachConfirm(tester);
    await tester.tap(find.text(l.myWithdrawAction));
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    // 화면 글이 아니라 서버가 받는 코드로 보낸다 — 번역이 바뀌어도 집계는 잇는다.
    expect(repo.lastReasons, <String>['hard_to_use']);
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
    ) = await _pumpWithdraw(
      tester,
      fails: true,
    );
    await _openWithdraw(tester, l);

    await _reachConfirm(tester);
    await tester.tap(find.text(l.myWithdrawAction));
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    expect(find.text(l.myWithdrawFailed), findsOneWidget);
    // 계정이 남아 있는데 기기 기록만 지우면 다음 로그인에서 첫 설정을 다시 묻는다.
    expect(prefs.onboardingDone, isTrue);
    expect(find.byType(WithdrawPage), findsOneWidget);
  });

  testWidgets('계속 쓰기로 하면 고객 지원으로 돌아간다', (WidgetTester tester) async {
    final (AppLocalizations l, _CountingAccountRepository repo, _) =
        await _pumpWithdraw(tester);
    await _openWithdraw(tester, l);

    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('withdrawStayButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SupportPage), findsOneWidget);
    expect(repo.deletes, 0);
  });
}
