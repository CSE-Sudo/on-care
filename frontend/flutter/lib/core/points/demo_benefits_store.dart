import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/storage/app_database.dart';

/// 데모 혜택 장부를 담는 키-값 키(#2664). 장부마다 한 구획이고, 한 키에 통째로 쓴다.
///
/// 시드 플래그(`seeded_vNN`)를 새로 쓰는 첫 부팅에 `seedIfEmpty` 가 이 키를 지운다 —
/// 플래그를 올리면 혜택 시드도 새로 깔린다. 날짜만 바뀐 부팅에는 지우지 않아, 회원이
/// 데모에서 쌓은 포인트·쿠폰이 다음 날에도 남는다(실서버처럼).
const String kDemoBenefitsKey = 'demo_benefits';

/// 저장소에 실을 수 있는 데모 장부. 서버 원장의 대역들이 이것을 따른다.
abstract interface class DemoPersistable {
  /// 지금 상태 — [restore] 가 그대로 되살릴 수 있는 JSON.
  Map<String, Object?> toJson();

  /// [toJson] 이 쓴 상태로 되돌린다.
  void restore(Map<String, Object?> json);

  /// 상태가 바뀔 때마다 부른다. 저장소가 붙인다.
  set onChanged(void Function()? callback);
}

/// 데모 혜택 장부의 저장소(#2664).
///
/// 포인트·쿠폰·챌린지·보호권·이모티콘 장부는 메모리에 있어 새로고침하면 비었다.
/// 부팅할 때 [open] 이 `AppKeyValues` 에서 저장분을 읽어(없으면 시드를 만들어) 들고
/// 있고, 장부 프로바이더가 [attach] 로 되살린 뒤 바뀔 때마다 다시 쓴다.
///
/// 기본값([DemoBenefitsStore.memory])은 아무것도 읽거나 쓰지 않는다 — 테스트와
/// 실서버 모드의 장부는 지금처럼 빈 채로 시작한다.
class DemoBenefitsStore {
  DemoBenefitsStore._(this._sections, this._write);

  DemoBenefitsStore.memory() : this._(<String, Map<String, Object?>>{}, null);

  final Map<String, Map<String, Object?>> _sections;
  final Future<void> Function(String value)? _write;

  /// [db] 의 저장분을 읽는다. 없거나 읽지 못하면 [seed] 로 채우고 곧바로 쓴다.
  ///
  /// 웹에서 drift 가 열리지 않아도 시드는 화면에 뜬다 — 쓰기만 조용히 실패한다.
  static Future<DemoBenefitsStore> open(
    AppDatabase db, {
    required Future<Map<String, Map<String, Object?>>> Function() seed,
  }) async {
    Map<String, Map<String, Object?>>? saved;
    try {
      final String? raw = await db.readValue(kDemoBenefitsKey);
      if (raw != null) {
        saved = <String, Map<String, Object?>>{
          for (final MapEntry<String, Object?> e
              in (jsonDecode(raw) as Map<String, Object?>).entries)
            if (e.value is Map)
              e.key: (e.value! as Map<Object?, Object?>)
                  .cast<String, Object?>(),
        };
      }
    } catch (_) {
      saved = null;
    }
    final DemoBenefitsStore store = DemoBenefitsStore._(
      saved ?? await seed(),
      (String value) => db.putValue(kDemoBenefitsKey, value),
    );
    if (saved == null) store._flush();
    return store;
  }

  /// [name] 구획의 저장분이 있으면 [book] 을 되살리고, 바뀔 때마다 그 구획을 쓴다.
  void attach(String name, DemoPersistable book) {
    final Map<String, Object?>? saved = _sections[name];
    if (saved != null) {
      try {
        book.restore(saved);
      } catch (_) {
        // 모양이 바뀐 옛 저장분 — 빈 장부로 시작한다. 다음 변경이 새 모양으로 덮는다.
      }
    }
    book.onChanged = () {
      _sections[name] = book.toJson();
      _flush();
    };
  }

  void _flush() {
    final Future<void> Function(String value)? write = _write;
    if (write == null) return;
    // 쓰기는 기다리지 않는다 — drift 가 요청 순서대로 처리하므로 마지막 쓰기가
    // 가장 새 상태다.
    final String value = jsonEncode(_sections);
    unawaited(() async {
      try {
        await write(value);
      } catch (_) {
        // 저장소가 없는 브라우저 — 이번 세션은 메모리로 이어 간다.
      }
    }());
  }
}

/// 장부 프로바이더가 함께 쓰는 저장소. 부팅이 [DemoBenefitsStore.open] 으로 덮는다.
final demoBenefitsStoreProvider = Provider<DemoBenefitsStore>(
  (ref) => DemoBenefitsStore.memory(),
  name: 'demoBenefitsStore',
);

/// 저장분의 날짜·시각 값 읽기.
DateTime demoParseTime(Object? raw) => DateTime.parse(raw! as String);

DateTime? demoParseTimeOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String);

/// 저장분의 목록 값 — 맵 줄만 추린다.
List<Map<String, Object?>> demoRows(Object? raw) => <Map<String, Object?>>[
  for (final Object? row in (raw as List<Object?>?) ?? const <Object?>[])
    if (row is Map) row.cast<String, Object?>(),
];
