// 알림함 경로(/notifications).

part of '../local_api_interceptor.dart';

extension _LocalApiNotifications on LocalApiInterceptor {
  /// 실서버와 같은 계약으로 답한다 — 최신순 한 쪽, `limit`·`before`·`before_id`
  /// 커서(#965). 여기서 상한을 무시하면 로컬 모드에서만 무한 목록이 되어, 이어
  /// 받기가 되는지 개발 중에 확인할 수 없다.
  Future<Response<Object?>> _notifications(RequestOptions options) async {
    // 끝난 주의 챌린지 결과 알림은 알림함을 읽을 때 생긴다 — 서버와 같다(#1789).
    await _settleChallenges();
    final Map<String, dynamic> params = options.queryParameters;
    final int limit = switch (params['limit']) {
      final int v => v.clamp(1, 100),
      final String v => (int.tryParse(v) ?? 50).clamp(1, 100),
      _ => 50,
    };
    final DateTime? before = switch (params['before']) {
      final String v => DateTime.tryParse(v),
      _ => null,
    };
    final String? beforeId = params['before_id'] as String?;

    final query = _db.select(_db.notificationItems)
      ..orderBy(<OrderClauseGenerator<$NotificationItemsTable>>[
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    if (before != null) {
      // (created_at, id) 복합 커서 — 같은 시각의 알림이 여러 건이어도 경계에서
      // 빠지거나 겹치지 않는다.
      query.where(
        (t) => beforeId == null
            ? t.createdAt.isSmallerThanValue(before)
            : t.createdAt.isSmallerThanValue(before) |
                  (t.createdAt.equals(before) &
                      t.id.isSmallerThanValue(beforeId)),
      );
    }
    query.limit(limit);
    final rows = await query.get();

    final now = nowKst();
    final list = <Map<String, Object?>>[
      for (final r in rows)
        <String, Object?>{
          'id': r.id,
          'title': r.title,
          'body': r.body,
          'category': r.category,
          'read': r.read,
          'created_at': r.createdAt.toIso8601String(),
          // 데모 시드 알림은 정해 둔 경과 시간으로 보인다 — 같은 날 안에서 시각이
          // 흐르지 않는다(#2660). 나머지는 실제 경과이고 문구도 서버 일반 알림과
          // 같다(#3099).
          'time_ago': switch (kDemoAlertAgeBySeedId[r.id]) {
            final Duration ago => _demoSeedTimeAgoKorean(ago),
            null => _timeAgoKorean(now.difference(r.createdAt)),
          },
          // 데모 시드 알림은 예전 데모 목록의 목적지, 나머지는 서버처럼 갈래별
          // 목적지를 싣는다(#1789·#2660).
          // 목적지가 없으면 서버처럼 null 로 싣는다 — 키가 빠지면 응답 모양이
          // 갈린다(#3099).
          'action': _demoSeedAction(r.id) ?? _demoActionFor(r.category),
          // 데모는 담당 요청 알림·문장 틀을 만들지 않는다. 서버 `NotificationOut`
          // 과 같은 키를 빈 값으로 싣는다(#3099).
          'invite_id': null,
          'template': null,
          'args': null,
          // 데모 시드 알림은 문구 키를 함께 준다 — 화면이 로케일에 맞는 문장을
          // 고른다. 시드 밖의 알림은 키가 없다(#1812).
          'message_key': ?kDemoAlertKeyBySeedId[r.id],
        },
    ];
    return _ok(options, list);
  }

  /// 데모에 로그인하면 시드 알림을 시드할 때의 읽음 상태로 되돌린다(#2660).
  ///
  /// 예전 데모는 로그인·계정 전환마다 알림이 처음 상태였다(#1936). 읽음이 drift 에
  /// 남게 된 뒤에도 그 모양을 지킨다. 챌린지 결과처럼 데모 중에 생긴 알림은 둔다.
  /// 앱을 다시 켜기만 한 것(새로고침)은 로그인이 아니라 읽음이 남는다 — 실서버와
  /// 같고, 날짜가 바뀌면 시드가 다시 깔리며 풀린다.
  Future<void> _resetDemoNotificationReads() async {
    await (_db.update(_db.notificationItems)
          ..where((t) => t.id.isIn(kDemoAlertKeyBySeedId.keys)))
        .write(const NotificationItemsCompanion(read: Value(false)));
    await (_db.update(_db.notificationItems)
          ..where((t) => t.id.isIn(kDemoAlertReadSeedIds)))
        .write(const NotificationItemsCompanion(read: Value(true)));
  }

  /// 헤더 벨 배지가 폴링하는 미읽음 수. 서버와 같은 키(`unread`)로 답한다.
  Future<Response<Object?>> _notificationsUnreadCount(
    RequestOptions options,
  ) async {
    final unread = await (_db.select(
      _db.notificationItems,
    )..where((t) => t.read.equals(false))).get();
    return _ok(options, <String, Object?>{'unread': unread.length});
  }

  /// 알림 한 건 읽음. 없는 id 는 서버처럼 404 다.
  Future<Response<Object?>> _notificationRead(RequestOptions options) async {
    final List<String> parts = options.path.split('/');
    final String id = parts[parts.length - 2];
    final int n =
        await (_db.update(_db.notificationItems)..where((t) => t.id.equals(id)))
            .write(const NotificationItemsCompanion(read: Value(true)));
    if (n == 0) return _notFound(options, '알림을 찾을 수 없어요.');
    return _ok(options, <String, Object?>{'id': id, 'read': true});
  }

  /// 안 읽은 알림을 모두 읽음. 바꾼 건수를 서버와 같은 키로 준다.
  Future<Response<Object?>> _notificationsReadAll(
    RequestOptions options,
  ) async {
    final int n =
        await (_db.update(_db.notificationItems)
              ..where((t) => t.read.equals(false)))
            .write(const NotificationItemsCompanion(read: Value(true)));
    return _ok(options, <String, Object?>{'marked_read': n});
  }

  /// 시드 밖 알림의 상대 시각 — 서버 `notification_service.time_ago` 와 같다.
  /// 하루 지난 알림은 `1일 전` 이다(#3099).
  String _timeAgoKorean(Duration d) {
    if (d.inMinutes < 1) return '방금 전';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    return '${d.inDays}일 전';
  }

  /// 데모 시드 알림의 상대 시각 — 서버 `seed_notifications.demo_time_ago` 와
  /// 같다. 하루 지난 알림은 `어제` 다(#2691).
  String _demoSeedTimeAgoKorean(Duration d) {
    if (d.inMinutes < 1) return '방금';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    if (d.inDays == 1) return '어제';
    return '${d.inDays}일 전';
  }
}

Map<String, Object?>? _demoSeedAction(String id) {
  final ({String label, String target})? a = kDemoAlertActionBySeedId[id];
  if (a == null) return null;
  return <String, Object?>{'label': a.label, 'target': a.target};
}

/// 목업 알림의 행동 유도 — 서버 `_ACTION_BY_CATEGORY` 중 목업이 만드는 것만.
///
/// 데모 시드 알림(리마인더·성취·트레이너 메시지·리포트·루틴)도 서버 표를 그대로
/// 따른다. 데모 알림함이 실서버 데모 계정과 같은 곳으로 이어져야 한다(#2660).
Map<String, Object?>? _demoActionFor(String category) => switch (category) {
  'reminder' => const <String, Object?>{
    'label': '기록하러 가기',
    'target': 'dashboard',
  },
  'achievement' => const <String, Object?>{
    'label': '대시보드 보기',
    'target': 'dashboard',
  },
  'coach_chat' => const <String, Object?>{
    'label': '대화 보기',
    'target': 'coach_chat',
  },
  'coach_report' => const <String, Object?>{
    'label': '리포트 보기',
    'target': 'coach_chat',
  },
  'routine' => const <String, Object?>{'label': '운동 보기', 'target': 'exercise'},
  // PT 일정 — 운동 탭의 다음 PT 배지·헬스장 패널 예약(#3028).
  'member_schedule' => const <String, Object?>{
    'label': '일정 보기',
    'target': 'exercise',
  },
  // PT 완료·피드백 — 운동 탭의 PT 기록(#3027).
  'pt_done' => const <String, Object?>{
    'label': 'PT 기록 보기',
    'target': 'exercise',
  },
  'benefits' => const <String, Object?>{
    'label': '내 혜택 보기',
    'target': 'my_benefits',
  },
  'points_shop' => const <String, Object?>{
    'label': '포인트 사용처 보기',
    'target': 'points_shop',
  },
  _ => null,
};
