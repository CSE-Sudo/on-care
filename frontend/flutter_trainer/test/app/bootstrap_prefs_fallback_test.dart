/// 저장소를 막은 브라우저에서도 앱이 뜬다. (#3250)
///
/// 설정 저장소를 열다 예외가 나면 이번 실행 동안만 쓰는 메모리 저장소로 대신한다.
/// 예전에는 이 호출이 오류 처리기보다 앞에 있어 부팅이 멈추고 흰 화면만 남았다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('열지 못하면 빈 메모리 저장소로 대신하고 까닭을 알린다', () async {
    Object? reported;
    final SharedPreferences prefs = await openPreferences(
      open: () async => throw StateError('localStorage blocked'),
      onFallback: (Object e, StackTrace _) => reported = e,
    );

    expect(reported, isA<StateError>());
    expect(prefs.getKeys(), isEmpty);
    expect(await prefs.setString('k', 'v'), isTrue);
    expect(prefs.getString('k'), 'v');
  });

  test('열리면 그 저장소를 그대로 쓴다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'saved': 'yes'});
    bool fellBack = false;
    final SharedPreferences prefs = await openPreferences(
      onFallback: (Object _, StackTrace _) => fellBack = true,
    );

    expect(fellBack, isFalse);
    expect(prefs.getString('saved'), 'yes');
  });
}
