/// 운동 값의 입력 상한 — 트레이너 앱·회원 앱·서버가 **같은 수**를 쓴다. (#1904)
///
/// 트레이너가 배정할 수 있는 값을 회원이 자기 앱에서 직접 적을 수도 있어야
/// 한다. 예전에는 세트가 트레이너 99·회원 앱 40 이라, 화면에 보이는 수를 회원이
/// 옮겨 적을 수 없었다.
///
/// 같은 값이 회원 앱 `features/exercise/domain/entities/exercise_limits.dart` 와
/// 서버 `backend/app/schemas/exercise_limits.py` 에 있다.
library;

/// 근력 한 항목의 세트 수 상한.
const int kMaxExerciseSets = 100;

/// 근력 한 세트당 횟수 상한.
const int kMaxExerciseReps = 999;

/// 근력 한 항목의 중량 상한(kg).
const double kMaxExerciseWeightKg = 1000;
