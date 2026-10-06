import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/errors/app_error_message.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 오류 → 화면 문구. 원인별 안내와 서버 사유, 화면 기본 문구의 우선순위.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  const String fallback = '저장하지 못했어요';

  group('한국어', () {
    test('연결 오류·타임아웃은 연결 안내다', () {
      expect(
        appErrorMessage(ko, const NetworkError(), fallback: fallback),
        ko.errorNetworkUnstable,
      );
      expect(ko.errorNetworkUnstable, contains('연결이 불안정합니다'));
    });

    test('사유 없는 5xx 는 서버 일시 문제 안내다', () {
      for (final int code in <int>[500, 502, 503, 504]) {
        expect(
          appErrorMessage(
            ko,
            ServerError(statusCode: code),
            fallback: fallback,
          ),
          ko.errorServerTemporary,
        );
      }
      expect(ko.errorServerTemporary, contains('서버에 일시적인 문제가 있어요'));
    });

    test('5xx 라도 서버가 사유를 주면 그 사유다', () {
      expect(
        appErrorMessage(
          ko,
          const ServerError(statusCode: 503, message: 'AI 서비스 점검 중입니다.'),
          fallback: fallback,
        ),
        'AI 서비스 점검 중입니다.',
      );
    });

    test('422 목록형(사유 없음)은 화면 기본 문구다', () {
      expect(
        appErrorMessage(ko, const ValidationError(), fallback: fallback),
        fallback,
      );
    });

    test('서버 사유가 있으면 그 사유다', () {
      expect(
        appErrorMessage(
          ko,
          const ValidationError(message: '현재 비밀번호가 일치하지 않습니다.'),
          fallback: fallback,
        ),
        '현재 비밀번호가 일치하지 않습니다.',
      );
      expect(
        appErrorMessage(
          ko,
          const ServerError(statusCode: 409, message: '이미 처리된 요청입니다.'),
          fallback: fallback,
        ),
        '이미 처리된 요청입니다.',
      );
    });

    test('사유 없는 4xx·알 수 없는 오류·AppError 가 아닌 오류는 기본 문구다', () {
      for (final Object error in <Object>[
        const ServerError(statusCode: 409),
        const NotFoundError(),
        const ForbiddenError(),
        const UnknownError(),
        const CancelledError(),
        StateError('x'),
        const FormatException('bad json'),
      ]) {
        expect(
          appErrorMessage(ko, error, fallback: fallback),
          fallback,
          reason: '$error',
        );
      }
    });

    test('null 도 기본 문구다', () {
      expect(appErrorMessage(ko, null, fallback: fallback), fallback);
    });
  });

  group('영어', () {
    test('연결 오류·5xx 는 영어 안내다', () {
      expect(
        appErrorMessage(en, const NetworkError(), fallback: 'Save failed'),
        en.errorNetworkUnstable,
      );
      expect(
        appErrorMessage(
          en,
          const ServerError(statusCode: 500),
          fallback: 'Save failed',
        ),
        en.errorServerTemporary,
      );
    });

    test('한국어 서버 사유는 영어 화면에 새지 않는다', () {
      expect(
        appErrorMessage(
          en,
          const ValidationError(message: '현재 비밀번호가 일치하지 않습니다.'),
          fallback: 'Save failed',
        ),
        'Save failed',
      );
      expect(
        appErrorMessage(
          en,
          const ServerError(statusCode: 503, message: '점검 중입니다.'),
          fallback: 'Save failed',
        ),
        en.errorServerTemporary,
      );
    });

    test('영어 안내에 한글이 없다', () {
      for (final String text in <String>[
        en.errorNetworkUnstable,
        en.errorServerTemporary,
      ]) {
        expect(RegExp(r'[가-힣]').hasMatch(text), isFalse, reason: text);
      }
    });
  });
}
