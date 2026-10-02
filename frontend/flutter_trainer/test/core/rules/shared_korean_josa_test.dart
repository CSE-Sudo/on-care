import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/korean_josa.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart'
    show withParticle;
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 트레이너 웹의 조사 고르기가 서버 `korean_josa` 와 같은 표를 쓰는가(#2897).
///
/// 리포트 요약·주간 피드백 초안·루틴 확인 문구가 모두 이 규칙 하나를 쓴다 —
/// 서버가 만든 문장과 웹이 그린 문장이 같은 이름에 다른 조사를 붙이면 안 된다.
void main() {
  final List<Map<String, Object?>> cases = vectorRows(
    loadSharedRuleVectors('korean_josa'),
    'cases',
  );
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('공용 규칙 — 서버 korean_josa 와 같은 답', () {
    for (final Map<String, Object?> c in cases) {
      final String word = c['word']! as String;
      test('"$word"', () {
        expect(hasFinalConsonant(word), c['has_final']);
        expect(endsWithHangul(word), c['ends_with_hangul']);
        expect(withObjectJosa(word), '$word${c['obj']}');
        expect(withTopicJosa(word), '$word${c['topic']}');
        expect(withParticle(ko, word, '이', '가'), '$word${c['subj']}');
        expect(withParticle(ko, word, '으로', '로'), '$word${c['dir']}');
      });
    }
  });

  test('괄호로 끝나는 이름은 괄호 앞 글자로 고른다 — 서버 _topic 과 같다', () {
    expect(withTopicJosa('레그 프레스(머신)'), '레그 프레스(머신)은');
    expect(withObjectJosa('레그 프레스(머신)'), '레그 프레스(머신)을');
  });

  test('받침 ㄹ 뒤 으로는 로다', () {
    expect(withParticle(ko, '3일', '으로', '로'), '3일로');
    expect(withParticle(ko, '덤벨 컬', '으로', '로'), '덤벨 컬로');
    expect(withParticle(ko, '코어 스트레칭', '으로', '로'), '코어 스트레칭으로');
  });

  test('영어에는 조사를 붙이지 않는다', () {
    expect(withParticle(en, 'Squat', '을', '를'), 'Squat');
  });
}
