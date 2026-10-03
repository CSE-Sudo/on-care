import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/platform/orientation_policy.dart';

/// 휴대폰은 세로 고정, 태블릿·웹은 그대로(#3050).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lockedOrientationsFor', () {
    test('짧은 변 599 는 휴대폰 — 세로만', () {
      expect(
        lockedOrientationsFor(screenSize: const Size(599, 900), isWeb: false),
        <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });

    test('휴대폰을 눕힌 크기여도 짧은 변으로 판단한다', () {
      expect(
        lockedOrientationsFor(screenSize: const Size(844, 390), isWeb: false),
        <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });

    test('짧은 변 600 은 태블릿 — 고정하지 않는다', () {
      expect(
        lockedOrientationsFor(screenSize: const Size(600, 960), isWeb: false),
        isNull,
      );
    });

    test('짧은 변 800 태블릿 가로 — 고정하지 않는다', () {
      expect(
        lockedOrientationsFor(screenSize: const Size(1194, 834), isWeb: false),
        isNull,
      );
    });

    test('웹은 크기와 상관없이 고정하지 않는다', () {
      expect(
        lockedOrientationsFor(screenSize: const Size(390, 844), isWeb: true),
        isNull,
      );
    });

    test('크기를 모르면 고정하지 않는다', () {
      expect(
        lockedOrientationsFor(screenSize: Size.zero, isWeb: false),
        isNull,
      );
    });
  });

  group('applyPhoneOrientationLock', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Iterable<MethodCall> orientationCalls() => calls.where(
      (MethodCall c) => c.method == 'SystemChrome.setPreferredOrientations',
    );

    test('휴대폰 크기면 세로만 담아 플랫폼에 요청한다', () async {
      expect(
        await applyPhoneOrientationLock(
          screenSize: const Size(390, 844),
          isWeb: false,
        ),
        isTrue,
      );
      expect(orientationCalls(), hasLength(1));
      expect(orientationCalls().single.arguments, <String>[
        'DeviceOrientation.portraitUp',
      ]);
    });

    test('태블릿 크기면 요청하지 않는다', () async {
      expect(
        await applyPhoneOrientationLock(
          screenSize: const Size(834, 1194),
          isWeb: false,
        ),
        isFalse,
      );
      expect(orientationCalls(), isEmpty);
    });

    test('웹이면 요청하지 않는다', () async {
      expect(
        await applyPhoneOrientationLock(
          screenSize: const Size(390, 844),
          isWeb: true,
        ),
        isFalse,
      );
      expect(orientationCalls(), isEmpty);
    });

    test('플랫폼이 실패해도 예외 없이 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (MethodCall call) async =>
                throw PlatformException(code: 'unavailable'),
          );
      expect(
        await applyPhoneOrientationLock(
          screenSize: const Size(390, 844),
          isWeb: false,
        ),
        isFalse,
      );
    });
  });

  test('bootstrap 이 앱 시작에서 방향 정책을 적용한다', () {
    final String source = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(source, contains('await applyPhoneOrientationLock();'));
  });

  group('iOS Info.plist', () {
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();

    List<String> orientations(String key) {
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

    test('iPhone 은 세로 하나뿐이다', () {
      expect(orientations('UISupportedInterfaceOrientations'), <String>[
        'UIInterfaceOrientationPortrait',
      ]);
    });

    test('iPad 는 네 방향을 유지한다(멀티태스킹 조건)', () {
      expect(
        orientations('UISupportedInterfaceOrientations~ipad'),
        unorderedEquals(<String>[
          'UIInterfaceOrientationPortrait',
          'UIInterfaceOrientationPortraitUpsideDown',
          'UIInterfaceOrientationLandscapeLeft',
          'UIInterfaceOrientationLandscapeRight',
        ]),
      );
    });
  });
}
