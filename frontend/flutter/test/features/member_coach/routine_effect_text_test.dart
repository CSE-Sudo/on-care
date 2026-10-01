/// 코치 루틴 효과 한 줄이 화면 언어를 따른다(#2725).
///
/// 서버·데모가 채우는 공용 효과 표의 한국어 문장을 회원 앱이 알아보고 영어
/// 화면에서는 영어 문구로 바꾼다. 표가 늘었는데 번역을 빠뜨리면 여기서 잡힌다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/member_coach/presentation/routine_effect_text.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

final RegExp _hangul = RegExp('[가-힣]');

/// 공용 효과 표의 빈 칸이 아닌 문장 전부.
Set<String> _tableSentences() {
  final Map<String, Object?> table =
      jsonDecode(
            File(
              '../../shared/routine_effects/routine_effects.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final Set<String> out = <String>{};
  void collect(Object? node) {
    if (node is String && node.isNotEmpty) out.add(node);
    if (node is Map) node.values.forEach(collect);
  }

  collect(table['default']);
  collect(table['by_goal']);
  return out;
}

void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  test('공용 표의 모든 문장이 영어로 옮겨진다', () {
    final Set<String> sentences = _tableSentences();
    expect(sentences, isNotEmpty);
    for (final String sentence in sentences) {
      final String text = routineEffectText(en, sentence);
      expect(_hangul.hasMatch(text), isFalse, reason: sentence);
    }
  });

  test('한국어 화면은 표의 문장 그대로다', () {
    for (final String sentence in _tableSentences()) {
      expect(routineEffectText(ko, sentence), sentence);
    }
  });

  test('트레이너가 직접 쓴 문장은 그대로 둔다', () {
    expect(routineEffectText(en, '오른쪽 어깨 보호'), '오른쪽 어깨 보호');
  });
}
