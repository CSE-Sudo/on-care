/// 앱에 담긴 글꼴 라이선스 등록과 라이선스 화면 열기. (#3150)
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/licenses.dart';

const String _ofl = 'SIL OPEN FONT LICENSE Version 1.1\n\nPretendard test text';

/// OFL 경로에만 답하는 번들. 몇 번 읽었는지 센다.
class _FakeBundle extends CachingAssetBundle {
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key != kPretendardLicenseAsset) {
      throw FlutterError('missing asset $key');
    }
    loads++;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(_ofl)));
  }
}

Future<List<LicenseEntry>> _pretendard() async {
  final List<LicenseEntry> all = await LicenseRegistry.licenses.toList();
  return all
      .where((LicenseEntry e) => e.packages.contains(kPretendardPackageName))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LicenseRegistry.reset();
    resetBundledLicensesForTest();
  });

  tearDown(() {
    LicenseRegistry.reset();
    resetBundledLicensesForTest();
  });

  group('registerBundledLicenses', () {
    test('Pretendard 글꼴 라이선스가 목록에 들어간다', () async {
      registerBundledLicenses(bundle: _FakeBundle());

      final List<LicenseEntry> entries = await _pretendard();
      expect(entries, hasLength(1));
      expect(entries.single.packages, <String>[kPretendardPackageName]);
      final String text = entries.single.paragraphs
          .map((LicenseParagraph p) => p.text)
          .join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE'));
    });

    test('여러 번 불러도 한 번만 들어간다', () async {
      final _FakeBundle bundle = _FakeBundle();
      registerBundledLicenses(bundle: bundle);
      registerBundledLicenses(bundle: bundle);
      registerBundledLicenses(bundle: bundle);

      expect(await _pretendard(), hasLength(1));
    });

    test('파일은 목록을 모을 때 읽는다 — 기동 때 읽지 않는다', () async {
      final _FakeBundle bundle = _FakeBundle();
      registerBundledLicenses(bundle: bundle);
      expect(bundle.loads, 0);

      await _pretendard();
      expect(bundle.loads, 1);
    });

    test('자산 경로는 두 앱이 담는 OFL 파일이다', () {
      expect(kPretendardLicenseAsset, 'assets/fonts/Pretendard-OFL.txt');
      expect(kPretendardPackageName, 'Pretendard');
    });
  });

  group('showOnCareLicenses', () {
    Future<void> pumpOpener(WidgetTester tester, {String? version}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Center(
              child: GestureDetector(
                key: const ValueKey<String>('open'),
                onTap: () => showOnCareLicenses(
                  context,
                  applicationName: 'On-Care',
                  applicationVersion: version,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('라이선스 화면을 앱 이름·버전과 함께 연다', (WidgetTester tester) async {
      registerBundledLicenses(bundle: _FakeBundle());
      await pumpOpener(tester, version: '1.2.3');

      await tester.tap(find.byKey(const ValueKey<String>('open')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('On-Care'), findsWidgets);
      expect(find.text('1.2.3'), findsWidgets);
      expect(find.byType(OnCareLicenseLogo), findsWidgets);
    });

    testWidgets('버전을 모르면 앱 이름만 싣는다', (WidgetTester tester) async {
      await pumpOpener(tester);

      await tester.tap(find.byKey(const ValueKey<String>('open')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      final LicensePage page = tester.widget<LicensePage>(
        find.byType(LicensePage),
      );
      expect(page.applicationName, 'On-Care');
      expect(page.applicationVersion, isNull);
    });
  });

  testWidgets('로고를 읽지 못해도 자리를 지키며 깨지지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: OnCareLicenseLogo())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(OnCareLicenseLogo)), const Size(48, 48));
  });
}
