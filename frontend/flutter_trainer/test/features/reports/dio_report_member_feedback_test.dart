/// 실서버 리포트가 회원 주간 피드백을 함께 읽는가. (#2286)
///
/// 리포트 ① 칸은 회원이 그 주에 낸 세 문항이다. 백엔드에는
/// `GET /trainer/clients/{id}/report/member-feedback` 가 있는데 실서버 저장소가
/// 부르지 않아, 데모에서만 채워지고 실서버에서는 언제나 "아직 받지 못함" 이었다.
///
/// 이 파일이 지키는 것:
///  * 본문과 **나란히** 부르고, 같은 주를 묻는다.
///  * 답이 있으면 도메인 값으로 옮긴다(컨디션·강도·통증·날짜·한 줄).
///  * 답이 없거나 이 요청만 실패하면 칸만 비고 리포트는 그대로 뜬다.
///  * 본문이 실패하면 피드백이 멀쩡해도 리포트는 오류다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_weekly_feedback.dart';

import '../../helpers/client_factory.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> _ok(Map<String, dynamic>? body, String path) =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: body,
    );

DioException _httpError(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

const String _reportPath = '/trainer/clients/m1/report';
const String _feedbackPath = '/trainer/clients/m1/report/member-feedback';

const Map<String, dynamic> _reportBody = <String, dynamic>{
  'week_start': '2026-09-14',
  'sessions_booked': 2,
  'sessions_done': 1,
  'completion_avg': 32,
};

/// 회원이 무릎 통증과 함께 `지쳤다·너무 힘들었다` 고 답한 주.
const Map<String, dynamic> _answered = <String, dynamic>{
  'week_start': '2026-09-14',
  'submitted': true,
  'condition': 'tired',
  'intensity': 'too_hard',
  'pain_area': '오른 무릎',
  'pain_on': '2026-09-17',
  'note': '3일차부터 힘들었어요',
  'submitted_at': '2026-09-21T09:30:00+09:00',
};

/// 서버가 "아직 안 냄" 을 알리는 모양 — 오류가 아니라 기본값이 채워진 200.
const Map<String, dynamic> _notSubmitted = <String, dynamic>{
  'week_start': '2026-09-14',
  'submitted': false,
  'condition': '',
  'intensity': '',
  'pain_area': '',
  'pain_on': '',
  'note': '',
  'submitted_at': null,
};

void main() {
  late _MockDio dio;
  late DioReportRepository repo;
  final client = makeClient(id: 'm1', name: '김민수');
  final weekStart = DateTime(2026, 9, 14);

  void stubReport(Future<Response<Map<String, dynamic>>> Function() answer) {
    when(
      () => dio.get<Map<String, dynamic>>(
        _reportPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) => answer());
  }

  void stubFeedback(Future<Response<Map<String, dynamic>>> Function() answer) {
    when(
      () => dio.get<Map<String, dynamic>>(
        _feedbackPath,
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) => answer());
  }

  setUp(() {
    dio = _MockDio();
    repo = DioReportRepository(dio);
  });

  group('요청', () {
    test('피드백을 본문과 같은 주로 묻는다', () async {
      stubReport(() async => _ok(_reportBody, _reportPath));
      stubFeedback(() async => _ok(_answered, _feedbackPath));

      await repo.watch(client: client, weekStart: weekStart).first;

      final Map<String, dynamic> query =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _feedbackPath,
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(query['week_start'], '2026-09-14');
    });

    test('본문 응답을 기다리지 않고 나란히 부른다', () async {
      // 본문이 아직 오지 않은 동안에도 피드백 요청은 이미 나가 있어야 한다 —
      // 차례로 부르면 리포트가 뜨는 시간이 두 요청을 더한 만큼 늘어난다.
      final Completer<Response<Map<String, dynamic>>> report =
          Completer<Response<Map<String, dynamic>>>();
      stubReport(() => report.future);
      stubFeedback(() async => _ok(_answered, _feedbackPath));

      final Future<Object?> pending = repo
          .watch(client: client, weekStart: weekStart)
          .first;
      await Future<void>.delayed(Duration.zero);

      verify(
        () => dio.get<Map<String, dynamic>>(
          _feedbackPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);

      report.complete(_ok(_reportBody, _reportPath));
      await pending;
    });

    test('회원 id 는 경로에 넣기 전에 인코딩한다', () async {
      const String oddId = 'user/jisu kim';
      final String encoded =
          '/trainer/clients/${Uri.encodeComponent(oddId)}/report';
      when(
        () => dio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((inv) async {
        final String p = inv.positionalArguments.first as String;
        return _ok(p.endsWith('/member-feedback') ? _answered : _reportBody, p);
      });

      await repo
          .watch(
            client: makeClient(id: oddId, name: '김지수'),
            weekStart: weekStart,
          )
          .first;

      verify(
        () => dio.get<Map<String, dynamic>>(
          '$encoded/member-feedback',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).called(1);
    });
  });

  group('답이 있는 주', () {
    test('세 문항·통증 날짜·한 줄이 리포트에 실린다', () async {
      stubReport(() async => _ok(_reportBody, _reportPath));
      stubFeedback(() async => _ok(_answered, _feedbackPath));

      final report = await repo
          .watch(client: client, weekStart: weekStart)
          .first;
      final MemberWeeklyFeedback? feedback = report.memberFeedback;

      expect(feedback, isNotNull);
      expect(feedback!.weekStart, DateTime(2026, 9, 14));
      expect(feedback.condition, WeekCondition.tired);
      expect(feedback.intensity, WeekIntensity.tooHard);
      expect(feedback.painArea, '오른 무릎');
      expect(feedback.painOn, DateTime(2026, 9, 17));
      expect(feedback.note, '3일차부터 힘들었어요');
      expect(feedback.needsAttention, isTrue);
      // 본문 수치도 함께 온다 — 피드백을 붙이며 본문을 잃지 않는다.
      expect(report.sessionsBooked, 2);
      expect(report.completionAvg, 32);
    });

    test('걱정할 것이 없는 답도 그대로 실린다', () async {
      stubReport(() async => _ok(_reportBody, _reportPath));
      stubFeedback(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'submitted': true,
          'condition': 'great',
          'intensity': 'right',
          'pain_area': '',
          'pain_on': '',
          'note': '',
        }, _feedbackPath),
      );

      final report = await repo
          .watch(client: client, weekStart: weekStart)
          .first;

      expect(report.memberFeedback?.condition, WeekCondition.great);
      expect(report.memberFeedback?.intensity, WeekIntensity.right);
      expect(report.memberFeedback?.hasPain, isFalse);
      expect(report.memberFeedback?.needsAttention, isFalse);
    });

    test('통증 부위 없이 온 날짜는 버린다', () async {
      stubReport(() async => _ok(_reportBody, _reportPath));
      stubFeedback(
        () async => _ok(<String, dynamic>{
          ..._answered,
          'pain_area': '   ',
          'pain_on': '2026-09-17',
        }, _feedbackPath),
      );

      final report = await repo
          .watch(client: client, weekStart: weekStart)
          .first;

      expect(report.memberFeedback?.hasPain, isFalse);
      expect(report.memberFeedback?.painOn, isNull);
    });

    test('읽지 못하는 통증 날짜는 부위만 남긴다', () async {
      stubReport(() async => _ok(_reportBody, _reportPath));
      stubFeedback(
        () async => _ok(<String, dynamic>{
          ..._answered,
          'pain_on': '어제',
        }, _feedbackPath),
      );

      final report = await repo
          .watch(client: client, weekStart: weekStart)
          .first;

      expect(report.memberFeedback?.painArea, '오른 무릎');
      expect(report.memberFeedback?.painOn, isNull);
    });
  });

  group('답이 없거나 읽을 수 없는 주 — 칸만 비고 리포트는 뜬다', () {
    // 안 낸 주와 읽지 못한 주는 가른다(#3246) — 읽지 못한 주를 `미응답` 으로
    // 그리면 답한 회원의 결과지에 `아직 받지 못했어요` 가 실린다.
    Future<void> expectEmptyFeedback(
      Future<Response<Map<String, dynamic>>> Function() feedback, {
      bool failed = true,
    }) async {
      stubReport(() async => _ok(_reportBody, _reportPath));
      stubFeedback(feedback);

      final report = await repo
          .watch(client: client, weekStart: weekStart)
          .first;

      expect(report.memberFeedback, isNull);
      expect(report.memberFeedbackFailed, failed);
      expect(report.sessionsBooked, 2);
    }

    test('submitted=false 는 답이 아니다', () async {
      await expectEmptyFeedback(
        () async => _ok(_notSubmitted, _feedbackPath),
        failed: false,
      );
    });

    test('submitted 가 빠진 응답도 답이 아니다', () async {
      await expectEmptyFeedback(
        () async => _ok(<String, dynamic>{
          'week_start': '2026-09-14',
          'condition': 'good',
          'intensity': 'right',
        }, _feedbackPath),
        failed: false,
      );
    });

    test('빈 본문', () async {
      await expectEmptyFeedback(() async => _ok(null, _feedbackPath));
    });

    test('404 — 옛 서버에 엔드포인트가 없다', () async {
      await expectEmptyFeedback(
        () async => throw _httpError(404, _feedbackPath),
      );
    });

    test('403 — 이 회원을 볼 권한이 없다', () async {
      await expectEmptyFeedback(
        () async => throw _httpError(403, _feedbackPath),
      );
    });

    test('500', () async {
      await expectEmptyFeedback(
        () async => throw _httpError(500, _feedbackPath),
      );
    });

    test('연결이 끊김', () async {
      await expectEmptyFeedback(
        () async => throw DioException(
          requestOptions: RequestOptions(path: _feedbackPath),
          type: DioExceptionType.connectionError,
        ),
      );
    });

    test('모르는 컨디션 값', () async {
      await expectEmptyFeedback(
        () async => _ok(<String, dynamic>{
          ..._answered,
          'condition': 'meh',
        }, _feedbackPath),
      );
    });

    test('모르는 강도 값', () async {
      await expectEmptyFeedback(
        () async => _ok(<String, dynamic>{
          ..._answered,
          'intensity': 'tooHard',
        }, _feedbackPath),
      );
    });

    test('문자열이 아닌 값', () async {
      await expectEmptyFeedback(
        () async => _ok(<String, dynamic>{
          ..._answered,
          'condition': 3,
          'intensity': null,
        }, _feedbackPath),
      );
    });

    test('응답 모양 자체가 다르다', () async {
      await expectEmptyFeedback(() async => throw TypeError());
    });
  });

  group('본문이 실패하면', () {
    test('피드백이 멀쩡해도 리포트는 오류다', () async {
      stubReport(() async => throw _httpError(500, _reportPath));
      stubFeedback(() async => _ok(_answered, _feedbackPath));

      await expectLater(
        repo.watch(client: client, weekStart: weekStart).first,
        throwsA(isA<ServerError>()),
      );
    });

    test('둘 다 실패해도 본문의 오류가 올라온다', () async {
      stubReport(() async => throw _httpError(404, _reportPath));
      stubFeedback(() async => throw _httpError(500, _feedbackPath));

      await expectLater(
        repo.watch(client: client, weekStart: weekStart).first,
        throwsA(isA<NotFoundError>()),
      );
    });
  });

  group('memberWeeklyFeedbackFromJson', () {
    test('서버가 돌려준 주를 믿는다', () {
      final MemberWeeklyFeedback? f = memberWeeklyFeedbackFromJson(
        _answered,
        DateTime(2026, 9, 16),
      );
      expect(f?.weekStart, DateTime(2026, 9, 14));
      // 제출일은 그 주의 일요일이다 — 카드 제목 줄이 이 날짜를 적는다.
      expect(f?.submittedOn, DateTime(2026, 9, 20));
    });

    test('주가 빠졌거나 깨졌으면 요청한 주의 월요일로 돌아간다', () {
      for (final Object? week in <Object?>[null, '', 'soon', 20260914]) {
        final MemberWeeklyFeedback? f = memberWeeklyFeedbackFromJson(
          <String, dynamic>{..._answered, 'week_start': week},
          DateTime(2026, 9, 17),
        );
        expect(f?.weekStart, DateTime(2026, 9, 14), reason: '$week');
      }
    });

    test('서버가 주 중간 날짜를 돌려줘도 월요일로 맞춘다', () {
      final MemberWeeklyFeedback? f = memberWeeklyFeedbackFromJson(
        <String, dynamic>{..._answered, 'week_start': '2026-09-18'},
        DateTime(2026, 9, 14),
      );
      expect(f?.weekStart, DateTime(2026, 9, 14));
    });

    test('모든 컨디션·강도 값을 읽는다', () {
      for (final WeekCondition c in WeekCondition.values) {
        for (final WeekIntensity i in WeekIntensity.values) {
          final MemberWeeklyFeedback? f = memberWeeklyFeedbackFromJson(
            <String, dynamic>{
              ..._answered,
              'condition': c.wire,
              'intensity': i.wire,
            },
            weekStart,
          );
          expect(f?.condition, c);
          expect(f?.intensity, i);
        }
      }
    });

    test('한 줄의 앞뒤 공백은 지운다', () {
      final MemberWeeklyFeedback? f = memberWeeklyFeedbackFromJson(
        <String, dynamic>{..._answered, 'note': '  무릎이 아팠어요 \n'},
        weekStart,
      );
      expect(f?.note, '무릎이 아팠어요');
    });

    test('submitted 가 문자열 "true" 여도 답으로 읽지 않는다', () {
      expect(
        memberWeeklyFeedbackFromJson(<String, dynamic>{
          ..._answered,
          'submitted': 'true',
        }, weekStart),
        isNull,
      );
    });
  });

  test('weeklyReportFromJson 은 피드백을 넘기지 않으면 비워 둔다', () {
    final report = weeklyReportFromJson(_reportBody, client);
    expect(report.memberFeedback, isNull);
  });
}
