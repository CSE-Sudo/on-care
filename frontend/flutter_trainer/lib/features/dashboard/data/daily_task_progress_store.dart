import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
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
  Future<void> save(String date, DailyTaskSnapshot snapshot);
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
      }),
    );
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
}

DailyTaskSnapshot? _decode(
  Object? total,
  Object? completedToday,
  Object? completedCarriedOver,
  Object? pendingKeys,
  Object? dismissedKeys,
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
  };
}

/// Provides the store for the current mode.
final dailyTaskProgressStoreProvider = Provider<DailyTaskProgressStore>((ref) {
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

  @override
  Future<DailyTaskHistory> build() {
    return ref.watch(dailyTaskProgressStoreProvider).load();
  }

  /// 화면 상태를 먼저 반영하고 저장한다.
  ///
  /// 저장은 **순서대로** 보낸다. 연달아 누른 체크의 요청이 뒤바뀌어 도착하면
  /// 서버에 옛 상태가 남는다. 앞 요청의 실패는 뒤 요청을 막지 않는다 — 매번
  /// 그날 전체를 보내므로 다음 저장이 성공하면 따라잡는다.
  Future<void> save(String date, DailyTaskSnapshot snapshot) {
    final current = state.valueOrNull;
    if (current != null) state = AsyncData(current.withDay(date, snapshot));
    final store = ref.read(dailyTaskProgressStoreProvider);
    final Future<void> next = _lastSave
        .then<void>((_) {}, onError: (Object _) {})
        .then<void>((_) => store.save(date, snapshot));
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
