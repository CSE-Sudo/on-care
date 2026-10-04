import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppButton;

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// `개인운동만` 보조 전송 흐름의 실패·시간 경과 처리 (#2896).
///
/// - PT 후보를 읽지 못하면 박스에서 다시 읽을 수 있다.
/// - 시작일이 지났으면 그 날짜로 보내지 않고 오늘로 당긴다.
/// - PT 에 붙이기를 서버가 거절하면 그 사유를, 붙은 개인운동을 읽지 못하면
///   쓰기 실패와 다른 문구를 보인다.
class _StaticSuggestionRepository
    implements TrainerRoutineSuggestionRepository {
  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async =>
      const <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'sug-1',
          name: '가벼운 인터벌 러닝',
          minutes: 30,
          type: '유산소',
          reason: '숨이 차면 속도를 낮추세요',
        ),
      ];

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) async {}

  @override
  Future<void> dismiss(String suggestionId) async {}
}

/// 데모 저장소 위에 PT 후보 조회·붙은 개인운동 읽기·붙이기 실패를 얹는다.
class _FlakyScheduleRepository extends DriftScheduleRepository {
  _FlakyScheduleRepository(super.db);

  List<ScheduleSession> candidates = const <ScheduleSession>[];
  bool failSessions = false;
  int sessionReads = 0;
  bool failRead = false;
  AppError? updateFailure;
  final List<String> updatedFor = <String>[];

  /// 다음 붙이기를 이 완료자가 끝낼 때까지 붙잡는다.
  Completer<void>? holdUpdate;

  @override
  Stream<List<ScheduleSession>> watchClientSessions(ScheduleClientKey client) {
    sessionReads++;
    if (failSessions) {
      return Stream<List<ScheduleSession>>.error(
        const NetworkError(message: 'offline'),
      );
    }
    return Stream<List<ScheduleSession>>.value(candidates);
  }

  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async {
    if (failRead) throw const NetworkError(message: 'offline');
    return const <SessionRoutine>[];
  }

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    final Completer<void>? hold = holdUpdate;
    holdUpdate = null;
    if (hold != null) await hold.future;
    if (updateFailure case final AppError error) throw error;
    updatedFor.add(id);
  }
}

/// 오늘(2026-08-20) 아직 보내지 않은 PT.
const ScheduleSession _todayPt = ScheduleSession(
  id: 'today-pt',
  date: '2026-08-20',
  time: '18:00',
  clientId: 'seed-client-1',
  clientName: '김민수',
  type: '1:1 PT',
  durationMinutes: 50,
  status: ScheduleStatus.upcoming,
  note: '',
  program: <ProgramItem>[ProgramItem(name: '스쿼트')],
);

Future<_FlakyScheduleRepository> _open(
  WidgetTester tester, {
  String? at,
  List<ScheduleSession> candidates = const <ScheduleSession>[],
  bool failSessions = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _FlakyScheduleRepository repo;
  await pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: at ?? AppRoutes.coachingFor('seed-client-1'),
    seedClock: kMidWeekKst,
    extraOverrides: [
      trainerRoutineSuggestionRepositoryProvider.overrideWithValue(
        _StaticSuggestionRepository(),
      ),
      scheduleRepositoryProvider.overrideWith((ref) {
        repo = _FlakyScheduleRepository(ref.watch(appDatabaseProvider))
          ..candidates = candidates
          ..failSessions = failSessions;
        return repo;
      }),
    ],
  );
  return repo;
}

Future<void> _tapCentered(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 위저드에서 PT 를 건너뛰고 개인운동 단계를 마친다.
Future<void> _composeRoutineOnly(WidgetTester tester) async {
  await _tapCentered(
    tester,
    find.byKey(const ValueKey<String>('skip-pt-program')),
  );
  await _completePersonalStep(tester);
}

Future<void> _completePersonalStep(WidgetTester tester) => _tapCentered(
  tester,
  find.byKey(const ValueKey<String>('complete-personal-routines')),
);

final Finder _send = find.byKey(
  const ValueKey<String>('personal-routine-send'),
);

Future<void> _tapSend(WidgetTester tester) => _tapCentered(tester, _send);

String _startDateLabel(WidgetTester tester) => tester
    .widget<AppButton>(
      find.byKey(const ValueKey<String>('personal-routine-start-date')),
    )
    .label;

void main() {
  group('PT 후보 조회 실패 (#2896)', () {
    testWidgets('읽지 못하면 박스에 다시 시도가 서고, 성공하면 보내기가 풀린다', (tester) async {
      final repo = await _open(tester, failSessions: true);
      await _composeRoutineOnly(tester);

      expect(
        find.byKey(const ValueKey<String>('personal-routine-target-failed')),
        findsOneWidget,
      );
      expect(find.text('PT 일정을 불러오지 못했어요'), findsOneWidget);
      expect(tester.widget<AppButton>(_send).onPressed, isNull);

      repo.failSessions = false;
      final int readsBefore = repo.sessionReads;
      await _tapCentered(
        tester,
        find.byKey(const ValueKey<String>('personal-routine-target-retry')),
      );

      expect(repo.sessionReads, readsBefore + 1);
      expect(
        find.byKey(const ValueKey<String>('personal-routine-target-failed')),
        findsNothing,
      );
      expect(tester.widget<AppButton>(_send).onPressed, isNotNull);
    });

    testWidgets('다시 읽어도 실패하면 다시 시도가 그대로 남는다', (tester) async {
      await _open(tester, failSessions: true);
      await _composeRoutineOnly(tester);

      await _tapCentered(
        tester,
        find.byKey(const ValueKey<String>('personal-routine-target-retry')),
      );

      expect(
        find.byKey(const ValueKey<String>('personal-routine-target-retry')),
        findsOneWidget,
      );
      expect(tester.widget<AppButton>(_send).onPressed, isNull);
    });

    testWidgets('정상 조회면 실패 줄이 서지 않는다', (tester) async {
      await _open(tester);
      await _composeRoutineOnly(tester);

      expect(
        find.byKey(const ValueKey<String>('personal-routine-target-failed')),
        findsNothing,
      );
      expect(tester.widget<AppButton>(_send).onPressed, isNotNull);
    });
  });

  group('지난 시작일 (#2896)', () {
    testWidgets('자정을 넘긴 뒤 보내면 확인창 없이 오늘로 당기고 알린다', (tester) async {
      await _open(tester);
      await _composeRoutineOnly(tester);
      expect(_startDateLabel(tester), '2026-08-20');

      debugNowKstOverride = () => DateTime(2026, 8, 21, 0, 5);
      await _tapSend(tester);

      expect(find.text('시작일이 지나 오늘로 바꿨어요. 확인하고 다시 보내 주세요'), findsOneWidget);
      expect(_startDateLabel(tester), '2026-08-21');
      // 지난 날짜가 적힌 확인창은 뜨지 않는다.
      expect(find.textContaining('2026-08-20'), findsNothing);
    });

    testWidgets('확인창을 띄운 채 자정을 넘기면 그 날짜로 보내지 않는다', (tester) async {
      await _open(tester);
      await _composeRoutineOnly(tester);
      await _tapSend(tester);
      expect(find.textContaining('2026-08-20'), findsWidgets);

      debugNowKstOverride = () => DateTime(2026, 8, 21, 0, 5);
      await tester.tap(find.text('보내기').last);
      await tester.pumpAndSettle();

      expect(find.text('시작일이 지나 오늘로 바꿨어요. 확인하고 다시 보내 주세요'), findsOneWidget);
      expect(_startDateLabel(tester), '2026-08-21');
      expect(tester.widget<AppButton>(_send).label, '회원에게 보내기');
    });

    testWidgets('스케줄에서 온 PT 가 그사이 보내져 지난 날만 남으면 오늘로 당긴다', (tester) async {
      await _open(
        tester,
        at: AppRoutes.coachingAttach(
          'seed-client-1',
          sessionId: 'already-sent',
          date: '2026-08-19',
          requestId: 'r-1',
        ),
      );
      await _completePersonalStep(tester);
      expect(_startDateLabel(tester), '2026-08-19');

      await _tapSend(tester);

      expect(find.text('시작일이 지나 오늘로 바꿨어요. 확인하고 다시 보내 주세요'), findsOneWidget);
      expect(_startDateLabel(tester), '2026-08-20');
    });

    testWidgets('시작일이 오늘이면 그대로 확인창이 뜬다', (tester) async {
      await _open(tester);
      await _composeRoutineOnly(tester);

      await _tapSend(tester);

      expect(find.text('시작일이 지나 오늘로 바꿨어요. 확인하고 다시 보내 주세요'), findsNothing);
      expect(find.textContaining('2026-08-20'), findsWidgets);
    });
  });

  group('PT 에 붙이기 실패 (#2896)', () {
    testWidgets('서버가 거절하면 그 사유를 보인다', (tester) async {
      final repo = await _open(
        tester,
        candidates: const <ScheduleSession>[_todayPt],
      );
      repo.updateFailure = const ServerError(
        statusCode: 409,
        message: '이미 회원에게 보낸 PT 입니다.',
      );
      await _composeRoutineOnly(tester);
      expect(tester.widget<AppButton>(_send).label, 'PT에 반영');

      await _tapSend(tester);

      expect(find.text('이미 회원에게 보낸 PT 입니다.'), findsOneWidget);
      expect(find.text('개인운동을 고치지 못했어요. 다시 시도해 주세요.'), findsNothing);
      expect(repo.updatedFor, isEmpty);
    });

    testWidgets('사유 없는 실패는 기본 문구로 남는다', (tester) async {
      final repo = await _open(
        tester,
        candidates: const <ScheduleSession>[_todayPt],
      );
      repo.updateFailure = const ServerError(statusCode: 500);
      await _composeRoutineOnly(tester);

      await _tapSend(tester);

      expect(find.text('개인운동을 고치지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    });

    testWidgets('붙은 개인운동을 읽지 못하면 쓰기 실패와 다른 문구다', (tester) async {
      final repo = await _open(
        tester,
        candidates: const <ScheduleSession>[_todayPt],
      );
      repo.failRead = true;
      await _composeRoutineOnly(tester);

      await _tapSend(tester);

      expect(find.text('붙어 있는 개인운동을 확인하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(find.text('개인운동을 고치지 못했어요. 다시 시도해 주세요.'), findsNothing);
      expect(repo.updatedFor, isEmpty);
    });

    testWidgets('지난 PT 에 붙이는 것은 날짜를 당기지 않는다', (tester) async {
      const ScheduleSession pastPt = ScheduleSession(
        id: 'past-pt',
        date: '2026-08-19',
        time: '18:00',
        clientId: 'seed-client-1',
        clientName: '김민수',
        type: '1:1 PT',
        durationMinutes: 50,
        status: ScheduleStatus.done,
        note: '',
        program: <ProgramItem>[ProgramItem(name: '스쿼트')],
      );
      final repo = await _open(
        tester,
        at: AppRoutes.coachingAttach(
          'seed-client-1',
          sessionId: pastPt.id,
          date: pastPt.date,
          requestId: 'r-1',
        ),
        candidates: const <ScheduleSession>[pastPt],
      );
      await _completePersonalStep(tester);
      expect(tester.widget<AppButton>(_send).label, 'PT에 반영');

      await _tapSend(tester);

      expect(find.text('시작일이 지나 오늘로 바꿨어요. 확인하고 다시 보내 주세요'), findsNothing);
      expect(repo.updatedFor, <String>['past-pt']);
    });
  });
  group('붙이기가 늦게 끝날 때 (#3101)', () {
    String attachRoute() => AppRoutes.coachingAttach(
      'seed-client-1',
      sessionId: _todayPt.id,
      date: _todayPt.date,
      requestId: 'r-3101',
    );

    Future<(_FlakyScheduleRepository, Completer<void>)> attachHeld(
      WidgetTester tester,
    ) async {
      final repo = await _open(
        tester,
        at: attachRoute(),
        candidates: const <ScheduleSession>[_todayPt],
      );
      await _completePersonalStep(tester);
      expect(tester.widget<AppButton>(_send).label, 'PT에 반영');
      final Completer<void> hold = Completer<void>();
      repo.holdUpdate = hold;
      await Scrollable.ensureVisible(tester.element(_send), alignment: 0.5);
      await tester.pump();
      await tester.tap(_send);
      await tester.pump();
      return (repo, hold);
    }

    testWidgets('그사이 다른 회원을 골랐으면 스케줄로 끌고 가지 않는다', (tester) async {
      final (repo, hold) = await attachHeld(tester);

      // 붙이는 중이라 묻지 않고 바로 옮긴다.
      await _tapCentered(
        tester,
        find.byKey(const ValueKey<String>('program-client-seed-client-2')),
      );
      expect(
        Uri.parse(currentLocation(tester)).queryParameters['client'],
        'seed-client-2',
      );

      hold.complete();
      await settle(tester);

      expect(repo.updatedFor, <String>['today-pt']);
      expect(find.text('개인운동을 붙였어요.'), findsOneWidget);
      final Uri location = Uri.parse(currentLocation(tester));
      expect(location.path, AppRoutes.coaching);
      expect(location.queryParameters['client'], 'seed-client-2');
    });

    testWidgets('그 회원 그대로면 지금처럼 그 일정으로 돌아간다', (tester) async {
      final (repo, hold) = await attachHeld(tester);

      hold.complete();
      await settle(tester);

      expect(repo.updatedFor, <String>['today-pt']);
      expect(
        currentLocation(tester),
        AppRoutes.scheduleAt(date: _todayPt.date, sessionId: _todayPt.id),
      );
    });
  });
}
