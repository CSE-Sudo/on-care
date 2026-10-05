/// MY 프로필·포인트 카드의 로딩·오류·재조회 상태. (#2853)
///
/// 예전에는 `myHealthStateProvider` 의 값만 넘겨 받아, 조회 중이거나 실패하면
/// 프로필은 "사용자"·빈 이메일, 포인트는 "—P" 로 그렸고 다시 시도가 없었다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/domain/entities/health_history.dart';
import 'package:oncare/features/my_health/domain/repositories/my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../benefits/fake_benefits_repository.dart';

const MyHealthState _state = MyHealthState(
  profile: UserProfile(name: '김민수', email: 'minsu@oncare.com'),
  activityPoints: 1240,
);

/// 응답마다 성공·실패·대기를 테스트가 정하는 대역.
class _ScriptedRepository implements MyHealthRepository {
  _ScriptedRepository();

  int calls = 0;

  /// 다음 응답들. 비면 [_state] 로 성공한다.
  final List<Object> script = <Object>[];

  @override
  Future<MyHealthState> fetchState() async {
    calls++;
    if (script.isEmpty) return _state;
    final Object next = script.removeAt(0);
    if (next is Completer<MyHealthState>) return next.future;
    if (next is MyHealthState) return next;
    throw next;
  }
}

void main() {
  late _ScriptedRepository repo;

  setUp(() => repo = _ScriptedRepository());

  Future<void> pumpMy(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gymRepositoryProvider.overrideWithValue(MockGymRepository()),
          myHealthRepositoryProvider.overrideWithValue(repo),
          benefitsRepositoryProvider.overrideWithValue(
            FakeBenefitsRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MyHealthPage(),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MyHealthPage)));

  Finder banner() => find.byKey(const Key('pointsBanner'));

  group('첫 조회 중', () {
    testWidgets('가짜 이름·잔액 대신 빈 자리와 스피너를 그린다', (WidgetTester tester) async {
      final Completer<MyHealthState> pending = Completer<MyHealthState>();
      repo.script.add(pending);
      await pumpMy(tester, settle: false);
      await tester.pump();

      expect(find.byKey(const Key('profileLoading')), findsOneWidget);
      expect(find.text('사용자'), findsNothing);
      expect(find.text('—P'), findsNothing);
      // 포인트 카드 자리는 지키되 숫자는 비어 있다.
      expect(banner(), findsOneWidget);
      expect(
        find.descendant(of: banner(), matching: find.text('')),
        findsOneWidget,
      );

      pending.complete(_state);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profileLoading')), findsNothing);
      expect(find.text('김민수'), findsOneWidget);
      expect(find.text('1,240P'), findsOneWidget);
    });
  });

  group('첫 조회 실패', () {
    testWidgets('프로필·포인트 자리에 오류와 다시 시도를 둔다', (WidgetTester tester) async {
      repo.script.add(StateError('network down'));
      await pumpMy(tester);

      expect(find.text('내 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('포인트 잔액을 불러오지 못했어요'), findsOneWidget);
      expect(find.byKey(const Key('profileRetry')), findsOneWidget);
      expect(find.byKey(const Key('pointsRetry')), findsOneWidget);
      expect(find.text('사용자'), findsNothing);
      expect(find.text('—P'), findsNothing);
      // 잔액을 모르는 동안에는 사용처로 들어가는 카드가 없다 — 교환을 시작할 수 없다.
      expect(banner(), findsNothing);
      // 동기화 코드는 따로 받으므로 실패와 상관없이 남는다.
      expect(find.text('트레이너와 데이터 동기화'), findsOneWidget);
    });

    testWidgets('프로필의 다시 시도를 누르면 다시 읽고 이름·잔액이 보인다', (
      WidgetTester tester,
    ) async {
      repo.script.add(StateError('network down'));
      await pumpMy(tester);
      expect(repo.calls, 1);

      await tester.tap(find.byKey(const Key('profileRetry')));
      await tester.pumpAndSettle();

      expect(repo.calls, 2);
      expect(find.text('김민수'), findsOneWidget);
      expect(find.text('minsu@oncare.com'), findsOneWidget);
      expect(find.text('1,240P'), findsOneWidget);
      expect(find.byKey(const Key('pointsLoadFailed')), findsNothing);
    });

    testWidgets('포인트의 다시 시도도 같은 정보를 다시 읽는다', (WidgetTester tester) async {
      repo.script.add(StateError('network down'));
      await pumpMy(tester);

      await tester.tap(find.byKey(const Key('pointsRetry')));
      await tester.pumpAndSettle();

      expect(repo.calls, 2);
      expect(banner(), findsOneWidget);
      expect(find.text('1,240P'), findsOneWidget);
    });

    testWidgets('다시 시도하는 동안에는 오류 대신 로딩 모양이다', (WidgetTester tester) async {
      final Completer<MyHealthState> pending = Completer<MyHealthState>();
      repo.script
        ..add(StateError('network down'))
        ..add(pending);
      await pumpMy(tester);

      await tester.tap(find.byKey(const Key('profileRetry')));
      await tester.pump();

      expect(find.byKey(const Key('profileLoading')), findsOneWidget);
      expect(find.byKey(const Key('profileLoadFailed')), findsNothing);
      expect(find.byKey(const Key('pointsLoadFailed')), findsNothing);

      pending.complete(_state);
      await tester.pumpAndSettle();
      expect(find.text('김민수'), findsOneWidget);
    });

    testWidgets('다시 시도가 또 실패하면 오류가 그대로 남는다', (WidgetTester tester) async {
      repo.script
        ..add(StateError('network down'))
        ..add(StateError('still down'));
      await pumpMy(tester);

      await tester.tap(find.byKey(const Key('profileRetry')));
      await tester.pumpAndSettle();

      expect(repo.calls, 2);
      expect(find.byKey(const Key('profileRetry')), findsOneWidget);
      expect(find.byKey(const Key('pointsRetry')), findsOneWidget);
    });
  });

  group('재조회', () {
    testWidgets('재조회 중에는 이전 이름·잔액을 그대로 보여 준다', (WidgetTester tester) async {
      await pumpMy(tester);
      expect(find.text('김민수'), findsOneWidget);

      final Completer<MyHealthState> pending = Completer<MyHealthState>();
      repo.script.add(pending);
      container(tester).invalidate(myHealthStateProvider);
      await tester.pump();

      expect(find.text('김민수'), findsOneWidget);
      expect(find.text('1,240P'), findsOneWidget);
      expect(find.byKey(const Key('profileLoading')), findsNothing);

      pending.complete(_state);
      await tester.pumpAndSettle();
    });

    testWidgets('이전 값이 있으면 재조회가 실패해도 오류 대신 그 값을 둔다', (
      WidgetTester tester,
    ) async {
      await pumpMy(tester);

      repo.script.add(StateError('network down'));
      container(tester).invalidate(myHealthStateProvider);
      await tester.pumpAndSettle();

      expect(find.text('김민수'), findsOneWidget);
      expect(find.text('1,240P'), findsOneWidget);
      expect(find.byKey(const Key('profileLoadFailed')), findsNothing);
      expect(find.byKey(const Key('pointsLoadFailed')), findsNothing);
    });
  });

  testWidgets('서버가 이름을 비워 보낸 경우에만 기본 이름을 쓴다', (WidgetTester tester) async {
    repo.script.add(
      const MyHealthState(
        profile: UserProfile(name: '', email: ''),
        activityPoints: 0,
      ),
    );
    await pumpMy(tester);

    expect(find.text('사용자'), findsOneWidget);
    expect(find.text('0P'), findsOneWidget);
  });
}
