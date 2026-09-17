enum AlertCategory { reminder, healthCheck, achievement, system }

/// 알림을 눌렀을 때 갈 곳. 서버가 알림마다 내려준다(`action.target`).
///
/// 앱이 모르는 target 은 [unknown] 이 되고, 그 알림은 읽음 처리만 하고 이동하지
/// 않는다 — 서버가 새 종류를 추가했을 때 **갈 곳 없는 알림**이 되는 편이 목록에서
/// 사라지거나 엉뚱한 화면으로 보내는 것보다 낫다.
enum AlertTarget {
  dashboard,
  coachChat,
  exercise,
  diet,

  /// MY 건강 목표 — 담당 트레이너가 목표를 바꿨을 때(#1832).
  healthGoals,
  unknown,
}

/// 알림 항목의 행동 유도 — 문구는 서버가, 이동은 앱이 정한다.
class AlertAction {
  const AlertAction({required this.label, required this.target});

  /// 버튼/힌트에 쓰는 서버 문구.
  final String label;

  /// 눌렀을 때 갈 곳.
  final AlertTarget target;

  /// 앱이 실제로 이동할 수 있는 행동인가.
  bool get isNavigable => target != AlertTarget.unknown;
}

class AlertItem {
  const AlertItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeAgo,
    required this.category,
    this.read = false,
    this.action,
    this.createdAt = '',
    this.messageKey,
    this.age,
  });

  final String id;
  final String title;
  final String body;
  final String timeAgo;
  final AlertCategory category;
  final bool read;

  /// 서버가 준 `created_at` **그대로**(ISO). 다음 쪽을 이어 받는 커서로 되돌려 준다.
  ///
  /// 파싱해서 들고 있지 않는 이유: 되돌려 줄 때 다시 문자열로 만들면 표기가 미묘하게
  /// 달라질 수 있고(정밀도·오프셋), 커서는 서버가 준 값과 **같아야** 경계가 맞는다.
  /// 화면에 보이는 시각은 별도로 [timeAgo] 가 담당한다.
  ///
  /// 데모 알림처럼 서버에서 오지 않은 항목은 비어 있다 — 목 모드는 쪽을 나누지 않는다.
  final String createdAt;

  /// 서버가 지정한 이동 경로. 없으면 읽음 처리만 한다.
  final AlertAction? action;

  /// 데모 알림 문구의 키(`demo_alert_keys.dart`). 있으면 화면이 [title]·[body]
  /// 대신 로케일에 맞는 문장을 쓴다. 서버가 만든 알림은 번역본이 없어 비어 있다. (#1812)
  final String? messageKey;

  /// 데모 알림이 만들어진 지 얼마나 됐는가. 서버 시각([createdAt])이 없는 데모
  /// 알림도 화면이 로케일에 맞는 상대 시각을 그리게 한다. (#1812)
  final Duration? age;

  AlertItem copyWith({bool? read}) => AlertItem(
    id: id,
    title: title,
    body: body,
    timeAgo: timeAgo,
    category: category,
    read: read ?? this.read,
    action: action,
    createdAt: createdAt,
    messageKey: messageKey,
    age: age,
  );
}

/// 알림 목록 화면이 그리는 상태.
///
/// [items] 와 [failedToLoad] 를 함께 들고 있는 이유: 조회가 실패해도 **이미 받아 둔
/// 목록을 지우지 않는다.** 지하철에서 새로고침했다고 알림이 사라지면, 사용자는 읽지
/// 않은 알림이 있었는지조차 알 수 없게 된다.
class NotificationState {
  const NotificationState({
    required this.items,
    this.loading = false,
    this.failedToLoad = false,
    this.hasMore = false,
    this.loadingMore = false,
  });

  final List<AlertItem> items;

  /// 첫 조회가 진행 중인가. 새로고침 중에는 기존 목록을 그대로 보여 준다.
  final bool loading;

  /// 마지막 조회가 실패했는가. 화면이 재시도를 제안하는 근거다.
  final bool failedToLoad;

  /// 더 받아 올 과거 알림이 남아 있을 수 있는가. (#965)
  ///
  /// 서버가 청한 만큼 꽉 채워 줬으면 참이다. 마지막 쪽이 정확히 한 쪽 크기였다면
  /// 한 번 더 물어보고 빈 쪽을 받게 되는데, 그 편이 **남은 알림을 못 보는 것보다**
  /// 낫다.
  final bool hasMore;

  /// 다음 쪽을 받는 중인가. 목록 끝에 진행 표시를 그리는 근거다.
  final bool loadingMore;

  int get unreadCount => items.where((AlertItem i) => !i.read).length;

  NotificationState copyWith({
    List<AlertItem>? items,
    bool? loading,
    bool? failedToLoad,
    bool? hasMore,
    bool? loadingMore,
  }) => NotificationState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    failedToLoad: failedToLoad ?? this.failedToLoad,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}
