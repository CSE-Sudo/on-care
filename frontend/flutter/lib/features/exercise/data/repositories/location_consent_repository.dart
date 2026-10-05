import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 위치정보 이용 동의(선택 동의 `location`)를 읽고 쓴다. (#3136)
///
/// 헬스장 찾기는 기기의 현재 좌표를 받아 주변 검색에 쓴다. OS 권한 창은 기기
/// 차원의 허락일 뿐이라, 그 앞에서 서비스 차원의 동의를 따로 받는다. 동의가
/// 없으면 앱은 OS 권한을 묻지도, 좌표를 읽지도 않는다.
///
/// 두 구현이 있다.
///
///  * [DioLocationConsentRepository] — 실사용자. 동의·철회를 서버에 시각·문서
///    버전과 함께 남긴다(`/users/me/consents/location`).
///  * [LocalLocationConsentRepository] — 데모 세션. 데모 회원 계정은 여럿이 함께
///    쓰므로 서버에 남기면 한 사람의 동의가 다른 사람에게 이어진다. 기기에만 둔다.
abstract class LocationConsentRepository {
  /// 지금 문서 버전에 철회하지 않은 동의가 있는가.
  Future<bool> fetch();

  /// 동의를 남긴다.
  Future<void> agree();

  /// 동의를 철회한다. 동의한 적이 없어도 성공으로 본다.
  Future<void> revoke();
}

/// 실 백엔드 — `GET`·`PUT`·`DELETE /users/me/consents/location`.
class DioLocationConsentRepository implements LocationConsentRepository {
  /// Creates the API-backed source.
  const DioLocationConsentRepository(this._dio);

  final Dio _dio;

  static const String path = '/users/me/consents/location';

  @override
  Future<bool> fetch() async {
    final Response<Map<String, Object?>> res = await _dio
        .get<Map<String, Object?>>(path);
    return _agreed(res.data);
  }

  @override
  Future<void> agree() async {
    final Response<Map<String, Object?>> res = await _dio
        .put<Map<String, Object?>>(path);
    // 서버가 동의로 받아들이지 않았다면 성공으로 보지 않는다 — 동의 없이
    // 권한 창으로 넘어가면 안 된다.
    if (!_agreed(res.data)) {
      throw StateError('location consent was not recorded');
    }
  }

  @override
  Future<void> revoke() async {
    await _dio.delete<Map<String, Object?>>(path);
  }

  /// 응답의 `agreed` 가 정확히 `true` 일 때만 동의로 읽는다. 필드가 빠지거나
  /// 모양이 다르면 동의가 없는 것으로 본다 — 모르는 상태에서 위치를 읽지 않는다.
  static bool _agreed(Map<String, Object?>? body) => body?['agreed'] == true;
}

/// 데모 세션 — 기기(SharedPreferences)에만 남긴다.
class LocalLocationConsentRepository implements LocationConsentRepository {
  /// Creates the device-only source over [_prefs].
  const LocalLocationConsentRepository(this._prefs);

  final SharedPreferences _prefs;

  /// 저장 키. 문서 버전이 바뀌면 키도 바꿔 다시 묻는다.
  static const String key = 'location_consent_2026-10-05';

  @override
  Future<bool> fetch() async => _prefs.getBool(key) ?? false;

  @override
  Future<void> agree() async {
    await _prefs.setBool(key, true);
  }

  @override
  Future<void> revoke() async {
    await _prefs.remove(key);
  }
}
