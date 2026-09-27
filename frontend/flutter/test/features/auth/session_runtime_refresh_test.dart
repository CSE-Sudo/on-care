/// 실행 중 접근 토큰이 만료됐을 때의 세션 — 컨트롤러·인터셉터·저장소 연동. (#1546)
///
/// 앱을 켜 둔 채 하루가 지나면 접근 토큰이 만료된다. 예전에는 갱신이 앱 시작
/// 복구에만 있어서, 화면은 로그인 상태인데 모든 요청이 실패했다. 여기서는 실제
/// 세션 컨트롤러와 인증 인터셉터를 가짜 서버에 붙여 다음을 고정한다.
///
///  * 만료되면 갱신 토큰으로 한 번 회전하고 원 요청이 성공한다.
///  * 동시 401 도 회전은 한 번 — 일회용 갱신 토큰을 두 번 쓰지 않는다.
///  * 갱신이 401/403 으로 거부되면 토큰을 지우고 로그아웃 상태로 간다.
///  * 연결 실패·5xx 면 토큰을 지키고 세션을 유지한다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/network/auth_token.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/network/interceptors/auth_interceptor.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/core/storage/secure_token_store.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';

import '../../helpers/token_backend.dart';

class _Session {
  _Session({Map<String, String>? stored}) {
    FlutterSecureStorage.setMockInitialValues(
      stored ??
          <String, String>{
            'access_token': 'access-0',
            'refresh_token': 'refresh-0',
          },
    );
    container = ProviderContainer(
      overrides: <Override>[
        dioProvider.overrideWith((ref) {
          final Dio dio = Dio(
            BaseOptions(
              baseUrl: 'https://api.test/v1',
              validateStatus: (int? s) => s != null && s < 400,
            ),
          );
          dio.httpClientAdapter = backend;
          dio.interceptors.add(AuthInterceptor(ref, retryClient: dio));
          return dio;
        }),
        sessionFeatureResetProvider.overrideWithValue(() => resets++),
      ],
    );
  }

  final TokenBackend backend = TokenBackend();
  late final ProviderContainer container;
  int resets = 0;

  Dio get dio => container.read(dioProvider);
  SessionState get state => container.read(sessionControllerProvider);
  String? get token => container.read(authAccessTokenProvider);
  bool get notice => container.read(sessionExpiredNoticeProvider);
  SecureTokenStore get store => container.read(secureTokenStoreProvider);

  /// 복구가 끝나 로그인 상태가 될 때까지 기다린다.
  Future<void> restore() async {
    container.read(sessionControllerProvider);
    await _until(() => state.status != SessionStatus.unknown);
    expect(state.status, SessionStatus.authenticated);
  }

  Future<void> _until(bool Function() done) async {
    for (int i = 0; i < 200; i++) {
      if (done()) {
        for (int t = 0; t < 5; t++) {
          await Future<void>.delayed(Duration.zero);
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    fail('기다린 상태가 오지 않았다');
  }

  Future<void> settle() => _until(() => true);

  void dispose() => container.dispose();
}

Matcher _statusIs(int code) => isA<DioException>().having(
  (DioException e) => e.response?.statusCode,
  'status',
  code,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Session s;
  setUp(() => s = _Session());
  tearDown(() => s.dispose());

  group('회전 성공', () {
    test('만료된 뒤의 조회는 한 번 회전하고 성공한다', () async {
      await s.restore();
      s.backend.expireAccessTokens();

      final Response<Object?> res = await s.dio.get<Object?>('/data/today');

      expect((res.data! as Map<String, Object?>)['token'], 'access-1');
      expect(s.backend.refreshCalls, 1);
      expect(s.state.status, SessionStatus.authenticated);
      expect(s.token, 'access-1');
      expect(await s.store.readAccessToken(), 'access-1');
      expect(await s.store.readRefreshToken(), 'refresh-1');
      expect(s.notice, isFalse);
      // 같은 계정이 이어지는 것이다 — 회원별 화면 상태를 비우지 않는다.
      expect(s.resets, 0);
    });

    test('갱신은 서버가 준 회전 전 갱신 토큰으로 요청한다', () async {
      await s.restore();
      s.backend.expireAccessTokens();
      await s.dio.get<Object?>('/data/today');

      final RecordedRequest refresh = s.backend
          .requestsTo('/auth/refresh')
          .single;
      expect(refresh.method, 'POST');
      expect(s.backend.currentRefresh, 'refresh-1');
    });

    test('동시 401 여러 건도 회전은 한 번이고 모두 성공한다', () async {
      await s.restore();
      s.backend
        ..expireAccessTokens()
        ..refreshDelay = const Duration(milliseconds: 20);

      final List<Response<Object?>> all = await Future.wait(
        <Future<Response<Object?>>>[
          for (int i = 0; i < 6; i++) s.dio.get<Object?>('/data/$i'),
        ],
      );

      // 일회용 갱신 토큰을 두 번 썼다면 두 번째가 401 로 거부되어 세션이 끝났다.
      expect(s.backend.refreshCalls, 1);
      expect(all, hasLength(6));
      expect(s.state.status, SessionStatus.authenticated);
      expect(s.token, 'access-1');
    });

    test('두 번째 만료도 새 갱신 토큰으로 다시 회전한다', () async {
      await s.restore();
      s.backend.expireAccessTokens();
      await s.dio.get<Object?>('/data/a');
      s.backend.expireAccessTokens();
      final Response<Object?> res = await s.dio.get<Object?>('/data/b');

      expect((res.data! as Map<String, Object?>)['token'], 'access-2');
      expect(s.backend.refreshCalls, 2);
      expect(await s.store.readRefreshToken(), 'refresh-2');
    });

    test('서버가 갱신 토큰을 새로 주지 않으면 쓰던 것을 유지한다', () async {
      await s.restore();
      s.backend
        ..expireAccessTokens()
        ..refreshMode = RefreshMode.rotateAccessOnly;

      await s.dio.get<Object?>('/data/today');

      expect(await s.store.readAccessToken(), 'access-1');
      expect(await s.store.readRefreshToken(), 'refresh-0');
    });
  });

  group('갱신 거부 → 세션 종료', () {
    for (final RefreshMode mode in <RefreshMode>[
      RefreshMode.reject401,
      RefreshMode.reject403,
    ]) {
      test('$mode 면 토큰을 지우고 로그아웃 상태로 간다', () async {
        await s.restore();
        s.backend
          ..expireAccessTokens()
          ..refreshMode = mode;

        await expectLater(
          s.dio.get<Object?>('/data/today'),
          throwsA(_statusIs(401)),
        );
        await s.settle();

        expect(s.state.status, SessionStatus.signedOut);
        expect(s.token, isNull);
        expect(await s.store.readAccessToken(), isNull);
        expect(await s.store.readRefreshToken(), isNull);
        expect(s.notice, isTrue);
        // 로그아웃과 같은 길 — 회원별 화면 상태도 비운다.
        expect(s.resets, 1);
        // 원 요청을 다시 보내지 않았다.
        expect(s.backend.requestsTo('/data/today'), hasLength(1));
      });
    }

    test('동시 401 에서 갱신이 거부돼도 종료는 한 번이다', () async {
      await s.restore();
      s.backend
        ..expireAccessTokens()
        ..refreshMode = RefreshMode.reject401
        ..refreshDelay = const Duration(milliseconds: 10);

      final List<Object?> errors = <Object?>[];
      await Future.wait(<Future<void>>[
        for (int i = 0; i < 4; i++)
          s.dio
              .get<Object?>('/data/$i')
              .then<void>((_) {}, onError: errors.add),
      ]);
      await s.settle();

      expect(errors, hasLength(4));
      expect(s.backend.refreshCalls, 1);
      expect(s.resets, 1);
      expect(s.state.status, SessionStatus.signedOut);
    });

    test('저장된 갱신 토큰이 없으면 세션을 끝낸다', () async {
      s.dispose();
      s = _Session(stored: <String, String>{'access_token': 'access-0'});
      await s.restore();
      s.backend.expireAccessTokens();

      await expectLater(
        s.dio.get<Object?>('/data/today'),
        throwsA(_statusIs(401)),
      );
      await s.settle();

      expect(s.backend.refreshCalls, 0);
      expect(s.state.status, SessionStatus.signedOut);
      expect(s.notice, isTrue);
    });
  });

  group('일시적 실패 → 토큰 유지', () {
    for (final RefreshMode mode in <RefreshMode>[
      RefreshMode.serverError,
      RefreshMode.offline,
      RefreshMode.emptyAccess,
    ]) {
      test('$mode 면 토큰을 지키고 로그인 상태를 유지한다', () async {
        await s.restore();
        s.backend
          ..expireAccessTokens()
          ..refreshMode = mode;

        await expectLater(
          s.dio.get<Object?>('/data/today'),
          throwsA(_statusIs(401)),
        );
        await s.settle();

        expect(s.state.status, SessionStatus.authenticated);
        expect(s.token, 'access-0');
        expect(await s.store.readAccessToken(), 'access-0');
        expect(await s.store.readRefreshToken(), 'refresh-0');
        expect(s.notice, isFalse);
        expect(s.resets, 0);
      });
    }

    test('망이 돌아오면 다음 요청에서 다시 회전한다', () async {
      await s.restore();
      s.backend
        ..expireAccessTokens()
        ..refreshMode = RefreshMode.offline;
      await expectLater(s.dio.get<Object?>('/data/a'), throwsA(_statusIs(401)));

      s.backend.refreshMode = RefreshMode.rotate;
      final Response<Object?> res = await s.dio.get<Object?>('/data/b');
      expect((res.data! as Map<String, Object?>)['token'], 'access-1');
    });
  });

  group('사용자 행동과 겹칠 때', () {
    test('회전 중에 로그아웃하면 새 토큰을 저장하지 않는다', () async {
      await s.restore();
      final Completer<void> gate = Completer<void>();
      s.backend
        ..expireAccessTokens()
        ..refreshGate = gate;

      final Future<Object?> call = s.dio
          .get<Object?>('/data/today')
          .then<Object?>((Response<Object?> r) => r, onError: (Object e) => e);
      await s.backend.refreshArrived.first;
      await s.container.read(sessionControllerProvider.notifier).signOut();
      gate.complete();
      final Object? outcome = await call;
      await s.settle();

      expect(outcome, _statusIs(401));
      expect(s.state.status, SessionStatus.signedOut);
      expect(s.token, isNull);
      expect(await s.store.readAccessToken(), isNull);
      expect(await s.store.readRefreshToken(), isNull);
      // 직접 로그아웃한 것 — 만료 안내를 띄우지 않는다.
      expect(s.notice, isFalse);
    });

    test('로그아웃은 남아 있던 만료 안내를 거둔다', () async {
      await s.restore();
      s.container.read(sessionExpiredNoticeProvider.notifier).state = true;
      await s.container.read(sessionControllerProvider.notifier).signOut();
      expect(s.notice, isFalse);
    });

    test('세션 확인 요청(복구)의 401 은 인터셉터가 회전하지 않는다', () async {
      // 복구는 스스로 회전한다 — 인터셉터까지 회전하면 일회용 토큰을 두 번 쓴다.
      s.backend.expireAccessTokens();
      s.container.read(sessionControllerProvider);
      await s._until(() => s.state.status != SessionStatus.unknown);

      expect(s.backend.refreshCalls, 1);
      expect(s.state.status, SessionStatus.authenticated);
      expect(s.token, 'access-1');
    });
  });
}
