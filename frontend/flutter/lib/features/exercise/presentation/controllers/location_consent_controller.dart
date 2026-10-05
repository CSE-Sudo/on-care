import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/exercise/data/repositories/location_consent_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';

/// 데모 세션은 기기에, 실사용자는 서버에 남긴다(#3136).
///
/// 데모 판별은 헬스장 찾기와 같은 [gymDemoSessionProvider] 다 — 목업 빌드와
/// 실서버 데모 세션 모두 기기에만 둔다. 실서버 데모 회원은 여럿이 함께 쓰는
/// 계정이라 서버에 남기면 한 사람의 동의가 다음 사람에게 이어진다.
final locationConsentRepositoryProvider = Provider<LocationConsentRepository>((
  ref,
) {
  if (ref.watch(gymDemoSessionProvider)) {
    return LocalLocationConsentRepository(ref.watch(sharedPreferencesProvider));
  }
  return DioLocationConsentRepository(ref.watch(dioProvider));
}, name: 'locationConsentRepository');

/// 위치정보 이용 동의 상태(#3136). `true` 면 지금 문서 버전에 동의해 있다.
///
/// 읽지 못하면 동의가 없는 것으로 본다 — 모르는 상태에서 OS 권한을 묻거나
/// 좌표를 읽지 않는다. 헬스장 찾기는 기본 검색 영역으로 그대로 쓸 수 있다.
class LocationConsentController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      return await ref.watch(locationConsentRepositoryProvider).fetch();
    } on Object {
      return false;
    }
  }

  /// 동의를 남긴다. 저장에 실패하면 상태를 그대로 두고 `false` — 화면은 이때
  /// 권한 창으로 넘어가지 않는다.
  Future<bool> agree() async {
    try {
      await ref.read(locationConsentRepositoryProvider).agree();
    } on Object {
      return false;
    }
    state = const AsyncData<bool>(true);
    return true;
  }

  /// 동의를 철회한다. 저장에 실패하면 상태를 그대로 두고 `false`.
  ///
  /// 철회하면 앱이 들고 있던 회원 위치도 버리고 기본 검색 영역으로 돌아간다 —
  /// 철회한 뒤에도 그 좌표로 주변 검색을 계속하면 안 된다. 이번 실행에서 동의
  /// 시트를 다시 저절로 띄우지도 않는다(회원이 방금 거둔 것이다).
  Future<bool> revoke() async {
    try {
      await ref.read(locationConsentRepositoryProvider).revoke();
    } on Object {
      return false;
    }
    state = const AsyncData<bool>(false);
    ref.read(locationConsentPromptedProvider.notifier).state = true;
    if (ref.read(gymSearchAreaProvider).origin ==
        GymSearchOrigin.userLocation) {
      ref.invalidate(gymSearchAreaProvider);
    }
    return true;
  }
}

/// 현재 동의 상태. 계정이 바뀌면 세션 초기화가 무효화한다.
final locationConsentProvider =
    AsyncNotifierProvider<LocationConsentController, bool>(
      LocationConsentController.new,
      name: 'locationConsent',
    );

/// 이번 앱 실행에서 동의 시트를 저절로 띄운 적이 있는가(#3136).
///
/// 헬스장 찾기를 처음 열 때 한 번만 저절로 묻는다. 거부한 뒤에는 탭을 오갈
/// 때마다 다시 띄우지 않고, 회원이 [위치 사용]·현재 위치 버튼을 누르면 다시
/// 묻는다. 저장하지 않으므로 앱을 다시 켜면 다시 한 번 묻는다.
final locationConsentPromptedProvider = StateProvider<bool>(
  (ref) => false,
  name: 'locationConsentPrompted',
);
