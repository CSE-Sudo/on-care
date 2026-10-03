import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// iOS 번들이 앱과 같은 언어(ko·en)를 선언하고, 권한 안내 문구가 두 언어로
/// 있는지(#3048).
///
/// 선언이 없으면 한국어 기기에서도 시스템 창(권한 버튼·사진 선택기)이 영어로
/// 뜨고, 권한 설명은 기기 언어와 상관없이 한 언어로만 뜬다. 권한을 새로 더하고
/// 번역을 빠뜨리면 여기서 실패한다.
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
      ]),
    );
  });

  for (final String language in <String>['ko', 'en']) {
    group('$language.lproj/InfoPlist.strings', () {
      final String path = '$runner/$language.lproj/InfoPlist.strings';

      test('모든 권한 키가 빈 값 없이 있다', () {
        final Map<String, String> values = readStrings(path);
        for (final String key in usageKeysInPlist()) {
          expect(values[key], isNotNull, reason: '$key 번역이 없다');
          expect(values[key]!.trim(), isNotEmpty, reason: '$key 가 비었다');
        }
      });
    });
  }

  test('한국어 문구는 한글, 영어 문구는 한글 없이 적는다', () {
    final RegExp hangul = RegExp(r'[가-힣]');
    final Map<String, String> ko = readStrings(
      '$runner/ko.lproj/InfoPlist.strings',
    );
    final Map<String, String> en = readStrings(
      '$runner/en.lproj/InfoPlist.strings',
    );
    for (final String key in usageKeysInPlist()) {
      expect(ko[key], matches(hangul), reason: 'ko $key');
      expect(en[key], isNot(matches(hangul)), reason: 'en $key');
    }
  });

  test('Info.plist 폴백 문구는 개발 언어(en)와 같다', () {
    final Map<String, String> en = readStrings(
      '$runner/en.lproj/InfoPlist.strings',
    );
    for (final String key in usageKeysInPlist()) {
      final RegExpMatch? m = RegExp(
        '<key>$key</key>\\s*<string>([^<]*)</string>',
      ).firstMatch(plist);
      expect(m?.group(1), en[key], reason: key);
    }
  });

  group('project.pbxproj', () {
    test('knownRegions 에 ko·en 이 있고 개발 언어는 en', () {
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
      expect(regions, containsAll(<String>['ko', 'en', 'Base']));
      expect(pbxproj, contains('developmentRegion = en;'));
    });

    test('InfoPlist.strings 가 언어별 그룹으로 Runner 리소스에 들어간다', () {
      expect(
        pbxproj,
        contains('path = ko.lproj/InfoPlist.strings;'),
        reason: 'ko 파일 참조',
      );
      expect(
        pbxproj,
        contains('path = en.lproj/InfoPlist.strings;'),
        reason: 'en 파일 참조',
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
