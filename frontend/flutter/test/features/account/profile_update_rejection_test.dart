/// 프로필 저장 거절 사유 — #2639.
///
/// 서버(`PUT /users/me`)는 다른 계정이 쓰는 이메일이면 409, 있던 연락처를 비우면
/// 422 로 거절한다. 예전에는 이 둘이 화면까지 "저장에 실패했어요" 한 가지로
/// 뭉개졌다. 여기서는 **실서버 경로와 데모 경로가 같은 사유로** 올라오는지 본다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/account/data/repositories/dio_account_repository.dart';
import 'package:oncare/features/account/domain/entities/profile_update_rejected.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';

import '../../helpers/mock_account_repository.dart';

Matcher _rejectedWith(ProfileUpdateRejection reason) => throwsA(
  isA<ProfileUpdateRejected>().having(
    (ProfileUpdateRejected e) => e.reason,
    'reason',
    reason,
  ),
);

/// 실서버처럼 정해 둔 상태 코드·본문으로 요청을 **예외로** 거절하는 대역.
class _RejectingServer extends Interceptor {
  _RejectingServer(this.status, this.body);

  final int status;
  final Object? body;
  int calls = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls++;
    handler.reject(
      DioException.badResponse(
        statusCode: status,
        requestOptions: options,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: status,
          data: body,
        ),
      ),
    );
  }
}

DioAccountRepository _serverRepo(int status, Object? body) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
    ..interceptors.add(_RejectingServer(status, body));
  addTearDown(dio.close);
  return DioAccountRepository(dio);
}

void main() {
  group('ProfileUpdateRejected.fromResponse', () {
    test('409 는 이메일 중복이다', () {
      expect(
        ProfileUpdateRejected.fromResponse(409, <String, Object?>{
          'detail': '이미 사용 중인 이메일입니다.',
        })?.reason,
        ProfileUpdateRejection.emailTaken,
      );
    });

    test('409 는 본문이 없어도 이메일 중복이다', () {
      expect(
        ProfileUpdateRejected.fromResponse(409, null)?.reason,
        ProfileUpdateRejection.emailTaken,
      );
    });

    test('422 가 문장이면 연락처 비움이다', () {
      expect(
        ProfileUpdateRejected.fromResponse(422, <String, Object?>{
          'detail': '전화번호는 비울 수 없습니다.',
        })?.reason,
        ProfileUpdateRejection.phoneRequired,
      );
    });

    test('422 가 필드 검증 목록이면 형식 오류다', () {
      expect(
        ProfileUpdateRejected.fromResponse(422, <String, Object?>{
          'detail': <Object?>[
            <String, Object?>{
              'type': 'value_error',
              'loc': <Object?>['body', 'email'],
              'msg': 'value is not a valid email address',
            },
          ],
        })?.reason,
        ProfileUpdateRejection.invalid,
      );
    });

    test('422 에 본문이 없으면 형식 오류다', () {
      expect(
        ProfileUpdateRejected.fromResponse(422, null)?.reason,
        ProfileUpdateRejection.invalid,
      );
    });

    test('그 밖의 상태 코드는 거절 사유가 아니다', () {
      for (final int? status in <int?>[null, 200, 400, 401, 404, 500, 503]) {
        expect(
          ProfileUpdateRejected.fromResponse(status, null),
          isNull,
          reason: 'status=$status',
        );
      }
    });
  });

  group('DioAccountRepository.updateProfile — 실서버 예외', () {
    test('409 는 이메일 중복으로 올린다', () async {
      final repo = _serverRepo(409, <String, Object?>{
        'detail': '이미 사용 중인 이메일입니다.',
      });
      await expectLater(
        repo.updateProfile(email: 'trainer@oncare.com'),
        _rejectedWith(ProfileUpdateRejection.emailTaken),
      );
    });

    test('문장 422 는 연락처 비움으로 올린다', () async {
      final repo = _serverRepo(422, <String, Object?>{
        'detail': '전화번호는 비울 수 없습니다.',
      });
      await expectLater(
        repo.updateProfile(phone: ''),
        _rejectedWith(ProfileUpdateRejection.phoneRequired),
      );
    });

    test('목록 422 는 형식 오류로 올린다', () async {
      final repo = _serverRepo(422, <String, Object?>{
        'detail': <Object?>[
          <String, Object?>{
            'type': 'string_too_long',
            'loc': <Object?>['body', 'name'],
          },
        ],
      });
      await expectLater(
        repo.updateProfile(name: 'x'),
        _rejectedWith(ProfileUpdateRejection.invalid),
      );
    });

    test('500 은 거절 사유가 아니라 원래 예외 그대로 올린다', () async {
      final repo = _serverRepo(500, null);
      await expectLater(
        repo.updateProfile(name: '김민수'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('DioAccountRepository.updateProfile — 데모 인터셉터', () {
    late AppDatabase db;
    late Dio dio;
    late DioAccountRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
      repo = DioAccountRepository(dio);
    });

    tearDown(() async {
      await db.close();
      dio.close();
    });

    test('데모 세계의 다른 계정 이메일이면 이메일 중복으로 올린다', () async {
      await expectLater(
        repo.updateProfile(email: 'trainer@oncare.com'),
        _rejectedWith(ProfileUpdateRejection.emailTaken),
      );
    });

    test('거절된 저장은 아무것도 바꾸지 않는다', () async {
      await expectLater(
        repo.updateProfile(name: '바뀐 이름', email: 'jisu@oncare.com'),
        _rejectedWith(ProfileUpdateRejection.emailTaken),
      );
      final UserProfile after = await repo.fetchProfile();
      expect(after.email, 'minsu@oncare.com');
      expect(after.name, '김민수');
    });

    test('자기 이메일 그대로면 저장된다', () async {
      final UserProfile saved = await repo.updateProfile(
        name: '김민수2',
        email: 'minsu@oncare.com',
      );
      expect(saved.name, '김민수2');
      expect(saved.email, 'minsu@oncare.com');
    });

    test('아무도 쓰지 않는 새 이메일이면 저장된다', () async {
      final UserProfile saved = await repo.updateProfile(
        email: 'minsu.new@oncare.com',
      );
      expect(saved.email, 'minsu.new@oncare.com');
    });

    test('있던 연락처를 비우면 연락처 비움으로 올린다', () async {
      await expectLater(
        repo.updateProfile(phone: ''),
        _rejectedWith(ProfileUpdateRejection.phoneRequired),
      );
      expect((await repo.fetchProfile()).phone, '010-1234-5678');
    });
  });

  group('LocalApiInterceptor PUT /users/me — 응답 모양', () {
    late AppDatabase db;
    late Dio dio;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..interceptors.add(LocalApiInterceptor(db, Logger(level: Level.off)));
    });

    tearDown(() async {
      await db.close();
      dio.close();
    });

    Future<Response<Object?>> put(Map<String, Object?> body) async {
      try {
        return await dio.put<Object?>('/users/me', data: body);
      } on DioException catch (e) {
        return e.response!;
      }
    }

    test('다른 계정 이메일은 서버와 같은 409 와 문장 detail', () async {
      final res = await put(<String, Object?>{'email': 'trainer@oncare.com'});
      expect(res.statusCode, 409);
      expect((res.data! as Map)['detail'], isA<String>());
    });

    test('대소문자·앞뒤 공백이 달라도 같은 이메일로 본다', () async {
      final res = await put(<String, Object?>{'email': ' Trainer@OnCare.com '});
      expect(res.statusCode, 409);
    });

    test('담당 회원 명단의 이메일도 409 다', () async {
      final res = await put(<String, Object?>{'email': 'hayun@oncare.demo'});
      expect(res.statusCode, 409);
    });

    test('있던 연락처 비움은 422 와 문장 detail', () async {
      final res = await put(<String, Object?>{'phone': ''});
      expect(res.statusCode, 422);
      expect((res.data! as Map)['detail'], isA<String>());
    });

    test('연락처를 다른 번호로 바꾸는 것은 된다', () async {
      final res = await put(<String, Object?>{'phone': '010-9876-5432'});
      expect(res.statusCode, 200);
      expect((res.data! as Map)['phone'], '010-9876-5432');
    });
  });

  group('MockAccountRepository — 쓰이는 이메일', () {
    test('쓰이는 이메일로 바꾸면 이메일 중복으로 거절한다', () async {
      final repo = MockAccountRepository(
        takenEmails: const <String>{'trainer@oncare.com'},
      );
      await expectLater(
        repo.updateProfile(email: 'TRAINER@oncare.com'),
        _rejectedWith(ProfileUpdateRejection.emailTaken),
      );
      expect((await repo.fetchProfile()).email, 'minsu@oncare.com');
    });

    test('기본은 쓰이는 이메일이 없어 지금처럼 저장된다', () async {
      final repo = MockAccountRepository();
      final UserProfile saved = await repo.updateProfile(
        email: 'trainer@oncare.com',
      );
      expect(saved.email, 'trainer@oncare.com');
    });

    test('있던 연락처를 비우면 연락처 비움으로 거절한다', () async {
      final repo = MockAccountRepository();
      await expectLater(
        repo.updateProfile(phone: ''),
        _rejectedWith(ProfileUpdateRejection.phoneRequired),
      );
    });

    test('처음부터 연락처가 없던 회원은 빈 연락처로 저장된다', () async {
      final repo = MockAccountRepository(
        profile: const UserProfile(
          id: 'u1',
          name: '소셜 가입자',
          email: 'social@oncare.com',
        ),
      );
      final UserProfile saved = await repo.updateProfile(phone: '');
      expect(saved.phone, '');
    });
  });
}
