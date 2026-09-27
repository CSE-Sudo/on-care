/// 스케줄 취소 버튼 문구. (#2377)
///
/// 카드 아래 버튼과 확인 창의 확정 버튼은 같은 `취소` 이고, 창을 그냥 닫는
/// 버튼은 `닫기` 다. 두 키가 같은 글씨가 되면 창 안에 같은 이름의 버튼
/// 둘이 선다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

void main() {
  for (final String code in <String>['ko', 'en']) {
    group('[$code]', () {
      final AppLocalizations l = lookupAppLocalizations(Locale(code));

      test('취소 버튼은 짧은 한 단어다', () {
        expect(l.schedCancel, code == 'ko' ? '취소' : 'Cancel');
      });

      test('확정 버튼과 닫기 버튼의 글씨가 다르다', () {
        expect(l.schedCancel, isNot(l.actionClose));
      });

      test('노쇼 확정 버튼은 취소 버튼과 구별된다', () {
        expect(l.schedNoShow, isNot(l.schedCancel));
      });
    });
  }
}
