import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 데모 모드가 심고 보여 주는 **내용**(회원 목표·대화·식단·상담·프로필)의 언어.
/// (#2304)
///
/// 화면 문구는 ARB 가 로케일마다 고르지만, 데모 내용은 로컬 DB 와 목 저장소가
/// 들고 있는 값이라 ARB 를 거치지 않는다. 그래서 앱이 켜질 때 한 번 언어를 정해
/// 그 언어로 심는다. 사람 이름은 어느 언어에서든 그대로 둔다.
enum DemoLanguage {
  /// 한국어 — 지금까지의 데모 내용 그대로다.
  ko,

  /// 영어.
  en;

  /// 이 언어의 로케일. 감지 메모의 요약 문구처럼 ARB 를 읽어야 하는 곳이 쓴다.
  Locale get locale => Locale(name);

  bool get isEnglish => this == DemoLanguage.en;
}

/// 데모 내용의 언어를 정한다.
///
/// [saved] 는 설정에서 고른 화면 언어(`ko`·`en`)다. 없거나 모르는 값이면
/// [preferred](브라우저 언어 목록)를 `MaterialApp` 과 같은 규칙으로 풀어 화면
/// 언어와 맞춘다 — 영어 화면에 한국어 대화가 뜨면 데모가 반쯤만 번역된 것처럼
/// 보인다.
DemoLanguage resolveDemoLanguage(Iterable<Locale> preferred, {String? saved}) {
  for (final DemoLanguage language in DemoLanguage.values) {
    if (saved == language.name) return language;
  }
  final Locale resolved = basicLocaleListResolution(
    preferred.toList(growable: false),
    AppLocalizations.supportedLocales,
  );
  return resolved.languageCode == DemoLanguage.en.name
      ? DemoLanguage.en
      : DemoLanguage.ko;
}

/// 설정에서 고른 화면 언어가 저장되는 `SharedPreferences` 키(#2296).
const String savedLocalePrefsKey = 'trainer.locale';

/// 이번 실행의 데모 내용 언어. `bootstrap()` 이 정해 덮어쓴다.
///
/// 기본값이 한국어인 이유: 덮어쓰지 않는 위젯 테스트가 지금까지처럼 한국어
/// 데모 내용을 읽는다.
final demoLanguageProvider = Provider<DemoLanguage>(
  (ref) => DemoLanguage.ko,
  name: 'demoLanguage',
);
