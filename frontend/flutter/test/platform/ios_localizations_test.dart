import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// iOS 번들이 앱과 같은 언어(ko)를 선언하고, 권한 안내 문구가 한국어로
/// 있는지(#3048).
///
/// 선언이 없으면 한국어 기기에서도 시스템 창(권한 버튼·사진 선택기)이 영어로
/// 뜬다. 권한을 새로 더하고 문구를 빠뜨리면 여기서 실패한다.
void main() {
  const String runner = 'ios/Runner';
  final String plist = File('$runner/Info.plist').readAsStringSync();
  final String pbxproj = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  final Set<String> appLanguages = <String>{
    for (final locale in AppLocalizations.supportedLocales) locale.languageCode,
  };

  List<String> plistArray(String key) {
    final RegExpMatch? m = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(m, isNotNull, reason: '$key 가 없다');
    return <String>[
      for (final RegExpMatch s in RegExp(
        r'<string>([^<]+)</string>',
      ).allMatches(m!.group(1)!))
        s.group(1)!,
    ];
  }

  Set<String> usageKeysInPlist() => <String>{
    for (final RegExpMatch m in RegExp(
      r'<key>(NS[A-Za-z]+UsageDescription)</key>',
    ).allMatches(plist))
      m.group(1)!,
  };

  /// `"KEY" = "값";` 줄을 읽는다. 주석과 빈 줄 밖의 다른 모양이 있으면 실패한다.
  Map<String, String> readStrings(String path) {
    final String raw = File(path).readAsStringSync();
    final String body = raw
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final RegExp entry = RegExp(r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";$');
    final Map<String, String> values = <String, String>{};
    for (final String line in body.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final RegExpMatch? m = entry.firstMatch(trimmed);
      expect(m, isNotNull, reason: '$path 문법 오류: $trimmed');
      expect(values.containsKey(m!.group(1)), isFalse, reason: '중복 키');
      values[m.group(1)!] = m.group(2)!;
    }
    return values;
  }

  test('CFBundleLocalizations 는 앱이 지원하는 언어와 같다', () {
    expect(plistArray('CFBundleLocalizations').toSet(), appLanguages);
  });

  test('Info.plist 에 권한 안내 키가 있다', () {
    expect(
      usageKeysInPlist(),
      containsAll(<String>[
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        // 앱은 "사용 중" 위치만 요청하지만 geolocator 가 항상 허용 API 를
        // 참조해, 문구가 없으면 업로드 때 ITMS-90683 경고가 난다(#3485).
        'NSLocationAlwaysAndWhenInUseUsageDescription',
      ]),
    );
  });

  group('ko.lproj/InfoPlist.strings', () {
    const String path = '$runner/ko.lproj/InfoPlist.strings';

    test('모든 권한 키가 빈 값 없이 한글로 있다', () {
      final RegExp hangul = RegExp(r'[가-힣]');
      final Map<String, String> values = readStrings(path);
      for (final String key in usageKeysInPlist()) {
        expect(values[key], isNotNull, reason: '$key 문구가 없다');
        expect(values[key], matches(hangul), reason: key);
      }
    });

    test('Info.plist 의 문구와 같다', () {
      final Map<String, String> ko = readStrings(path);
      for (final String key in usageKeysInPlist()) {
        final RegExpMatch? m = RegExp(
          '<key>$key</key>\\s*<string>([^<]*)</string>',
        ).firstMatch(plist);
        expect(m?.group(1), ko[key], reason: key);
      }
    });
  });

  test('영어 리소스가 남아 있지 않다', () {
    expect(Directory('$runner/en.lproj').existsSync(), isFalse);
    expect(pbxproj, isNot(contains('en.lproj')));
  });

  group('project.pbxproj', () {
    test('knownRegions 는 ko·Base 이고 개발 언어는 ko', () {
      final RegExpMatch? m = RegExp(
        r'knownRegions = \((.*?)\);',
        dotAll: true,
      ).firstMatch(pbxproj);
      expect(m, isNotNull);
      final Set<String> regions = m!
          .group(1)!
          .split(',')
          .map((String r) => r.trim())
          .where((String r) => r.isNotEmpty)
          .toSet();
      expect(regions, <String>{'ko', 'Base'});
      expect(pbxproj, contains('developmentRegion = ko;'));
    });

    test('InfoPlist.strings 가 Runner 리소스에 들어간다', () {
      expect(
        pbxproj,
        contains('path = ko.lproj/InfoPlist.strings;'),
        reason: 'ko 파일 참조',
      );
      expect(
        RegExp(
          r'/\* InfoPlist\.strings \*/ = \{\s*isa = PBXVariantGroup;',
        ).hasMatch(pbxproj),
        isTrue,
        reason: 'PBXVariantGroup',
      );
      final RegExpMatch? resources = RegExp(
        r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{.*?files = \((.*?)\);',
        dotAll: true,
      ).firstMatch(pbxproj);
      expect(resources, isNotNull, reason: 'Runner Resources 단계');
      expect(resources!.group(1), contains('InfoPlist.strings in Resources'));
    });
  });
}
