/// 헬스장 찾기의 기준 좌표 — 지도 중심이자 조회 기준. (#324, #329)
///
/// 지도(`_GymMap`)와 목록 조회(`DioGymRepository`, `gymFinderResultsProvider`)가
/// **같은 값**을 써야 한다. 두 곳에 따로 두면 한쪽만 바뀌었을 때 지도 중심과 검색
/// 중심이 조용히 어긋난다.
///
/// 위치를 얻기 전의 초기 지도 영역이다. 위치 허용 후에는 사용자 좌표를 쓴다.
library;

const double kGymSearchLat = 37.5559;
const double kGymSearchLng = 126.9368;
