import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 알림 수신 설정 항목. 키는 서버와 공유하는 계약이다. (#489)
///
/// 화면 라벨은 ARB 에서 키로 찾으므로 여기에 두지 않는다.
class NotificationSettingItem {
  /// Creates a toggle definition.
  const NotificationSettingItem(this.key, this.fallback);

  /// 저장 키. 로컬(SharedPreferences)과 서버 응답 필드가 이 값을 공유한다 —
  /// 서버는 `notif_` 접두사를 뗀 이름을 쓰므로 매핑은 repository 가 한다.
  final String key;

  /// 한 번도 바꾼 적 없을 때의 값.
  final bool fallback;
}

/// 화면에 보이는 순서 그대로. 주간 리포트만 기본 꺼짐이다.
///
/// 모든 항목은 서버가 실제로 만드는 알림을 켜고 끈다. 식단 기록·AI 코칭
/// (`notif_diet_log`·`notif_ai_coaching`)은 그 알림을 만드는 곳이 서버에 없어
/// 뺐다(#2854) — 켜 두면 올 것으로 기대하는데 아무것도 오지 않았다. 서버는 이미
/// 저장된 값 때문에 응답에 두 필드를 남기지만, 앱은 읽지도 보내지도 않는다.
const List<NotificationSettingItem> kNotificationSettingItems =
    <NotificationSettingItem>[
      NotificationSettingItem('notif_exercise_reminder', true),
      NotificationSettingItem('notif_trainer_message', true),
      NotificationSettingItem('notif_weekly_report', false),
    ];

/// 알림 수신 설정을 읽고 쓴다.
///
/// 두 구현이 [notificationSettingsRepositoryProvider] 뒤에 있고 `useMockApi` 로
/// 갈린다.
///
///  * [LocalNotificationSettingsRepository] — 데모/목. 기기에만 남는다.
///  * [DioNotificationSettingsRepository] — 실 백엔드. **계정 단위**라 기기를
///    바꿔도 유지되고, 무엇보다 서버가 설정을 알아야 알림을 만들 때 끌 수 있다.
///
/// 데모를 로컬로 남겨 두는 이유: 데모에는 설정을 저장할 백엔드가 없다. 서버로
/// 보내면 설정 화면이 로딩 실패로 뜨고, 지금 화면과 달라진다.
abstract class NotificationSettingsRepository {
  /// 전체 설정. 저장한 적 없는 항목은 기본값으로 채워 온다.
  Future<Map<String, bool>> fetch();

  /// 한 항목을 바꾼다.
  Future<void> setValue(String key, bool value);
}

/// 데모/목 — 기존 동작 그대로 SharedPreferences 에 남긴다.
class LocalNotificationSettingsRepository
    implements NotificationSettingsRepository {
  /// Creates the local source over [_prefs].
  const LocalNotificationSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<Map<String, bool>> fetch() async => <String, bool>{
    for (final NotificationSettingItem item in kNotificationSettingItems)
      item.key: _prefs.getBool(item.key) ?? item.fallback,
  };

  @override
  Future<void> setValue(String key, bool value) async {
    await _prefs.setBool(key, value);
  }
}

/// 실 백엔드 — `GET`/`PUT /users/me/notification-settings`.
class DioNotificationSettingsRepository
    implements NotificationSettingsRepository {
  /// Creates the API-backed source.
  const DioNotificationSettingsRepository(this._dio);

  final Dio _dio;

  static const String _path = '/users/me/notification-settings';

  @override
  Future<Map<String, bool>> fetch() async {
    final Response<Map<String, Object?>> res = await _dio
        .get<Map<String, Object?>>(_path);
    final Map<String, Object?> body = res.data ?? const <String, Object?>{};
    return <String, bool>{
      for (final NotificationSettingItem item in kNotificationSettingItems)
        item.key: switch (body[_wireName(item.key)]) {
          final bool value => value,
          // 서버가 모르는 항목은 기본값으로 둔다 — 배포 시점이 어긋나
          // 필드가 빠져 와도 토글이 사라지지 않는다.
          _ => item.fallback,
        },
    };
  }

  @override
  Future<void> setValue(String key, bool value) async {
    await _dio.put<Map<String, Object?>>(
      _path,
      data: <String, Object?>{_wireName(key): value},
    );
  }

  /// `notif_trainer_message` → `trainer_message`. 서버 필드는 접두사가 없다.
  static String _wireName(String key) => key.replaceFirst('notif_', '');
}

/// 데모/목은 로컬, 실모드는 백엔드.
final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>((ref) {
      if (ref.watch(appConfigProvider).useMockApi) {
        return LocalNotificationSettingsRepository(
          ref.watch(sharedPreferencesProvider),
        );
      }
      return DioNotificationSettingsRepository(ref.watch(dioProvider));
    }, name: 'notificationSettingsRepository');

/// 저장 전이라도 화면이 바로 그릴 수 있는 기본값.
Map<String, bool> defaultNotificationSettings() => <String, bool>{
  for (final NotificationSettingItem item in kNotificationSettingItems)
    item.key: item.fallback,
};

/// 알림 설정 화면이 그리는 상태.
class NotificationSettingsState {
  /// Creates a snapshot of the toggles.
  const NotificationSettingsState({
    required this.values,
    this.loadFailed = false,
  });

  /// 키 → 켜짐 여부. 저장하는 동안에도 바꾼 값이 들어 있다(낙관적 갱신).
  final Map<String, bool> values;

  /// 서버 값을 못 읽어 기본값으로 그리는 중인지. 화면은 이때 실패 안내와
  /// 다시 시도를 보인다 — 기본값을 서버 값처럼 보여 주면 회원이 실제 설정과
  /// 다른 화면을 보고 토글한다(#2851).
  final bool loadFailed;

  /// [key] 의 현재 값. 모르는 키는 항목 기본값.
  bool valueOf(String key) =>
      values[key] ??
      kNotificationSettingItems
          .firstWhere(
            (NotificationSettingItem item) => item.key == key,
            orElse: () => NotificationSettingItem(key, true),
          )
          .fallback;

  /// [key] 만 [value] 로 바꾼 사본.
  NotificationSettingsState withValue(String key, bool value) =>
      NotificationSettingsState(
        values: <String, bool>{...values, key: value},
        loadFailed: loadFailed,
      );
}

/// 알림 설정 조회·저장을 한 곳에서 맡는다(#2851).
///
/// 예전에는 provider 가 최초 조회값만 들고 있고, 바꾼 값은 화면 State 에만
/// 남았다. 화면을 나갔다 들어오면 옛 값이 보여, 회원이 다시 누르는 순간 서버
/// 값이 뒤집혔다. 이제 저장 결과가 이 캐시에 남으므로 다시 들어와도 마지막 값이
/// 보인다.
class NotificationSettingsController
    extends AsyncNotifier<NotificationSettingsState> {
  /// 키별 최신 요청 번호. 늦게 도착한 옛 실패가 최신 상태를 되돌리지 않게 한다.
  final Map<String, int> _requestSeq = <String, int>{};

  @override
  Future<NotificationSettingsState> build() async {
    try {
      final Map<String, bool> values = await ref
          .watch(notificationSettingsRepositoryProvider)
          .fetch();
      return NotificationSettingsState(values: values);
    } on Object {
      // 토글은 그대로 쓸 수 있게 기본값으로 그리되, 실패했다는 사실을 남긴다
      // — 설정을 못 읽었다고 토글을 감추면 끌 방법이 사라진다.
      return NotificationSettingsState(
        values: defaultNotificationSettings(),
        loadFailed: true,
      );
    }
  }

  NotificationSettingsState get _current =>
      state.valueOrNull ??
      NotificationSettingsState(values: defaultNotificationSettings());

  /// [key] 를 [value] 로 바꾼다. 화면은 즉시 바뀌고, 저장이 실패하면 **직전
  /// 값**으로 돌아간다. 실패를 알려야 하면 false.
  ///
  /// 이 요청을 기다리는 사이 같은 키를 또 바꿨다면 옛 실패는 무시한다(true).
  Future<bool> setValue(String key, bool value) async {
    final bool previous = _current.valueOf(key);
    final int seq = (_requestSeq[key] ?? 0) + 1;
    _requestSeq[key] = seq;
    state = AsyncData<NotificationSettingsState>(
      _current.withValue(key, value),
    );
    try {
      await ref
          .read(notificationSettingsRepositoryProvider)
          .setValue(key, value);
      return true;
    } on Object {
      if (_requestSeq[key] != seq) return true;
      // 되돌릴 곳은 최초 조회값이 아니라 직전 값이다 — 한 번 저장에 성공한 뒤
      // 다음 저장이 실패하면 최초값으로 돌아가 서버와 어긋난다.
      state = AsyncData<NotificationSettingsState>(
        _current.withValue(key, previous),
      );
      return false;
    }
  }
}

/// 현재 설정. 앱 세션 동안 유지되고 저장 결과로 갱신된다. 계정이 바뀌면
/// 세션 초기화가 무효화한다.
final notificationSettingsProvider =
    AsyncNotifierProvider<
      NotificationSettingsController,
      NotificationSettingsState
    >(NotificationSettingsController.new, name: 'notificationSettings');
