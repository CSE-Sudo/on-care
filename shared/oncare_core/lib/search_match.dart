/// 사람이 치는 검색어를 이름·주소와 비교하는 규칙 — 두 앱의 헬스장 찾기가 함께 쓴다.
/// (#3223)
///
/// 서버의 등록 헬스장 검색(`backend/app/services/trainer_gym_search.py`)과 같은
/// 규칙이다.
///
/// - 대소문자를 보지 않는다.
/// - 띄어쓰기를 보지 않는다 — `온케어짐신촌` 이 `온케어짐 신촌점` 을 찾는다.
/// - 검색어를 띄어쓰기로 나눈 **모든 단어**가 비교 대상 어딘가에 있으면 일치다.
///   단어 순서는 보지 않는다 — `신촌 헬스메이트` 가 `헬스메이트 신촌점` 을 찾는다.
///
/// 예전에는 검색어 전체를 `contains` 한 번으로 비교해, 띄어쓰기나 순서만 달라도
/// 목록에 있는 헬스장이 빠졌다.
library;

final RegExp _whitespace = RegExp(r'\s+');

/// 비교용으로 고친 글자 — 소문자로 바꾸고 띄어쓰기를 모두 뺀다.
String normalizeSearchText(String text) =>
    text.toLowerCase().replaceAll(_whitespace, '');

/// [query] 를 비교할 단어로 나눈다. 빈 검색어는 빈 목록이다.
List<String> searchTerms(String query) => <String>[
  for (final String term in query.toLowerCase().split(_whitespace))
    if (term.isNotEmpty) term,
];

/// [fields](이름·주소 등) 가 [query] 에 맞는가. 빈 검색어는 모두 맞는다 —
/// 검색 칸을 비우면 목록 전체가 보여야 한다.
bool matchesSearchQuery(String query, Iterable<String> fields) {
  final List<String> terms = searchTerms(query);
  if (terms.isEmpty) return true;
  final List<String> haystack = <String>[
    for (final String field in fields) normalizeSearchText(field),
  ];
  return terms.every(
    (String term) => haystack.any((String field) => field.contains(term)),
  );
}
