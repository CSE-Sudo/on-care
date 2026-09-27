import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원앱은 라이트 전용이다(#1604).
///
/// Flutter 쪽은 `theme: AppTheme.light()` 하나만 등록하지만, 첫 프레임을 그리기
/// 전에 보이는 플랫폼 껍데기(안드로이드 창 테마·iOS 인터페이스 스타일·웹 HTML
/// 배경)는 기기 설정을 따로 따라간다. 이 중 하나라도 다크를 따라가면 다크모드
/// 기기에서 스플래시·상태바·웹 배경이 어두웠다가 밝아지는 깜빡임이 생긴다.
/// 설정 파일을 직접 읽어, 누가 템플릿을 다시 생성하거나 색을 바꿔도 바로
/// 드러나게 한다.
void main() {
  /// 회원앱(모바일 밀도)의 화면 배경 토큰. 웹 첫 프레임 색도 이 값과 같아야
  /// Flutter 가 그리기 시작할 때 색이 튀지 않는다.
  const Color appBackground = OnCareColors.surfaceCard;

  String read(String path) => File(path).readAsStringSync();

  Color hexColor(String hex) {
    final String digits = hex.replaceFirst('#', '').toUpperCase();
    expect(digits, matches(RegExp(r'^[0-9A-F]{6}$')), reason: hex);
    return Color(int.parse('FF$digits', radix: 16));
  }

  Map<String, String> styleParents(String xml) => <String, String>{
    for (final RegExpMatch m in RegExp(
      r'<style\s+name="([^"]+)"\s+parent="([^"]+)"',
    ).allMatches(xml))
      m.group(1)!: m.group(2)!,
  };

  bool isDarkParent(String parent) =>
      parent.contains('Black') ||
      parent.contains('Dark') ||
      parent.contains('DayNight') ||
      parent.contains('Night');

  group('Android window themes', () {
    const String day = 'android/app/src/main/res/values/styles.xml';
    const String night = 'android/app/src/main/res/values-night/styles.xml';

    test('values-night keeps LaunchTheme and NormalTheme', () {
      final Map<String, String> parents = styleParents(read(night));
      expect(parents.keys, containsAll(<String>['LaunchTheme', 'NormalTheme']));
    });

    test('values-night uses a light parent for every style', () {
      final Map<String, String> parents = styleParents(read(night));
      expect(parents, isNotEmpty);
      parents.forEach((String name, String parent) {
        expect(isDarkParent(parent), isFalse, reason: '$name → $parent');
        expect(parent, contains('Light'), reason: '$name → $parent');
      });
    });

    test('values-night matches the day themes one to one', () {
      final Map<String, String> dayParents = styleParents(read(day));
      final Map<String, String> nightParents = styleParents(read(night));
      expect(nightParents, equals(dayParents));
    });

    test('day themes are light too', () {
      styleParents(read(day)).forEach((String name, String parent) {
        expect(isDarkParent(parent), isFalse, reason: '$name → $parent');
      });
    });

    test('no other night resource folder overrides the window theme', () {
      final Iterable<String> nightDirs = Directory('android/app/src/main/res')
          .listSync()
          .whereType<Directory>()
          .map(
            (Directory d) => d.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
          )
          .where((String name) => name.contains('night'));
      for (final String dir in nightDirs) {
        final File styles = File('android/app/src/main/res/$dir/styles.xml');
        if (!styles.existsSync()) continue;
        styleParents(styles.readAsStringSync()).forEach((name, parent) {
          expect(isDarkParent(parent), isFalse, reason: '$dir/$name → $parent');
        });
      }
    });

    test('launch backgrounds do not point at a dark color', () {
      for (final String path in <String>[
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final String xml = read(path).toLowerCase();
        expect(xml, isNot(contains('color/black')), reason: path);
        expect(xml, isNot(contains('dark')), reason: path);
      }
    });
  });

  group('iOS interface style', () {
    const String plist = 'ios/Runner/Info.plist';

    test('Info.plist pins UIUserInterfaceStyle to Light', () {
      final RegExpMatch? m = RegExp(
        r'<key>UIUserInterfaceStyle</key>\s*<string>([^<]*)</string>',
      ).firstMatch(read(plist));
      expect(m, isNotNull, reason: 'UIUserInterfaceStyle is missing');
      expect(m!.group(1), 'Light');
    });

    test('UIUserInterfaceStyle is declared exactly once', () {
      expect(
        RegExp('<key>UIUserInterfaceStyle</key>').allMatches(read(plist)),
        hasLength(1),
      );
    });

    test('launch screen background is the app background', () {
      final RegExpMatch? m = RegExp(
        r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" '
        r'blue="([\d.]+)" alpha="([\d.]+)"',
      ).firstMatch(read('ios/Runner/Base.lproj/LaunchScreen.storyboard'));
      expect(m, isNotNull);
      int channel(int i) => (double.parse(m!.group(i)!) * 255).round();
      expect(
        Color.fromARGB(channel(4), channel(1), channel(2), channel(3)),
        appBackground,
      );
    });
  });

  group('web shell', () {
    final String html = read('web/index.html');
    final String head = html.substring(0, html.indexOf('</head>'));

    String? metaContent(String name) => RegExp(
      '<meta\\s+name="$name"\\s+content="([^"]*)"',
    ).firstMatch(head)?.group(1);

    test('declares a light-only color scheme', () {
      expect(metaContent('color-scheme'), 'light');
      expect(head, isNot(contains('prefers-color-scheme: dark')));
    });

    test('theme-color matches the app background token', () {
      final String? value = metaContent('theme-color');
      expect(value, isNotNull);
      expect(hexColor(value!), appBackground);
    });

    test('page background matches the app background token', () {
      final RegExpMatch? m = RegExp(
        r'html,\s*body\s*\{\s*background-color:\s*(#[0-9A-Fa-f]{6});',
      ).firstMatch(head);
      expect(m, isNotNull, reason: 'html/body background-color is missing');
      expect(hexColor(m!.group(1)!), appBackground);
    });

    test('color scheme is set before Flutter boots', () {
      expect(
        html.indexOf('name="color-scheme"'),
        lessThan(html.indexOf('flutter_bootstrap.js')),
      );
    });

    test('standalone status bar uses the light style', () {
      expect(metaContent('apple-mobile-web-app-status-bar-style'), 'default');
    });

    test('manifest splash and toolbar colors match the app background', () {
      final Map<String, dynamic> manifest =
          jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
      expect(hexColor(manifest['background_color'] as String), appBackground);
      expect(hexColor(manifest['theme_color'] as String), appBackground);
    });
  });

  group('Flutter theme', () {
    test('app registers only the light theme', () {
      final String app = read('lib/app/app.dart');
      expect(app, contains('theme: AppTheme.light()'));
      expect(app, isNot(contains('darkTheme')));
      expect(app, isNot(contains('themeMode')));
      expect(app, isNot(contains('AppTheme.dark')));
    });

    test('no screen reintroduces a dark theme or theme mode', () {
      final Iterable<File> sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .where((File f) => !f.path.contains('/gen/'));
      for (final File f in sources) {
        final String src = f.readAsStringSync();
        expect(src, isNot(contains('darkTheme:')), reason: f.path);
        expect(src, isNot(contains('ThemeMode.')), reason: f.path);
        expect(src, isNot(contains('AppTheme.dark')), reason: f.path);
      }
    });

    test('AppTheme.light is light with the app background', () {
      final ThemeData theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, appBackground);
    });

    testWidgets('stays light when the device is in dark mode', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      late ThemeData seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (BuildContext context) {
              seen = Theme.of(context);
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      expect(
        MediaQuery.platformBrightnessOf(tester.element(find.byType(Scaffold))),
        Brightness.dark,
      );
      expect(seen.brightness, Brightness.light);
      final Material page = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Scaffold),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(page.color, appBackground);
    });
  });
}
