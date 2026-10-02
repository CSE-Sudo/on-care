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

  /// 고를 때 화면에 있던 자료 — 그 뒤에 생긴 자료를 가려내는 데 쓴다(#2794).
  static String _seenKey(String account) => 'ai_routine_sources_seen.$account';

  /// 저장한 선택. 저장한 적이 없으면 [RoutineContextSource.defaults] 다.
  ///
  /// 모든 자료를 끈 선택(빈 목록)도 트레이너가 고른 값이라 기본값으로
  /// 되돌리지 않는다. 다만 **고를 때 없던 자료**는 기본값을 따른다 — 새로 생긴
  /// `최근 대화`(#2794)가 예전 선택에 없다고 꺼진 채로 시작하면, 업데이트만으로
  /// 늘 실리던 대화가 AI 에서 조용히 빠진다.
  Set<RoutineContextSource> read(String account) {
    final List<String>? stored = _prefs.getStringList(_key(account));
    if (stored == null) return RoutineContextSource.defaults;
    final List<String>? seenWires = _prefs.getStringList(_seenKey(account));
    final Set<RoutineContextSource> seen = seenWires == null
        ? RoutineContextSource.legacy
        : <RoutineContextSource>{
            for (final String wire in seenWires)
              ?RoutineContextSource.fromWire(wire),
          };
    return <RoutineContextSource>{
      for (final String wire in stored) ?RoutineContextSource.fromWire(wire),
      for (final RoutineContextSource source in RoutineContextSource.values)
        if (!seen.contains(source) && source.defaultOn) source,
    };
  }

  Future<void> write(String account, Set<RoutineContextSource> sources) async {
    await _prefs.setStringList(_key(account), <String>[
      for (final RoutineContextSource source in RoutineContextSource.values)
        if (sources.contains(source)) source.wire,
    ]);
    await _prefs.setStringList(_seenKey(account), <String>[
      for (final RoutineContextSource source in RoutineContextSource.values)
        source.wire,
    ]);
  }
}

/// 브라우저 저장소. 데모·실서버 모두 같은 저장소를 쓴다 — 서버에 두지 않는
/// 화면 설정이다.
final routineContextSourceStoreProvider = Provider<RoutineContextSourceStore>(
  (ref) => RoutineContextSourceStore(ref.watch(sharedPreferencesProvider)),
  name: 'routineContextSourceStore',
);
