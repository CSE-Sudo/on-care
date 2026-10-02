/// 개인운동 조회 실패는 "없음" 과 구분된다. (#2891)
///
/// 마무리된 PT 에 보내지 않은 개인운동이 남아 있어도 조회가 한 번 실패해
/// 갈래째 사라지면, 트레이너는 보낼 것이 없다고 읽어 회원에게 루틴이 영영
/// 가지 않을 수 있다. 일정 상세와 코칭 탭의 미전송 안내 모두 실패를 한 줄로
/// 알리고 다시 시도할 수 있게 한다.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_personal_routines.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

const RoutineExercise _walking = RoutineExercise(
  name: '저강도 걷기',
  minutes: 30,
  type: '유산소',
);

/// 개인운동 조회만 손으로 움직이는 데모 저장소.
class _FlakyRoutinesRepository extends DriftScheduleRepository {
  _FlakyRoutinesRepository(super.db);

  /// 일정의 개인운동 조회가 실패하는가.
  bool failScheduled = true;

  /// 회원의 미전송 개인운동 조회가 실패하는가.
  bool failUnsent = true;

  int scheduledReads = 0;
  int unsentReads = 0;

  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async {
    scheduledReads++;
    if (failScheduled) throw const NetworkError();
    return const <SessionRoutine>[
      SessionRoutine(exercise: _walking, sent: false),
    ];
  }

  @override
  Future<List<UnsentRoutine>> fetchUnsentRoutinesFor(String clientId) async {
    unsentReads++;
    if (failUnsent) throw const ServerError(statusCode: 503);
    return const <UnsentRoutine>[
      UnsentRoutine(
        exercise: _walking,
        scheduleId: 'sched-1',
        scheduleDate: '2026-08-19',
      ),
    ];
  }
}

void main() {
  group('일정 상세의 개인운동 갈래', () {
    late AppDatabase db;
    late _FlakyRoutinesRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = _FlakyRoutinesRepository(db);
      addTearDown(db.close);
    });

    Future<List<List<RoutineExercise>?>> pump(
      WidgetTester tester, {
      Locale locale = const Locale('ko'),
    }) async {
      final reported = <List<RoutineExercise>?>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SessionPersonalRoutines(
                sessionId: 'sched-1',
                finished: true,
                showEmpty: true,
                onChanged: reported.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return reported;
    }

    testWidgets('실패하면 숨기지 않고 실패 안내와 재시도를 보인다', (tester) async {
      final reported = await pump(tester);

      expect(
        find.byKey(const ValueKey<String>('session-personal-routines-error')),
        findsOneWidget,
      );
      expect(find.text('개인운동을 불러오지 못했어요'), findsOneWidget);
      // "없음" 으로 읽히지 않는다.
      expect(
        find.byKey(const ValueKey<String>('session-no-personal-routines')),
        findsNothing,
      );
      // 부르는 쪽에는 "모름" 이다 — 보낼 것이 없다고 정하지 않는다.
      expect(reported.last, isNull);
    });

    testWidgets('다시 시도하면 목록을 그린다', (tester) async {
      final reported = await pump(tester);
      repo.failScheduled = false;

      await tester.tap(
        find.byKey(const ValueKey<String>('session-personal-routines-retry')),
      );
      await tester.pump();
      await tester.pump();

      expect(repo.scheduledReads, 2);
      expect(
        find.byKey(const ValueKey<String>('session-personal-routines-error')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('session-personal-routines')),
        findsOneWidget,
      );
      expect(find.textContaining('저강도 걷기'), findsOneWidget);
      expect(reported.last, const <RoutineExercise>[_walking]);
    });

    testWidgets('정상 조회면 지금처럼 목록이다', (tester) async {
      repo.failScheduled = false;
      await pump(tester);

      expect(
        find.byKey(const ValueKey<String>('session-personal-routines-error')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('session-personal-routines')),
        findsOneWidget,
      );
    });

    testWidgets('영어 화면은 영어 안내다', (tester) async {
      await pump(tester, locale: const Locale('en'));

      expect(find.text("Couldn't load personal exercises"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('코칭 탭의 미전송 안내', () {
    late _FlakyRoutinesRepository repo;

    Future<void> openCoaching(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.coachingFor('seed-client-1'),
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith((ref) {
            repo = _FlakyRoutinesRepository(ref.watch(appDatabaseProvider))
              ..failScheduled = false;
            return repo;
          }),
        ],
      );
    }

    testWidgets('조회가 실패하면 안내가 빠지지 않고 실패 한 줄과 재시도다', (tester) async {
      await openCoaching(tester);

      final Finder error = find.byKey(
        const ValueKey<String>('coach-unsent-routines-error'),
      );
      expect(error, findsOneWidget);
      expect(find.text('개인운동을 불러오지 못했어요'), findsOneWidget);

      final Finder retry = find.byKey(
        const ValueKey<String>('coach-unsent-routines-retry'),
      );
      await tester.ensureVisible(retry);
      await tester.pump();
      final int before = repo.unsentReads;
      repo.failUnsent = false;
      await tester.tap(retry);
      await settle(tester);

      expect(repo.unsentReads, greaterThan(before));
      expect(error, findsNothing);
      expect(
        find.byKey(const ValueKey<String>('coach-unsent-routines')),
        findsOneWidget,
      );
      expect(find.text('아직 보내지 않은 개인운동 1개'), findsOneWidget);
    });
  });
}
