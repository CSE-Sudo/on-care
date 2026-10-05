import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/release/release_update.dart';

/// 브라우저 대신 쓰는 새 버전 확인 기능(#3023).
///
/// [latest] 가 다음 `version.txt` 응답이고, [error] 를 주면 읽기가 실패한다.
/// [hold] 를 켜면 [release] 를 부를 때까지 응답을 붙잡는다(동시 확인 검사용).
///
/// [reloadedSha] 는 탭 저장소(sessionStorage) 대역이다(#3204). [storageError] 를 주면
/// 읽기·쓰기가 실패하고, [reloadError] 를 주면 새로고침이 실패한다.
class FakeReleaseProbe implements ReleaseProbe {
  FakeReleaseProbe({this.latest, this.reloadedSha});

  String? latest;
  Object? error;
  bool hold = false;
  int fetchCount = 0;
  int reloadCount = 0;

  /// 탭 저장소에 남은 "받으러 간 배포" 기록.
  String? reloadedSha;

  /// 새로고침을 부른 순간의 기록 — 기록이 새로고침보다 먼저 남는지 본다.
  final List<String?> reloadedShaAtReload = <String?>[];

  Object? storageError;
  Object? reloadError;

  final StreamController<void> visible = StreamController<void>.broadcast();
  final List<Completer<void>> _held = <Completer<void>>[];

  @override
  Future<String?> fetchLatest() async {
    fetchCount++;
    if (hold) {
      final Completer<void> gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    final Object? failure = error;
    if (failure != null) throw failure;
    return latest;
  }

  /// 붙잡아 둔 응답을 모두 내보낸다.
  void release() {
    for (final Completer<void> gate in _held) {
      gate.complete();
    }
    _held.clear();
  }

  @override
  Stream<void> get onVisible => visible.stream;

  @override
  Future<void> reload() async {
    reloadCount++;
    reloadedShaAtReload.add(reloadedSha);
    final Object? failure = reloadError;
    if (failure != null) throw failure;
  }

  @override
  String? readReloadedSha() {
    final Object? failure = storageError;
    if (failure != null) throw failure;
    return reloadedSha;
  }

  @override
  void writeReloadedSha(String? sha) {
    final Object? failure = storageError;
    if (failure != null) throw failure;
    reloadedSha = sha;
  }

  /// 탭 복귀 신호를 닫는다. 테스트 정리 단계에서 부른다.
  Future<void> close() => visible.close();
}

/// 지금 번들 SHA.
const String kCurrentSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// 새로 배포된 SHA.
const String kNextSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// 그다음 배포 SHA.
const String kLaterSha = 'cccccccccccccccccccccccccccccccccccccccc';

/// 새 버전 확인을 켜는 override 묶음 — [probe] 와 내장 [sha], 손으로 쏘는 [ticks].
List<Override> releaseOverrides(
  FakeReleaseProbe probe, {
  String sha = kCurrentSha,
  Stream<void>? ticks,
}) => <Override>[
  releaseShaProvider.overrideWithValue(sha),
  releaseProbeProvider.overrideWithValue(probe),
  releaseCheckTicksProvider.overrideWithValue(
    ticks ?? const Stream<void>.empty(),
  ),
];
