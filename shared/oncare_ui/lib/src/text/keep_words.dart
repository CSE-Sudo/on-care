/// 폭 없는 줄바꿈 금지 문자(U+2060 WORD JOINER).
const String kWordJoiner = '⁠';

/// 줄이 **띄어쓰기에서만** 바뀌게 한다 — 두 앱의 서술형 문장(조언·분석·AI 답변·혜택
/// 안내)이 쓴다. (#2969)
///
/// 한 덩어리 Text 로 두면 한글은 음절 사이 어디서나 끊겨 `단백` / `질`, `김` /
/// `치찌개` 처럼 갈린다. 낱말 안의 글자 사이마다 줄바꿈 금지 문자를 끼워 낱말을
/// 통째로 넘긴다. 한 낱말이 한 줄보다 길면 Flutter 가 그 안에서 끊는다.
///
/// 이미 거친 문장을 다시 넣어도 같다 — 공용 카드가 넣고 호출부도 넣는 일이 있다.
/// 화면 글자를 찾는 테스트는 [withoutWordJoiners] 로 떼고 비교한다.
String keepWords(String text) => withoutWordJoiners(text)
    .split(' ')
    .map((String word) => word.runes.map(String.fromCharCode).join(kWordJoiner))
    .join(' ');

/// [keepWords] 가 넣은 줄바꿈 금지 문자를 뗀다.
String withoutWordJoiners(String text) => text.replaceAll(kWordJoiner, '');
