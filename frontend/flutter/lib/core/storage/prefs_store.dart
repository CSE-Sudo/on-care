import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Injected once in `bootstrap.dart` (after `SharedPreferences.getInstance()`).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope.',
  ),
  name: 'sharedPreferences',
);

/// Convenience wrapper exposing typed accessors for the keys the app uses.
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const String _kLocaleCode = 'locale_code';
  static const String _kOnboardingDone = 'onboarding_done';

  /// 첫 홈 진입 스포트라이트 가이드를 이미 봤는지(#1857). 끝까지 봤든 건너뛰었든
  /// 같은 값이다 — 건너뛴 사람에게 같은 덮개를 다시 내밀지 않는다.
  static const String _kHomeGuideDone = 'home_guide_done';

  /// 이 설치본이 한 번이라도 실행됐는가(#1944).
  ///
  /// **앱을 지우면 함께 지워진다** — 그것이 이 값을 쓰는 이유다. iOS 키체인
  /// 항목은 앱을 지워도 남아서, 재설치하고 열면 이전 계정 대시보드로 바로
  /// 들어갔다. 이 표식이 없는 실행은 새 설치이므로 그때 키체인을 비운다.
  static const String _kInstalled = 'installed';

  String? get localeCode => _prefs.getString(_kLocaleCode);
  Future<void> setLocaleCode(String? value) {
    if (value == null) return _prefs.remove(_kLocaleCode);
    return _prefs.setString(_kLocaleCode, value);
  }

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone(bool value) =>
      _prefs.setBool(_kOnboardingDone, value);

  bool get homeGuideDone => _prefs.getBool(_kHomeGuideDone) ?? false;
  Future<void> setHomeGuideDone(bool value) =>
      _prefs.setBool(_kHomeGuideDone, value);

  bool get installed => _prefs.getBool(_kInstalled) ?? false;
  Future<void> markInstalled() => _prefs.setBool(_kInstalled, true);
}

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
  name: 'appPrefs',
);
