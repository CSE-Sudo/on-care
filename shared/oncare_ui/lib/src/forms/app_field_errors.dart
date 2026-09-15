/// 칸 아래 오류 문구를 **언제** 보일지 정하는 작은 상태(#1784).
///
/// - 처음 제출하기 전에는 아무 칸에도 오류를 보이지 않는다. 치기도 전에 빨간
///   글씨가 뜨면 틀린 것처럼 보인다.
/// - 제출하면 모든 칸을 검사해 틀린 칸에 오류를 보인다.
/// - 한 번 오류를 보인 칸은 그 뒤로 입력하는 대로 다시 검사한다. 고치는 순간
///   문구가 사라지고, 다시 틀리면 다시 뜬다.
///
/// 문구는 그릴 때마다 칸의 지금 값으로 [_check] 를 불러 만든다. 따로 들고 있지
/// 않으므로 값과 문구가 어긋나지 않는다. 화면은 입력이 바뀔 때 [isWatching] 이면
/// 다시 그리기만 하면 된다.
class AppFieldErrors<F> {
  AppFieldErrors(this._check);

  /// 칸 [F] 의 지금 값에 대한 오류 문구. 맞으면 null.
  final String? Function(F field) _check;

  /// 오류를 한 번이라도 보인 칸.
  final Set<F> _watched = <F>{};

  /// 칸 아래에 그릴 문구. 오류를 보인 적 없는 칸은 늘 null 이다.
  String? of(F field) => _watched.contains(field) ? _check(field) : null;

  /// 제출할 때 부른다. [fields] 를 모두 검사해 틀린 칸부터 오류를 보이고,
  /// 모두 맞으면 true — 그때만 요청을 보낸다.
  bool validate(Iterable<F> fields) {
    bool valid = true;
    for (final F field in fields) {
      if (_check(field) != null) {
        _watched.add(field);
        valid = false;
      }
    }
    return valid;
  }

  /// 입력하는 대로 다시 검사할 칸이 있는가. 없으면 입력마다 다시 그릴 필요가 없다.
  bool get isWatching => _watched.isNotEmpty;
}
