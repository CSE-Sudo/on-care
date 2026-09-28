import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

ValueKey<String> _item(TrainerLanguage language) =>
    ValueKey<String>('my-language-${language.name}');

/// 설정의 화면 언어 판을 넓은 화면에서 연다 — 목록과 판이 함께 보인다(#2264).
/// [stored] 가 있으면 그 언어가 저장된 브라우저에서 연다.
Future<ProviderContainer> _openSettings(
  WidgetTester tester, {
  Locale locale = const Locale('ko'),
  String? stored,
}) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<Override> overrides = <Override>[];
  if (stored != null) {
    // pumpTrainerApp 은 prefs 를 비워 두므로, 저장값이 든 prefs 를 이 provider
    // 에만 따로 준다 — 새로 고침한 브라우저가 읽는 것과 같은 경로다.
    SharedPreferences.setMockInitialValues(<String, Object>{
      TrainerLocaleController.storageKey: stored,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    overrides.add(
      trainerLocaleProvider.overrideWith(
        (ref) => TrainerLocaleController(prefs),
      ),
    );
  }
  return pumpTrainerApp(
    tester,
    token: 'demo-trainer-token',
    at: AppRoutes.mySection('language'),
    locale: locale,
    extraOverrides: overrides,
  );
}

Future<void> _choose(WidgetTester tester, TrainerLanguage language) async {
  await tester.tap(find.byKey(_item(language)));
  await settle(tester);
}

/// 지금 고른 언어 — 그 줄에 체크가 달린다.
Finder _checked(TrainerLanguage language) => find.descendant(
  of: find.byKey(_item(language)),
  matching: find.byIcon(Icons.check_rounded),
);

void main() {
  group('설정 · 화면 언어', () {
    testWidgets('shows the language row, following the browser by default', (
      tester,
    ) async {
      await _openSettings(tester);

      // 설정 목록의 한 항목이고, 고르면 옆 판이 열린다(#2264).
      expect(find.text('화면 언어'), findsWidgets);
      expect(_checked(TrainerLanguage.system), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsWidgets);
    });

    testWidgets('sits between notifications and account', (tester) async {
      await _openSettings(tester);

      // 메뉴 항목끼리 비교한다 — 화면 제목도 '화면 언어' 다.
      double top(String section) => tester
          .getTopLeft(find.byKey(ValueKey<String>('my-$section-entry')))
          .dy;
      final double notif = top('notifications');
      final double language = top('language');
      final double account = top('account');
      expect(notif, lessThan(language));
      expect(language, lessThan(account));
    });

    testWidgets('the menu lists all three choices and checks the current one', (
      tester,
    ) async {
      await _openSettings(tester);

      for (final TrainerLanguage language in TrainerLanguage.values) {
        expect(find.byKey(_item(language)), findsOneWidget);
      }
      // 언어 이름은 어느 화면 언어에서든 자기 말로 적는다.
      expect(
        find.descendant(
          of: find.byKey(_item(TrainerLanguage.korean)),
          matching: find.text('한국어'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_item(TrainerLanguage.english)),
          matching: find.text('English'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_item(TrainerLanguage.system)),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_item(TrainerLanguage.english)),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('choosing English switches the console at once and saves it', (
      tester,
    ) async {
      final ProviderContainer container = await _openSettings(tester);

      await _choose(tester, TrainerLanguage.english);

      // 설정 화면 자신과 셸이 모두 영어로 다시 그려진다.
      expect(find.text('Display language'), findsWidgets);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('화면 언어'), findsNothing);
      expect(find.text('알림'), findsNothing);
      expect(_checked(TrainerLanguage.english), findsOneWidget);

      expect(container.read(trainerLocaleProvider), const Locale('en'));
      expect(container.read(trainerResolvedLocaleProvider), const Locale('en'));
      final SharedPreferences prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(TrainerLocaleController.storageKey), 'en');
    });

    testWidgets('choosing 한국어 on an English browser switches to Korean', (
      tester,
    ) async {
      final ProviderContainer container = await _openSettings(
        tester,
        locale: const Locale('en'),
      );

      expect(find.text('Display language'), findsWidgets);
      expect(_checked(TrainerLanguage.system), findsOneWidget);

      await _choose(tester, TrainerLanguage.korean);

      expect(find.text('화면 언어'), findsWidgets);
      expect(find.text('Display language'), findsNothing);
      expect(
        container
            .read(sharedPreferencesProvider)
            .getString(TrainerLocaleController.storageKey),
        'ko',
      );
    });

    testWidgets('going back to the browser setting clears the saved choice', (
      tester,
    ) async {
      final ProviderContainer container = await _openSettings(tester);

      await _choose(tester, TrainerLanguage.english);
      expect(find.text('Display language'), findsWidgets);

      await _choose(tester, TrainerLanguage.system);

      // 테스트의 '브라우저 언어' 는 한국어다(pumpTrainerApp 의 locale).
      expect(find.text('화면 언어'), findsWidgets);
      expect(_checked(TrainerLanguage.system), findsOneWidget);
      expect(container.read(trainerLocaleProvider), isNull);
      expect(
        container
            .read(sharedPreferencesProvider)
            .containsKey(TrainerLocaleController.storageKey),
        isFalse,
      );
    });

    testWidgets('a saved English choice is used from the first frame', (
      tester,
    ) async {
      await _openSettings(tester, stored: 'en');

      expect(find.text('Display language'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(_checked(TrainerLanguage.english), findsOneWidget);
    });

    testWidgets('a saved Korean choice wins over an English browser', (
      tester,
    ) async {
      await _openSettings(tester, locale: const Locale('en'), stored: 'ko');

      expect(find.text('화면 언어'), findsWidgets);
      expect(_checked(TrainerLanguage.korean), findsOneWidget);
    });

    testWidgets('an unknown saved value falls back to the browser', (
      tester,
    ) async {
      await _openSettings(tester, stored: 'fr');

      expect(find.text('화면 언어'), findsWidgets);
      expect(_checked(TrainerLanguage.system), findsOneWidget);
    });

    testWidgets('the rest of the settings still work after switching', (
      tester,
    ) async {
      await _openSettings(tester);

      await _choose(tester, TrainerLanguage.english);

      // 알림 스위치는 언어를 바꾼 뒤에도 그대로 살아 있다. 스위치는 알림
      // 하위 화면에 있다(#2264).
      await tester.tap(find.text('Notifications'));
      await settle(tester);
      final Finder toggle = find.byKey(
        const ValueKey<String>('my-notif-new-message'),
      );
      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await settle(tester);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(find.text('New message alerts'), findsOneWidget);
    });
  });
}
