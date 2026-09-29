import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 트레이너가 AI 추천 위저드에서 고른 참고 자료를 브라우저에 기억한다(#2587).
///
/// 서버가 아니라 브라우저에 두는 이유: 화면 편의 설정이라 계정 데이터로
/// 옮길 만큼의 값이 아니고, 기기를 바꾸면 기본값으로 돌아가도 잃는 것이 없다.
///
/// 한 브라우저에서 트레이너가 번갈아 로그인할 수 있으므로 **계정별 키**로
/// 저장한다. 키는 로그인한 트레이너의 이메일, 데모는 `demo` 다.
class RoutineContextSourceStore {
  const RoutineContextSourceStore(this._prefs);

  final SharedPreferences _prefs;

  static String _key(String account) => 'ai_routine_sources.$account';

  /// 저장한 선택. 저장한 적이 없으면 [RoutineContextSource.defaults] 다.
  ///
  /// 모든 자료를 끈 선택(빈 목록)도 트레이너가 고른 값이라 기본값으로
  /// 되돌리지 않는다.
  Set<RoutineContextSource> read(String account) {
    final List<String>? stored = _prefs.getStringList(_key(account));
    if (stored == null) return RoutineContextSource.defaults;
    return <RoutineContextSource>{
      for (final String wire in stored) ?RoutineContextSource.fromWire(wire),
    };
  }

  Future<void> write(String account, Set<RoutineContextSource> sources) =>
      _prefs.setStringList(_key(account), <String>[
        for (final RoutineContextSource source in RoutineContextSource.values)
          if (sources.contains(source)) source.wire,
      ]);
}

/// 브라우저 저장소. 데모·실서버 모두 같은 저장소를 쓴다 — 서버에 두지 않는
/// 화면 설정이다.
final routineContextSourceStoreProvider = Provider<RoutineContextSourceStore>(
  (ref) => RoutineContextSourceStore(ref.watch(sharedPreferencesProvider)),
  name: 'routineContextSourceStore',
);
