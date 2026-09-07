import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_invite_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_invite.dart';

class _MockDio extends Mock implements Dio {}

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

/// 담당 요청은 **요청이지 등록이 아니다**(#919). 저장소가 그 계약을 지키는지 —
/// 어떤 실패를 어떤 타입으로 옮기는지, 데모에서 진입점을 감추는지 — 를 본다.
void main() {
  late _MockDio dio;
  late DioClientInviteRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioClientInviteRepository(dio);
  });

  group('invite', () {
    test('sends the member id and a trimmed message', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/client-invites',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'tci-1',
          'member_id': 'm1',
          'member_name': '김민수',
          'member_email': 'minsu@oncare.com',
          'message': '함께 해요',
          'status': 'pending',
          'created_at': '2026-08-19T09:00:00Z',
        }, '/trainer/client-invites'),
      );

      final invite = await repo.invite('m1', message: '  함께 해요  ');

      expect(invite.status, ClientInviteStatus.pending);
      verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/client-invites',
          data: <String, Object?>{'member_id': 'm1', 'message': '함께 해요'},
        ),
      ).called(1);
    });

    test('a blank message is left out entirely', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/client-invites',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'tci-1',
          'member_id': 'm1',
          'member_name': '김민수',
          'member_email': 'minsu@oncare.com',
          'status': 'pending',
          'created_at': '2026-08-19T09:00:00Z',
        }, '/trainer/client-invites'),
      );

      await repo.invite('m1', message: '   ');

      verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/client-invites',
          data: <String, Object?>{'member_id': 'm1'},
        ),
      ).called(1);
    });

    test('keeps the server\'s reason for a refused invite (409)', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/trainer/client-invites',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        _httpError(
          409,
          '/trainer/client-invites',
          body: <String, Object?>{'detail': '이미 다른 트레이너가 담당 중인 회원이에요.'},
        ),
      );

      // 어느 쪽 이유인지는 서버만 안다 — 그 문장이 트레이너가 다음에 할 일을 정한다.
      await expectLater(
        repo.invite('m1'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            '이미 다른 트레이너가 담당 중인 회원이에요.',
          ),
        ),
      );
    });
  });

  test('the sent list parses statuses', () async {
    when(
      () => dio.get<List<dynamic>>(
        '/trainer/client-invites',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok<List<dynamic>>(<dynamic>[
        <String, Object?>{
          'id': 'tci-1',
          'member_id': 'm1',
          'member_name': '김민수',
          'member_email': 'a@b.com',
          'status': 'pending',
          'created_at': '2026-08-19T09:00:00Z',
        },
        <String, Object?>{
          'id': 'tci-2',
          'member_id': 'm2',
          'member_name': '이지수',
          'member_email': 'c@d.com',
          'status': 'accepted',
          'created_at': '2026-08-18T09:00:00Z',
        },
      ], '/trainer/client-invites'),
    );

    final rows = await repo.listSent(status: 'all');

    expect(rows.map((r) => r.status).toList(), <ClientInviteStatus>[
      ClientInviteStatus.pending,
      ClientInviteStatus.accepted,
    ]);
    expect(rows.first.isPending, isTrue);
  });

  test('cancelling an already-decided invite surfaces the reason', () async {
    when(
      () => dio.delete<Map<String, Object?>>('/trainer/client-invites/tci-1'),
    ).thenThrow(
      _httpError(
        409,
        '/trainer/client-invites/tci-1',
        body: <String, Object?>{'detail': '이미 처리된 요청이에요.'},
      ),
    );

    await expectLater(repo.cancel('tci-1'), throwsA(isA<ValidationError>()));
  });

  group('provider', () {
    test('demo mode resolves the local (immediate-connect) source', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demoConfig),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      // 데모도 회원 ID로 찾아 연결할 수 있다 — 성별·나이를 트레이너가 입력
      // 하는 등록 폼은 어느 모드에도 없다.
      expect(container.read(clientInvitesEnabledProvider), isTrue);
      final repo = container.read(clientInviteRepositoryProvider);
      expect(repo, isA<DemoClientInviteRepository>());
      expect(repo.connectsImmediately, isTrue);
    });

    test('real-API mode resolves the Dio source but hides the entry', () {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_realConfig),
          dioProvider.overrideWithValue(Dio()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(clientInvitesEnabledProvider), isFalse);
      final repo = container.read(clientInviteRepositoryProvider);
      expect(repo, isA<DioClientInviteRepository>());
      // 실 API 는 회원의 수락을 기다리는 요청만 보낸다 — 즉시 연결하지 않는다.
      expect(repo.connectsImmediately, isFalse);
    });
  });

  group('DemoClientInviteRepository', () {
    late AppDatabase db;
    late DemoClientInviteRepository demo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
      demo = DemoClientInviteRepository(db);
    });
    tearDown(() => db.close());

    test('finds a prospective member by their demo member id', () async {
      // 대소문자는 같은 ID다 — 실 서비스의 `func.lower(User.id)` 비교와 같다.
      final found = await demo.lookup('USER-8F2A41C9D6E3');

      expect(found.name, '이수아');
      expect(found.canInvite, isTrue);
      // 등록 전 확인 화면이 쓰는 신체 정보·운동 목표 — 회원이 이미 등록해
      // 둔 값이지 지금 지어낸 값이 아니다.
      expect(found.gender, 'female');
      expect(found.age, isNotNull);
      expect(found.goal, '체지방 감량');
    });

    test('두 데모 회원은 서로 다른 신체정보·운동목표를 갖는다', () async {
      final soo = await demo.lookup('user-8f2a41c9d6e3');
      final jun = await demo.lookup('user-1c7b93f04a58');

      expect(jun.name, '박준서');
      expect(soo.gender, isNot(jun.gender));
      expect(soo.goal, isNot(jun.goal));
    });

    test('an already-linked member id reports coachedByMe', () async {
      // 이미 담당 중인 김민수(seed-client-1)의 회원 ID다 — 회원 앱 MY 탭이
      // 데모 모드에서 보여주는 것과 같은 값이다.
      final found = await demo.lookup('user-7d4e9a2c5f18');

      expect(found.name, '김민수');
      // 로스터 행의 id(seed-client-1)가 아니라 조회에 쓴 회원 ID가 그대로
      // 나와야 한다 — 백엔드의 User.id 기반 응답 계약과 같은 모양이어야 한다.
      expect(found.memberId, 'user-7d4e9a2c5f18');
      expect(found.hasTrainer, isTrue);
      expect(found.coachedByMe, isTrue);
      expect(found.canInvite, isFalse);
    });

    test('an unknown member id is not found', () {
      expect(demo.lookup('user-no-such-member'), throwsA(isA<NotFoundError>()));
    });

    test(
      'invite connects immediately with the prospect\'s real profile',
      () async {
        final found = await demo.lookup('user-1c7b93f04a58');
        final invite = await demo.invite(found.memberId);

        expect(invite.status, ClientInviteStatus.accepted);

        final clients = await demo.lookup('user-1c7b93f04a58');
        // 두 번째 조회는 이미 연결된 상태를 본다 — 중복 연결이 막힌다.
        expect(clients.coachedByMe, isTrue);

        final row = await (db.select(
          db.trainerClients,
        )..where((t) => t.id.equals(found.memberId))).getSingle();
        // 트레이너가 지금 입력한 값이 아니라 회원이 이미 등록해 둔 실제 값이다.
        expect(row.gender, 'male');
        expect(row.age, isNotNull);
      },
    );
  });
}
