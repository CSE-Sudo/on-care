import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/points_rules.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 회원 앱 포인트 적립 규칙이 원본 표와 같은가(#2906).
///
/// 원본은 `shared/oncare_rules/vectors/points_rules.json` 이고 서버
/// `points_service` 의 `EarnRule` 도 같은 파일로 대조한다. 목업 원장과 적립
/// 안내창이 이 enum 을 읽으므로, 여기가 어긋나면 데모와 실서버의 적립이 갈린다.
void main() {
  final Map<String, Object?> rules =
      loadSharedRuleVectors('points_rules')['rules']! as Map<String, Object?>;

  /// 서버 `EarnRule.reason` 과 같은 이름(enum 이름의 snake_case).
  String reasonOf(PointsRule r) => r.name.replaceAllMapped(
    RegExp('[A-Z]'),
    (Match m) => '_${m[0]!.toLowerCase()}',
  );

  test('규칙 목록이 원본 표와 같다', () {
    expect(PointsRule.values.map(reasonOf).toSet(), rules.keys.toSet());
  });

  for (final PointsRule rule in PointsRule.values) {
    test('${rule.name} 의 포인트·하루 한도·기록 종류가 원본 표와 같다', () {
      final Map<String, Object?> original =
          rules[reasonOf(rule)]! as Map<String, Object?>;
      expect(rule.sourceType, original['source_type']);
      expect(rule.points, original['points']);
      expect(rule.dailyCap, original['daily_cap']);
    });
  }
}
