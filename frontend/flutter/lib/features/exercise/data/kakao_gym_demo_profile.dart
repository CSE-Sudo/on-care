/// 카카오 Local 이 주지 않는 항목을 채우는 **시연용** 보강 데이터.
///
/// 카카오 Local 장소검색이 주는 것: 이름·주소·거리·좌표·전화
/// 카카오가 주지 않는 것: 평점·전문분야·영업시간·소속 트레이너
///
/// 키는 데모 픽스처의 **가상 비제휴 헬스장** id 다(#2811). 예전에는 신촌 실재 업체
/// 4곳의 카카오 place id 에 지어낸 평점·영업시간을 붙였는데, 실재 업체에 허위 정보를
/// 붙이는 것이라 가상 헬스장으로 바꿨다. 실재 업체 id 를 키로 다시 넣지 말 것.
/// 전화번호도 넣지 않는다 — 지어낸 번호가 실제 누군가의 번호일 수 있다.
///
/// 소속 트레이너는 `Gym` 이 아니라 `Trainer` 엔티티에 있으므로 여기 두지 않고
/// `MockGymRepository` 가 `gymId`(= 카카오 place id)로 들고 있다.
///
/// 키는 데모 픽스처(`local_api_interceptor`)와 백엔드 데모 시드(`seed_gyms`)가 같은
/// id 를 쓰므로 양쪽에 동일하게 매칭된다. 데모 경로에서만 붙는다.
class KakaoGymDemoProfile {
  const KakaoGymDemoProfile({
    required this.rating,
    required this.tags,
    this.phone,
    this.weekdayHours,
    this.weekendHours,
  });

  final double rating;
  final List<String> tags;
  final String? phone;
  final String? weekdayHours;
  final String? weekendHours;
}

/// 신촌 권역 가상 비제휴 헬스장 4곳 — 전부 시연용 값이다.
const Map<String, KakaoGymDemoProfile> kKakaoGymDemoProfiles =
    <String, KakaoGymDemoProfile>{
      // 온케어 핏스튜디오
      'gym-demo-fitstudio': KakaoGymDemoProfile(
        rating: 4.6,
        tags: <String>['다이어트', '체형 교정'],
        weekdayHours: '06:00 - 23:00',
        weekendHours: '09:00 - 18:00',
      ),
      // 온케어 무브랩
      'gym-demo-movelab': KakaoGymDemoProfile(
        rating: 4.4,
        tags: <String>['근력운동', '그룹 PT'],
        weekdayHours: '05:30 - 24:00',
        weekendHours: '08:00 - 20:00',
      ),
      // 온케어 PT랩
      'gym-demo-ptlab': KakaoGymDemoProfile(
        rating: 4.9,
        tags: <String>['PT 전문', '재활운동'],
        weekdayHours: '07:00 - 23:00',
        weekendHours: '10:00 - 17:00',
      ),
      // 온케어 1:1 스튜디오
      'gym-demo-onestudio': KakaoGymDemoProfile(
        rating: 4.7,
        tags: <String>['1:1 PT', '식단 관리'],
        weekdayHours: '08:00 - 22:00',
        weekendHours: '10:00 - 16:00',
      ),
    };
