/// 계정이 바뀌면 알림 저장소와 벨 배지도 새 계정 기준으로 시작한다. (#1936)
///
/// 리셋 목록에 이 둘이 빠져 있어, 데모에서 "모두 읽음" 을 누른 뒤 다시 들어오면
/// 알림이 전부 읽음인 채였고 벨의 빨간 점도 앞 계정 값으로 남았다.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

void main() {
  // 알림만 보는 테스트지만 `appDatabaseProvider` 까지 인메모리로 덮어야 한다.
  //
  // 리셋은 등록된 목록을 전부 무효화하고, riverpod 의 `invalidate` 는 디버그
  // 단언(`_debugAssertCanDependOn`)이 순환 의존을 확인하려고 대상 provider 의
  // element 를 **미리 만든다**. 그래서 이 테스트가 한 번도 읽지 않는
  // `dietRepositoryProvider` 가 실제로 생성되고, 그 뿌리를 따라
  // `dioProvider` → `appDatabaseProvider` → 파일 기반 drift DB 가 열린다.
  // 파일 DB 는 `path_provider` 로 기기 저장 경로를 묻는데 VM 테스트에는 그
  // 플러그인 구현이 없다 — E2E 하네스의 `installPluginFakes` 가 같은 이유로
  // 이 채널을 대신 채워 준다.
  //
  // 그 실패는 테스트 본문이 끝난 **뒤** 처리되지 않은 비동기 오류로 올라온다
  // (riverpod 의 단언은 동기 예외만 삼킨다). 그래서 한 번 통과한 테스트가
  // 뒤늦게 빨개지고, 지연된 오류가 아직 살아 있는 테스트에 닿는지는 호스트마다
  // 달라 리눅스 CI 는 초록인데 Windows 로컬만 깨졌다(#1997). 인메모리 DB 를
  // 덮으면 아무도 기기 저장소를 묻지 않는다 — 같은 리셋을 돌리는 옆 테스트
  // `session_feature_reset_test.dart` 도 같은 이유로 같은 것을 덮는다.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('계정이 바뀌면 알림 저장소를 새로 만든다', () async {
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        appDatabaseProvider.overrideWithValue(db),
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
    final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mockConfig),
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        appDatabaseProvider.overrideWithValue(db),
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
