import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/utils/active_polling_stream.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/data/repositories/mock_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';

class NotificationController extends StateNotifier<NotificationState> {
  /// [seed] 가 주어지면(데모/목 모드) 즉시 노출하고 네트워크 로드를 건너뛴다 —
  /// 데모 둘러보기 화면이 기존과 동일하게 보이도록 유지한다. 실모드는 seed=null
  /// 로 생성해 백엔드(`/notifications`)에서 최신 알림을 불러온다.
  NotificationController(this._repo, {List<AlertItem>? seed, this.onChanged})
    : _seeded = seed != null,
      super(NotificationState(items: seed ?? const <AlertItem>[])) {
    if (seed == null) {
      _load();
    }
  }

  final NotificationRepository _repo;

  /// 목록이 바뀌면 호출된다. 헤더 배지가 목록과 같은 서버 상태를 보도록,
  /// 읽음 처리 직후 다음 폴링을 기다리지 않고 즉시 다시 세게 한다.
  final void Function()? onChanged;

  /// 시드로 띄운 목/데모 모드인지(seed 가 주어진 경우). 실모드는 서버가
  /// 진실원본이라 조회·이어받기가 모두 네트워크를 타고, 목/데모는 시드가
  /// 전부라 그 경로를 건너뛴다.
  final bool _seeded;

  /// 진행 중인 조회. 화면 진입과 포그라운드 복귀가 겹쳐도 요청이 두 번 나가지 않게
  /// 같은 future 를 돌려준다 — 중복 조회는 목록이 두 번 흔들리는 것으로 보인다.
  Future<void>? _inFlight;

  Future<void> _load() {
    return _inFlight ??= _loadOnce().whenComplete(() => _inFlight = null);
  }

  Future<void> _loadOnce() async {
    if (mounted) state = state.copyWith(loading: true);
    try {
      final items = await _repo.fetchPage(limit: notificationPageSize);
      if (!mounted) return;
      // 서버가 진실원본이다. 목록을 통째로 갈아 끼우므로 중복이 남지 않는다.
      // 새로고침은 **첫 쪽으로 되돌린다** — 이어 받아 둔 과거 알림을 그대로 두면
      // 그 사이 지워진 알림이 목록에 남는다.
      state = NotificationState(
        items: items,
        hasMore: items.length >= notificationPageSize,
      );
      onChanged?.call();
    } catch (_) {
      // 실패해도 **이미 받아 둔 목록은 지우지 않는다.** 화면이 재시도를 제안한다.
      if (!mounted) return;
      state = state.copyWith(loading: false, failedToLoad: true);
    }
  }

  /// 과거 알림을 한 쪽 더 이어 붙인다. (#965)
  ///
  /// 목록 끝에 닿을 때 화면이 부른다. 이미 받는 중이거나 더 없을 때, 그리고 첫
  /// 조회가 진행 중일 때는 아무 일도 하지 않는다 — 새로고침이 첫 쪽으로 되돌리는
  /// 중에 뒤쪽을 붙이면 목록이 어긋난다.
  Future<void> loadMore() async {
    if (_seeded) return; // 목/데모는 시드가 전부다.
    if (!state.hasMore || state.loadingMore || _inFlight != null) return;
    final AlertItem? last = state.items.isEmpty ? null : state.items.last;
    if (last == null || last.createdAt.isEmpty) return;

    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repo.fetchPage(
        limit: notificationPageSize,
        before: last.createdAt,
        beforeId: last.id,
      );
      if (!mounted) return;
      // 커서가 겹치는 경우(같은 시각의 알림이 여러 건)에도 같은 항목이 두 번
      // 그려지지 않게 id 로 걸러 붙인다.
      final seen = state.items.map((AlertItem i) => i.id).toSet();
      final fresh = page
          .where((AlertItem i) => seen.add(i.id))
          .toList(growable: false);
      state = state.copyWith(
        items: <AlertItem>[...state.items, ...fresh],
        loadingMore: false,
        hasMore: page.length >= notificationPageSize,
      );
    } catch (_) {
      // 이어 받기 실패는 이미 보고 있는 목록을 건드리지 않는다. 다시 스크롤하면
      // 또 시도한다 — 첫 조회와 달리 배너까지 띄울 일은 아니다.
      if (!mounted) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  /// 서버 알림을 다시 불러온다.
  ///
  /// 화면 진입·복귀·당겨서 새로고침이 모두 이 경로를 쓴다. 목 모드에서는 시드가
  /// 진실원본이라 아무 일도 하지 않는다 — 데모 화면이 네트워크를 타면 안 된다.
  Future<void> refresh() async {
    if (_seeded) return;
    await _load();
  }

  Future<void> markRead(String id) async {
    // copyWith 로 바꾼다 — 새 상태를 통째로 만들면 이어 받아 둔 쪽 정보(hasMore)가
    // 사라져, 읽음 처리 한 번에 "더 보기" 가 멈춘다.
    state = state.copyWith(
      items: state.items
          .map((AlertItem i) => i.id == id ? i.copyWith(read: true) : i)
          .toList(),
    );
    try {
      await _repo.markRead(id);
    } catch (_) {
      // 낙관적 업데이트 유지 — 영속화 실패는 다음 로드에서 정정된다.
    } finally {
      // **쓰기가 끝난 뒤에** 다시 센다. 먼저 부르면 서버가 아직 옛 수를 답해,
      // 배지가 다음 폴링까지 틀린 채로 남는다(리뷰).
      onChanged?.call();
    }
  }

  Future<void> markAllRead() async {
    state = state.copyWith(
      items: state.items.map((AlertItem i) => i.copyWith(read: true)).toList(),
    );
    try {
      await _repo.markAllRead();
    } catch (_) {
      // 낙관적 업데이트 유지.
    } finally {
      onChanged?.call();
    }
  }
}

/// 데모/로컬 모드는 목, 실모드는 백엔드(`/notifications`) 리포.
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return MockNotificationRepository();
  }
  return DioNotificationRepository(ref.watch(dioProvider));
}, name: 'notificationRepository');

/// 알림 목록 + 세션 변이(읽음/전체읽음)를 담는 컨트롤러.
/// 목 모드는 [demoAlerts] 를 즉시 시드로 사용하고, 실모드는 백엔드에서 로드한다.
final notificationControllerProvider =
    StateNotifierProvider<NotificationController, NotificationState>((ref) {
      final useMock = ref.watch(appConfigProvider).useMockApi;
      final repo = ref.watch(notificationRepositoryProvider);
      return NotificationController(
        repo,
        seed: useMock ? demoAlerts : null,
        onChanged: () => ref.invalidate(notificationUnreadProvider),
      );
    }, name: 'notifications');

/// 헤더 벨 배지가 읽는 **서버 기준** 미읽음 수.
///
/// 목록 전체를 받아 세지 않는 이유: 배지는 모든 탭에 떠 있어서 알림을 열지 않아도
/// 최신이어야 하는데, 그때마다 전체 목록을 받는 것은 과하다.
///
/// 폴링은 앱이 앞에 있을 때만 돌고, 일시적 실패에는 마지막 값을 유지한다
/// (`activePollingStream`). 트레이너가 무언가 하면 회원 앱을 재시작하지 않아도
/// 배지가 따라온다.
final notificationUnreadProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  if (ref.watch(appConfigProvider).useMockApi) {
    // 데모에는 따라갈 서버가 없다. 시드 값을 한 번만 내보내고 폴링하지 않는다 —
    // 없는 서버를 15초마다 찌르는 타이머가 화면 수명 내내 남는다.
    return Stream<int>.fromFuture(repo.unreadCount());
  }
  return activePollingStream<int>(
    load: repo.unreadCount,
    interval: const Duration(seconds: 15),
  );
}, name: 'notificationUnread');

/// 가벼운 소비처용 **최신 한 쪽**(리포 직접). 컨트롤러와 별개로 유지한다.
///
/// 전체가 아니라 한 쪽인 이유: 서버가 더 이상 전부 주지 않는다(#965). 여기서 세어
/// 미읽음 수를 만들면 안 된다 — 그 값은 [notificationUnreadProvider] 가 서버에서
/// 받아 온다.
final notificationListProvider = FutureProvider.autoDispose<List<AlertItem>>(
  (ref) => ref.watch(notificationRepositoryProvider).fetchPage(),
  name: 'notificationList',
);
