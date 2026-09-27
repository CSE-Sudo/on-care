import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';

const ValueKey<String> _button = ValueKey<String>('my-language-button');

ValueKey<String> _item(TrainerLanguage language) =>
    ValueKey<String>('my-language-${language.name}');

/// 설정 탭을 연다. [stored] 가 있으면 그 언어가 저장된 브라우저에서 연다.
Future<ProviderContainer> _openSettings(
  WidgetTester tester, {
  Locale locale = const Locale('ko'),
  String? stored,
}) async {
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
    at: AppRoutes.mySection('settings'),
    locale: locale,
    extraOverrides: overrides,
  );
}

Future<void> _choose(WidgetTester tester, TrainerLanguage language) async {
  await tester.ensureVisible(find.byKey(_button));
  await tester.tap(find.byKey(_button));
  await tester.pump();
  await tester.tap(find.byKey(_item(language)));
  await settle(tester);
}

void main() {
  group('설정 · 화면 언어', () {
    testWidgets('shows the language row, following the browser by default', (
      tester,
    ) async {
      await _openSettings(tester);

      // 설정 목록의 한 줄이다(#2264) — 카드 제목 '언어' 는 따로 없다.
      expect(find.text('화면 언어'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_button),
          matching: find.text('브라우저 설정 따르기'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    });

    testWidgets('sits between notifications and account', (tester) async {
      await _openSettings(tester);

      final double notif = tester.getTopLeft(find.text('알림')).dy;
      final double language = tester.getTopLeft(find.text('화면 언어')).dy;
      final double account = tester.getTopLeft(find.text('계정')).dy;
      expect(notif, lessThan(language));
      expect(language, lessThan(account));
    });

    testWidgets('the menu lists all three choices and checks the current one', (
      tester,
    ) async {
      await _openSettings(tester);

      await tester.tap(find.byKey(_button));
      await tester.pump();

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
      expect(find.text('Display language'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('화면 언어'), findsNothing);
      expect(find.text('알림'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_button),
          matching: find.text('English'),
        ),
        findsOneWidget,
      );

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

      expect(find.text('Display language'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_button),
          matching: find.text('Match browser'),
        ),
        findsOneWidget,
      );

      await _choose(tester, TrainerLanguage.korean);

      expect(find.text('화면 언어'), findsOneWidget);
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
      expect(find.text('Display language'), findsOneWidget);

      await _choose(tester, TrainerLanguage.system);

      // 테스트의 '브라우저 언어' 는 한국어다(pumpTrainerApp 의 locale).
      expect(find.text('화면 언어'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_button),
          matching: find.text('브라우저 설정 따르기'),
        ),
        findsOneWidget,
      );
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

      expect(find.text('Display language'), findsOneWidget);
      expect(find.text('Settings'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(_button),
          matching: find.text('English'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a saved Korean choice wins over an English browser', (
      tester,
    ) async {
      await _openSettings(tester, locale: const Locale('en'), stored: 'ko');

      expect(find.text('화면 언어'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_button), matching: find.text('한국어')),
        findsOneWidget,
      );
    });

    testWidgets('an unknown saved value falls back to the browser', (
      tester,
    ) async {
      await _openSettings(tester, stored: 'fr');

      expect(find.text('화면 언어'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_button),
          matching: find.text('브라우저 설정 따르기'),
        ),
        findsOneWidget,
      );
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
      final Finder toggle = find.byType(Switch);
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
