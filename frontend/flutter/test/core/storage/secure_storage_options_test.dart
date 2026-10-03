import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/storage/secure_token_store.dart';

/// 토큰 저장소 옵션은 한 곳에서만 정한다(#3049).
///
/// 저장소를 여는 곳마다 옵션을 따로 적으면 같은 키를 다른 방식으로 열게 된다.
/// 안드로이드는 풀 수 없는 값(백업·기기 이전으로 넘어온 암호문)을 만나면 비우고
/// 다시 쓰도록 `resetOnError` 를 켠다.
void main() {
  test('provider 는 공유 저장소 상수를 그대로 쓴다', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      identical(container.read(secureStorageProvider), memberSecureStorage),
      isTrue,
    );
  });

  test('안드로이드는 암호화 저장소에 resetOnError 를 켠다', () {
    final Map<String, String> android = memberSecureStorage.aOptions.toMap();
    expect(android['encryptedSharedPreferences'], 'true');
    expect(android['resetOnError'], 'true');
    expect(
      identical(
        memberSecureStorage.aOptions,
        memberSecureStorageAndroidOptions,
      ),
      isTrue,
    );
  });

  test('iOS 는 이 기기 전용 키체인 접근을 유지한다', () {
    expect(
      memberSecureStorage.iOptions.toMap()['accessibility'],
      KeychainAccessibility.first_unlock_this_device.name,
    );
  });

  test('lib 에서 FlutterSecureStorage 를 직접 만드는 곳은 공유 상수 하나뿐이다', () {
    final RegExp construct = RegExp(r'FlutterSecureStorage\(');
    final List<String> hits = <String>[];
    for (final File file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'))) {
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String code = lines[i].split('//').first;
        if (construct.hasMatch(code)) hits.add('${file.path}:${i + 1}');
      }
    }
    expect(hits, hasLength(1), reason: hits.join('\n'));
    expect(hits.single, contains('core/storage/secure_token_store.dart'));
  });
}
