import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/dio_member_coach_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T body) => Response<T>(
  requestOptions: RequestOptions(path: '/me/coach/sessions'),
  statusCode: 200,
  data: body,
);

Map<String, Object?> _row({
  Object? id = 'sched-1',
  Object? date = '2026-08-20',
  Object? time = '10:00',
  Object? type = '1:1 PT',
  Object? minutes = 50,
  Object? status = '예정',
  Object? note = '',
  Object? program = const <Object?>[],
}) => <String, Object?>{
  'id': id,
  'date': date,
  'time': time,
  'client_name': '김민수',
  'type': type,
  'duration_minutes': minutes,
  'status': status,
  'note': note,
  'program': program,
};

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const AppConfig _real = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: false,
);

void main() {
  group('DTO', () {
    test('세션 한 건을 읽는다', () {
      final CoachSession session = coachSessionFromJson(_row());

      expect(session.id, 'sched-1');
      expect(session.date, DateTime(2026, 8, 20));
      expect(session.time, '10:00');
      expect(session.type, '1:1 PT');
      expect(session.durationMinutes, 50);
      expect(session.isUpcoming, isTrue);
    });

    test('완료된 세션은 예정이 아니다', () {
      expect(coachSessionFromJson(_row(status: '완료')).isUpcoming, isFalse);
    });

    test('완료 메모와 운동 프로그램을 읽는다', () {
      final CoachSession session = coachSessionFromJson(
        _row(
          status: '완료',
          note: '오른쪽 어깨 가동 범위를 확인해 주세요.',
          program: <Object?>[
            <String, Object?>{
              'name': '숄더 프레스',
              'sets': 4,
              'reps': '12회',
              'weight': '10kg',
            },
          ],
        ),
      );

      expect(session.isDone, isTrue);
      expect(session.note, '오른쪽 어깨 가동 범위를 확인해 주세요.');
      expect(session.program.single.name, '숄더 프레스');
      expect(session.program.single.sets, 4);
      // 옛 행에 남은 문자열도 숫자로 되짚어 읽는다 (#1310).
      expect(session.program.single.reps, 12);
      expect(session.program.single.weight, 10);
    });

    test('날짜가 깨져도 던지지 않는다', () {
      // 한 행 때문에 일정 전체가 사라지면 안 된다 — 화면이 null 을 걸러낸다.
      final CoachSession session = coachSessionFromJson(
        _row(date: 'not-a-date'),
      );

      expect(session.date, isNull);
    });

    test('시간 필드가 없어도 빈 문자열로 둔다', () {
      expect(coachSessionFromJson(_row(time: null)).time, '');
    });
  });

  group('저장소', () {
    test('실모드는 세션 엔드포인트를 읽는다', () async {
      final dio = _MockDio();
      when(
        () => dio.get<List<dynamic>>('/me/coach/sessions'),
      ).thenAnswer((_) async => _ok<List<dynamic>>(<dynamic>[_row()]));

      final List<CoachSession> sessions = await DioMemberCoachRepository(
        dio,
      ).fetchSessions();

      expect(sessions.single.id, 'sched-1');
      verify(() => dio.get<List<dynamic>>('/me/coach/sessions')).called(1);
    });

    test('데모도 담당 일정을 준다 — 끝난 수업과 다음 예정이 함께 온다 (#2659)', () async {
      final List<CoachSession> sessions = await MockMemberCoachRepository()
          .fetchSessions();

      expect(sessions.where((CoachSession s) => s.isDone), isNotEmpty);
      expect(sessions.where((CoachSession s) => s.isUpcoming), hasLength(1));
    });
  });

  group('provider 분기', () {
    test('데모는 목 저장소를 쓰고 네트워크로 나가지 않는다', () async {
      final dio = _MockDio();
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_demo),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(coachSessionsProvider.future), isEmpty);
      verifyNever(() => dio.get<List<dynamic>>(any()));
    });

    test('실모드는 백엔드에서 읽는다', () async {
      final dio = _MockDio();
      when(
        () => dio.get<List<dynamic>>('/me/coach/sessions'),
      ).thenAnswer((_) async => _ok<List<dynamic>>(<dynamic>[_row()]));
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_real),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final List<CoachSession> sessions = await container.read(
        coachSessionsProvider.future,
      );

      expect(sessions, hasLength(1));
    });
  });
}
