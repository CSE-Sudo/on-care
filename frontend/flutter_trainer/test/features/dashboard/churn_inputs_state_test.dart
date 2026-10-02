/// 이탈 위험·활동 피드백은 입력이 모두 준비됐을 때만 숫자를 낸다. (#2891)
///
/// 예전에는 최근 세션 조회가 실패하거나 아직 오지 않으면 빈 목록으로 계산해,
/// 모든 회원이 "최근 트레이너 피드백 없음" 이 되어 이탈 위험 인원이 부풀려진
/// 채 빨간색으로 떴다. 이제는 로딩 중엔 자리 표시, 실패하면 확인할 수 없다는
/// 문구와 재시도다.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 이탈 위험이 읽는 30일 구간 조회만 손으로 움직이는 데모 저장소 — 나머지
/// 조회(오늘 일정 등)는 데모 그대로다.
class _ScriptedRecentRepository extends DriftScheduleRepository {
  _ScriptedRecentRepository(super.db);

  /// 다음 30일 구간 조회가 돌려줄 것. null 이면 데모 저장소 그대로다.
  Stream<List<ScheduleSession>> Function()? recent;

  int recentReads = 0;

  static bool _isChurnWindow(String from, String to) =>
      DateTime.parse(to).difference(DateTime.parse(from)).inDays >= 28;

  @override
  Stream<List<ScheduleSession>> watchRange(String fromDate, String toDate) {
    final script = recent;
    if (_isChurnWindow(fromDate, toDate)) {
      recentReads++;
      if (script != null) return script();
    }
    return super.watchRange(fromDate, toDate);
  }
}

typedef _Inputs = ({
  List<TrainerClient> clients,
  List<ScheduleSession> recentSessions,
});

void main() {
  group('combineChurnInputs', () {
    final List<TrainerClient> roster = <TrainerClient>[makeClient()];
    const List<ScheduleSession> none = <ScheduleSession>[];

    test('세션을 아직 못 받았으면 로딩이다 — 빈 목록으로 세지 않는다', () {
      final _Inputs? value = combineChurnInputs(
        AsyncData<List<TrainerClient>>(roster),
        const AsyncLoading<List<ScheduleSession>>(),
      ).valueOrNull;
      expect(value, isNull);
      expect(
        combineChurnInputs(
          AsyncData<List<TrainerClient>>(roster),
          const AsyncLoading<List<ScheduleSession>>(),
        ).isLoading,
        isTrue,
      );
    });

    test('로스터를 아직 못 받았어도 로딩이다', () {
      expect(
        combineChurnInputs(
          const AsyncLoading<List<TrainerClient>>(),
          const AsyncData<List<ScheduleSession>>(none),
        ).isLoading,
        isTrue,
      );
    });

    test('세션 조회 실패는 실패다', () {
      final combined = combineChurnInputs(
        AsyncData<List<TrainerClient>>(roster),
        const AsyncError<List<ScheduleSession>>(
          NetworkError(),
          StackTrace.empty,
        ),
      );
      expect(combined.hasError, isTrue);
      expect(combined.error, isA<NetworkError>());
      expect(combined.hasValue, isFalse);
    });

    test('로스터 조회 실패도 실패다', () {
      expect(
        combineChurnInputs(
          const AsyncError<List<TrainerClient>>(
            ServerError(statusCode: 500),
            StackTrace.empty,
          ),
          const AsyncData<List<ScheduleSession>>(none),
        ).hasError,
        isTrue,
      );
    });

    test('실패 뒤 다시 읽는 동안은 로딩이다', () {
      final AsyncValue<List<ScheduleSession>> retrying =
          const AsyncLoading<List<ScheduleSession>>().copyWithPrevious(
            const AsyncError<List<ScheduleSession>>(
              NetworkError(),
              StackTrace.empty,
            ),
          );
      final combined = combineChurnInputs(
        AsyncData<List<TrainerClient>>(roster),
        retrying,
      );
      expect(combined.isLoading, isTrue);
      expect(combined.hasError, isFalse);
    });

    test('둘 다 있으면 값이다', () {
      final combined = combineChurnInputs(
        AsyncData<List<TrainerClient>>(roster),
        const AsyncData<List<ScheduleSession>>(none),
      );
      expect(combined.requireValue.clients, roster);
      expect(combined.requireValue.recentSessions, isEmpty);
    });
  });

  group('대시보드 provider', () {
    late AppDatabase db;
    late _ScriptedRecentRepository repo;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = _ScriptedRecentRepository(db);
      container = ProviderContainer(
        overrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
              makeClient(),
            ]),
          ),
          scheduleRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
    });

    /// 대시보드가 화면에 있는 것처럼 두 provider 를 구독한다.
    void listen() {
      container
        ..listen(dashboardChurnRiskProvider, (_, _) {})
        ..listen(dashboardActivityFeedbackProvider, (_, _) {});
    }

    test('세션이 오기 전에는 이탈 위험·활동 피드백을 세지 않는다', () async {
      final pending = Completer<List<ScheduleSession>>();
      repo.recent = () =>
          Stream<List<ScheduleSession>>.fromFuture(pending.future);
      listen();
      await pumpEventQueue();

      expect(container.read(dashboardChurnRiskProvider).hasValue, isFalse);
      expect(container.read(dashboardChurnRiskProvider).isLoading, isTrue);
      expect(
        container.read(dashboardActivityFeedbackProvider).hasValue,
        isFalse,
      );

      pending.complete(const <ScheduleSession>[]);
      await pumpEventQueue();
      expect(container.read(dashboardChurnRiskProvider).hasValue, isTrue);
    });

    test('세션 조회가 실패하면 실패 상태이고, 재시도하면 다시 읽는다', () async {
      repo.recent = () =>
          Stream<List<ScheduleSession>>.error(const NetworkError());
      listen();
      await pumpEventQueue();

      final failed = container.read(dashboardChurnRiskProvider);
      expect(failed.hasError, isTrue);
      expect(failed.hasValue, isFalse);
      expect(
        container.read(dashboardActivityFeedbackProvider).hasError,
        isTrue,
      );

      final int before = repo.recentReads;
      repo.recent = () =>
          Stream<List<ScheduleSession>>.value(const <ScheduleSession>[]);
      retryChurnInputs(container.invalidate);
      await pumpEventQueue();

      expect(repo.recentReads, greaterThan(before));
      expect(container.read(dashboardChurnRiskProvider).hasValue, isTrue);
      expect(
        container.read(dashboardActivityFeedbackProvider).hasValue,
        isTrue,
      );
    });
  });

  group('대시보드 이탈 위험 KPI 카드', () {
    late _ScriptedRecentRepository repo;

    Future<void> openDashboard(
      WidgetTester tester, {
      required Stream<List<ScheduleSession>> Function() recent,
      Locale locale = const Locale('ko'),
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
        locale: locale,
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith((ref) {
            repo = _ScriptedRecentRepository(ref.watch(appDatabaseProvider))
              ..recent = recent;
            return repo;
          }),
        ],
      );
    }

    AppStatCard churnCard(WidgetTester tester) => tester.widget<AppStatCard>(
      find.byKey(const ValueKey<String>('dashboard-churn-kpi')),
    );

    testWidgets('세션을 읽는 동안에는 숫자 대신 자리 표시다', (tester) async {
      final pending = Completer<List<ScheduleSession>>();
      await openDashboard(
        tester,
        recent: () => Stream<List<ScheduleSession>>.fromFuture(pending.future),
      );

      final card = churnCard(tester);
      expect(card.value, '–');
      expect(card.caption, '최근 세션 확인 중');
      expect(card.toneColor, isNull, reason: '확정 전에는 빨강·초록을 칠하지 않는다');
      expect(card.onTap, isNull);
      expect(find.text(keepWords('최근 세션을 확인하고 있어요.')), findsOneWidget);

      pending.complete(const <ScheduleSession>[]);
      await settle(tester);
      expect(churnCard(tester).value, isNot('–'));
    });

    testWidgets('세션 조회가 실패하면 확인할 수 없음과 재시도다', (tester) async {
      var fail = true;
      await openDashboard(
        tester,
        recent: () => fail
            ? Stream<List<ScheduleSession>>.error(const NetworkError())
            : Stream<List<ScheduleSession>>.value(const <ScheduleSession>[]),
      );

      final card = churnCard(tester);
      expect(card.value, '–');
      expect(card.caption, '확인할 수 없음 · 눌러서 다시 시도');
      expect(card.toneColor, isNull);
      expect(
        find.textContaining(keepWords('활동 피드백을 확인할 수 없어요')),
        findsOneWidget,
        reason: '활동 피드백도 "담당 회원 없음" 으로 읽히지 않는다',
      );

      fail = false;
      final int before = repo.recentReads;
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard-churn-kpi')),
      );
      await settle(tester);

      expect(repo.recentReads, greaterThan(before));
      expect(churnCard(tester).value, isNot('–'));
      expect(churnCard(tester).toneColor, isNotNull);
    });

    testWidgets('영어 화면은 영어 문구다', (tester) async {
      await openDashboard(
        tester,
        locale: const Locale('en'),
        recent: () => Stream<List<ScheduleSession>>.error(const NetworkError()),
      );

      expect(churnCard(tester).caption, 'Unavailable · Tap to retry');
    });

    testWidgets('정상 조회면 지금처럼 숫자를 그린다', (tester) async {
      await openDashboard(
        tester,
        recent: () =>
            Stream<List<ScheduleSession>>.value(const <ScheduleSession>[]),
      );

      final card = churnCard(tester);
      expect(int.tryParse(card.value), isNotNull);
      expect(card.onTap, isNotNull);
    });
  });
}
