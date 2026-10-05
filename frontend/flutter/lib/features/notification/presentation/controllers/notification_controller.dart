import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare_core/active_polling_stream.dart';

class NotificationController extends StateNotifier<NotificationState> {
  /// 만들자마자 `/notifications` 에서 최신 알림을 불러온다. 데모(목 모드)도 같은
  /// 경로다 — 로컬 인터셉터가 drift 시드로 답한다(#2660).
  ///
  /// 첫 조회가 성공하기 전에는 받은 목록이 없다 — 화면이 빈 상태 대신 로딩 표시를
  /// 그린다(#2638).
  NotificationController(this._repo, {this.onChanged})
    : super(const NotificationState(items: <AlertItem>[])) {
    _load();
  }

  final NotificationRepository _repo;

  /// 목록이 바뀌면 호출된다. 헤더 배지가 목록과 같은 서버 상태를 보도록,
  /// 읽음 처리 직후 다음 폴링을 기다리지 않고 즉시 다시 세게 한다.
  final void Function()? onChanged;

  /// 진행 중인 조회. 화면 진입과 포그라운드 복귀가 겹쳐도 요청이 두 번 나가지 않게
  /// 같은 future 를 돌려준다 — 중복 조회는 목록이 두 번 흔들리는 것으로 보인다.
  Future<void>? _inFlight;

  /// 조회가 진행 중인 동안 일어난 읽음 처리(#3097).
  ///
  /// 조회 응답은 요청을 보낸 시점의 서버 상태라, 그 사이 읽음 쓰기가 먼저 끝나면
  /// 응답이 방금 읽은 알림을 다시 안 읽음으로 덮는다. 쓰기가 진행 중이거나 조회
  /// 중에 끝난 읽음 처리를 여기 남겨 두었다가 응답에 덧입힌다 — 응답을 버리지
  /// 않으므로 그 사이 새로 온 알림은 그대로 살아 있다.
  final List<_ReadMark> _readMarks = <_ReadMark>[];

  Future<void> _load() {
    return _inFlight ??= _loadOnce().whenComplete(() => _inFlight = null);
  }

  Future<void> _loadOnce() async {
    // 다시 받기 시작하면 실패 표시를 내린다(#2877) — 재시도 중에도 실패 안내가
    // 남아 있으면 누른 것이 먹지 않은 것처럼 보인다. 받아 본 적 없이 비어 있으면
    // 화면이 첫 로딩 표시로 돌아간다.
    if (mounted) {
      state = state.copyWith(
        loading: true,
        failedToLoad: false,
        loadError: null,
      );
    }
    try {
      final items = await _repo.fetchPage(limit: notificationPageSize);
      if (!mounted) return;
      // 서버가 진실원본이다. 목록을 통째로 갈아 끼우므로 중복이 남지 않는다.
      // 새로고침은 **첫 쪽으로 되돌린다** — 이어 받아 둔 과거 알림을 그대로 두면
      // 그 사이 지워진 알림이 목록에 남는다.
      state = NotificationState(
        items: _overlayReadMarks(items),
        loaded: true,
        hasMore: items.length >= notificationPageSize,
      );
      onChanged?.call();
    } catch (error) {
      // 실패해도 **이미 받아 둔 목록은 지우지 않는다.** 화면이 재시도를 제안한다.
      // 오류는 들고 간다 — 첫 조회 실패 안내가 원인을 말한다(#3140).
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        failedToLoad: true,
        loadError: error,
      );
    } finally {
      // 쓰기가 끝난 읽음 처리는 이 조회까지만 덧입히면 된다. 다음 조회는 쓰기 뒤에
      // 나가므로 서버가 이미 읽음으로 답한다.
      _readMarks.removeWhere((_ReadMark m) => m.done);
    }
  }

  /// 받은 목록에 진행 중·조회 중에 끝난 읽음 처리를 덧입힌다(#3097).
  List<AlertItem> _overlayReadMarks(List<AlertItem> items) {
    if (_readMarks.isEmpty) return items;
    return items.map((AlertItem item) {
      if (item.read) return item;
      bool covered = false;
      for (final _ReadMark mark in _readMarks) {
        if (mark.covers(item)) {
          // 쓰기가 실패하면 이렇게 덮은 알림도 함께 안 읽음으로 되돌린다.
          if (!mark.done) mark.overlaid.add(item.id);
          covered = true;
        }
      }
      return covered ? item.copyWith(read: true) : item;
    }).toList();
  }

  /// 읽음 쓰기가 성공했다. 진행 중인 조회가 없으면 더 덧입힐 응답이 없으므로
  /// 바로 거두고, 있으면 그 응답을 받을 때까지 남겨 둔다.
  void _settleReadMark(_ReadMark mark) {
    mark.done = true;
    if (_inFlight == null) _readMarks.remove(mark);
  }

  /// 과거 알림을 한 쪽 더 이어 붙인다. (#965)
  ///
  /// 목록 끝에 닿을 때 화면이 부른다. 이미 받는 중이거나 더 없을 때, 그리고 첫
  /// 조회가 진행 중일 때는 아무 일도 하지 않는다 — 새로고침이 첫 쪽으로 되돌리는
  /// 중에 뒤쪽을 붙이면 목록이 어긋난다.
  Future<void> loadMore() async {
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
  /// 화면 진입·복귀·당겨서 새로고침이 모두 이 경로를 쓴다.
  Future<void> refresh() => _load();

  /// 알림 한 건을 읽음으로 바꾼다.
  ///
  /// 쓰기가 실패하면 그 알림만 안 읽음으로 되돌린다(#2877). 알림을 누르면 이동이
  /// 함께 일어나므로 따로 안내하지 않는다 — 서버에 안 읽음으로 남은 것이 화면에도
  /// 그대로 보이면 된다.
  Future<void> markRead(String id) async {
    final bool wasUnread = state.items.any(
      (AlertItem i) => i.id == id && !i.read,
    );
    final _ReadMark mark = _ReadMark(ids: <String>{id});
    _readMarks.add(mark);
    // copyWith 로 바꾼다 — 새 상태를 통째로 만들면 이어 받아 둔 쪽 정보(hasMore)가
    // 사라져, 읽음 처리 한 번에 "더 보기" 가 멈춘다.
    state = state.copyWith(
      items: state.items
          .map((AlertItem i) => i.id == id ? i.copyWith(read: true) : i)
          .toList(),
    );
    try {
      await _repo.markRead(id);
      _settleReadMark(mark);
    } catch (_) {
      _readMarks.remove(mark);
      if (mounted && (wasUnread || mark.overlaid.isNotEmpty)) {
        _restoreUnread(<String>{id});
      }
    } finally {
      // **쓰기가 끝난 뒤에** 다시 센다. 먼저 부르면 서버가 아직 옛 수를 답해,
      // 배지가 다음 폴링까지 틀린 채로 남는다(리뷰).
      onChanged?.call();
    }
  }

  /// 모두 읽음으로 바꾸고, 서버 쓰기가 성공했는지 돌려준다.
  ///
  /// 실패하면 읽음 표시를 되돌리고 `false` 를 돌려준다(#2877) — 화면이 실패를
  /// 알린다. 예전에는 실패를 버려, 화면은 모두 읽음인데 서버에는 안 읽음으로 남아
  /// 다음 조회 때 말없이 되살아났다.
  Future<bool> markAllRead() async {
    final Set<String> unread = state.items
        .where((AlertItem i) => !i.read)
        .map((AlertItem i) => i.id)
        .toSet();
    // 서버는 "지금까지 온 알림 전부" 를 읽음으로 바꾼다. 받아 둔 알림 id 와, 받지
    // 않은 과거 알림까지 덮도록 받아 둔 것 중 가장 새 알림 시각을 기준으로 남긴다.
    final _ReadMark mark = _ReadMark(
      ids: state.items.map((AlertItem i) => i.id).toSet(),
      before: _newestCreatedAt(state.items),
    );
    _readMarks.add(mark);
    state = state.copyWith(
      items: state.items.map((AlertItem i) => i.copyWith(read: true)).toList(),
    );
    try {
      await _repo.markAllRead();
      _settleReadMark(mark);
      return true;
    } catch (_) {
      _readMarks.remove(mark);
      if (mounted) _restoreUnread(<String>{...unread, ...mark.overlaid});
      return false;
    } finally {
      onChanged?.call();
    }
  }

  /// [ids] 를 안 읽음으로 되돌린다. 그 사이 새로고침으로 목록이 바뀌었으면 지금
  /// 목록에 남아 있는 것만 되돌린다 — 새로 받은 목록은 이미 서버 상태다.
  void _restoreUnread(Set<String> ids) {
    if (ids.isEmpty) return;
    state = state.copyWith(
      items: state.items
          .map(
            (AlertItem i) => ids.contains(i.id) ? i.copyWith(read: false) : i,
          )
          .toList(),
    );
  }
}

/// [items] 가운데 가장 새 알림의 시각. 시각을 읽을 수 없으면 null 이다.
DateTime? _newestCreatedAt(List<AlertItem> items) {
  DateTime? newest;
  for (final AlertItem item in items) {
    final DateTime? at = DateTime.tryParse(item.createdAt);
    if (at != null && (newest == null || at.isAfter(newest))) newest = at;
  }
  return newest;
}

/// 조회 응답에 덧입힐 읽음 처리 한 건(#3097).
class _ReadMark {
  _ReadMark({required this.ids, this.before});

  /// 읽음으로 바꾼 알림 id.
  final Set<String> ids;

  /// 모두 읽음이면 이 시각까지 온 알림 전부를 덮는다 — 받지 않은 과거 알림도
  /// 서버에서는 함께 읽음이 된다.
  final DateTime? before;

  /// 서버 쓰기가 성공했다.
  bool done = false;

  /// 쓰기가 끝나기 전에 도착한 응답에서 안 읽음이었는데 이 표시로 읽음으로
  /// 덮은 알림. 쓰기가 실패하면 이것까지 되돌린다.
  final Set<String> overlaid = <String>{};

  bool covers(AlertItem item) {
    if (ids.contains(item.id)) return true;
    final DateTime? cutoff = before;
    if (cutoff == null) return false;
    final DateTime? at = DateTime.tryParse(item.createdAt);
    return at != null && !at.isAfter(cutoff);
  }
}

/// 백엔드(`/notifications`) 리포. 데모(목 모드)는 같은 요청에 로컬 인터셉터가
/// drift 시드로 답한다 — 실서버와 같은 목록·쪽 넘김·읽음 경로를 탄다(#2660).
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return DioNotificationRepository(ref.watch(dioProvider));
}, name: 'notificationRepository');

/// 알림 목록 + 세션 변이(읽음/전체읽음)를 담는 컨트롤러.
final notificationControllerProvider =
    StateNotifierProvider<NotificationController, NotificationState>((ref) {
      final repo = ref.watch(notificationRepositoryProvider);
      return NotificationController(
        repo,
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
///
/// autoDispose 다(#3097). 듣는 화면(셸·탭 헤더·알림함)이 모두 사라지면 스트림을
/// 닫아 폴링을 멈춘다 — 예전에는 로그아웃 뒤 로그인 화면에서도 토큰 없이 15초마다
/// 미읽음 수를 물었다. 다시 로그인해 셸이 서면 새로 시작한다.
final notificationUnreadProvider = StreamProvider.autoDispose<int>((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  // 데모도 같은 폴링이다 — 로컬 인터셉터가 drift 의 미읽음 수로 답한다(#2660).
  return activePollingStream<int>(
    load: () async {
      // 로그아웃이 세션 상태를 먼저 바꾸고 셸이 치워지기 전 한 틈에, 무효화로 새로
      // 선 스트림이 토큰 없이 묻지 않게 한 번 더 본다. 세션을 watch 하지 않는다 —
      // 세션 초기화가 이 provider 를 무효화하므로 의존 검사에 걸릴 수 있다. 세션을
      // 아직 아무도 만들지 않았으면(라우터 없이 세운 테스트) 만들지 않는다.
      if (ref.exists(sessionControllerProvider) &&
          !ref.read(sessionControllerProvider).canEnterApp) {
        return 0;
      }
      return repo.unreadCount();
    },
    interval: const Duration(seconds: 15),
  );
}, name: 'notificationUnread');
