import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';

/// Network-side [NotificationRepository]. Calls go through `Dio`; the
/// dev/local build short-circuits them in `LocalApiInterceptor`.
class DioNotificationRepository implements NotificationRepository {
  DioNotificationRepository(this._dio);
  final Dio _dio;

  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async {
    final res = await _dio.get<List<Object?>>(
      '/notifications',
      queryParameters: <String, Object?>{
        'limit': limit,
        // 커서는 첫 쪽에서 없다. null 을 실어 보내면 서버가 빈 문자열로 읽는 일이
        // 생기므로 있는 것만 붙인다.
        'before': ?before,
        'before_id': ?beforeId,
      },
    );
    final rows = res.data ?? const <Object?>[];
    return rows.cast<Map<String, Object?>>().map(_fromJson).toList();
  }

  @override
  Future<void> markRead(String id) async {
    await _dio.post<Object?>('/notifications/$id/read');
  }

  @override
  Future<void> markAllRead() async {
    await _dio.post<Object?>('/notifications/read-all');
  }

  @override
  Future<int> unreadCount() async {
    final res = await _dio.get<Map<String, Object?>>(
      '/notifications/unread-count',
    );
    // 서버가 쓰는 키는 `unread` 다(트레이너 웹도 같은 키를 읽는다). `count` 로 읽고
    // 있었는데, 그러면 실서버에서 늘 값을 못 찾아 배지가 아예 동작하지 않는다.
    final Object? raw = res.data?['unread'];
    // 잘못된 응답을 0 으로 삼키면 **읽지 않은 알림이 있는데도 배지가 꺼진다.**
    // 던져서 폴링이 마지막 좋은 값을 유지하게 한다(연결 실패와 같은 취급).
    //
    // `num` 이 아니라 `int` 를 요구하는 이유: 계약은 0 이상의 정수다. 소수를 받아
    // `toInt()` 로 잘라 내면 1.5 가 1 이 되어 **틀린 수를 조용히 보여 준다**(리뷰).
    if (raw is! int || raw < 0) {
      throw const FormatException('unread-count 응답이 올바르지 않습니다');
    }
    return raw;
  }

  static AlertItem _fromJson(Map<String, Object?> json) {
    return AlertItem(
      id: json['id']! as String,
      title: json['title']! as String,
      body: json['body']! as String,
      timeAgo: (json['time_ago'] as String?) ?? '',
      category: categoryFromWire(json['category']! as String),
      read: (json['read'] as bool?) ?? false,
      action: _actionFrom(json['action']),
      // 다음 쪽 커서로 되돌려 줄 값이라 **문자열 그대로** 들고 간다(#965).
      createdAt: (json['created_at'] as String?) ?? '',
      // 로컬 목 모드의 데모 시드만 준다. 실서버 알림에는 없다(#1812).
      messageKey: json['message_key'] as String?,
    );
  }

  /// 서버가 준 행동 유도. 없으면 null — 읽음 처리만 하는 알림이다.
  static AlertAction? _actionFrom(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    // 캐스팅하지 않고 확인만 한다. 계약이 깨진 action 하나가 `TypeError` 를 던지면
    // **알림 목록 전체가 실패한다** — 그 한 건만 버리고 나머지는 보여 준다(리뷰).
    //
    // 미읽음 수와 반대로 판단하는 이유: 그쪽은 값 하나라 던지면 폴링이 마지막 좋은
    // 값을 유지한다. 여기서 던지면 멀쩡한 알림까지 함께 사라진다.
    final Object? label = raw['label'];
    final Object? target = raw['target'];
    if (label is! String || label.isEmpty || target is! String) return null;
    return AlertAction(label: label, target: _targetFrom(target));
  }

  /// 앱이 모르는 target 은 [AlertTarget.unknown] 이다. 목록에서 빼지 않고 이동만
  /// 하지 않는다 — 안 보이는 알림보다 갈 곳 없는 알림이 낫다(트레이너 웹과 같은 규칙).
  static AlertTarget _targetFrom(String s) => switch (s) {
    'dashboard' => AlertTarget.dashboard,
    'coach_chat' => AlertTarget.coachChat,
    'exercise' => AlertTarget.exercise,
    'diet' => AlertTarget.diet,
    'health_goals' => AlertTarget.healthGoals,
    _ => AlertTarget.unknown,
  };

  /// 서버 갈래 → 앱 갈래.
  ///
  /// 트레이너 활동이 만드는 회원 알림(`coach_chat`·`routine`·`member_schedule`·
  /// `consultation_result`)은 회원이 확인하고 움직여야 하는 알림이라 리마인더다.
  /// 예전에는 모르는 갈래로 떨어져 시스템 공지(정보 아이콘)처럼 보였다(#1812).
  @visibleForTesting
  static AlertCategory categoryFromWire(String s) => switch (s) {
    'reminder' ||
    'coach_chat' ||
    'routine' ||
    'member_schedule' ||
    'consultation_result' => AlertCategory.reminder,
    'health_check' => AlertCategory.healthCheck,
    'achievement' => AlertCategory.achievement,
    _ => AlertCategory.system,
  };
}
