import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 저장값 [stored] 로 prefs 를 채운 컨테이너.
Future<(ProviderContainer, SharedPreferences)> _container({
  String? stored,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    TrainerLocaleController.storageKey: ?stored,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return (container, prefs);
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  final TestPlatformDispatcher dispatcher = binding.platformDispatcher;

  group('TrainerLanguage', () {
    test('maps each choice to its fixed locale', () {
      expect(TrainerLanguage.system.locale, isNull);
      expect(TrainerLanguage.korean.locale, const Locale('ko'));
      expect(TrainerLanguage.english.locale, const Locale('en'));
    });

    test('fromLocale finds the choice by language code', () {
      expect(TrainerLanguage.fromLocale(null), TrainerLanguage.system);
      expect(
        TrainerLanguage.fromLocale(const Locale('ko')),
        TrainerLanguage.korean,
      );
      expect(
        TrainerLanguage.fromLocale(const Locale('en', 'US')),
        TrainerLanguage.english,
      );
      expect(
        TrainerLanguage.fromLocale(const Locale('ko', 'KR')),
        TrainerLanguage.korean,
      );
    });

    test('fromCode reads stored codes, unknown ones mean the browser', () {
      expect(TrainerLanguage.fromCode('ko'), TrainerLanguage.korean);
      expect(TrainerLanguage.fromCode('en'), TrainerLanguage.english);
      expect(TrainerLanguage.fromCode('fr'), TrainerLanguage.system);
      expect(TrainerLanguage.fromCode(''), TrainerLanguage.system);
      expect(TrainerLanguage.fromCode(null), TrainerLanguage.system);
    });

    test('an unsupported language falls back to the browser setting', () {
      expect(
        TrainerLanguage.fromLocale(const Locale('fr')),
        TrainerLanguage.system,
      );
    });
  });

  group('trainerLocaleProvider', () {
    test('follows the browser when nothing is stored', () async {
      final (container, _) = await _container();
      expect(container.read(trainerLocaleProvider), isNull);
      expect(
        container.read(trainerLocaleProvider.notifier).language,
        TrainerLanguage.system,
      );
    });

    test('restores a stored Korean choice synchronously', () async {
      final (container, _) = await _container(stored: 'ko');
      expect(container.read(trainerLocaleProvider), const Locale('ko'));
    });

    test('restores a stored English choice synchronously', () async {
      final (container, _) = await _container(stored: 'en');
      expect(container.read(trainerLocaleProvider), const Locale('en'));
      expect(
        container.read(trainerLocaleProvider.notifier).language,
        TrainerLanguage.english,
      );
    });

    test('ignores a stored code the console does not support', () async {
      final (container, _) = await _container(stored: 'fr');
      expect(container.read(trainerLocaleProvider), isNull);
    });

    test('ignores an empty stored code', () async {
      final (container, _) = await _container(stored: '');
      expect(container.read(trainerLocaleProvider), isNull);
    });

    test('setLanguage updates state and persists the code', () async {
      final (container, prefs) = await _container();

      await container
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);

      expect(container.read(trainerLocaleProvider), const Locale('en'));
      expect(prefs.getString(TrainerLocaleController.storageKey), 'en');

      await container
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.korean);

      expect(container.read(trainerLocaleProvider), const Locale('ko'));
      expect(prefs.getString(TrainerLocaleController.storageKey), 'ko');
    });

    test('choosing the browser setting clears the stored value', () async {
      final (container, prefs) = await _container(stored: 'en');

      await container
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.system);

      expect(container.read(trainerLocaleProvider), isNull);
      expect(prefs.containsKey(TrainerLocaleController.storageKey), isFalse);
    });

    test('a saved choice survives a reload', () async {
      final (first, prefs) = await _container();
      await first
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);

      // 새로 고침 — 같은 저장소를 읽는 새 컨테이너.
      final ProviderContainer reloaded = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(reloaded.dispose);

      expect(reloaded.read(trainerLocaleProvider), const Locale('en'));
    });

    test('works without prefs instead of crashing', () async {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(trainerLocaleProvider), isNull);
      await container
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.korean);
      expect(container.read(trainerLocaleProvider), const Locale('ko'));
    });
  });

  group('resolveTrainerLocale', () {
    test('a chosen language wins over the browser', () {
      expect(
        resolveTrainerLocale(const Locale('en'), const <Locale>[Locale('ko')]),
        const Locale('en'),
      );
    });

    test('a Korean browser resolves to Korean', () {
      expect(
        resolveTrainerLocale(null, const <Locale>[Locale('ko', 'KR')]),
        const Locale('ko'),
      );
    });

    test('an English browser resolves to English', () {
      expect(
        resolveTrainerLocale(null, const <Locale>[Locale('en', 'GB')]),
        const Locale('en'),
      );
    });

    test('takes the first supported language in the browser list', () {
      expect(
        resolveTrainerLocale(null, const <Locale>[
          Locale('fr'),
          Locale('ko'),
          Locale('en'),
        ]),
        const Locale('ko'),
      );
    });

    test('an unsupported browser falls back like MaterialApp does', () {
      expect(
        resolveTrainerLocale(null, const <Locale>[Locale('fr')]),
        const Locale('en'),
      );
      expect(resolveTrainerLocale(null, const <Locale>[]), const Locale('en'));
    });
  });

  group('trainerResolvedLocaleProvider', () {
    test('follows the browser language and its changes', () async {
      dispatcher.localesTestValue = const <Locale>[Locale('ko', 'KR')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final (container, _) = await _container();

      expect(container.read(trainerResolvedLocaleProvider), const Locale('ko'));

      dispatcher.localesTestValue = const <Locale>[Locale('en', 'US')];

      expect(container.read(trainerResolvedLocaleProvider), const Locale('en'));
    });

    test('a chosen language overrides the browser', () async {
      dispatcher.localesTestValue = const <Locale>[Locale('ko', 'KR')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final (container, _) = await _container();

      await container
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.english);
      expect(container.read(trainerResolvedLocaleProvider), const Locale('en'));

      await container
          .read(trainerLocaleProvider.notifier)
          .setLanguage(TrainerLanguage.system);
      expect(container.read(trainerResolvedLocaleProvider), const Locale('ko'));
    });

    test('a stored choice is resolved from the first read', () async {
      dispatcher.localesTestValue = const <Locale>[Locale('en', 'US')];
      addTearDown(dispatcher.clearLocalesTestValue);
      final (container, _) = await _container(stored: 'ko');

      expect(container.read(trainerResolvedLocaleProvider), const Locale('ko'));
    });
  });
}
