import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym_search_area.dart';
import 'package:oncare/features/place/domain/entities/place.dart';
import 'package:oncare/features/place/domain/entities/place_query.dart';

/// 검색과 지도가 공유하는 좌표. 권한을 얻기 전에는 데모 초기 영역을 유지한다.
final gymSearchAreaProvider = StateProvider<PlaceQuery>(
  (ref) => const PlaceQuery(
    lat: kGymSearchLat,
    lng: kGymSearchLng,
    category: PlaceCategory.fitness,
  ),
);

final gymLocationServiceProvider = Provider((ref) => GymLocationService());

enum GymLocationFailure { denied, blocked, disabled, unavailable }

class GymLocationService {
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

/// 위치를 얻기 전에는 실제 거리로 오인할 숫자를 표시하지 않는다.
final gymHasLocationProvider = StateProvider<bool>((ref) => false);
final gymShowDistanceProvider = Provider<bool>(
  (ref) =>
      ref.watch(appConfigProvider).useMockApi ||
      ref.watch(gymHasLocationProvider),
);
