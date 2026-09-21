import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';

/// 기록 그래프 — 날짜별 기록 조회와 그래프 색 고르기. (#2075, #2076)
///
/// 색을 **여는** 것은 다른 사용처 항목과 같은
/// `BenefitsRepository.exchange('graph_color', option: <색>)` 다. 여기 [selectColor]
/// 는 이미 연 색 사이를 오가는 것이라 포인트가 들지 않는다.
///
/// 보호권 저장소([StreakShieldRepository])와 따로 둔 이유는 같다 — 데모에서 날짜별
/// 기록을 아는 곳이 목업 운동 저장소와 목업 식단이라, 그 계약에 메서드를 더하면
/// 운동·식단 화면 테스트의 대역이 모두 함께 바뀌어야 한다.
abstract interface class ActivityCalendarRepository {
  /// [from]…[to] 의 날짜별 기록·기록 연속·그래프 색. 구간을 주지 않으면 서버 기본
  /// (오늘로 끝나는 8주)이다.
  Future<ActivityCalendar> fetch({DateTime? from, DateTime? to});

  /// 그래프 색을 [color] 로 바꾼다. 아직 열지 않은 색이면 서버 오류로 올라온다.
  Future<GraphColorState> selectColor(String color);
}
