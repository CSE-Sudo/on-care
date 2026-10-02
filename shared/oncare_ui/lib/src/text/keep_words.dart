/// 폭 없는 줄바꿈 금지 문자(U+2060 WORD JOINER).
///
/// 보이지 않는 문자라 이스케이프로 적는다 — 글자 그대로 적으면 읽을 수도,
/// 검색할 수도 없다.
const String kWordJoiner = '⁠';

/// 줄이 바뀌지 않는 공백(U+00A0).
const String kNoBreakSpace = ' ';

/// 줄이 **띄어쓰기에서만** 바뀌게 한다(#2908).
///
/// 한 덩어리 Text 로 두면 한글은 음절 사이 어디서나 끊겨 `분석` / `에 맞춘`,
/// `받아` / `요` 처럼 갈린다. 낱말 안의 글자 사이마다 [kWordJoiner] 를 끼워
/// 낱말을 통째로 넘긴다. 한 낱말이 한 줄보다 길면 Flutter 가 그 안에서 끊는다.
///
/// 회원 앱(분석용 식판 #2150, 주간 챌린지 #1789)과 트레이너 웹(MY 안내 문구)이
/// 같은 함수를 쓴다.
String keepWords(String text) => text
    .split(' ')
    .map((String word) => word.runes.map(String.fromCharCode).join(kWordJoiner))
    .join(' ');

/// 한 덩어리로 읽혀야 하는 글자를 **어디서도** 줄이 바뀌지 않게 잇는다(#2908).
///
/// [keepWords] 와 달리 띄어쓰기도 붙는 공백([kNoBreakSpace])으로 바꾼다 — 음식
/// 이름처럼 `그래놀` / `라 토핑` 은 물론 `그래놀라` / `토핑` 으로도 갈리면 안
/// 되는 짧은 글에 쓴다. 공백만 붙는 공백으로 바꾸면 모자라다 — 한국어는 음절
/// 사이 어디서든 줄이 바뀌므로 글자 사이마다 [kWordJoiner] 를 끼운다.
String keepTogether(String text) => text
    .replaceAll(' ', kNoBreakSpace)
    .runes
    .map(String.fromCharCode)
    .join(kWordJoiner);
