/// 폭 없는 줄바꿈 금지 문자(U+2060 WORD JOINER).
const String _wordJoiner = '⁠';

/// 줄이 **띄어쓰기에서만** 바뀌게 한다 — 회원 앱 `keepWords` 와 같은 방법이다.
///
/// 한 덩어리 Text 로 두면 한글은 음절 사이 어디서나 끊겨 `회원 계` / `정과`
/// 처럼 갈린다. 낱말 안의 글자 사이마다 줄바꿈 금지 문자를 끼워 낱말을 통째로
/// 넘긴다. 한 낱말이 한 줄보다 길면 Flutter 가 그 안에서 끊는다.
String keepWords(String text) => text
    .split(' ')
    .map((String word) => word.runes.map(String.fromCharCode).join(_wordJoiner))
    .join(' ');
