import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "이 브라우저에서 알림 받기"(#3285).
///
/// 계정이 아니라 **브라우저마다** 따로다 — 센터 PC 는 켜고 태블릿은 끄는 경우가
/// 있다. 그래서 서버가 아니라 `SharedPreferences` 에 둔다. 기본은 끔: 켤 때
/// 브라우저가 권한을 물어야 하므로 트레이너가 직접 켠다.
///
/// 탭 제목의 안 읽은 수는 이 설정과 상관없이 보인다 — 권한이 필요 없고 조용하다.
class DesktopAlertPreference extends StateNotifier<bool> {
  /// 저장된 값으로 시작한다. [prefs] 가 없으면(설정이 빠진 테스트) 저장 없이 동작한다.
  DesktopAlertPreference(this._prefs)
    : super(_prefs?.getBool(storageKey) ?? false);

  /// 저장 키.
  static const String storageKey = 'trainer.desktopAlerts.enabled';

  final SharedPreferences? _prefs;

  /// 켜고 끈다.
  Future<void> set({required bool enabled}) async {
    state = enabled;
    await _prefs?.setBool(storageKey, enabled);
  }
}

/// 이 브라우저에서 화면 구석 알림을 받는가.
final desktopAlertPreferenceProvider =
    StateNotifierProvider<DesktopAlertPreference, bool>((ref) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // prefs 를 주입하지 않은 위젯 테스트 — 저장 없이 끔으로 시작한다.
        prefs = null;
      }
      return DesktopAlertPreference(prefs);
    }, name: 'desktopAlertPreference');
