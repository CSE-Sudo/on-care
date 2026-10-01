import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/utils/server_message.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 서버 사유는 한국어 화면에서만 그대로 쓴다. (#2859)
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('serverDetailOr', () {
    test('한국어 화면은 서버 사유를 그대로 보인다', () {
      expect(serverDetailOr(ko, '이미 결정된 상담입니다.', '기본 문구'), '이미 결정된 상담입니다.');
    });

    test('영어 화면에는 한국어 사유가 새지 않는다', () {
      expect(
        serverDetailOr(en, '이미 결정된 상담입니다.', 'App fallback'),
        'App fallback',
      );
    });

    test('사유가 없거나 비었으면 앱 문구로 물러난다', () {
      expect(serverDetailOr(ko, null, '기본 문구'), '기본 문구');
      expect(serverDetailOr(ko, '', '기본 문구'), '기본 문구');
      expect(serverDetailOr(ko, '   ', '기본 문구'), '기본 문구');
      expect(serverDetailOr(en, null, 'App fallback'), 'App fallback');
    });

    test('앞뒤 공백은 지워서 보인다', () {
      expect(serverDetailOr(ko, '  사유  ', '기본 문구'), '사유');
    });
  });
}
