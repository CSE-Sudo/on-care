import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// 소속 헬스장 찾기의 "현재 위치로 찾기"가 얻은 좌표(#3223).
///
/// 이 화면에서 주변 헬스장을 한 번 찾는 데만 쓴다. 서버·로컬 저장소 어디에도
/// 남기지 않는다 — 회원 앱 헬스장 찾기(`GymLocationService`)와 같은 규칙이다.
class TrainerPosition {
  const TrainerPosition({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

/// 위치를 얻지 못한 까닭. 화면은 까닭마다 다른 안내를 보인다.
enum TrainerLocationFailure {
  /// 이번 권한 창에서 거부했다 — 다시 누르면 다시 묻는다.
  denied,

  /// 브라우저 사이트 설정에서 막혀 있다 — 권한 창이 뜨지 않는다.
  blocked,

  /// 기기·브라우저의 위치 서비스를 쓸 수 없다.
  disabled,

  /// 시간 초과·알 수 없는 오류.
  unavailable,
}

final trainerLocationServiceProvider = Provider<TrainerLocationService>(
  (ref) => const TrainerLocationService(),
  name: 'trainerLocationService',
);

/// 브라우저 위치(Geolocation API)로 현재 좌표를 얻는다(#3223).
///
/// 회원 앱과 같은 geolocator 를 쓴다 — 웹에서는 브라우저의 위치 권한 창이 뜬다.
/// 트레이너가 버튼을 눌렀을 때만 부르고, 들어오자마자 조용히 위치를 읽지 않는다.
/// 실패는 [TrainerLocationFailure] 로 던진다.
class TrainerLocationService {
  const TrainerLocationService();

  Future<TrainerPosition> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw TrainerLocationFailure.disabled;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw TrainerLocationFailure.blocked;
      }
      if (permission == LocationPermission.denied) {
        throw TrainerLocationFailure.denied;
      }
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return TrainerPosition(lat: position.latitude, lng: position.longitude);
    } on TrainerLocationFailure {
      rethrow;
    } on PermissionDeniedException {
      // 웹은 권한 창에서 거부하면 checkPermission 단계가 아니라 위치 요청에서
      // 이 예외로 끝난다.
      throw TrainerLocationFailure.denied;
    } on LocationServiceDisabledException {
      throw TrainerLocationFailure.disabled;
    } on Object {
      throw TrainerLocationFailure.unavailable;
    }
  }
}
