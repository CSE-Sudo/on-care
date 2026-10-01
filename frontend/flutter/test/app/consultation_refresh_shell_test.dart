/// 미읽음 알림 수가 늘면 하단 탭 틀이 상담 목록을 다시 받는다 (#2067).
///
/// 트레이너의 승인·거절과 요청 만료는 알림으로 먼저 온다. 알림 배지는 15초마다
/// 따라오는데 상담 목록은 처음 한 번만 받아서, 알림은 "반려되었어요" 인데 상담
/// 화면은 "확인 대기" 로 남았다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/fake_dashboard_repository.dart';
import '../helpers/fake_diet_repository.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 목록을 몇 번 받았는지만 센다.
class _CountingRepository implements ConsultationRepository {
  int fetchCalls = 0;

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async {
    fetchCalls++;
    return const <ConsultationRequest>[];
  }

  @override
  Future<String> create(ConsultationDraft draft) async => '';

  @override
  Future<void> cancel(String consultationId) async {}

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

void main() {
  late StreamController<int> unread;
  late _CountingRepository consultations;

  Future<void> pumpShell(WidgetTester tester) async {
    final AppDatabase exerciseDb = await seededDemoDatabase(tester);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 브로드캐스트다 — 셸이 미리 불러오는 알림 목록(#2688)이 끝나면 미읽음
    // provider 를 무효화해 스트림을 다시 구독한다. 한 번만 구독할 수 있는
    // 스트림이면 그 뒤로 보낸 값이 닿지 않는다. 운동이 실제 데모 경로(drift)를
    // 타면서 그 조회가 실제로 끝나게 됐다(#2724).
    unread = StreamController<int>.broadcast();
    addTearDown(unread.close);
    consultations = _CountingRepository();

    final GoRouter router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

    final FakeDietRepository diet = FakeDietRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
          dietRepositoryProvider.overrideWithValue(diet as DietRepository),
          // 운동은 앱의 데모와 같은 경로(로컬 목업 API + drift)로 돈다(#2724).
          ...demoExerciseOverrides(exerciseDb),
          dashboardRepositoryProvider.overrideWithValue(
            FakeDashboardRepository(diet) as DashboardRepository,
          ),
          consultationRepositoryProvider.overrideWithValue(consultations),
          notificationUnreadProvider.overrideWith((_) => unread.stream),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, int count) async {
    unread.add(count);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('미읽음 수가 늘면 상담 목록을 다시 받는다', (WidgetTester tester) async {
    await pumpShell(tester);
    await emit(tester, 1); // 첫 값 — 새로 온 것이 아니다.
    final int before = consultations.fetchCalls;

    await emit(tester, 2);

    expect(consultations.fetchCalls, greaterThan(before));
  });

  testWidgets('첫 값과 줄어드는 값에는 다시 받지 않는다', (WidgetTester tester) async {
    await pumpShell(tester);
    final int initial = consultations.fetchCalls;

    await emit(tester, 3); // 첫 값
    expect(consultations.fetchCalls, initial);

    await emit(tester, 1); // 읽음 처리로 줄었다
    await emit(tester, 1); // 그대로
    expect(consultations.fetchCalls, initial);
  });
}
