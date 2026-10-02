/// 첫 설정을 건너뛴 회원에게 MY 건강 목표가 기본 정보 입력으로 가는 길을
/// 보여 준다. (#2855)
///
/// 건너뛰기가 계정에 남아 로그인할 때 더는 첫 설정으로 끌려가지 않으므로,
/// 생년월일·키·체중을 넣을 자리가 따로 있어야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/mock_account_repository.dart';

const UserProfile _skipped = UserProfile(
  id: 'user-skip',
  onboardingSkipped: true,
  name: '건너뜀',
  email: 'skip@oncare.com',
);

const UserProfile _done = UserProfile(
  id: 'user-done',
  onboarded: true,
  name: '끝냄',
  email: 'done@oncare.com',
);

/// 건너뛰었다가 MY 에서 다시 열어 끝낸 회원.
const UserProfile _skippedThenDone = UserProfile(
  id: 'user-both',
  onboarded: true,
  onboardingSkipped: true,
  name: '다시함',
  email: 'both@oncare.com',
);

Future<List<String>> _open(WidgetTester tester, UserProfile profile) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final List<String> opened = <String>[];
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const HealthGoalsPage()),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('첫 설정'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(profile: profile),
        ),
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
  return opened;
}

void main() {
  testWidgets('건너뛴 회원에게는 기본 정보 입력 안내가 보인다', (tester) async {
    await _open(tester, _skipped);

    expect(find.byKey(const Key('firstRunPrompt')), findsOneWidget);
    expect(find.text('기본 정보를 입력하면 맞춤 목표를 계산해요'), findsOneWidget);
    expect(find.text('기본 정보 입력'), findsOneWidget);
  });

  testWidgets('안내를 누르면 앱 안 첫 설정이 열린다', (tester) async {
    final List<String> opened = await _open(tester, _skipped);

    await tester.tap(find.text('기본 정보 입력'));
    await tester.pumpAndSettle();

    expect(find.text('첫 설정'), findsOneWidget);
    expect(opened.single, AppRoutes.onboardingResume);
  });

  testWidgets('첫 설정을 끝낸 회원에게는 안내가 없다', (tester) async {
    await _open(tester, _done);

    expect(find.byKey(const Key('firstRunPrompt')), findsNothing);
  });

  testWidgets('건너뛰었다가 끝낸 회원에게도 안내가 없다', (tester) async {
    await _open(tester, _skippedThenDone);

    expect(find.byKey(const Key('firstRunPrompt')), findsNothing);
  });

  testWidgets('편집 중에는 안내를 내리고 목표 칸에 집중한다', (tester) async {
    await _open(tester, _skipped);

    await tester.tap(find.byKey(const Key('goalsEditButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firstRunPrompt')), findsNothing);
  });
}
