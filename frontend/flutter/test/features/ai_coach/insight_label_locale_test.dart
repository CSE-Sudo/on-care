/// 참고 기록의 감지 부위 이름이 화면 언어를 따른다(#2736).
///
/// 감지는 회원이 쓴 말의 언어로 부위를 돌려준다(`무릎`·`Knee`). 화면은 둘 다
/// 알아보고 화면 언어의 이름으로 감지 이름을 만든다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/presentation/widgets/insight_history_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

ChatInsight _pain(String part) =>
    ChatInsight(kind: ChatInsightKind.discomfort, bodyPart: part);

void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  test('영어 화면은 한국어로 감지된 부위도 영어로 적는다', () {
    expect(insightLabel(en, _pain('무릎')), 'Knee pain noted');
    expect(insightLabel(en, _pain('Knee')), 'Knee pain noted');
  });

  test('한국어 화면은 영어로 감지된 부위도 한국어로 적는다', () {
    expect(insightLabel(ko, _pain('Shoulder')), '어깨 통증 감지');
    expect(insightLabel(ko, _pain('어깨')), '어깨 통증 감지');
  });

  test('감지 규칙의 부위는 모두 번역이 있다', () {
    for (final String part in <String>[
      '무릎',
      '허리',
      '발목',
      '어깨',
      '손목',
      '목',
      'Knee',
      'Back',
      'Ankle',
      'Shoulder',
      'Wrist',
      'Neck',
    ]) {
      expect(insightBodyPartLabel(en, part), isNot(contains(RegExp('[가-힣]'))));
      expect(insightBodyPartLabel(ko, part), contains(RegExp('[가-힣]')));
    }
  });

  test('모르는 부위 이름은 그대로 둔다', () {
    expect(insightBodyPartLabel(en, '팔꿈치'), '팔꿈치');
  });
}
