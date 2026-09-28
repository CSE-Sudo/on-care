// 트레이너 웹 `식단 분석` 데모 규칙이 서버와 같은가 (#2379).
//
// 사례 파일은 서버 `scripts/gen_trainer_diet_analysis_cases.py` 가 서버 규칙으로 만든다.
// 서버 테스트(`test_trainer_diet_analysis_cases.py`)가 같은 파일을 읽으므로, 두 쪽이
// 모두 통과하면 데모와 서버가 같은 입력에 같은 문장 키·값을 낸다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/domain/diet_analysis_rules.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_analysis.dart';
import 'package:oncare_trainer/features/clients/presentation/diet_analysis_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

Map<String, Object?> _cases() =>
    jsonDecode(
          File(
            'test/features/clients/diet_analysis_cases.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

DietRuleEntry _entry(Map<String, Object?> e) => DietRuleEntry(
  date: e['date']! as String,
  slot: e['meal_type']! as String,
  foods: <DietRuleFood>[
    for (final Map<String, Object?> f
        in (e['foods']! as List<Object?>).cast<Map<String, Object?>>())
      DietRuleFood(
        f['name']! as String,
        calories: f['calories'] as num?,
        sodiumMg: f['sodium_mg'] as num?,
        sugarG: f['sugar_g'] as num?,
      ),
  ],
  calories: e['kcal']! as num,
  proteinG: e['protein_g']! as num,
  sodiumMg: e['sodium_mg']! as num,
  sugarG: e['sugar_g']! as num,
  carbsG: e['carbs_g']! as num,
  fatG: e['fat_g']! as num,
);

DietRuleTargets _targets(Map<String, Object?> t) => (
  calories: t['calories']! as int,
  proteinG: t['protein_g']! as int,
  sodiumMg: t['sodium_mg']! as int,
  sugarG: t['sugar_g']! as int,
);

List<Map<String, Object>> _json(List<ClientDietSentence> sentences) =>
    <Map<String, Object>>[
      for (final ClientDietSentence s in sentences) s.toJson(),
    ];

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final Map<String, Object?> file = _cases();
  final List<Map<String, Object?>> cases = <Map<String, Object?>>[
    for (final Object? c in file['cases']! as List<Object?>)
      c! as Map<String, Object?>,
  ];

  test('사례 파일이 세 기간을 모두 담는다', () {
    expect(cases.map((Map<String, Object?> c) => c['period']).toSet(), <String>{
      'today',
      'week',
      'all',
    });
  });

  for (final Map<String, Object?> c in cases) {
    test('데모 규칙이 서버와 같다 — ${c['name']}', () {
      final List<DietRuleEntry> entries = <DietRuleEntry>[
        for (final Object? e in c['entries']! as List<Object?>)
          _entry(e! as Map<String, Object?>),
      ];
      final DietRuleTargets targets = _targets(
        c['targets']! as Map<String, Object?>,
      );
      final Map<String, Object?> expected =
          c['expected']! as Map<String, Object?>;
      final Object? wanted = jsonDecode(jsonEncode(expected['sentences']));
      switch (c['period']) {
        case 'today':
          final List<ClientDietSentence> out = todaySentences(
            entries,
            targets,
            DateTime.parse(c['now']! as String),
            avgProteinG: c['avg_protein_g'] as int?,
          );
          expect(jsonDecode(jsonEncode(_json(out))), wanted);
        case 'week':
          final result = weekSentences(
            entries,
            targets,
            DateTime.parse(c['now']! as String),
          );
          expect(_ymd(result.start), expected['from']);
          expect(_ymd(result.end), expected['to']);
          expect(result.logged, expected['logged']);
          expect(jsonDecode(jsonEncode(_json(result.sentences))), wanted);
        case 'all':
          final result = allSentences(
            entries,
            targets,
            DateTime.parse(c['today']! as String),
          );
          expect(result.logged, expected['logged']);
          expect(jsonDecode(jsonEncode(_json(result.sentences))), wanted);
      }
    });
  }

  // 트레이너 웹 ARB 가 서버 틀과 같은 문장을 그린다 — 키마다 한국어·영어.
  final List<Map<String, Object?>> renderings = <Map<String, Object?>>[
    for (final Object? r in file['renderings']! as List<Object?>)
      r! as Map<String, Object?>,
  ];
  for (final String lang in <String>['ko', 'en']) {
    final AppLocalizations l = lookupAppLocalizations(Locale(lang));
    for (final Map<String, Object?> r in renderings) {
      test('ARB 가 서버와 같은 문장을 그린다 — $lang ${r['key']}', () {
        final ClientDietSentence s = ClientDietSentence.fromJson(r);
        expect(clientDietSentenceText(l, s), r[lang]);
      });
    }
  }

  test('모르는 키는 그리지 않는다', () {
    final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
    expect(
      clientDietSentenceText(l, const ClientDietSentence('tr_future_key')),
      isNull,
    );
  });

  test('파이썬 round 와 같은 반올림 — 짝수 쪽', () {
    expect(pyRound(2.5), 2);
    expect(pyRound(3.5), 4);
    expect(pyRound(-0.4), 0);
    expect(pyRound(7.8), 8);
  });
}
