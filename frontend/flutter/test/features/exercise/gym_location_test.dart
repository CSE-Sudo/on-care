import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:oncare/features/exercise/presentation/controllers/gym_location_controller.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requested = LocationPermission.whileInUse;
  int requests = 0;
  int reads = 0;
  int appSettings = 0;
  int locationSettings = 0;
  bool throwOnCheck = false;

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async {
    if (throwOnCheck) throw StateError('no plugin');
    return permission;
  }

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

  group('권한 창 없이 보는 상태 (#3044)', () {
    Future<GymLocationAccess> access() => GymLocationService().checkAccess();

    test('이미 허용했으면 granted — 조용히 위치를 얻어도 된다', () async {
      for (final LocationPermission p in <LocationPermission>[
        LocationPermission.whileInUse,
        LocationPermission.always,
      ]) {
        platform.permission = p;
        expect(await access(), GymLocationAccess.granted, reason: '$p');
        expect(
          await GymLocationService().currentPermissionAllowsSilentLocate(),
          isTrue,
        );
      }
      expect(platform.requests, 0, reason: '권한 창을 띄우면 안 된다');
      expect(platform.reads, 0, reason: '보기만 하고 위치는 읽지 않는다');
    });

    test('아직 묻지 않았으면 undetermined — 권한 창을 띄우지 않는다', () async {
      platform.permission = LocationPermission.denied;
      expect(await access(), GymLocationAccess.undetermined);
      expect(
        await GymLocationService().currentPermissionAllowsSilentLocate(),
        isFalse,
      );
      platform.permission = LocationPermission.unableToDetermine;
      expect(await access(), GymLocationAccess.undetermined);
      expect(platform.requests, 0);
    });

    test('영구 거부면 blocked', () async {
      platform.permission = LocationPermission.deniedForever;
      expect(await access(), GymLocationAccess.blocked);
      expect(
        await GymLocationService().currentPermissionAllowsSilentLocate(),
        isFalse,
      );
    });

    test('위치 서비스가 꺼져 있으면 권한과 무관하게 disabled', () async {
      platform
        ..enabled = false
        ..permission = LocationPermission.whileInUse;
      expect(await access(), GymLocationAccess.disabled);
      expect(
        await GymLocationService().currentPermissionAllowsSilentLocate(),
        isFalse,
      );
    });

    test('확인이 실패하면 undetermined — 화면이 깨지지 않는다', () async {
      platform.throwOnCheck = true;
      expect(await access(), GymLocationAccess.undetermined);
    });
  });

  group('설정 화면 열기 (#3044)', () {
    test('영구 거부는 앱 설정, 꺼진 위치 서비스는 위치 설정', () async {
      final GymLocationService service = GymLocationService();
      expect(await service.openSettingsFor(GymLocationAccess.blocked), isTrue);
      expect(platform.appSettings, 1);
      expect(await service.openSettingsFor(GymLocationAccess.disabled), isTrue);
      expect(platform.locationSettings, 1);
    });

    test('그 밖에는 아무것도 열지 않는다', () async {
      final GymLocationService service = GymLocationService();
      expect(await service.openSettingsFor(GymLocationAccess.granted), isFalse);
      expect(
        await service.openSettingsFor(GymLocationAccess.undetermined),
        isFalse,
      );
      expect(platform.appSettings + platform.locationSettings, 0);
    });
  });
}
