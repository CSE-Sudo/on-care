import 'package:oncare_core/search_match.dart';

/// Membership / candidate gym used by the 헬스장 tab of the exercise page.
/// Mirrors the prototype's `GymCard` + `GymFinder` data shape: card list
/// with rating, distance, tags, and hours.
///
/// Trainers are not part of this entity — a gym employs several of them, so
/// they live in `Trainer` keyed by [id]. Fetch them with
/// `GymRepository.fetchTrainersByGym`.
class Gym {
  const Gym({
    required this.id,
    required this.name,
    required this.address,
    required this.distanceKm,
    required this.rating,
    required this.tags,
    this.weekdayHours,
    this.weekendHours,
    this.phone,
    this.lat,
    this.lng,
  });

  final String id;
  final String name;
  final String address;
  final double distanceKm;
  final double rating;
  final List<String> tags;
  final String? weekdayHours;
  final String? weekendHours;
  final String? phone;

  /// 지도 핀 좌표. 좌표를 모르는 헬스장은 목록에만 뜨고 핀은 생략된다
  /// (제휴 데이터가 `/gyms/*` 로 옮겨가기 전까지는 비어 있을 수 있다 — #324).
  final double? lat;
  final double? lng;

  bool get hasCoordinates => lat != null && lng != null;

  /// 헬스장 찾기 검색 칸의 [query] 에 맞는가. 이름·주소·태그를 본다. (#3223)
  ///
  /// 트레이너 웹·서버와 같은 규칙이다([matchesSearchQuery]) — 대소문자·띄어쓰기·
  /// 단어 순서를 보지 않는다. 예전에는 검색어 전체를 `contains` 한 번으로 비교해
  /// `헬스메이트신촌`·`신촌 헬스메이트` 가 목록에 있는 `헬스메이트 신촌점` 을
  /// 걸러 냈다. 빈 검색어는 모두 맞는다.
  bool matchesQuery(String query) =>
      matchesSearchQuery(query, <String>[name, address, ...tags]);
}
