/// 트레이너 동의 저장소와 동의 항목 규칙 — #2819.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/features/auth/data/repositories/consent_repositories.dart';
import 'package:oncare_trainer/features/auth/domain/entities/signup_consent.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, Object?>> _ok(Map<String, Object?> body) =>
    Response<Map<String, Object?>>(
      requestOptions: RequestOptions(path: '/users/me/consents'),
      statusCode: 200,
      data: body,
    );

void main() {
  group('TrainerSignupConsent', () {
    test('필수는 약관·처리방침·만 14세 — 건강정보 항목은 없다', () {
      expect(TrainerSignupConsent.required, <String>{
        'terms',
        'privacy',
        'age14',
      });
      expect(TrainerSignupConsent.kinds, isNot(contains('health')));
      expect(TrainerSignupConsent.required, isNot(contains('marketing')));
    });

    test('필수가 하나라도 빠지면 거짓', () {
      expect(
        TrainerSignupConsent.hasAllRequired(<String>{
          'terms',
          'privacy',
          'age14',
        }),
        isTrue,
      );
      for (final String missing in TrainerSignupConsent.required) {
        final Set<String> checked = <String>{...TrainerSignupConsent.required}
          ..remove(missing);
        expect(
          TrainerSignupConsent.hasAllRequired(checked),
          isFalse,
          reason: missing,
        );
      }
    });

    test('보낼 목록은 화면 순서이고 모르는 값은 뺀다', () {
      expect(
        TrainerSignupConsent.toPayload(<String>{
          'marketing',
          'age14',
          'health',
          'terms',
          'privacy',
        }),
        <String>['terms', 'privacy', 'age14', 'marketing'],
      );
      expect(TrainerSignupConsent.toPayload(<String>{}), isEmpty);
    });
  });

  group('MockConsentRepository', () {
    const MockConsentRepository repo = MockConsentRepository();

    test('필수를 다 주면 남은 동의가 없다', () async {
      expect(await repo.submit(<String>['terms', 'privacy', 'age14']), isFalse);
    });

    test('필수가 빠지면 서버처럼 거절한다', () async {
      await expectLater(
        repo.submit(<String>['terms', 'privacy']),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DioConsentRepository', () {
    late _MockDio dio;
    late DioConsentRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioConsentRepository(dio);
    });

    test('체크한 목록을 consents 로 보내고 남은 동의 여부를 읽는다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/users/me/consents',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, Object?>{
          'consent_required': false,
          'consent_pending': <String>[],
        }),
      );

      final bool still = await repo.submit(<String>[
        'terms',
        'privacy',
        'age14',
      ]);

      expect(still, isFalse);
      final Object? sent = verify(
        () => dio.post<Map<String, Object?>>(
          '/users/me/consents',
          data: captureAny(named: 'data'),
        ),
      ).captured.single;
      expect(sent, <String, Object?>{
        'consents': <String>['terms', 'privacy', 'age14'],
      });
    });

    test('서버가 아직 남았다고 하면 참', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/users/me/consents',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok(<String, Object?>{
          'consent_required': true,
          'consent_pending': <String>['privacy'],
        }),
      );

      expect(await repo.submit(<String>['terms', 'age14']), isTrue);
    });

    test('422 거절은 그대로 던진다', () async {
      when(
        () => dio.post<Map<String, Object?>>(
          '/users/me/consents',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/users/me/consents'),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/users/me/consents'),
            statusCode: 422,
          ),
        ),
      );

      await expectLater(
        repo.submit(<String>['terms']),
        throwsA(isA<DioException>()),
      );
    });
  });
}
