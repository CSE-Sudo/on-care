import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/demo/demo_ai_advice.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/ai_advice_text.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 조언 필드만 다르게 둔 최소 요약.
DashboardSummary _summary({
  String? adviceKey,
  String? dietKey,
  Map<String, Object> dietParams = const <String, Object>{},
  String? exerciseKey,
  int cardioMinutes = 0,
  String? sodiumWarning,
}) => DashboardSummary(
  indicators: const <HealthIndicator>[],
  macros: const DietMacros.zero(),
  dietEntries: 0,
  exerciseMinutes: cardioMinutes,
  exerciseCardioMinutes: cardioMinutes,
  sodiumWarning: sodiumWarning,
  aiAdviceKey: adviceKey,
  dietAdviceKey: dietKey,
  dietAdviceParams: dietParams,
  exerciseAdviceKey: exerciseKey,
);

/// 홈 '오늘의 AI 통합 조언'은 식단 문장과 운동 문장을 잇는다(#3549).
///
/// 예전에는 한 가지 키만 골라, 나트륨 경고가 있는 날은 운동을, 없는 날은 식단을
/// 빠뜨려 체험하기 카드보다 훨씬 짧았다. 두 문장 모두 규칙 문장이라 AI 를 부르지
/// 않는다. 체험하기(데모 키)는 그대로다.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  group('식단 문장 + 운동 문장', () {
    test('나트륨 경고 뒤에 운동 문장이 이어진다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          adviceKey: 'sodium_over',
          dietKey: 'sodium_over',
          exerciseKey: 'exercise_more',
          cardioMinutes: 40,
        ),
      );

      expect(
        body,
        '${ko.homeAdviceSodiumOver} ${ko.homeAdviceExerciseMore(40)}',
      );
    });

    test('음식 이름이 든 경고는 다음 끼니 행동을 함께 말한다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          adviceKey: 'sodium_over_sources',
          dietKey: 'sodium_over_sources',
          dietParams: const <String, Object>{
            'foods': <String>['짬뽕', '김치'],
          },
          exerciseKey: 'exercise_on_track',
          cardioMinutes: 160,
        ),
      );

      expect(
        body,
        '짬뽕·김치 섭취로 나트륨이 높아요. ${ko.homeAdviceSodiumNextMeal} '
        '${ko.homeAdviceExerciseOnTrack(160)}',
      );
    });

    test('나트륨이 목표 안인 날도 식단을 말한다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          adviceKey: 'exercise_cardio_start',
          dietKey: 'diet_ok',
          exerciseKey: 'exercise_cardio_start',
        ),
      );

      expect(
        body,
        '${ko.homeAdviceDietOk} ${ko.homeAdviceExerciseCardioStart}',
      );
    });

    test('기록이 없는 날은 두 쪽 모두 기록을 권한다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          adviceKey: 'exercise_start',
          dietKey: 'diet_empty',
          exerciseKey: 'exercise_start',
        ),
      );

      expect(body, '${ko.homeAdviceDietEmpty} ${ko.homeAdviceExerciseStart}');
    });

    test('이은 문장은 체험하기 카드에 가까운 분량이다', () {
      final List<DashboardSummary> cases = <DashboardSummary>[
        _summary(dietKey: 'diet_empty', exerciseKey: 'exercise_start'),
        _summary(dietKey: 'diet_ok', exerciseKey: 'exercise_more'),
        _summary(dietKey: 'sodium_over', exerciseKey: 'exercise_on_track'),
        _summary(
          dietKey: 'sodium_over_sources',
          dietParams: const <String, Object>{
            'foods': <String>['짬뽕', '김치찌개'],
          },
          exerciseKey: 'exercise_cardio_start',
        ),
      ];
      for (final DashboardSummary summary in cases) {
        final int length = aiAdviceBody(ko, summary).length;
        expect(
          length,
          inInclusiveRange(55, 110),
          reason: summary.dietAdviceKey,
        );
      }
    });
  });

  group('이어 붙이지 않는 경우', () {
    test('체험하기 데모 키는 새 키보다 먼저다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          adviceKey: kDailyCombinedAdviceKey,
          dietKey: 'diet_ok',
          exerciseKey: 'exercise_more',
        ),
      );

      expect(body, ko.homeAiAdviceBody);
    });

    test('새 키가 없는 옛 서버 응답은 한 가지 키를 그대로 쓴다', () {
      final String body = aiAdviceBody(ko, _summary(adviceKey: 'sodium_over'));

      expect(body, ko.homeAdviceSodiumOver);
    });

    test('한쪽 키를 모르면 예전 방식으로 넘어간다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          adviceKey: 'exercise_start',
          dietKey: 'diet_unknown_future',
          exerciseKey: 'exercise_start',
        ),
      );

      expect(body, ko.homeAdviceExerciseStart);
    });

    test('음식 이름이 비면 예전 방식(받은 문장)으로 넘어간다', () {
      final String body = aiAdviceBody(
        ko,
        _summary(
          dietKey: 'sodium_over_sources',
          exerciseKey: 'exercise_start',
          sodiumWarning: '서버 문장',
        ),
      );

      expect(body, '서버 문장');
    });
  });

  test('응답에서 식단·운동 문장 키를 읽는다', () {
    final DashboardSummary summary = DashboardSummary.fromJson(
      <String, Object?>{
        'indicators': <Object?>[],
        'diet_entries': 1,
        'exercise_minutes': 30,
        'exercise_cardio_minutes': 30,
        'sodium_warning': null,
        'diet_advice_key': 'sodium_over_sources',
        'diet_advice_params': <String, Object?>{
          'foods': <Object?>['라면'],
          'ignored': null,
        },
        'exercise_advice_key': 'exercise_more',
      },
    );

    expect(summary.dietAdviceKey, 'sodium_over_sources');
    expect(summary.dietAdviceParams, <String, Object>{
      'foods': <Object?>['라면'],
    });
    expect(summary.exerciseAdviceKey, 'exercise_more');
  });

  test('새 키가 없는 옛 응답은 null·빈 값이다', () {
    final DashboardSummary summary =
        DashboardSummary.fromJson(<String, Object?>{
          'indicators': <Object?>[],
          'diet_entries': 0,
          'exercise_minutes': 0,
          'sodium_warning': null,
        });

    expect(summary.dietAdviceKey, isNull);
    expect(summary.dietAdviceParams, isEmpty);
    expect(summary.exerciseAdviceKey, isNull);
  });
}
