class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    this.emailIsPlaceholder = false,
    this.emailPlaceholderProvider,
    this.id = '',
  });
  final String name;
  final String email;

  /// [email] 이 소셜 가입의 대체 이메일(`kakao_…@social.oncare`)인가(#3338).
  /// 참이면 MY 카드는 주소 대신 가입 수단과 "이메일 미등록" 을 보여 준다.
  final bool emailIsPlaceholder;

  /// 대체 이메일을 만든 가입 수단(`kakao`·`google`). 대체 이메일이 아니면 null.
  final String? emailPlaceholderProvider;

  /// 회원 고유번호(`User.id`) — MY 탭이 "내 회원번호"로 보여주는 값이다.
  /// 트레이너웹의 신규 고객 등록이 이 값으로 회원을 찾아 연결한다.
  final String id;

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    name: json['name']! as String,
    email: json['email']! as String,
    emailIsPlaceholder: (json['email_is_placeholder'] as bool?) ?? false,
    emailPlaceholderProvider: switch (json['email_placeholder_provider']) {
      final String provider when provider.isNotEmpty => provider,
      _ => null,
    },
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
