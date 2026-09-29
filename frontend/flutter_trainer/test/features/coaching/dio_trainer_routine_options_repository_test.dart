import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';

class _MockDio extends Mock implements Dio {}

Map<String, Object?> _optionsBody() => <String, Object?>{
  'analysis': <String, Object?>{
    'goal': '혈압',
    'sodium_today_mg': 2100,
    'sodium_over_target': true,
    'avg_completion_rate': 55,
    'latest_routine': '걷기',
    'note': '무릎 주의',
  },
  'plan_a': <String, Object?>{
    'key': 'A',
    'label': '회복',
    'total_minutes': 21,
    'intensity': '낮음',
    'exercises': <Object?>[
      <String, Object?>{'name': '걷기', 'minutes': 21, 'type': '유산소'},
    ],
    'reason': '회복',
    'rationale': '지속',
  },
  'plan_b': <String, Object?>{
    'key': 'B',
    'label': '강도',
    'total_minutes': 30,
    'intensity': '높음',
    'exercises': <Object?>[
      <String, Object?>{'name': '러닝', 'minutes': 30, 'type': '유산소'},
    ],
    'reason': '강도',
    'rationale': '운동량',
  },
  'generated_by': 'rule',
};

void main() {
  late _MockDio dio;
  late DioTrainerRoutineOptionsRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioTrainerRoutineOptionsRepository(dio);
  });

  test('고른 자료는 표 순서의 sources 로, 모두 끈 선택은 빈 목록으로 보낸다(#2587)', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/routine-options',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, Object?>>(
        requestOptions: RequestOptions(
          path: '/trainer/clients/m1/routine-options',
        ),
        statusCode: 200,
        data: _optionsBody(),
      ),
    );

    for (final (Set<RoutineContextSource> chosen, List<String> wire)
        in <(Set<RoutineContextSource>, List<String>)>[
          (
            <RoutineContextSource>{
              RoutineContextSource.weeklyFeedback,
              RoutineContextSource.consultMemo,
            },
            <String>['consult_memo', 'weekly_feedback'],
          ),
          (<RoutineContextSource>{}, <String>[]),
        ]) {
      await repo.generate(
        'm1',
        availableMinutes: null,
        intensityPreference: null,
        trainerNote: '',
        sources: chosen,
      );
      verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/routine-options',
          data: <String, Object?>{
            'available_minutes': null,
            'intensity_preference': null,
            'trainer_note': '',
            'sources': wire,
          },
          options: any(named: 'options'),
        ),
      ).called(1);
    }
  });

  test('generate POSTs the steering inputs and parses A/B', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/routine-options',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, Object?>>(
        requestOptions: RequestOptions(
          path: '/trainer/clients/m1/routine-options',
        ),
        statusCode: 200,
        data: _optionsBody(),
      ),
    );

    final o = await repo.generate(
      'm1',
      availableMinutes: 30,
      intensityPreference: 'moderate',
      trainerNote: '무릎 주의',
    );
    expect(o.planA.key, 'A');
    expect(o.planB.totalMinutes, 30);

    final captured = verify(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/routine-options',
        data: <String, Object?>{
          'available_minutes': 30,
          'intensity_preference': 'moderate',
          'trainer_note': '무릎 주의',
        },
        options: captureAny(named: 'options'),
      ),
    ).captured;

    // 전역 receiveTimeout(15초)으로는 생성이 끝나기 전에 앱이 포기한다 — 요청
    // 단위로 넉넉히 올렸는지 고정한다(#579).
    final options = captured.single as Options;
    expect(options.receiveTimeout, const Duration(seconds: 60));
  });

  test('surfaces a failure as AppError', () async {
    when(
      () => dio.post<Map<String, Object?>>(
        '/trainer/clients/m1/routine-options',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(
          path: '/trainer/clients/m1/routine-options',
        ),
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: RequestOptions(
            path: '/trainer/clients/m1/routine-options',
          ),
          statusCode: 404,
        ),
      ),
    );

    await expectLater(
      repo.generate(
        'm1',
        availableMinutes: 30,
        intensityPreference: 'moderate',
        trainerNote: '',
      ),
      throwsA(isA<AppError>()),
    );
  });

  test('encodes an opaque member id as one path segment', () async {
    const path = '/trainer/clients/member%2Fwith%3Freserved/routine-options';
    when(
      () => dio.post<Map<String, Object?>>(
        path,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, Object?>>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: _optionsBody(),
      ),
    );

    await repo.generate(
      'member/with?reserved',
      availableMinutes: 30,
      intensityPreference: 'moderate',
      trainerNote: '',
    );

    verify(
      () => dio.post<Map<String, Object?>>(
        path,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).called(1);
  });
}
