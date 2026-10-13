import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/utils/server_message.dart';

/// 서버 사유는 그대로 쓰고, 없으면 앱 문구로 물러난다. (#2859)
void main() {
  group('serverDetailOr', () {
    test('서버 사유를 그대로 보인다', () {
      expect(serverDetailOr('이미 결정된 상담입니다.', '기본 문구'), '이미 결정된 상담입니다.');
    });

    test('사유가 없거나 비었으면 앱 문구로 물러난다', () {
      expect(serverDetailOr(null, '기본 문구'), '기본 문구');
      expect(serverDetailOr('', '기본 문구'), '기본 문구');
      expect(serverDetailOr('   ', '기본 문구'), '기본 문구');
    });

    test('앞뒤 공백은 지워서 보인다', () {
      expect(serverDetailOr('  사유  ', '기본 문구'), '사유');
    });
  });
}
