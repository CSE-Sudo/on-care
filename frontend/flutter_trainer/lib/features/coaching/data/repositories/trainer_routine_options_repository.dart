import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

/// Generates A/B routine options for a member (the AI generation step). The
/// result is *generated*, not assigned — the trainer picks/edits one and
/// sends it via the routine assign repository.
///
/// Two implementations, selected by [trainerRoutineOptionsRepositoryProvider]
/// via [AppConfig.useMockApi]:
///  * [MockTrainerRoutineOptionsRepository] — demo (deterministic A/B);
///  * [DioTrainerRoutineOptionsRepository] — the real FastAPI backend.
abstract interface class TrainerRoutineOptionsRepository {
  /// [availableMinutes]/[intensityPreference] are null when the trainer
  /// hasn't touched those fields (#776) — the server then derives them from
  /// the member's recent history, or a fixed default when history is thin.
  /// A non-null value always wins over whatever the server would suggest.
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
  });
}

/// Deterministic demo generator mirroring the backend rule-based output, so
/// the 3-step flow works with no backend. Uses a fixed member snapshot
/// (over-target sodium, mid adherence) that tells the demo story.
///
/// 실서버처럼 **생성을 요청하는 순간의 화면 언어**로 이름·사유·근거 문장을
/// 만든다(#2301). 문장은 서버 규칙형(`routine_ai.rule_based_plans`)의 영어판과
/// 같다. `intensity`·`type` 은 번역하지 않는 계약값이다.
class MockTrainerRoutineOptionsRepository
    implements TrainerRoutineOptionsRepository {
  /// [languageCode] 를 생략하면 한국어다.
  const MockTrainerRoutineOptionsRepository({this.languageCode = _korean});

  /// 생성을 요청하는 순간의 화면 언어 코드(`ko`·`en`).
  final String Function() languageCode;

  static String _korean() => 'ko';

  /// Matches the backend default used when the trainer leaves conditions
  /// blank (`trainer_routine_options_service.DEFAULT_AVAILABLE_MINUTES`).
  static const int _defaultMinutes = 30;
  static const String _defaultIntensity = 'moderate';

  @override
  Future<RoutineOptions> generate(
    String memberId, {
    required int? availableMinutes,
    required String? intensityPreference,
    required String trainerNote,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final bool en = languageCode() == 'en';
    const sodium = 2100;
    const completion = 55;
    // 회원 목표는 회원이 고른 목표 이름이라 서버도 옮기지 않는다 — 데모도 같다.
    const goal = '혈압 관리 · 체중 감량';
    final note = trainerNote.trim();
    final noteSuffix = note.isEmpty
        ? ''
        : en
        ? ' Trainer note applied: $note.'
        : ' 트레이너 메모 반영: $note.';
    String t(String ko, String english) => en ? english : ko;
    final minutes = availableMinutes ?? _defaultMinutes;
    final intensityPref = intensityPreference ?? _defaultIntensity;

    // 하한은 슬라이더의 실제 최소값(5분)과 맞춘다 — 10으로 두면 5분 요청에서
    // `clamp(10, 5)`가 하한>상한이 되어 데모 생성이 그대로 예외로 죽는다.
    final totalA = (minutes * 0.7).round().clamp(5, minutes);
    // Keep the demo contract aligned with the backend: neither option may
    // exceed the time the trainer entered. The old lower bound
    // (`totalA + 5`) produced a 15-minute plan for a 10-minute request and
    // even threw when availableMinutes was 180 (lower clamp bound > 180).
    final totalB = minutes;

    // B안 세 운동의 시간 배분. 셋을 각자 독립적으로 반올림·clamp 하면(예전
    // 코드) 합이 totalB 를 벗어날 수 있다 — 5분처럼 작은 값에서 실제로 6분이
    // 나왔다. 앞 두 개만 반올림해서 정하고, 세 번째는 항상 나머지로 채워
    // 합이 totalB 와 정확히 같게 한다. 앞 두 개의 상한도 "남은 운동에 최소
    // 1분씩은 남긴다"는 조건으로 둔다.
    final intervalMinutes = (totalB * 0.5).round().clamp(1, totalB - 2);
    final squatMinutes = (totalB * 0.3).round().clamp(
      1,
      totalB - intervalMinutes - 1,
    );
    final plankMinutes = totalB - intervalMinutes - squatMinutes;

    return RoutineOptions(
      analysis: MemberAnalysis(
        goal: goal,
        sodiumTodayMg: sodium,
        sodiumOverTarget: true,
        avgCompletionRate: completion,
        latestRoutine: t('저강도 유산소 (걷기)', 'Low-intensity cardio (walk)'),
        note: note,
        // 데모 회원은 실제 축적 이력이 없다 — #776 의 "데이터 부족" 상태를
        // 그대로 보여 준다(개인화한 것처럼 보이지 않아야 한다는 요구와도 맞다).
      ),
      planA: RoutinePlan(
        key: 'A',
        label: t('회복·지속 중심', 'Recovery & consistency'),
        totalMinutes: totalA,
        intensity: '낮음',
        exercises: <RoutineExercise>[
          RoutineExercise(
            name: t('저강도 걷기', 'Low-intensity walk'),
            minutes: (totalA * 0.6).round().clamp(1, totalA),
            type: '유산소',
          ),
          RoutineExercise(
            name: t('코어 스트레칭', 'Core stretch'),
            minutes: (totalA - (totalA * 0.6).round()).clamp(1, totalA),
            type: '스트레칭',
          ),
        ],
        reason: t(
          '짧고 지속하기 쉬운 회복 중심 프로그램',
          'A short, easy-to-sustain recovery program',
        ),
        rationale: en
            ? 'Sodium today ${sodium}mg (over target), recent workout '
                  'completion $completion% → focusing on consistency with '
                  'low-strain cardio and stretching.$noteSuffix'
            : '오늘 나트륨 ${sodium}mg (목표 초과), 최근 운동 완료율 $completion% → '
                  '부담이 적은 유산소·스트레칭으로 지속 가능성에 집중.$noteSuffix',
      ),
      planB: RoutinePlan(
        key: 'B',
        label: t('강도·운동량 중심', 'Intensity & volume'),
        totalMinutes: totalB,
        intensity: intensityPref == 'low' ? '보통' : '높음',
        exercises: <RoutineExercise>[
          RoutineExercise(
            name: t('인터벌 러닝', 'Interval running'),
            minutes: intervalMinutes,
            type: '유산소',
          ),
          RoutineExercise(
            name: t('스쿼트', 'Squat'),
            minutes: squatMinutes,
            type: '근력',
          ),
          RoutineExercise(
            name: t('플랭크', 'Plank'),
            minutes: plankMinutes,
            type: '근력',
          ),
        ],
        reason: t(
          '운동량과 강도를 높인 프로그램',
          'A program with more volume and intensity',
        ),
        rationale: en
            ? "Based on the goal '$goal' and a $completion% completion rate, "
                  'gradually adding strength and cardio to raise the '
                  'workload.$noteSuffix'
            : "목표 '$goal' 기준, 완료율 $completion%로 점진적으로 근력·유산소를 더해 "
                  '운동량을 높임.$noteSuffix',
      ),
      generatedBy: 'rule',
    );
  }
}

/// Selects the real Dio-backed generator, or the demo generator for
/// `USE_MOCK_API=true`.
final trainerRoutineOptionsRepositoryProvider =
    Provider<TrainerRoutineOptionsRepository>((ref) {
      if (ref.watch(appConfigProvider).useMockApi) {
        return MockTrainerRoutineOptionsRepository(
          languageCode: () =>
              ref.read(trainerResolvedLocaleProvider).languageCode,
        );
      }
      return DioTrainerRoutineOptionsRepository(ref.watch(dioProvider));
    }, name: 'trainerRoutineOptionsRepository');
