import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/program_draft_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_editor_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

const String _base = '/trainer/programs';

Map<String, Object?> _draftJson({
  String id = 'pgm-1',
  String name = '체중 감량 프로그램',
  List<Map<String, Object?>> sessions = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'id': id,
  'name': name,
  'goal': '체지방 감량',
  'period': '8주',
  'memo': '주 3회',
  'sessions': sessions,
  'created_at': '2026-08-14T09:00:00Z',
  'updated_at': '2026-08-14T09:00:00Z',
};

Response<T> _ok<T>(T data, {String path = _base}) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

DioException _httpError(int status) => DioException(
  requestOptions: RequestOptions(path: _base),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _base),
    statusCode: status,
  ),
);

ProgramEditorState _editorDraft({
  String name = '체중 감량 프로그램',
  List<ProgramExerciseDraft> exercises = const <ProgramExerciseDraft>[],
}) => ProgramEditorState(
  name: name,
  goal: '체지방 감량',
  period: '8주',
  memo: '주 3회',
  sessions: <ProgramSessionDraft>[
    ProgramSessionDraft(id: 'session-1', name: '세션 A', exercises: exercises),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioTrainerProgramDraftRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioTrainerProgramDraftRepository(dio);
  });

  group('저장 형식 변환', () {
    test('편집기가 지원하는 값이 하나도 빠지지 않고 실린다', () {
      final payload = programDraftToJson(
        _editorDraft(
          exercises: <ProgramExerciseDraft>[
            ProgramExerciseDraft(
              id: 'exercise-2',
              name: '레그프레스',
              date: DateTime(2026, 8, 24),
              sets: 4,
              weight: 60.5,
              intensity: 'high',
              memo: '무릎 각도 확인',
              source: 'ai',
            ),
          ],
        ),
      );

      expect(payload['name'], '체중 감량 프로그램');
      final session =
          (payload['sessions']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(session['name'], '세션 A');
      final exercise =
          (session['exercises']! as List<Object?>).single!
              as Map<String, Object?>;
      // AI 제안인지 트레이너가 넣은 것인지의 구분이 그대로 나간다.
      expect(exercise['source'], 'ai');
      expect(exercise['date'], '2026-08-24');
      expect(exercise['sets'], 4);
      expect(exercise['weight'], 60.5);
      expect(exercise['intensity'], 'high');
      // 근력은 세트·중량으로만 잰다 — 시간은 싣지 않는다 (#1276).
      expect(exercise['duration'], isNull);
      expect(exercise['memo'], '무릎 각도 확인');
    });

    test('서버가 모르는 유형·출처는 초안을 통째로 날리지 않고 기본값으로 눕는다', () {
      final payload = programDraftToJson(
        _editorDraft(
          exercises: const <ProgramExerciseDraft>[
            ProgramExerciseDraft(
              id: 'exercise-2',
              name: '레그프레스',
              type: 'Strength',
              source: 'import',
            ),
          ],
        ),
      );
      final exercise =
          (((payload['sessions']! as List<Object?>).single!
                          as Map<String, Object?>)['exercises']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      expect(exercise['type'], '근력');
      expect(exercise['source'], 'trainer');
    });

    test('빈 운동 이름은 서버가 거절하므로 자리표시자로 바뀐다', () {
      final payload = programDraftToJson(
        _editorDraft(
          exercises: const <ProgramExerciseDraft>[
            ProgramExerciseDraft(id: 'exercise-2', name: '   '),
          ],
        ),
      );
      final exercise =
          (((payload['sessions']! as List<Object?>).single!
                          as Map<String, Object?>)['exercises']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      expect(exercise['name'], '-');
    });
  });

  group('DioTrainerProgramDraftRepository', () {
    test('list 는 요약만 읽는다', () async {
      when(() => dio.get<List<dynamic>>(_base)).thenAnswer(
        (_) async => _ok<List<dynamic>>(<dynamic>[
          <String, Object?>{
            'id': 'pgm-1',
            'name': '체중 감량',
            'goal': '체지방 감량',
            'period': '8주',
            'session_count': 1,
            'exercise_count': 3,
            'updated_at': '2026-08-14T09:00:00Z',
          },
        ]),
      );

      final drafts = await repo.list();
      expect(drafts.single.id, 'pgm-1');
      expect(drafts.single.exerciseCount, 3);
    });

    test('create 는 편집기 payload 를 그대로 보내고 저장본을 읽는다', () async {
      Map<String, Object?>? sent;
      when(
        () => dio.post<Map<String, Object?>>(_base, data: any(named: 'data')),
      ).thenAnswer((invocation) async {
        sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
            .cast<String, Object?>();
        return _ok<Map<String, Object?>>(_draftJson());
      });

      final saved = await repo.create(programDraftToJson(_editorDraft()));
      expect(sent!['name'], '체중 감량 프로그램');
      expect(saved.id, 'pgm-1');
    });

    test('update 는 열려 있는 초안을 덮어쓴다', () async {
      when(
        () => dio.put<Map<String, Object?>>(
          '$_base/pgm-1',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(_draftJson(name: '수정본')),
      );

      final saved = await repo.update(
        'pgm-1',
        programDraftToJson(_editorDraft(name: '수정본')),
      );
      expect(saved.name, '수정본');
    });

    test('다시 읽은 초안이 편집기 상태로 복원된다', () async {
      when(() => dio.get<Map<String, Object?>>('$_base/pgm-1')).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(
          _draftJson(
            sessions: <Map<String, Object?>>[
              <String, Object?>{
                'id': 'session-1',
                'name': '세션 A',
                'exercises': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'exercise-2',
                'name': '레그프레스',
                // 예전 초안은 자유 문자열로 저장돼 있다 — 숫자만 되짚어
                // 읽는다 (#1276).
                'sets': '4',
                'weight': '60kg',
                'memo': '무릎 각도 확인',
                'type': '근력',
                'source': 'ai',
              },
                ],
              },
            ],
          ),
          path: '$_base/pgm-1',
        ),
      );

      final state = (await repo.read(
        'pgm-1',
      )).toEditorState(fallbackSessionName: '세션 A');
      expect(state.name, '체중 감량 프로그램');
      expect(state.period, '8주');
      expect(state.sessions.single.name, '세션 A');
      final exercise = state.sessions.single.exercises.single;
      expect(exercise.name, '레그프레스');
      expect(exercise.sets, 4);
      expect(exercise.weight, 60.0);
      expect(exercise.source, 'ai');
      // 복원한 초안은 기존 배정·일정 등록 경로에 그대로 쓸 수 있다.
      expect(state.supportsAssignment, isTrue);
    });

    test('남의 초안은 타입 있는 오류로 올라온다', () {
      when(
        () => dio.get<Map<String, Object?>>('$_base/pgm-1'),
      ).thenThrow(_httpError(404));
      expect(repo.read('pgm-1'), throwsA(isA<AppError>()));
    });
  });

  group('저장소 선택', () {
    ProviderContainer containerFor({
      required bool useMockApi,
      required List<Override> extraOverrides,
    }) {
      final container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost/v1',
              useMockApi: useMockApi,
            ),
          ),
          ...extraOverrides,
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('데모는 브라우저 로컬에 저장한다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = containerFor(
        useMockApi: true,
        extraOverrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      expect(
        container.read(trainerProgramDraftRepositoryProvider),
        isA<LocalTrainerProgramDraftRepository>(),
      );
    });

    test('실 API 모드는 백엔드를 쓴다', () {
      final container = containerFor(
        useMockApi: false,
        extraOverrides: <Override>[dioProvider.overrideWithValue(dio)],
      );
      expect(
        container.read(trainerProgramDraftRepositoryProvider),
        isA<DioTrainerProgramDraftRepository>(),
      );
    });

    test('로컬 저장소도 저장 → 목록 → 재조회 → 수정을 지원한다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalTrainerProgramDraftRepository(prefs);

      final created = await repository.create(
        programDraftToJson(
          _editorDraft(
            exercises: const <ProgramExerciseDraft>[
              ProgramExerciseDraft(id: 'exercise-2', name: '레그프레스'),
            ],
          ),
        ),
      );
      expect((await repository.list()).single.exerciseCount, 1);
      expect((await repository.read(created.id)).name, '체중 감량 프로그램');

      await repository.update(
        created.id,
        programDraftToJson(_editorDraft(name: '수정본')),
      );
      expect((await repository.read(created.id)).name, '수정본');

      await repository.delete(created.id);
      expect(await repository.list(), isEmpty);
    });
  });
}
