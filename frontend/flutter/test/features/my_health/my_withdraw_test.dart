/// 회원 탈퇴 — 고객 지원 안의 두 칸. (#1935·#2019)
///
/// 탈퇴 동작 자체는 #1935 그대로다: `DELETE /users/me` 를 부르고, 성공하면
/// 계정에 매인 기기 기록을 지운 뒤 세션을 비우고 로그인 화면으로 보낸다.
/// #2019 에서 그 앞에 두 칸이 붙었다 — 무엇이 불편했는지 묻고(건너뛸 수 있다),
/// 고른 것마다 탈퇴 말고 무엇으로 풀리는지 답한다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/domain/entities/account_deletion_preview.dart';
import 'package:oncare/features/account/domain/entities/account_reauth.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/controllers/withdraw_preview_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/withdraw_page.dart';
import 'package:oncare/features/my_health/presentation/widgets/account_reauth_dialog.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_account_repository.dart';

/// 본인 확인에서 맞다고 보는 현재 비밀번호(#3039). 테스트 전용 값이다.
const String _currentPassword = 'pw-current-1';

/// 탈퇴 요청을 받아 적고, 원하면 실패시키는 저장소.
class _CountingAccountRepository extends MockAccountRepository {
  _CountingAccountRepository({this.fails = false, super.profile})
    : super(currentPassword: _currentPassword);

  final bool fails;
  int deletes = 0;
  List<String> lastReasons = const <String>[];

  /// 채워 두면 탈퇴 요청이 이것이 끝날 때까지 서버에 머문다(#3245).
  Completer<void>? gate;

  @override
  Future<void> deleteAccount({
    List<String> reasons = const <String>[],
    AccountReauth? reauth,
  }) async {
    deletes++;
    lastReasons = reasons;
    await gate?.future;
    if (fails) throw Exception('offline');
    // 본인 확인 판정은 대역의 것 그대로다 — 틀리면 400 처럼 거절한다.
    await super.deleteAccount(reasons: reasons, reauth: reauth);
  }
}

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

Finder _reason(String code) =>
    find.byKey(ValueKey<String>('withdrawReason-$code'));
Finder _keep(String code) => find.byKey(ValueKey<String>('withdrawKeep-$code'));
Finder _next() => find.byKey(const ValueKey<String>('withdrawNextButton'));
Finder _continue() =>
    find.byKey(const ValueKey<String>('withdrawContinueButton'));

Future<(AppLocalizations, _CountingAccountRepository, AppPrefs)> _pumpWithdraw(
  WidgetTester tester, {
  bool fails = false,
  bool hasPassword = true,
  WithdrawPreviewLoader? preview,
  Locale locale = const Locale('ko'),
  Size size = const Size(390, 1200),
}) async {
  await tester.binding.setSurfaceSize(size);
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
  final _CountingAccountRepository repository = hasPassword
      ? _CountingAccountRepository(fails: fails)
      : _CountingAccountRepository(
          fails: fails,
          // 비밀번호 없이 소셜로만 가입한 회원(#3039).
          profile: const UserProfile(
            id: 'user-social',
            name: '김민수',
            email: 'minsu@oncare.com',
            phone: '010-1234-5678',
            birthDate: '1990-01-15',
            gender: 'male',
            hasPassword: false,
          ),
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
        // 소셜 다시 로그인은 기기 안 목업 설정에서만 열린다.
        appConfigProvider.overrideWithValue(_mockConfig),
        // 기본은 잃는 것이 없는 계정 — 확인창은 일반 문구만 띄운다(#3006).
        withdrawPreviewLoaderProvider.overrideWithValue(
          preview ?? repository.fetchDeletionPreview,
        ),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(),
        locale: locale,
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

Finder _reauthPassword() =>
    find.byKey(const ValueKey<String>('reauth-password'));
Finder _reauthConfirm() => find.byKey(const ValueKey<String>('reauth-confirm'));

AppButton _confirmButton(WidgetTester tester) =>
    tester.widget<AppButton>(_reauthConfirm());

/// 확인창에 현재 비밀번호를 적고 빨간 버튼을 누른다(#3039).
Future<void> _confirmWithPassword(
  WidgetTester tester, [
  String password = _currentPassword,
]) async {
  await tester.enterText(_reauthPassword(), password);
  await tester.pump();
  await tester.tap(_reauthConfirm());
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
    await _confirmWithPassword(tester);
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    // 화면 글이 아니라 서버가 받는 코드로 보낸다 — 번역이 바뀌어도 집계는 잇는다.
    expect(repo.lastReasons, <String>['hard_to_use']);
    // 적은 현재 비밀번호가 본인 확인으로 함께 나간다(#3039).
    expect(repo.lastReauth?.currentPassword, _currentPassword);
    expect(repo.lastReauth?.socialToken, isNull);
    expect(prefs.onboardingDone, isFalse);
    expect(prefs.homeGuideDone, isFalse);
    // 언어는 기기 설정이라 남는다.
    expect(prefs.localeCode, 'ko');
    expect(find.text('로그인 화면'), findsOneWidget);
  });

  testWidgets('탈퇴 요청이 도는 동안에는 바깥·뒤로 가기로 창이 닫히지 않는다 (#3245)', (
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
    await _reachConfirm(tester);
    repo.gate = Completer<void>();
    await _confirmWithPassword(tester);
    await tester.pump();

    // 바깥을 누르고, 뒤로 가기를 보낸다.
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AccountReauthDialog), findsOneWidget);

    repo.gate!.complete();
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    expect(prefs.onboardingDone, isFalse);
    expect(find.text('로그인 화면'), findsOneWidget);
  });

  testWidgets('요청 중 창이 다른 길로 닫혀도 탈퇴가 끝나면 로그아웃한다 (#3245)', (
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
    await _reachConfirm(tester);
    repo.gate = Completer<void>();
    await _confirmWithPassword(tester);
    await tester.pump();

    // 창만 걷어 낸다 — 결과 없이 닫히면 부른 쪽은 `취소` 로 받는다.
    Navigator.of(tester.element(find.byType(AccountReauthDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AccountReauthDialog), findsNothing);
    expect(find.byType(WithdrawPage), findsOneWidget);

    repo.gate!.complete();
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    expect(prefs.onboardingDone, isFalse);
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
    await _confirmWithPassword(tester);
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    expect(find.text(l.myWithdrawFailed), findsOneWidget);
    // 계정이 남아 있는데 기기 기록만 지우면 다음 로그인에서 첫 설정을 다시 묻는다.
    expect(prefs.onboardingDone, isTrue);
    expect(find.byType(WithdrawPage), findsOneWidget);
  });

  testWidgets('현재 비밀번호를 적기 전에는 빨간 버튼이 꺼져 있다 (#3039)', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo, _) =
        await _pumpWithdraw(tester);
    await _openWithdraw(tester, l);
    await _reachConfirm(tester);

    expect(_reauthPassword(), findsOneWidget);
    expect(find.text(l.reauthPasswordPrompt), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.tap(_reauthConfirm(), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.deletes, 0);

    await tester.enterText(_reauthPassword(), 'x');
    await tester.pump();
    expect(_confirmButton(tester).onPressed, isNotNull);

    await tester.enterText(_reauthPassword(), '');
    await tester.pump();
    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('비밀번호가 틀리면 창 안에 알리고 로그아웃하지 않는다 (#3039)', (
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
    await _reachConfirm(tester);

    await _confirmWithPassword(tester, 'wrong-password');
    await _settleDeletion(tester);

    // 창은 그대로 열려 있고, 칸 아래에 이유가 붙는다.
    expect(find.byType(AccountReauthDialog), findsOneWidget);
    expect(find.text(l.passwordChangeWrongCurrent), findsOneWidget);
    // 400 은 세션 문제가 아니다 — 기기 기록도 세션도 그대로다.
    expect(prefs.onboardingDone, isTrue);
    expect(find.text('로그인 화면'), findsNothing);
    expect(find.byType(WithdrawPage), findsOneWidget);

    // 다시 적으면 이유는 걷히고, 맞는 비밀번호로는 끝까지 간다.
    await tester.enterText(_reauthPassword(), _currentPassword);
    await tester.pump();
    expect(find.text(l.passwordChangeWrongCurrent), findsNothing);
    await tester.tap(_reauthConfirm());
    await _settleDeletion(tester);
    expect(repo.lastReauth?.currentPassword, _currentPassword);
    expect(find.text('로그인 화면'), findsOneWidget);
  });

  testWidgets('소셜 전용 계정은 비밀번호 칸 대신 다시 로그인 버튼이다 (#3039)', (
    WidgetTester tester,
  ) async {
    final (AppLocalizations l, _CountingAccountRepository repo, _) =
        await _pumpWithdraw(tester, hasPassword: false);
    await _openWithdraw(tester, l);
    await _reachConfirm(tester);

    expect(_reauthPassword(), findsNothing);
    expect(find.text(l.reauthSocialAction), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reauth-social-kakao')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reauth-social-google')),
      findsOneWidget,
    );
    // 다시 로그인하기 전에는 지울 수 없다.
    expect(_confirmButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey<String>('reauth-social-kakao')));
    await tester.pumpAndSettle();
    expect(find.text(l.reauthSocialConfirmed), findsOneWidget);
    expect(_confirmButton(tester).onPressed, isNotNull);

    await tester.tap(_reauthConfirm());
    await _settleDeletion(tester);

    expect(repo.deletes, 1);
    expect(repo.lastReauth?.socialProvider, 'kakao');
    expect(repo.lastReauth?.socialToken, 'demo-kakao-token');
    expect(repo.lastReauth?.currentPassword, isNull);
    expect(find.text('로그인 화면'), findsOneWidget);
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

  group('확인창은 이 계정이 잃는 것을 숫자로 말한다 (#3006)', () {
    testWidgets('0 이 아닌 것만 한 줄씩 덧붙인다', (WidgetTester tester) async {
      final (
        AppLocalizations l,
        _CountingAccountRepository repo,
        _,
      ) = await _pumpWithdraw(
        tester,
        preview: () async => const AccountDeletionPreview(
          points: 1200,
          activeCoupons: 2,
          upcomingReservations: 1,
        ),
      );
      await _openWithdraw(tester, l);
      await _reachConfirm(tester);

      expect(find.byType(AppDialog), findsOneWidget);
      final String message = withdrawConfirmMessage(
        l,
        const AccountDeletionPreview(
          points: 1200,
          activeCoupons: 2,
          upcomingReservations: 1,
        ),
      );
      expect(find.text(message), findsOneWidget);
      expect(message, startsWith(l.myWithdrawConfirm));
      expect(message, contains(l.myWithdrawLosePoints(1200)));
      expect(message, contains('1,200P'));
      expect(message, contains(l.myWithdrawLoseCoupons(2)));
      expect(message, contains(l.myWithdrawCancelReservations(1)));
      // 대기 중인 상담이 없으면 그 줄은 없다 — 0건을 말하면 겁만 준다.
      expect(message, isNot(contains(l.myWithdrawCancelConsultations(0))));
      expect(repo.deletes, 0);
    });

    testWidgets('잃는 것이 없으면 기본 문구만 띄운다', (WidgetTester tester) async {
      final (AppLocalizations l, _, _) = await _pumpWithdraw(tester);
      await _openWithdraw(tester, l);
      await _reachConfirm(tester);

      expect(find.text(l.myWithdrawConfirm), findsOneWidget);
    });

    testWidgets('숫자를 못 읽어도 탈퇴는 막지 않는다 — 기본 문구로 물러선다', (
      WidgetTester tester,
    ) async {
      final (
        AppLocalizations l,
        _CountingAccountRepository repo,
        _,
      ) = await _pumpWithdraw(
        tester,
        preview: () async => throw Exception('offline'),
      );
      await _openWithdraw(tester, l);
      await _reachConfirm(tester);

      expect(find.text(l.myWithdrawConfirm), findsOneWidget);
      // 본인 확인은 그대로 거친다(#3039).
      await _confirmWithPassword(tester);
      await _settleDeletion(tester);
      expect(repo.deletes, 1);
    });

    testWidgets('영어 로케일에서도 숫자 줄이 붙는다', (WidgetTester tester) async {
      final (AppLocalizations l, _, _) = await _pumpWithdraw(
        tester,
        locale: const Locale('en'),
        preview: () async =>
            const AccountDeletionPreview(points: 300, pendingConsultations: 1),
      );
      await _openWithdraw(tester, l);
      await _reachConfirm(tester);

      final String message = withdrawConfirmMessage(
        l,
        const AccountDeletionPreview(points: 300, pendingConsultations: 1),
      );
      expect(find.text(message), findsOneWidget);
      expect(message, contains('300P'));
      expect(message, contains(l.myWithdrawCancelConsultations(1)));
    });

    testWidgets('작은 화면에서도 확인창이 넘치지 않는다', (WidgetTester tester) async {
      final (AppLocalizations l, _, _) = await _pumpWithdraw(
        tester,
        size: const Size(320, 568),
        preview: () async => const AccountDeletionPreview(
          points: 125000,
          activeCoupons: 12,
          upcomingReservations: 4,
          pendingConsultations: 3,
        ),
      );
      await _openWithdraw(tester, l);
      await _reachConfirm(tester);

      expect(find.byType(AppDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 확정 버튼이 화면 안에 남는다.
      expect(find.text(l.myWithdrawAction).hitTestable(), findsOneWidget);
    });
  });
}
