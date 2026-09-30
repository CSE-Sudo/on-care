import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

abstract class ExerciseRepository {
  Future<ExerciseWeek> fetchThisWeek();

  /// 한 주의 기록. [weekStart] 는 그 주의 **월요일**이다.
  ///
  /// 조회가 이번 주 하나뿐이라 운동 탭에서 지난 날짜를 골라도 보여줄 것이
  /// 없었다(#671). 이번 주를 넘겨 부르면 [fetchThisWeek] 과 같은 결과다.
  Future<ExerciseWeek> fetchWeek(DateTime weekStart);

  /// 구간이 걸친 **주들** — GET /exercise/weeks?from=&to= (#2247)
  ///
  /// `전체` 그래프가 쓰는 길이다. 예전에는 주마다 [fetchWeek] 을 불렀는데,
  /// `전체` 가 모든 기록을 그리게 되면서(#2079) 해가 바뀐 회원에게 쉰 번이 넘는
  /// 왕복이 됐다.
  ///
  /// [from] 을 주지 않으면 첫 기록이 있는 주부터다. 돌려주는 칸에는 세션 목록과
  /// 코칭 문구가 없다 — 한 주를 펼쳐 볼 때는 [fetchWeek] 이다.
  Future<List<ExercisePeriodWeek>> fetchPeriod({DateTime? from, DateTime? to});

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

  /// POST /exercise/sessions — 운동 기록 [drafts](1~N개)를 **한 번에** 저장한다.
  /// (#2544)
  ///
  /// 서버는 목록 하나를 한 트랜잭션으로 저장한다 — 전부 되거나 전부 안 된다.
  /// 한 건씩 보내면 몇 개만 저장된 채 실패할 수 있고, 다시 시도한 회원이 이미
  /// 저장된 것을 한 번 더 남긴다. 한 건도 이 길로 보낸다 — 추가 경로는 한
  /// 벌이다.
  ///
  /// 돌려주는 기록은 요청과 같은 순서다. 필드의 뜻은 [ExerciseSessionDraft].
  Future<ExerciseSessionsAdded> addSessions(List<ExerciseSessionDraft> drafts);

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
