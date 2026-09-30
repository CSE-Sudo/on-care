import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 배정 루틴 완료가 남기는 운동 기록을 쓰고 지우는 곳 — **데모 전용**이다.
///
/// 실서버는 루틴 완료를 받으면 회원 운동 기록 한 건(`assigned_routine`)을 함께
/// 만들고 완료를 되돌리면 지운다(#1131). 데모에는 서버가 없어 목업 코치 저장소가
/// 이 일을 대신하는데, 그 기록은 운동 탭·홈·챌린지가 읽는 **같은 기록**에
/// 들어가야 한다(#2662). 앱에서는 로컬 목업 API(drift)가, 테스트에서는 메모리
/// 목업 운동 저장소가 이 역할을 맡는다.
abstract interface class RoutineSessionLog {
  /// 배정 루틴을 수행한 기록을 남긴다. 출처는 `assigned_routine` 이라 회원이
  /// 고치거나 지우지 못한다(#499, #638).
  Future<ExerciseSession> addAssignedRoutineSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    required String routineId,
    required String name,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? durationSeconds,
  });

  /// 완료를 되돌릴 때 그 수행 기록을 지운다. 배정 루틴 기록만 지운다.
  Future<void> removeAssignedRoutineSession(String id);

  /// 남아 있는 배정 루틴 수행 기록 전부 — `assigned_routine_id` 와 날짜가 있는
  /// 것만. 새로고침한 뒤 목업 코치 저장소가 그날의 체크를 되살리는 재료다.
  /// 기록은 남았는데 체크가 풀려 있으면, 다시 체크할 때 같은 기록이 하나 더
  /// 생긴다. (#2662)
  Future<List<ExerciseSession>> assignedRoutineSessions();
}
