/// 주간 피드백이 저장소를 오가는 길. (#2232)
///
/// 세 층을 한 파일에서 본다 — 서버 응답을 읽는 규칙(DTO), 실서버로 나가는
/// 요청(Dio), 그리고 데모가 그 자리를 대신하는 방식(Mock). 세 층이 같은 규칙을
/// 지켜야 하는 곳이 하나 있다: **아픈 곳을 적지 않으면 아픈 날도 없다.** 한
/// 층만 놓치면 트레이너 화면이 "(빈칸) 이 아팠다" 를 그린다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';

import '../../helpers/fixed_clock.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/me/coach/weekly-feedback';

Response<T> _ok<T>(T body) => Response<T>(
  requestOptions: RequestOptions(path: _path),
  statusCode: 200,
  data: body,
);

DioException _httpError(int status) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
  ),
);

Map<String, Object?> _wire({
  String weekStart = '2026-09-14',
  bool submitted = true,
  String condition = 'tired',
  String intensity = 'too_hard',
  String painArea = '',
  String painOn = '',
  String note = '',
  String? submittedAt,
}) => <String, Object?>{
  'week_start': weekStart,
  'submitted': submitted,
  'condition': condition,
  'intensity': intensity,
  'pain_area': painArea,
  'pain_on': painOn,
  'note': note,
  'submitted_at': submittedAt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('응답 읽기', () {
    test('낸 주는 두 문항과 함께 온다', () {
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(_wire());

      expect(f.submitted, isTrue);
      expect(f.weekStart, DateTime(2026, 9, 14));
      expect(f.condition, WeekCondition.tired);
      expect(f.intensity, WeekIntensity.tooHard);
    });

    test('안 낸 주는 빈 답이다 — 오류가 아니다', () {
      // 없는 것을 404 로 만들면 화면의 그 칸이 통째로 사라진다.
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(
        _wire(submitted: false, condition: '', intensity: ''),
      );

      expect(f.submitted, isFalse);
      expect(f.condition, isNull);
      expect(f.weekStart, DateTime(2026, 9, 14));
    });

    test('한쪽 문항만 읽히면 안 낸 주로 둔다', () {
      // 반쯤 그린 답은 회원에게 "이미 보냈다" 고 말하면서 트레이너에게는
      // 아무것도 주지 않는다.
      expect(
        memberWeeklyFeedbackFromJson(_wire(intensity: 'sideways')).submitted,
        isFalse,
      );
      expect(
        memberWeeklyFeedbackFromJson(_wire(condition: 'sleepy')).submitted,
        isFalse,
      );
    });

    test('냈다고 적혀 있어도 답이 없으면 안 낸 주다', () {
      expect(
        memberWeeklyFeedbackFromJson(
          _wire(condition: '', intensity: ''),
        ).submitted,
        isFalse,
      );
    });

    test('아픈 곳과 날을 함께 읽는다', () {
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(
        _wire(painArea: '오른 무릎', painOn: '2026-09-17'),
      );

      expect(f.painArea, '오른 무릎');
      expect(f.painOn, DateTime(2026, 9, 17));
      expect(f.hasPain, isTrue);
    });

    test('아픈 곳이 비면 날짜도 버린다', () {
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(
        _wire(painOn: '2026-09-17'),
      );

      expect(f.hasPain, isFalse);
      expect(f.painOn, isNull);
    });

    test('아픈 날이 날짜가 아니면 통증만 남는다', () {
      // 날짜 한 칸 때문에 회원이 보고한 통증을 통째로 잃지 않는다.
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(
        _wire(painArea: '허리', painOn: '언젠가'),
      );

      expect(f.painArea, '허리');
      expect(f.painOn, isNull);
    });

    test('앞뒤 공백은 떼고 읽는다', () {
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(
        _wire(painArea: '  오른 무릎  ', note: '  계단이 힘들었어요  '),
      );

      expect(f.painArea, '오른 무릎');
      expect(f.note, '계단이 힘들었어요');
    });

    test('공백만 적은 아픈 곳은 통증이 아니다', () {
      expect(memberWeeklyFeedbackFromJson(_wire(painArea: '   ')).hasPain,
          isFalse);
    });

    test('낸 시각이 있으면 읽는다', () {
      final MemberWeeklyFeedback f = memberWeeklyFeedbackFromJson(
        _wire(submittedAt: '2026-09-20T21:12:00'),
      );

      expect(f.submittedAt, DateTime(2026, 9, 20, 21, 12));
    });

    test('낸 시각이 없어도 답은 남는다', () {
      expect(memberWeeklyFeedbackFromJson(_wire()).submittedAt, isNull);
    });
  });

  group('실서버', () {
    late _MockDio dio;
    late DioMemberCoachRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioMemberCoachRepository(dio);
    });

    test('주를 주지 않으면 서버가 지난 주로 읽는다', () async {
      // 주 경계 계산이 앱과 서버 두 곳에 있으면 한쪽만 틀리는 날이 온다.
      when(
        // 빈 질의를 적어 두는 것이 이 시험의 요지다 — 앱이 주를 실어 보내면
        // 이 대역은 답하지 않는다.
        // ignore: avoid_redundant_argument_values
        () => dio.get<Map<String, Object?>>(_path, queryParameters: null),
      ).thenAnswer((_) async => _ok<Map<String, Object?>>(_wire()));

      final MemberWeeklyFeedback f = await repo.fetchWeeklyFeedback();

      expect(f.condition, WeekCondition.tired);
    });

    test('주를 주면 그 주를 묻는다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: <String, Object?>{'week_start': '2026-09-14'},
        ),
      ).thenAnswer((_) async => _ok<Map<String, Object?>>(_wire()));

      await repo.fetchWeeklyFeedback(weekStart: DateTime(2026, 9, 14));

      verify(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: <String, Object?>{'week_start': '2026-09-14'},
        ),
      ).called(1);
    });

    test('담당이 없으면 빈 답이다 — 화면이 칸을 숨긴다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(_httpError(404));

      final MemberWeeklyFeedback f = await repo.fetchWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
      );

      expect(f.submitted, isFalse);
      expect(f.weekStart, DateTime(2026, 9, 14));
    });

    test('다른 오류는 그대로 올라온다', () async {
      when(
        () => dio.get<Map<String, Object?>>(
          _path,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(_httpError(500));

      expect(
        () => repo.fetchWeeklyFeedback(weekStart: DateTime(2026, 9, 14)),
        throwsA(isA<AppError>()),
      );
    });

    test('보낼 때 두 문항은 저장값으로 나간다', () async {
      Map<String, Object?>? sent;
      when(
        () => dio.put<Map<String, Object?>>(_path, data: any(named: 'data')),
      ).thenAnswer((Invocation i) async {
        sent = i.namedArguments[#data] as Map<String, Object?>;
        return _ok<Map<String, Object?>>(_wire());
      });

      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.bad,
        intensity: WeekIntensity.tooEasy,
      );

      expect(sent!['week_start'], '2026-09-14');
      expect(sent!['condition'], 'bad');
      expect(sent!['intensity'], 'too_easy');
    });

    test('아픈 곳이 없으면 날짜도 보내지 않는다', () async {
      Map<String, Object?>? sent;
      when(
        () => dio.put<Map<String, Object?>>(_path, data: any(named: 'data')),
      ).thenAnswer((Invocation i) async {
        sent = i.namedArguments[#data] as Map<String, Object?>;
        return _ok<Map<String, Object?>>(_wire());
      });

      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.ok,
        intensity: WeekIntensity.right,
        painOn: DateTime(2026, 9, 17),
      );

      expect(sent!['pain_area'], '');
      expect(sent!['pain_on'], '');
    });

    test('아픈 곳을 적었으면 날짜도 함께 나간다', () async {
      Map<String, Object?>? sent;
      when(
        () => dio.put<Map<String, Object?>>(_path, data: any(named: 'data')),
      ).thenAnswer((Invocation i) async {
        sent = i.namedArguments[#data] as Map<String, Object?>;
        return _ok<Map<String, Object?>>(_wire());
      });

      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.ok,
        intensity: WeekIntensity.right,
        painArea: '  오른 무릎 ',
        painOn: DateTime(2026, 9, 17),
        note: '  계단이 힘들었어요 ',
      );

      expect(sent!['pain_area'], '오른 무릎');
      expect(sent!['pain_on'], '2026-09-17');
      expect(sent!['note'], '계단이 힘들었어요');
    });

    test('보내고 나면 서버가 돌려준 답을 읽는다', () async {
      when(
        () => dio.put<Map<String, Object?>>(_path, data: any(named: 'data')),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(
          _wire(condition: 'great', intensity: 'right'),
        ),
      );

      final MemberWeeklyFeedback saved = await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.bad,
        intensity: WeekIntensity.tooHard,
      );

      expect(saved.condition, WeekCondition.great);
      expect(saved.submitted, isTrue);
    });

    test('보내지 못하면 던진다 — 화면이 시트를 닫지 않는다', () async {
      when(
        () => dio.put<Map<String, Object?>>(_path, data: any(named: 'data')),
      ).thenThrow(_httpError(404));

      expect(
        () => repo.saveWeeklyFeedback(
          weekStart: DateTime(2026, 9, 14),
          condition: WeekCondition.ok,
          intensity: WeekIntensity.right,
        ),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('데모', () {
    setUp(() => useFixedKstDate(DateTime(2026, 9, 23, 9)));

    test('켜자마자 직전 주 답이 하나 있다', () async {
      // 빈 화면으로 시작하면 MY 탭의 `보낸 주간 피드백` 이 안내문 하나로만
      // 보여, 회원이 무엇을 보내는 것인지 알 수 없다.
      final MemberWeeklyFeedback f = await MockMemberCoachRepository()
          .fetchWeeklyFeedback();

      expect(f.submitted, isTrue);
      expect(f.weekStart, DateTime(2026, 9, 14));
      expect(f.hasPain, isTrue);
      expect(f.needsAttention, isTrue);
    });

    test('답이 없는 주는 빈 답이다', () async {
      final MemberWeeklyFeedback f = await MockMemberCoachRepository()
          .fetchWeeklyFeedback(weekStart: DateTime(2026, 8, 3));

      expect(f.submitted, isFalse);
      expect(f.weekStart, DateTime(2026, 8, 3));
    });

    test('주 가운데 날로 물어도 그 주 월요일 답을 준다', () async {
      final MemberWeeklyFeedback f = await MockMemberCoachRepository()
          .fetchWeeklyFeedback(weekStart: DateTime(2026, 9, 17));

      expect(f.submitted, isTrue);
      expect(f.weekStart, DateTime(2026, 9, 14));
    });

    test('보낸 답이 그대로 남는다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();

      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 7),
        condition: WeekCondition.great,
        intensity: WeekIntensity.right,
        note: '한 주 내내 잘 잤어요',
      );
      final MemberWeeklyFeedback f = await repo.fetchWeeklyFeedback(
        weekStart: DateTime(2026, 9, 7),
      );

      expect(f.condition, WeekCondition.great);
      expect(f.note, '한 주 내내 잘 잤어요');
      expect(f.submittedAt, isNotNull);
    });

    test('같은 주에 다시 내면 덮어쓴다 — 마지막 말 하나다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();

      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.bad,
        intensity: WeekIntensity.tooHard,
      );
      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.good,
        intensity: WeekIntensity.right,
      );
      final MemberWeeklyFeedback f = await repo.fetchWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
      );

      expect(f.condition, WeekCondition.good);
      expect(f.intensity, WeekIntensity.right);
    });

    test('아픈 곳 없이 날짜만 보내면 날짜도 남지 않는다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository();

      await repo.saveWeeklyFeedback(
        weekStart: DateTime(2026, 9, 14),
        condition: WeekCondition.ok,
        intensity: WeekIntensity.right,
        painOn: DateTime(2026, 9, 17),
      );

      expect(
        (await repo.fetchWeeklyFeedback(weekStart: DateTime(2026, 9, 14)))
            .painOn,
        isNull,
      );
    });

    test('담당이 끊기면 읽을 답이 없다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        linked: () => false,
      );

      expect((await repo.fetchWeeklyFeedback()).submitted, isFalse);
    });

    test('담당이 끊기면 보낼 수도 없다 — 받는 사람이 없다', () async {
      final MockMemberCoachRepository repo = MockMemberCoachRepository(
        linked: () => false,
      );

      expect(
        () => repo.saveWeeklyFeedback(
          weekStart: DateTime(2026, 9, 14),
          condition: WeekCondition.ok,
          intensity: WeekIntensity.right,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
