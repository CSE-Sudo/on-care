/// 빌드 버전 읽기(#3047).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/app_version/app_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String?> read() async {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    return c.read(appVersionProvider.future);
  }

  void mock(String version) => PackageInfo.setMockInitialValues(
    appName: 'oncare',
    packageName: 'com.csesudo.oncare',
    version: version,
    buildNumber: '4',
    buildSignature: '',
  );

  test('빌드의 버전 이름을 돌려준다', () async {
    mock('1.2.3');
    expect(await read(), '1.2.3');
  });

  test('앞뒤 공백은 지운다', () async {
    mock(' 0.4.0 ');
    expect(await read(), '0.4.0');
  });

  test('비어 있으면 null', () async {
    mock('   ');
    expect(await read(), isNull);
  });
}
