import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requested = LocationPermission.whileInUse;
  int requests = 0;
  int reads = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requested;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads++;
    return Position(
      latitude: 35.1,
      longitude: 129.1,
      timestamp: DateTime(2026),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  late GeolocatorPlatform original;
  late _LocationPlatform platform;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  test('허용하면 실제 좌표로 검색 영역을 만든다', () async {
    final area = await GymLocationService().locate();
    expect(area.lat, 35.1);
    expect(area.lng, 129.1);
    expect(platform.requests, 1);
  });
  test('이미 허용했으면 다시 권한을 요청하지 않는다', () async {
    platform.permission = LocationPermission.whileInUse;
    await GymLocationService().locate();
    expect(platform.requests, 0);
    expect(platform.reads, 1);
  });
  test('거부하면 위치를 읽지 않는다', () async {
    platform.requested = LocationPermission.denied;
    await expectLater(
      GymLocationService().locate(),
      throwsA(GymLocationFailure.denied),
    );
    expect(platform.reads, 0);
  });
  test('영구 차단이면 재요청하지 않는다', () async {
    platform.permission = LocationPermission.deniedForever;
    await expectLater(
      GymLocationService().locate(),
      throwsA(GymLocationFailure.blocked),
    );
    expect(platform.requests, 0);
    expect(platform.reads, 0);
  });
  test('위치 서비스가 꺼져 있으면 권한을 요청하지 않는다', () async {
    platform.enabled = false;
    await expectLater(
      GymLocationService().locate(),
      throwsA(GymLocationFailure.disabled),
    );
    expect(platform.requests, 0);
  });
}
