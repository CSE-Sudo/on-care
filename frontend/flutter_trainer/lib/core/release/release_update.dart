import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/release/release_probe.dart';

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

  /// 페이지를 다시 읽는다.
  void reload();
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
    return const ReleaseUpdateState();
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
  void reload() => ref.read(releaseProbeProvider)?.reload();
}

/// 새 버전 안내 상태 provider.
final NotifierProvider<ReleaseUpdateController, ReleaseUpdateState>
releaseUpdateProvider =
    NotifierProvider<ReleaseUpdateController, ReleaseUpdateState>(
      ReleaseUpdateController.new,
      name: 'releaseUpdate',
    );
