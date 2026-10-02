/// 첫 설정 `건너뛰기` 를 계정에 남긴다. (#2855)
///
/// 예전 `건너뛰기` 는 이동만 해서, 건너뛴 회원이 다음 로그인·세션 복구마다 같은
/// 첫 설정 폼으로 다시 끌려갔다. 앱 안(MY 건강 목표)에서 다시 연 첫 설정은 연
/// 자리로 돌아간다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/pages/onboarding_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 가입 직후 계정 — 첫 설정을 끝내지도 건너뛰지도 않았다.
const UserProfile _fresh = UserProfile(
  id: 'user-new',
  name: '새회원',
  email: 'new@oncare.com',
);

class _CountingRepository extends MockAccountRepository {
  _CountingRepository({this.failSkip = false}) : super(profile: _fresh);

  final bool failSkip;
  int skipCalls = 0;

  @override
  Future<UserProfile> skipOnboarding() async {
    skipCalls++;
    if (failSkip) throw StateError('offline');
    return super.skipOnboarding();
  }
}

/// 실제 경로로 띄운다. [start] 가 `/` 면 앱 안에서 다시 여는 경우를 흉내 낸다 —
/// 시작 화면의 버튼이 [AppRoutes.onboardingResume] 을 쌓는다.
Future<ProviderContainer> _open(
  WidgetTester tester,
  _CountingRepository repo, {
  String start = AppRoutes.onboarding,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final GoRouter router = GoRouter(
    initialLocation: start,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push<void>(AppRoutes.onboardingResume),
            child: const Text('건강 목표'),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, GoRouterState state) =>
            OnboardingPage(resumed: state.uri.queryParameters['from'] == 'app'),
      ),
      GoRoute(
        path: AppRoutes.guideTour,
        builder: (_, _) => const Scaffold(body: Text('앱 사용 가이드')),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const Scaffold(body: Text('홈')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
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
  return ProviderScope.containerOf(
    tester.element(find.byType(Navigator).first),
  );
}

Future<void> _tapSkip(WidgetTester tester) async {
  final AppLocalizations l = AppLocalizations.of(
    tester.element(find.byType(OnboardingPage)),
  );
  await tester.tap(find.text(l.onboardSkip));
  await tester.pumpAndSettle();
}

void main() {
  group('가입 직후 첫 설정', () {
    testWidgets('건너뛰면 계정에 남기고 가이드로 간다', (tester) async {
      final _CountingRepository repo = _CountingRepository();
      final ProviderContainer c = await _open(tester, repo);

      await _tapSkip(tester);

      expect(repo.skipCalls, 1);
      expect(find.text('앱 사용 가이드'), findsOneWidget);
      // 다음 판단이 읽는 프로필도 건너뛴 계정이다.
      final UserProfile now = await repo.fetchProfile();
      expect(now.onboardingSkipped, isTrue);
      expect(now.onboarded, isFalse);
      expect(c.read(profileProvider).valueOrNull?.onboardingSkipped, isTrue);
      // 프로필을 못 받아 왔을 때의 보조 기록도 남는다.
      expect(c.read(appPrefsProvider).onboardingDone, isTrue);
    });

    testWidgets('남기지 못해도 건너뛰기는 막지 않는다', (tester) async {
      final _CountingRepository repo = _CountingRepository(failSkip: true);
      final ProviderContainer c = await _open(tester, repo);

      await _tapSkip(tester);

      expect(repo.skipCalls, 1);
      expect(find.text('앱 사용 가이드'), findsOneWidget);
      // 서버에 남지 않았으니 이 기기에도 끝냈다고 적지 않는다 — 다음 진입 때
      // 다시 묻는 예전 동작으로 남는다.
      expect(c.read(appPrefsProvider).onboardingDone, isFalse);
    });
  });

  group('앱 안에서 다시 연 첫 설정', () {
    testWidgets('건너뛰면 서버에 다시 남기지 않고 연 자리로 돌아간다', (tester) async {
      final _CountingRepository repo = _CountingRepository();
      await _open(tester, repo, start: '/');
      await tester.tap(find.text('건강 목표'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);

      await _tapSkip(tester);

      expect(repo.skipCalls, 0);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('건강 목표'), findsOneWidget);
      expect(find.text('앱 사용 가이드'), findsNothing);
    });

    testWidgets('쌓인 자리가 없으면 홈으로 간다', (tester) async {
      final _CountingRepository repo = _CountingRepository();
      await _open(tester, repo, start: AppRoutes.onboardingResume);

      await _tapSkip(tester);

      expect(find.text('홈'), findsOneWidget);
      expect(find.text('앱 사용 가이드'), findsNothing);
    });
  });

  test('목업 저장소의 건너뛰기는 다른 값을 건드리지 않는다', () async {
    final MockAccountRepository repo = MockAccountRepository(profile: _fresh);

    final UserProfile skipped = await repo.skipOnboarding();

    expect(skipped.onboardingSkipped, isTrue);
    expect(skipped.onboarded, isFalse);
    expect(skipped.name, '새회원');
    expect(skipped.birthDate, isEmpty);
  });

  test('목업 저장소의 첫 설정 저장은 끝낸 계정으로 표시하고 건너뛰기를 유지한다', () async {
    final MockAccountRepository repo = MockAccountRepository(profile: _fresh);
    await repo.skipOnboarding();

    final UserProfile done = await repo.submitOnboarding(heightCm: 170);

    expect(done.onboarded, isTrue);
    expect(done.onboardingSkipped, isTrue);
    expect(done.heightCm, 170);
  });
}
