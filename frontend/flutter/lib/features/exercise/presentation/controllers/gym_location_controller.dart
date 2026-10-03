import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';

/// 검색과 지도가 공유하는 기준 좌표와 그 출처(#3044).
///
/// 회원 위치를 얻기 전에는 기본 검색 영역(신촌)이다. 화면은 이때 "신촌 주변
/// 결과" 안내를 두고 거리를 감춘다. 위치를 얻으면 앱이 켜져 있는 동안 그 좌표를
/// 유지한다 — 저장하지는 않는다.
final gymSearchAreaProvider = StateProvider<GymSearchArea>(
  (ref) => const GymSearchArea.defaultArea(),
);

final gymLocationServiceProvider = Provider((ref) => GymLocationService());

enum GymLocationFailure { denied, blocked, disabled, unavailable }

/// 권한 창을 띄우지 않고 본 위치 사용 가능 상태(#3044).
enum GymLocationAccess {
  /// 이미 허용됐다 — 조용히 위치를 얻어도 된다.
  granted,

  /// 아직 묻지 않았거나 이번에 거부했다 — 회원이 누르면 권한 창을 띄운다.
  undetermined,

  /// 영구 거부 — 권한 창이 뜨지 않으니 앱 설정으로 보낸다.
  blocked,

  /// 기기 위치 서비스가 꺼져 있다 — 위치 설정으로 보낸다.
  disabled,
}

class GymLocationService {
  /// 권한 창 없이 지금 상태만 본다. 확인하지 못하면 [GymLocationAccess.undetermined].
  Future<GymLocationAccess> checkAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return GymLocationAccess.disabled;
      }
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.whileInUse ||
        LocationPermission.always => GymLocationAccess.granted,
        LocationPermission.deniedForever => GymLocationAccess.blocked,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => GymLocationAccess.undetermined,
      };
    } on Object {
      return GymLocationAccess.undetermined;
    }
  }

  /// 이미 허용된 권한이라 권한 창 없이 위치를 얻어도 되는가.
  Future<bool> currentPermissionAllowsSilentLocate() async =>
      await checkAccess() == GymLocationAccess.granted;

  /// [access] 를 풀 수 있는 설정 화면을 연다 — 영구 거부면 앱 설정, 위치 서비스가
  /// 꺼져 있으면 위치 설정. 그 밖이면 아무것도 하지 않고 `false`.
  Future<bool> openSettingsFor(GymLocationAccess access) async {
    try {
      return switch (access) {
        GymLocationAccess.blocked => await Geolocator.openAppSettings(),
        GymLocationAccess.disabled => await Geolocator.openLocationSettings(),
        GymLocationAccess.granted || GymLocationAccess.undetermined => false,
      };
    } on Object {
      return false;
    }
  }

  /// 위치를 얻는다. 아직 묻지 않았으면 권한 창을 띄운다 — 회원이 [위치 사용]·현재
  /// 위치 버튼을 눌렀을 때만 부른다.
  Future<PlaceQuery> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw GymLocationFailure.disabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw GymLocationFailure.blocked;
    }
    if (permission == LocationPermission.denied) {
      throw GymLocationFailure.denied;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return PlaceQuery(
      lat: position.latitude,
      lng: position.longitude,
      category: PlaceCategory.fitness,
    );
  }
}
