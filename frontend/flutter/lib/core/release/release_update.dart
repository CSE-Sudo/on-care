import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/release/release_probe.dart';

/// 이 번들이 빌드된 릴리스의 커밋 SHA(#3023).
///
/// 배포 워크플로가 `--dart-define=RELEASE_SHA=...` 로 넣는다. 로컬 실행·테스트
/// 빌드에는 없어 빈 값이고, 그러면 새 버전 확인이 꺼진다.
const String kReleaseSha = String.fromEnvironment('RELEASE_SHA');

/// 탭이 계속 보이는 동안 새 배포를 확인하는 간격. 탭이 다시 보일 때는 바로 본다.
const Duration kReleaseCheckInterval = Duration(minutes: 10);

final RegExp _shaPattern = RegExp(r'^[0-9a-f]{7,40}$');

/// `version.txt` 내용·define 값을 비교할 수 있는 SHA 로 다듬는다.
///
/// 앞뒤 공백·개행을 떼고 소문자로 맞춘다. SHA 모양이 아니면(빈 파일, 오류 페이지
/// HTML 등) `null` — 그런 응답으로 배너를 띄우지 않는다.
String? normalizeReleaseSha(String? raw) {
  if (raw == null) return null;
  final String value = raw.trim().toLowerCase();
  return _shaPattern.hasMatch(value) ? value : null;
}

/// 배포된 [latest] 가 지금 떠 있는 [current] 와 다른 릴리스인가.
///
/// 둘 중 하나라도 SHA 가 아니면 판단하지 않는다(`false`).
bool isNewerRelease({required String current, required String? latest}) {
  final String? a = normalizeReleaseSha(current);
  final String? b = normalizeReleaseSha(latest);
  return a != null && b != null && a != b;
}

/// 새 버전 확인에 필요한 브라우저 기능 — 웹에서만 있다.
///
/// 웹이 아닌 빌드(테스트 포함)는 [createReleaseProbe] 가 `null` 을 돌려 확인 자체가
/// 꺼진다. 테스트는 가짜를 [releaseProbeProvider] 로 넣는다.
abstract interface class ReleaseProbe {
  /// 지금 배포된 릴리스의 `version.txt` 내용. 읽지 못하면 `null`.
  Future<String?> fetchLatest();

  /// 탭이 다시 보일 때마다 한 번씩 알린다.
  Stream<void> get onVisible;

  /// 새 번들을 받도록 페이지를 다시 읽는다(#3204).
  ///
  /// 보통의 새로고침은 이름이 고정된 진입 파일(`main.dart.js` 등)을 HTTP 캐시에서
  /// 그대로 다시 쓸 수 있다. 그래서 진입 파일을 먼저 서버에서 새로 받아 캐시를 갈아
  /// 끼운 뒤 다시 읽는다. 미리 받기가 실패해도 새로고침은 한다.
  Future<void> reload();

  /// 이 탭이 새로고침으로 받으러 간 배포 SHA. 기록이 없거나 읽지 못하면 `null`.
  ///
  /// 탭 단위 저장소(sessionStorage)에 있어 새로고침 뒤에도 남는다 — 새로 뜬 번들이
  /// 정말 그 배포인지 보고, 아니면 같은 안내를 되풀이하지 않는 데 쓴다.
  String? readReloadedSha();

  /// [readReloadedSha] 기록을 남긴다. `null` 이면 지운다. 저장소를 못 쓰면 넘긴다.
  void writeReloadedSha(String? sha);
}

/// 새 버전 안내 상태.
class ReleaseUpdateState {
  /// 기본값은 "안내 없음".
  const ReleaseUpdateState({this.latestSha, this.dismissedSha});

  /// 확인한 배포 SHA 중 지금 번들과 다른 마지막 값.
  final String? latestSha;

  /// 사용자가 닫은 배포 SHA. 같은 배포에 대해서는 이 탭에서 다시 띄우지 않는다.
  final String? dismissedSha;

  /// 배너를 띄울지.
  bool get showBanner => latestSha != null && latestSha != dismissedSha;

  ReleaseUpdateState copyWith({String? latestSha, String? dismissedSha}) =>
      ReleaseUpdateState(
        latestSha: latestSha ?? this.latestSha,
        dismissedSha: dismissedSha ?? this.dismissedSha,
      );
}

/// 이 번들의 릴리스 SHA. 테스트가 바꿔 넣는다.
final Provider<String> releaseShaProvider = Provider<String>(
  (ref) => kReleaseSha,
  name: 'releaseSha',
);

/// 브라우저 기능. 웹이 아니면 `null`.
final Provider<ReleaseProbe?> releaseProbeProvider = Provider<ReleaseProbe?>(
  (ref) => createReleaseProbe(),
  name: 'releaseProbe',
);

/// 주기 확인 신호 — [kReleaseCheckInterval] 마다 한 번. 듣는 동안만 타이머가 돈다.
/// 테스트는 손으로 쏘는 스트림을 넣는다.
final Provider<Stream<void>> releaseCheckTicksProvider = Provider<Stream<void>>(
  (ref) => Stream<void>.periodic(kReleaseCheckInterval),
  name: 'releaseCheckTicks',
);

/// 새 버전 안내 컨트롤러(#3023).
///
/// 시작 직후 한 번, 탭이 다시 보일 때, 그리고 [kReleaseCheckInterval] 마다
/// `version.txt` 를 읽어 내장 SHA 와 비교한다. 읽기 실패·이상한 응답은 조용히
/// 넘긴다 — 네트워크가 잠깐 끊겼다고 배너를 띄우지 않는다. 자동 새로고침은 하지
/// 않는다(작성 중인 폼을 잃지 않게).
///
/// 새로고침을 누르면 배너를 바로 내리고, 어느 배포를 받으러 갔는지 탭에 남긴다
/// (#3204). 다시 뜬 번들이 그 배포면 기록을 지우고, 여전히 옛 번들이면 같은 배포는
/// 이 탭에서 다시 안내하지 않는다 — 새로고침해도 바뀌지 않는 안내가 끝없이 되풀이되지
/// 않게. 더 새 배포가 오면 다시 안내한다.
class ReleaseUpdateController extends Notifier<ReleaseUpdateState> {
  bool _checking = false;

  @override
  ReleaseUpdateState build() {
    final String current = ref.watch(releaseShaProvider);
    final ReleaseProbe? probe = ref.watch(releaseProbeProvider);
    if (probe == null || normalizeReleaseSha(current) == null) {
      return const ReleaseUpdateState();
    }
    final StreamSubscription<void> ticks = ref
        .watch(releaseCheckTicksProvider)
        .listen((_) => unawaited(check()));
    final StreamSubscription<void> visible = probe.onVisible.listen(
      (_) => unawaited(check()),
    );
    ref.onDispose(() {
      unawaited(ticks.cancel());
      unawaited(visible.cancel());
    });
    Future<void>.microtask(check);
    return ReleaseUpdateState(
      dismissedSha: _settleReload(probe, normalizeReleaseSha(current)!),
    );
  }

  /// 직전 새로고침의 결과를 정리하고, 다시 안내하지 않을 배포 SHA 를 돌려준다.
  ///
  /// 받으러 간 배포가 지금 번들이면 새로고침이 통한 것이라 기록을 지운다(`null`).
  /// 다르면 새로고침해도 옛 번들이 뜬 것이다(브라우저·중간 캐시가 아직 옛 파일을
  /// 내준다). 그 배포는 이 탭에서 닫은 것으로 친다.
  String? _settleReload(ReleaseProbe probe, String current) {
    final String? reloaded = normalizeReleaseSha(_readReloadedSha(probe));
    if (reloaded == null) return null;
    if (reloaded == current) {
      _writeReloadedSha(probe, null);
      return null;
    }
    return reloaded;
  }

  /// 지금 배포된 릴리스를 한 번 확인한다. 이미 확인 중이면 건너뛴다.
  Future<void> check() async {
    final ReleaseProbe? probe = ref.read(releaseProbeProvider);
    if (probe == null || _checking) return;
    _checking = true;
    try {
      final String? latest = await probe.fetchLatest();
      final String current = ref.read(releaseShaProvider);
      if (isNewerRelease(current: current, latest: latest)) {
        state = state.copyWith(latestSha: normalizeReleaseSha(latest));
      }
    } on Object {
      // 확인 실패는 안내하지 않는다 — 다음 확인에서 다시 본다.
    } finally {
      _checking = false;
    }
  }

  /// 지금 안내한 배포를 닫는다. 더 새 배포가 오면 다시 뜬다.
  void dismiss() {
    final String? latest = state.latestSha;
    if (latest == null) return;
    state = state.copyWith(dismissedSha: latest);
  }

  /// 새 버전을 받으러 페이지를 다시 읽는다.
  ///
  /// 누르는 즉시 배너를 내리고(같은 배포를 닫은 것으로 친다) 받으러 간 배포를 탭에
  /// 남긴 뒤 브라우저에 맡긴다. 작성 중 확인창(#2264)에서 취소해 페이지가 남아도
  /// 배너는 내려간 채이고, 더 새 배포가 오면 다시 뜬다.
  Future<void> reload() async {
    final ReleaseProbe? probe = ref.read(releaseProbeProvider);
    if (probe == null) return;
    final String? latest = state.latestSha;
    if (latest != null) {
      state = state.copyWith(dismissedSha: latest);
      _writeReloadedSha(probe, latest);
    }
    try {
      await probe.reload();
    } on Object {
      // 새로고침 실패는 안내하지 않는다 — 사용자가 직접 새로고침할 수 있다.
    }
  }
}

/// 저장소를 읽지 못하면(사생활 보호 모드 제한 등) 기록이 없는 것으로 친다.
String? _readReloadedSha(ReleaseProbe probe) {
  try {
    return probe.readReloadedSha();
  } on Object {
    return null;
  }
}

/// 저장소에 쓰지 못해도 안내·새로고침은 그대로 한다.
void _writeReloadedSha(ReleaseProbe probe, String? sha) {
  try {
    probe.writeReloadedSha(sha);
  } on Object {
    // 기록 없이 넘어간다 — 새로고침 뒤 옛 번들이면 안내가 한 번 더 뜰 뿐이다.
  }
}

/// 새 버전 안내 상태 provider.
final NotifierProvider<ReleaseUpdateController, ReleaseUpdateState>
releaseUpdateProvider =
    NotifierProvider<ReleaseUpdateController, ReleaseUpdateState>(
      ReleaseUpdateController.new,
      name: 'releaseUpdate',
    );
