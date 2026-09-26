/// 이름 뒤에 붙는 조사를 받침에 맞춰 고른다.
///
/// `을(를)`·`은(는)` 처럼 둘 다 적어 두는 표기는 사람이 쓴 글로 읽히지
/// 않는다. 트레이너와 회원이 그대로 받는 문장이라, 기계가 쓴 티가 나는
/// 자리를 남기지 않는다(#1177). 백엔드의 `_topic` 과 같은 규칙이다.
library;

/// 마지막 글자를 소리 내어 읽었을 때 받침이 있는가.
///
/// 조사를 고르는 유일한 기준이다. 한글만 보던 때에는 `81%`·`1,916mg` 처럼
/// 숫자·단위로 끝나는 말이 전부 받침 없음으로 떨어져, 요약 문장의 조사가
/// 반쯤 어긋났다(#1177).
bool hasFinalConsonant(String word) {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return false;
  final last = trimmed.codeUnitAt(trimmed.length - 1);
  if (last >= 0xAC00 && last <= 0xD7A3) return (last - 0xAC00) % 28 != 0;
  // 숫자로 끝나면 그 숫자를 읽은 소리로 본다 — 영·일·삼·육·칠·팔에 받침이 있다.
  if (last >= 0x30 && last <= 0x39) {
    return const <int>{0, 1, 3, 6, 7, 8}.contains(last - 0x30);
  }
  // 화면에 쓰는 단위는 모두 모음으로 끝나게 읽힌다(퍼센트·밀리그램·그램·
  // 킬로칼로리). 그 밖의 라틴 문자도 같은 쪽으로 둔다 — 틀리더라도 `…를` 은
  // `…을` 보다 눈에 덜 걸린다.
  return false;
}

/// [word] 에 목적격 조사(`을`/`를`)를 붙인다.
String withObjectJosa(String word) =>
    '$word${hasFinalConsonant(word) ? '을' : '를'}';

/// [word] 에 주제격 조사(`은`/`는`)를 붙인다.
String withTopicJosa(String word) =>
    '$word${hasFinalConsonant(word) ? '은' : '는'}';
