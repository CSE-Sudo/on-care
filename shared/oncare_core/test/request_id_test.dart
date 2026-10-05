/// 생성 요청의 멱등 키. (#581, #605, #2907)
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/request_id.dart';

void main() {
  test('req- 뒤에 16자리 소문자 16진수다', () {
    expect(newClientRequestId(), matches(RegExp(r'^req-[0-9a-f]{16}$')));
  });

  test('부를 때마다 새 키다', () {
    final Set<String> ids = <String>{
      for (int i = 0; i < 200; i++) newClientRequestId(),
    };
    expect(ids, hasLength(200));
  });
}
