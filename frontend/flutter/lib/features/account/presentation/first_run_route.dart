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
/// 기록이 없을 때만 첫 설정으로 보낸다. 그 기록은 계정 경계에서 지워지므로
/// (#2630) 앞 계정의 기록이 새 계정의 판단에 섞이지 않는다.
///
/// **[WidgetRef] 가 아니라 [ProviderContainer] 를 받는다.** 로그인에 성공하면
/// 라우터의 세션 가드가 그 자리에서 로그인 화면을 대시보드로 갈아 치우므로,
/// 여기까지 오는 동안 부르는 쪽 위젯은 이미 사라져 있다. 위젯의 `ref` 로는
/// 그 뒤를 읽을 수 없다.
Future<String> firstRouteAfterSignIn(ProviderContainer ref) =>
    firstRunRoute(ref.read);

/// provider 하나를 읽는 함수 — [ProviderContainer.read] 와 [Ref.read] 가 둘 다
/// 이 모양이다. 로그인 화면(컨테이너)과 라우터 provider(`Ref`)가 같은 규칙을
/// 쓰도록 판단을 이 모양으로 받는다(#2630).
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// 첫 설정을 아직 안 한 계정이면 [AppRoutes.onboarding], 아니면
/// [AppRoutes.dashboard]. 판단 규칙은 [firstRouteAfterSignIn] 을 따른다.
Future<String> firstRunRoute(ProviderRead read) async {
  try {
    // 되짚지(`refresh`) 않는다 — 로그인이 끝나면서 세션 리셋이 이미 이 provider
    // 를 비웠다(`session_feature_reset`). 여기서 한 번 더 비우면 방금 대시보드가
    // 시작한 조회를 버리고 같은 요청을 다시 보낸다.
    final UserProfile profile = await read(profileProvider.future);
    if (profile.onboarded) {
      await _remember(read);
      return AppRoutes.dashboard;
    }
    return AppRoutes.onboarding;
  } on Object {
    return _seenOnThisDevice(read) ? AppRoutes.dashboard : AppRoutes.onboarding;
  }
}

/// 세션이 **복구**된 뒤 첫 설정이 남았으면 그리로 옮긴다. (#2630)
///
/// 로그인 경로는 로그인 화면이 [firstRouteAfterSignIn] 으로 맡는다. 앱을 다시
/// 켜서 저장된 세션으로 들어온 회원에게는 그 화면이 없어, 가입 직후 첫 설정
/// 폼에서 앱을 닫은 회원이 빈 프로필로 홈에 남았다.
///
/// 판단이 끝나기 전에 로그아웃·다른 계정 로그인이 있었다면 옮기지 않는다
/// ([stillSameSession] 이 거짓). 이미 홈에 있으므로 홈으로는 다시 옮기지 않는다 —
/// 탭 껍데기가 다시 세워지며 열려 있던 탭이 초기화된다.
Future<void> openFirstRunAfterRestore({
  required ProviderRead read,
  required void Function(String location) go,
  required bool Function() stillSameSession,
}) async {
  final String next = await firstRunRoute(read);
  if (next == AppRoutes.dashboard || !stillSameSession()) return;
  go(next);
}

bool _seenOnThisDevice(ProviderRead read) {
  try {
    return read(appPrefsProvider).onboardingDone;
  } on Object {
    // 설정 저장소가 없는 자리(일부 테스트)에서는 묻지 않는 쪽을 고른다.
    return true;
  }
}

/// 첫 설정을 끝냈다고 이 기기에 남긴다. 서버 값이 참이 되는 것과 별개로, 다음
/// 세션 복구에서 프로필을 못 받아 왔을 때의 보조 기록이다.
///
/// 이 기록은 **지금 저장된 세션의 계정 것**이다. 로그인·로그아웃·만료로 계정
/// 경계를 넘으면 세션 컨트롤러가 지운다(#2630) — 앞 계정의 기록을 보고 첫
/// 설정을 안 한 새 계정을 홈으로 보내지 않기 위해서다.
Future<void> rememberFirstRunDone(ProviderContainer ref) => _remember(ref.read);

Future<void> _remember(ProviderRead read) async {
  try {
    await read(appPrefsProvider).setOnboardingDone(true);
  } on Object {
    // 기록에 실패해도 서버 값이 참이라 다음에도 같은 판단이 나온다.
  }
}
