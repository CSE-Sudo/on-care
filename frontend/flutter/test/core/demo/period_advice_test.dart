/// 기간별 운동 조언 문장 규칙. (#1574) — 식단은 `diet_advice_test.dart`(#2255).
///
/// 서버(`exercise_service.period_coach_message`)가 원본이고 데모가 같은 규칙을 재현한다. 여기서 확인하는 것은 두 가지다 —
/// 기간마다 **다른 재료를 보고 다른 말을 하는가**, 그리고 없는 기록으로 조언을
/// 지어내지 않는가.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/demo/period_advice.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

ExerciseDayTotals _exercise(
  String date, {
  int minutes = 30,
  int calories = 270,
  Map<String, int> byType = const <String, int>{'cardio': 30},
}) => (
  date: DateTime.parse(date),
  minutes: minutes,
  calories: calories,
  byType: Map<String, int>.of(byType),
);

void main() {
  group('운동', () {
    test('기록이 없으면 기간마다 다른 안내를 남긴다', () {
      final Set<String> messages = <String>{
        for (final String period in <String>[
          kPeriodToday,
          kPeriodWeek,
          kPeriodAll,
        ])
          exercisePeriodAdvice(const <ExerciseDayTotals>[], period),
      };
      expect(messages.length, 3);
    });

    test('오늘은 그날 한 운동과 소모 칼로리를 말한다', () {
      final String today = exercisePeriodAdvice(<ExerciseDayTotals>[
        _exercise('2026-08-27', minutes: 45, calories: 400),
      ], kPeriodToday);
      expect(today, contains('45분'));
      expect(today, contains('400kcal'));
      expect(today, contains('유산소'));
    });

    test('이번 주는 한 유형에 쏠렸는지를 먼저 짚는다', () {
      final List<ExerciseDayTotals> cardioOnly = <ExerciseDayTotals>[
        _exercise('2026-08-24'),
        _exercise('2026-08-25'),
        _exercise('2026-08-26'),
      ];
      final String week = exercisePeriodAdvice(cardioOnly, kPeriodWeek);
      expect(week, contains('유산소'));
      expect(week, contains('근력'));
      expect(week, isNot(exercisePeriodAdvice(cardioOnly, kPeriodToday)));

      final String mixed = exercisePeriodAdvice(<ExerciseDayTotals>[
        _exercise('2026-08-24'),
        _exercise('2026-08-25', byType: <String, int>{'strength': 30}),
        _exercise('2026-08-26', byType: <String, int>{'stretching': 30}),
      ], kPeriodWeek);
      expect(mixed, contains('고르게'));
    });

    test('전체는 최근 4주 추세를 본다', () {
      final List<ExerciseDayTotals> days = <ExerciseDayTotals>[
        for (int i = 0; i < 20; i++)
          _exercise(
            DateTime(2026, 6, 1 + i).toIso8601String().split('T').first,
            minutes: 10,
          ),
        for (int i = 0; i < 20; i++)
          _exercise(
            DateTime(2026, 8, 1 + i).toIso8601String().split('T').first,
            minutes: 60,
          ),
      ];
      expect(exercisePeriodAdvice(days, kPeriodAll), contains('최근 4주'));
    });

    test('조언은 짧다 — 카드 한 줄 반을 넘기지 않는다', () {
      final List<String> messages = <String>[
        exercisePeriodAdvice(<ExerciseDayTotals>[
          _exercise('2026-08-27', minutes: 45, calories: 400),
        ], kPeriodToday),
        exercisePeriodAdvice(<ExerciseDayTotals>[
          _exercise('2026-08-24'),
          _exercise('2026-08-25'),
        ], kPeriodWeek),
        exercisePeriodAdvice(const <ExerciseDayTotals>[], kPeriodWeek),
      ];
      for (final String message in messages) {
        expect(message.length, lessThanOrEqualTo(45), reason: message);
      }
    });
  });

  // 서버와 **같은 사례 파일**을 읽는다(#2162, #2210). 서버 테스트
  // (`test_period_advice_copy.py`)도 이 파일로 같은 키·값·문장을 확인한다.
  group('운동 조언 — 서버와 같은 키·값·문장', () {
    final Map<String, dynamic> shared =
        jsonDecode(
              File(
                'test/core/demo/routine_advice_cases.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    List<RoutineAdviceDay> routineDays(List<dynamic> raw) => <RoutineAdviceDay>[
      for (final dynamic day in raw)
        (
          date: DateTime.parse((day as Map<String, dynamic>)['date'] as String),
          routines: <RoutineAdviceItem>[
            for (final dynamic item in day['routines'] as List<dynamic>)
              (
                name: (item as Map<String, dynamic>)['name'] as String,
                type: item['type'] as String,
                minutes: item['minutes'] as int,
                done: item['done'] as bool,
                completedMinutes: item['completed_minutes'] as int?,
              ),
          ],
        ),
    ];

    List<ExerciseDayTotals> records(List<dynamic> raw) => <ExerciseDayTotals>[
      for (final dynamic r in raw)
        _exercise(
          ((r as Map<String, dynamic>)['date']) as String,
          minutes: r['minutes'] as int,
          calories: r['calories'] as int,
          byType: (r['by_type'] as Map<String, dynamic>).map(
            (String k, dynamic v) => MapEntry<String, int>(k, v as int),
          ),
        ),
    ];

    Map<String, Object> params(Map<String, dynamic> raw) => <String, Object>{
      for (final MapEntry<String, dynamic> e in raw.entries)
        e.key: e.value as Object,
    };

    for (final dynamic raw in shared['cases'] as List<dynamic>) {
      final Map<String, dynamic> c = raw as Map<String, dynamic>;
      test('서버와 같은 조언 — ${c['name']}', () {
        final ExerciseAdvice advice = exercisePeriodAdviceOf(
          records(c['records'] as List<dynamic>),
          c['period'] as String,
          routineDays: routineDays(c['days'] as List<dynamic>),
        );
        final Map<String, dynamic> expected =
            c['expected'] as Map<String, dynamic>;
        expect(advice.key, expected['key']);
        expect(
          advice.params,
          params(expected['params'] as Map<String, dynamic>),
        );
        expect(advice.message, expected['message']);
        expect(advice.message.runes.length, lessThanOrEqualTo(kAdviceMaxLen));
      });
    }

    // 모든 키 × 대표 값 — 한국어 ARB 가 서버 문장과 글자까지 같은지, 영어 ARB 가
    // 빠짐없이 영어로 그리는지.
    final RegExp hangul = RegExp('[가-힣]');
    for (final dynamic raw in shared['renderings'] as List<dynamic>) {
      final Map<String, dynamic> r = raw as Map<String, dynamic>;
      final ExerciseAdvice advice = ExerciseAdvice(
        message: '',
        key: r['key'] as String,
        params: params(r['params'] as Map<String, dynamic>),
      );
      test('번역 — ${r['key']} ${r['params']}', () {
        expect(exerciseAdviceText(ko, advice), r['message']);
        final String english = exerciseAdviceText(en, advice);
        expect(english, isNotEmpty);
        // 값으로 들어간 운동 이름을 빼면 영어 문장에 한글이 없어야 한다.
        String rest = english;
        for (final Object value in advice.params.values) {
          if (value is String) rest = rest.replaceAll(value, '');
        }
        expect(rest.contains(hangul), isFalse, reason: english);
      });
    }

    test('모르는 키·맞지 않는 값이면 받은 한국어 문장을 쓴다', () {
      expect(
        exerciseAdviceText(
          en,
          const ExerciseAdvice(message: '서버 문장', key: 'future_key'),
        ),
        '서버 문장',
      );
      expect(
        exerciseAdviceText(
          en,
          const ExerciseAdvice(
            message: '서버 문장',
            key: 'routine_today_next',
            params: <String, Object>{'next': 3},
          ),
        ),
        '서버 문장',
      );
      expect(
        exerciseAdviceText(en, const ExerciseAdvice(message: '키 없는 문장')),
        '키 없는 문장',
      );
    });

    test('부위는 운동 이름으로 판정한다 — 서버와 같은 결과', () {
      (shared['body_parts'] as Map<String, dynamic>).forEach((
        String name,
        dynamic part,
      ) {
        expect(bodyPartOf(name), part, reason: name);
      });
    });

    test('오늘 걸린 추천이 있으면 그 목록으로 말하고, 없으면 기록 기준 조언이다', () {
      final List<ExerciseDayTotals> days = <ExerciseDayTotals>[
        _exercise('2026-09-23'),
      ];
      final String recordAdvice = exercisePeriodAdvice(days, kPeriodToday);
      expect(
        exercisePeriodAdvice(
          days,
          kPeriodToday,
          routineDays: <RoutineAdviceDay>[
            (
              date: DateTime.parse('2026-09-23'),
              routines: <RoutineAdviceItem>[],
            ),
          ],
        ),
        recordAdvice,
      );
      expect(
        exercisePeriodAdvice(
          days,
          kPeriodToday,
          routineDays: <RoutineAdviceDay>[
            (
              date: DateTime.parse('2026-09-23'),
              routines: <RoutineAdviceItem>[
                (
                  name: '스쿼트',
                  type: '근력',
                  minutes: 10,
                  done: false,
                  completedMinutes: null,
                ),
              ],
            ),
          ],
        ),
        '오늘은 스쿼트부터 시작해 보세요.',
      );
    });

    test('조언이 읽는 구간의 시작은 서버와 같다', () {
      final DateTime wednesday = DateTime(2026, 9, 23);
      expect(routineAdviceFetchStart(kPeriodToday, wednesday), wednesday);
      // 이번 주는 지난주 월요일부터 — 월·화에 지난주를 돌아본다.
      expect(
        routineAdviceFetchStart(kPeriodWeek, wednesday),
        DateTime(2026, 9, 14),
      );
      expect(
        routineAdviceFetchStart(kPeriodAll, wednesday),
        DateTime(2026, 7, 2),
      );
    });
  });
}
