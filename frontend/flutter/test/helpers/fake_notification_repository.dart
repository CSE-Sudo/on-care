import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';

/// 메모리 알림 저장소. 셸을 띄우는 위젯 테스트용이다.
///
/// 데모(목 모드) 알림함은 Dio + drift 를 탄다(#2660). 알림이 관심사가 아닌 셸
/// 테스트가 그 길을 그대로 타면 파일 drift DB 를 열려다 첫 조회가 끝나지 않아,
/// 로딩 표시 때문에 `pumpAndSettle` 이 멈춘다. 식단·운동처럼 가짜로 덮는다.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository([List<AlertItem> items = const <AlertItem>[]])
    : _items = List<AlertItem>.of(items);

  List<AlertItem> _items;

  /// 목록을 부른 횟수.
  int fetchCalls = 0;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    fetchCalls++;
    return List<AlertItem>.of(_items);
  }

  @override
  Future<void> markRead(String id) async {
    _items = _items
        .map((AlertItem a) => a.id == id ? a.copyWith(read: true) : a)
        .toList();
  }

  @override
  Future<void> markAllRead() async {
    _items = _items.map((AlertItem a) => a.copyWith(read: true)).toList();
  }

  @override
  Future<int> unreadCount() async =>
      _items.where((AlertItem a) => !a.read).length;
}
