import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';

/// 유형·시간·강도로 소모 칼로리를 어림한다.
///
/// 백엔드 `exercise_catalog.energy.fallback` 과 같은 표다(#1276) — 운동 이름이
/// 종목 참조표에 붙지 않을 때의 **폴백**이고, 붙으면 서버가 종목 계수와 회원
/// 체중으로 계산한다(#1312). 트레이너 폼은 아직 수행할 회원이 정해지지 않은
/// 자리라 여기서는 늘 이 표를 쓴다. 트레이너가
/// 프로그램을 짜는 동안 화면이 보여 주는 값과 회원이 그 운동을 마친 뒤 기록에
/// 남는 값이 갈리면, 같은 운동을 두 사람이 다른 수로 이야기하게 된다.
///
/// **세 유형을 한 축에서 비교하는 값은 이 칼로리 하나다.** 유산소는 분, 근력은
/// 세트, 스트레칭은 분으로 재는 서로 더할 수 없는 값이라, 합쳐 보려면 셋이 함께
/// 만든 결과 하나로 읽어야 한다.
const Map<String, double> _kcalPerMinute = <String, double>{
  '유산소': 9,
  '근력': 6,
  '스트레칭': 3,
  '기타': 5,
};

const Map<String, double> _intensityFactor = <String, double>{
  'light': 0.85,
  'moderate': 1.0,
  'high': 1.2,
};

/// 근력 1세트가 차지하는 벽시계 시간(세트 + 휴식). 회원 앱
/// `kStrengthMinutesPerSetWithRest`·백엔드 `STRENGTH_MINUTES_PER_SET` 과 같은
/// 값이라야 세 곳이 같은 분을 센다.
const double kStrengthMinutesPerSet = 3;

/// 근력 세트 수 → 분. 서버는 여전히 분(>0)을 요구하고 주간 운동 시간도 분으로
/// 세므로, 세트로 받은 값을 저장 전에 여기서 환산한다.
int minutesFromSets(int sets) => (sets * kStrengthMinutesPerSet).round();

/// 예상 소모 칼로리 한 건과 그 근거. (#1312)
class RoutineCalorieEstimate {
  const RoutineCalorieEstimate({required this.calories, this.isRough = true});

  final int calories;

  /// 유형 평균으로 낸 어림값인가. 트레이너가 프로그램을 짜는 동안에는 아직
  /// 어느 회원이 수행할지·그 회원의 체중이 얼마인지가 계산에 들어가지 않으므로
  /// 늘 참이다 — 회원이 그 운동을 마치면 서버가 종목 참조표와 회원 체중으로
  /// 다시 계산한 값이 기록에 남는다(#1312).
  final bool isRough;
}

/// 이 운동의 예상 소모 칼로리. **이름이 비어 있으면 null 이다.**
///
/// 이름 없이 확정된 듯한 숫자를 띄우지 않는 것이 회원 앱과 같은 규약이다
/// (#1312). 이름 칸이 계산에 아무 영향이 없던 때에는, 폼을 여는 순간 기본값만
/// 으로 값이 떠 있어 그 숫자가 무엇의 값인지 읽히지 않았다.
///
/// [minutes] 는 근력이면 [minutesFromSets] 로 환산한 값이다 — 중량은 계산에
/// 쓰지 않는다(같은 무게라도 사람마다 소모가 달라, 추정식에 넣으면 근거 없는
/// 정밀도가 된다).
RoutineCalorieEstimate? estimateRoutineCalories({
  required String name,
  required String type,
  required int minutes,
  required String intensity,
}) {
  if (name.trim().isEmpty) return null;
  final double perMinute = _kcalPerMinute[normaliseRoutineType(type)] ?? 5;
  final double factor =
      _intensityFactor[normaliseRoutineIntensity(intensity)] ?? 1.0;
  return RoutineCalorieEstimate(
    calories: (perMinute * (minutes < 0 ? 0 : minutes) * factor).round(),
  );
}

/// 버티는 운동으로 알려진 종목 이름 조각 — 서버 종목표의 `isometric` 표시를
/// 앱이 보는 벌이다. 원본은 `backend/app/data/exercise_catalog_seed.py` 이고,
/// 이 목록은 서버에 닿지 못하는 자리(데모·목업)와 응답이 오기 전의 **기본값**
/// 으로만 쓴다. (#1969)
///
/// 이름 조각으로 보는 이유는 회원이 적는 말이 종목 이름 그대로가 아니기
/// 때문이다 — `사이드 플랭크`, `플랭크 홀드` 가 모두 같은 종목이다.
const List<String> kIsometricNameParts = <String>['플랭크', 'plank'];

/// [name] 이 버티는 운동인가 — 폼이 `횟수` 대신 `초` 를 물을지의 **기본값**.
///
/// 맞고 틀리고를 여기서 끝내지 않는다. 종목표에 없는 이름도 있고 같은 이름을
/// 다르게 쓰는 사람도 있어, 폼은 이 값으로 칸을 고르되 사용자가 곧바로 바꿀
/// 수 있어야 한다.
bool isIsometricExerciseName(String name) {
  final String normalized = name.toLowerCase().replaceAll(' ', '');
  return kIsometricNameParts.any(normalized.contains);
}
