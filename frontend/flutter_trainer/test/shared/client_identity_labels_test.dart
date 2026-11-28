/// 동명이인 구분 문구 `여성 · 29세` (#2304).
///
/// 성별 이름과 나이 틀은 코드가 아니라 ARB 가 정한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/utils/client_identity_labels.dart';

/// 앱 문구를 연 뒤 그 [BuildContext] 로 [demographicsLabel] 을 부른다.
Future<String> _label(
  WidgetTester tester, {
  required String gender,
  required int? age,
}) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ko'),
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
    testWidgets('성별과 나이를 함께 적는다', (tester) async {
      expect(await _label(tester, gender: 'female', age: 29), '여성 · 29세');
      expect(await _label(tester, gender: 'male', age: 41), '남성 · 41세');
      expect(await _label(tester, gender: 'other', age: 35), '기타 · 35세');
    });

    testWidgets('성별 미입력은 기타가 아니라 나이만 적는다 (#2870)', (tester) async {
      expect(await _label(tester, gender: '', age: 50), '50세');
      // 세 가지 밖의 값도 미입력으로 읽는다 — 기타로 지어내지 않는다.
      expect(await _label(tester, gender: 'unknown', age: 50), '50세');
    });

    testWidgets('성별·나이 둘 다 모르면 빈 문구다 (#2870)', (tester) async {
      expect(await _label(tester, gender: '', age: null), '');
    });

    testWidgets('회원이 직접 고른 기타는 그대로 기타다', (tester) async {
      expect(await _label(tester, gender: 'other', age: null), '기타');
    });

    testWidgets('나이가 없으면 성별만 적는다 (#2744)', (tester) async {
      expect(await _label(tester, gender: 'female', age: null), '여성');
      expect(await _label(tester, gender: 'male', age: null), '남성');
    });
  });
}
