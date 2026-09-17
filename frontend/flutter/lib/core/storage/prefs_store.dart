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

  /// 계정에 매인 기기 기록을 지운다 — 탈퇴한 계정의 흔적이 다음 회원에게
  /// 넘어가지 않게 한다(#1935). 같은 기기에 다른 계정으로 로그인했을 때
  /// 첫 설정과 가이드를 처음처럼 만나야 한다.
  ///
  /// **언어는 남긴다.** 기기 설정이지 계정의 것이 아니다.
  Future<void> clearAccountScoped() async {
    await _prefs.remove(_kOnboardingDone);
    await _prefs.remove(_kHomeGuideDone);
  }
}

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
  name: 'appPrefs',
);
