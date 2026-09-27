import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너웹은 라이트 전용이다(#1604).
///
/// Flutter 쪽은 `theme: AppTheme.light()` 하나만 등록하지만, 엔진이 첫 프레임을
/// 그리기 전의 HTML 배경·스크롤바·주소창 색은 브라우저의 다크 모드를 따로
/// 따라간다. 여기가 다크를 따라가거나 배경색이 앱과 다르면 다크모드 브라우저에서
/// 어두운 화면이 한 번 비쳤다가 밝아진다. 설정 파일을 직접 읽어 확인한다.
void main() {
  /// 트레이너웹(웹 밀도)의 화면 배경 토큰(#1740). 웹 첫 프레임 색도 이 값과
  /// 같아야 Flutter 가 그리기 시작할 때 색이 튀지 않는다.
  const Color appBackground = OnCareColors.surfacePage;

  String read(String path) => File(path).readAsStringSync();

  Color hexColor(String hex) {
    final String digits = hex.replaceFirst('#', '').toUpperCase();
    expect(digits, matches(RegExp(r'^[0-9A-F]{6}$')), reason: hex);
    return Color(int.parse('FF$digits', radix: 16));
  }

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

    test('color-scheme is declared exactly once', () {
      expect(RegExp('name="color-scheme"').allMatches(html), hasLength(1));
    });

    test('theme-color keeps the trainer brand navy', () {
      final String? value = metaContent('theme-color');
      expect(value, isNotNull);
      expect(hexColor(value!), OnCareBrand.trainer.primary);
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

    test('manifest splash color matches the app background', () {
      final Map<String, dynamic> manifest =
          jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
      expect(hexColor(manifest['background_color'] as String), appBackground);
    });

    test('manifest toolbar color keeps the trainer brand navy', () {
      final Map<String, dynamic> manifest =
          jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
      expect(
        hexColor(manifest['theme_color'] as String),
        OnCareBrand.trainer.primary,
      );
    });

    test('index.html and manifest agree on the toolbar color', () {
      final Map<String, dynamic> manifest =
          jsonDecode(read('web/manifest.json')) as Map<String, dynamic>;
      expect(
        hexColor(metaContent('theme-color')!),
        hexColor(manifest['theme_color'] as String),
      );
    });
  });

  group('native shells', () {
    test('any Android window theme stays light', () {
      final Directory res = Directory('android/app/src/main/res');
      if (!res.existsSync()) return;
      final Iterable<File> styles = res
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('styles.xml'));
      for (final File f in styles) {
        for (final RegExpMatch m in RegExp(
          r'<style\s+name="([^"]+)"\s+parent="([^"]+)"',
        ).allMatches(f.readAsStringSync())) {
          final String parent = m.group(2)!;
          expect(
            parent.contains('Black') ||
                parent.contains('Dark') ||
                parent.contains('DayNight'),
            isFalse,
            reason: '${f.path}: ${m.group(1)} → $parent',
          );
        }
      }
    });

    test('any iOS Info.plist pins UIUserInterfaceStyle to Light', () {
      final File plist = File('ios/Runner/Info.plist');
      if (!plist.existsSync()) return;
      final RegExpMatch? m = RegExp(
        r'<key>UIUserInterfaceStyle</key>\s*<string>([^<]*)</string>',
      ).firstMatch(plist.readAsStringSync());
      expect(m?.group(1), 'Light');
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

    testWidgets('stays light when the browser is in dark mode', (
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
