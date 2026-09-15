import 'dart:io';

import 'package:test/test.dart';
import 'package:ui_guard/ui_guard.dart';

void main() {
  late Directory root;
  const app = 'frontend/flutter';

  File appFile(String path) => File('${root.path}/$app/$path');

  void write(String path, String content) {
    appFile(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  (int, String) check() {
    final out = StringBuffer();
    return (runCheck(root, app, out), out.toString());
  }

  (int, String) update({bool allowIncrease = false}) {
    final out = StringBuffer();
    final code = runUpdate(root, app, out, allowIncrease: allowIncrease);
    return (code, out.toString());
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('ui_guard_test');
    File('${root.path}/tool/ui_guard/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: ui_guard\n');
    write('lib/home.dart', '''
Widget a() => const SizedBox(height: 8, child: Text('a', style: TextStyle(fontSize: 14)));
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('제외 경로를 가린다', () {
    expect(isExcluded('lib/gen/l10n/app_localizations.dart'), isTrue);
    expect(isExcluded('lib/l10n/strings.dart'), isTrue);
    expect(isExcluded('lib/core/storage/app_database.g.dart'), isTrue);
    expect(
      isExcluded(
        'lib/features/member_coach/services/member_report_pdf_generator.dart',
      ),
      isTrue,
    );
    expect(
      isExcluded('lib/features/reports/services/report_pdf_generator.dart'),
      isTrue,
    );
    expect(isExcluded('../../shared/oncare_ui/lib/src/button.dart'), isTrue);
    expect(isExcluded('lib/features/home/home_page.dart'), isFalse);
    expect(isExcluded('lib/general/page.dart'), isFalse);
  });

  test('제외 경로 파일은 세지 않는다', () {
    write('lib/gen/x.dart', 'final c = Colors.red;');
    write('lib/db.g.dart', 'final c = Colors.red;');
    final counts = countFindings(scanApp(Directory('${root.path}/$app')));
    expect(counts.keys, ['lib/home.dart']);
  });

  test('기준선이 없으면 실패하고 만드는 명령을 알려 준다', () {
    final (code, out) = check();
    expect(code, 1);
    expect(out, contains('dart run bin/ui_guard.dart update $app'));
  });

  test('기준선과 같으면 통과한다', () {
    expect(update().$1, 0);
    expect(
      appFile(baselineFileName).readAsStringSync(),
      '{\n'
      '  "lib/home.dart": {\n'
      '    "fontSize": 1,\n'
      '    "sizedBox": 1\n'
      '  }\n'
      '}\n',
    );
    final (code, out) = check();
    expect(code, 0, reason: out);
  });

  test('늘면 실패하고 해당 위치를 보여 준다', () {
    update();
    write('lib/home.dart', '''
Widget a() => const SizedBox(height: 8, child: Text('a', style: TextStyle(fontSize: 14)));
Widget b() => const Text('b', style: TextStyle(fontSize: 13));
''');
    write('lib/new_page.dart', 'final c = Colors.red;\n');
    final (code, out) = check();
    expect(code, 1);
    expect(out, contains('lib/home.dart  fontSize: 1 → 2'));
    expect(out, contains('Widget b()'));
    expect(out, contains('lib/new_page.dart  materialColor: 0 → 1'));
  });

  test('줄었는데 기준선을 갱신하지 않으면 실패한다', () {
    update();
    write('lib/home.dart', '''
Widget a() => const SizedBox(height: AppSpacing.sm, child: Text('a', style: TextStyle(fontSize: 14)));
''');
    final (code, out) = check();
    expect(code, 1);
    expect(out, contains('줄었는데 기준선에 반영되지 않았습니다'));
    expect(out, contains('lib/home.dart  sizedBox: 1 → 0'));

    expect(update().$1, 0);
    expect(check().$1, 0);
    expect(
      appFile(baselineFileName).readAsStringSync(),
      isNot(contains('sizedBox')),
    );
  });

  test('파일을 지우면 기준선에서 빠질 때까지 실패한다', () {
    update();
    appFile('lib/home.dart').deleteSync();
    expect(check().$1, 1);
    expect(update().$1, 0);
    expect(appFile(baselineFileName).readAsStringSync(), '{}\n');
    expect(check().$1, 0);
  });

  test('update 는 늘어난 곳이 있으면 --allow-increase 없이 쓰지 않는다', () {
    update();
    final before = appFile(baselineFileName).readAsStringSync();
    write('lib/new_page.dart', 'final c = Colors.red;\n');

    final (code, out) = update();
    expect(code, 1);
    expect(out, contains('--allow-increase'));
    expect(appFile(baselineFileName).readAsStringSync(), before);

    expect(update(allowIncrease: true).$1, 0);
    expect(check().$1, 0);
  });

  test('회원앱은 아이콘 목록 밖 아이콘을 잡고 목록 파일은 뺀다(#1803)', () {
    expect(iconRegistryOf('frontend/flutter/'), 'lib/app/app_icons.dart');
    expect(iconRegistryOf('frontend/flutter_trainer'), isNull);
    write(
      'lib/app/app_icons.dart',
      'class AppIcons { static const home = Symbols.home_rounded; }\n',
    );
    write(
      'lib/page.dart',
      'Widget a() => Icon(Icons.close_rounded);\n'
          'Widget b() => AppIcon(AppIcons.home);\n',
    );
    final counts = countFindings(
      scanApp(
        Directory('${root.path}/$app'),
        iconRegistry: iconRegistryOf(app),
      ),
    );
    expect(counts.containsKey('lib/app/app_icons.dart'), isFalse);
    expect(counts['lib/page.dart'], {
      Rule.iconOutsideRegistry: 1,
      Rule.rawIcon: 1,
    });

    // 트레이너웹은 지금 규칙(_rounded) 그대로다.
    const trainer = 'frontend/flutter_trainer';
    File('${root.path}/$trainer/lib/page.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'Widget a() => Icon(Icons.close);\n'
        'Widget b() => Icon(Icons.close_rounded);\n',
      );
    final trainerCounts = countFindings(
      scanApp(
        Directory('${root.path}/$trainer'),
        iconRegistry: iconRegistryOf(trainer),
      ),
    );
    expect(trainerCounts['lib/page.dart'], {Rule.nonRoundedIcon: 1});
  });

  test('check 는 회원앱 화면의 목록 밖 아이콘을 늘어난 것으로 본다', () {
    update();
    write('lib/new_page.dart', 'Widget a() => AppIcon(Icons.close_rounded);\n');
    final (code, out) = check();
    expect(code, 1);
    expect(out, contains('lib/new_page.dart  iconOutsideRegistry: 0 → 1'));
  });

  test('기준선의 모르는 항목 이름은 형식 오류다', () {
    expect(
      () => decodeBaseline('{"lib/a.dart": {"fontsize": 1}}'),
      throwsFormatException,
    );
  });

  test('findRepoRoot 는 하위 디렉터리에서도 루트를 찾는다', () {
    final nested = Directory('${root.path}/$app/lib')
      ..createSync(recursive: true);
    expect(
      findRepoRoot(nested).resolveSymbolicLinksSync(),
      root.resolveSymbolicLinksSync(),
    );
  });
}
