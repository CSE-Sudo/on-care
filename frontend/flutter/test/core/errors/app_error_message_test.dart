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

  group('appErrorMessage — 나머지', () {
    test('화면이 준 문구를 그대로 돌려준다', () {
      for (final Object error in <Object>[
        const UnauthorizedError(detail: '토큰 만료'),
        const NotFoundError(detail: '없음'),
        const ServerError(statusCode: 500, detail: '서버 오류'),
        const NetworkError(),
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

  test('새 문구는 ko/en 이 모두 있고 서로 다르다', () {
    expect(ko.errorForbidden, isNotEmpty);
    expect(en.errorForbidden, isNotEmpty);
    expect(ko.errorForbidden, isNot(en.errorForbidden));
    expect(ko.errorRateLimited, isNot(en.errorRateLimited));
  });
}
