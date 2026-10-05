/// 탈퇴 요청의 본인 확인(#3039) — 실 서버 본문·오류 매핑과 데모 규칙.
///
/// 확인 거절은 모두 400 이고 토큰은 아직 유효하다. 리포지토리가 그것을
/// [ReauthRejected] 로 구분해 줘야 화면이 로그아웃하지 않고 창 안에 알린다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/my/data/trainer_account_repository.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/trainer/me';

DioException _error(int status, Object? body) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
    data: body,
  ),
);

Map<String, Object?> _detail(String code) => <String, Object?>{
  'detail': <String, Object?>{'code': code, 'message': '서버 문장'},
};

void main() {
  group('DioTrainerAccountRepository.deleteAccount', () {
    late _MockDio dio;
    late DioTrainerAccountRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioTrainerAccountRepository(dio);
    });

    void answerOk() {
      when(
        () => dio.delete<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: _path),
          statusCode: 200,
        ),
      );
    }

    Map<String, Object?> sentBody() =>
        verify(
              () => dio.delete<Map<String, dynamic>>(
                _path,
                data: captureAny(named: 'data'),
              ),
            ).captured.single
            as Map<String, Object?>;

    test('비밀번호 계정은 사유와 현재 비밀번호를 함께 보낸다', () async {
      answerOk();

      await repo.deleteAccount(
        reauth: const PasswordReauth('current-pw-1'),
        reasons: const <String>['other'],
      );

      final Map<String, Object?> body = sentBody();
      expect(body['current_password'], 'current-pw-1');
      expect(body['reasons'], <String>['other']);
      expect(body.containsKey('social_provider'), isFalse);
      expect(body.containsKey('social_token'), isFalse);
    });

    test('소셜 계정은 제공자와 토큰을 보내고 비밀번호 칸은 싣지 않는다', () async {
      answerOk();

      await repo.deleteAccount(
        reauth: const SocialReauth(provider: 'kakao', token: 'tok'),
      );

      final Map<String, Object?> body = sentBody();
      expect(body['social_provider'], 'kakao');
      expect(body['social_token'], 'tok');
      expect(body['reasons'], isEmpty);
      expect(body.containsKey('current_password'), isFalse);
    });

    for (final MapEntry<String, ReauthFailure> c in <String, ReauthFailure>{
      'reauth_required': ReauthFailure.required,
      'invalid_current_password': ReauthFailure.invalidPassword,
      'invalid_reauth': ReauthFailure.invalidSocial,
    }.entries) {
      test('400 ${c.key} → ReauthRejected(${c.value.name})', () async {
        when(
          () =>
              dio.delete<Map<String, dynamic>>(_path, data: any(named: 'data')),
        ).thenThrow(_error(400, _detail(c.key)));

        await expectLater(
          repo.deleteAccount(reauth: const PasswordReauth('x')),
          throwsA(
            isA<ReauthRejected>().having((e) => e.reason, 'reason', c.value),
          ),
        );
      });
    }

    test('코드가 없는 400 은 예전처럼 ValidationError 다', () async {
      when(
        () => dio.delete<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenThrow(_error(400, <String, Object?>{'detail': '잘못된 요청'}));

      await expectLater(
        repo.deleteAccount(reauth: const PasswordReauth('x')),
        throwsA(
          isA<ValidationError>()
              .having((e) => e is ReauthRejected, 'is ReauthRejected', isFalse)
              .having((e) => e.message, 'message', '잘못된 요청'),
        ),
      );
    });

    test('429 는 한도 초과 오류로 나간다 — 확인 거절이 아니다', () async {
      when(
        () => dio.delete<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenThrow(_error(429, <String, Object?>{'detail': '잠시 후 다시 시도해 주세요.'}));

      await expectLater(
        repo.deleteAccount(reauth: const PasswordReauth('x')),
        throwsA(isA<RateLimitedError>()),
      );
    });

    test('ReauthFailure.fromCode 는 모르는 코드를 null 로 둔다', () {
      expect(ReauthFailure.fromCode('something_else'), isNull);
      expect(ReauthFailure.fromCode(null), isNull);
    });
  });

  group('MockTrainerAccountRepository.deleteAccount (데모)', () {
    const MockTrainerAccountRepository repo = MockTrainerAccountRepository();

    Matcher rejectedWith(ReauthFailure reason) => throwsA(
      isA<ReauthRejected>().having((e) => e.reason, 'reason', reason),
    );

    /// 확인을 통과했다 — 데모에는 지울 계정이 없다는 안내로 끝난다.
    final Matcher passedReauth = throwsA(
      isA<ValidationError>().having(
        (e) => e is ReauthRejected,
        'is ReauthRejected',
        isFalse,
      ),
    );

    test('빈 비밀번호는 reauth_required 와 같다', () async {
      await expectLater(
        repo.deleteAccount(reauth: const PasswordReauth('')),
        rejectedWith(ReauthFailure.required),
      );
    });

    test('데모 로그인처럼 비어 있지 않은 비밀번호는 확인을 통과한다', () async {
      await expectLater(
        repo.deleteAccount(reauth: const PasswordReauth('any-pw-1')),
        passedReauth,
      );
    });

    test('데모 소셜 토큰(demo-<provider>-token)만 통과한다', () async {
      await expectLater(
        repo.deleteAccount(
          reauth: const SocialReauth(
            provider: 'google',
            token: 'demo-google-token',
          ),
        ),
        passedReauth,
      );
      await expectLater(
        repo.deleteAccount(
          reauth: const SocialReauth(
            provider: 'google',
            token: 'demo-kakao-token',
          ),
        ),
        rejectedWith(ReauthFailure.invalidSocial),
      );
      await expectLater(
        repo.deleteAccount(
          reauth: const SocialReauth(provider: 'kakao', token: ''),
        ),
        rejectedWith(ReauthFailure.required),
      );
    });

    test('데모 빌드는 탈퇴를 열지 않는다', () {
      expect(repo.supportsDeletion, isFalse);
    });
  });
}
