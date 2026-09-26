/// MY → `트레이너 리포트` 입구. (#2232)
///
/// 트레이너가 보낸 리포트를 대화 안에서만 열 수 있으면, 지난주 것을 다시
/// 보려면 그 주의 메시지까지 스크롤을 올려야 한다. MY 에 줄을 하나 두어
/// 목록으로 가게 한다.
///
/// 단, **담당 트레이너가 있는 회원에게만** 보인다. 담당이 없는 회원에게 이
/// 줄은 눌러도 늘 비어 있는 화면이고, 그건 없는 기능을 있는 것처럼 보이게
/// 하는 것이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';
import '../benefits/fake_benefits_repository.dart';

const Key _entry = ValueKey<String>('my-coach-reports-entry');

Future<void> _pumpMy(
  WidgetTester tester, {
  required FakeMemberCoachRepository repository,
  String locale = 'ko',
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final GoRouter router = GoRouter(
    initialLocation: AppRoutes.myHealth,
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.myHealth, builder: (_, _) => const MyHealthPage()),
      GoRoute(
        path: AppRoutes.myCoachReports,
        builder: (_, _) => const Scaffold(body: Center(child: Text('리포트 목록'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        gymRepositoryProvider.overrideWithValue(MockGymRepository()),
        myHealthRepositoryProvider.overrideWithValue(
          const MockMyHealthRepository(),
        ),
        benefitsRepositoryProvider.overrideWithValue(FakeBenefitsRepository()),
        memberCoachRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => useFixedKstDate());

  testWidgets('담당 트레이너가 있으면 리포트 줄이 선다', (tester) async {
    await _pumpMy(tester, repository: FakeMemberCoachRepository());

    expect(find.byKey(_entry), findsOneWidget);
    expect(find.text('트레이너 리포트'), findsOneWidget);
  });

  testWidgets('무엇이 있는 줄인지 한 줄로 말한다', (tester) async {
    await _pumpMy(tester, repository: FakeMemberCoachRepository());

    expect(find.text('받은 리포트와 보낸 주간 피드백'), findsOneWidget);
  });

  testWidgets('담당이 없는 회원에게는 보이지 않는다', (tester) async {
    await _pumpMy(tester, repository: FakeMemberCoachRepository(coach: null));

    expect(find.byKey(_entry), findsNothing);
    expect(find.text('트레이너 리포트'), findsNothing);
  });

  testWidgets('누르면 리포트 목록으로 간다', (tester) async {
    await _pumpMy(tester, repository: FakeMemberCoachRepository());

    await tester.tap(find.byKey(_entry));
    await tester.pumpAndSettle();

    expect(find.text('리포트 목록'), findsOneWidget);
  });

  testWidgets('영어에서도 번역되어 있다', (tester) async {
    await _pumpMy(tester, repository: FakeMemberCoachRepository(), locale: 'en');

    expect(find.text('Trainer reports'), findsOneWidget);
    expect(find.text('Reports you received and feedback you sent'), findsOneWidget);
  });
}
