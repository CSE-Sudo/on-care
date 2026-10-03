import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 회원 앱 데이터는 Google 자동 백업·기기 간 이전에 싣지 않는다(#3049).
///
/// 토큰 저장소는 Keystore 키로 암호화돼 다른 기기에서는 풀리지 않는다. 새 설치
/// 표식까지 함께 복원되면 새 설치 정리도 건너뛰어, 기기를 바꾼 회원이 다시
/// 로그인해도 토큰을 저장하지 못했다. 매니페스트와 규칙 파일을 직접 읽어, 누가
/// 템플릿을 다시 만들거나 속성을 지워도 바로 드러나게 한다.
void main() {
  const String manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const String xmlDir = 'android/app/src/main/res/xml';
  const List<String> domains = <String>[
    'root',
    'file',
    'database',
    'sharedpref',
  ];

  String read(String path) => File(path).readAsStringSync();

  /// 주석을 걷어 낸 XML — 주석 속 예시가 검사를 통과시키지 않게 한다.
  String withoutComments(String xml) =>
      xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  String applicationTag() {
    final RegExpMatch? tag = RegExp(
      r'<application\b[^>]*>',
      dotAll: true,
    ).firstMatch(withoutComments(read(manifestPath)));
    expect(tag, isNotNull, reason: '<application> 이 없다');
    return tag!.group(0)!;
  }

  String? attribute(String tag, String name) =>
      RegExp('android:$name="([^"]*)"').firstMatch(tag)?.group(1);

  Set<String> excludedDomains(String section) => <String>{
    for (final RegExpMatch m in RegExp(
      r'<exclude\s+domain="([^"]+)"',
    ).allMatches(section))
      m.group(1)!,
  };

  group('AndroidManifest <application>', () {
    test('allowBackup 은 false', () {
      expect(attribute(applicationTag(), 'allowBackup'), 'false');
    });

    test('Android 11 이하·12 이상 규칙 파일을 모두 가리킨다', () {
      final String tag = applicationTag();
      expect(attribute(tag, 'fullBackupContent'), '@xml/backup_rules');
      expect(
        attribute(tag, 'dataExtractionRules'),
        '@xml/data_extraction_rules',
      );
    });
  });

  group('data_extraction_rules.xml (Android 12+)', () {
    const String path = '$xmlDir/data_extraction_rules.xml';

    String section(String name) {
      final RegExpMatch? m = RegExp(
        '<$name>(.*?)</$name>',
        dotAll: true,
      ).firstMatch(withoutComments(read(path)));
      expect(m, isNotNull, reason: '<$name> 절이 없다');
      return m!.group(1)!;
    }

    test('파일이 있다', () {
      expect(File(path).existsSync(), isTrue);
    });

    // allowBackup=false 는 기기 간 이전을 막지 못한다 — 두 절 모두 필요하다.
    for (final String name in <String>['cloud-backup', 'device-transfer']) {
      test('$name 에서 앱 데이터 영역을 모두 제외한다', () {
        final String body = section(name);
        expect(excludedDomains(body), containsAll(domains));
        expect(body, isNot(contains('<include')));
      });
    }
  });

  group('backup_rules.xml (Android 11 이하)', () {
    const String path = '$xmlDir/backup_rules.xml';

    test('앱 데이터 영역을 모두 제외하고 포함 규칙이 없다', () {
      expect(File(path).existsSync(), isTrue);
      final String xml = withoutComments(read(path));
      expect(xml, contains('<full-backup-content>'));
      expect(excludedDomains(xml), containsAll(domains));
      expect(xml, isNot(contains('<include')));
    });
  });
}
