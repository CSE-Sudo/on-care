/// 서버가 프로필 저장을 **이유를 들어** 거절한 경우의 사유(#2639).
enum ProfileUpdateRejection {
  /// 다른 계정이 이미 쓰는 이메일(409).
  emailTaken,

  /// 있던 연락처를 비우려 했다(422, 서버가 문장으로 준 거절).
  phoneRequired,

  /// 그 밖의 형식 검증 실패(422, 필드 검증 목록).
  invalid,
}

/// 프로필 저장이 거절됐다 — 화면이 어느 칸이 문제인지 말할 수 있게 사유를 싣는다.
///
/// "저장에 실패했어요. 잠시 후 다시 시도해 주세요" 는 다시 해 보면 될 때의 문구다.
/// 이메일이 이미 쓰이는 중이면 같은 값으로 몇 번을 눌러도 막히므로, 이 경우는 일시
/// 오류와 나눠서 올린다.
class ProfileUpdateRejected implements Exception {
  const ProfileUpdateRejected(this.reason);

  final ProfileUpdateRejection reason;

  /// 서버 응답(상태 코드·본문)을 거절 사유로. 이유를 들어 거절한 것이 아니면 null.
  ///
  /// `PUT /users/me` 의 409 는 이메일 중복뿐이다. 422 는 두 모양이다 — 연락처를
  /// 비우려 하면 서버가 문장(`detail: "..."`)으로, 스키마 검증에 걸리면 FastAPI 가
  /// 목록(`detail: [...]`)으로 준다(`backend/app/api/v1/users.py`).
  static ProfileUpdateRejected? fromResponse(int? statusCode, Object? body) {
    if (statusCode == 409) {
      return const ProfileUpdateRejected(ProfileUpdateRejection.emailTaken);
    }
    if (statusCode == 422) {
      final Object? detail = body is Map ? body['detail'] : null;
      return ProfileUpdateRejected(
        detail is String
            ? ProfileUpdateRejection.phoneRequired
            : ProfileUpdateRejection.invalid,
      );
    }
    return null;
  }

  @override
  String toString() => 'ProfileUpdateRejected(${reason.name})';
}
