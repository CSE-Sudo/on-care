/// 식단 AI 맞춤 조언 — 데모와 앱 번역이 서버와 같은 말을 하는가. (#2255)
///
/// 서버(`backend/scripts/gen_diet_advice_cases.py`)가 만든 공유 사례 파일을 읽어
/// - 데모(`core/demo/diet_advice.dart`)가 같은 입력에 같은 규칙 한 줄·다음 할 일을 내는지,
/// - 앱 ARB 가 서버 문장 틀과 글자까지 같은지 본다.
/// 서버 쪽은 `backend/tests/test_diet_advice_cases.py` 가 같은 파일로 본다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/core/demo/diet_advice.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';
import 'package:oncare_ui/oncare_ui.dart' show keepWords;

final Map<String, Object?> _cases =
    jsonDecode(File('test/core/demo/diet_advice_cases.json').readAsStringSync())
        as Map<String, Object?>;

DemoDietEntry _entry(Map<String, Object?> e) => (
  date: e['date']! as String,
  mealType: e['meal_type']! as String,
  foods: (e['foods']! as List<Object?>).cast<String>(),
  kcal: e['kcal']! as num,
  proteinG: e['protein_g']! as num,
  sodiumMg: e['sodium_mg']! as num,
  sugarG: e['sugar_g']! as num,
  carbsG: e['carbs_g']! as num,
  fatG: e['fat_g']! as num,
);

Map<String, Object?> _params(Object? raw) =>
    Map<String, Object?>.from(raw! as Map<String, Object?>);

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));

  group('데모 = 서버', () {
    for (final Object? raw in _cases['cases']! as List<Object?>) {
      final Map<String, Object?> c = raw! as Map<String, Object?>;
      // 공유 사례 파일은 서버 생성기가 만든다. 앱은 한국어 사례만 본다.
      if (((c['lang'] as String?) ?? 'ko') != 'ko') continue;
      test('${c['name']}', () {
        final Map<String, Object?> t = c['targets']! as Map<String, Object?>;
        final Map<String, Object?> res = demoDietAdvice(
          period: c['period']! as String,
          now: DateTime.parse(c['now']! as String),
          entries: <DemoDietEntry>[
            for (final Object? e in c['entries']! as List<Object?>)
              _entry(e! as Map<String, Object?>),
          ],
          targets: (
            calories: t['calories']! as int,
            proteinG: t['protein_g']! as int,
            sodiumMg: t['sodium_mg']! as int,
            sugarG: t['sugar_g']! as int,
          ),
          recent: <String>{
            for (final Object? n
                in (c['recent'] as List<Object?>?) ?? <Object?>[])
              normName(n! as String),
          },
          lastKind: c['last_kind'] as String?,
        );
        final Map<String, Object?> expected =
            c['expected']! as Map<String, Object?>;
        final Map<String, Object?> analysis =
            expected['analysis']! as Map<String, Object?>;
        expect(res['analysis_key'], analysis['key']);
        expect(_params(res['analysis_params']), _params(analysis['params']));
        expect(res['analysis'], analysis['text']);

        final Map<String, Object?>? action =
            expected['action'] as Map<String, Object?>?;
        expect(res['action_key'], action?['key']);
        if (action != null) {
          expect(_params(res['action_params']), _params(action['params']));
          expect(res['action'], action['text']);
        }
        if (expected.containsKey('from_date')) {
          expect(res['from_date'], expected['from_date']);
          expect(res['to_date'], expected['to_date']);
        }
        expect((res['message']! as String).contains('**'), isFalse);
      });
    }

    test('메뉴 리스트는 서버의 카탈로그 리스트와 같다', () {
      final Map<String, Object?> plan =
          _cases['demo_plan']! as Map<String, Object?>;
      expect(
        <Map<String, Object?>>[
          for (final DemoPlanMenu m in kDemoMenuPlan['ko']!)
            <String, Object?>{
              'slot': m.slot,
              'name': m.name,
              'tag': m.tag,
              'keyword': m.keyword,
            },
        ],
        <Map<String, Object?>>[
          for (final Object? m in plan['ko']! as List<Object?>)
            <String, Object?>{
              for (final String k in <String>['slot', 'name', 'tag', 'keyword'])
                k: (m! as Map<String, Object?>)[k],
            },
        ],
      );
    });
  });

  group('번역', () {
    for (final Object? raw in _cases['renderings']! as List<Object?>) {
      final Map<String, Object?> r = raw! as Map<String, Object?>;
      final String key = r['key']! as String;
      final Map<String, Object> params = <String, Object>{
        for (final MapEntry<String, Object?> e
            in (r['params']! as Map<String, Object?>).entries)
          e.key: e.value!,
      };
      test('$key $params', () {
        expect(dietAdviceKeyText(ko, key, params), r['text']);
      });
    }

    test('모르는 키·맞지 않는 값이면 받은 문장을 쓴다', () {
      const DietAdviceLine unknown = DietAdviceLine(
        text: '서버가 새로 보낸 문장',
        key: 'brand_new_key',
      );
      expect(dietAdviceLineText(ko, unknown), '서버가 새로 보낸 문장');
      const DietAdviceLine broken = DietAdviceLine(
        text: '받은 문장',
        key: 'today_balanced',
        params: <String, Object>{'kcal': 'x'},
      );
      expect(dietAdviceLineText(ko, broken), '받은 문장');
      const DietAdviceLine ai = DietAdviceLine(text: '**연어**를 드세요.');
      expect(dietAdviceLineText(ko, ai), '**연어**를 드세요.');
    });

    test('두 문장을 잇고, 옛 응답이면 message 를 쓴다', () {
      final DietAdvice advice = DietAdvice.fromJson(<String, Object?>{
        'message': '단백질 32g 더 필요해요. 저녁은 연어 어때요?',
        'analysis': '단백질 **32g** 더 필요해요.',
        'analysis_key': 'today_protein_left',
        'analysis_params': <String, Object?>{'protein_g': 32},
        'action': '저녁은 **연어** 어때요?',
        'action_key': 'next_meal',
        'action_params': <String, Object?>{
          'slot': 'dinner',
          'menu': '연어',
          'keyword': '고단백',
        },
      });
      expect(dietAdviceText(ko, advice), '단백질 **32g** 더 필요해요. 저녁은 **연어** 어때요?');
      final DietAdvice old = DietAdvice.fromJson(<String, Object?>{
        'message': '예전 한 문장',
      });
      expect(dietAdviceText(ko, old), '예전 한 문장');
    });
  });

  group('카드', () {
    testWidgets('** 표시는 떼고 평문으로 그린다 — 굵게 하지 않는다', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AiAdviceCard(
              title: 'AI 맞춤 조언',
              message: '단백질 **32g** 더 필요해요. 저녁은 **연어** 어때요?',
            ),
          ),
        ),
      );
      final Finder body = find.text(keepWords('단백질 32g 더 필요해요. 저녁은 연어 어때요?'));
      expect(body, findsOneWidget);
      expect(
        tester.widget<Text>(body).textSpan,
        isNull,
        reason: '조각 없이 평문 한 줄',
      );
      expect(find.textContaining('**'), findsNothing);
    });
  });
}
