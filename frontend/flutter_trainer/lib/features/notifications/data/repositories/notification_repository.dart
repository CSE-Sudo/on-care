import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_notifications.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';

/// 트레이너 알림함을 읽고 읽음 처리한다. (#503)
///
/// 두 구현이 [trainerNotificationRepositoryProvider] 뒤에 있고
/// [AppConfig.useMockApi] 로 갈린다.
///
///  * [DemoNotificationRepository] — 데모. 로컬 DB 에 심어 둔 과거 알림을
///    읽는다(#2628). 예전에는 늘 비어 있어 진입점을 감췄다(#503).
///  * [DioNotificationRepository] — 실 백엔드(`/trainer/notifications`).
///
/// 회원용 `/notifications` 를 쓰지 않는 이유: 그 경로는 트레이너 계정을 403 으로
/// 막는 **회원 전용**이다(역할 분리). 저장되는 행은 같은 테이블이다.
abstract interface class TrainerNotificationRepository {
  /// 이 빌드에서 알림함을 쓸 수 있는가. 지금은 두 구현 모두 쓴다(#2628).
  bool get supportsInbox;

  /// 받은 알림 한 쪽(최신순). [before] 가 없으면 첫 쪽이다.
  ///
  /// 서버는 한 쪽(기본 100건)만 준다. 다음 쪽이 있으면
  /// [TrainerNotificationPage.next] 가 그 자리를 가리킨다(#2293).
  Future<TrainerNotificationPage> fetch({TrainerNotificationCursor? before});

  /// 첫 쪽을 구독한다 — 화면이 열려 있는 동안 새 알림을 따라잡는다. 이어 받은
  /// 과거 쪽은 다시 읽지 않는다 — 새 알림은 늘 첫 쪽에 들어온다.
  Stream<TrainerNotificationPage> watch();

  /// 사이드바 배지가 읽는 미읽음 수.
  Future<int> unreadCount();

  /// 미읽음 수를 구독한다. 배지가 처음 센 숫자에 멈추지 않게 하는 쪽. (#917)
  Stream<int> watchUnreadCount();

  /// 한 건 읽음 처리.
  Future<void> markRead(String id);

  /// 전체 읽음 처리. 읽음으로 바뀐 건수를 돌려준다.
  Future<int> markAllRead();
}

/// 데모: 로컬 DB 에 심어 둔 과거 알림을 읽는다(#2628).
///
/// 알림은 다 확인해도 이전 기록이 남는 화면이다. 데모에는 알림을 새로 만드는
/// 회원 백엔드가 없지만, 시드가 트레이너가 받는 종류를 골고루 심어 두고
/// 읽음 처리도 그 값을 고쳐 남긴다. 한 쪽에 모두 담는다.
class DemoNotificationRepository implements TrainerNotificationRepository {
  const DemoNotificationRepository(this._db, {this.language = DemoLanguage.ko});

  final AppDatabase _db;

  /// `3시간 전` 같은 상대 시각의 언어. 실 서버는 요청 언어로 적어 보낸다.
  final DemoLanguage language;

  @override
  bool get supportsInbox => true;

  Future<List<Map<String, Object?>>> _rows() async =>
      _decode(await _db.readValue(demoNotificationsKey));

  static List<Map<String, Object?>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, Object?>>[];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final Object? row in decoded)
        if (row is Map<String, Object?>) Map<String, Object?>.of(row),
    ];
  }

  TrainerNotificationPage _page(List<Map<String, Object?>> rows) {
    // 데모의 '지금'(서울 벽시계)을 같은 순간의 UTC 로 — 시드와 같은 시계다.
    final DateTime wall = nowKst();
    final DateTime now = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    ).subtract(kstOffset);
    final List<TrainerNotification> items = <TrainerNotification>[
      for (final Map<String, Object?> row in rows)
        TrainerNotification.fromJson(<String, Object?>{
          ...row,
          'time_ago': demoTimeAgo(
            DateTime.parse(row['created_at']! as String),
            now: now,
            korean: language == DemoLanguage.ko,
          ),
        }),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return TrainerNotificationPage(items: items);
  }

  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async =>
      // 한 쪽에 모두 담았다 — 이어 받을 쪽이 없다.
      before == null ? _page(await _rows()) : TrainerNotificationPage.empty;

  Stream<List<Map<String, Object?>>> _watchRows() =>
      (_db.select(_db.appKeyValues)
            ..where((t) => t.key.equals(demoNotificationsKey)))
          .watchSingleOrNull()
          .map((AppKeyValue? row) => _decode(row?.value));

  @override
  Stream<TrainerNotificationPage> watch() => _watchRows().map(_page);

  @override
  Future<int> unreadCount() async =>
      (await _rows()).where((r) => r['read'] != true).length;

  @override
  Stream<int> watchUnreadCount() =>
      _watchRows().map((rows) => rows.where((r) => r['read'] != true).length);

  @override
  Future<void> markRead(String id) async {
    final List<Map<String, Object?>> rows = await _rows();
    for (final Map<String, Object?> row in rows) {
      if (row['id'] == id) row['read'] = true;
    }
    await _db.putValue(demoNotificationsKey, jsonEncode(rows));
  }

  @override
  Future<int> markAllRead() async {
    final List<Map<String, Object?>> rows = await _rows();
    int marked = 0;
    for (final Map<String, Object?> row in rows) {
      if (row['read'] != true) {
        row['read'] = true;
        marked++;
      }
    }
    await _db.putValue(demoNotificationsKey, jsonEncode(rows));
    return marked;
  }
}

/// 서버 `notification_service.time_ago` 와 같은 상대 시각 문구.
@visibleForTesting
String demoTimeAgo(DateTime at, {required DateTime now, required bool korean}) {
  final int sec = now.difference(at).inSeconds;
  if (sec < 60) return korean ? '방금 전' : 'just now';
  if (sec < 3600) {
    final int n = sec ~/ 60;
    return korean ? '$n분 전' : '$n min ago';
  }
  if (sec < 86400) {
    final int n = sec ~/ 3600;
    return korean ? '$n시간 전' : '$n ${n == 1 ? 'hour' : 'hours'} ago';
  }
  final int n = sec ~/ 86400;
  return korean ? '$n일 전' : '$n ${n == 1 ? 'day' : 'days'} ago';
}

/// 다음 쪽 커서가 실리는 응답 헤더(#2293). 서버 `trainer.py` 와 같은 이름이다.
const String nextBeforeHeader = 'x-next-before';

/// 다음 쪽 커서의 tie-break(알림 id)가 실리는 응답 헤더.
const String nextBeforeIdHeader = 'x-next-before-id';

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

  /// 본문은 전과 같은 배열이고, 다음 쪽 커서는 응답 헤더로 온다(#2293).
  /// 헤더가 없으면 마지막 쪽이다.
  @override
  Future<TrainerNotificationPage> fetch({
    TrainerNotificationCursor? before,
  }) async {
    try {
      // 첫 쪽은 쿼리 없이 부른다 — 쪽 나눔 이전과 같은 요청이다.
      final res = before == null
          ? await _dio.get<List<dynamic>>(_path)
          : await _dio.get<List<dynamic>>(
              _path,
              queryParameters: before.toQuery(),
            );
      final List<TrainerNotification> items = (res.data ?? const <dynamic>[])
          .whereType<Map<String, Object?>>()
          .map(TrainerNotification.fromJson)
          .toList(growable: false);
      return TrainerNotificationPage(
        items: items,
        next: TrainerNotificationCursor.fromHeaders(
          res.headers.value(nextBeforeHeader),
          res.headers.value(nextBeforeIdHeader),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  static const String _path = '/trainer/notifications';

  @override
  Stream<TrainerNotificationPage> watch() =>
      activePollingStream<TrainerNotificationPage>(
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
        return DemoNotificationRepository(
          ref.watch(appDatabaseProvider),
          language: ref.watch(demoLanguageProvider),
        );
      }
      return DioNotificationRepository(ref.watch(dioProvider));
    }, name: 'trainerNotificationRepository');

/// 알림함에 들어갈 수 있는 빌드인가 — 사이드바 진입점 노출 조건.
final notificationInboxEnabledProvider = Provider<bool>(
  (ref) => ref.watch(trainerNotificationRepositoryProvider).supportsInbox,
  name: 'notificationInboxEnabled',
);

/// 받은 알림의 첫 쪽.
///
/// 스트림인 이유는 배지와 짝을 맞추기 위해서다 — 알림함을 열어 둔 채 배지만
/// 올라가면 목록에 없는 알림이 숫자로만 존재하게 된다. (#917)
///
/// 첫 쪽보다 오래된 알림은 [trainerNotificationPagingProvider] 가 이어 받는다
/// (#2293). 화면은 둘을 [mergeTrainerNotifications] 로 합쳐 그린다.
///
/// **목록을 보는 동안만** 산다(#2767). 알림 종 팝오버나 알림 화면이 닫히면
/// 구독이 끝나 폴링도 멈춘다. 전에는 계정 동안 붙잡아 두어(`keepAliveForAccount`)
/// 한 번 연 뒤로는 아무도 보지 않는 목록을 20초마다 다시 받았다. 배지 숫자는
/// [trainerUnreadNotificationsProvider] 가 따로 맡으니 목록을 살려 둘 이유가
/// 없다. 다시 열면 첫 쪽을 새로 받는다. 계정 경계는 저장소 provider 가
/// [accountScopeProvider] 를 보므로 그대로 지켜진다.
final trainerNotificationsProvider =
    StreamProvider.autoDispose<TrainerNotificationPage>((ref) {
      return ref.watch(trainerNotificationRepositoryProvider).watch();
    }, name: 'trainerNotifications');

/// 미읽음 수 — 사이드바 배지.
final trainerUnreadNotificationsProvider = StreamProvider.autoDispose<int>((
  ref,
) {
  return ref.watch(trainerNotificationRepositoryProvider).watchUnreadCount();
}, name: 'trainerUnreadNotifications');

/// 읽음 처리를 보냈지만 서버가 센 미읽음 수에는 아직 비치지 않은 알림. (#2762)
///
/// 알림을 누르면 화면은 바로 그 알림의 자리로 간다. 서버 숫자는 읽음 요청이
/// 끝나고 다시 읽어야 바뀌므로, 그 사이 배지는 여기 담긴 수만큼 미리 뺀다.
/// 새 숫자가 오거나 요청이 실패하면 [NotificationReadTracker] 가 꺼낸다.
/// 계정이 바뀌면 비운다.
final trainerPendingNotificationReadsProvider = StateProvider<Set<String>>((
  ref,
) {
  ref.watch(accountScopeProvider);
  return const <String>{};
}, name: 'trainerPendingNotificationReads');

/// 배지·알림 화면이 그리는 미읽음 수. 아직 모르면 `null`. (#2762)
///
/// 서버 수([trainerUnreadNotificationsProvider])에서 읽음 처리 중인 알림을
/// 미리 뺀다 — 누른 알림이 다음 폴링(20초)까지 배지에 남지 않게 한다.
final trainerUnreadBadgeProvider = Provider.autoDispose<int?>((ref) {
  final int? unread = ref.watch(trainerUnreadNotificationsProvider).valueOrNull;
  if (unread == null) return null;
  final int pending = ref.watch(trainerPendingNotificationReadsProvider).length;
  return unread - pending < 0 ? 0 : unread - pending;
}, name: 'trainerUnreadBadge');

/// 알림 한 건의 읽음 처리 — 화면 수명과 무관하게 끝까지 간다. (#2762)
///
/// 알림 종 팝오버는 항목을 누르는 순간 닫히고, 그 위젯의 `ref`·`context` 도
/// 함께 끝난다. 전에는 그 `ref` 로 읽음 요청 뒤의 갱신을 이어 가다 예외가 나
/// 이동과 배지 갱신이 모두 빠졌다. 그래서 여기서는 앱 전체의
/// [ProviderContainer] 만 쓴다.
class NotificationReadTracker {
  const NotificationReadTracker(this._container);

  final ProviderContainer _container;

  /// [id] 를 읽음으로 보낸다. 배지는 요청 전에 미리 줄이고, 실패하면 되돌린다.
  Future<void> markRead(String id) async {
    _pend(id);
    final TrainerNotificationRepository repository = _container.read(
      trainerNotificationRepositoryProvider,
    );
    try {
      await repository.markRead(id);
    } on Object {
      // 실패하면 미리 뺀 몫을 돌려 둔다 — 다음 조회에서 다시 미읽음으로 보인다.
      _unpend(id);
      return;
    }
    // 이어 받은 과거 쪽은 다시 읽지 않으므로 여기서 읽음을 비춘다. 알림 화면을
    // 떠났으면 그 상태도 이미 버려졌다.
    if (_container.exists(trainerNotificationPagingProvider)) {
      _container.read(trainerNotificationPagingProvider.notifier).markRead(id);
    }
    // 서버가 읽음을 센 새 숫자가 오면 미리 뺀 몫을 거둔다. 새 숫자가 오기 전에
    // 거두면 배지가 옛 숫자로 한 번 튀어 오른다.
    late final ProviderSubscription<AsyncValue<int>> watching;
    watching = _container.listen<AsyncValue<int>>(
      trainerUnreadNotificationsProvider,
      (AsyncValue<int>? _, AsyncValue<int> next) {
        if (next.isLoading) return;
        watching.close();
        _unpend(id);
      },
    );
    _container
      ..invalidate(trainerNotificationsProvider)
      ..invalidate(trainerUnreadNotificationsProvider);
  }

  void _pend(String id) {
    final StateController<Set<String>> pending = _container.read(
      trainerPendingNotificationReadsProvider.notifier,
    );
    pending.state = <String>{...pending.state, id};
  }

  void _unpend(String id) {
    final StateController<Set<String>> pending = _container.read(
      trainerPendingNotificationReadsProvider.notifier,
    );
    if (!pending.state.contains(id)) return;
    pending.state = <String>{...pending.state}..remove(id);
  }
}

/// 첫 쪽 뒤에 이어 받은 과거 알림. (#2293)
///
/// 전에는 첫 쪽(100건)이 전부였다. 미읽음 배지는 전체를 세는데 그보다 오래된
/// 미읽음은 목록 어디에서도 볼 수 없었다.
@immutable
class TrainerNotificationPaging {
  const TrainerNotificationPaging({
    this.items = const <TrainerNotification>[],
    this.next,
    this.started = false,
    this.loading = false,
    this.error,
  });

  /// 이어 받기를 시작한 순간의 첫 쪽 + 이어 받은 쪽들(최신순).
  ///
  /// 첫 쪽을 함께 붙잡아 두는 이유: 첫 쪽은 폴링으로 계속 바뀐다. 새 알림이
  /// 들어와 첫 쪽 끝의 알림이 밀려나면, 그 알림은 새 첫 쪽에도 이어 받은 쪽에도
  /// 없어 목록에서 사라진다.
  final List<TrainerNotification> items;

  /// 다음 쪽 커서. [started] 인데 없으면 끝까지 받았다.
  final TrainerNotificationCursor? next;

  /// 한 쪽이라도 이어 받았는가.
  final bool started;

  /// 다음 쪽을 받는 중인가 — 두 번 부르지 않게 막는다.
  final bool loading;

  /// 마지막 이어 받기가 실패했으면 그 오류. 다시 시도하면 지운다.
  final Object? error;

  TrainerNotificationPaging _copy({
    List<TrainerNotification>? items,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) => TrainerNotificationPaging(
    items: items ?? this.items,
    next: next,
    started: started,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// 과거 알림을 한 쪽씩 이어 받는다. (#2293)
///
/// 첫 쪽은 [trainerNotificationsProvider] 가 폴링하고, 이 컨트롤러는 그보다
/// 오래된 쪽만 맡는다. 새 알림은 늘 첫 쪽에 들어오므로 과거 쪽을 다시 읽을
/// 일이 없다 — 매번 전체를 읽으면 알림함이 길어질수록 폴링이 무거워진다.
class TrainerNotificationPagingController
    extends StateNotifier<TrainerNotificationPaging> {
  TrainerNotificationPagingController(this._repository)
    : super(const TrainerNotificationPaging());

  final TrainerNotificationRepository _repository;

  /// 다음 쪽을 받는다. [firstPage] 는 지금 보이는 첫 쪽 — 처음 이어 받을 때
  /// 그 커서에서 시작한다. 받을 쪽이 없거나 받는 중이면 아무것도 하지 않는다.
  Future<void> loadMore(TrainerNotificationPage firstPage) async {
    if (state.loading) return;
    final TrainerNotificationCursor? cursor = state.started
        ? state.next
        : firstPage.next;
    if (cursor == null) return;

    state = state._copy(loading: true, clearError: true);
    try {
      final TrainerNotificationPage page = await _repository.fetch(
        before: cursor,
      );
      if (!mounted) return;
      final List<TrainerNotification> base = state.started
          ? state.items
          : firstPage.items;
      final Set<String> seen = base.map((n) => n.id).toSet();
      state = TrainerNotificationPaging(
        items: <TrainerNotification>[
          ...base,
          ...page.items.where((TrainerNotification n) => seen.add(n.id)),
        ],
        next: page.next,
        started: true,
      );
    } on Object catch (error) {
      // 이어 받기 실패는 보고 있는 목록을 건드리지 않는다. 다시 누르면 또 시도한다.
      if (!mounted) return;
      state = state._copy(loading: false, error: error);
    }
  }

  /// 스크롤이 끝에 가까워져 부르는 이어 받기. 실패한 뒤에는 부르지 않는다 —
  /// 스크롤할 때마다 실패한 요청을 되풀이하지 않고, 재시도는 버튼으로 한다.
  ///
  /// 화면이 아니라 여기서 막는 이유: 요청이 곧바로 실패하면 화면이 다시 그려지기
  /// 전에 같은 스크롤 동작의 다음 알림이 도착해, 화면이 들고 있던 옛 상태로는
  /// 실패를 알 수 없다.
  Future<void> autoLoadMore(TrainerNotificationPage firstPage) async {
    if (state.error != null) return;
    await loadMore(firstPage);
  }

  /// 한 건 읽음 — 서버에 반영한 뒤 과거 쪽에도 그대로 비춘다. 과거 쪽은 다시
  /// 읽지 않으므로, 여기서 바꾸지 않으면 읽은 알림이 계속 미읽음으로 보인다.
  void markRead(String id) {
    if (!state.started) return;
    state = state._copy(
      items: <TrainerNotification>[
        for (final TrainerNotification n in state.items)
          n.id == id && !n.read ? n.copyWith(read: true) : n,
      ],
    );
  }

  /// 모두 읽음 — 서버는 쪽과 무관하게 전체를 바꾼다. 받아 둔 과거 쪽도 같게.
  void markAllRead() {
    if (!state.started) return;
    state = state._copy(
      items: <TrainerNotification>[
        for (final TrainerNotification n in state.items)
          n.read ? n : n.copyWith(read: true),
      ],
    );
  }
}

/// 이어 받은 과거 알림. 알림함을 떠나면 비운다 — 다시 열면 첫 쪽부터 본다.
final trainerNotificationPagingProvider =
    StateNotifierProvider.autoDispose<
      TrainerNotificationPagingController,
      TrainerNotificationPaging
    >((ref) {
      // 저장소가 계정마다 새로 만들어지므로(#2285) 이어 받은 쪽도 함께 비워진다.
      return TrainerNotificationPagingController(
        ref.watch(trainerNotificationRepositoryProvider),
      );
    }, name: 'trainerNotificationPaging');

/// 화면이 그리는 알림함 — 첫 쪽과 이어 받은 쪽을 합친 것. (#2293)
@immutable
class TrainerNotificationInbox {
  const TrainerNotificationInbox({
    required this.items,
    required this.hasMore,
    required this.loadingMore,
    required this.reachedEnd,
    this.loadMoreError,
  });

  /// 최신순, 같은 알림은 한 번만.
  final List<TrainerNotification> items;

  /// 더 받을 쪽이 있는가.
  final bool hasMore;

  /// 다음 쪽을 받는 중인가.
  final bool loadingMore;

  /// 이어 받다가 끝에 닿았는가. 첫 쪽만으로 끝난 짧은 알림함은 아니다 —
  /// 그때 "더 없어요" 를 붙이면 늘 보이는 군더더기가 된다.
  final bool reachedEnd;

  /// 마지막 이어 받기의 오류.
  final Object? loadMoreError;
}

/// 첫 쪽 [first] 와 이어 받은 쪽 [paging] 을 합친다.
///
/// 폴링으로 바뀐 첫 쪽이 늘 앞에 오고(읽음 상태도 첫 쪽이 더 새 값이다), 그
/// 뒤에 첫 쪽에 없는 과거 알림이 받은 순서대로 붙는다. 첫 쪽에서 밀려난
/// 알림은 붙잡아 둔 스냅숏에 남아 있어 빠지지 않는다.
TrainerNotificationInbox mergeTrainerNotifications(
  TrainerNotificationPage first,
  TrainerNotificationPaging paging,
) {
  if (!paging.started) {
    return TrainerNotificationInbox(
      items: first.items,
      hasMore: first.hasMore,
      loadingMore: paging.loading,
      reachedEnd: false,
      loadMoreError: paging.error,
    );
  }
  final Set<String> seen = first.items.map((n) => n.id).toSet();
  return TrainerNotificationInbox(
    items: <TrainerNotification>[
      ...first.items,
      ...paging.items.where((TrainerNotification n) => seen.add(n.id)),
    ],
    hasMore: paging.next != null,
    loadingMore: paging.loading,
    reachedEnd: paging.next == null,
    loadMoreError: paging.error,
  );
}
