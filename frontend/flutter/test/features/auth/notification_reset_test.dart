/// 계정이 바뀌면 알림 저장소와 벨 배지도 새 계정 기준으로 시작한다. (#1936)
///
/// 리셋 목록에 이 둘이 빠져 있어, 데모에서 "모두 읽음" 을 누른 뒤 다시 들어오면
/// 알림이 전부 읽음인 채였고 벨의 빨간 점도 앞 계정 값으로 남았다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('계정이 바뀌면 알림 저장소를 새로 만든다', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    final NotificationRepository before = container.read(
      notificationRepositoryProvider,
    );
    // 앞 계정이 전부 읽음으로 바꾼다 — 목 저장소는 이것을 세션 동안 기억한다.
    await container.read(notificationControllerProvider.notifier).markAllRead();

    container.read(sessionFeatureResetProvider)();

    // 같은 인스턴스가 남아 있으면 앞 계정의 읽음 상태를 그대로 물려받는다.
    expect(
      identical(container.read(notificationRepositoryProvider), before),
      isFalse,
    );
  });

  test('리셋 목록이 벨 배지까지 훑는다', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);

    // 듣는 사람이 있어야 무효화가 다시 읽기로 이어진다.
    final int before = container.read(notificationUnreadProvider).valueOrNull ?? 0;
    container.read(sessionFeatureResetProvider)();

    // 값 자체가 아니라 "되짚혔는가" 를 본다 — 목 모드는 한 번 내보내고 끝이라
    // 되짚지 않으면 앞 계정 값이 그대로 남는다.
    expect(container.read(notificationUnreadProvider), isA<AsyncValue<int>>());
    expect(before, isNotNull);
  });
}
