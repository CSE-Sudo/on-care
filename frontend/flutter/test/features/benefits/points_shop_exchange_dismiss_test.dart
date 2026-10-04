/// 포인트 사용처에서 교환하는 동안 뒤로 가기로 떠나지 않고, 화면이 사라져도
/// 교환 뒤 MY 잔액을 다시 읽는다. (#3096)
///
/// 예전에는 교환 성공 뒤 `if (!mounted) return;` 이 갱신보다 앞에 있어, 교환
/// 중에 화면을 떠나면 MY 잔액(autoDispose 가 아님)이 옛 값으로 남았다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'fake_benefits_repository.dart';
import 'fake_challenge_repository.dart';

void main() {
  late FakeBenefitsRepository repo;
  late int healthBuilds;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    repo = FakeBenefitsRepository();
    healthBuilds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          benefitsRepositoryProvider.overrideWithValue(repo),
          challengeRepositoryProvider.overrideWithValue(
            FakeChallengeRepository(),
          ),
          // 다시 만들어졌는지만 센다 — 값은 끝나지 않는 Future 다.
          myHealthStateProvider.overrideWith((ref) {
            healthBuilds++;
            return Completer<MyHealthState>().future;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              // MY 탭이 잔액을 보고 있는 상태.
              ref.watch(myHealthStateProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const PointsBenefitsPage(points: 9000),
                    ),
                  ),
                  child: const Text('사용처'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('사용처'));
    await tester.pumpAndSettle();
  }

  /// 락커 쿠폰을 교환한다 — 교환 요청은 [exchangeGate] 에 걸린 채 남는다.
  Future<void> startExchange(WidgetTester tester) async {
    repo.exchangeGate = Completer<void>();
    await tester.tap(
      find.byKey(const ValueKey<String>('shop-exchange-locker_month')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AppDialog), matching: find.text('교환')),
    );
    await tester.pump();
  }

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('교환 중에는 뒤로 가기로 떠나지 않는다', (WidgetTester tester) async {
    await pump(tester);
    await startExchange(tester);

    await tester.binding.handlePopRoute();
    // 교환 카드의 진행 표시가 돌고 있어 settle 하지 않고 전환 시간만 흘린다.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('pointsBenefitsPage')), findsOneWidget);

    repo.exchangeGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.exchanged, <String>['locker_month']);
    expect(find.text('교환했어요'), findsOneWidget);
    // 끝난 뒤에는 떠날 수 있다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pointsBenefitsPage')), findsNothing);

    await drainToast(tester);
  });

  testWidgets('교환 중에 화면이 사라져도 교환 뒤 MY 잔액을 다시 읽는다', (WidgetTester tester) async {
    await pump(tester);
    expect(healthBuilds, 1);
    await startExchange(tester);

    // 뒤로 가기는 막혀 있다 — 앱이 화면을 직접 치운 경우(로그아웃·딥링크 등).
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pointsBenefitsPage')), findsNothing);

    repo.exchangeGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.exchanged, <String>['locker_month']);
    expect(healthBuilds, 2);
  });
}
