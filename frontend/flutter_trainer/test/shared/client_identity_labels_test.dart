/// 동명이인 구분 문구 `여성 · 29세` / `Female · Age 29` (#2304).
///
/// 예전에는 `korean ?` 분기로 두 언어를 코드에 박아 두었다. 이제 성별 이름과
/// 나이 틀을 ARB 가 정한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';

/// [locale] 로 앱 문구를 연 뒤 그 [BuildContext] 로 [demographicsLabel] 을 부른다.
Future<String> _label(
  WidgetTester tester,
  Locale locale, {
  required String gender,
  required int? age,
}) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) {
          out = demographicsLabel(context, gender: gender, age: age);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return out;
}

void main() {
  group('demographicsLabel', () {
    testWidgets('한국어', (tester) async {
      const ko = Locale('ko');
      expect(await _label(tester, ko, gender: 'female', age: 29), '여성 · 29세');
      expect(await _label(tester, ko, gender: 'male', age: 41), '남성 · 41세');
      expect(await _label(tester, ko, gender: 'other', age: 35), '기타 · 35세');
    });

    testWidgets('영어', (tester) async {
      const en = Locale('en');
      expect(
        await _label(tester, en, gender: 'female', age: 29),
        'Female · Age 29',
      );
      expect(
        await _label(tester, en, gender: 'male', age: 41),
        'Male · Age 41',
      );
      expect(
        await _label(tester, en, gender: 'other', age: 35),
        'Other · Age 35',
      );
    });

    testWidgets('모르는 성별 값은 기타로 읽는다', (tester) async {
      expect(
        await _label(tester, const Locale('en'), gender: '', age: 50),
        'Other · Age 50',
      );
      expect(
        await _label(tester, const Locale('ko'), gender: 'unknown', age: 50),
        '기타 · 50세',
      );
    });

    testWidgets('나이가 없으면 성별만 적는다 (#2744)', (tester) async {
      expect(
        await _label(tester, const Locale('ko'), gender: 'female', age: null),
        '여성',
      );
      expect(
        await _label(tester, const Locale('en'), gender: 'male', age: null),
        'Male',
      );
      expect(
        await _label(tester, const Locale('ko'), gender: '', age: null),
        '기타',
      );
    });

    testWidgets('영어 문구에는 한글이 없다', (tester) async {
      for (final gender in <String>['female', 'male', 'other']) {
        final label = await _label(
          tester,
          const Locale('en'),
          gender: gender,
          age: 30,
        );
        expect(label, isNot(matches(RegExp(r'[가-힣]'))), reason: gender);
      }
    });
  });
}
