import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/shared/widgets/action_button.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 취소·노쇼 — 삭제와 갈라진 동작과 그 기록. (#871)
void main() {
  group('DriftScheduleRepository 상태 전이', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });

    tearDown(() => db.close());

    Future<ScheduleSession> upcoming(DriftScheduleRepository repo) async {
      final today = await repo.watchToday().first;
      return today.firstWhere((session) => session.isUpcoming);
    }

    test('취소는 행을 남긴다 — 삭제와 다른 동작이다', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.cancelSession(session.id, source: CancellationSource.member);

      final after = await repo.watchToday().first;
      final stored = after.firstWhere((item) => item.id == session.id);
      expect(stored.isCancelled, isTrue);
      expect(stored.isUpcoming, isFalse);
      expect(stored.isFinished, isTrue);
    });

    test('취소가 주체·시각·사유를 함께 남긴다 (#906)', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.cancelSession(
        session.id,
        source: CancellationSource.member,
        reason: '회원 출장',
      );

      final stored = (await repo.watchToday().first).firstWhere(
        (item) => item.id == session.id,
      );
      // 데모도 실서버와 같은 것을 저장한다 — 취소한 쪽을 고르고도 카드에 남지
      // 않으면 취소가 삭제와 어떻게 다른지 화면에서 전달되지 않는다.
      expect(stored.cancellationSource, CancellationSource.member);
      expect(stored.cancellationReason, '회원 출장');
      expect(stored.cancelledAt, isNotNull);
      expect(stored.noShowAt, isNull);
    });

    test('노쇼는 시각만 남기고 취소 주체는 비어 있다 (#906)', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.markNoShow(session.id);

      final stored = (await repo.watchToday().first).firstWhere(
        (item) => item.id == session.id,
      );
      expect(stored.noShowAt, isNotNull);
      expect(stored.cancelledAt, isNull);
      // 노쇼에는 주체가 없다 — 약속은 그대로였고 회원이 오지 않았다.
      expect(stored.cancellationSource, isEmpty);
    });

    test('마무리된 세션의 기록은 뒤이은 요청에 덮이지 않는다 (#906)', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.cancelSession(
        session.id,
        source: CancellationSource.member,
        reason: '회원 출장',
      );
      final first = (await repo.watchToday().first).firstWhere(
        (item) => item.id == session.id,
      );
      await repo.cancelSession(
        session.id,
        source: CancellationSource.trainer,
        reason: '덮어쓰기 시도',
      );

      final stored = (await repo.watchToday().first).firstWhere(
        (item) => item.id == session.id,
      );
      expect(stored.cancellationSource, first.cancellationSource);
      expect(stored.cancellationReason, first.cancellationReason);
      expect(stored.cancelledAt, first.cancelledAt);
    });

    test('노쇼도 행을 남기고 취소와 구분된다', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.markNoShow(session.id);

      final stored = (await repo.watchToday().first).firstWhere(
        (item) => item.id == session.id,
      );
      expect(stored.isNoShow, isTrue);
      expect(stored.isCancelled, isFalse);
    });

    test('이미 마무리된 세션은 다른 결말로 바뀌지 않는다', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.cancelSession(session.id, source: CancellationSource.trainer);
      // 실서버는 409 로 막고, 데모는 조용히 아무것도 하지 않는다 — 어느 쪽이든
      // 취소한 세션이 노쇼로 뒤집히지 않는 것이 규칙이다.
      await repo.markNoShow(session.id);

      final stored = (await repo.watchToday().first).firstWhere(
        (item) => item.id == session.id,
      );
      expect(stored.isCancelled, isTrue);
    });

    test('삭제는 여전히 행을 없앤다', () async {
      final repo = DriftScheduleRepository(db);
      final session = await upcoming(repo);

      await repo.deleteSession(session.id);

      final after = await repo.watchToday().first;
      expect(after.where((item) => item.id == session.id), isEmpty);
    });
  });

  group('스케줄 화면', () {
    Future<void> openSchedule(WidgetTester tester) async {
      // 세션을 다루는 동선은 시간표 오른쪽 상세 패널에 있다(#988).
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
      );
    }

    /// 시간표에서 [name] 의 블록을 눌러 상세 패널에 연다.
    Future<void> openSession(WidgetTester tester, String name) async {
      // 블록의 둘째 줄은 `이름 종류` 라 이름만으로는 정확히 맞지 않는다(#1010).
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

    /// 상세 패널 안에서 [finder] 가 보일 때까지 스크롤한다.
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

    Future<void> tapChip(WidgetTester tester, String key) async {
      final chip = find.byKey(ValueKey<String>(key));
      await revealInPanel(tester, chip);
      await tester.tap(chip);
      await settle(tester);
    }

    testWidgets('취소는 주체를 고르기 전에는 저장되지 않는다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await tapChip(tester, 'session-cancel-chip');

      // 기본 주체가 없다 — 무엇이든 기본으로 저장되면 그 값이 사실인지 알 수 없다.
      final confirm = find.byKey(
        const ValueKey<String>('session-cancel-confirm'),
      );
      expect(tester.widget<ActionButton>(confirm).onPressed, isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('cancel-source-member')),
      );
      await settle(tester);
      expect(tester.widget<ActionButton>(confirm).onPressed, isNotNull);
    });

    testWidgets('취소한 세션은 목록에 남고 상태와 기록을 보여 준다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await tapChip(tester, 'session-cancel-chip');

      await tester.tap(
        find.byKey(const ValueKey<String>('cancel-source-member')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('cancel-reason-input')),
        '회원 출장',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-cancel-confirm')),
      );
      await settle(tester);

      // 삭제가 아니다 — 그 자리에 남아 취소로 보인다.
      expect(find.text('박성호'), findsWidgets);
      expect(find.text('취소'), findsWidgets);
      // 데모도 주체·시각을 저장하므로 기록 줄이 그대로 뜬다(#906).
      expect(find.textContaining('회원 취소'), findsOneWidget);
      expect(find.text('회원 출장'), findsOneWidget);
      // 마무리된 세션에는 완료·취소·노쇼 동작이 더 이상 나오지 않는다.
      expect(
        find.byKey(const ValueKey<String>('session-cancel-chip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('session-complete-chip')),
        findsNothing,
      );
    });

    testWidgets('노쇼는 확인을 거쳐 기록된다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      await tapChip(tester, 'session-no-show-chip');

      await tester.tap(
        find.byKey(const ValueKey<String>('session-no-show-confirm')),
      );
      await settle(tester);

      expect(find.text('박성호'), findsWidgets);
      expect(find.text('노쇼'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('session-no-show-chip')),
        findsNothing,
      );
    });

    testWidgets('삭제 확인 문구가 취소·노쇼를 가리킨다', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');
      final delete = find.byKey(const ValueKey<String>('session-delete-chip'));
      await revealInPanel(tester, delete.first);
      await tester.tap(delete.first);
      await settle(tester);

      // 잘못 만든 일정과 진행되지 않은 PT 를 가르는 문장이다(#871).
      expect(find.textContaining('취소·노쇼로 남기세요'), findsOneWidget);
    });

    testWidgets('완료된 세션의 삭제 확인 문구는 취소·노쇼를 권하지 않는다', (
      tester,
    ) async {
      await openSchedule(tester);
      // 김민수(18:00, 완료)는 예정에서만 갈리는 취소·노쇼로 되돌릴 수 없다(#1226).
      await openSession(tester, '김민수');
      final delete = find.byKey(const ValueKey<String>('session-delete-chip'));
      await revealInPanel(tester, delete.first);
      await tester.tap(delete.first);
      await settle(tester);

      expect(find.textContaining('취소·노쇼로 남기세요'), findsNothing);
      expect(
        find.text('18:00–18:50 김민수님 PT 일정을 삭제할까요?'),
        findsOneWidget,
      );
    });
  });
}
