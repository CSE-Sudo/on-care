/// 설정 › 알림의 데스크톱 알림 — 이 브라우저에서 화면 구석 알림을 받을지. (#3285)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/browser_alerts.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/desktop_alert_preference.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

import '../../helpers/pump_app.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

/// 권한을 테스트가 정하는 브라우저. [answer] 는 물었을 때 사용자의 대답이다.
class _FakeAlerts implements BrowserAlerts {
  _FakeAlerts(this.current, {this.answer = BrowserAlertPermission.granted});

  BrowserAlertPermission current;
  final BrowserAlertPermission answer;
  int asked = 0;
  final List<BrowserAlert> shown = <BrowserAlert>[];

  @override
  BrowserAlertPermission get permission => current;

  @override
  Future<BrowserAlertPermission> requestPermission() async {
    asked++;
    if (current == BrowserAlertPermission.notAsked) current = answer;
    return current;
  }

  @override
  void show(BrowserAlert alert, {required void Function() onClick}) =>
      shown.add(alert);

  @override
  bool get pageFocused => true;

  @override
  void setIconDot({required bool on}) {}
}

const Key _switchKey = ValueKey<String>('my-notif-desktop');
const Key _testKey = ValueKey<String>('my-notif-desktop-test');

void main() {
  Future<ProviderContainer> open(WidgetTester tester, _FakeAlerts alerts) =>
      pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.mySection('notifications'),
        extraOverrides: <Override>[
          browserAlertsProvider.overrideWithValue(alerts),
        ],
      );

  Switch desktopSwitch(WidgetTester tester) =>
      tester.widget<Switch>(find.byKey(_switchKey));

  testWidgets('켜면 권한을 묻고, 허용하면 켜지며 시험 알림과 컴퓨터 설정 안내가 보인다', (tester) async {
    await withWideSurface(tester, () async {
      final _FakeAlerts alerts = _FakeAlerts(BrowserAlertPermission.notAsked);
      final ProviderContainer container = await open(tester, alerts);

      expect(find.text(_ko.myNotifDesktopTitle), findsOneWidget);
      expect(find.text(_ko.myNotifDesktopNotAsked), findsOneWidget);
      expect(desktopSwitch(tester).value, isFalse);
      expect(find.byKey(_testKey), findsNothing);

      await tester.ensureVisible(find.byKey(_switchKey));
      await tester.tap(find.byKey(_switchKey));
      await settle(tester);

      expect(alerts.asked, 1);
      expect(desktopSwitch(tester).value, isTrue);
      expect(container.read(desktopAlertPreferenceProvider), isTrue);
      expect(find.text(_ko.myNotifDesktopGranted), findsOneWidget);
      expect(find.text(_ko.myNotifDesktopOsHint), findsOneWidget);

      await tester.ensureVisible(find.byKey(_testKey));
      await tester.tap(find.byKey(_testKey));
      await settle(tester);
      expect(alerts.shown.single.title, _ko.myNotifDesktopTestTitle);
    });
  });

  testWidgets('권한을 허용하지 않으면 끔으로 남고 차단 안내를 보인다', (tester) async {
    await withWideSurface(tester, () async {
      final _FakeAlerts alerts = _FakeAlerts(
        BrowserAlertPermission.notAsked,
        answer: BrowserAlertPermission.denied,
      );
      final ProviderContainer container = await open(tester, alerts);

      await tester.ensureVisible(find.byKey(_switchKey));
      await tester.tap(find.byKey(_switchKey));
      await settle(tester);

      expect(desktopSwitch(tester).value, isFalse);
      expect(desktopSwitch(tester).onChanged, isNull);
      expect(container.read(desktopAlertPreferenceProvider), isFalse);
      expect(find.text(_ko.myNotifDesktopDenied), findsOneWidget);
    });
  });

  testWidgets('이미 차단돼 있으면 스위치를 막고 푸는 곳을 안내한다', (tester) async {
    await withWideSurface(tester, () async {
      await open(tester, _FakeAlerts(BrowserAlertPermission.denied));

      expect(desktopSwitch(tester).onChanged, isNull);
      expect(find.text(_ko.myNotifDesktopDenied), findsOneWidget);
    });
  });

  testWidgets('알림을 쓸 수 없는 브라우저는 스위치를 막고 그렇다고 알린다', (tester) async {
    await withWideSurface(tester, () async {
      await open(tester, _FakeAlerts(BrowserAlertPermission.unsupported));

      expect(desktopSwitch(tester).onChanged, isNull);
      expect(find.text(_ko.myNotifDesktopUnsupported), findsOneWidget);
    });
  });

  testWidgets('끄면 시험 알림과 안내가 사라진다', (tester) async {
    await withWideSurface(tester, () async {
      final _FakeAlerts alerts = _FakeAlerts(BrowserAlertPermission.granted);
      final ProviderContainer container = await open(tester, alerts);
      await container
          .read(desktopAlertPreferenceProvider.notifier)
          .set(enabled: true);
      await settle(tester);
      expect(find.byKey(_testKey), findsOneWidget);

      await tester.ensureVisible(find.byKey(_switchKey));
      await tester.tap(find.byKey(_switchKey));
      await settle(tester);

      expect(desktopSwitch(tester).value, isFalse);
      expect(find.byKey(_testKey), findsNothing);
      expect(find.text(_ko.myNotifDesktopOsHint), findsNothing);
      expect(alerts.asked, 0);
    });
  });
}
