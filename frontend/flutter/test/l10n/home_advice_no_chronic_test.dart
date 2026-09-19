/// 홈 `오늘의 AI 통합 조언` 이 만성질환을 전제로 말하지 않는지. (#2013)
///
/// 예전 문구는 `높아진 나트륨과 혈당을 낮추기 위해` 였다. 앱은 혈당을 재지
/// 않는다 — 재지 않는 지표를 근거처럼 말하면 근거 없는 단정이고 진단처럼
/// 읽힌다. 지금 타깃은 PT를 이용하는 회원이다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

void main() {
  test('기본 조언 문구에 만성질환 어휘가 없다', () {
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    for (final String word in <String>['혈당', '혈압', '고혈압', '당뇨']) {
      expect(ko.homeAiAdviceBody, isNot(contains(word)), reason: word);
    }

    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
    for (final String word in <String>[
      'blood sugar',
      'blood pressure',
      'diabetes',
      'hypertension',
    ]) {
      expect(en.homeAiAdviceBody.toLowerCase(), isNot(contains(word)));
    }
  });

  test('기록으로 뒷받침되는 이야기는 남는다', () {
    // 나트륨은 실제로 재는 값이라 조언의 근거가 된다 — 통째로 비우지 않는다.
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    expect(ko.homeAiAdviceBody, contains('나트륨'));
    expect(
      lookupAppLocalizations(const Locale('en')).homeAiAdviceBody.toLowerCase(),
      contains('sodium'),
    );
  });
}
