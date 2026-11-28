import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 운동 탭 `이번 주` 카드 = 규칙 문장 + AI 한 문장(#3549).
///
/// 식단 `이번 주` 카드처럼 수치는 규칙 문장이 말하고, AI 문장은 잘한 운동과 다음
/// 운동을 짚는다. AI 문장이 없으면(기록 없는 주, AI 실패, 옛 서버) 규칙 문장만이다.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  test('ai_sentence 를 읽어 규칙 문장 뒤에 잇는다', () {
    final ExerciseAdvice advice = ExerciseAdvice.fromJson(<String, Object?>{
      'message': '이번 주 3일, 모두 90분 운동했어요.',
      'advice_key': 'record_week_balanced',
      'advice_params': <String, Object?>{'days': 3, 'minutes': 90},
      'ai_sentence': '주말에 스트레칭을 더해요.',
    });

    expect(advice.aiSentence, '주말에 스트레칭을 더해요.');
    expect(
      exerciseAdviceText(ko, advice),
      '${ko.exerciseAdviceRecordWeekBalanced(3, 90)} 주말에 스트레칭을 더해요.',
    );
  });

  test('키를 모르면 받은 규칙 문장 뒤에 잇는다', () {
    final ExerciseAdvice advice = ExerciseAdvice.fromJson(<String, Object?>{
      'message': '서버 규칙 문장이에요.',
      'advice_key': 'future_key',
      'ai_sentence': '주말에 스트레칭을 더해요.',
    });

    expect(exerciseAdviceText(ko, advice), '서버 규칙 문장이에요. 주말에 스트레칭을 더해요.');
  });

  for (final Object? missing in <Object?>[null, '', '   ', 3]) {
    test('ai_sentence 가 없거나 비면 규칙 문장만이다 ($missing)', () {
      final ExerciseAdvice advice = ExerciseAdvice.fromJson(<String, Object?>{
        'message': '서버 규칙 문장이에요.',
        'ai_sentence': missing,
      });

      expect(advice.aiSentence, isNull);
      expect(exerciseAdviceText(ko, advice), '서버 규칙 문장이에요.');
    });
  }
}
