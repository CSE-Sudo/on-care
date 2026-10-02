import 'dart:convert';

import 'package:oncare/core/storage/app_database.dart';

/// 데모에서 가입한 계정과 지금 로그인한 계정. (#2665)
///
/// 데모 세계의 기록(식단·운동·채팅 등)은 김민수 한 명의 것이다. 가입한 계정은
/// **프로필만** 따로 갖는다 — 이름·이메일·연락처와 첫 설정 값이다. 그래서 새
/// 계정은 실서버처럼 첫 설정을 거치고, 내 프로필·MY 카드에 자기 이름이 보인다.
///
/// 가입하지 않은 이메일로 로그인하면 지금처럼 데모 회원(김민수)으로 들어간다 —
/// 아무 값으로나 둘러볼 수 있던 데모 입장 방식을 그대로 둔다.
///
/// 값은 `AppKeyValues` 에 둔다. 목업 인터셉터와 목업 MY 저장소가 같은 판단을
/// 해야 해서 한곳에 모았다.
class DemoAccounts {
  const DemoAccounts(this._db);

  final AppDatabase _db;

  static const String _accountsKey = 'demo_accounts';
  static const String _currentKey = 'demo_current_account';

  /// 데모 회원(김민수)의 프로필 오버레이 키. 예전부터 쓰던 이름 그대로다.
  static const String demoProfileKey = 'profile_overlay';

  /// 데모 회원의 이메일. 이 주소로는 가입할 수 없다.
  static const String demoEmail = 'minsu@oncare.com';

  static String normalize(String email) => email.trim().toLowerCase();

  Future<Map<String, Map<String, Object?>>> _all() async {
    final String? raw = await _db.readValue(_accountsKey);
    if (raw == null || raw.isEmpty) return <String, Map<String, Object?>>{};
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, Map<String, Object?>>{};
    return <String, Map<String, Object?>>{
      for (final MapEntry<Object?, Object?> e in decoded.entries)
        if (e.key is String && e.value is Map)
          e.key! as String: (e.value! as Map).cast<String, Object?>(),
    };
  }

  Future<void> _save(Map<String, Map<String, Object?>> all) =>
      _db.putValue(_accountsKey, jsonEncode(all));

  /// 가입한 계정. 없으면 null.
  Future<Map<String, Object?>?> find(String email) async =>
      (await _all())[normalize(email)];

  /// 이 데모에서 가입한 계정의 이메일 전부.
  Future<Set<String>> emails() async => (await _all()).keys.toSet();

  Future<void> add({
    required String id,
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    final Map<String, Map<String, Object?>> all = await _all();
    all[normalize(email)] = <String, Object?>{
      'id': id,
      'email': email.trim(),
      'password': password,
      'name': name,
      'phone': phone,
    };
    await _save(all);
  }

  /// 지금 로그인한 가입 계정. 데모 회원으로 들어와 있으면 null.
  Future<Map<String, Object?>?> current() async {
    final String? email = await _db.readValue(_currentKey);
    if (email == null || email.isEmpty) return null;
    return (await _all())[email];
  }

  /// [email] 로 로그인한다. null 이면 데모 회원이다.
  Future<void> signIn(String? email) async {
    if (email == null) {
      await _db.deleteValue(_currentKey);
    } else {
      await _db.putValue(_currentKey, normalize(email));
    }
  }

  /// 지금 계정의 이메일을 바꾼다 — 다음 로그인도 새 주소로 된다.
  Future<void> renameCurrent(String newEmail) async {
    final String? old = await _db.readValue(_currentKey);
    if (old == null || old.isEmpty) return;
    final Map<String, Map<String, Object?>> all = await _all();
    final Map<String, Object?>? account = all.remove(old);
    if (account == null) return;
    account['email'] = newEmail.trim();
    all[normalize(newEmail)] = account;
    await _save(all);
    await _db.putValue(_currentKey, normalize(newEmail));
  }

  /// 지금 계정을 지운다(탈퇴). 프로필도 함께 지우고 데모 회원으로 돌아간다.
  Future<void> removeCurrent() async {
    final Map<String, Object?>? account = await current();
    if (account == null) return;
    final Map<String, Map<String, Object?>> all = await _all()
      ..remove(normalize(account['email']! as String));
    await _save(all);
    await _db.deleteValue(profileKeyOf(account));
    await signIn(null);
  }

  /// [account] 의 프로필 오버레이 키. null 이면 데모 회원의 것이다.
  static String profileKeyOf(Map<String, Object?>? account) =>
      account == null ? demoProfileKey : 'profile_overlay:${account['id']}';

  /// 지금 계정의 프로필 오버레이 키.
  Future<String> currentProfileKey() async => profileKeyOf(await current());
}
