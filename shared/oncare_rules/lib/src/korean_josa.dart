/// 이름 뒤에 붙는 한국어 조사(`을/를`·`은/는`·`이/가`·`으로/로`)를 고르는 규칙. (#1177, #2897)
///
/// 서버 `backend/app/services/korean_josa.py` 와 **같은 규칙**이다. 예전에는 서버·두
/// 앱에 받침 판정이 다섯 벌 있었고 규칙이 세 갈래였다 — 괄호로 끝나는 이름
/// (`레그 프레스(머신)`)이 어떤 문장에서는 `를`, 어떤 문장에서는 `을` 을 받았고,
/// 영문 이름에는 `을(를)` 처럼 두 꼴이 함께 적혔다.
///
/// 하나로 합친 규칙:
///
/// 1. 끝의 공백과 닫는 괄호(`)`·`]`·`}`)를 벗기고 그 앞 글자로 본다.
/// 2. 한글 음절이면 받침으로 본다.
/// 3. 숫자면 읽는 소리로 본다 — 영·일·삼·육·칠·팔(0·1·3·6·7·8)에 받침이 있다.
/// 4. 그 밖(영문·`%`·단위·빈 문자열)은 받침 없음으로 본다. 화면에 쓰는 단위는
///    모두 모음으로 끝나게 읽히고(퍼센트·밀리그램), 틀리더라도 `…를` 이 `…을` 보다
///    눈에 덜 걸린다. **두 꼴(`을(를)`)은 쓰지 않는다** — 사람이 쓴 글로 읽히지
///    않는다(#1177).
///
/// `으로/로` 는 받침이 `ㄹ` 이면 `로` 다(`3일로`·`덤벨 컬로`).
library;

/// 끝에서 벗겨 낼 공백·닫는 괄호.
final RegExp _trailing = RegExp(r'[\s)\]}]+$');

/// 받침 `ㄹ` 의 종성 번호.
const int _rieul = 8;

/// 판정에 쓰는 마지막 글자. 벗기고 나서 비면 null.
int? _lastRune(String word) {
  final String stripped = word.replaceFirst(_trailing, '');
  if (stripped.isEmpty) return null;
  return stripped.runes.last;
}

bool _isHangulSyllable(int rune) => rune >= 0xAC00 && rune <= 0xD7A3;

bool _isDigit(int rune) => rune >= 0x30 && rune <= 0x39;

/// 공백·닫는 괄호를 벗긴 뒤 한글 음절로 끝나는가.
///
/// "받침을 판정할 수 없다" 가 아니라 "한글 이름이 아니다" 를 뜻한다 — 조언 문장이
/// 한글 이름이 아닐 때(`Squat`, `플랭크 60`) 조사 없이 읽히는 다른 틀(`_plain`)을
/// 고르는 기준이다. 서버 `korean_josa.ends_with_hangul` 과 같다.
bool endsWithHangul(String word) {
  final int? last = _lastRune(word);
  return last != null && _isHangulSyllable(last);
}

/// 마지막 글자를 소리 내어 읽었을 때 받침이 있는가. 규칙은 이 파일 머리말.
bool hasFinalConsonant(String word) {
  final int? last = _lastRune(word);
  if (last == null) return false;
  if (_isHangulSyllable(last)) return (last - 0xAC00) % 28 != 0;
  if (_isDigit(last)) {
    return const <int>{0, 1, 3, 6, 7, 8}.contains(last - 0x30);
  }
  return false;
}

/// 받침이 `ㄹ` 인가 — `으로/로` 만 이것을 본다. 숫자는 일·칠·팔(1·7·8)이다.
bool _finalIsRieul(String word) {
  final int? last = _lastRune(word);
  if (last == null) return false;
  if (_isHangulSyllable(last)) return (last - 0xAC00) % 28 == _rieul;
  if (_isDigit(last)) return const <int>{1, 7, 8}.contains(last - 0x30);
  return false;
}

/// [word] 뒤에 올 조사 — 받침이 있으면 [withFinal], 없으면 [withoutFinal].
///
/// `으로`/`로` 쌍이면 받침이 `ㄹ` 일 때도 `로` 다. 단어는 붙이지 않고 조사만
/// 돌려준다. 서버 `korean_josa.particle` 과 같다.
String josa(String word, String withFinal, String withoutFinal) {
  if (!hasFinalConsonant(word)) return withoutFinal;
  if (withFinal == '으로' && _finalIsRieul(word)) return withoutFinal;
  return withFinal;
}

/// [word] 에 [josa] 로 고른 조사를 붙인다.
String withJosa(String word, String withFinal, String withoutFinal) =>
    '$word${josa(word, withFinal, withoutFinal)}';
