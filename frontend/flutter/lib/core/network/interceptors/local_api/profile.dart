// 내 정보·프로필·건강 목표·연결 코드 경로(/users/me*).

part of '../local_api_interceptor.dart';

extension _LocalApiProfile on LocalApiInterceptor {
  Future<Map<String, Object?>> _readProfileOverlay() async {
    final raw = await _db.readValue(await _accounts.currentProfileKey());
    if (raw == null || raw.isEmpty) return <String, Object?>{};
    return (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>();
  }

  Future<Map<String, Object?>> _mergedProfile() async {
    final Map<String, Object?>? account = await _accounts.current();
    return <String, Object?>{
      if (account == null) ..._defaultProfile else ..._signedUpProfile(account),
      ...await _readProfileOverlay(),
    };
  }

  /// 프로필 응답 — 서버 `ProfileView` 처럼 실효 단백질 목표를 함께 싣는다(#2898).
  /// 식단 분석이 쓰는 규칙(목표 → 체중 × 1.2g → 60g)과 같은 값이다.
  Future<Map<String, Object?>> _profileView() async {
    final Map<String, Object?> profile = await _mergedProfile();
    return <String, Object?>{
      ...profile,
      'effective_daily_protein_g': demoDietTargets(profile).proteinG,
      // 소셜로 든 데모 회원은 비밀번호 없는 계정처럼 보인다(#3039) — 본인 확인을
      // 소셜 재로그인으로 해 볼 수 있다.
      'has_password': await _hasDemoPassword(),
    };
  }

  /// 지금 계정에 확인할 비밀번호가 있는가. 가입 계정은 늘 있고, 데모 회원은
  /// 소셜로 들어오지 않았으면 있다(#3039).
  Future<bool> _hasDemoPassword() async {
    if (await _accounts.current() != null) return true;
    return (await _accounts.demoLogin()).socialProvider == null;
  }

  /// 이메일 변경·탈퇴 앞의 본인 확인(#3039) — 서버(`reauth`)와 같은 규칙·400
  /// 코드다. 통과하면 null, 막히면 그 400 응답.
  ///
  ///  * 비밀번호 계정: `current_password` 가 가입 계정의 비밀번호(데모 회원은
  ///    들어올 때 친 비밀번호)와 같아야 한다. 없으면 `reauth_required`, 다르면
  ///    `invalid_current_password`.
  ///  * 소셜로 든 데모 회원: `social_provider` 가 들어온 provider 이고
  ///    `social_token` 이 그 데모 토큰(`demo-<provider>-token`)이어야 한다. 없으면
  ///    `reauth_required`, 다르면 `invalid_reauth`.
  ///
  /// 400 인 이유: 토큰은 멀쩡하다 — 401 이면 앱이 세션 만료로 오인한다.
  Future<Response<Object?>?> _reauthRejection(
    RequestOptions options,
    Map<String, Object?> body,
  ) async {
    Response<Object?> reject(String code, String message) => Response<Object?>(
      requestOptions: options,
      statusCode: 400,
      data: <String, Object?>{
        'detail': <String, Object?>{'code': code, 'message': message},
      },
    );
    final Map<String, Object?>? account = await _accounts.current();
    final ({String? password, String? socialProvider}) login = await _accounts
        .demoLogin();
    if (account == null && login.socialProvider != null) {
      final String provider = (body['social_provider'] as String? ?? '').trim();
      final String token = (body['social_token'] as String? ?? '').trim();
      if (provider.isEmpty || token.isEmpty) {
        return reject('reauth_required', '본인 확인을 위해 소셜 계정으로 다시 로그인해 주세요.');
      }
      if (provider != login.socialProvider || token != 'demo-$provider-token') {
        return reject('invalid_reauth', '소셜 계정 확인에 실패했습니다. 다시 로그인해 주세요.');
      }
      return null;
    }
    final String password = body['current_password'] as String? ?? '';
    if (password.isEmpty) {
      return reject('reauth_required', '본인 확인을 위해 현재 비밀번호를 입력해 주세요.');
    }
    // 로그인 없이 둘러보는 데모 회원은 비교할 비밀번호가 없다 — 데모 로그인처럼
    // 비어 있지 않은 값이면 받는다.
    final String? expected = account != null
        ? account['password'] as String?
        : login.password;
    if (expected != null && expected != password) {
      return reject('invalid_current_password', '현재 비밀번호가 일치하지 않습니다.');
    }
    return null;
  }

  Future<void> _mergeProfileOverlay(Map<String, Object?> patch) async {
    final overlay = await _readProfileOverlay();
    overlay.addAll(patch);
    await _db.putValue(
      await _accounts.currentProfileKey(),
      jsonEncode(overlay),
    );
  }

  Future<Response<Object?>> _usersMe(RequestOptions options) async {
    final p = await _mergedProfile();
    return _ok(options, <String, Object?>{
      'id': p['id'],
      'name': p['name'],
      'email': p['email'],
      // 서버와 같은 모양(#3054). 데모 계정은 회원이다.
      'role': 'member',
      // 데모 회원은 동의를 마친 계정으로 둔다(#2819) — 데모 진입마다 동의
      // 화면이 끼면 시연 흐름이 끊긴다.
      'consent_required': false,
      'consent_pending': const <String>[],
    });
  }

  /// POST /users/me/consents — 동의 화면의 저장(#2819). 서버처럼 필수 항목이
  /// 빠지면 아무것도 남기지 않고 422 다. 데모에는 남길 기록이 없다.
  Future<Response<Object?>> _usersMeConsents(RequestOptions options) async {
    final body = _jsonBody(options);
    final Object? raw = body['consents'];
    final List<String> missing = raw is List
        ? _missingConsents(raw)
        : (SignupConsent.memberRequired.toList()..sort());
    if (missing.isNotEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{
          'detail': <String, Object?>{
            'code': 'consent_required',
            'missing': missing,
          },
        },
      );
    }
    return _ok(options, <String, Object?>{
      'consent_required': false,
      'consent_pending': const <String>[],
    });
  }

  Future<Response<Object?>> _usersMeProfile(RequestOptions options) async {
    return _ok(options, await _profileView());
  }

  /// PUT /users/me — 서버(`update_me`)와 같은 거절을 먼저 본다(#2639).
  ///
  ///  * 이메일을 바꾸면 본인 확인(#3039) → 막히면 400. 대소문자만 다르면 바꾼
  ///    것이 아니다. 통과하면 응답에 새 토큰 한 쌍을 싣는다 — 서버가 다른
  ///    기기의 세션을 끊고 이 기기에 새 쌍을 주는 것과 같은 모양이다.
  ///  * 다른 계정이 쓰는 이메일 → 409. 자기 이메일 그대로면 통과한다. 본인 확인
  ///    뒤에 본다.
  ///  * 있던 연락처를 비움 → 422. 서버처럼 `detail` 을 문장으로 준다.
  ///
  /// 거절하면 아무것도 저장하지 않는다.
  Future<Response<Object?>> _usersMeUpdate(RequestOptions options) async {
    final body = _jsonBody(options);
    final Map<String, Object?> current = await _mergedProfile();
    final String? email = (body['email'] as String?)?.trim().toLowerCase();
    final String currentEmail = ((current['email'] as String?) ?? '')
        .trim()
        .toLowerCase();
    final bool emailChanged = email != null && email != currentEmail;
    if (emailChanged) {
      final Response<Object?>? rejected = await _reauthRejection(options, body);
      if (rejected != null) return rejected;
    }
    if (email != null && emailChanged && await _isTakenEmail(email)) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: <String, Object?>{'detail': '이미 사용 중인 이메일입니다.'},
      );
    }
    final String currentPhone = ((current['phone'] as String?) ?? '').trim();
    if (body['phone'] == '' && currentPhone.isNotEmpty) {
      return Response<Object?>(
        requestOptions: options,
        statusCode: 422,
        data: <String, Object?>{'detail': '전화번호는 비울 수 없습니다.'},
      );
    }
    final patch = <String, Object?>{};
    for (final String k in <String>[
      'name',
      'email',
      'phone',
      'birth_date',
      'gender',
    ]) {
      if (body[k] != null) patch[k] = body[k];
    }
    // 키·몸무게만 **키가 있는지**를 본다. 비울 수 있는 두 칸이라 명시적 null 은
    // 지움이고, 값으로 거르면 지운 값이 되살아난다 — 서버도 이 둘만
    // `nullable_fields` 로 둔다(#1941).
    for (final String k in <String>['height_cm', 'weight_kg']) {
      if (body.containsKey(k)) patch[k] = body[k];
    }
    await _mergeProfileOverlay(patch);
    // 가입 계정은 바꾼 이메일로 다음에 로그인한다 — 서버도 같은 사용자 행이다.
    if (email != null && emailChanged) {
      await _accounts.renameCurrent(email);
    }
    return _ok(options, <String, Object?>{
      ...await _profileView(),
      'access_token': emailChanged
          ? 'demo-access-${DateTime.now().microsecondsSinceEpoch}'
          : null,
      'refresh_token': emailChanged ? 'demo-refresh' : null,
    });
  }

  /// PUT /users/me/health-goals — 식단 일일 목표(6종) + 운동 목표(7종)를
  /// 프로필 오버레이에 병합한다(체중/혈압/혈당 목표는 다루지 않음).
  Future<Response<Object?>> _usersMeHealthGoals(RequestOptions options) async {
    final body = _jsonBody(options);
    final patch = <String, Object?>{};
    for (final String k in <String>[
      // MY 건강 목표가 목표 칸과 함께 보내는 건강 목표·자유 입력 목표. 빠져 있어
      // 데모에서 고른 목표가 저장되지 않았다(#1814).
      'conditions',
      'daily_calories',
      'daily_sodium_mg',
      'daily_sugar_g',
      'daily_carbs_g',
      'daily_protein_g',
      'daily_fat_g',
      'weekly_workout_goal',
      'weekly_exercise_minutes_goal',
      'weekly_burn_goal',
      'daily_burn_kcal',
      'weekly_cardio_minutes',
      'weekly_strength_sets',
      'weekly_flexibility_minutes',
    ]) {
      // 값이 아니라 **키가 있는지**를 본다. 명시적 null 은 목표 해제라
      // 오버레이에도 null 로 남아야 한다 — 건너뛰면 지운 목표가 되살아난다.
      if (body.containsKey(k)) patch[k] = body[k];
    }
    _normalizeConditions(patch);
    await _stampMemberHealthChanges(patch);
    await _mergeProfileOverlay(patch);
    return _ok(options, await _profileView());
  }

  /// 회원이 저장한 `conditions` 에서 목표 칩·건강상태·주의사항이 실제로 바뀌었으면
  /// 누가 언제 바꿨는지 [patch] 에 얹는다 — 실서버 `record_member_change` 와 같은
  /// 규칙이다. MY 건강 목표와 온보딩이 함께 쓴다(#2942).
  Future<void> _stampMemberHealthChanges(Map<String, Object?> patch) async {
    // 목표 칩이 실제로 바뀐 저장만 `마지막 변경` 으로 남긴다 — 실서버와 같은
    // 규칙이다(#1832). 목업에는 담당 트레이너 쪽 알림함이 없어 기록만 한다.
    if (patch['conditions'] case final String next) {
      final Map<String, Object?> current = await _mergedProfile();
      final Set<String> before = parseHealthFocus(
        current['conditions'] as String? ?? '',
      ).toSet();
      if (!before.containsAll(parseHealthFocus(next)) ||
          before.length != parseHealthFocus(next).toSet().length) {
        patch['focus_changed_by'] = 'member';
        patch['focus_changed_at'] = nowKst().toIso8601String();
      }
      // 건강상태·주의사항은 따로 남긴다 — 조각 순서만 바뀐 저장은 아니다(#2942).
      Set<String> notes(String raw) => healthFocusNotes(
        raw,
      ).split(', ').where((String t) => t.isNotEmpty).toSet();
      final Set<String> notesBefore = notes(
        current['conditions'] as String? ?? '',
      );
      final Set<String> notesAfter = notes(next);
      if (notesBefore.length != notesAfter.length ||
          !notesBefore.containsAll(notesAfter)) {
        patch['notes_changed_by'] = 'member';
        patch['notes_changed_at'] = nowKst().toIso8601String();
      }
    }
  }

  /// GET /users/me/deletion-preview — 탈퇴하면 사라지거나 취소되는 것의 건수(#3006).
  ///
  /// 포인트·쿠폰은 이 목업이 들고 있는 원장·쿠폰함에서 센다. 데모의 PT 예약과
  /// 상담 요청은 목 헬스장·상담 저장소가 들고 있어 여기서는 0 으로 두고, 앱의
  /// 탈퇴 화면이 그 저장소에서 센 값으로 덮는다(`withdrawPreviewLoaderProvider`).
  Future<Response<Object?>> _usersMeDeletionPreview(
    RequestOptions options,
  ) async {
    final int activeCoupons = _coupons
        .couponsJson()
        .where((Map<String, Object?> c) => c['status'] == 'issued')
        .length;
    return _ok(options, <String, Object?>{
      'points': _points.balance,
      'active_coupons': activeCoupons,
      'upcoming_reservations': 0,
      'pending_consultations': 0,
    });
  }

  /// DELETE /users/me — withdraw. The demo wipes the profile overlay so a
  /// subsequent session starts clean, mirroring FastAPI's cascade delete.
  ///
  /// The body's `reasons` (#2019) are dropped here on purpose: the server keeps
  /// them in a table nobody reads back, and the demo has no such table. The
  /// withdrawal itself is what the demo has to reproduce.
  ///
  /// 가입 계정이 탈퇴하면 계정째 지운다(#2665) — 같은 이메일로 다시 가입할 수
  /// 있고, 그 비밀번호로는 더 로그인되지 않는다.
  ///
  /// 탈퇴는 언제나 본인 확인을 거친다(#3039) — 막히면 400 이고 아무것도 지우지
  /// 않는다.
  Future<Response<Object?>> _usersMeDelete(RequestOptions options) async {
    final Response<Object?>? rejected = await _reauthRejection(
      options,
      _jsonBody(options),
    );
    if (rejected != null) return rejected;
    if (await _accounts.current() != null) {
      await _accounts.removeCurrent();
      return _ok(options, <String, Object?>{'status': 'deleted'});
    }
    await _db.putValue(DemoAccounts.demoProfileKey, '');
    await _accounts.rememberDemoLogin();
    return _ok(options, <String, Object?>{'status': 'deleted'});
  }

  /// POST /users/me/onboarding — first-run setup. Persists any provided
  /// fields and marks the profile onboarded; mirrors FastAPI's partial save.
  Future<Response<Object?>> _usersMeOnboarding(RequestOptions options) async {
    final body = _jsonBody(options);
    final patch = <String, Object?>{};
    for (final String k in <String>[
      'name',
      'birth_date',
      'gender',
      'height_cm',
      'weight_kg',
      'conditions',
      // 목표 열 칸은 PUT /users/me/health-goals 가 쓰는 열과 같다 — 온보딩이
      // 채운 값을 MY 건강 목표가 그대로 이어 고친다.
      'daily_calories',
      'daily_sodium_mg',
      'daily_sugar_g',
      'daily_carbs_g',
      'daily_protein_g',
      'daily_fat_g',
      'daily_burn_kcal',
      'weekly_cardio_minutes',
      'weekly_strength_sets',
      'weekly_flexibility_minutes',
    ]) {
      if (body[k] != null) patch[k] = body[k];
    }
    patch['onboarded'] = true;
    _normalizeConditions(patch);
    // 처음 고른 목표·적은 주의사항도 회원이 정한 것이다 — 실서버처럼 남긴다.
    await _stampMemberHealthChanges(patch);
    await _mergeProfileOverlay(patch);
    return _ok(options, await _profileView());
  }

  /// POST /users/me/onboarding/skip — 첫 설정 건너뛰기만 남긴다(#2855). 서버처럼
  /// 다른 값은 건드리지 않고 `onboarded` 도 그대로 둔다.
  Future<Response<Object?>> _usersMeOnboardingSkip(
    RequestOptions options,
  ) async {
    await _mergeProfileOverlay(<String, Object?>{'onboarding_skipped': true});
    return _ok(options, await _mergedProfile());
  }

  Future<Response<Object?>> _pairingCodeIssue(RequestOptions options) async {
    return _ok(options, <String, Object?>{
      'code': _demoPairingCode,
      'expires_at': nowKst().add(const Duration(minutes: 5)).toIso8601String(),
      'expires_in_seconds': 5 * 60,
    });
  }

  Future<Response<Object?>> _pairingCodeRevoke(RequestOptions options) async {
    // 데모의 코드는 고정이라 버릴 것이 없다. 그래도 받아 주지 않으면 시트를
    // 닫을 때마다 실 네트워크로 새어 나간다.
    return Response<Object?>(requestOptions: options, statusCode: 204);
  }

  Future<Response<Object?>> _usersMeHealth(RequestOptions options) async {
    // 끝난 주의 챌린지를 먼저 판정해 보상이 든 잔액을 싣는다(#1789).
    await _settleChallenges();
    // 이름·이메일은 `PUT /users/me` 가 저장한 프로필에서 읽는다(#2661) — 서버도
    // 같은 사용자 행을 읽으므로 내 프로필에서 바꾼 값이 MY 카드에 보인다.
    // 모양은 실서버와 같다 — 위험 문구·순위·설정 메뉴는 싣지 않는다(#2903).
    final Map<String, Object?> me = await _mergedProfile();
    return _ok(options, <String, Object?>{
      'profile': <String, Object?>{
        'id': me['id'],
        'name': me['name'],
        'email': me['email'],
      },
      // 원장의 잔액 — 적립·회수가 그대로 보인다(#1786).
      'activity_points': _points.balance,
    });
  }
}

const Map<String, Object?> _defaultProfile = <String, Object?>{
  'id': 'user-7d4e9a2c5f18',
  'name': '김민수',
  'email': 'minsu@oncare.com',
  'phone': '010-1234-5678',
  'birth_date': '1990-01-15',
  // 데모 회원은 남성이다 — 트레이너 앱의 김민수와 같은 사람이라 두 앱이
  // 같은 값을 말해야 한다 (#1140).
  'gender': 'male',
  'height_cm': 175.0,
  'weight_kg': 72.0,
  // 건강 목표(#1814) — 트레이너 앱이 이 회원의 목표로 보여 주는 값과 같다.
  'conditions': '체중 감량, 혈압 관리',
  'daily_calories': 2000,
  'daily_sodium_mg': 2000,
  'daily_sugar_g': 50,
  'daily_carbs_g': 275,
  'daily_protein_g': 100,
  'daily_fat_g': 55,
  'weekly_workout_goal': null,
  'weekly_exercise_minutes_goal': null,
  'weekly_burn_goal': null,
  // 운동 탭이 견주는 목표 (#1139) — 비워 두면 앱이 권장값을 쓴다.
  'daily_burn_kcal': null,
  'weekly_cardio_minutes': null,
  'weekly_strength_sets': null,
  'weekly_flexibility_minutes': null,
  'onboarded': true,
  'onboarding_skipped': false,
};

/// 이 데모에서 가입한 계정의 시작 프로필 — 실서버의 새 계정처럼 가입 때 받은
/// 값만 있고, 첫 설정 전이다(#2665). 목표는 비워 두면 앱이 권장값을 쓴다.
Map<String, Object?> _signedUpProfile(Map<String, Object?> account) {
  final String phone = account['phone'] as String? ?? '';
  return <String, Object?>{
    for (final String k in _defaultProfile.keys) k: null,
    'id': account['id'],
    'name': account['name'],
    'email': account['email'],
    'phone': phone.isEmpty ? null : phone,
    'onboarded': false,
  };
}

/// [raw] 가 목록이면 그 안에 없는 회원 필수 동의 항목, 목록이 아니면(안
/// 보냄) 빈 목록. 서버(`signup_consent.missing_required`)처럼 정렬해 준다.
List<String> _missingConsents(Object? raw) {
  if (raw is! List) return const <String>[];
  final Set<String> given = <String>{for (final Object? k in raw) '$k'};
  return SignupConsent.memberRequired.difference(given).toList()..sort();
}

/// 옛 질환 이름(고혈압·당뇨 등)을 새 건강 목표로 정리한다 — 서버 스키마가
/// 저장 전에 하는 정리와 같다(#1814).
void _normalizeConditions(Map<String, Object?> patch) {
  if (patch['conditions'] case final String raw) {
    patch['conditions'] = normalizeHealthFocusText(raw);
  }
}

/// 데모 모드의 동기화 코드 — 김민수(데모 회원)의 고정 값이다. (#1634)
///
/// **트레이너 앱의 `demoAlreadyLinkedPairingCode` 와 같은 값이어야 한다.**
/// 두 앱은 서로 다른 패키지라 상수를 나눠 가질 수 없고, 데모에는 코드를
/// 발급·소비할 서버도 없다. 여기서 무작위로 뽑으면 회원 화면이 보여 준
/// 여섯 자리를 트레이너 데모가 영영 알아보지 못한다.
///
/// 실서비스에서는 서버가 발급한 한 값을 두 화면이 함께 본다.
const String _demoPairingCode = '567812';
