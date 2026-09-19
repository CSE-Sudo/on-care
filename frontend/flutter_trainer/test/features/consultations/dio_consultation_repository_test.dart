import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

class _MockDio extends Mock implements Dio {}

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

Response<T> _ok<T>(T body, String path) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: body,
);

DioException _httpError(int status, String path, {Object? body}) =>
    DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: RequestOptions(path: path),
        statusCode: status,
        data: body,
      ),
    );

const AppConfig _demoConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioConsultationRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioConsultationRepository(dio);
  });

  group('DioConsultationRepository', () {
    test('fetch defaults to the pending filter', () async {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/consultations',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok<List<dynamic>>(<dynamic>[
          <String, Object?>{
            'id': 'consult-1',
            'member_id': 'u1',
            'member_name': '김민수',
            'exercise_goal': 'strength',
            'health_purpose_type': 'general',
            'preferred_date': '2026-08-12',
            'preferred_time_slot': 'morning',
            'status': 'pending',
          },
        ], '/trainer/consultations'),
      );

      final list = await repo.fetch();

      expect(list, hasLength(1));
      expect(list.single.memberName, '김민수');
      final captured =
          verify(
                () => dio.get<List<dynamic>>(
                  '/trainer/consultations',
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured['status'], 'pending');
    });

    test('첫 쪽은 상한만 싣고, 이어 받기는 (created_at, id) 를 UTC 로 넘긴다 (#980)', () async {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/consultations',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async =>
            _ok<List<dynamic>>(const <dynamic>[], '/trainer/consultations'),
      );

      await repo.fetch();
      await repo.fetch(
        status: 'all',
        before: DateTime.utc(2026, 8, 19, 9).toLocal(),
        beforeId: 'consult-1',
      );

      final captured = verify(
        () => dio.get<List<dynamic>>(
          '/trainer/consultations',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.cast<Map<String, Object?>>();

      // 첫 쪽에는 커서를 싣지 않는다 — 실으면 첫 쪽이 한 칸 밀린다.
      expect(captured.first['limit'], consultationPageSize);
      expect(captured.first.containsKey('before'), isFalse);
      expect(captured.first.containsKey('before_id'), isFalse);
      // 엔티티는 로컬 시각을 들고 있다. 그대로 보내면 쪽 경계가 시간대만큼 밀린다.
      expect(captured.last['status'], 'all');
      expect(captured.last['before'], '2026-08-19T09:00:00.000Z');
      expect(captured.last['before_id'], 'consult-1');
    });

    test('fetch skips malformed elements instead of throwing', () async {
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/consultations',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _ok<List<dynamic>>(<dynamic>[
          'nonsense',
          <String, Object?>{
            'id': 'consult-2',
            'member_id': 'u2',
            'member_name': '이지수',
            'exercise_goal': 'fitness',
            'health_purpose_type': 'general',
            'preferred_date': '2026-08-13',
            'preferred_time_slot': 'evening',
            'status': 'pending',
          },
        ], '/trainer/consultations'),
      );

      final list = await repo.fetch();

      expect(list.map((r) => r.id), <String>['consult-2']);
    });

    test('pendingCount reads the count field', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          '/trainer/consultations/pending-count',
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'count': 3,
        }, '/trainer/consultations/pending-count'),
      );

      expect(await repo.pendingCount(), 3);
    });

    test('accept posts to the accept path', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/consult-1/accept',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'client_connected': true,
          'schedule_created': true,
          'schedule_id': 'sched-1',
        }, '/trainer/consultations/consult-1/accept'),
      );

      final result = await repo.accept('consult-1');

      final data =
          verify(
                () => dio.post<Map<String, Object?>>(
                  '/trainer/consultations/consult-1/accept',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      // 승인은 시각을 보내지 않는다 — 회원이 고른 자리가 이미 정해 두었다(#1873).
      for (final String key in <String>[
        'date',
        'time',
        'type',
        'duration_minutes',
      ]) {
        expect(data.containsKey(key), isFalse, reason: key);
      }
      expect(result.clientConnected, isTrue);
      expect(result.scheduleCreated, isTrue);
      expect(result.scheduleId, 'sched-1');
    });

    test('reject carries the note the member will receive', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/consult-1/reject',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(
          <String, Object?>{},
          '/trainer/consultations/consult-1/reject',
        ),
      );

      await repo.reject('consult-1', note: '정원이 찼어요');

      final data =
          verify(
                () => dio.post<Map<String, Object?>>(
                  '/trainer/consultations/consult-1/reject',
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(data['note'], '정원이 찼어요');
    });

    test(
      "409's own reason survives as the message shown to the trainer",
      () async {
        when(
          () => dio.post<Map<String, Object?>>(
            '/trainer/consultations/consult-1/accept',
            data: any(named: 'data'),
          ),
        ).thenThrow(
          _httpError(
            409,
            '/trainer/consultations/consult-1/accept',
            body: <String, Object?>{'detail': '이미 다른 트레이너가 담당 중인 회원입니다.'},
          ),
        );

        // The whole point of the 409 is its sentence — a generic network
        // error would leave the trainer with no idea why it failed.
        await expectLater(
          repo.accept('consult-1'),
          throwsA(
            isA<ValidationError>().having(
              (e) => e.message,
              'message',
              '이미 다른 트레이너가 담당 중인 회원입니다.',
            ),
          ),
        );
      },
    );

    test('a 404 stays a typed transport error', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/nope/accept',
          data: any(named: 'data'),
        ),
      ).thenThrow(_httpError(404, '/trainer/consultations/nope/accept'));

      await expectLater(repo.accept('nope'), throwsA(isA<NotFoundError>()));
    });

    test('ids are percent-encoded into the path', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/a%2Fb/accept',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(
          <String, Object?>{},
          '/trainer/consultations/a%2Fb/accept',
        ),
      );

      await repo.accept('a/b');

      verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/consultations/a%2Fb/accept',
          data: any(named: 'data'),
        ),
      ).called(1);
    });
  });

  group('consultationRepositoryProvider', () {
    test('demo mode exposes the seeded schedule inbox', () {
      final container = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_demoConfig)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(consultationRepositoryProvider),
        isA<DemoConsultationRepository>(),
      );
      // The demo console must look exactly as it does today — no inbox
      // row, no badge.
      expect(container.read(consultationInboxEnabledProvider), isTrue);
    });

    test('real-API mode resolves the Dio source', () {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_realConfig),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(consultationRepositoryProvider),
        isA<DioConsultationRepository>(),
      );
      expect(container.read(consultationInboxEnabledProvider), isTrue);
    });

    test('the demo badge count includes the seeded request', () async {
      final container = ProviderContainer(
        overrides: <Override>[appConfigProvider.overrideWithValue(_demoConfig)],
      );
      addTearDown(container.dispose);

      expect(await container.read(consultationPendingCountProvider.future), 2);
    });

    test('the pending badge keeps counting so a request that arrives while the '
        'trainer works elsewhere shows up (#917)', () async {
      var calls = 0;
      when(
        () => dio.get<Map<String, Object?>>(
          '/trainer/consultations/pending-count',
        ),
      ).thenAnswer((_) async {
        calls += 1;
        return _ok<Map<String, Object?>>(<String, Object?>{
          'count': calls,
        }, '/trainer/consultations/pending-count');
      });

      final emissions =
          await DioConsultationRepository(
                dio,
                pollInterval: const Duration(milliseconds: 5),
              )
              .watchPendingCount()
              .take(2)
              .toList()
              .timeout(const Duration(seconds: 1));

      expect(emissions, <int>[1, 2]);
    });

    test('the open inbox re-reads its own filter', () async {
      var calls = 0;
      when(
        () => dio.get<List<dynamic>>(
          '/trainer/consultations',
          queryParameters: <String, Object?>{
            'status': 'pending',
            'limit': consultationPageSize,
          },
        ),
      ).thenAnswer((_) async {
        calls += 1;
        return _ok<List<dynamic>>(<dynamic>[
          <String, Object?>{
            'id': 'consult-$calls',
            'member_id': 'm1',
            'member_name': '김하늘',
            'goal': 'fitness',
            'purpose': 'general',
            'preferred_date': '2026-08-20',
            'preferred_time': 'evening',
            'status': 'pending',
            'message': null,
            'created_at': '2026-08-19T09:00:00Z',
          },
        ], '/trainer/consultations');
      });

      final emissions = await DioConsultationRepository(
        dio,
        pollInterval: const Duration(milliseconds: 5),
      ).watch().take(2).toList().timeout(const Duration(seconds: 1));

      expect(emissions.map((rows) => rows.single.id).toList(), <String>[
        'consult-1',
        'consult-2',
      ]);
    });

    test('the demo source removes decided requests from pending', () async {
      final repo = DemoConsultationRepository();
      final request = (await repo.fetch()).firstWhere(
        (r) => r.id == 'demo-consultation-1',
      );

      await repo.accept(request.id);

      expect(
        (await repo.fetch()).map((r) => r.id),
        isNot(contains(request.id)),
      );
      expect(
        (await repo.fetch(
          status: 'all',
        )).firstWhere((r) => r.id == request.id).status,
        'accepted',
      );
    });

    test('the demo source books the slot the member picked (#1873)', () async {
      final scheduleRepository = _MockScheduleRepository();
      when(
        () => scheduleRepository.addSession(
          date: any(named: 'date'),
          clientName: any(named: 'clientName'),
          clientId: any(named: 'clientId'),
          time: any(named: 'time'),
          type: any(named: 'type'),
          durationMinutes: any(named: 'durationMinutes'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async {});
      final repo = DemoConsultationRepository(
        scheduleRepository: () => scheduleRepository,
      );
      final request = (await repo.fetch()).firstWhere(
        (r) => r.id == 'demo-consultation-1',
      );

      final result = await repo.accept(request.id);

      expect(result.scheduleCreated, isTrue);
      // 자리가 정한 시각·길이 그대로, 종류는 `1:1 PT` 다 — 코드 상수 30분이나
      // `상담` 종류를 지어내지 않는다.
      final DateTime start = request.slotStartsAt!;
      verify(
        () => scheduleRepository.addSession(
          date: ymd(start),
          clientName: request.memberName,
          clientId: request.memberId,
          time: '19:00',
          type: SessionType.personalTraining,
          durationMinutes: request.slotDurationMinutes!,
          note: request.message ?? '',
        ),
      ).called(1);
    });
  });
}
