/// MY 프로필 이름 옆에 단 펫 이모지. (#2021)
///
/// 기간은 서버가 들고 있다(`GET /me/profile-pet`). 기간이 끝났으면 서버가 `pet` 을
/// 비워 보내므로, 앱은 받은 값이 있으면 그리고 없으면 그리지 않는다.
library;

class ProfilePet {
  const ProfilePet({required this.kind, required this.remainingSeconds});

  /// `dog`·`cat`. 앱이 모르는 값이면 그리지 않는다.
  final String kind;

  /// 남은 초 — 기기 시계가 틀어져도 남은 기간이 어긋나지 않는다.
  final int remainingSeconds;

  /// 응답의 `pet`. null 이면 달고 있지 않다.
  static ProfilePet? fromStateJson(Map<String, Object?> json) {
    final Object? raw = json['pet'];
    if (raw is! Map) return null;
    final Map<String, Object?> pet = raw.cast<String, Object?>();
    final int remaining = (pet['remaining_seconds'] as num?)?.toInt() ?? 0;
    if (remaining <= 0) return null;
    return ProfilePet(
      kind: (pet['kind'] as String?) ?? '',
      remainingSeconds: remaining,
    );
  }
}
