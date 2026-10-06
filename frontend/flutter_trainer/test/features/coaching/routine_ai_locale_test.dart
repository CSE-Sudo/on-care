// AI 운동 추천의 근거·기본 이름·데모 문구가 화면 언어를 따르는지 (#2301).
//
// 한국어 문구는 바뀌지 않았음을 함께 고정한다 — 영어를 더하면서 기존 화면이
// 달라지면 안 된다.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_suggestion_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

final AppLocalizations _ko = lookupAppLocalizations(const Locale('ko'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

/// 한글 음절이 하나라도 있는지.
final RegExp _hangul = RegExp('[가-힣]');

/// 번역하지 않는 계약값(유형·강도). 영어 데모에 남아 있어도 된다.
const Set<String> _contractValues = <String>{
  '유산소',
  '근력',
  '스트레칭',
  '기타',
  '낮음',
  '보통',
  '높음',
};

const List<String> _allCodes = <String>[
  RoutineEvidence.recentPtFeedback,
  RoutineEvidence.strengthHeavy,
  RoutineEvidence.bloodPressureGoal,
  RoutineEvidence.lowCardio,
  RoutineEvidence.recentRecord,
];

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: true,
);

const AppConfig _realConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

/// 데모 후보 생성 한 번. 지연이 있어 fake async 없이 실제로 기다린다.
Future<RoutineOptions> _generate(
  MockTrainerRoutineOptionsRepository repo, {
  int? minutes,
  String note = '',
}) => repo.generate(
  'm1',
  availableMinutes: minutes,
  intensityPreference: null,
  trainerNote: note,
);

List<String> _planTexts(RoutinePlan p) => <String>[
  p.label,
  p.reason,
  p.rationale,
  for (final RoutineExercise e in p.exercises) e.name,
];

void main() {
  final TestPlatformDispatcher dispatcher =
      TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
  tearDown(dispatcher.clearLocalesTestValue);

  group('근거 코드 → 화면 문구', () {
    test('코드 상수는 서버가 보내는 값과 같다', () {
      // backend/app/services/routine_suggestion_service.py 의 EVIDENCE_CODES.
      expect(_allCodes, <String>[
        'recent_pt_feedback',
        'strength_heavy',
        'blood_pressure_goal',
        'low_cardio',
        'recent_record',
      ]);
    });

    // 예전 서버 문장(`최근 근력운동 비중 높음`)은 서버가 코드로 되돌려 읽는다 —
    // 화면 문구는 띄어쓰기만 다른 곳과 맞췄다(#3201).
    test('한국어 문구는 예전 서버 문장과 같은 말이다', () {
      expect(
        <String>[for (final c in _allCodes) routineEvidenceLabel(_ko, c)],
        <String>[
          '최근 PT 피드백 반영',
          '최근 근력 운동 비중 높음',
          '혈압 관리 목표',
          '최근 유산소 비중 낮음',
          '최근 운동 기록 반영',
        ],
      );
    });

    test('영어 문구는 모두 영어다', () {
      expect(
        <String>[for (final c in _allCodes) routineEvidenceLabel(_en, c)],
        <String>[
          'Recent PT feedback',
          'Mostly strength lately',
          'Blood pressure goal',
          'Little cardio lately',
          'Recent workout log',
        ],
      );
    });

    test('코드마다 문구가 서로 다르다 (칩 두 개가 같은 말을 하지 않는다)', () {
      for (final AppLocalizations l in <AppLocalizations>[_ko, _en]) {
        final Set<String> labels = <String>{
          for (final c in _allCodes) routineEvidenceLabel(l, c),
        };
        expect(labels, hasLength(_allCodes.length));
      }
    });

    test('모르는 값은 그대로 돌려준다 — 새 코드·예전 문장을 버리지 않는다', () {
      expect(routineEvidenceLabel(_en, 'future_code'), 'future_code');
      expect(routineEvidenceLabel(_ko, '트레이너가 쓴 근거'), '트레이너가 쓴 근거');
      expect(routineEvidenceLabel(_en, ''), '');
    });
  });

  group('강도 계약값 → 화면 문구', () {
    test('한국어 화면은 계약값을 강도 표시와 같은 말로 읽는다 (#3201)', () {
      expect(routinePlanIntensityLabel(_ko, '낮음'), '가벼움');
      expect(routinePlanIntensityLabel(_ko, '보통'), '보통');
      expect(routinePlanIntensityLabel(_ko, '높음'), '높음');
    });

    test('영어 화면은 영어로 옮긴다', () {
      expect(routinePlanIntensityLabel(_en, '낮음'), 'Light');
      expect(routinePlanIntensityLabel(_en, '보통'), 'Moderate');
      expect(routinePlanIntensityLabel(_en, '높음'), 'High');
    });

    test('모르는 값은 그대로다', () {
      expect(routinePlanIntensityLabel(_en, 'extreme'), 'extreme');
    });
  });

  group('이름 없는 배정의 기본 이름', () {
    const AssignedRoutine unnamed = AssignedRoutine(
      id: '',
      name: '   ',
      minutes: 30,
      type: '유산소',
      reason: '',
      source: 'ai',
    );

    test('생략하면 예전과 같은 한국어 이름이다', () {
      expect(kDefaultAiRoutineName, 'AI 맞춤 추천안');
      expect(assignRoutineToJson(unnamed)['name'], 'AI 맞춤 추천안');
      expect(_ko.aiCustomRoutineName, kDefaultAiRoutineName);
    });

    test('넘긴 이름(보내는 트레이너의 화면 언어)을 쓴다', () {
      expect(
        assignRoutineToJson(
          unnamed,
          fallbackName: _en.aiCustomRoutineName,
        )['name'],
        'AI custom suggestion',
      );
    });

    test('이름이 있으면 기본 이름은 쓰지 않는다', () {
      expect(
        assignRoutineToJson(
          const AssignedRoutine(
            id: '',
            name: '인터벌 걷기',
            minutes: 30,
            type: '유산소',
            reason: '',
            source: 'ai',
          ),
          fallbackName: 'AI custom suggestion',
        )['name'],
        '인터벌 걷기',
      );
    });

    test('Dio 저장소는 보내는 순간에 기본 이름을 읽는다', () async {
      final _MockDio dio = _MockDio();
      when(
        () => dio.post<Map<String, Object?>>(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 201,
          data: <String, Object?>{'id': 'r1'},
        ),
      );
      String current = _ko.aiCustomRoutineName;
      final DioTrainerRoutineRepository repo = DioTrainerRoutineRepository(
        dio,
        fallbackName: () => current,
      );

      await repo.assignRoutine('m1', unnamed);
      current = _en.aiCustomRoutineName;
      await repo.assignRoutine('m1', unnamed);

      final List<Object?> sent = verify(
        () => dio.post<Map<String, Object?>>(
          '/trainer/clients/m1/routines',
          data: captureAny(named: 'data'),
        ),
      ).captured;
      expect(
        <Object?>[
          for (final Object? body in sent)
            (body! as Map<String, Object?>)['name'],
        ],
        <String>['AI 맞춤 추천안', 'AI custom suggestion'],
      );
    });

    test('기본 이름을 주지 않은 Dio 저장소는 한국어 이름이다', () async {
      final _MockDio dio = _MockDio();
      when(
        () => dio.post<Map<String, Object?>>(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 201,
          data: <String, Object?>{'id': 'r1'},
        ),
      );
      await DioTrainerRoutineRepository(dio).assignRoutine('m1', unnamed);
      final Map<String, Object?> body =
          verify(
                () => dio.post<Map<String, Object?>>(
                  any(),
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(body['name'], 'AI 맞춤 추천안');
    });
  });

  group('데모 AI 제안', () {
    final List<RoutineSuggestion> ko =
        MockTrainerRoutineSuggestionRepository.seedFor('ko');
    final List<RoutineSuggestion> en =
        MockTrainerRoutineSuggestionRepository.seedFor('en');

    test('한국어 후보는 예전 그대로다', () {
      expect(ko.map((s) => s.name), <String>[
        '가벼운 인터벌 러닝',
        '흉추 회전 스트레칭',
        '힙 브리지',
      ]);
      expect(MockTrainerRoutineSuggestionRepository.seedFor('fr'), same(ko));
    });

    test('영어 후보는 id·시간·유형·세트·근거가 같고 이름·사유만 영어다', () {
      expect(en, hasLength(ko.length));
      for (int i = 0; i < ko.length; i++) {
        expect(en[i].id, ko[i].id);
        expect(en[i].minutes, ko[i].minutes);
        expect(en[i].type, ko[i].type);
        expect(en[i].sets, ko[i].sets);
        expect(en[i].reps, ko[i].reps);
        expect(en[i].weight, ko[i].weight);
        expect(en[i].evidence, ko[i].evidence);
        expect(en[i].name, isNot(contains(_hangul)));
        expect(en[i].reason, isNot(contains(_hangul)));
        expect(en[i].reason, isNotEmpty);
      }
    });

    test('근거는 모두 앱이 아는 코드다 — 문장이 아니다', () {
      for (final RoutineSuggestion s in <RoutineSuggestion>[...ko, ...en]) {
        for (final String code in s.evidence) {
          expect(_allCodes, contains(code));
        }
      }
    });

    test('저장소는 목록을 처음 여는 순간의 언어로 채운다', () async {
      String lang = 'en';
      final MockTrainerRoutineSuggestionRepository repo =
          MockTrainerRoutineSuggestionRepository(languageCode: () => lang);
      expect(
        (await repo.pending('m1')).map((s) => s.name),
        en.map((s) => s.name),
      );
      lang = 'ko';
      expect(
        (await repo.pending('m2')).map((s) => s.name),
        ko.map((s) => s.name),
      );
    });

    test('언어를 주지 않으면 한국어다', () async {
      expect(
        (await MockTrainerRoutineSuggestionRepository().pending(
          'm1',
        )).map((s) => s.name),
        ko.map((s) => s.name),
      );
    });
  });

  group('데모 시작 템플릿', () {
    const List<ProgramTemplate> ko =
        MockTrainerProgramTemplateRepository.starters;
    const List<ProgramTemplate> en =
        MockTrainerProgramTemplateRepository.startersEn;

    test('한국어 시작 구성은 예전 그대로다', () {
      expect(ko.map((t) => t.name), <String>[
        '혈압 관리 기본',
        '체중 감량 순환',
        '하체 근력 A',
      ]);
      expect(MockTrainerProgramTemplateRepository.startersFor('ko'), same(ko));
      expect(MockTrainerProgramTemplateRepository.startersFor('fr'), same(ko));
      expect(MockTrainerProgramTemplateRepository.startersFor('en'), same(en));
    });

    test('영어 시작 구성은 id·시간·유형이 같고 글만 영어다 (서버 영어판과 같은 이름)', () {
      expect(en.map((t) => t.name), <String>[
        'Blood pressure basics',
        'Weight-loss circuit',
        'Lower-body strength A',
      ]);
      expect(en, hasLength(ko.length));
      for (int i = 0; i < ko.length; i++) {
        expect(en[i].id, ko[i].id);
        expect(en[i].exercises, hasLength(ko[i].exercises.length));
        for (int j = 0; j < ko[i].exercises.length; j++) {
          expect(en[i].exercises[j].minutes, ko[i].exercises[j].minutes);
          expect(en[i].exercises[j].type, ko[i].exercises[j].type);
          expect(en[i].exercises[j].name, isNot(contains(_hangul)));
        }
        expect(en[i].name, isNot(contains(_hangul)));
        expect(en[i].goal, isNot(contains(_hangul)));
      }
    });

    test('목록은 읽는 순간의 언어로 주고, 저장한 템플릿은 옮기지 않는다', () async {
      String lang = 'ko';
      final MockTrainerProgramTemplateRepository repo =
          MockTrainerProgramTemplateRepository(languageCode: () => lang);
      await repo.create(
        name: '내 루틴',
        goal: '근력',
        exercises: const <TemplateExercise>[
          TemplateExercise(name: '스쿼트', minutes: 10, type: '근력'),
        ],
      );

      final List<ProgramTemplate> inKorean = await repo.list();
      lang = 'en';
      final List<ProgramTemplate> inEnglish = await repo.list();

      expect(inKorean.first.name, '내 루틴');
      expect(inEnglish.first.name, '내 루틴');
      expect(inKorean.skip(1).map((t) => t.name), ko.map((t) => t.name));
      expect(inEnglish.skip(1).map((t) => t.name), en.map((t) => t.name));
    });
  });

  group('데모 후보 생성', () {
    test('한국어 문구는 예전 그대로다', () async {
      final RoutineOptions o = await _generate(
        const MockTrainerRoutineOptionsRepository(),
      );
      expect(o.planA.label, '회복·지속 중심');
      expect(o.planB.label, '강도·운동량 중심');
      expect(o.planA.exercises.first.name, '저강도 걷기');
      expect(o.planA.reason, '짧고 지속하기 쉬운 회복 중심 프로그램');
      expect(o.analysis.latestRoutine, '저강도 유산소 (걷기)');
      expect(o.planA.rationale, startsWith('오늘 나트륨 2100mg (목표 초과)'));
    });

    test('영어는 이름·사유·근거 문장에 한글이 없다 (회원 목표 이름 제외)', () async {
      final RoutineOptions o = await _generate(
        MockTrainerRoutineOptionsRepository(languageCode: () => 'en'),
        note: 'knee pain',
      );
      for (final RoutinePlan p in <RoutinePlan>[o.planA, o.planB]) {
        // 회원 목표는 회원이 고른 이름이라 옮기지 않는다(서버도 같다). 그 이름을
        // 뺀 나머지 문장에는 한글이 없다.
        for (final String text in _planTexts(p)) {
          expect(
            text.replaceAll(o.analysis.goal, ''),
            isNot(contains(_hangul)),
            reason: text,
          );
        }
        expect(_contractValues, contains(p.intensity));
        for (final RoutineExercise e in p.exercises) {
          expect(_contractValues, contains(e.type));
        }
      }
      expect(o.planA.label, 'Recovery & consistency');
      expect(o.planB.label, 'Intensity & volume');
      expect(o.planA.rationale, contains('Trainer note applied: knee pain.'));
      expect(o.analysis.latestRoutine, 'Low-intensity cardio (walk)');
    });

    test('언어와 무관하게 시간·강도·유형 구성은 같다', () async {
      for (final int? minutes in <int?>[null, 10, 45, 180]) {
        final RoutineOptions ko = await _generate(
          const MockTrainerRoutineOptionsRepository(),
          minutes: minutes,
        );
        final RoutineOptions en = await _generate(
          MockTrainerRoutineOptionsRepository(languageCode: () => 'en'),
          minutes: minutes,
        );
        for (final (RoutinePlan a, RoutinePlan b)
            in <(RoutinePlan, RoutinePlan)>[
              (ko.planA, en.planA),
              (ko.planB, en.planB),
            ]) {
          expect(b.key, a.key);
          expect(b.totalMinutes, a.totalMinutes);
          expect(b.intensity, a.intensity);
          expect(
            b.exercises.map((e) => (e.minutes, e.type)),
            a.exercises.map((e) => (e.minutes, e.type)),
          );
        }
      }
    });
  });

  group('provider 는 화면 언어를 요청하는 순간에 읽는다', () {
    Future<ProviderContainer> container(AppConfig config, {Dio? dio}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // 데모 제안·후보 생성은 데모 DB 를 읽는다(#2668) — 빈 메모리 DB 면 시드
      // 회원이 아닌 `m1` 은 기본 후보·고정 스냅샷을 받는다.
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (dio != null) dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('브라우저 언어가 영어면 데모 저장소가 영어를 준다', () async {
      dispatcher.localesTestValue = const <Locale>[Locale('en', 'US')];
      final ProviderContainer c = await container(_mockConfig);

      final List<ProgramTemplate> templates = await c
          .read(trainerProgramTemplateRepositoryProvider)
          .list();
      expect(templates.first.name, 'Blood pressure basics');
      final List<RoutineSuggestion> suggestions = await c
          .read(trainerRoutineSuggestionRepositoryProvider)
          .pending('m1');
      expect(suggestions.first.name, 'Light interval run');
      final RoutineOptions options = await c
          .read(trainerRoutineOptionsRepositoryProvider)
          .generate(
            'm1',
            availableMinutes: null,
            intensityPreference: null,
            trainerNote: '',
          );
      expect(options.planA.label, 'Recovery & consistency');
    });

    test('설정에서 고른 언어가 브라우저 언어를 이긴다', () async {
      dispatcher.localesTestValue = const <Locale>[Locale('en')];
      final ProviderContainer c = await container(_mockConfig);
      await c
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.korean);

      final List<ProgramTemplate> templates = await c
          .read(trainerProgramTemplateRepositoryProvider)
          .list();
      expect(templates.first.name, '혈압 관리 기본');
    });

    test('실서버 배정의 기본 이름은 보내는 순간의 화면 언어다', () async {
      dispatcher.localesTestValue = const <Locale>[Locale('ko')];
      final _MockDio dio = _MockDio();
      when(
        () => dio.post<Map<String, Object?>>(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<Map<String, Object?>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 201,
          data: <String, Object?>{'id': 'r1'},
        ),
      );
      final ProviderContainer c = await container(_realConfig, dio: dio);
      const AssignedRoutine unnamed = AssignedRoutine(
        id: '',
        name: '',
        minutes: 20,
        type: '유산소',
        reason: '',
        source: 'ai',
      );
      final TrainerRoutineRepository repo = c.read(
        trainerRoutineRepositoryProvider,
      );

      await repo.assignRoutine('m1', unnamed);
      await c
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);
      await repo.assignRoutine('m1', unnamed);

      final List<Object?> sent = verify(
        () => dio.post<Map<String, Object?>>(
          any(),
          data: captureAny(named: 'data'),
        ),
      ).captured;
      expect(
        <Object?>[
          for (final Object? body in sent)
            (body! as Map<String, Object?>)['name'],
        ],
        <String>['AI 맞춤 추천안', 'AI custom suggestion'],
      );
    });
  });
}
