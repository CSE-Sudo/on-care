import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

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
class MockTrainerRoutineOptionsRepository
    implements TrainerRoutineOptionsRepository {
  const MockTrainerRoutineOptionsRepository();

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
    const sodium = 2100;
    const completion = 55;
    const goal = '혈압 관리 · 체중 감량';
    final note = trainerNote.trim();
    final noteSuffix = note.isEmpty ? '' : ' 트레이너 메모 반영: $note.';
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
        latestRoutine: '저강도 유산소 (걷기)',
        note: note,
        // 데모 회원은 실제 축적 이력이 없다 — #776 의 "데이터 부족" 상태를
        // 그대로 보여 준다(개인화한 것처럼 보이지 않아야 한다는 요구와도 맞다).
      ),
      planA: RoutinePlan(
        key: 'A',
        label: '회복·지속 중심',
        totalMinutes: totalA,
        intensity: '낮음',
        exercises: <RoutineExercise>[
          RoutineExercise(
            name: '저강도 걷기',
            minutes: (totalA * 0.6).round().clamp(1, totalA),
            type: '유산소',
          ),
          RoutineExercise(
            name: '코어 스트레칭',
            minutes: (totalA - (totalA * 0.6).round()).clamp(1, totalA),
            type: '스트레칭',
          ),
        ],
        reason: '짧고 지속하기 쉬운 회복 중심 프로그램',
        rationale:
            '오늘 나트륨 ${sodium}mg (목표 초과), 최근 운동 완료율 $completion% → '
            '부담이 적은 유산소·스트레칭으로 지속 가능성에 집중.$noteSuffix',
      ),
      planB: RoutinePlan(
        key: 'B',
        label: '강도·운동량 중심',
        totalMinutes: totalB,
        intensity: intensityPref == 'low' ? '보통' : '높음',
        exercises: <RoutineExercise>[
          RoutineExercise(
            name: '인터벌 러닝',
            minutes: intervalMinutes,
            type: '유산소',
          ),
          RoutineExercise(name: '스쿼트', minutes: squatMinutes, type: '근력'),
          RoutineExercise(name: '플랭크', minutes: plankMinutes, type: '근력'),
        ],
        reason: '운동량과 강도를 높인 프로그램',
        rationale:
            "목표 '$goal' 기준, 완료율 $completion%로 점진적으로 근력·유산소를 더해 "
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
      ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
      if (ref.watch(appConfigProvider).useMockApi) {
        return const MockTrainerRoutineOptionsRepository();
      }
      return DioTrainerRoutineOptionsRepository(ref.watch(dioProvider));
    }, name: 'trainerRoutineOptionsRepository');
