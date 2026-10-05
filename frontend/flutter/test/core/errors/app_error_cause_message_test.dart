import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/errors/app_error_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/app_error_state_for.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 오류 화면의 설명 줄이 원인을 말한다. (#3140)
///
/// 연결이 끊겨도, 서버가 잠시 내려가도, 동의 문제로 403 이 나도 같은 문구였다.
/// 회원은 [다시 시도] 가 의미 있는지 알 수 없었다 — 원인마다 할 일이 다르므로
/// 문구도 달라야 한다.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  DioException dio(DioExceptionType type, {int? status, Object? body}) {
    final RequestOptions options = RequestOptions(path: '/v1/x');
    return DioException(
      requestOptions: options,
      type: type,
      response: status == null
          ? null
          : Response<Object?>(
              requestOptions: options,
              statusCode: status,
              data: body,
            ),
    );
  }

  group('appErrorCauseMessage — 원인별', () {
    for (final AppLocalizations l in <AppLocalizations>[ko, en]) {
      final String lang = l.localeName;

      test('[$lang] 연결 끊김·시간 초과', () {
        expect(appErrorCauseMessage(l, const NetworkError()), l.errorNetwork);
        expect(
          appErrorCauseMessage(l, TimeoutException('slow')),
          l.errorNetwork,
        );
      });

      test('[$lang] 5xx 서버 오류', () {
        expect(
          appErrorCauseMessage(l, const ServerError(statusCode: 503)),
          l.errorServer,
        );
      });

      test('[$lang] 401 로그인 만료', () {
        expect(
          appErrorCauseMessage(l, const UnauthorizedError()),
          l.authSessionExpired,
        );
      });

      test('[$lang] 403 권한·동의', () {
        expect(
          appErrorCauseMessage(l, const ForbiddenError()),
          l.errorForbidden,
        );
      });

      test('[$lang] 429 요청 한도', () {
        expect(
          appErrorCauseMessage(l, const RateLimitedError()),
          l.errorRateLimited,
        );
      });

      test('[$lang] 422 사유 없는 검증 오류', () {
        expect(
          appErrorCauseMessage(l, const ValidationError(statusCode: 422)),
          l.errorInvalidRequest,
        );
      });

      test('[$lang] 원인을 가릴 수 없으면 null', () {
        for (final Object? error in <Object?>[
          null,
          const NotFoundError(),
          const ServerError(statusCode: 409),
          const ServerError(),
          const CancelledError(),
          const UnknownError(),
          StateError('boom'),
        ]) {
          expect(appErrorCauseMessage(l, error), isNull, reason: '$error');
        }
      });
    }

    test('네트워크·서버·403·429·422 문구가 서로 다르다', () {
      for (final AppLocalizations l in <AppLocalizations>[ko, en]) {
        final List<String?> messages = <String?>[
          appErrorCauseMessage(l, const NetworkError()),
          appErrorCauseMessage(l, const ServerError(statusCode: 500)),
          appErrorCauseMessage(l, const ForbiddenError()),
          appErrorCauseMessage(l, const RateLimitedError()),
          appErrorCauseMessage(l, const ValidationError(statusCode: 422)),
          appErrorCauseMessage(l, const UnauthorizedError()),
        ];
        expect(
          messages.toSet(),
          hasLength(messages.length),
          reason: l.localeName,
        );
      }
    });

    test('한국어 화면의 422 는 서버 사유를 보인다', () {
      expect(
        appErrorCauseMessage(
          ko,
          const ValidationError(statusCode: 422, detail: '날짜 형식이 아닙니다.'),
        ),
        '날짜 형식이 아닙니다.',
      );
      // 영어 화면은 한국어 사유 대신 앱 문구다.
      expect(
        appErrorCauseMessage(
          en,
          const ValidationError(statusCode: 422, detail: '날짜 형식이 아닙니다.'),
        ),
        en.errorInvalidRequest,
      );
    });

    test('영어 문구에는 한글이 없다', () {
      for (final String text in <String>[
        en.errorNetwork,
        en.errorServer,
        en.errorInvalidRequest,
      ]) {
        expect(RegExp(r'[가-힣]').hasMatch(text), isFalse, reason: text);
      }
    });
  });

  group('감싸지 않은 DioException 도 같은 규칙', () {
    test('연결 오류·시간 초과는 연결 안내다', () {
      for (final DioExceptionType type in <DioExceptionType>[
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          appErrorCauseMessage(ko, dio(type)),
          ko.errorNetwork,
          reason: '$type',
        );
      }
    });

    test('응답 상태 코드로 가른다', () {
      expect(
        appErrorCauseMessage(
          ko,
          dio(DioExceptionType.badResponse, status: 502),
        ),
        ko.errorServer,
      );
      expect(
        appErrorCauseMessage(
          ko,
          dio(DioExceptionType.badResponse, status: 429),
        ),
        ko.errorRateLimited,
      );
      expect(
        appErrorCauseMessage(
          ko,
          dio(
            DioExceptionType.badResponse,
            status: 403,
            body: <String, Object?>{'detail': '데이터 공유 동의가 필요합니다.'},
          ),
        ),
        '데이터 공유 동의가 필요합니다.',
      );
      expect(
        appErrorMessage(
          ko,
          dio(DioExceptionType.badResponse, status: 404),
          fallback: '화면 문구',
        ),
        '화면 문구',
      );
    });
  });

  group('appErrorStateFor', () {
    Future<void> pump(
      WidgetTester tester, {
      required Object? error,
      String? message,
      Locale locale = const Locale('ko'),
      VoidCallback? onRetry,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => appErrorStateFor(
                context,
                key: const Key('state'),
                error: error,
                title: '불러오지 못했어요',
                message: message,
                onRetry: onRetry ?? () {},
                retryKey: const Key('retry'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('제목은 화면 문구, 설명은 원인 문구다', (WidgetTester tester) async {
      await pump(tester, error: const NetworkError(), message: '화면 설명');

      expect(find.text('불러오지 못했어요'), findsOneWidget);
      expect(find.text(ko.errorNetwork), findsOneWidget);
      // 원인을 알면 화면 설명보다 원인이 앞선다.
      expect(find.text('화면 설명'), findsNothing);
    });

    testWidgets('원인을 모르면 화면이 준 설명으로 떨어진다', (WidgetTester tester) async {
      await pump(tester, error: StateError('boom'), message: '화면 설명');

      expect(find.text('화면 설명'), findsOneWidget);
    });

    testWidgets('원인도 설명도 없으면 제목만 남는다 — 지금 모양 그대로', (WidgetTester tester) async {
      await pump(tester, error: StateError('boom'));

      final AppErrorState state = tester.widget<AppErrorState>(
        find.byKey(const Key('state')),
      );
      expect(state.message, isNull);
      expect(state.title, '불러오지 못했어요');
    });

    testWidgets('버튼은 [다시 시도] 이고 누르면 재시도한다', (WidgetTester tester) async {
      int retried = 0;
      await pump(
        tester,
        error: const ServerError(statusCode: 503),
        onRetry: () => retried++,
      );

      expect(find.text(ko.actionRetry), findsOneWidget);
      expect(find.text(ko.errorServer), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry')));
      expect(retried, 1);
    });

    testWidgets('영어 화면은 영어 원인 문구다', (WidgetTester tester) async {
      await pump(
        tester,
        error: const ServerError(statusCode: 500),
        locale: const Locale('en'),
      );

      expect(find.text(en.errorServer), findsOneWidget);
      expect(find.text(en.actionRetry), findsOneWidget);
    });
  });

  test('회원 앱의 오류 상태는 모두 오류 객체를 받는 경로로 만든다', () {
    // 공용 위젯을 직접 만들면 원인 문구를 건너뛴다. 새 화면이 그 길로 돌아가지
    // 않게, 생성 함수 밖에서 [AppErrorState] 를 만드는 곳이 없음을 확인한다.
    final List<String> offenders = <String>[
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('app_error_state_for.dart') &&
            entity.readAsStringSync().contains('AppErrorState('))
          entity.path,
    ];
    expect(offenders, isEmpty);
  });
}
