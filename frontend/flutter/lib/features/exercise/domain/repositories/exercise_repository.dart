import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

abstract class ExerciseRepository {
  Future<ExerciseWeek> fetchThisWeek();

  /// 한 주의 기록. [weekStart] 는 그 주의 **월요일**이다.
  ///
  /// 조회가 이번 주 하나뿐이라 운동 탭에서 지난 날짜를 골라도 보여줄 것이
  /// 없었다(#671). 이번 주를 넘겨 부르면 [fetchThisWeek] 과 같은 결과다.
  Future<ExerciseWeek> fetchWeek(DateTime weekStart);

  /// 기간에 맞는 운동 조언 — GET /exercise/advice. (#1574)
  ///
  /// [period] 는 화면의 기간 토글과 같은 말이다(`today`·`week`·`all`). 구간
  /// 경계는 서버가 정한다 — 앱이 따로 계산해 넘기면 같은 회원의 `이번 주` 가
  /// 화면마다 다른 날부터 시작한다.
  ///
  /// 문장 키·값과 한국어 문장을 함께 준다(#2210) — 화면이 자기 언어로 그린다.
  Future<ExerciseAdvice> fetchAdvice(String period);

  /// POST /exercise/calories — 운동 이름·시간·강도로 예상 소모 칼로리. (#1312)
  ///
  /// 저장 경로와 **같은 계산**이라, 폼이 보여 준 숫자와 저장된 기록의 숫자가
  /// 갈리지 않는다. 이름이 종목 참조표에 붙고 회원 체중을 알면 그 둘에서 나온
  /// 값이고, 아니면 유형 평균의 어림값이다 — 어느 쪽인지는
  /// [ExerciseCalorieEstimate.source] 가 말한다.
  ///
  /// [name] 은 비어 있으면 안 된다. 이름 없이 확정된 숫자를 내주지 않는 것이 이
  /// 계산의 요점이라, 부르는 쪽이 이름이 찬 뒤에 부른다.
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  });

  /// Persist a new workout session (POST /exercise/sessions) and return
  /// the created session as the server materialised it.
  ///
  /// [sets]·[reps]·[holdSeconds]·[weight] 는 근력 기록에만 있는 값이다 —
  /// 근력은 시간이 아니라 세트·횟수·무게로 읽는 운동이라 회원이 적은 수를
  /// 그대로 싣는다. 다른 유형은 null 이고, 서버도 근력이 아닌 기록에서는 이
  /// 값들을 버린다. (#1262, #1276, #1310)
  ///
  /// [holdSeconds] 는 플랭크처럼 **버티는** 운동이 한 세트를 버틴 시간이고,
  /// [reps] 와 한 자리를 나눠 쓴다 — 이 값을 실으면 서버가 횟수를 비운다.
  /// 한 세트를 회로든 초로든 한 번만 잰다(#1969).
  ///
  /// [durationSeconds] 는 회원이 시·분·초 휠로 적은 걸린 시간이다(#2071).
  /// 보내면 서버가 그 초로 `minutes` 를 다시 계산한다 — 분 칸은 주간 집계와
  /// 트레이너웹이 읽으므로 늘 차 있어야 한다. 근력은 분이 세트에서 나오는
  /// 값이라 싣지 않는다.
  ///
  /// [date] 는 회원이 달력에서 고른 날이다. 생략하면 서버가 오늘로 둔다.
  Future<ExerciseSession> addSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  });

  /// DELETE /exercise/sessions/{id} — remove a workout session.
  Future<void> deleteSession(String id);

  /// PUT /exercise/sessions/{id} — edit a workout session.
  Future<ExerciseSession> updateSession({
    required String id,
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  });
}
