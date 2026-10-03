/// 직접 추가한 끼니의 멱등키에 이미 다른 끼니가 저장돼 있다 — 서버 409. (#3095)
///
/// 응답을 잃은 저장이 서버에는 남아 있고, 그 뒤 같은 키로 다른 내용이 왔다는
/// 뜻이다. 화면은 "이미 저장된 끼니가 있다" 를 알리고 기록을 다시 읽는다. 키는
/// 저장소가 버렸으므로 다시 저장하면 새 끼니로 남는다.
class DietEntryKeyConflict implements Exception {
  const DietEntryKeyConflict();

  @override
  String toString() => 'DietEntryKeyConflict';
}
