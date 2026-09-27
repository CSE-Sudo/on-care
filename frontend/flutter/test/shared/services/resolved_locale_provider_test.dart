import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/shared/services/locale_provider.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  final TestPlatformDispatcher dispatcher = binding.platformDispatcher;

  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('resolveAppLocale', () {
    test('a chosen language wins over the device', () {
      expect(
        resolveAppLocale(const Locale('en'), const <Locale>[Locale('ko')]),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const Locale('ko'), const <Locale>[Locale('en')]),
        const Locale('ko'),
      );
    });

    test('a Korean device resolves to Korean', () {
      expect(
        resolveAppLocale(null, const <Locale>[Locale('ko', 'KR')]),
        const Locale('ko'),
      );
    });

    test('an English device resolves to English', () {
      expect(
        resolveAppLocale(null, const <Locale>[Locale('en', 'AU')]),
        const Locale('en'),
      );
    });

    test('takes the first supported language in the device list', () {
      expect(
        resolveAppLocale(null, const <Locale>[
          Locale('ja'),
          Locale('ko'),
          Locale('en'),
        ]),
        const Locale('ko'),
      );
    });

    test('an unsupported device falls back like MaterialApp does', () {
      expect(
        resolveAppLocale(null, const <Locale>[Locale('ja')]),
        const Locale('en'),
      );
      expect(resolveAppLocale(null, const <Locale>[]), const Locale('en'));
    });
  });

  group('resolvedLocaleProvider', () {
    test('follows the device language and its changes', () {
      dispatcher.localesTestValue = const <Locale>[Locale('ko', 'KR')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final ProviderContainer c = container();

      expect(c.read(resolvedLocaleProvider), const Locale('ko'));

      dispatcher.localesTestValue = const <Locale>[Locale('en', 'US')];

      expect(c.read(resolvedLocaleProvider), const Locale('en'));
    });

    test('a chosen language overrides the device and can be cleared', () {
      dispatcher.localesTestValue = const <Locale>[Locale('ko', 'KR')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final ProviderContainer c = container();

      c.read(localeProvider.notifier).state = const Locale('en');
      expect(c.read(resolvedLocaleProvider), const Locale('en'));

      c.read(localeProvider.notifier).state = null;
      expect(c.read(resolvedLocaleProvider), const Locale('ko'));
    });

    test('an overridden locale (as widget tests do) is honoured', () {
      dispatcher.localesTestValue = const <Locale>[Locale('ko')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          localeProvider.overrideWith((Ref ref) => const Locale('en')),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(resolvedLocaleProvider), const Locale('en'));
    });
  });
}
