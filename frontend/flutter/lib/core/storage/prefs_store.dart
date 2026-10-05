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

  /// 첫 설정 기기 기록만 지운다 — 새 토큰으로 로그인할 때 부른다. (#2630)
  ///
  /// 이 기록은 프로필을 못 받아 왔을 때의 보조 판단이라 **지금 세션의 계정
  /// 것**이어야 한다. 기기 전체에 하나로 남기면 앞 계정이 끝낸 기록을 보고 첫
  /// 설정을 안 한 새 계정을 홈으로 보낸다. 로그아웃·만료는 홈 가이드 기록까지
  /// 함께 지우는 [clearAccountScoped] 를 쓴다(#3154).
  Future<void> forgetOnboardingDone() => _prefs.remove(_kOnboardingDone);

  bool get homeGuideDone => _prefs.getBool(_kHomeGuideDone) ?? false;
  Future<void> setHomeGuideDone(bool value) =>
      _prefs.setBool(_kHomeGuideDone, value);

  bool get installed => _prefs.getBool(_kInstalled) ?? false;
  Future<void> markInstalled() => _prefs.setBool(_kInstalled, true);

  /// 계정에 매인 기기 기록을 지운다 — 앞 계정의 흔적이 다음 회원에게
  /// 넘어가지 않게 한다. 같은 기기에 다른 계정으로 로그인했을 때 첫 설정과
  /// 가이드를 처음처럼 만나야 한다.
  ///
  /// 탈퇴(#1935)만이 아니라 세션이 끝나는 모든 길 — 로그아웃, 저장된 세션의
  /// 만료, 실행 중 갱신 거부로 인한 강제 로그아웃 — 에서 부른다(#3154). 예전에는
  /// 탈퇴할 때만 불려, 가족 휴대폰·헬스장 공용 기기에서 계정만 바꿔 로그인한
  /// 새 회원은 앞 계정이 끝낸 홈 가이드를 한 번도 보지 못했다.
  ///
  /// **언어와 설치 표식은 남긴다.** 둘 다 기기의 것이지 계정의 것이 아니다 —
  /// 설치 표식을 지우면 다음 실행이 새 설치로 보여 키체인을 또 비운다(#1944).
  Future<void> clearAccountScoped() async {
    await _prefs.remove(_kOnboardingDone);
    await _prefs.remove(_kHomeGuideDone);
  }
}

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
  name: 'appPrefs',
);
