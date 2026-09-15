import 'package:oncare/features/exercise/domain/entities/streak_shield.dart';

/// 연속 기록 보호권 — 보유·보호한 날 조회와 사용. (#1788)
///
/// 교환은 다른 사용처 항목과 같은 `BenefitsRepository.exchange('streak_shield')` 다.
/// 운동 현황의 버튼 여부는 운동 주간 응답(`ExerciseWeek.streakShield`)이 준다.
///
/// 운동 저장소([ExerciseRepository])와 따로 둔 이유: 데모에서 "어제 운동 기록이
/// 있나" 를 아는 곳은 목업 운동 저장소인데, 그 계약에 메서드를 더하면 운동 화면
/// 테스트의 대역이 모두 함께 바뀌어야 한다.
abstract interface class StreakShieldRepository {
  /// 쓰지 않은 보호권 수와 보호한 날(최근 먼저).
  Future<StreakShields> fetch();

  /// [date](어제)를 연속 기록에 이어 붙이고 보호권 한 장을 쓴다. 이미 보호한
  /// 날이면 더 쓰지 않는다. 규칙에 막히면 서버 오류로 올라온다.
  Future<StreakShields> use(DateTime date);
}
