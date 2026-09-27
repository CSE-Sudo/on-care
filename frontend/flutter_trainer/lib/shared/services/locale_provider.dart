import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정에서 고르는 화면 언어(#2296).
///
/// [system] 은 브라우저(기기) 언어를 따른다 — 지금까지의 동작이고 기본값이다.
/// 나머지 둘은 브라우저 언어와 상관없이 그 언어로 고정한다.
enum TrainerLanguage {
  /// 브라우저 언어를 따른다.
  system(null),

  /// 한국어로 고정.
  korean(Locale('ko')),

  /// 영어로 고정.
  english(Locale('en'));

  const TrainerLanguage(this.locale);

  /// 고정할 로케일. [system] 이면 `null` 이다.
  final Locale? locale;

  /// 로케일에서 선택지를 되찾는다. 모르는 언어는 [system] 이다.
  static TrainerLanguage fromLocale(Locale? locale) =>
      fromCode(locale?.languageCode);

  /// 언어 코드(`ko`·`en`)에서 선택지를 되찾는다. 모르는 코드·빈 값은
  /// [system] 이다.
  static TrainerLanguage fromCode(String? code) {
    for (final TrainerLanguage language in values) {
      final Locale? own = language.locale;
      if (own != null && own.languageCode == code) return language;
    }
    return system;
  }
}

/// 고른 언어를 이 브라우저에 남긴다. 계정이 아니라 기기 단위 설정이라
/// 서버가 아니라 `SharedPreferences` 에 둔다 — 공용 PC 에서 다른 트레이너가
/// 로그인해도 화면 언어는 그 자리의 것을 따른다.
class TrainerLocaleController extends StateNotifier<Locale?> {
  /// 저장된 값으로 시작한다. 첫 프레임부터 그 언어로 그려야 깜박이지 않으므로
  /// 읽기는 동기다. [prefs] 가 없으면(설정이 빠진 테스트) 저장 없이 동작한다.
  TrainerLocaleController(this._prefs) : super(_read(_prefs));

  /// 저장 키. 값은 언어 코드(`ko`·`en`)이고, 없으면 브라우저 언어를 따른다.
  static const String storageKey = 'trainer.locale';

  final SharedPreferences? _prefs;

  static Locale? _read(SharedPreferences? prefs) {
    // 지원하지 않는 코드(예전 빌드·손으로 고친 값)는 버리고 브라우저를 따른다.
    return TrainerLanguage.fromCode(prefs?.getString(storageKey)).locale;
  }

  /// 지금 고른 선택지.
  TrainerLanguage get language => TrainerLanguage.fromLocale(state);

  /// [language] 로 바꾸고 저장한다. [TrainerLanguage.system] 은 저장값을 지운다.
  Future<void> setLanguage(TrainerLanguage language) async {
    final Locale? next = language.locale;
    state = next;
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    if (next == null) {
      await prefs.remove(storageKey);
    } else {
      await prefs.setString(storageKey, next.languageCode);
    }
  }
}

/// 사용자가 고른 화면 언어. `null` 이면 브라우저 언어를 따른다.
///
/// `MaterialApp.locale` 로 들어가는 값이다. 실제로 화면에 쓰이는 언어가
/// 필요하면(요청 헤더 등) [trainerResolvedLocaleProvider] 를 읽는다.
final trainerLocaleProvider =
    StateNotifierProvider<TrainerLocaleController, Locale?>((ref) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // prefs 를 주입하지 않은 위젯 테스트 — 저장 없이 브라우저 언어를 따른다.
        prefs = null;
      }
      return TrainerLocaleController(prefs);
    }, name: 'trainerLocale');

/// 브라우저(기기)가 선호하는 언어 목록. 사용자가 브라우저 언어를 바꾸면
/// 따라 바뀐다.
class PlatformLocalesNotifier extends StateNotifier<List<Locale>>
    with WidgetsBindingObserver {
  /// 지금의 목록으로 시작하고 바뀌는 것을 지켜본다.
  PlatformLocalesNotifier()
    : super(WidgetsBinding.instance.platformDispatcher.locales) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    state = locales ?? WidgetsBinding.instance.platformDispatcher.locales;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// 브라우저가 선호하는 언어 목록.
final platformLocalesProvider =
    StateNotifierProvider<PlatformLocalesNotifier, List<Locale>>(
      (ref) => PlatformLocalesNotifier(),
      name: 'platformLocales',
    );

/// 고른 언어와 브라우저 언어 목록으로 **실제 화면 언어**를 정한다.
///
/// 고른 언어가 있으면 그것이고, 없으면 `MaterialApp` 과 같은 규칙
/// ([basicLocaleListResolution])으로 지원 언어 중 하나를 고른다. 그래서 이
/// 값은 화면이 그리는 언어와 어긋나지 않는다.
Locale resolveTrainerLocale(Locale? chosen, List<Locale> preferred) {
  if (chosen != null) return chosen;
  return basicLocaleListResolution(
    preferred,
    AppLocalizations.supportedLocales,
  );
}

/// 지금 화면이 쓰는 언어 — 항상 지원 언어(`ko`·`en`) 중 하나다.
///
/// 서버에 보내는 `Accept-Language` 처럼 위젯 밖에서 언어가 필요한 곳이 읽는다.
final trainerResolvedLocaleProvider = Provider<Locale>((ref) {
  return resolveTrainerLocale(
    ref.watch(trainerLocaleProvider),
    ref.watch(platformLocalesProvider),
  );
}, name: 'trainerResolvedLocale');
