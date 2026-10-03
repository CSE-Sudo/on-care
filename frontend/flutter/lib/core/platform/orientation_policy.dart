import 'dart:ui' show Display, FlutterView, PlatformDispatcher, Size;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// 휴대폰과 태블릿을 나누는 기준 — 화면 짧은 변이 이 값(논리 픽셀) 미만이면
/// 휴대폰으로 본다. 안드로이드 `sw600dp` 와 같은 경계다.
const double kPhoneShortestSideLimit = 600;

/// 회원 앱 화면 방향 정책(#3050).
///
/// 회원 앱 화면은 세로 기준으로 짜여 있다. 휴대폰을 눕히면 시트·지도·입력 칸이
/// 좁은 높이에 눌려 쓰기 어려워서 **휴대폰은 세로로 고정**한다. 태블릿은 화면
/// 폭을 휴대폰 폭으로 제한해 가운데 정렬하므로 가로에서도 쓸 수 있고, iPad
/// 멀티태스킹은 네 방향 지원을 요구하므로 **모든 방향을 그대로 둔다.** 웹은
/// 브라우저가 정한다.
///
/// 고정할 방향 목록을 돌려준다. `null` 이면 고정하지 않는다.
List<DeviceOrientation>? lockedOrientationsFor({
  required Size screenSize,
  required bool isWeb,
}) {
  if (isWeb) return null;
  // 크기를 아직 모르면 고정하지 않는다 — 태블릿을 세로로 묶는 쪽이 더 나쁘다.
  if (screenSize.isEmpty) return null;
  if (screenSize.shortestSide >= kPhoneShortestSideLimit) return null;
  return const <DeviceOrientation>[DeviceOrientation.portraitUp];
}

/// 기기 화면의 논리 크기. 창 크기(분할 화면에서 줄어든다)가 아니라 **화면**
/// 크기를 본다 — 태블릿을 분할 화면으로 열었다고 휴대폰으로 보면 안 된다.
/// 화면 정보가 없으면 첫 창 크기로 대신한다. 둘 다 없으면 [Size.zero].
Size currentScreenLogicalSize([PlatformDispatcher? dispatcher]) {
  final PlatformDispatcher platform = dispatcher ?? PlatformDispatcher.instance;
  final FlutterView? view =
      platform.implicitView ??
      (platform.views.isEmpty ? null : platform.views.first);
  if (view == null) return Size.zero;
  try {
    final Display display = view.display;
    if (display.devicePixelRatio > 0 && !display.size.isEmpty) {
      return display.size / display.devicePixelRatio;
    }
  } on Object {
    // 화면 정보를 주지 않는 플랫폼 — 창 크기로 대신한다.
  }
  if (view.devicePixelRatio <= 0) return Size.zero;
  return view.physicalSize / view.devicePixelRatio;
}

/// 휴대폰이면 세로로 고정한다. 앱 시작(`bootstrap`)에서 한 번 부른다.
///
/// 고정했으면 `true`. 실패해도 앱은 뜬다 — 방향 고정은 편의다.
Future<bool> applyPhoneOrientationLock({Size? screenSize, bool? isWeb}) async {
  final List<DeviceOrientation>? lock = lockedOrientationsFor(
    screenSize: screenSize ?? currentScreenLogicalSize(),
    isWeb: isWeb ?? kIsWeb,
  );
  if (lock == null) return false;
  try {
    await SystemChrome.setPreferredOrientations(lock);
    return true;
  } on Object {
    return false;
  }
}
