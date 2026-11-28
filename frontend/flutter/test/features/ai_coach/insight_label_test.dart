/// 참고 기록의 감지 부위 이름은 한국어로 적는다(#2736).
///
/// 저장된 감지 기록에는 영문 부위 이름(`Knee`)도 남아 있다. 화면은 둘 다
/// 알아보고 한국어 이름으로 감지 이름을 만든다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/presentation/widgets/insight_history_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

ChatInsight _pain(String part) =>
    ChatInsight(kind: ChatInsightKind.discomfort, bodyPart: part);

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  test('영문으로 감지된 부위도 한국어로 적는다', () {
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
      expect(insightBodyPartLabel(ko, part), contains(RegExp('[가-힣]')));
    }
  });

  test('모르는 부위 이름은 그대로 둔다', () {
    expect(insightBodyPartLabel(ko, '팔꿈치'), '팔꿈치');
  });
}
