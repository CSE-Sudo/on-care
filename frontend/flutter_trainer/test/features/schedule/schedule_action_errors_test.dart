/// 스케줄 동작 실패 토스트 — 서버 사유와 동작별 문구. (#2888)
///
/// 취소·노쇼·개인운동 전송·수정·건너뛰기·프로그램 전송이 실패하면 서버가 준
/// 사유(이미 다른 기기에서 마무리됨, 시작 전이라 노쇼 불가 등)를 보인다. 사유가
/// 없으면 동작별 기존 문구다. 상태가 그새 바뀐 409 는 그 주를 다시 읽는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/schedule_action_error.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 데모 저장소 위에 개인운동을 얹고, 고른 동작만 실패시킨다.
class _FailingRepository extends DriftScheduleRepository {
  _FailingRepository(super.db, {required this.attached});

  final List<RoutineExercise> attached;

  Object? cancelError;
  Object? noShowError;
  Object? sendRoutinesError;
  Object? updateRoutinesError;
  Object? dismissError;
  Object? sendProgramError;

  /// 주간 조회를 몇 번 열었나 — 409 뒤 다시 읽는지 본다.
  int rangeReads = 0;

  @override
  Stream<List<ScheduleSession>> watchRange(String fromDate, String toDate) {
    rangeReads++;
    return super.watchRange(fromDate, toDate);
  }

  @override
  Future<List<SessionRoutine>> fetchScheduledRoutines(String id) async =>
      <SessionRoutine>[
        for (final RoutineExercise e in attached)
          SessionRoutine(exercise: e, sent: false),
      ];

  @override
  Future<void> cancelSession(
    String id, {
    required String source,
    String reason = '',
  }) async {
    final Object? error = cancelError;
    if (error != null) throw error;
    await super.cancelSession(id, source: source, reason: reason);
  }

  @override
  Future<void> markNoShow(String id) async {
    final Object? error = noShowError;
    if (error != null) throw error;
    await super.markNoShow(id);
  }

  @override
  Future<void> sendScheduledRoutines(
    String id, {
    List<RoutineExercise>? items,
  }) async {
    final Object? error = sendRoutinesError;
    if (error != null) throw error;
  }

  @override
  Future<void> updateScheduledRoutines(
    String id,
    List<RoutineExercise> items,
  ) async {
    final Object? error = updateRoutinesError;
    if (error != null) throw error;
  }

  @override
  Future<void> dismissScheduledRoutines(String id) async {
    final Object? error = dismissError;
    if (error != null) throw error;
  }

  @override
  Future<void> sendProgram(String id, {String? clientRequestId}) async {
    final Object? error = sendProgramError;
    if (error != null) throw error;
    await super.sendProgram(id, clientRequestId: clientRequestId);
  }
}

const RoutineExercise _walking = RoutineExercise(
  name: '저강도 걷기',
  minutes: 30,
  type: '유산소',
);

void main() {
  group('scheduleActionErrorMessage', () {
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    test('서버 사유가 있으면 그것이다', () {
      expect(
        scheduleActionErrorMessage(
          ko,
          const ValidationError(message: '빈 슬롯은 취소할 수 없습니다'),
          ko.schedCancelFailed,
        ),
        '빈 슬롯은 취소할 수 없습니다',
      );
    });

    test('연결 오류·5xx 는 원인별 안내다', () {
      expect(
        scheduleActionErrorMessage(
          ko,
          const NetworkError(),
          ko.schedCancelFailed,
        ),
        ko.errorNetworkUnstable,
      );
      expect(
        scheduleActionErrorMessage(
          ko,
          const ServerError(statusCode: 503),
          ko.schedCancelFailed,
        ),
        ko.errorServerTemporary,
      );
    });

    test('사유가 없으면 동작별 문구다', () {
      expect(
        scheduleActionErrorMessage(
          ko,
          const ValidationError(),
          ko.schedCancelFailed,
        ),
        ko.schedCancelFailed,
      );
      expect(
        scheduleActionErrorMessage(ko, StateError('x'), ko.schedNoShowFailed),
        ko.schedNoShowFailed,
      );
    });

    test('영어 화면에는 한국어 사유를 띄우지 않는다', () {
      expect(
        scheduleActionErrorMessage(
          en,
          const ServerError(statusCode: 409, message: '이미 마무리된 세션입니다'),
          en.schedCancelFailed,
        ),
        en.schedCancelFailed,
      );
    });

    test('409 만 상태가 바뀐 거절이다', () {
      expect(
        isScheduleStateConflict(const ServerError(statusCode: 409)),
        isTrue,
      );
      expect(
        isScheduleStateConflict(const ServerError(statusCode: 500)),
        isFalse,
      );
      expect(isScheduleStateConflict(const ValidationError()), isFalse);
    });

    test('건너뛰기 실패 문구는 전송 실패 문구가 아니다', () {
      expect(ko.schedRoutinesSkipFailed, isNot(ko.schedRoutinesSendFailed));
      expect(en.schedRoutinesSkipFailed, isNot(en.schedRoutinesSendFailed));
    });
  });

  group('스케줄 화면 실패 토스트', () {
    late _FailingRepository repo;

    Future<void> openSchedule(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        // 오늘 수업이 모두 시작한 뒤 — 완료·노쇼가 열린다(#2760).
        seedClock: kMidWeekEveningKst,
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith((ref) {
            repo = _FailingRepository(
              ref.watch(appDatabaseProvider),
              attached: const <RoutineExercise>[_walking],
            );
            return repo;
          }),
        ],
      );
    }

    Future<void> openSession(WidgetTester tester, String name) async {
      final block = find
          .descendant(
            of: find.byType(ScheduleWeekTimetable),
            matching: find.textContaining(name),
          )
          .first;
      await tester.ensureVisible(block);
      await tester.pump();
      await tester.tap(block);
      await settle(tester);
    }

    Future<void> revealInPanel(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('week-detail')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final Finder target = find.byKey(ValueKey<String>(key));
      await revealInPanel(tester, target);
      await tester.tap(target);
      await settle(tester);
    }

    /// 취소 창에서 [sourceKey] 를 골라 확정한다.
    Future<void> cancelWith(WidgetTester tester, String sourceKey) async {
      await tapKey(tester, 'session-cancel-chip');
      await tester.tap(find.byKey(ValueKey<String>(sourceKey)));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-cancel-confirm')),
      );
      await settle(tester);
    }

    testWidgets('취소 실패는 서버 사유를 보이고, 409 면 주를 다시 읽는다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      repo.cancelError = const ServerError(
        statusCode: 409,
        message: '완료·노쇼로 마무리된 PT는 취소할 수 없습니다',
      );
      final int before = repo.rangeReads;

      await cancelWith(tester, 'cancel-source-member');

      expect(find.text('완료·노쇼로 마무리된 PT는 취소할 수 없습니다'), findsOneWidget);
      expect(find.text('취소 처리하지 못했어요. 잠시 후 다시 시도해 주세요'), findsNothing);
      expect(repo.rangeReads, greaterThan(before));
    });

    testWidgets('사유 없는 취소 실패는 기존 문구다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      // 사유 없는 거절 — 연결 오류는 원인별 안내라 따로 본다.
      repo.cancelError = const ValidationError();

      await cancelWith(tester, 'cancel-source-member');

      expect(find.text('취소 처리하지 못했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);
    });

    testWidgets('연결 오류로 취소가 실패하면 연결 안내다 — Dio 원문이 아니다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      repo.cancelError = const NetworkError();

      await cancelWith(tester, 'cancel-source-member');

      expect(
        find.text(
          lookupAppLocalizations(const Locale('ko')).errorNetworkUnstable,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('exception'), findsNothing);
    });

    testWidgets('사유 없는 5xx 로 노쇼가 실패하면 서버 일시 문제 안내다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      repo.noShowError = const ServerError(statusCode: 500);

      await cancelWith(tester, 'cancel-source-no-show');

      expect(
        find.text(
          lookupAppLocalizations(const Locale('ko')).errorServerTemporary,
        ),
        findsOneWidget,
      );
    });

    testWidgets('노쇼 실패는 서버 사유를 보인다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      repo.noShowError = const ValidationError(
        message: '시작 전 일정은 노쇼 처리할 수 없습니다',
      );

      await cancelWith(tester, 'cancel-source-no-show');

      expect(find.text('시작 전 일정은 노쇼 처리할 수 없습니다'), findsOneWidget);
    });

    testWidgets('개인운동 수정 실패는 서버 사유를 보인다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      repo.updateRoutinesError = const NotFoundError(
        message: '보내지 않은 개인운동이 없습니다',
      );

      await tapKey(tester, 'session-edit-menu');
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-routines-chip')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await settle(tester);

      expect(find.text('보내지 않은 개인운동이 없습니다'), findsOneWidget);
    });

    testWidgets('개인운동 전송 실패는 서버 사유를 보인다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await cancelWith(tester, 'cancel-source-member');
      repo.sendRoutinesError = const ValidationError(message: '보낼 개인운동이 없습니다');

      await tapKey(tester, 'session-routines-send');
      await tester.tap(
        find.byKey(const ValueKey<String>('session-routines-send-confirm')),
      );
      await settle(tester);

      expect(find.text('보낼 개인운동이 없습니다'), findsOneWidget);
    });

    testWidgets('보내지 않기 실패에는 전송 실패 문구가 뜨지 않는다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await cancelWith(tester, 'cancel-source-member');
      repo.dismissError = const ValidationError();

      await tapKey(tester, 'session-routines-skip');

      expect(find.text('보내지 않기로 처리하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('개인운동을 보내지 못했어요. 잠시 후 다시 시도해 주세요.'), findsNothing);
    });

    testWidgets('프로그램 전송 실패는 서버 사유를 보인다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await tapKey(tester, 'session-complete-chip');
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
      );
      await settle(tester);
      repo.sendProgramError = const ValidationError(
        message: '완료한 세션만 보낼 수 있습니다',
      );

      await tapKey(tester, 'schedule-send-program');

      expect(find.text('완료한 세션만 보낼 수 있습니다'), findsOneWidget);
      expect(find.text('전송에 실패했어요. 다시 시도해 주세요'), findsNothing);
    });
  });
}
