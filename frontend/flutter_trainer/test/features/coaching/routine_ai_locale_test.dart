// AI 운동 추천의 근거·기본 이름·데모 문구 (#2301).
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_suggestion_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

class _MockDio extends Mock implements Dio {}

final AppLocalizations _ko = lookupAppLocalizations(const Locale('ko'));

const List<String> _allCodes = <String>[
  RoutineEvidence.recentPtFeedback,
  RoutineEvidence.strengthHeavy,
  RoutineEvidence.bloodPressureGoal,
  RoutineEvidence.lowCardio,
  RoutineEvidence.recentRecord,
];

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

void main() {

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

    test('코드마다 문구가 서로 다르다 (칩 두 개가 같은 말을 하지 않는다)', () {
      final Set<String> labels = <String>{
        for (final c in _allCodes) routineEvidenceLabel(_ko, c),
      };
      expect(labels, hasLength(_allCodes.length));
    });

    test('모르는 값은 그대로 돌려준다 — 새 코드·예전 문장을 버리지 않는다', () {
      expect(routineEvidenceLabel(_ko, 'future_code'), 'future_code');
      expect(routineEvidenceLabel(_ko, '트레이너가 쓴 근거'), '트레이너가 쓴 근거');
      expect(routineEvidenceLabel(_ko, ''), '');
    });
  });

  group('강도 계약값 → 화면 문구', () {
    test('한국어 화면은 계약값을 강도 표시와 같은 말로 읽는다 (#3201)', () {
      expect(routinePlanIntensityLabel(_ko, '낮음'), '가벼움');
      expect(routinePlanIntensityLabel(_ko, '보통'), '보통');
      expect(routinePlanIntensityLabel(_ko, '높음'), '높음');
    });

    test('모르는 값은 그대로다', () {
      expect(routinePlanIntensityLabel(_ko, 'extreme'), 'extreme');
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

    test('기본 이름은 ARB 문구와 같다', () {
      expect(kDefaultAiRoutineName, 'AI 맞춤 추천안');
      expect(assignRoutineToJson(unnamed)['name'], 'AI 맞춤 추천안');
      expect(_ko.aiCustomRoutineName, kDefaultAiRoutineName);
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
        )['name'],
        '인터벌 걷기',
      );
    });

    test('Dio 저장소는 이름 없는 배정을 기본 이름으로 보낸다', () async {
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
    const List<RoutineSuggestion> ko =
        MockTrainerRoutineSuggestionRepository.seed;

    test('한국어 후보는 예전 그대로다', () {
      expect(ko.map((s) => s.name), <String>[
        '가벼운 인터벌 러닝',
        '흉추 회전 스트레칭',
        '힙 브리지',
      ]);
    });

    test('근거는 모두 앱이 아는 코드다 — 문장이 아니다', () {
      for (final RoutineSuggestion s in ko) {
        for (final String code in s.evidence) {
          expect(_allCodes, contains(code));
        }
      }
    });

    test('저장소는 처음 여는 회원에게 기본 후보를 준다', () async {
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

    test('한국어 시작 구성은 예전 그대로다', () {
      expect(ko.map((t) => t.name), <String>[
        '혈압 관리 기본',
        '체중 감량 순환',
        '하체 근력 A',
      ]);
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
  });

}
