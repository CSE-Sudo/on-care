import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/app_version/app_version.dart';
import 'package:oncare/core/app_version/semver.dart';
import 'package:oncare/core/network/dio_client.dart';

/// 최소 지원 버전 확인 결과(#3045).
enum AppVersionStatus {
  /// 아직 확인하지 못했다(확인 전·실패·꺼짐). 평소처럼 진행한다.
  unknown,

  /// 이 빌드는 지원된다(또는 서버가 최소 버전을 두지 않았다).
  supported,

  /// 서버의 최소 지원 버전보다 낮다 — 업데이트 화면만 보인다.
  updateRequired,
}

/// 최소 지원 버전 확인 상태.
@immutable
class AppVersionGateState {
  const AppVersionGateState({
    this.status = AppVersionStatus.unknown,
    this.currentVersion,
    this.minVersion,
  });

  final AppVersionStatus status;

  /// 이 빌드의 버전 이름. 읽지 못했으면 `null`.
  final String? currentVersion;

  /// 서버가 알려 준 최소 지원 버전. 없으면 `null`.
  final String? minVersion;

  bool get updateRequired => status == AppVersionStatus.updateRequired;

  @override
  bool operator ==(Object other) =>
      other is AppVersionGateState &&
      other.status == status &&
      other.currentVersion == currentVersion &&
      other.minVersion == minVersion;

  @override
  int get hashCode => Object.hash(status, currentVersion, minVersion);

  @override
  String toString() =>
      'AppVersionGateState($status, current: $currentVersion, '
      'min: $minVersion)';
}

/// `/version` 한 번이 이 시간 안에 오지 않으면 확인을 접고 평소처럼 진행한다.
const Duration kAppVersionCheckTimeout = Duration(seconds: 3);

/// [current] 빌드가 서버의 최소 지원 버전 [minRaw](`/version` 의
/// `min_app_version` 값 그대로)를 만족하는가.
///
/// 판단할 수 없으면 `unknown` 이다 — 버전 확인 탓에 앱이 켜지지 않는 쪽이
/// 더 나쁘다(fail-open).
AppVersionGateState evaluateAppVersion({
  required String? current,
  required Object? minRaw,
}) {
  if (minRaw == null || (minRaw is String && minRaw.trim().isEmpty)) {
    // 서버가 최소 버전을 두지 않았다 — 검사하지 않는다.
    return AppVersionGateState(
      status: AppVersionStatus.supported,
      currentVersion: current,
    );
  }
  if (minRaw is! String) {
    return AppVersionGateState(currentVersion: current);
  }
  final AppSemver? min = AppSemver.tryParse(minRaw);
  final AppSemver? mine = AppSemver.tryParse(current);
  if (min == null || mine == null) {
    return AppVersionGateState(currentVersion: current, minVersion: minRaw);
  }
  return AppVersionGateState(
    status: mine < min
        ? AppVersionStatus.updateRequired
        : AppVersionStatus.supported,
    currentVersion: current,
    minVersion: min.toString(),
  );
}

/// 최소 지원 버전을 확인한다(#3045).
///
/// 앱이 뜰 때 한 번, 백그라운드에서 돌아올 때마다 한 번 더 확인한다(오래 켜 둔
/// 앱 대비). 확인이 실패하면 상태를 바꾸지 않는다 — 처음이면 `unknown` 이라
/// 평소처럼 진행하고, 이미 업데이트가 필요하다고 알았다면 그대로 막는다.
class AppVersionGate extends StateNotifier<AppVersionGateState> {
  AppVersionGate({
    required this.enabled,
    required Future<String?> Function() readCurrentVersion,
    required Future<Map<String, Object?>?> Function() fetchVersionInfo,
    this.timeout = kAppVersionCheckTimeout,
  }) : _readCurrentVersion = readCurrentVersion,
       _fetchVersionInfo = fetchVersionInfo,
       super(const AppVersionGateState());

  /// 꺼져 있으면 아무것도 묻지 않는다(웹·테스트).
  final bool enabled;
  final Duration timeout;
  final Future<String?> Function() _readCurrentVersion;
  final Future<Map<String, Object?>?> Function() _fetchVersionInfo;

  Future<void>? _inFlight;

  /// 서버에 최소 지원 버전을 묻는다. 이미 묻는 중이면 그 결과를 함께 기다린다.
  Future<void> check() {
    if (!enabled) return Future<void>.value();
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  Future<void> _check() async {
    final String? current;
    final Map<String, Object?>? info;
    try {
      current = await _readCurrentVersion();
      info = await _fetchVersionInfo().timeout(timeout);
    } on Object {
      // 연결 실패·시간 초과·응답 형식 이상 — 지금 상태로 둔다.
      return;
    }
    if (!mounted || info == null) return;
    state = evaluateAppVersion(
      current: current,
      minRaw: info['min_app_version'],
    );
  }
}

/// 이 빌드에서 최소 지원 버전을 확인할지. 웹은 하지 않는다.
bool appVersionCheckEnabledFor({required bool isWeb}) => !isWeb;

/// 최소 지원 버전 확인을 켤지. 기본은 꺼짐 — 앱 진입점(`bootstrap`)이 모바일
/// 빌드에서만 켠다. 웹은 배포하면 곧 새 빌드를 받으므로 검사하지 않는다.
final appVersionCheckEnabledProvider = Provider<bool>(
  (ref) => false,
  name: 'appVersionCheckEnabled',
);

/// 앱 전체가 보는 최소 지원 버전 상태. 라우터 가드가 읽는다.
final appVersionGateProvider =
    StateNotifierProvider<AppVersionGate, AppVersionGateState>((ref) {
      final bool enabled = ref.watch(appVersionCheckEnabledProvider);
      final AppVersionGate gate = AppVersionGate(
        enabled: enabled,
        readCurrentVersion: () => ref.read(appVersionProvider.future),
        fetchVersionInfo: () async {
          final Response<Map<String, Object?>> res = await ref
              .read(dioProvider)
              .get<Map<String, Object?>>('/version');
          return res.data;
        },
      );
      if (enabled) {
        final AppLifecycleListener lifecycle = AppLifecycleListener(
          onResume: () => unawaited(gate.check()),
        );
        ref.onDispose(lifecycle.dispose);
        unawaited(gate.check());
      }
      return gate;
    }, name: 'appVersionGate');
