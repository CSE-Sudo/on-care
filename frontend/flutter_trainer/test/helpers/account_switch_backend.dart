// 계정 전환 테스트용 가짜 서버와 로그인 저장소. (#2285)
//
// 한 탭에서 트레이너 A 로 로그인했다가 로그아웃하고 트레이너 B 로 다시 들어가는
// 흐름을 **실제 provider 정의 그대로** 돌려 보기 위한 도구다. 저장소 provider 를
// override 하지 않는다 — override 하면 계정 범위를 거는 코드 자체가 빠져 검증할
// 것이 없어진다. 대신 맨 아래의 HTTP 만 바꾼다: 요청에 붙은 토큰으로 어느
// 계정의 요청인지 가려 그 계정의 데이터만 돌려준다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/network/interceptors/auth_interceptor.dart';
import 'package:oncare_trainer/features/auth/data/repositories/dio_trainer_auth_repository.dart';
import 'package:oncare_trainer/features/auth/domain/entities/auth_tokens.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/trainer_auth_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// 실서버 모드 — 저장소 provider 가 Dio 구현을 고른다.
const AppConfig kAccountSwitchConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: false,
);

/// 테스트에 등장하는 트레이너 계정.
enum TestTrainer {
  a('a', 'trainer-a@oncare.test', '에이 트레이너'),
  b('b', 'trainer-b@oncare.test', '비 트레이너');

  const TestTrainer(this.key, this.email, this.displayName);

  /// 토큰·id 에 붙는 짧은 표식.
  final String key;
  final String email;
  final String displayName;

  /// 이 계정이 로그인하면 받는 액세스 토큰.
  String get accessToken => 'access-$key';

  /// 이 계정의 회원 id — 계정마다 다르다.
  String get memberId => 'member-$key';

  /// 이 계정의 회원 이름. 화면·값 검사에서 계정을 가르는 표식이다.
  String get memberName => '$displayName의 회원';

  String get notificationTitle => '$displayName 알림';

  String get templateName => '$displayName 템플릿';

  /// 주간 리포트의 예약 수 — 계정마다 달라 섞이면 바로 드러난다.
  int get sessionsBooked => this == a ? 3 : 7;

  /// 메시지 알림 설정 — A 는 기본값(켜짐)과 다르게 꺼 두었다.
  bool get newMessageAlerts => this == b;

  /// 끼니 사진 바이트.
  List<int> get photoBytes => this == a ? <int>[1, 1, 1] : <int>[2, 2, 2];

  static TestTrainer? fromToken(String? header) {
    for (final TestTrainer t in values) {
      if (header == 'Bearer ${t.accessToken}') return t;
    }
    return null;
  }

  static TestTrainer fromEmail(String email) =>
      values.firstWhere((TestTrainer t) => t.email == email);
}

/// 요청 토큰에 따라 계정별 데이터를 주는 가짜 서버.
///
/// 토큰이 없거나 모르는 토큰이면 401 이다 — 로그아웃한 뒤 날아간 요청이 이전
/// 계정의 데이터를 받아 오는 일이 없음을 서버 쪽에서도 보장한다.
class FakeTrainerBackend implements HttpClientAdapter {
  /// 받은 요청 `(계정, 경로)` 기록. 계정이 없으면 null.
  final List<({TestTrainer? account, String path})> requests =
      <({TestTrainer? account, String path})>[];

  /// [path] 로 들어온 요청 수.
  int count(String path) => requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final TestTrainer? account = TestTrainer.fromToken(
      options.headers['Authorization'] as String?,
    );
    final String path = options.uri.path.replaceFirst('/v1', '');
    requests.add((account: account, path: path));
    if (account == null) {
      return _json(<String, Object?>{'detail': 'unauthorized'}, 401);
    }
    if (path == '/trainer/clients') {
      return _json(<Object?>[
        <String, Object?>{'id': account.memberId, 'name': account.memberName},
      ]);
    }
    if (path == '/trainer/notifications') {
      return _json(<Object?>[
        <String, Object?>{
          'id': '${account.memberId}-n1',
          'title': account.notificationTitle,
          'body': '',
          'category': 'message',
          'read': false,
          'created_at': '2026-09-20T09:00:00Z',
        },
      ]);
    }
    if (path == '/trainer/notifications/unread-count') {
      return _json(<String, Object?>{'unread': 1});
    }
    if (path == '/trainer/program-templates') {
      return _json(<Object?>[
        <String, Object?>{
          'id': '${account.memberId}-t1',
          'name': account.templateName,
          'goal': '',
          'exercises': <Object?>[],
        },
      ]);
    }
    if (path == '/trainer/me/settings') {
      return _json(<String, Object?>{
        'notify_new_message': account.newMessageAlerts,
      });
    }
    if (path.startsWith('/trainer/clients/') && path.endsWith('/report')) {
      // 다른 계정의 회원 리포트는 서버가 거절한다(권한 경계).
      if (!path.contains(account.memberId)) {
        return _json(<String, Object?>{'detail': 'forbidden'}, 403);
      }
      return _json(<String, Object?>{
        'week_start': options.queryParameters['week_start'],
        'sessions_booked': account.sessionsBooked,
        'sessions_done': 0,
      });
    }
    if (path.startsWith('/trainer/clients/') && path.contains('/photos/')) {
      return ResponseBody.fromBytes(account.photoBytes, 200);
    }
    return _json(<String, Object?>{'detail': 'not found'}, 404);
  }

  ResponseBody _json(Object? body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// 이메일로 계정을 가르는 로그인 저장소.
class FakeTrainerAuthRepository implements TrainerAuthRepository {
  /// 서버에 폐기를 요청한 갱신 토큰.
  final List<String> revoked = <String>[];

  /// 참이면 `/me` 가 만료로 거절한다 — 복구가 만료로 끝나는 길을 연다.
  bool rejectProfile = false;

  TrainerAuthTokens _tokensFor(TestTrainer t) =>
      TrainerAuthTokens(access: t.accessToken, refresh: 'refresh-${t.key}');

  @override
  Future<TrainerAuthTokens> login({
    required String email,
    required String password,
  }) async => _tokensFor(TestTrainer.fromEmail(email));

  @override
  Future<TrainerAuthTokens> register({
    required String email,
    required String password,
    required String name,
  }) async => _tokensFor(TestTrainer.fromEmail(email));

  @override
  Future<TrainerAuthTokens> socialLogin({
    required String provider,
    required String token,
  }) async => _tokensFor(TestTrainer.a);

  @override
  Future<TrainerAuthTokens> refresh(String refreshToken) async =>
      throw const AuthException(AuthFailure.sessionExpired);

  @override
  Future<void> logout(String refreshToken) async => revoked.add(refreshToken);

  @override
  Future<TrainerProfile> fetchProfile(String accessToken) async {
    if (rejectProfile) throw const AuthException(AuthFailure.sessionExpired);
    final TestTrainer t = TestTrainer.values.firstWhere(
      (TestTrainer t) => t.accessToken == accessToken,
    );
    return seedTrainerProfile.copyWith(name: t.displayName, email: t.email);
  }
}

/// 가짜 서버·로그인 저장소를 붙인 컨테이너.
///
/// [persisted] 는 브라우저 저장소에 남아 있던 토큰 — 주면 앱을 다시 연 것처럼
/// 복구부터 한다.
({
  ProviderContainer container,
  FakeTrainerBackend backend,
  FakeTrainerAuthRepository auth,
})
makeAccountSwitchContainer({
  TestTrainer? persisted,
  List<Override> extraOverrides = const <Override>[],
}) {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    if (persisted != null) 'access_token': persisted.accessToken,
    if (persisted != null) 'refresh_token': 'refresh-${persisted.key}',
  });
  final FakeTrainerBackend backend = FakeTrainerBackend();
  final FakeTrainerAuthRepository auth = FakeTrainerAuthRepository();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(kAccountSwitchConfig),
      trainerAuthRepositoryProvider.overrideWithValue(auth),
      dioProvider.overrideWith((ref) {
        final Dio dio = Dio(
          BaseOptions(
            baseUrl: kAccountSwitchConfig.apiBaseUrl,
            validateStatus: (int? status) => status != null && status < 400,
          ),
        );
        dio.httpClientAdapter = backend;
        dio.interceptors.add(AuthInterceptor(ref));
        return dio;
      }),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  return (container: container, backend: backend, auth: auth);
}

/// 로그인·복구의 비동기 사슬과 첫 응답이 끝나기를 기다린다.
Future<void> settleAsync() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

/// [condition] 이 참이 될 때까지 기다린다. 첫 실행의 느린 준비에도 흔들리지
/// 않게 고정 지연 대신 쓴다.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      fail('기다린 조건이 ${timeout.inSeconds}초 안에 참이 되지 않았다');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
