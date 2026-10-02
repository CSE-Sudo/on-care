import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_rules/oncare_rules.dart';

import '../../helpers/shared_rule_vectors.dart';

/// 회원 앱의 조사 고르기가 서버 `korean_josa` 와 같은 표를 쓰는가(#2897).
///
/// 운동 조언 문장은 서버(`exercise_advice`)와 데모(`period_advice`)가 같은 키·값을
/// 내고 앱이 ARB 로 그린다. 조사 판정이 서버와 갈리면 같은 이름이 실서버와 데모에서
/// 다른 조사를 받는다.
void main() {
  final List<Map<String, Object?>> cases = vectorRows(
    loadSharedRuleVectors('korean_josa'),
    'cases',
  );
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  group('공용 규칙 — 서버 korean_josa 와 같은 답', () {
    for (final Map<String, Object?> c in cases) {
      final String word = c['word']! as String;
      test('"$word"', () {
        expect(hasFinalConsonant(word), c['has_final']);
        expect(endsWithHangul(word), c['ends_with_hangul']);
        expect(josa(word, '을', '를'), c['obj']);
        expect(josa(word, '은', '는'), c['topic']);
        expect(josa(word, '이', '가'), c['subj']);
        expect(josa(word, '으로', '로'), c['dir']);
      });
    }
  });

  group('운동 조언 문장 — 두 꼴을 적지 않는다', () {
    String doneNext(String done) => exerciseAdviceText(
      ko,
      ExerciseAdvice(
        message: '',
        key: 'routine_today_done_next',
        params: <String, Object>{'done': done, 'next': '런지'},
      ),
    );

    test('괄호로 끝나는 이름은 괄호 앞 글자로 고른다', () {
      expect(doneNext('레그 프레스(머신)'), startsWith('레그 프레스(머신)을 마쳤어요.'));
    });

    test('숫자로 끝나는 이름은 읽는 소리로 고른다', () {
      expect(doneNext('플랭크 60'), startsWith('플랭크 60을 마쳤어요.'));
      expect(doneNext('하체 근력 2'), startsWith('하체 근력 2를 마쳤어요.'));
    });

    test('영문 이름에도 한 꼴만 붙는다 — 서버 exercise_advice 와 같다', () {
      final String text = doneNext('Squat');
      expect(text, startsWith('Squat를 마쳤어요.'));
      expect(text, isNot(contains('(를)')));
      expect(text, isNot(contains('을(')));
    });
  });

  group('데모 추천 운동 조언 — 한글 이름 판정이 서버와 같다', () {
    RoutineAdviceDay day(List<(String, bool)> items) => (
      date: DateTime.utc(2026, 9, 30),
      routines: <RoutineAdviceItem>[
        for (final (String name, bool done) in items)
          (
            name: name,
            type: 'strength',
            minutes: 10,
            done: done,
            completedMinutes: done ? 10 : null,
          ),
      ],
    );

    test('괄호로 끝나는 한글 이름은 마친 운동을 말한다', () {
      final ExerciseAdvice? advice = routineCoachAdvice(<RoutineAdviceDay>[
        day(<(String, bool)>[('레그 프레스(머신)', true), ('런지', false)]),
      ], kPeriodToday);
      expect(advice?.key, 'routine_today_done_next');
      expect(exerciseAdviceText(ko, advice!), startsWith('레그 프레스(머신)을 마쳤어요.'));
    });

    test('한글로 끝나지 않는 이름은 마친 운동 문장을 건너뛴다', () {
      final ExerciseAdvice? advice = routineCoachAdvice(<RoutineAdviceDay>[
        day(<(String, bool)>[('Squat', true), ('런지', false)]),
      ], kPeriodToday);
      expect(advice?.key, isNot('routine_today_done_next'));
      expect(advice?.key, isNot('routine_today_done_next_order'));
    });
  });
}
