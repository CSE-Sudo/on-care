import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/design_system/tokens/colors.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// A chat repository whose sends always fail.
class _FailingChatRepository extends DriftChatRepository {
  const _FailingChatRepository(super.db);

  @override
  Future<void> sendTrainerMessage({
    required String clientId,
    required String text,
    DateTime? reportWeekStart,
  }) async => throw Exception('chat write failed');
}

/// A repository whose writes always fail — to exercise error handling.
class _ThrowingScheduleRepository extends DriftScheduleRepository {
  const _ThrowingScheduleRepository(super.db);

  @override
  Future<void> addSession({
    required String date,
    required String clientName,
    String? clientId,
    required String time,
    required String type,
    required int durationMinutes,
    String note = '',
  }) async => throw Exception('add failed');

  @override
  Future<void> deleteSession(String id) async => throw Exception('del failed');

  @override
  Future<void> completeSession(String id, {String note = ''}) async =>
      throw Exception('complete failed');
}

void main() {
  group('ScheduleRepository.watchToday', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('returns the 6 seeded slots in timeline order', () async {
      final slots = await DriftScheduleRepository(db).watchToday().first;
      expect(slots.length, 6);
      expect(slots.map((s) => s.time).toList(), <String>[
        '12:00',
        '14:00',
        '16:00',
        '17:00',
        // 김민수의 PT 는 공유 픽스처가 정하는 18:00 이다 — 목록은 시각 순이라
        // 시드 목록에서의 자리와 무관하게 여기에 선다.
        '18:00',
        '19:00',
      ]);
      expect(slots.where((s) => s.isGap).length, 2);
    });

    // #386 회귀: 스케줄이 회원을 이름으로 참조하던 시절에는 회원 이름을
    // 바꾸면 과거 세션이 통째로 끊겼다. 크래시도 오류 표시도 없이 주간
    // 리포트가 "세션 0건" 이 되고, 그대로 회원에게 전송될 수 있었다.
    test('회원 이름을 바꿔도 과거 세션이 끊기지 않는다', () async {
      final repo = DriftScheduleRepository(db);
      const key = (id: 'seed-client-1', name: '김민수');
      final before = await repo.watchClientSessions(key).first;
      expect(before, isNotEmpty, reason: '시드에 김민수 세션이 있어야 한다');

      await (db.update(db.trainerClients)
            ..where((t) => t.id.equals('seed-client-1')))
          .write(const TrainerClientsCompanion(name: Value('김민수2')));

      final after = await repo.watchClientSessions((
        id: 'seed-client-1',
        name: '김민수2',
      )).first;
      expect(after.length, before.length);
    });

    test('이름이 같아도 다른 회원의 세션은 섞이지 않는다', () async {
      final repo = DriftScheduleRepository(db);
      // 이름만 같고 id 가 다른 회원은 남의 세션을 가져오면 안 된다.
      final sessions = await repo.watchClientSessions((
        id: 'other-client',
        name: '김민수',
      )).first;
      expect(sessions, isEmpty);
    });

    test('v3 이전 행(client_id 없음)은 이름으로 폴백한다', () async {
      // 마이그레이션만 거친 기존 설치를 흉내 낸다 — client_id 가 null 이다.
      await db
          .into(db.trainerScheduleEntries)
          .insert(
            TrainerScheduleEntriesCompanion.insert(
              id: 'legacy-row',
              date: ymd(nowKst()),
              time: '21:00',
              status: '예정',
              clientName: const Value('  김민수  '), // 공백까지 섞인 기존 데이터
            ),
          );

      final sessions = await DriftScheduleRepository(
        db,
      ).watchClientSessions((id: 'seed-client-1', name: '김민수')).first;
      expect(sessions.any((s) => s.id == 'legacy-row'), isTrue);
    });

    test('decodes the PT program and expandability rules', () async {
      final slots = await DriftScheduleRepository(db).watchToday().first;
      final minsu = slots.firstWhere((s) => s.clientName == '김민수');
      expect(minsu.expandable, isTrue); // 완료 + program
      expect(minsu.program.length, 4);
      expect(minsu.program.first.name, '벤치프레스');
      expect(minsu.program.first.sets, 4);
      expect(minsu.program.first.reps, 10);
      expect(minsu.program.first.weight, 40.0);

      final seongho = slots.firstWhere((s) => s.clientName == '박성호');
      expect(seongho.expandable, isTrue); // 예정 now opens (plan preview)
      expect(seongho.isUpcoming, isTrue);
      final consult = slots.firstWhere((s) => s.clientName == '윤가온');
      expect(consult.program, isEmpty);
      expect(consult.expandable, isTrue); // opens with the no-plan hint
    });

    test('addSession inserts an 예정 slot sorted into the timeline', () async {
      final repo = DriftScheduleRepository(db);
      await repo.addSession(
        date: ymd(nowKst()),
        clientName: '이지수',
        time: '10:15',
        type: '1:1 PT',
        durationMinutes: 45,
      );
      final slots = await repo.watchToday().first;
      expect(slots.length, 7);
      // Lands before the 12:00 session (time-ordered).
      expect(slots[0].time, '10:15');
      expect(slots[0].clientName, '이지수');
      expect(slots[0].isUpcoming, isTrue);
      expect(slots[0].id.startsWith('seed-'), isFalse);
    });

    test('updateSession moves a slot to a 15-minute step', () async {
      final repo = DriftScheduleRepository(db);
      final before = await repo.watchToday().first;
      final target = before.firstWhere((s) => s.clientName == '박성호');
      await repo.updateSession(
        target.id,
        clientName: target.clientName,
        time: '19:30',
        type: target.type,
        durationMinutes: 90,
        note: target.note,
      );
      final after = await repo.watchToday().first;
      final moved = after.firstWhere((s) => s.clientName == '박성호');
      expect(moved.time, '19:30');
      expect(moved.durationMinutes, 90);
    });

    test(
      'updateProgram changes exercises without changing the booking',
      () async {
        final repo = DriftScheduleRepository(db);
        final before = await repo.watchToday().first;
        final target = before.firstWhere((s) => s.clientName == '박성호');

        await repo.updateProgram(
          target.id,
          program: const <ProgramItem>[
            ProgramItem(name: '덤벨 프레스', sets: 4, weight: 16),
          ],
          note: '마지막 세트 RPE 8 확인',
        );

        final after = await repo.watchToday().first;
        final updated = after.firstWhere((s) => s.id == target.id);
        expect(updated.time, target.time);
        expect(updated.clientName, target.clientName);
        expect(updated.program.single.name, '덤벨 프레스');
        expect(updated.program.single.sets, 4);
        expect(updated.note, '마지막 세트 RPE 8 확인');
      },
    );

    test('completeSession flips 예정 to 완료 and logs the 운동기록', () async {
      final repo = DriftScheduleRepository(db);
      final before = await repo.watchToday().first;
      final target = before.firstWhere((s) => s.clientName == '박성호');
      expect(target.isUpcoming, isTrue);

      await repo.completeSession(target.id, note: '벤치 폼 안정적');

      final after = await repo.watchToday().first;
      final done = after.firstWhere((s) => s.clientName == '박성호');
      expect(done.isDone, isTrue);
      expect(done.note, '벤치 폼 안정적');

      // Logged newest-first into his history.
      final history = await db.select(db.clientRoutineHistory).get()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final logged = history.firstWhere((h) => h.id.startsWith('hist-'));
      expect(logged.clientId, 'seed-client-3');
      expect(logged.label, 'PT 세션 · 트레이너 지도');
      expect(logged.trainerNote, '벤치 폼 안정적');
      expect(logged.exercisesJson, contains('벤치프레스'));
      expect(logged.sortOrder, lessThan(0)); // sorts before seed rows
    });

    test('concurrent completeSession calls log the 운동기록 once', () async {
      final repo = DriftScheduleRepository(db);
      final before = await repo.watchToday().first;
      final target = before.firstWhere((s) => s.clientName == '박성호');

      // Both calls observe 예정 before either commits — only the one that
      // actually flips the status may write history (review PR 237).
      await Future.wait<void>(<Future<void>>[
        repo.completeSession(target.id, note: '첫 번째'),
        repo.completeSession(target.id, note: '두 번째'),
      ]);

      final history = await db.select(db.clientRoutineHistory).get();
      final logged = history.where((h) => h.id.startsWith('hist-')).toList();
      expect(logged.length, 1, reason: '완료 처리는 멱등해야 함');

      // A later completion of an already-완료 session is also a no-op.
      await repo.completeSession(target.id, note: '세 번째');
      final after = await db.select(db.clientRoutineHistory).get();
      expect(after.where((h) => h.id.startsWith('hist-')).length, 1);
    });

    test(
      'completeSession with an empty memo keeps the existing note',
      () async {
        final repo = DriftScheduleRepository(db);
        // A booked 예정 session that already carries a note.
        await db
            .into(db.trainerScheduleEntries)
            .insert(
              TrainerScheduleEntriesCompanion.insert(
                id: 'sched-noted',
                date: ymd(nowKst()),
                time: '18:00',
                clientName: const Value('이지수'),
                type: const Value('1:1 PT'),
                durationMinutes: const Value(60),
                status: '예정',
                note: const Value('허리 통증 주의'),
                programJson: const Value('[]'),
              ),
            );

        await repo.completeSession('sched-noted'); // no memo entered

        final after = await repo.watchToday().first;
        final done = after.firstWhere((s) => s.id == 'sched-noted');
        expect(done.isDone, isTrue);
        expect(done.note, '허리 통증 주의'); // preserved, not wiped
      },
    );

    test(
      'completeSession without a known client only flips the status',
      () async {
        final repo = DriftScheduleRepository(db);
        final before = await repo.watchToday().first;
        final consult = before.firstWhere((s) => s.clientName == '윤가온');
        final histBefore =
            (await db.select(db.clientRoutineHistory).get()).length;

        await repo.completeSession(consult.id);

        final after = await repo.watchToday().first;
        expect(after.firstWhere((s) => s.clientName == '윤가온').isDone, isTrue);
        final histAfter =
            (await db.select(db.clientRoutineHistory).get()).length;
        expect(histAfter, histBefore); // no orphan history row
      },
    );

    test('watchDate separates timelines per calendar day', () async {
      final repo = DriftScheduleRepository(db);
      // 시드는 이번 주를 채우므로(#1210) 빈 날은 그 밖에서 잡는다.
      final tomorrow = ymd(nowKst().add(const Duration(days: 14)));

      expect(await repo.watchDate(tomorrow).first, isEmpty);

      await repo.addSession(
        date: tomorrow,
        clientName: '이지수',
        time: '11:00',
        type: '1:1 PT',
        durationMinutes: 60,
      );

      final tomorrowSlots = await repo.watchDate(tomorrow).first;
      expect(tomorrowSlots.single.clientName, '이지수');
      // Today's timeline is untouched.
      expect((await repo.watchToday().first).length, 6);
      // …and the booked-dates set now covers both days.
      final booked = await repo.watchBookedDates().first;
      expect(booked, containsAll(<String>[ymd(nowKst()), tomorrow]));
    });

    test('completing a non-today session labels its own date', () async {
      final repo = DriftScheduleRepository(db);
      // A PAST session — completing it retro-logs the class. Future
      // sessions can't be completed (see the next test).
      // 이번 주는 데모 일정으로 채워져 있다. 실행 요일에 따라 어제가 시드와
      // 겹치지 않도록, 항상 시드 주간 밖의 지난 날짜를 쓴다.
      final yesterday = nowKst().subtract(const Duration(days: 14));
      await repo.addSession(
        date: ymd(yesterday),
        clientName: '이지수',
        time: '11:00',
        type: '1:1 PT',
        durationMinutes: 60,
      );
      final slot = (await repo.watchDate(ymd(yesterday)).first).firstWhere(
        (entry) => entry.clientName == '이지수' && entry.time == '11:00',
      );

      await repo.completeSession(slot.id, note: '어제 세션 뒤늦게 기록');

      final history = await db.select(db.clientRoutineHistory).get();
      final logged = history.firstWhere((h) => h.id.startsWith('hist-'));
      expect(logged.dateLabel, '${yesterday.month}/${yesterday.day}');
      expect(logged.dateLabel.contains('(오늘)'), isFalse);
    });

    test('completeSession refuses a future-dated session', () async {
      final repo = DriftScheduleRepository(db);
      // 시드가 채우지 않는 날 — 그 날의 세션이 하나여야 `single` 이 의미를 갖는다.
      final tomorrow = nowKst().add(const Duration(days: 14));
      await repo.addSession(
        date: ymd(tomorrow),
        clientName: '이지수',
        time: '11:00',
        type: '1:1 PT',
        durationMinutes: 60,
      );
      final slot = (await repo.watchDate(ymd(tomorrow)).first).single;

      // You can't complete a class that hasn't happened yet — the call is
      // a no-op, the session stays 예정 and nothing is logged (review 245).
      await repo.completeSession(slot.id, note: '미리 완료 시도');

      final after = (await repo.watchDate(ymd(tomorrow)).first).single;
      expect(after.status, '예정');
      final history = await db.select(db.clientRoutineHistory).get();
      expect(history.where((h) => h.id.startsWith('hist-')), isEmpty);
    });

    test('client sessions match on the same normalisation as the uniqueness '
        'guard (trim + lowercase)', () async {
      // addClient blocks duplicates on lower(trim(name)) but addSession
      // stores the trainer's raw input. An exact compare here returned
      // nothing for a name saved with stray whitespace, and the weekly
      // report then showed 0 sessions with no error (CodeRabbit #377).
      final repo = DriftScheduleRepository(db);
      await repo.addSession(
        date: ymd(nowKst()),
        clientName: '  김민수  ',
        time: '21:00',
        type: '1:1 PT',
        durationMinutes: 60,
      );

      final found = await repo.watchClientSessions((
        id: 'seed-client-1',
        name: '김민수',
      )).first;
      expect(found.any((s) => s.time == '21:00'), isTrue);
    });

    test('deleteSession removes the slot', () async {
      final repo = DriftScheduleRepository(db);
      final before = await repo.watchToday().first;
      final target = before.firstWhere((s) => s.clientName == '윤가온');
      await repo.deleteSession(target.id);
      final after = await repo.watchToday().first;
      expect(after.length, before.length - 1);
      expect(after.where((s) => s.clientName == '윤가온'), isEmpty);
    });
  });

  group('SchedulePage', () {
    /// 상세 패널이 시간표 오른쪽에 서는 폭으로 창을 넓힌다. (#988)
    ///
    /// 세션을 다루는 동선(수정·삭제·완료·채팅)이 전부 그 패널에 있어서, 좁은
    /// 화면에서는 스크롤 대상이 시간표와 패널 둘로 갈린다.
    void useWideConsole(WidgetTester tester) {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// [wide] 가 false 면 부르는 쪽이 잡아 둔 화면 크기를 그대로 쓴다 — 좁은
    /// 폭 회귀를 보는 테스트가 여기서 다시 넓어지면 아무것도 재지 못한다.
    Future<ProviderContainer> openSchedule(
      WidgetTester tester, {
      bool wide = true,
    }) async {
      if (wide) useWideConsole(tester);
      return pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
      );
    }

    Future<void> enterTimeRange(
      WidgetTester tester, {
      required String start,
      required String end,
      bool confirm = true,
    }) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('session-time-range-field')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-time-range-start-input')),
        start,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-time-range-end-input')),
        end,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      if (confirm) {
        final confirmButton = find.byKey(
          const ValueKey<String>('session-time-range-confirm'),
        );
        await tester.ensureVisible(confirmButton);
        await tester.pump();
        await tester.tap(confirmButton);
        await settle(tester);
      }
    }

    /// [day] 의 일정을 지워 빈 날로 만든다.
    ///
    /// 시드는 이번 주 월~일을 모두 채운다(#1210). "일정이 없는 날" 흐름을 보는
    /// 테스트는 그 조건을 직접 만든다 — 어느 요일에 돌려도 같아야 한다.
    Future<void> clearDay(
      WidgetTester tester,
      ProviderContainer container,
      DateTime day,
    ) async {
      final AppDatabase db = container.read(appDatabaseProvider);
      await tester.runAsync(
        () => (db.delete(
          db.trainerScheduleEntries,
        )..where((t) => t.date.equals(ymd(day)))).go(),
      );
      await settle(tester);
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

    /// 메모 자리가 스스로를 뭐라고 부르는가 — `메모 추가` 인가 `메모 수정` 인가.
    /// 아이콘만 그리는 자리라 그 이름은 툴팁과 시맨틱스에만 남는다(#1011).
    String noteActionLabel(WidgetTester tester) => tester
        .widget<Tooltip>(
          find
              .descendant(
                of: find.byKey(
                  const ValueKey<String>('session-edit-note-chip'),
                ),
                matching: find.byType(Tooltip),
              )
              .first,
        )
        .message!;

    /// 이번 주 안에서 오늘이 아닌 날. 시드가 채운 뒤라 [clearDay] 로 비운다.
    DateTime otherDayThisWeek() {
      final today = todayKst();
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return monday == today ? monday.add(const Duration(days: 1)) : monday;
    }

    testWidgets('주간 시간표에 시간축·격자·세션 블록이 함께 그려진다 (#988)', (tester) async {
      await openSchedule(tester);

      expect(find.text('스케줄'), findsWidgets);
      expect(find.byType(ScheduleWeekTimetable), findsOneWidget);

      // 왼쪽 시간축 — 일정이 없는 시간대도 눈금으로 남는다. 이것이 없던 때에는
      // 10시 세션과 17시 세션이 세로로 붙어 그 사이가 비었다는 사실이 화면에
      // 없었다.
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);

      // 블록은 시간 범위와 종류를 함께 말한다.
      expect(find.text('12:00\u201312:50'), findsWidgets);
      expect(find.text('17:00\u201318:00'), findsWidgets);
      expect(find.text('김민수'), findsWidgets);
      expect(find.textContaining('이지수'), findsWidgets);
      expect(find.textContaining('박성호'), findsWidgets);
      // 소요 시간은 시각 옆 괄호로 갔다(#1012) — 종류만 본다.
      expect(find.textContaining('1:1 PT'), findsWidgets);
      expect(find.text('상담'), findsWidgets);

      // 로스터에 없는 상담 회원도 이름만 부른다(#1012) — 신규라는 사실은
      // 종류 알약(`상담`)이 이미 말한다.
      expect(find.text('윤가온'), findsWidgets);

      // 고른 날의 첫 세션이 상세 패널에 열려 있다.
      expect(find.byKey(const Key('week-detail')), findsOneWidget);
    });

    // 좁은 화면에서도 누르면 세부 프로그램이 떠야 한다. 예전에는 패널을
    // 통째로 버려, 탭이 선택만 바꾸고 화면은 그대로였다(#881).
    testWidgets('좁은 화면 주 보기에서도 세부 프로그램이 뜬다', (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // URL 에 실을 날짜를 인자에서 계산하면 고정 **전** 의 오늘이 들어가,
      // 앱이 보는 오늘과 하루가 어긋난다. 먼저 고정하고 나서 읽는다.
      useFixedKstDate();
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.scheduleAt(date: ymd(todayKst())),
        seedClock: kMidWeekKst,
      );

      // 넓은 화면에서 쓰는 패널과 같은 위젯이 그리드 아래에 쌓인다.
      expect(find.byKey(const Key('week-detail')), findsOneWidget);

      // 세션을 고르면 그 세션의 프로그램이 패널에 실린다.
      final Finder minsuBlock = find
          .descendant(
            of: find.byType(ScheduleWeekTimetable),
            matching: find.textContaining('김민수'),
          )
          .first;
      // 시간축이 08:00~22:00 이라 18:00 블록은 좁은 화면에서 아래로 밀린다 —
      // 보이는 자리로 올리지 않고 누르면 탭이 허공에 떨어진다.
      await tester.ensureVisible(minsuBlock);
      await settle(tester);
      await tester.tap(minsuBlock);
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('week-detail')),
          matching: find.text('벤치프레스'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('week detail follows the URL date after selecting a session', (
      tester,
    ) async {
      // 고정 뒤에 읽어야 URL 날짜와 앱의 오늘이 같다.
      useFixedKstDate();
      final today = nowKst();
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.scheduleAt(date: ymd(today)),
        seedClock: kMidWeekKst,
      );

      final Finder minsuBlock = find
          .descendant(
            of: find.byType(ScheduleWeekTimetable),
            matching: find.textContaining('김민수'),
          )
          .first;
      // 시간축이 08:00~22:00 이라 18:00 블록은 좁은 화면에서 아래로 밀린다 —
      // 보이는 자리로 올리지 않고 누르면 탭이 허공에 떨어진다.
      await tester.ensureVisible(minsuBlock);
      await settle(tester);
      await tester.tap(minsuBlock);
      await settle(tester);
      await goTo(
        tester,
        AppRoutes.scheduleAt(date: ymd(today.add(const Duration(days: 1)))),
      );

      // 어제 고른 세션이 내일의 상세 패널에 남아 있으면 안 된다. 블록은 같은
      // 주에 있는 동안 그대로 있어도 된다 — 그 자리가 그 세션의 자리다.
      expect(
        find.descendant(
          of: find.byKey(const Key('week-detail')),
          matching: find.textContaining('김민수'),
        ),
        findsNothing,
      );
    });

    // 진입점은 헤더 액션이고, 대기 건수는 빨간 배지로 뜬다(#882).
    testWidgets('상담 요청 진입점은 대기 건수를 빨간 배지로 보여 준다', (tester) async {
      await openSchedule(tester);

      final Finder entry = find.byKey(const Key('consult-inbox-entry'));
      expect(entry, findsOneWidget);

      final Badge badge = tester.widget<Badge>(
        find.descendant(of: entry, matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isTrue, reason: '시드에 대기 2건');
      expect(badge.backgroundColor, AppColors.destructive);
      expect(
        find.descendant(of: entry, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('빨간 배지가 아이콘을 가리지 않고 네모 모서리에 붙는다 (#987)', (tester) async {
      // 배지가 아이콘을 감싸던 때에는 지름 16px 짜리 원이 17px 아이콘의 절반을
      // 덮어, 남는 것이 빨간 원뿐이었다. 배지는 숫자를 **더하는** 표시이지
      // 아이콘을 대체하는 표시가 아니다.
      await openSchedule(tester);

      final Finder entry = find.byKey(const Key('consult-inbox-entry'));
      final Rect icon = tester.getRect(
        find.descendant(
          of: entry,
          matching: find.byIcon(Icons.mark_email_unread_outlined),
        ),
      );
      final Rect label = tester.getRect(
        find.descendant(of: entry, matching: find.text('2')),
      );
      // 배지 원(지름 16)은 라벨을 가운데 두므로, 원 전체를 아이콘 오른쪽
      // 바깥에서 재려면 라벨이 아니라 원의 왼쪽 끝을 봐야 한다.
      final double badgeLeft = label.center.dx - 8;

      expect(
        badgeLeft,
        greaterThanOrEqualTo(icon.right),
        reason: '배지가 아이콘 오른쪽 바깥에 있어야 한다',
      );
      final Rect box = tester.getRect(
        find.descendant(of: entry, matching: find.byType(InkWell)).first,
      );
      expect(
        label.center.dy,
        lessThan(box.top + 8),
        reason: '배지는 네모의 위쪽 모서리에 걸친다',
      );
    });

    testWidgets('대기 건이 없으면 빨간 배지를 달지 않는다', (tester) async {
      // 빨강은 처리할 것이 있을 때만 뜬다 — 0건에도 뜨면 몇 번 겪고 나서
      // 아무도 안 보게 된다.
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        extraOverrides: <Override>[
          consultationRepositoryProvider.overrideWithValue(
            DemoConsultationRepository(requests: <ConsultationRequest>[]),
          ),
        ],
        seedClock: kMidWeekKst,
      );

      final Finder entry = find.byKey(const Key('consult-inbox-entry'));
      expect(entry, findsOneWidget);
      final Badge badge = tester.widget<Badge>(
        find.descendant(of: entry, matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('상담 요청 진입점이 좁은 폭에서 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await openSchedule(tester, wide: false);

      expect(find.byKey(const Key('consult-inbox-entry')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('consultation inbox dialog opens over the schedule tab', (
      tester,
    ) async {
      await openSchedule(tester);

      await tester.tap(find.byKey(const Key('consult-inbox-entry')));
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.schedule);
      expect(find.text('상담 요청'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('consultations-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('consultations-back-to-schedule')),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('예약 슬롯 action opens the selected-day management sheet', (
      tester,
    ) async {
      await openSchedule(tester);

      await tester.tap(find.text('예약 슬롯'));
      await settle(tester);

      expect(find.text('예약 슬롯 관리'), findsOneWidget);
      expect(find.textContaining('회원이 예약할 시간을 엽니다'), findsOneWidget);
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('완료 세션의 프로그램을 회원에게 보내고 그 사실이 남는다 (#822)', (tester) async {
      // 펼친 완료 카드와 그 아래 전송 버튼이 한 화면에 들어와야 탭이 닿는다.
      await withWideSurface(tester, () async {
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.schedule,
          seedClock: kMidWeekKst,
        );

        await openSession(tester, '김민수');
        expect(find.text('벤치프레스'), findsOneWidget);
        expect(find.text('플랭크 60초'), findsOneWidget);
        expect(find.text('트레이너 메모'), findsOneWidget);
        expect(
          find.text('무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.'),
          findsOneWidget,
        );

        // 예전에는 이 자리가 눌리지 않는 안내였다("전송 API가 아직 없어…").
        expect(find.text('김민수님에게 전송됨'), findsNothing);
        final send = find.byKey(
          const ValueKey<String>('schedule-send-program'),
        );
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();

        // 보낸 뒤에는 같은 자리가 그 사실을 말하고, 다시 누를 수 없다.
        expect(find.text('김민수님에게 전송됨'), findsWidgets);
        final button = tester.widget<InkWell>(
          find
              .ancestor(
                of: find.text('김민수님에게 전송됨').first,
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(button.onTap, isNull);
      }, size: const Size(1100, 2000));
    });

    testWidgets('예정 session expands to the plan preview with manage '
        'actions', (tester) async {
      await openSchedule(tester);

      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      );
      expect(find.text('벤치프레스'), findsOneWidget); // planned program
      expect(
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-edit-program-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-delete-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-chat-chip')),
        findsOneWidget,
      );
    });

    // 상담은 운동 프로그램을 짜는 자리가 아니라 무슨 이야기를 나눴는지 적는
    // 자리다. 프로그램 안내를 그대로 두면 짜야 할 것이 밀린 것처럼 읽힌다(#988).
    testWidgets('상담 세션은 프로그램 대신 메모 자리를 보여 준다 (#988)', (tester) async {
      await openSchedule(tester);

      await openSession(tester, '윤가온');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-no-note')),
      );
      expect(find.text('아직 남긴 메모가 없어요'), findsOneWidget);
      expect(find.text('아직 계획된 프로그램이 없어요'), findsNothing);
      // 같은 자리가 프로그램이 아니라 메모를 연다.
      expect(
        find.byKey(const ValueKey<String>('session-edit-note-chip')),
        findsOneWidget,
      );
      // 아직 적은 것이 없으므로 `메모 수정` 이 아니라 `메모 추가` 다(#1011).
      expect(noteActionLabel(tester), '메모 추가');
      expect(
        find.byKey(const ValueKey<String>('session-edit-program-chip')),
        findsNothing,
      );
    });

    testWidgets('계획이 없는 1:1 PT 는 프로그램 안내를 보여 준다', (tester) async {
      final container = await openSchedule(tester);

      // 시드의 예정 PT 에는 모두 계획이 있다. 비운 날에 하나 만들면 그 세션이
      // 곧바로 상세 패널에 열린다 — 그 날의 유일한 세션이라서다.
      await clearDay(tester, container, otherDayThisWeek());
      await tester.tap(
        find.byKey(ValueKey<String>('schedule-day-${ymd(otherDayThisWeek())}')),
      );
      await settle(tester);
      await tester.tap(find.text('새 일정'));
      await settle(tester);
      await tester.tap(find.text('추가'));
      await settle(tester);

      await revealInPanel(tester, find.text('아직 계획된 프로그램이 없어요'));
      expect(find.text('아직 계획된 프로그램이 없어요'), findsOneWidget);
      // 계획이 없으면 이 카드 안에서 고치는 자리(`프로그램 수정`)가 아니라
      // 코칭 탭으로 나가는 자리(`프로그램 추가`)만 있다(#1247).
      expect(
        find.byKey(const ValueKey<String>('session-add-program-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-edit-program-chip')),
        findsNothing,
      );
      // 메모 자리는 종류와 상관없이 있다(#1011).
      expect(
        find.byKey(const ValueKey<String>('session-edit-note-chip')),
        findsOneWidget,
      );
      expect(noteActionLabel(tester), '메모 추가');

      await tester.tap(
        find.byKey(const ValueKey<String>('session-add-program-chip')),
      );
      await settle(tester);

      expect(currentLocation(tester), startsWith(AppRoutes.coaching));
    });

    testWidgets('이미 회원에게 보낸 프로그램은 프로그램 수정 아이콘이 없다 (#1247)', (tester) async {
      await withWideSurface(tester, () async {
        await pumpTrainerApp(
          tester,
          token: 'demo-trainer-token',
          at: AppRoutes.schedule,
          seedClock: kMidWeekKst,
        );

        await openSession(tester, '김민수');
        expect(
          find.byKey(const ValueKey<String>('session-edit-program-chip')),
          findsOneWidget,
        );

        final send = find.byKey(
          const ValueKey<String>('schedule-send-program'),
        );
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('session-edit-program-chip')),
          findsNothing,
        );
      }, size: const Size(1100, 2000));
    });

    testWidgets('새 일정 추가 books a session at a 15-minute step', (tester) async {
      await openSchedule(tester);

      await tester.tap(find.text('새 일정'));
      await settle(tester);

      await enterTimeRange(tester, start: '10:15', end: '11:15');

      await tester.tap(find.text('추가'));
      await settle(tester);

      // 시간표 블록이 시작·끝을 함께 말한다. 상세 패널도 같은 범위를 적는다 —
      // 이 날의 첫 세션이라 방금 만든 것이 열린다.
      expect(
        find.descendant(
          of: find.byType(ScheduleWeekTimetable),
          matching: find.text('10:15\u201311:15'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('종료 시간을 직접 옮기면 소요 시간이 바뀐다 (#1090)', (tester) async {
      await openSchedule(tester);

      await tester.tap(find.text('새 일정'));
      await settle(tester);

      await enterTimeRange(tester, start: '10:00', end: '11:30');

      await tester.tap(find.text('추가'));
      await settle(tester);

      expect(find.text('10:00\u201311:30'), findsWidgets);
    });

    testWidgets('종료 시간이 시작보다 이르면 확인을 막는다 (#1090)', (tester) async {
      await openSchedule(tester);

      await tester.tap(find.text('새 일정'));
      await settle(tester);

      await enterTimeRange(
        tester,
        start: '10:00',
        end: '06:00',
        confirm: false,
      );

      final confirm = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('session-time-range-confirm')),
      );
      expect(confirm.onPressed, isNull);
    });

    testWidgets('일정 수정 moves 박성호 to a 15-minute step (16:00 → 16:30)', (
      tester,
    ) async {
      await openSchedule(tester);

      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      );
      await settle(tester);

      // 일정 수정은 상세 패널을 바꿔치는 대신 가운데 모달로 뜬다(#1250).
      // 프로그램·메모 편집은 각자 다른 자리다.
      expect(
        find.byKey(const ValueKey<String>('schedule-editor-seed-schedule-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule-trainer-note')),
        findsNothing,
      );

      await enterTimeRange(tester, start: '16:30', end: '17:30');
      await tester.ensureVisible(find.text('저장'));
      await tester.pump();
      await tester.tap(find.text('저장'));
      await settle(tester);

      // 시각은 시간표 블록과 상세 카드 두 곳에 있다 — 카드 쪽을 잰다.
      expect(
        find.descendant(
          of: find.byKey(const Key('week-detail')),
          matching: find.text('16:30\u201317:30'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('week-detail')),
          matching: find.text('16:00\u201317:00'),
        ),
        findsNothing,
      );
    });

    testWidgets('프로그램 수정 opens a dialog to edit exercises', (tester) async {
      await openSchedule(tester);

      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-edit-program-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-program-chip')),
      );
      await settle(tester);

      // 좁은 상세 패널이 아니라 가운데 모달로 열린다 — 세트·횟수/시간·
      // 중량 칸이 잘리던 문제의 근본 원인이었다.
      expect(
        find.byKey(const ValueKey<String>('program-editor-seed-schedule-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('schedule-editor-seed-schedule-3')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('program-name-0')),
        '덤벨 플라이',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('program-sets-0-field')),
        '4',
      );
      // 메모는 이 편집기에 없다 — 고치는 자리가 둘이면 어느 쪽이 최신인지
      // 읽는 사람이 알 수 없다(#1011).
      expect(
        find.byKey(const ValueKey<String>('program-trainer-note')),
        findsNothing,
      );
      // 운동별 날짜 선택도 없다(#1489 후속) — 이 운동은 이미 이 세션(위
      // 실제 일정)에 속해 있고, 여기서 따로 고르면 세션 날짜와 어긋나는
      // 두 번째 입력이 생긴다.
      expect(
        find.byKey(const ValueKey<String>('program-date-0')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('save-program')),
      );
      await tester.pump();
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('save-program')),
      );
      save.onPressed!();
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('program-editor-seed-schedule-3')),
        findsNothing,
      );
      expect(find.textContaining('16:00\u201316:45'), findsWidgets);
      expect(find.text('덤벨 플라이'), findsOneWidget);
      expect(find.textContaining('4세트'), findsOneWidget);
      // 프로그램만 고쳤으므로 원래 메모는 그대로 남는다.
      expect(find.text('벤치 컨디션 확인 필요.'), findsNothing);
    });

    // 메모는 세션 종류와 상관없이 제 자리를 갖는다. `프로그램 수정` 안쪽,
    // 운동 목록을 다 지나야 나오는 자리에만 있던 때에는 매주 반복되는 1:1 PT 의
    // 메모를 남기려면 프로그램 편집기를 열고 스크롤해 내려가야 했다(#1011).
    testWidgets('1:1 PT 도 메모만 따로 고칠 수 있다 (#1011)', (tester) async {
      await openSchedule(tester);
      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-edit-note-chip')),
      );
      // 메모가 없는 세션이라 이 자리는 아직 `메모 추가` 다(#1011).
      expect(noteActionLabel(tester), '메모 추가');
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-note-chip')),
      );
      await settle(tester);

      // 운동 목록 없이 메모만 연다.
      expect(
        find.byKey(const ValueKey<String>('note-editor-seed-schedule-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('program-name-0')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('program-trainer-note')),
        '견갑 고정 확인',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('save-program')),
      );
      await tester.pump();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('save-program')),
          )
          .onPressed!();
      await settle(tester);

      expect(find.text('견갑 고정 확인'), findsOneWidget);
      // 저장이 프로그램을 지우지 않는다 — 편집기가 보여 주지 않은 값이다.
      expect(find.text('벤치프레스'), findsOneWidget);

      // 메모를 남긴 뒤에는 같은 자리가 `메모 수정` 으로 이름을 바꾼다.
      expect(noteActionLabel(tester), '메모 수정');
    });

    // 자리는 하나지만 하는 일이 둘이다 — 처음 적는 것과 고치는 것. 아무것도
    // 적지 않았는데 `메모 수정` 이라고 부르면, 어딘가에 이미 메모가 있는데 못
    // 찾고 있는 것처럼 읽힌다(#1011).
    testWidgets('메모가 있으면 `메모 수정`, 없으면 `메모 추가` (#1011)', (tester) async {
      await openSchedule(tester);

      final Finder noteChip = find.byKey(
        const ValueKey<String>('session-edit-note-chip'),
      );

      // 시드의 김민수 세션에는 메모가 있다.
      await openSession(tester, '김민수');
      await revealInPanel(tester, noteChip);
      expect(noteActionLabel(tester), '메모 수정');
      expect(
        find.descendant(of: noteChip, matching: find.byIcon(Icons.edit_note)),
        findsOneWidget,
        reason: '아이콘도 함께 갈린다 — 글씨 없이 아이콘만 그리는 자리다',
      );

      // 박성호 세션에는 없다.
      await openSession(tester, '박성호');
      await revealInPanel(tester, noteChip);
      expect(noteActionLabel(tester), '메모 추가');
      expect(
        find.descendant(
          of: noteChip,
          matching: find.byIcon(Icons.note_add_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('삭제 removes the session after confirmation', (tester) async {
      await openSchedule(tester);

      await openSession(tester, '윤가온');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-delete-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-delete-chip')),
      );
      await settle(tester);
      // Confirm in the dialog (its action is the last 삭제 on screen).
      await tester.tap(find.text('삭제').last);
      await settle(tester);

      expect(find.text('윤가온'), findsNothing);
    });

    testWidgets('unsupported program send does not create a chat bubble', (
      tester,
    ) async {
      await openSchedule(tester);

      await openSession(tester, '김민수');
      await revealInPanel(tester, find.textContaining('오늘 PT 프로그램 전송'));
      // There is no delivery endpoint, so merely rendering the disabled
      // action must not manufacture a trainer-authored chat event.
      await goTo(
        tester,
        AppRoutes.clientDetail('seed-client-1', section: 'chat'),
      );
      expect(find.textContaining('📤 오늘 PT 프로그램을 보냈어요'), findsNothing);
    });

    testWidgets('완료 chip asks for confirmation before processing (#1227)', (
      tester,
    ) async {
      await openSchedule(tester);
      await openSession(tester, '박성호'); // 예정 session

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-complete-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-chip')),
      );
      await settle(tester);

      // 취소·노쇼처럼 완료도 종료 상태라 되돌릴 UI가 없다 — 확인 없이
      // 바로 처리하지 않는다.
      expect(find.text('일정 완료'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
        findsOneWidget,
      );

      // 취소를 누르면 처리되지 않고 예정 그대로 남는다.
      await tester.tap(find.text('취소').last);
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('session-complete-chip')),
        findsOneWidget,
      );
    });

    testWidgets('완료 chip marks the session done and shows in 운동기록', (
      tester,
    ) async {
      // 날짜별 기록이 한 목록으로 합쳐지면서 세로가 길어졌다(#1025).
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 3000);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await openSchedule(tester);

      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-complete-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-chip')),
      );
      await settle(tester);
      // 완료는 예정에서만 갈리는 종료 상태라 되돌릴 UI가 없다 — 확인
      // 다이얼로그를 거친 뒤에야 처리된다(#1227).
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
      );
      await settle(tester);

      // The card flipped to 완료 (the 완료 action chip is gone).
      expect(
        find.byKey(const ValueKey<String>('session-complete-chip')),
        findsNothing,
      );

      // …and the 운동 sub-tab shows the fresh PT entry.
      await goTo(
        tester,
        AppRoutes.clientDetail('seed-client-3', section: 'workout'),
      );
      // 운동 기록은 날짜별 목록 하나로 합쳐졌고 오늘 줄은 처음부터 펼쳐져
      // 있다(#1025). 목록이 길어 스크롤 곡예 대신 화면을 키운다.
      //
      // 메모는 더 이상 완료 처리에서 받지 않으므로(#1106) 그 문구로 찾지
      // 않는다 — 방금 생긴 PT 기록의 종류로 확인한다.
      expect(find.text('PT 세션 · 트레이너 지도'), findsWidgets);
      // 날짜는 미션 카드가 아니라 그 줄이 말한다.
      const List<String> weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];
      final DateTime today = nowKst();
      expect(
        find.text(
          '${today.month}월 ${today.day}일 (${weekdays[today.weekday - 1]})',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a future session offers no 완료 action', (tester) async {
      await openSchedule(tester);

      // Browse to tomorrow and book a session there. 주가 월~일 로 고정이라
      // 내일이 다음 주일 수도 있다 — 날짜는 URL 로 지정한다(#988).
      final tomorrow = nowKst().add(const Duration(days: 1));
      await goTo(tester, AppRoutes.scheduleAt(date: ymd(tomorrow)));
      await tester.tap(find.text('새 일정'));
      await settle(tester);
      await tester.tap(find.text('추가'));
      await settle(tester);

      // 갓 만든 예정 세션을 상세 패널에 연다.
      await openSession(tester, '김민수');

      // Manage actions are there, but 완료 is not — the class is in the
      // future (review PR 245).
      expect(
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-edit-program-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-chat-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('session-complete-chip')),
        findsNothing,
      );
    });

    testWidgets('요일 칸을 누르면 그 날을 보고, 오늘 로 돌아온다', (tester) async {
      final container = await openSchedule(tester);
      expect(find.text('김민수'), findsWidgets);
      // 오늘을 보고 있으면 `오늘` 은 눌러도 달라질 것이 없어 뜨지 않는다.
      expect(find.text('오늘'), findsNothing);

      // 같은 주의 다른 날을 비워, 일정이 없는 날의 안내를 본다.
      final other = otherDayThisWeek();
      await clearDay(tester, container, other);
      await tester.tap(
        find.byKey(ValueKey<String>('schedule-day-${ymd(other)}')),
      );
      await settle(tester);

      // 그 날에는 세션이 없어 상세 패널이 비고, `오늘` 이 나타난다.
      expect(
        find.descendant(
          of: find.byType(ScheduleWeekTimetable),
          matching: find.textContaining('김민수'),
        ),
        findsWidgets,
        reason: '같은 주라 오늘의 블록은 그대로 있다',
      );
      expect(find.textContaining('이 날짜에는 일정이 없어요'), findsOneWidget);
      expect(find.text('오늘'), findsOneWidget);

      // 그 날에 일정을 만들면 빈 안내가 사라진다.
      await tester.tap(find.text('새 일정'));
      await settle(tester);
      await tester.tap(find.text('추가'));
      await settle(tester);
      expect(find.text('10:00\u201311:00'), findsWidgets);
      expect(find.textContaining('이 날짜에는 일정이 없어요'), findsNothing);

      // 오늘 → 오늘의 세션이 다시 패널에 실리고 버튼은 숨는다. 패널은 그 날의
      // **첫** 세션을 연다 — 김민수의 PT 는 픽스처가 정한 18:00 이라 오늘의
      // 첫 세션은 12:00 이지수다.
      await tester.tap(find.text('오늘'));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('week-detail')),
          matching: find.text('이지수'),
        ),
        findsOneWidget,
      );
      expect(find.text('오늘'), findsNothing);
    });

    testWidgets('보이는 주는 월요일에서 시작해 일요일에서 끝난다 (#988)', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
      );

      final today = todayKst();
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));

      final first = find.byKey(ValueKey<String>('schedule-day-${ymd(monday)}'));
      final last = find.byKey(ValueKey<String>('schedule-day-${ymd(sunday)}'));
      expect(first, findsOneWidget);
      expect(last, findsOneWidget);
      // 월요일 앞과 일요일 뒤는 없다 — 창이 `오늘 − 3일` 로 떠다니지 않는다.
      expect(
        find.byKey(
          ValueKey<String>(
            'schedule-day-${ymd(monday.subtract(const Duration(days: 1)))}',
          ),
        ),
        findsNothing,
      );

      // 일곱 칸이 폭을 고르게 나눠 쓴다.
      final firstBox = tester.getRect(first);
      final lastBox = tester.getRect(last);
      expect((firstBox.width - lastBox.width).abs(), lessThanOrEqualTo(1.0));
      expect(
        lastBox.right - firstBox.left,
        greaterThan(600),
        reason: '폭 상한이 다시 생기면 여기서 걸린다',
      );
    });

    testWidgets('시간표가 좁은 폭에서도 넘치지 않는다', (tester) async {
      // 가장 좁은 지원 폭. 고정 폭 칸을 쓰던 때에는 여기서 4px 씩 넘쳤다.
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
      );

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('화살표는 주와 함께 보고 있는 날을 옮긴다 (#988)', (tester) async {
      await openSchedule(tester);
      expect(find.text('김민수'), findsWidgets);
      expect(find.text('오늘'), findsNothing);

      // 다음 주에는 시드가 없다 — 시간표가 통째로 비고 `오늘` 이 나타난다.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await settle(tester);
      expect(find.text('김민수'), findsNothing);
      expect(find.text('이번 주에는 일정이 없어요.'), findsOneWidget);
      expect(find.text('오늘'), findsOneWidget);

      // 되돌아오면 오늘이 다시 선택된 주다.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await settle(tester);
      expect(find.text('김민수'), findsWidgets);
      expect(find.text('오늘'), findsNothing);
    });

    testWidgets('채팅 chip jumps to the standalone message thread', (
      tester,
    ) async {
      await openSchedule(tester);

      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-chat-chip')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('session-chat-chip')));
      await settle(tester);

      // Client detail opened on the chat section — the header's message
      // button reads as selected, standing in for the tab it replaced.
      expect(
        find.byKey(const ValueKey<String>('messages-thread-seed-client-3')),
        findsOneWidget,
      );
      // The thread auto-scrolls to the newest message; drag back up so
      // the lazily-built banner at the top of the thread exists.
      await tester.drag(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('messages-thread-seed-client-3'),
              ),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, 600),
      );
      await tester.pump();
      expect(find.textContaining('AI가 박성호님의'), findsOneWidget);
    });

    testWidgets('editing a session whose client is not in the roster keeps '
        'its own values on a no-op save', (tester) async {
      useWideConsole(tester);
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.schedule);

      // 윤가온 (상담, 30분) is booked but is NOT a registered client.
      await openSession(tester, '윤가온');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-edit-schedule-chip')),
      );
      await settle(tester);

      // Save without changing anything — the sheet must have prefilled
      // the session's own values, not snapped to defaults.
      await tester.ensureVisible(find.text('저장'));
      await tester.pump();
      await tester.tap(find.text('저장'));
      await settle(tester);

      // Read the row outside fake-async — a drift stream's .first would
      // otherwise deadlock inside testWidgets.
      String? clientName;
      String? type;
      int? duration;
      await tester.runAsync(() async {
        final slots = await container
            .read(scheduleRepositoryProvider)
            .watchToday()
            .first;
        final consult = slots.firstWhere((s) => s.time == '17:00');
        clientName = consult.clientName;
        type = consult.type;
        duration = consult.durationMinutes;
      });

      expect(clientName, '윤가온'); // not reassigned to 김민수
      expect(type, '상담');
      expect(duration, 60);
    });

    testWidgets('unsupported program action does not call chat repository', (
      tester,
    ) async {
      useWideConsole(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          chatRepositoryProvider.overrideWith(
            (ref) => _FailingChatRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.schedule);

      await openSession(tester, '김민수'); // 완료 session with a program
      await revealInPanel(tester, find.textContaining('오늘 PT 프로그램 전송'));
      expect(find.text('전송에 실패했어요. 다시 시도해 주세요'), findsNothing);
      expect(find.text('김민수님에게 전송됨'), findsNothing);
    });

    testWidgets('a failed save shows a snackbar and keeps the sheet open', (
      tester,
    ) async {
      useWideConsole(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) =>
                _ThrowingScheduleRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.schedule);

      await tester.tap(find.text('새 일정'));
      await settle(tester);
      await tester.tap(find.text('추가'));
      await settle(tester);

      expect(find.text('일정 저장에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
      // Sheet stays open (its title is still present) so input isn't lost.
      expect(find.text('새 일정 추가'), findsOneWidget);
    });

    testWidgets('a failed completion keeps the session 예정 and shows an error', (
      tester,
    ) async {
      useWideConsole(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        // 완료 동작은 지나간 약속에만 열린다 — 박성호의 토요일 수업이 오늘이
        // 되는 시각으로 고정한다.
        seedClock: kSaturdayKst,
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) =>
                _ThrowingScheduleRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );
      await goTo(tester, AppRoutes.schedule);

      await openSession(tester, '박성호'); // 예정 session

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-complete-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-chip')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('session-complete-confirm')),
      );
      await settle(tester);

      // The exception is caught: an error snackbar shows and the card is
      // still 예정 (its ✓ 완료 action remains) (review PR 237).
      expect(find.text('완료 처리에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed delete shows a snackbar', (tester) async {
      useWideConsole(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        extraOverrides: <Override>[
          scheduleRepositoryProvider.overrideWith(
            (ref) =>
                _ThrowingScheduleRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
        seedClock: kMidWeekKst,
      );
      await goTo(tester, AppRoutes.schedule);

      await openSession(tester, '박성호');

      await revealInPanel(
        tester,
        find.byKey(const ValueKey<String>('session-delete-chip')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('session-delete-chip')),
      );
      await settle(tester);
      await tester.tap(find.text('삭제').last); // confirm in dialog
      await settle(tester);

      expect(find.text('일정 삭제에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
    });
  });
}
