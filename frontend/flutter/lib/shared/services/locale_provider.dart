import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// User-controlled app locale. `null` follows the system locale.
/// A future settings page mutates this; persistence to `AppPrefs`
/// lands together with that page.
final localeProvider = StateProvider<Locale?>((ref) => null, name: 'locale');

/// 기기가 선호하는 언어 목록. 사용자가 기기 언어를 바꾸면 따라 바뀐다.
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

/// 기기가 선호하는 언어 목록.
final platformLocalesProvider =
    StateNotifierProvider<PlatformLocalesNotifier, List<Locale>>(
      (ref) => PlatformLocalesNotifier(),
      name: 'platformLocales',
    );

/// 고른 언어와 기기 언어 목록으로 **실제 화면 언어**를 정한다.
///
/// 고른 언어가 있으면 그것이고, 없으면 `MaterialApp` 과 같은 규칙
/// ([basicLocaleListResolution])으로 지원 언어 중 하나를 고른다. 그래서 이
/// 값은 화면이 그리는 언어와 어긋나지 않는다.
Locale resolveAppLocale(Locale? chosen, List<Locale> preferred) {
  if (chosen != null) return chosen;
  return basicLocaleListResolution(
    preferred,
    AppLocalizations.supportedLocales,
  );
}

/// 지금 화면이 쓰는 언어 — 항상 지원 언어(`ko`·`en`) 중 하나다(#2297).
///
/// 서버에 보내는 `Accept-Language` 처럼 위젯 밖에서 언어가 필요한 곳이 읽는다.
final resolvedLocaleProvider = Provider<Locale>((ref) {
  return resolveAppLocale(
    ref.watch(localeProvider),
    ref.watch(platformLocalesProvider),
  );
}, name: 'resolvedLocale');
