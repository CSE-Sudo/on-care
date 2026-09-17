import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';

/// 로그인 직후 갈 곳 — 첫 설정을 아직 안 했으면 그 화면이다. (#1927)
///
/// 예전에는 `/onboarding` 으로 가는 길이 **가입 직후 한 줄뿐**이었다. 그래서
/// 도중에 앱을 닫거나 기기를 바꾼 회원은 생년월일·키·체중·건강 목표가 빈 채로
/// 남고, 그 값을 쓰는 화면들이 계속 빈칸이었다 — 다시 들어갈 길도 없었다.
///
/// 판단은 **계정에 붙은 값**([UserProfile.onboarded])으로 한다. 기기 설정이
/// 아니라 서버가 들고 있어야 기기를 바꿔도 한 번만 묻는다.
///
/// 프로필을 못 받아 왔을 때는 기기에 남은 기록([AppPrefs.onboardingDone])을 본다.
/// 이미 끝낸 회원을 망이 나빴다는 이유로 다시 폼에 세우지 않기 위해서다 — 그
/// 기록이 없을 때만 첫 설정으로 보낸다.
///
/// **[WidgetRef] 가 아니라 [ProviderContainer] 를 받는다.** 로그인에 성공하면
/// 라우터의 세션 가드가 그 자리에서 로그인 화면을 대시보드로 갈아 치우므로,
/// 여기까지 오는 동안 부르는 쪽 위젯은 이미 사라져 있다. 위젯의 `ref` 로는
/// 그 뒤를 읽을 수 없다.
Future<String> firstRouteAfterSignIn(ProviderContainer ref) async {
  try {
    final UserProfile profile = await ref.refresh(profileProvider.future);
    if (profile.onboarded) {
      await rememberFirstRunDone(ref);
      return AppRoutes.dashboard;
    }
    return AppRoutes.onboarding;
  } on Object {
    return _seenOnThisDevice(ref) ? AppRoutes.dashboard : AppRoutes.onboarding;
  }
}

bool _seenOnThisDevice(ProviderContainer ref) {
  try {
    return ref.read(appPrefsProvider).onboardingDone;
  } on Object {
    // 설정 저장소가 없는 자리(일부 테스트)에서는 묻지 않는 쪽을 고른다.
    return true;
  }
}

/// 첫 설정을 끝냈다고 이 기기에 남긴다. 서버 값이 참이 되는 것과 별개로, 다음
/// 로그인에서 프로필을 못 받아 왔을 때의 보조 기록이다.
Future<void> rememberFirstRunDone(ProviderContainer ref) async {
  try {
    await ref.read(appPrefsProvider).setOnboardingDone(true);
  } on Object {
    // 기록에 실패해도 서버 값이 참이라 다음에도 같은 판단이 나온다.
  }
}
