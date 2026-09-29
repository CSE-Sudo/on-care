import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/dio_schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/reservation_slot.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_recurrence.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_overlap_banner.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 시간 겹침 — 서버 409 `schedule_overlap` 을 알아보는 곳부터, 데모 저장소의
/// 같은 규칙, 일정·예약 슬롯·상담 승인 화면의 안내까지. (#2284)

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

class _MockDio extends Mock implements Dio {}

Map<String, dynamic> _sessionJson({
  String id = 'sched-9',
  String date = '2031-03-10',
  String time = '10:00',
  String clientName = '김민수',
  String type = '1:1 PT',
  int duration = 60,
}) => <String, dynamic>{
  'id': id,
  'date': date,
  'time': time,
  'member_id': 'm1',
  'client_name': clientName,
  'type': type,
  'duration_minutes': duration,
  'status': '예정',
  'note': '',
  'program': const <dynamic>[],
};

Map<String, dynamic> _overlapBody({
  List<Map<String, dynamic>>? conflicts,
  bool withConflicts = true,
}) => <String, dynamic>{
  'detail': <String, dynamic>{
    'code': scheduleOverlapCode,
    'message': '같은 시간에 이미 다른 일정이 있습니다.',
    if (withConflicts) 'conflicts': conflicts ?? <dynamic>[_sessionJson()],
  },
};

DioException _httpError(String path, int status, Object? body) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
    data: body,
  ),
);

ScheduleSession _session({
  String id = 'blocker',
  String date = '2026-08-20',
  String time = '10:00',
  String clientName = '김민수',
  String type = SessionType.personalTraining,
  int duration = 60,
}) => ScheduleSession(
  id: id,
  date: date,
  time: time,
  clientName: clientName,
  type: type,
  durationMinutes: duration,
  status: ScheduleStatus.upcoming,
  note: '',
  program: const <ProgramItem>[],
);

void main() {
  // ---------------------------------------------------------------------------
  group('scheduleOverlapFromResponse', () {
    test('409 + schedule_overlap 이면 겹친 세션을 들고 온다', () {
      final error = scheduleOverlapFromResponse(409, _overlapBody());
      expect(error, isA<ScheduleOverlapError>());
      expect(error!.conflicts, hasLength(1));
      expect(error.conflicts.single.time, '10:00');
      expect(error.conflicts.single.clientName, '김민수');
      expect(error.conflicts.single.durationMinutes, 60);
    });

    test('회원 예약처럼 목록이 빠진 409 도 겹침이다 — 목록만 비어 있다', () {
      final error = scheduleOverlapFromResponse(
        409,
        _overlapBody(withConflicts: false),
      );
      expect(error, isNotNull);
      expect(error!.conflicts, isEmpty);
    });

    test('다른 409(멱등키 충돌·문자열 사유)는 겹침이 아니다', () {
      expect(
        scheduleOverlapFromResponse(409, <String, dynamic>{
          'detail': '이미 처리된 요청입니다.',
        }),
        isNull,
      );
      expect(
        scheduleOverlapFromResponse(409, <String, dynamic>{
          'detail': <String, dynamic>{'code': 'idempotency_conflict'},
        }),
        isNull,
      );
    });

    test('409 가 아니면 코드가 같아도 겹침으로 읽지 않는다', () {
      expect(scheduleOverlapFromResponse(400, _overlapBody()), isNull);
      expect(scheduleOverlapFromResponse(null, _overlapBody()), isNull);
    });

    test('본문이 없거나 모양이 다르면 null', () {
      expect(scheduleOverlapFromResponse(409, null), isNull);
      expect(scheduleOverlapFromResponse(409, 'conflict'), isNull);
      expect(scheduleOverlapFromResponse(409, <String, dynamic>{}), isNull);
    });

    test('목록 안의 이상한 행은 건너뛴다', () {
      final error = scheduleOverlapFromResponse(409, <String, dynamic>{
        'detail': <String, dynamic>{
          'code': scheduleOverlapCode,
          'conflicts': <dynamic>['oops', 3, _sessionJson(id: 'ok')],
        },
      });
      expect(error!.conflicts.map((s) => s.id), <String>['ok']);
    });
  });

  // ---------------------------------------------------------------------------
  group('DriftScheduleRepository 시간 겹침', () {
    late AppDatabase db;
    late DriftScheduleRepository repo;
    const day = '2031-03-10';

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftScheduleRepository(db);
      await repo.addSession(
        date: day,
        clientName: '김민수',
        time: '10:00',
        type: SessionType.personalTraining,
        durationMinutes: 60,
      );
    });

    tearDown(() => db.close());

    Future<List<ScheduleSession>> sessionsOn(String date) =>
        repo.watchDate(date).first;

    test('시작 시각이 달라도 구간이 겹치면 막는다', () async {
      await expectLater(
        repo.addSession(
          date: day,
          clientName: '이지수',
          time: '10:30',
          type: SessionType.personalTraining,
          durationMinutes: 30,
        ),
        throwsA(
          isA<ScheduleOverlapError>().having(
            (e) => e.conflicts.single.clientName,
            'conflict',
            '김민수',
          ),
        ),
      );
      expect(await sessionsOn(day), hasLength(1));
    });

    test('앞에서 걸쳐 들어오는 일정도 막는다', () async {
      await expectLater(
        repo.addSession(
          date: day,
          clientName: '이지수',
          time: '09:30',
          type: SessionType.personalTraining,
          durationMinutes: 45,
        ),
        throwsA(isA<ScheduleOverlapError>()),
      );
    });

    test('끝과 시작이 맞닿기만 하면 겹침이 아니다', () async {
      await repo.addSession(
        date: day,
        clientName: '이지수',
        time: '11:00',
        type: SessionType.personalTraining,
        durationMinutes: 30,
      );
      await repo.addSession(
        date: day,
        clientName: '박성호',
        time: '09:00',
        type: SessionType.personalTraining,
        durationMinutes: 60,
      );
      expect(await sessionsOn(day), hasLength(3));
    });

    test('다른 날의 같은 시각은 겹침이 아니다', () async {
      await repo.addSession(
        date: '2031-03-11',
        clientName: '이지수',
        time: '10:00',
        type: SessionType.personalTraining,
        durationMinutes: 60,
      );
      expect(await sessionsOn('2031-03-11'), hasLength(1));
    });

    test('취소된 자리는 비어 있다 — 그 시간에 다시 잡을 수 있다', () async {
      final existing = (await sessionsOn(day)).single;
      await repo.cancelSession(existing.id, source: 'trainer');
      await repo.addSession(
        date: day,
        clientName: '이지수',
        time: '10:00',
        type: SessionType.personalTraining,
        durationMinutes: 60,
      );
      expect((await sessionsOn(day)).where((s) => s.isUpcoming), hasLength(1));
    });

    test('수정은 자기 자신과는 겹치지 않는다', () async {
      final existing = (await sessionsOn(day)).single;
      await repo.updateSession(
        existing.id,
        clientName: existing.clientName,
        time: '10:30',
        type: existing.type,
        durationMinutes: 60,
        note: '',
      );
      expect((await sessionsOn(day)).single.time, '10:30');
    });

    test('다른 일정 쪽으로 옮기거나 늘리면 막고 그대로 둔다', () async {
      await repo.addSession(
        date: day,
        clientName: '이지수',
        time: '12:00',
        type: SessionType.personalTraining,
        durationMinutes: 60,
      );
      final mine = (await sessionsOn(
        day,
      )).firstWhere((s) => s.clientName == '김민수');

      // 11:30 까지 늘려도 12:00 과는 맞닿지 않는다 — 통과.
      await repo.updateSession(
        mine.id,
        clientName: mine.clientName,
        time: '10:00',
        type: mine.type,
        durationMinutes: 120,
        note: '',
      );
      // 12:30 까지 늘리면 이지수와 겹친다.
      await expectLater(
        repo.updateSession(
          mine.id,
          clientName: mine.clientName,
          time: '10:00',
          type: mine.type,
          durationMinutes: 150,
          note: '',
        ),
        throwsA(isA<ScheduleOverlapError>()),
      );
      final after = (await sessionsOn(
        day,
      )).firstWhere((s) => s.clientName == '김민수');
      expect(after.durationMinutes, 120);
    });

    test('다른 날로 옮기면 그 날의 일정과 견준다', () async {
      await repo.addSession(
        date: '2031-03-11',
        clientName: '이지수',
        time: '10:15',
        type: SessionType.personalTraining,
        durationMinutes: 30,
      );
      final mine = (await sessionsOn(day)).single;
      await expectLater(
        repo.updateSession(
          mine.id,
          date: '2031-03-11',
          clientName: mine.clientName,
          time: '10:00',
          type: mine.type,
          durationMinutes: 60,
          note: '',
        ),
        throwsA(isA<ScheduleOverlapError>()),
      );
      expect((await sessionsOn(day)).single.id, mine.id);
    });

    test('반복 미리보기는 회차 길이로 겹침을 본다', () async {
      final start = DateTime(2031, 3, 10);
      final rule = WeeklyRecurrence(weekdays: <int>{start.weekday}, count: 2);
      // 10:30 시작은 10:00 과 시작 시각이 달라 예전 규칙으로는 비어 보였다.
      final withDuration = await repo.previewRecurring(
        start: start,
        time: '10:30',
        rule: rule,
        durationMinutes: 30,
      );
      expect(withDuration.conflicts.map((s) => s.time), <String>['10:00']);

      final adjacent = await repo.previewRecurring(
        start: start,
        time: '11:00',
        rule: rule,
        durationMinutes: 30,
      );
      expect(adjacent.conflicts, isEmpty);
    });

    test('반복 생성도 구간이 겹치면 하나도 만들지 않는다', () async {
      final start = DateTime(2031, 3, 3);
      await expectLater(
        repo.addRecurringSessions(
          start: start,
          time: '09:30',
          rule: WeeklyRecurrence(weekdays: <int>{start.weekday}, count: 3),
          clientName: '이지수',
          type: SessionType.personalTraining,
          durationMinutes: 60,
        ),
        throwsA(isA<ScheduleSeriesConflictError>()),
      );
      final range = await repo.watchRange('2031-03-01', '2031-03-31').first;
      expect(range, hasLength(1));
    });

    test('PT 등록이 새 자리를 잡을 때 다른 회원 일정과 겹치면 막는다', () async {
      await expectLater(
        repo.registerProgramSchedule(
          date: day,
          clientId: 'client-2',
          clientName: '이지수',
          time: '10:30',
          durationMinutes: 60,
          assignment: const <String, Object?>{},
          program: const <ProgramItem>[],
        ),
        throwsA(isA<ScheduleOverlapError>()),
      );
      expect(await sessionsOn(day), hasLength(1));
    });

    test('PT 등록이 이 회원의 겹치는 예정 세션에 붙는 것은 겹침이 아니다', () async {
      final attached = await repo.registerProgramSchedule(
        date: day,
        clientId: 'client-9',
        clientName: '김민수',
        time: '10:30',
        durationMinutes: 30,
        assignment: const <String, Object?>{},
        program: const <ProgramItem>[
          ProgramItem(name: '스쿼트', sets: 3, reps: 10),
        ],
      );
      expect(attached, isTrue);
      expect(await sessionsOn(day), hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  group('DioScheduleRepository 겹침 409', () {
    late _MockDio dio;
    late DioScheduleRepository repo;

    setUpAll(() => registerFallbackValue(<String, dynamic>{}));

    setUp(() {
      dio = _MockDio();
      repo = DioScheduleRepository(dio, requestIdFactory: () => 'req-1');
      addTearDown(repo.dispose);
    });

    test('일정 추가 409 schedule_overlap → ScheduleOverlapError', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/trainer/schedule',
          data: any(named: 'data'),
        ),
      ).thenThrow(_httpError('/trainer/schedule', 409, _overlapBody()));

      await expectLater(
        repo.addSession(
          date: '2031-03-10',
          clientName: '이지수',
          time: '10:30',
          type: SessionType.personalTraining,
          durationMinutes: 30,
        ),
        throwsA(
          isA<ScheduleOverlapError>().having(
            (e) => e.conflicts.single.id,
            'conflict id',
            'sched-9',
          ),
        ),
      );
    });

    test('일정 수정 409 schedule_overlap → ScheduleOverlapError', () async {
      when(
        () => dio.put<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_httpError('/trainer/schedule/s1', 409, _overlapBody()));

      await expectLater(
        repo.updateSession(
          's1',
          clientName: '이지수',
          time: '10:30',
          type: SessionType.personalTraining,
          durationMinutes: 30,
          note: '',
        ),
        throwsA(isA<ScheduleOverlapError>()),
      );
    });

    test('겹침이 아닌 409 는 지금처럼 AppError 로 남는다', () async {
      when(
        () => dio.put<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(
        _httpError('/trainer/schedule/s1', 409, <String, dynamic>{
          'detail': '완료된 세션은 수정할 수 없습니다.',
        }),
      );

      await expectLater(
        repo.updateSession(
          's1',
          clientName: '이지수',
          time: '10:30',
          type: SessionType.personalTraining,
          durationMinutes: 30,
          note: '',
        ),
        throwsA(allOf(isA<AppError>(), isNot(isA<ScheduleOverlapError>()))),
      );
    });

    test('반복 미리보기는 회차 길이를 함께 보낸다', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/trainer/schedule/recurring/preview',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(
            path: '/trainer/schedule/recurring/preview',
          ),
          statusCode: 200,
          data: <String, dynamic>{
            'dates': <dynamic>['2031-03-10'],
            'conflicts': <dynamic>[],
          },
        ),
      );

      await repo.previewRecurring(
        start: DateTime(2031, 3, 10),
        time: '10:30',
        rule: WeeklyRecurrence(
          weekdays: <int>{DateTime(2031, 3, 10).weekday},
          count: 1,
        ),
        durationMinutes: 45,
      );

      final sent =
          verify(
                () => dio.post<Map<String, dynamic>>(
                  '/trainer/schedule/recurring/preview',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(sent['duration_minutes'], 45);
    });
  });

  // ---------------------------------------------------------------------------
  group('DioReservationSlotRepository 겹침 409', () {
    late _MockDio dio;
    late DioReservationSlotRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioReservationSlotRepository(dio);
      addTearDown(repo.dispose);
    });

    test('자리 열기 409 schedule_overlap → ScheduleOverlapError', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/trainer/reservation-slots',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError('/trainer/reservation-slots', 409, _overlapBody()),
      );

      await expectLater(
        repo.create(
          startsAt: DateTime(2031, 3, 10, 10, 30),
          sessionType: SessionType.personalTraining,
        ),
        throwsA(isA<ScheduleOverlapError>()),
      );
    });

    test('자리 옮기기 409 schedule_overlap → ScheduleOverlapError', () async {
      when(
        () => dio.put<Map<String, dynamic>>(
          '/trainer/reservation-slots/slot-1',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError('/trainer/reservation-slots/slot-1', 409, _overlapBody()),
      );

      await expectLater(
        repo.update('slot-1', startsAt: DateTime(2031, 3, 10, 10, 30)),
        throwsA(isA<ScheduleOverlapError>()),
      );
    });

    test('그 밖의 실패는 DioException 그대로 — 화면의 서버 사유 경로를 지킨다', () async {
      when(
        () => dio.post<Map<String, dynamic>>(
          '/trainer/reservation-slots',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError('/trainer/reservation-slots', 400, <String, dynamic>{
          'detail': '지난 시간에는 예약 자리를 열 수 없습니다.',
        }),
      );

      await expectLater(
        repo.create(
          startsAt: DateTime(2031, 3, 10, 10, 30),
          sessionType: SessionType.personalTraining,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('상담 승인 저장소', () {
    test('Dio: 승인 409 schedule_overlap → ScheduleOverlapError', () async {
      final dio = _MockDio();
      final repo = DioConsultationRepository(dio);
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/consult-1/accept',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError(
          '/trainer/consultations/consult-1/accept',
          409,
          _overlapBody(),
        ),
      );

      await expectLater(
        repo.accept('consult-1'),
        throwsA(isA<ScheduleOverlapError>()),
      );
    });

    test('Dio: 다른 409 는 지금처럼 서버 사유를 담은 ValidationError', () async {
      final dio = _MockDio();
      final repo = DioConsultationRepository(dio);
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/consult-1/accept',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError(
          '/trainer/consultations/consult-1/accept',
          409,
          <String, Object?>{'detail': '이미 처리된 요청입니다.'},
        ),
      );

      await expectLater(
        repo.accept('consult-1'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('데모: 고른 자리에 일정이 있으면 승인하지 않고 대기로 둔다', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final schedule = DriftScheduleRepository(db);
      final startsAt = DateTime(2031, 3, 10, 19);
      await schedule.addSession(
        date: ymd(startsAt),
        clientName: '박성호',
        time: '18:30',
        type: SessionType.personalTraining,
        durationMinutes: 60,
      );
      final repo = DemoConsultationRepository(
        requests: <ConsultationRequest>[
          ConsultationRequest(
            id: 'c-1',
            memberId: 'member-1',
            memberName: '김하늘',
            goalCode: 'fitness',
            purposeCode: 'general',
            preferredDate: startsAt,
            preferredTimeCode: '19:00',
            slotStartsAt: startsAt,
            slotDurationMinutes: 30,
            status: 'pending',
          ),
        ],
        scheduleRepository: () => schedule,
      );

      await expectLater(
        repo.accept('c-1'),
        throwsA(isA<ScheduleOverlapError>()),
      );
      final pending = await repo.fetch();
      expect(pending.single.isPending, isTrue);
      expect(await schedule.watchDate(ymd(startsAt)).first, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  group('ScheduleOverlapBanner', () {
    Future<void> pumpBanner(
      WidgetTester tester, {
      required Locale locale,
      required List<ScheduleSession> conflicts,
      String? hint,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScheduleOverlapBanner(conflicts: conflicts, hint: hint),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('한국어: 제목·겹친 일정 줄·안내', (tester) async {
      await pumpBanner(
        tester,
        locale: const Locale('ko'),
        conflicts: <ScheduleSession>[_session()],
      );
      expect(find.text(_ko.schedOverlapTitle), findsOneWidget);
      expect(
        find.textContaining(
          _ko.schedRepeatConflictRow('2026-08-20', '10:00', '김민수'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(_ko.schedOverlapHint), findsOneWidget);
    });

    testWidgets('English: title, row and hint', (tester) async {
      await pumpBanner(
        tester,
        locale: const Locale('en'),
        conflicts: <ScheduleSession>[_session()],
        hint: _en.slotOverlapHint,
      );
      expect(find.text(_en.schedOverlapTitle), findsOneWidget);
      expect(
        find.textContaining(
          _en.schedRepeatConflictRow('2026-08-20', '10:00', '김민수'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(_en.slotOverlapHint), findsOneWidget);
      expect(find.textContaining(_en.schedOverlapHint), findsNothing);
    });

    testWidgets('이름이 없는 일정(상담 자리 등)은 종류로 짚는다', (tester) async {
      await pumpBanner(
        tester,
        locale: const Locale('ko'),
        conflicts: <ScheduleSession>[
          _session(clientName: '', type: SessionType.consultation),
        ],
      );
      expect(
        find.textContaining(
          _ko.schedRepeatConflictRow(
            '2026-08-20',
            '10:00',
            sessionTypeLabel(_ko, SessionType.consultation),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('겹친 목록이 없으면 안내만 남는다', (tester) async {
      await pumpBanner(
        tester,
        locale: const Locale('ko'),
        conflicts: const <ScheduleSession>[],
      );
      expect(find.text(_ko.schedOverlapTitle), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('다섯 줄까지만 보인다', (tester) async {
      await pumpBanner(
        tester,
        locale: const Locale('ko'),
        conflicts: <ScheduleSession>[
          for (var i = 0; i < 7; i++)
            _session(id: 's$i', time: '1$i:00', clientName: '회원$i'),
        ],
      );
      expect(find.textContaining('회원4'), findsOneWidget);
      expect(find.textContaining('회원5'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('일정 추가 화면', () {
    void useWideConsole(WidgetTester tester) {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> enterTimeRange(
      WidgetTester tester, {
      required String start,
      required String end,
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
      final confirm = find.byKey(
        const ValueKey<String>('session-time-range-confirm'),
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await settle(tester);
    }

    Future<ProviderContainer> openNewSession(
      WidgetTester tester, {
      Locale locale = const Locale('ko'),
    }) async {
      useWideConsole(tester);
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
        locale: locale,
      );
      final l = locale.languageCode == 'en' ? _en : _ko;
      await tester.tap(find.text(l.schedNewSession));
      await settle(tester);
      return container;
    }

    Future<void> tapAdd(WidgetTester tester, String label) async {
      final add = find.text(label);
      await tester.ensureVisible(add);
      await tester.pump();
      await tester.tap(add);
      await settle(tester);
    }

    Future<int> countAt(ProviderContainer container, String time) async {
      final today = ymd(kMidWeekKst);
      final rows = await container
          .read(scheduleRepositoryProvider)
          .watchDate(today)
          .first;
      return rows.where((s) => s.time == time).length;
    }

    testWidgets('겹치면 창을 닫지 않고 무엇과 겹쳤는지 버튼 위에 남긴다', (tester) async {
      final container = await openNewSession(tester);
      // 오늘 12:00 에는 이지수 수업(50분)이 있다.
      await enterTimeRange(tester, start: '12:30', end: '13:30');
      await tapAdd(tester, _ko.schedAddAction);

      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsOneWidget,
      );
      expect(find.text(_ko.schedOverlapTitle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('schedule-overlap')),
          matching: find.textContaining('이지수'),
        ),
        findsOneWidget,
      );
      // 입력이 남아 있다 — 창이 그대로다.
      expect(
        find.byKey(const ValueKey<String>('session-time-range-field')),
        findsOneWidget,
      );
      // 토스트로 흘려보내지 않는다.
      expect(find.text(_ko.schedSaveFailed), findsNothing);
      expect(await tester.runAsync(() => countAt(container, '12:30')), 0);
    });

    testWidgets('시간을 바꿔 다시 저장하면 안내가 걷히고 저장된다', (tester) async {
      final container = await openNewSession(tester);
      await enterTimeRange(tester, start: '12:30', end: '13:30');
      await tapAdd(tester, _ko.schedAddAction);
      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsOneWidget,
      );

      // 12:50 에 끝나는 수업과 맞닿기만 하는 자리.
      await enterTimeRange(tester, start: '12:50', end: '13:50');
      await tapAdd(tester, _ko.schedAddAction);

      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('session-time-range-field')),
        findsNothing,
      );
      expect(await tester.runAsync(() => countAt(container, '12:50')), 1);
    });

    testWidgets('English console shows the same notice in English', (
      tester,
    ) async {
      await openNewSession(tester, locale: const Locale('en'));
      await enterTimeRange(tester, start: '12:30', end: '13:30');
      await tapAdd(tester, _en.schedAddAction);

      expect(find.text(_en.schedOverlapTitle), findsOneWidget);
      expect(find.textContaining(_en.schedOverlapHint), findsOneWidget);
      expect(find.text(_ko.schedOverlapTitle), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  group('예약 자리 열기', () {
    Future<_OverlapSlotRepository> openSlots(
      WidgetTester tester, {
      Locale locale = const Locale('ko'),
    }) async {
      final repo = _OverlapSlotRepository();
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        // 기본 열기 시각(10:00)이 아직 오지 않은 아침.
        seedClock: DateTime(2026, 8, 20, 7),
        locale: locale,
        extraOverrides: <Override>[
          reservationSlotRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('schedule-open-slots')),
      );
      await settle(tester);
      return repo;
    }

    testWidgets('겹치면 폼 아래에 겹친 일정을 짚어 두고, 다시 열면 걷힌다', (tester) async {
      final repo = await openSlots(tester);
      repo.overlapNext = <ScheduleSession>[_session(clientName: '윤가온')];

      await tester.tap(find.byKey(const ValueKey<String>('slot-create')));
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsOneWidget,
      );
      expect(find.textContaining(_ko.slotOverlapHint), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('schedule-overlap')),
          matching: find.textContaining('윤가온'),
        ),
        findsOneWidget,
      );
      expect(find.text(_ko.slotActionFailed), findsNothing);
      expect(repo.created, isEmpty);

      await tester.tap(find.byKey(const ValueKey<String>('slot-create')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsNothing,
      );
      expect(repo.created, hasLength(1));
      // 토스트 타이머를 흘려보낸다.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('English: slot notice', (tester) async {
      final repo = await openSlots(tester, locale: const Locale('en'));
      repo.overlapNext = <ScheduleSession>[_session()];

      await tester.tap(find.byKey(const ValueKey<String>('slot-create')));
      await settle(tester);

      expect(find.text(_en.schedOverlapTitle), findsOneWidget);
      expect(find.textContaining(_en.slotOverlapHint), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  group('상담 승인', () {
    ConsultationRequest request() => ConsultationRequest(
      id: 'consult-1',
      memberId: 'user-1',
      memberName: '김하늘',
      goalCode: 'fitness',
      purposeCode: 'general',
      preferredDate: DateTime(2026, 8, 21, 19),
      preferredTimeCode: '19:00',
      slotStartsAt: DateTime(2026, 8, 21, 19),
      slotDurationMinutes: 30,
      status: 'pending',
    );

    Future<_OverlapConsultationRepository> openInbox(
      WidgetTester tester, {
      Locale locale = const Locale('ko'),
    }) async {
      final repo = _OverlapConsultationRepository(<ConsultationRequest>[
        request(),
      ]);
      await pumpTrainerApp(
        tester,
        token: 'demo-token',
        at: AppRoutes.consultations,
        locale: locale,
        extraOverrides: <Override>[
          consultationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await settle(tester);
      return repo;
    }

    testWidgets('겹치면 신청을 대기로 둔 채 카드 안에 겹친 일정을 짚는다', (tester) async {
      final repo = await openInbox(tester);
      repo.overlapNext = <ScheduleSession>[
        _session(date: '2026-08-21', time: '18:30', clientName: '박성호'),
      ];

      await tester.tap(
        find.byKey(const ValueKey<String>('consultation-accept-consult-1')),
      );
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsOneWidget,
      );
      expect(find.textContaining(_ko.consultOverlapHint), findsOneWidget);
      expect(find.textContaining('박성호'), findsOneWidget);
      // 대기 그대로 — 승인 버튼이 다시 누를 수 있게 남아 있다.
      final accept = find.byKey(
        const ValueKey<String>('consultation-accept-consult-1'),
      );
      expect(accept, findsOneWidget);
      expect(find.text(_ko.consultActionFailed), findsNothing);

      // 겹친 일정을 옮긴 뒤 다시 승인하면 통과하고 안내가 걷힌다.
      await tester.tap(accept);
      await settle(tester);
      expect(repo.accepted, <String>['consult-1']);
      expect(
        find.byKey(const ValueKey<String>('schedule-overlap')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('English: consultation notice', (tester) async {
      final repo = await openInbox(tester, locale: const Locale('en'));
      repo.overlapNext = <ScheduleSession>[_session()];

      await tester.tap(
        find.byKey(const ValueKey<String>('consultation-accept-consult-1')),
      );
      await settle(tester);

      expect(find.text(_en.schedOverlapTitle), findsOneWidget);
      expect(find.textContaining(_en.consultOverlapHint), findsOneWidget);
      expect(find.text(_ko.consultOverlapHint), findsNothing);
    });
  });
}

/// 다음 한 번의 `create` 를 겹침으로 막는 슬롯 저장소.
class _OverlapSlotRepository implements ReservationSlotRepository {
  final List<ReservationSlot> created = <ReservationSlot>[];
  final StreamController<void> _revisions = StreamController<void>.broadcast();
  List<ScheduleSession>? overlapNext;

  @override
  Future<List<ReservationSlot>> list() async => created;

  @override
  Stream<List<ReservationSlot>> watch() =>
      activePollingStream<List<ReservationSlot>>(
        load: list,
        interval: null,
        refreshes: _revisions.stream,
      );

  @override
  Future<ReservationSlot> create({
    required DateTime startsAt,
    int durationMinutes = 60,
    required String sessionType,
  }) async {
    final blocked = overlapNext;
    if (blocked != null) {
      overlapNext = null;
      throw ScheduleOverlapError(blocked);
    }
    final slot = ReservationSlot(
      id: 'slot-${created.length + 1}',
      startsAt: startsAt,
      durationMinutes: durationMinutes,
      booked: false,
      isClosed: false,
      sessionType: sessionType,
    );
    created.add(slot);
    _revisions.add(null);
    return slot;
  }

  @override
  Future<ReservationSlot> update(
    String id, {
    DateTime? startsAt,
    int? durationMinutes,
    String? sessionType,
  }) => throw UnimplementedError();

  @override
  Future<ReservationSlot> close(String id) => throw UnimplementedError();

  @override
  void dispose() => unawaited(_revisions.close());
}

/// 다음 한 번의 승인을 겹침으로 막는 상담 저장소.
class _OverlapConsultationRepository implements ConsultationRepository {
  _OverlapConsultationRepository(this.requests);

  List<ConsultationRequest> requests;
  List<ScheduleSession>? overlapNext;
  final List<String> accepted = <String>[];

  @override
  bool get supportsInbox => true;

  @override
  Future<List<ConsultationRequest>> fetch({
    String status = 'pending',
    int limit = consultationPageSize,
    DateTime? before,
    String? beforeId,
  }) async => before != null
      ? const <ConsultationRequest>[]
      : status == 'pending'
      ? requests.where((r) => r.isPending).toList()
      : requests;

  @override
  Stream<List<ConsultationRequest>> watch({
    String status = 'pending',
    int limit = consultationPageSize,
  }) => Stream<List<ConsultationRequest>>.fromFuture(fetch(status: status));

  @override
  Future<int> pendingCount() async => requests.where((r) => r.isPending).length;

  @override
  Stream<int> watchPendingCount() => Stream<int>.fromFuture(pendingCount());

  @override
  Future<ConsultationAcceptResult> accept(String id) async {
    final blocked = overlapNext;
    if (blocked != null) {
      overlapNext = null;
      throw ScheduleOverlapError(blocked);
    }
    accepted.add(id);
    return const ConsultationAcceptResult(
      clientConnected: false,
      scheduleCreated: true,
    );
  }

  @override
  Future<void> reject(String id, {String? note}) async {}
}
