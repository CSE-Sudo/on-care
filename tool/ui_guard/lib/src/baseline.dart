import 'dart:convert';

import 'rules.dart';

/// 파일 경로(앱 디렉터리 기준) → 항목 → 개수. 개수가 0 인 항목·파일은 두지 않는다.
typedef Counts = Map<String, Map<Rule, int>>;

/// 기준선과 현재 개수가 다른 곳 하나.
class Difference {
  const Difference(this.path, this.rule, this.baseline, this.actual);

  final String path;
  final Rule rule;
  final int baseline;
  final int actual;

  bool get increased => actual > baseline;
}

/// 기준선과 현재를 비교해 다른 곳을 경로·항목 순으로 돌려준다.
List<Difference> compare(Counts baseline, Counts actual) {
  final paths = {...baseline.keys, ...actual.keys}.toList()..sort();
  final differences = <Difference>[];
  for (final path in paths) {
    for (final rule in Rule.values) {
      final before = baseline[path]?[rule] ?? 0;
      final now = actual[path]?[rule] ?? 0;
      if (before != now) differences.add(Difference(path, rule, before, now));
    }
  }
  return differences;
}

/// 기준선 JSON 을 읽는다. 모르는 항목 이름이 있으면 [FormatException].
Counts decodeBaseline(String json) {
  final raw = jsonDecode(json);
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('기준선은 {"경로": {"항목": 개수}} 객체여야 합니다.');
  }
  final counts = <String, Map<Rule, int>>{};
  raw.forEach((path, value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$path 의 값이 객체가 아닙니다.');
    }
    final byRule = <Rule, int>{};
    value.forEach((id, count) {
      final rule = Rule.byId(id);
      if (rule == null) throw FormatException('$path: 모르는 항목 "$id"');
      if (count is! int || count < 0) {
        throw FormatException('$path.$id: 개수는 0 이상의 정수여야 합니다.');
      }
      if (count > 0) byRule[rule] = count;
    });
    if (byRule.isNotEmpty) counts[path] = byRule;
  });
  return counts;
}

/// 경로는 가나다·알파벳 순, 항목은 [Rule] 선언 순으로 적어 diff 가 안정적이게 한다.
String encodeBaseline(Counts counts) {
  final paths = counts.keys.toList()..sort();
  final ordered = <String, Map<String, int>>{};
  for (final path in paths) {
    final byRule = <String, int>{};
    for (final rule in Rule.values) {
      final count = counts[path]![rule] ?? 0;
      if (count > 0) byRule[rule.id] = count;
    }
    if (byRule.isNotEmpty) ordered[path] = byRule;
  }
  return '${const JsonEncoder.withIndent('  ').convert(ordered)}\n';
}
