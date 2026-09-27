import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

/// 트레이너 알림함을 읽고 읽음 처리한다. (#503)
///
/// 두 구현이 [trainerNotificationRepositoryProvider] 뒤에 있고
/// [AppConfig.useMockApi] 로 갈린다.
///
///  * [DemoNotificationRepository] — 데모. 알림을 만드는 회원 백엔드가 없어
///    항상 비어 있다. 상담 인박스(#467)와 같은 이유로, 늘 "없어요"만 말하는
///    진입점을 데모에 남기지 않는다.
///  * [DioNotificationRepository] — 실 백엔드(`/trainer/notifications`).
///
/// 회원용 `/notifications` 를 쓰지 않는 이유: 그 경로는 트레이너 계정을 403 으로
/// 막는 **회원 전용**이다(역할 분리). 저장되는 행은 같은 테이블이다.
abstract interface class TrainerNotificationRepository {
  /// 이 빌드에서 알림함을 쓸 수 있는가. 데모에서는 진입점을 감춘다.
  bool get supportsInbox;

  /// 받은 알림(최신순).
  Future<List<TrainerNotification>> fetch();

  /// 받은 알림을 구독한다 — 화면이 열려 있는 동안 새 알림을 따라잡는다.
  Stream<List<TrainerNotification>> watch();

  /// 사이드바 배지가 읽는 미읽음 수.
  Future<int> unreadCount();

  /// 미읽음 수를 구독한다. 배지가 처음 센 숫자에 멈추지 않게 하는 쪽. (#917)
  Stream<int> watchUnreadCount();

  /// 한 건 읽음 처리.
  Future<void> markRead(String id);

  /// 전체 읽음 처리. 읽음으로 바뀐 건수를 돌려준다.
  Future<int> markAllRead();
}

/// 데모: 알림함이 없다. 읽기는 빈 결과로 성공해, 딥링크로 들어와도 오류가
/// 아니라 빈 화면이 된다.
class DemoNotificationRepository implements TrainerNotificationRepository {
  const DemoNotificationRepository();

  @override
  bool get supportsInbox => false;

  @override
  Future<List<TrainerNotification>> fetch() async =>
      const <TrainerNotification>[];

  /// 데모에는 알림을 만드는 회원 백엔드가 없다. 폴링해 봐야 같은 빈 목록을
  /// 다시 세는 요청이라, 한 번 내고 끝낸다.
  @override
  Stream<List<TrainerNotification>> watch() =>
      Stream<List<TrainerNotification>>.value(const <TrainerNotification>[]);

  @override
  Future<int> unreadCount() async => 0;

  @override
  Stream<int> watchUnreadCount() => Stream<int>.value(0);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;
}

/// 실 백엔드 구현.
class DioNotificationRepository implements TrainerNotificationRepository {
  const DioNotificationRepository(
    this._dio, {
    this.pollInterval = badgePollInterval,
  });

  final Dio _dio;

  /// 알림함과 그 배지를 다시 읽는 주기. 두 값이 같은 주기를 쓰는 이유는
  /// 알림함을 열어 둔 채로 배지만 올라가면 목록과 숫자가 어긋나 보여서다.
  final Duration pollInterval;

  @override
  bool get supportsInbox => true;

  @override
  Future<List<TrainerNotification>> fetch() async {
    try {
      final res = await _dio.get<List<dynamic>>('/trainer/notifications');
      return (res.data ?? const <dynamic>[])
          .whereType<Map<String, Object?>>()
          .map(TrainerNotification.fromJson)
          .toList();
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Stream<List<TrainerNotification>> watch() =>
      activePollingStream<List<TrainerNotification>>(
        load: fetch,
        interval: pollInterval,
      );

  @override
  Stream<int> watchUnreadCount() =>
      activePollingStream<int>(load: unreadCount, interval: pollInterval);

  @override
  Future<int> unreadCount() async {
    try {
      final res = await _dio.get<Map<String, Object?>>(
        '/trainer/notifications/unread-count',
      );
      final value = res.data?['unread'];
      return value is num ? value.toInt() : 0;
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> markRead(String id) async {
    try {
      await _dio.post<void>('/trainer/notifications/$id/read');
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<int> markAllRead() async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/trainer/notifications/read-all',
      );
      final value = res.data?['marked_read'];
      return value is num ? value.toInt() : 0;
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

/// 현재 모드에 맞는 저장소.
final trainerNotificationRepositoryProvider =
    Provider<TrainerNotificationRepository>((ref) {
      ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
      if (ref.watch(appConfigProvider).useMockApi) {
        return const DemoNotificationRepository();
      }
      return DioNotificationRepository(ref.watch(dioProvider));
    }, name: 'trainerNotificationRepository');

/// 알림함에 들어갈 수 있는 빌드인가 — 사이드바 진입점 노출 조건.
final notificationInboxEnabledProvider = Provider<bool>(
  (ref) => ref.watch(trainerNotificationRepositoryProvider).supportsInbox,
  name: 'notificationInboxEnabled',
);

/// 받은 알림 목록.
///
/// 스트림인 이유는 배지와 짝을 맞추기 위해서다 — 알림함을 열어 둔 채 배지만
/// 올라가면 목록에 없는 알림이 숫자로만 존재하게 된다. (#917)
final trainerNotificationsProvider =
    StreamProvider.autoDispose<List<TrainerNotification>>((ref) {
      keepAliveForAccount(ref);
      return ref.watch(trainerNotificationRepositoryProvider).watch();
    }, name: 'trainerNotifications');

/// 미읽음 수 — 사이드바 배지.
final trainerUnreadNotificationsProvider = StreamProvider.autoDispose<int>((
  ref,
) {
  return ref.watch(trainerNotificationRepositoryProvider).watchUnreadCount();
}, name: 'trainerUnreadNotifications');
