class UserProfile {
  const UserProfile({required this.name, required this.email, this.id = ''});
  final String name;
  final String email;

  /// 회원 고유번호(`User.id`) — MY 탭이 "내 회원번호"로 보여주는 값이다.
  /// 트레이너웹의 신규 고객 등록이 이 값으로 회원을 찾아 연결한다.
  final String id;

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    name: json['name']! as String,
    email: json['email']! as String,
    id: (json['id'] as String?) ?? '',
  );
}

/// `GET /users/me/health` — MY 계정 카드의 회원 정보와 포인트 잔액.
///
/// 위험 문구·활동 순위·설정 메뉴는 화면이 읽지 않는 고정값이라 응답에서
/// 뺐다(#2903). 옛 서버가 아직 실어 보내도 여기서는 무시한다.
class MyHealthState {
  const MyHealthState({required this.profile, required this.activityPoints});

  final UserProfile profile;
  final int activityPoints;

  factory MyHealthState.fromJson(Map<String, Object?> json) => MyHealthState(
    profile: UserProfile.fromJson(json['profile']! as Map<String, Object?>),
    activityPoints: (json['activity_points']! as num).toInt(),
  );
}
