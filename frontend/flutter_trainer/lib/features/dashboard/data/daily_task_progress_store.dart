import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One day's 오늘 할 일 체크 현황.
///
/// [completedCarriedOver] is the subset of [completedToday] + itself that
/// was already pending on a *previous* day's snapshot — a real "이월된
/// 할 일을 오늘 해결했다" count, not a guess. [pendingKeys] is saved so the
/// *next* day can tell which of its own tasks are carry-overs.
class DailyTaskSnapshot {
  /// Creates a snapshot.
  const DailyTaskSnapshot({
    required this.total,
    required this.completedToday,
    required this.completedCarriedOver,
    required this.pendingKeys,
    this.dismissedKeys = const <String>{},
    this.completedKeys,
  });

  /// How many tasks were on the list that day.
  final int total;

  /// Checked, and not carried over from an earlier day.
  final int completedToday;

  /// Checked, and already pending on a previous day's snapshot.
  final int completedCarriedOver;

  /// Task keys (`alert-clientId`) still unchecked as of the last save —
  /// tomorrow's carry-over check reads this.
  final Set<String> pendingKeys;

  /// 그날 오늘 목록에서 삭제한 키 — 같은 날 다시 연 화면(다른 기기 포함)이
  /// 지운 항목을 되살리지 않게 한다(#1633).
  final Set<String> dismissedKeys;

  /// 그날 체크한 키(#1716). 복원은 이 값만 체크로 되살린다 — [pendingKeys] 에서
  /// 거꾸로 추정하면 마지막 저장 뒤에 새로 생긴 미션까지 완료로 보인다. 이 값이
  /// 생기기 전에 저장된 날은 null.
  final Set<String>? completedKeys;

  /// Total checked, either kind.
  int get completed => completedToday + completedCarriedOver;
}

/// 보관 중인 날짜별 요약 전체.
class DailyTaskHistory {
  /// Creates a history.
  const DailyTaskHistory({
    this.days = const <String, DailyTaskSnapshot>{},
    this.firstSavedDate,
  });

  /// `YYYY-MM-DD` → 그날 요약.
  final Map<String, DailyTaskSnapshot> days;

  /// 실제로 저장된 가장 이른 날, 한 번도 쓰지 않았으면 null.
  ///
  /// 데모 이력이 어디까지 끼어들어도 되는지의 경계다(#1203) — 트레이너가 처음
  /// 체크한 날부터는 그날의 실제 기록만 보여 준다.
  final String? firstSavedDate;

  /// The snapshot saved for [date] (`YYYY-MM-DD`), or null if the trainer
  /// never opened the dashboard that day.
  DailyTaskSnapshot? read(String date) => days[date];

  /// [date] 를 [snapshot] 으로 바꾼 사본.
  DailyTaskHistory withDay(String date, DailyTaskSnapshot snapshot) {
    final String? first = firstSavedDate;
    return DailyTaskHistory(
      days: <String, DailyTaskSnapshot>{...days, date: snapshot},
      firstSavedDate: first == null || date.compareTo(first) < 0 ? date : first,
    );
  }
}

/// 할 일 키 하나에 하는 일. 서버 `TrainerTaskKeyChange.action` 과 같은 값이다.
enum TaskKeyAction {
  /// 완료로 체크.
  check('check'),

  /// 체크 해제(완료 취소).
  uncheck('uncheck'),

  /// 오늘 목록에서 지움. 되돌리지 않는다.
  dismiss('dismiss');

  const TaskKeyAction(this.wire);

  /// 서버로 보내는 값.
  final String wire;
}

/// 할 일 키 하나의 변경 — 그날 기록에 이 키만 반영한다. (#2886)
///
/// 예전에는 체크할 때마다 그날 목록 전체를 보내 덮어써, 두 탭·기기에서 서로
/// 다른 할 일을 체크하면 나중에 저장한 쪽이 앞의 체크를 지웠다.
class TaskKeyChange {
  /// Creates a change.
  const TaskKeyChange({
    required this.key,
    required this.action,
    required this.keys,
    required this.seen,
    this.carriedOver = const <String>{},
  });

  /// 바꾸는 미션 키.
  final String key;

  /// 그 키에 하는 일.
  final TaskKeyAction action;

  /// 화면이 지금 보여 주는 미션 키(지운 것 제외) — 처음 보는 미션을 그날 목록에
  /// 올린다.
  final Set<String> keys;

  /// 화면이 그날 본 미션 키 — 저장된 키 중 여기 있으면서 [keys] 에 없는 것은
  /// 화면에서 사라진 미션이라 목록에서 뺀다. 여기 없는 저장 키는 화면이 모르는
  /// 미션이라 그대로 둔다(#2763).
  final Set<String> seen;

  /// 어제 끝내지 못해 넘어온 키. 로컬 저장소(데모)와 화면의 선반영만 쓴다 —
  /// 서버는 전날 행의 `pending_keys` 에서 직접 낸다. 데모의 이월 항목은 서버
  /// 기록이 아니라 데모 이력에서 오기 때문이다.
  final Set<String> carriedOver;
}

/// 저장된 그날 기록 [saved] 에 [change] 를 얹은 결과. (#2886)
///
/// 서버 `merge_key_change`(`trainer_task_progress_service.py`)와 같은 규칙이다 —
/// 데모 저장소와 화면의 선반영이 이 함수를 쓴다.
///  * 바꾸는 것은 [TaskKeyChange.key] 하나다. 다른 탭이 체크한 키는 남는다.
///  * 지운 키는 되살아나지 않는다.
///  * 그날 목록 = 화면의 키 + 화면이 모르는 저장 키. 완료는 그 안에서만 센다.
///  * 이월 완료 = 완료 중 [TaskKeyChange.carriedOver] 에 든 키.
///
/// 체크 키 기록 이전(#1716)의 날은 무엇을 체크했는지 알 수 없어 완료를 비운다.
DailyTaskSnapshot applyTaskKeyChange({
  required DailyTaskSnapshot? saved,
  required TaskKeyChange change,
}) {
  final Set<String> storedCompleted = <String>{...?saved?.completedKeys};
  final Set<String> storedPending = <String>{...?saved?.pendingKeys};
  final Set<String> dismissed = <String>{...?saved?.dismissedKeys};
  final Set<String> completed = Set<String>.of(storedCompleted);
  final Set<String> keys = Set<String>.of(change.keys);
  switch (change.action) {
    case TaskKeyAction.check:
      completed.add(change.key);
      keys.add(change.key);
    case TaskKeyAction.uncheck:
      completed.remove(change.key);
      keys.add(change.key);
    case TaskKeyAction.dismiss:
      dismissed.add(change.key);
      completed.remove(change.key);
  }
  final Set<String> unseen = storedCompleted
      .union(storedPending)
      .difference(change.seen)
      .difference(keys);
  final Set<String> universe = keys.union(unseen).difference(dismissed);
  completed.retainAll(universe);
  return taskSnapshotOf(
    completed: completed,
    pending: universe.difference(completed),
    dismissed: dismissed,
    carriedOver: change.carriedOver,
  );
}

/// 실패한 변경을 되돌린다 — [current] 에서 [key] 의 상태만 [before] 로 돌린다.
///
/// 그 사이 다른 키의 변경(연달아 누른 체크)은 그대로 둔다.
DailyTaskSnapshot restoreTaskKey({
  required DailyTaskSnapshot? current,
  required DailyTaskSnapshot? before,
  required String key,
  Set<String> carriedOver = const <String>{},
}) {
  final Set<String> completed = <String>{...?current?.completedKeys}
    ..remove(key);
  final Set<String> pending = <String>{...?current?.pendingKeys}..remove(key);
  final Set<String> dismissed = <String>{...?current?.dismissedKeys}
    ..remove(key);
  if (before?.completedKeys?.contains(key) ?? false) completed.add(key);
  if (before?.pendingKeys.contains(key) ?? false) pending.add(key);
  if (before?.dismissedKeys.contains(key) ?? false) dismissed.add(key);
  return taskSnapshotOf(
    completed: completed,
    pending: pending,
    dismissed: dismissed,
    carriedOver: carriedOver,
  );
}

/// 키 집합에서 하루 요약을 만든다 — 합계는 집합에서 다시 낸다.
DailyTaskSnapshot taskSnapshotOf({
  required Set<String> completed,
  required Set<String> pending,
  required Set<String> dismissed,
  required Set<String> carriedOver,
}) {
  final int carried = completed.intersection(carriedOver).length;
  return DailyTaskSnapshot(
    total: completed.union(pending).length,
    completedToday: completed.length - carried,
    completedCarriedOver: carried,
    pendingKeys: Set<String>.of(pending),
    dismissedKeys: Set<String>.of(dismissed),
    completedKeys: Set<String>.of(completed),
  );
}

/// 오늘 할 일 진행 상태를 읽고 쓴다 — 할 일 진행률 그래프의 날짜별 이력이기도
/// 하다.
///
/// 알림 수신 설정(`trainer_settings_repository.dart`)과 같은 두 갈래다.
/// [AppConfig.useMockApi] 로 고른다:
///  * [LocalDailyTaskProgressStore] — 데모. 계정이 없어 기기 말고 둘 곳이 없다.
///  * [DioDailyTaskProgressStore] — 실서버. **계정 단위**라 센터 PC 에서 체크한
///    항목이 태블릿에서도 체크돼 있다(#1633). 오늘·어제 판정과 보관 기간(63일)은
///    서버가 정한다.
abstract interface class DailyTaskProgressStore {
  /// 보관 중인 날짜별 요약.
  Future<DailyTaskHistory> load();

  /// [date] (`YYYY-MM-DD`) 의 요약을 통째로 덮어쓴다. 실패하면 [AppError].
  ///
  /// 화면은 [applyKey] 를 쓴다 — 통째 저장은 다른 탭·기기의 체크를 지운다
  /// (#2886). 데모 이력을 채우는 등 그날 전체를 정할 때만 쓴다.
  Future<void> save(String date, DailyTaskSnapshot snapshot);

  /// [date] 의 기록에 키 하나의 변경을 반영하고, 반영 뒤 그날 요약을 돌려준다.
  /// 실서버에서는 다른 기기의 변경도 담겨 온다. 실패하면 [AppError]. (#2886)
  Future<DailyTaskSnapshot> applyKey(String date, TaskKeyChange change);
}

/// 데모용 기기 로컬 저장 — SharedPreferences.
class LocalDailyTaskProgressStore implements DailyTaskProgressStore {
  /// Creates the store over the app-wide prefs instance.
  const LocalDailyTaskProgressStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'dashboard_task_progress:';

  @override
  Future<void> save(String date, DailyTaskSnapshot snapshot) {
    return _prefs.setString(
      '$_prefix$date',
      jsonEncode(<String, Object?>{
        'total': snapshot.total,
        'completedToday': snapshot.completedToday,
        'completedCarriedOver': snapshot.completedCarriedOver,
        'pendingKeys': snapshot.pendingKeys.toList(growable: false),
        'dismissedKeys': snapshot.dismissedKeys.toList(growable: false),
        'completedKeys': snapshot.completedKeys?.toList(growable: false),
      }),
    );
  }

  /// 기기 하나의 저장이라 겹칠 다른 쓰기가 없다 — 저장된 그날 기록에 같은
  /// 규칙([applyTaskKeyChange])으로 얹는다.
  @override
  Future<DailyTaskSnapshot> applyKey(String date, TaskKeyChange change) async {
    final String? raw = _prefs.getString('$_prefix$date');
    final Object? decoded = raw == null ? null : jsonDecode(raw);
    final DailyTaskSnapshot? saved = decoded is Map
        ? _decode(
            decoded['total'],
            decoded['completedToday'],
            decoded['completedCarriedOver'],
            decoded['pendingKeys'],
            decoded['dismissedKeys'],
            decoded['completedKeys'],
          )
        : null;
    final DailyTaskSnapshot next = applyTaskKeyChange(
      saved: saved,
      change: change,
    );
    await save(date, next);
    return next;
  }

  @override
  Future<DailyTaskHistory> load() async {
    final days = <String, DailyTaskSnapshot>{};
    for (final String key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = _prefs.getString(key);
      if (raw == null) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final snapshot = _decode(
        decoded['total'],
        decoded['completedToday'],
        decoded['completedCarriedOver'],
        decoded['pendingKeys'],
        decoded['dismissedKeys'],
        decoded['completedKeys'],
      );
      if (snapshot != null) days[key.substring(_prefix.length)] = snapshot;
    }
    final dates = days.keys.toList()..sort();
    return DailyTaskHistory(
      days: days,
      firstSavedDate: dates.isEmpty ? null : dates.first,
    );
  }
}

/// 계정 단위 저장 — `/v1/trainer/dashboard/task-progress`.
class DioDailyTaskProgressStore implements DailyTaskProgressStore {
  /// Creates the API-backed store.
  const DioDailyTaskProgressStore(this._dio);

  final Dio _dio;

  static const String _base = '/trainer/dashboard/task-progress';

  @override
  Future<DailyTaskHistory> load() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(_base);
      return dailyTaskHistoryFromJson(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> save(String date, DailyTaskSnapshot snapshot) async {
    try {
      await _dio.put<Map<String, dynamic>>(
        '$_base/$date',
        data: dailyTaskSnapshotToJson(snapshot),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  /// `POST /trainer/dashboard/task-progress/{date}/keys` — 서버가 행을 잠그고 그
  /// 키만 반영한다. 응답은 반영 뒤의 그날 상태다.
  @override
  Future<DailyTaskSnapshot> applyKey(String date, TaskKeyChange change) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_base/$date/keys',
        data: taskKeyChangeToJson(change),
      );
      final Map<String, dynamic> day = res.data ?? const <String, dynamic>{};
      final DailyTaskSnapshot? snapshot = _decode(
        day['total'],
        day['completed_today'],
        day['completed_carried_over'],
        day['pending_keys'],
        day['dismissed_keys'],
        day['completed_keys'],
      );
      if (snapshot == null) {
        throw const UnknownError(message: 'task-progress: malformed response');
      }
      return snapshot;
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

DailyTaskSnapshot? _decode(
  Object? total,
  Object? completedToday,
  Object? completedCarriedOver,
  Object? pendingKeys,
  Object? dismissedKeys,
  Object? completedKeys,
) {
  if (total is! int ||
      completedToday is! int ||
      completedCarriedOver is! int ||
      pendingKeys is! List) {
    return null;
  }
  return DailyTaskSnapshot(
    total: total,
    completedToday: completedToday,
    completedCarriedOver: completedCarriedOver,
    pendingKeys: pendingKeys.whereType<String>().toSet(),
    // 삭제 기록 이전에 저장된 날에는 이 값이 없다.
    dismissedKeys: dismissedKeys is List
        ? dismissedKeys.whereType<String>().toSet()
        : const <String>{},
    // 체크한 키 기록 이전(#1716)에 저장된 날에는 이 값이 없다.
    completedKeys: completedKeys is List
        ? completedKeys.whereType<String>().toSet()
        : null,
  );
}

/// Decodes `TrainerTaskProgressOut`.
DailyTaskHistory dailyTaskHistoryFromJson(Map<String, dynamic> json) {
  final days = <String, DailyTaskSnapshot>{};
  final rawDays = json['days'];
  if (rawDays is List) {
    for (final Object? item in rawDays) {
      if (item is! Map) continue;
      final date = item['date'];
      final snapshot = _decode(
        item['total'],
        item['completed_today'],
        item['completed_carried_over'],
        item['pending_keys'],
        item['dismissed_keys'],
        item['completed_keys'],
      );
      if (date is String && snapshot != null) days[date] = snapshot;
    }
  }
  final first = json['first_saved_date'];
  return DailyTaskHistory(
    days: days,
    firstSavedDate: first is String ? first : null,
  );
}

/// Encodes `TrainerTaskProgressSave`.
Map<String, Object?> dailyTaskSnapshotToJson(DailyTaskSnapshot snapshot) {
  return <String, Object?>{
    'total': snapshot.total,
    'completed_today': snapshot.completedToday,
    'completed_carried_over': snapshot.completedCarriedOver,
    'pending_keys': snapshot.pendingKeys.toList(growable: false),
    'dismissed_keys': snapshot.dismissedKeys.toList(growable: false),
    'completed_keys': snapshot.completedKeys?.toList(growable: false),
  };
}

/// Encodes `TrainerTaskKeyChange`. [TaskKeyChange.carriedOver] 는 보내지 않는다 —
/// 서버가 전날 기록에서 직접 낸다.
Map<String, Object?> taskKeyChangeToJson(TaskKeyChange change) {
  return <String, Object?>{
    'key': change.key,
    'action': change.action.wire,
    'keys': (change.keys.toList()..sort()),
    'seen': (change.seen.toList()..sort()),
  };
}

/// Provides the store for the current mode.
final dailyTaskProgressStoreProvider = Provider<DailyTaskProgressStore>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  if (ref.watch(appConfigProvider).useMockApi) {
    return LocalDailyTaskProgressStore(ref.watch(sharedPreferencesProvider));
  }
  return DioDailyTaskProgressStore(ref.watch(dioProvider));
}, name: 'dailyTaskProgressStore');

/// 불러온 이력과 저장 — 오늘 할 일 카드와 할 일 진행률 그래프가 함께 본다.
///
/// 대시보드를 떠나면 버린다(autoDispose). 다시 들어오면 새로 읽어, 다른 기기에서
/// 바꾼 체크가 반영되고 로그아웃한 계정의 이력이 다음 계정에 남지 않는다.
class DailyTaskHistoryController
    extends AutoDisposeAsyncNotifier<DailyTaskHistory> {
  Future<void> _lastSave = Future<void>.value();
  int _inFlight = 0;

  /// 아직 답을 받지 못한 변경이 있는가. 있으면 다시 읽기를 미룬다 — 다시 읽은
  /// 기록이 선반영한 체크를 잠깐 지웠다가 되살리며 깜빡인다.
  bool get hasPendingChanges => _inFlight > 0;

  @override
  Future<DailyTaskHistory> build() {
    return ref.watch(dailyTaskProgressStoreProvider).load();
  }

  /// 키 하나의 변경을 화면에 먼저 반영하고 저장소에 보낸다. (#2886)
  ///
  /// 성공하면 저장소가 돌려준 그날 기록(다른 기기의 변경 포함)으로 바꾼다.
  /// 실패하면 그 키만 원래대로 되돌리고 [AppError] 를 다시 던진다.
  ///
  /// 요청은 **순서대로** 보낸다. 같은 키를 체크했다 푼 요청이 뒤바뀌어 도착하면
  /// 서버에 옛 상태가 남는다. 앞 요청의 실패는 뒤 요청을 막지 않는다.
  Future<void> apply(String date, TaskKeyChange change) {
    final DailyTaskSnapshot? before = state.valueOrNull?.read(date);
    final DailyTaskHistory? current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.withDay(
          date,
          applyTaskKeyChange(saved: before, change: change),
        ),
      );
    }
    final store = ref.read(dailyTaskProgressStoreProvider);
    _inFlight += 1;
    final Future<void> next = _lastSave
        .then<void>((_) {}, onError: (Object _) {})
        .then<void>((_) async {
          try {
            final DailyTaskSnapshot saved = await store.applyKey(date, change);
            final DailyTaskHistory? latest = state.valueOrNull;
            if (latest != null) state = AsyncData(latest.withDay(date, saved));
          } on AppError {
            final DailyTaskHistory? latest = state.valueOrNull;
            if (latest != null) {
              state = AsyncData(
                latest.withDay(
                  date,
                  restoreTaskKey(
                    current: latest.read(date),
                    before: before,
                    key: change.key,
                    carriedOver: change.carriedOver,
                  ),
                ),
              );
            }
            rethrow;
          } finally {
            _inFlight -= 1;
          }
        });
    _lastSave = next;
    return next;
  }
}

/// Provides [DailyTaskHistoryController].
final dailyTaskHistoryProvider =
    AsyncNotifierProvider.autoDispose<
      DailyTaskHistoryController,
      DailyTaskHistory
    >(DailyTaskHistoryController.new, name: 'dailyTaskHistory');
