/// 세션 전환에서 계정 데이터가 새지 않는지 — #634.
///
/// 두 provider 의 사정이 다르다.
///
///  * **알림 수신 설정** — 실제로 새고 있었다. 이 잎이 읽는 저장소가 레지스트리에 없어
///    전이 무효화도 일어나지 않아, 앞 계정의 토글이 그대로 남았다.
///  * **예약 내역** — 이미 리셋되고 있었다. 헬스장 저장소를 watch 하고 그 뿌리가
///    레지스트리에 있어 함께 다시 조회된다. 여기서는 그 성질을 **고정**한다 — 잎을
///    명시적으로 등록한 뒤에도, 앞으로 뿌리 쪽 구조가 바뀌어도 계속 지켜지도록.
///
/// 저장소 인스턴스를 비교하지 않고 **다시 조회하는지**로 확인한다. 두 provider 모두
/// 상태를 들지 않는 저장소를 읽으므로, 인스턴스가 같은지로는 리셋 여부를 알 수 없다.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

/// 조회 횟수를 세고, 계정이 바뀌면 다른 예약을 돌려주는 대역.
///
/// 기존 목업을 상속해 예약 조회만 덮는다 — 계약 전체를 손으로 구현하면 저장소에
/// 메서드가 늘 때마다 이 테스트가 관련 없는 이유로 깨진다.
class _CountingGymRepository extends MockGymRepository {
  int fetchReservationsCalls = 0;

  /// 지금 로그인한 계정 — 테스트가 전환 시점에 바꾼다.
  String accountId = 'account-a';

  @override
  Future<List<MyReservation>> fetchMyReservations({
    int limit = reservationPageSize,
    DateTime? before,
    String? beforeId,
  }) async {
    fetchReservationsCalls++;
    return <MyReservation>[
      MyReservation(
        id: '$accountId-reservation',
        slotId: 'slot-1',
        trainerId: 'trainer-1',
        startsAt: DateTime(2026, 8, 20, 10),
        cancellable: true,
      ),
    ];
  }
}

/// 조회 횟수를 세고, 계정이 바뀌면 다른 설정을 돌려주는 대역.
class _CountingSettingsRepository implements NotificationSettingsRepository {
  int fetchCalls = 0;
  String accountId = 'account-a';

  @override
  Future<Map<String, bool>> fetch() async {
    fetchCalls++;
    return <String, bool>{
      for (final NotificationSettingItem item in kNotificationSettingItems)
        item.key: accountId == 'account-a',
    };
  }

  @override
  Future<void> setValue(String key, bool value) async {}
}

void main() {
  test('계정이 바뀌면 예약 내역을 다시 조회한다', () async {
    final gym = _CountingGymRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        gymRepositoryProvider.overrideWithValue(gym),
        // 리셋이 다시 읽는 MY 목업 저장소가 저장된 프로필을 DB 에서 읽는다(#2661)
        // — 실기기 DB 는 이 테스트에서 열 수 없어 메모리 DB 를 끼운다.
        appDatabaseProvider.overrideWith((ref) {
          final AppDatabase db = AppDatabase.forTesting(
            NativeDatabase.memory(),
          );
          ref.onDispose(db.close);
          return db;
        }),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    final List<MyReservation> before = await container.read(
      myReservationsProvider.future,
    );
    expect(before.single.id, 'account-a-reservation');
    expect(gym.fetchReservationsCalls, 1);

    gym.accountId = 'account-b';
    container.read(sessionFeatureResetProvider)();

    final List<MyReservation> after = await container.read(
      myReservationsProvider.future,
    );
    // 앞 계정의 예약이 그대로 보이면 안 된다. (뿌리를 통해 이미 지켜지던 성질이라
    // 이 테스트는 레지스트리 수정 전에도 통과한다 — 고정이 목적이다.)
    expect(after.single.id, 'account-b-reservation');
    expect(gym.fetchReservationsCalls, greaterThan(1));
  });

  test('계정이 바뀌면 알림 수신 설정을 다시 조회한다', () async {
    final settings = _CountingSettingsRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        notificationSettingsRepositoryProvider.overrideWithValue(settings),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    final Map<String, bool> before = await container.read(
      notificationSettingsProvider.future,
    );
    expect(before.values, everyElement(isTrue));
    expect(settings.fetchCalls, 1);

    settings.accountId = 'account-b';
    container.read(sessionFeatureResetProvider)();

    final Map<String, bool> after = await container.read(
      notificationSettingsProvider.future,
    );
    // 앞 계정의 토글이 남으면 사용자가 끈 적 없는 알림이 켜져 있거나 그 반대가 된다.
    expect(after.values, everyElement(isFalse));
    expect(settings.fetchCalls, greaterThan(1));
  });
}
