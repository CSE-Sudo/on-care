import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/errors/app_error_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 403·429·검증 오류의 공통 문구. (#2859)
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  const String fallback = '화면 문구';

  group('appErrorMessage — 403', () {
    test('사유가 없으면 권한·동의 안내다', () {
      expect(
        appErrorMessage(ko, const ForbiddenError(), fallback: fallback),
        ko.errorForbidden,
      );
      expect(
        appErrorMessage(en, const ForbiddenError(), fallback: fallback),
        en.errorForbidden,
      );
    });

    test('한국어 화면은 서버 사유를 보인다', () {
      expect(
        appErrorMessage(
          ko,
          const ForbiddenError(detail: '데이터 공유 동의가 필요합니다.'),
          fallback: fallback,
        ),
        '데이터 공유 동의가 필요합니다.',
      );
    });

    test('영어 화면은 한국어 사유 대신 앱 문구다', () {
      expect(
        appErrorMessage(
          en,
          const ForbiddenError(detail: '데이터 공유 동의가 필요합니다.'),
          fallback: fallback,
        ),
        en.errorForbidden,
      );
    });

    test('로그인을 다시 하라고 하지 않는다', () {
      final String text = appErrorMessage(
        ko,
        const ForbiddenError(),
        fallback: fallback,
      );
      expect(text, isNot(contains('로그인')));
    });
  });

  group('appErrorMessage — 429', () {
    test('잠시 뒤 다시 시도를 안내한다', () {
      expect(
        appErrorMessage(ko, const RateLimitedError(), fallback: fallback),
        ko.errorRateLimited,
      );
      expect(ko.errorRateLimited, contains('잠시 뒤 다시 시도'));
    });

    test('서버 사유가 있어도 행동 안내를 쓴다', () {
      expect(
        appErrorMessage(
          ko,
          const RateLimitedError(detail: 'Too Many Requests'),
          fallback: fallback,
        ),
        ko.errorRateLimited,
      );
    });

    test('영어 화면도 같은 뜻의 영어 문구다', () {
      expect(
        appErrorMessage(en, const RateLimitedError(), fallback: fallback),
        en.errorRateLimited,
      );
    });
  });

  group('appErrorMessage — 400·422', () {
    test('한국어 화면은 서버 사유를 보인다', () {
      expect(
        appErrorMessage(
          ko,
          const ValidationError(statusCode: 422, detail: '연락처는 비울 수 없습니다.'),
          fallback: fallback,
        ),
        '연락처는 비울 수 없습니다.',
      );
    });

    test('영어 화면은 화면이 준 문구다', () {
      expect(
        appErrorMessage(
          en,
          const ValidationError(statusCode: 422, detail: '연락처는 비울 수 없습니다.'),
          fallback: 'Check the value',
        ),
        'Check the value',
      );
    });

    test('사유가 없으면 화면이 준 문구다', () {
      expect(
        appErrorMessage(
          ko,
          const ValidationError(statusCode: 400),
          fallback: fallback,
        ),
        fallback,
      );
    });
  });

  group('appErrorMessage — 원인을 가릴 수 없는 오류', () {
    test('화면이 준 문구를 그대로 돌려준다', () {
      for (final Object error in <Object>[
        const NotFoundError(detail: '없음'),
        // 409 같은 5xx 가 아닌 서버 오류는 화면마다 뜻이 달라 화면 문구다.
        const ServerError(statusCode: 409, detail: '충돌'),
        const ServerError(),
        const CancelledError(),
        const UnknownError(),
        StateError('boom'),
      ]) {
        expect(
          appErrorMessage(ko, error, fallback: fallback),
          fallback,
          reason: '$error',
        );
      }
    });
  });

  group('appErrorMessage — 원인별 문구 (#3140)', () {
    test('연결 끊김·시간 초과는 연결 확인 안내다', () {
      expect(
        appErrorMessage(ko, const NetworkError(), fallback: fallback),
        ko.errorNetwork,
      );
      expect(
        appErrorMessage(en, const NetworkError(), fallback: fallback),
        en.errorNetwork,
      );
    });

    test('5xx 는 서버 일시 문제 안내다', () {
      for (final int code in <int>[500, 502, 503, 504]) {
        expect(
          appErrorMessage(
            ko,
            ServerError(statusCode: code, detail: '서버 오류'),
            fallback: fallback,
          ),
          ko.errorServer,
          reason: '$code',
        );
      }
    });

    test('401 은 다시 로그인 안내다', () {
      expect(
        appErrorMessage(
          ko,
          const UnauthorizedError(detail: '토큰 만료'),
          fallback: fallback,
        ),
        ko.authSessionExpired,
      );
    });
  });
  test('새 문구는 ko/en 이 모두 있고 서로 다르다', () {
    expect(ko.errorForbidden, isNotEmpty);
    expect(en.errorForbidden, isNotEmpty);
    expect(ko.errorForbidden, isNot(en.errorForbidden));
    expect(ko.errorRateLimited, isNot(en.errorRateLimited));
  });
}
