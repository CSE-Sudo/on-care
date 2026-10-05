import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/reservation_slot_repository.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  // `watch()` 가 앱 생명주기(포그라운드 여부)를 보므로 바인딩이 필요하다.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioReservationSlotRepository repository;

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  setUp(() {
    dio = _MockDio();
    repository = DioReservationSlotRepository(dio);
  });

  Map<String, dynamic> slotJson({
    int remaining = 1,
    String sessionType = '1:1 PT',
  }) => <String, dynamic>{
    'id': 'slot-1',
    'trainer_id': 'trainer-1',
    'starts_at': '2026-08-10T01:00:00Z',
    'duration_minutes': 60,
    'capacity': 1,
    'remaining': remaining,
    'is_closed': false,
    'session_type': sessionType,
  };

  test('list maps the trainer slot API response', () async {
    when(() => dio.get<List<dynamic>>('/trainer/reservation-slots')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/reservation-slots'),
        statusCode: 200,
        data: <dynamic>[slotJson(remaining: 0)],
      ),
    );

    final result = await repository.list();

    expect(result.single.id, 'slot-1');
    // 서버가 좌석 수로 주더라도 앱은 예약 여부만 본다(#1072).
    expect(result.single.booked, isTrue);
    expect(result.single.sessionType, '1:1 PT');
    expect(result.single.durationMinutes, 60);
  });

  test('좌석이 남아 있으면 비어 있는 자리로 읽는다', () async {
    when(() => dio.get<List<dynamic>>('/trainer/reservation-slots')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/reservation-slots'),
        statusCode: 200,
        data: <dynamic>[slotJson()],
      ),
    );

    expect((await repository.list()).single.booked, isFalse);
  });

  test('watch 는 회원 앱이 잡아 간 자리를 주기적으로 다시 읽는다 (#1590)', () async {
    var calls = 0;
    when(() => dio.get<List<dynamic>>('/trainer/reservation-slots')).thenAnswer(
      (_) async {
        calls += 1;
        return Response<List<dynamic>>(
          requestOptions: RequestOptions(path: '/trainer/reservation-slots'),
          statusCode: 200,
          // 두 번째 읽기에서 회원이 그 자리를 잡았다.
          data: <dynamic>[
            <String, dynamic>{
              ...slotJson(remaining: calls == 1 ? 1 : 0),
              if (calls > 1) 'booked_by_name': '김하늘',
            },
          ],
        );
      },
    );

    final emissions = await DioReservationSlotRepository(
      dio,
      pollInterval: const Duration(milliseconds: 5),
    ).watch().take(2).toList().timeout(const Duration(seconds: 1));

    expect(emissions.first.single.booked, isFalse);
    expect(emissions.last.single.booked, isTrue);
    expect(emissions.last.single.bookedByName, '김하늘');
  });

  test('watch 는 이 콘솔이 만든 변경도 기다리지 않고 다시 읽는다 (#1590)', () async {
    when(() => dio.get<List<dynamic>>('/trainer/reservation-slots')).thenAnswer(
      (_) async => Response<List<dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/reservation-slots'),
        statusCode: 200,
        data: <dynamic>[slotJson()],
      ),
    );
    when(
      () =>
          dio.delete<Map<String, dynamic>>('/trainer/reservation-slots/slot-1'),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(
          path: '/trainer/reservation-slots/slot-1',
        ),
        statusCode: 200,
        data: <String, dynamic>{...slotJson(), 'is_closed': true},
      ),
    );

    // 폴링 없이(주기를 길게) 변경 신호만으로 두 번째 값이 오는지 본다.
    final repo = DioReservationSlotRepository(
      dio,
      pollInterval: const Duration(minutes: 5),
    );
    final emissions = repo
        .watch()
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    await repo.close('slot-1');

    expect(await emissions, hasLength(2));
  });

  test('create sends UTC time, duration, and session type', () async {
    when(
      () => dio.post<Map<String, dynamic>>(
        '/trainer/reservation-slots',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/trainer/reservation-slots'),
        statusCode: 201,
        data: slotJson(sessionType: '상담'),
      ),
    );

    await repository.create(
      startsAt: DateTime.parse('2026-08-10T10:00:00+09:00'),
      sessionType: '상담',
    );

    final data =
        verify(
              () => dio.post<Map<String, dynamic>>(
                '/trainer/reservation-slots',
                data: captureAny(named: 'data'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(data, <String, dynamic>{
      'starts_at': '2026-08-10T01:00:00.000Z',
      'duration_minutes': 60,
      'session_type': '상담',
    });
  });

  test('update and close use the slot-scoped endpoints', () async {
    when(
      () => dio.put<Map<String, dynamic>>(
        '/trainer/reservation-slots/slot-1',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(
          path: '/trainer/reservation-slots/slot-1',
        ),
        statusCode: 200,
        data: slotJson(sessionType: '상담'),
      ),
    );
    when(
      () =>
          dio.delete<Map<String, dynamic>>('/trainer/reservation-slots/slot-1'),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(
          path: '/trainer/reservation-slots/slot-1',
        ),
        statusCode: 200,
        data: <String, dynamic>{...slotJson(), 'is_closed': true},
      ),
    );

    await repository.update('slot-1', sessionType: '상담');
    final closed = await repository.close('slot-1');

    verify(
      () => dio.put<Map<String, dynamic>>(
        '/trainer/reservation-slots/slot-1',
        data: <String, dynamic>{'session_type': '상담'},
      ),
    ).called(1);
    expect(closed.isClosed, isTrue);
  });

  group('MockReservationSlotRepository validation', () {
    test('create rejects past times', () async {
      final mockRepository = MockReservationSlotRepository();

      await expectLater(
        mockRepository.create(
          startsAt: nowKst().subtract(const Duration(minutes: 1)),
          sessionType: '1:1 PT',
        ),
        throwsStateError,
      );
      expect(await mockRepository.list(), isEmpty);
    });

    test('새로 연 자리는 비어 있는 상태로 시작한다', () async {
      final mockRepository = MockReservationSlotRepository();
      final future = nowKst().add(const Duration(days: 1));

      final slot = await mockRepository.create(
        startsAt: future,
        sessionType: '상담',
      );

      expect(slot.booked, isFalse);
      expect(slot.isClosed, isFalse);
      expect(slot.sessionType, '상담');
    });

    test('update rejects past times', () async {
      final mockRepository = MockReservationSlotRepository();
      final slot = await mockRepository.create(
        startsAt: nowKst().add(const Duration(days: 1)),
        sessionType: '1:1 PT',
      );

      await expectLater(
        mockRepository.update(
          slot.id,
          startsAt: nowKst().subtract(const Duration(minutes: 1)),
        ),
        throwsStateError,
      );

      final unchanged = (await mockRepository.list()).single;
      expect(unchanged.sessionType, '1:1 PT');
      expect(unchanged.startsAt, slot.startsAt);
    });

    test('watch 는 자리를 열고 닫을 때마다 새 목록을 낸다 (#1590)', () async {
      final mockRepository = MockReservationSlotRepository();
      addTearDown(mockRepository.dispose);
      final emissions = mockRepository
          .watch()
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      await mockRepository.create(
        startsAt: nowKst().add(const Duration(days: 1)),
        sessionType: '상담',
      );

      final pages = await emissions;
      expect(pages.first, isEmpty);
      expect(pages.last.single.sessionType, '상담');
    });

    test('update can change the session type of an open slot', () async {
      final mockRepository = MockReservationSlotRepository();
      final slot = await mockRepository.create(
        startsAt: nowKst().add(const Duration(days: 1)),
        sessionType: '1:1 PT',
      );

      final changed = await mockRepository.update(slot.id, sessionType: '상담');

      expect(changed.sessionType, '상담');
    });
  });
}
