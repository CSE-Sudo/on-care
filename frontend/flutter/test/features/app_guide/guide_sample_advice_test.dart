/// 앱 사용 가이드의 예시 식단·운동 조언이 화면 언어를 따르는지. (#2644)
///
/// 가이드는 조언 provider 를 예시 자료로 덮는다. 예전에는 키 없이 한국어 문장만
/// 넣어, 조언 카드가 받은 문장을 그대로 그리는 바람에 영어 가이드에서도 한국어
/// 조언이 나왔다. 이제 서버와 같은 문장 키로 싣는다.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/features/app_guide/domain/guide_sample_data.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

final RegExp _hangul = RegExp('[가-힣]');

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('예시 식단 조언', () {
    test('두 문장 모두 아는 키다', () {
      final DietAdviceLine analysis = kGuideSampleDietAdvice.analysis!;
      final DietAdviceLine action = kGuideSampleDietAdvice.action!;

      expect(dietAdviceKeyText(en, analysis.key!, analysis.params), isNotNull);
      expect(dietAdviceKeyText(en, action.key!, action.params), isNotNull);
    });

    test('영어 화면에서 한글이 없다', () {
      final String text = dietAdviceText(en, kGuideSampleDietAdvice);
      expect(text, isNotEmpty);
      expect(text, isNot(matches(_hangul)));
    });

    test('한국어 화면은 받은 한국어 문장과 같은 뜻이다', () {
      // 키를 풀지 못할 때 쓰는 문장(`text`)이 ARB 한국어와 어긋나지 않는지.
      final DietAdviceLine analysis = kGuideSampleDietAdvice.analysis!;
      final DietAdviceLine action = kGuideSampleDietAdvice.action!;
      expect(dietAdviceKeyText(ko, action.key!, action.params), action.text);
      expect(
        dietAdviceKeyText(ko, analysis.key!, analysis.params),
        contains('균형이 좋아요'),
      );
    });

    test('예시 하루(1,480kcal)와 같은 수치를 말한다', () {
      expect(
        kGuideSampleDietAdvice.analysis!.params['kcal'],
        guideSampleDietDay(ko).totalCalories,
      );
    });
  });

  group('예시 운동 조언', () {
    test('아는 키이고 영어 화면에서 한글이 없다', () {
      final String text = exerciseAdviceText(en, kGuideSampleExerciseAdvice);
      expect(text, isNot(kGuideSampleExerciseAdvice.message));
      expect(text, isNot(matches(_hangul)));
    });

    test('한국어 문장은 받은 문장과 같다', () {
      expect(
        exerciseAdviceText(ko, kGuideSampleExerciseAdvice),
        kGuideSampleExerciseAdvice.message,
      );
    });

    test('예시 한 주(3일 95분)와 같은 수치를 말한다', () {
      final Map<String, Object> p = kGuideSampleExerciseAdvice.params;
      expect(p['minutes'], kGuideSampleWeek.totalMinutes);
      final int activeDays = kGuideSampleWeek.dailyMinutes
          .where((double m) => m > 0)
          .length;
      expect(p['days'], activeDays);
    });
  });

  group('가이드 덮어쓰기', () {
    test('조언 provider 가 키가 있는 예시 조언을 돌려준다', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: guideSampleOverrides(en),
      );
      addTearDown(container.dispose);

      final DietAdvice diet = await container.read(
        dietAdviceProvider((period: kPeriodToday, lang: 'en')).future,
      );
      expect(diet.analysis?.key, isNotNull);

      final ExerciseAdvice exercise = await container.read(
        exerciseAdviceProvider(kPeriodWeek).future,
      );
      expect(exercise.key, isNotNull);
    });
  });
}
