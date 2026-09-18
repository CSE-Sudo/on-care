/// 실 API E2E 공통 하네스 (트레이너 웹) — #637.
///
/// ## 왜 `test_e2e/` 이고 `integration_test/` 가 아닌가
///
/// `flutter test integration_test/...` 는 실기기·브라우저 러너를 요구한다(브라우저는
/// ChromeDriver). 이 스위트는 **브라우저 없이** 실 백엔드를 검증하므로 그 러너가 필요
/// 없다. 대신 `IntegrationTestWidgetsFlutterBinding`(LiveBinding)을 그대로 써서 실제
/// 위젯 트리와 실제 HTTP 를 얻는다 — `flutter test` 기본 바인딩은 FakeAsync 라 실 네트워크
/// 응답이 영원히 오지 않는다.
///
/// 디렉터리를 `test/` 밖에 둔 이유는 CI 다. `trainer-ci.yml` 의 `flutter test` 는 인자
/// 없이 돌아 `test/` 만 훑는다. 백엔드가 없는 CI 에서 이 스위트가 딸려 돌면 무조건 깨진다.
///
/// ## 단계를 나눈 이유
///
/// 회원 앱과 트레이너 웹은 **서로 다른 Dart 패키지**라 한 프로세스에 함께 띄울 수 없다.
/// 그래서 한 시나리오를 단계로 쪼개 번갈아 실행하고, 단계 사이의 상태는 두 가지로 넘긴다.
///
///  * **서버 DB** — 이 테스트가 실제로 검증하려는 것. 슬롯·예약·일정이 여기 남는다.
///  * **상태 파일** — id 처럼 화면에서 읽을 수 없는 값만. [E2eState] 참고.
library;

// `test_e2e/` 는 분석기가 테스트 디렉터리로 인정하는 경로(`test/`)가 아니다. 그래서
// 테스트에서만 쓰라고 표시된 플러그인 페이크 진입점이 경고로 잡힌다 — 이 파일은
// 테스트 전용이고 앱 코드에서 import 되지 않으므로 그 경고만 끈다.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/bootstrap.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String trainerEmail = 'trainer@oncare.com';
const String memberEmail = 'minsu@oncare.com';
const String memberId = 'user-7d4e9a2c5f18';
const String memberName = '김민수';
const String demoPassword = 'oncare123';

const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const String e2ePhase = String.fromEnvironment('E2E_PHASE');
const String e2eStateFile = String.fromEnvironment('E2E_STATE_FILE');

/// 회원 단계가 상담에 고르는 자리의 시작 시각(서울, `HH:mm`). (#1873)
///
/// 서버는 고른 자리의 시각을 `preferred_time_slot` 에 이 모양으로 옮겨 적고,
/// 승인이 이 시각에 일정을 만든다. 회원 앱 하네스
/// (`frontend/flutter/test_e2e/support/e2e_harness.dart`)의 같은 이름 상수와
/// **값이 같아야 한다** — 두 앱은 서로 다른 패키지라 공유할 수 없다.
const String consultStartTime = '21:00';

/// 단계 사이로 넘기는 값. **화면에서 읽을 수 없는 id 만** 여기 담는다.
///
/// 잔여 좌석이나 일정 표시 여부처럼 검증 대상인 것은 절대 담지 않는다 — 그것을
/// 파일로 넘기면 서버가 아니라 앞 단계의 기억을 검증하게 된다.
class E2eState {
  const E2eState(this.values);

  final Map<String, Object?> values;

  static File get _file {
    expect(e2eStateFile, isNotEmpty, reason: 'E2E_STATE_FILE 이 필요합니다.');
    return File(e2eStateFile);
  }

  static E2eState read() {
    final File file = _file;
    if (!file.existsSync()) return const E2eState(<String, Object?>{});
    // 러너가 실행 시작에 파일을 비운다 — 빈 파일은 "아직 아무 단계도 안 지났다" 다.
    final String raw = file.readAsStringSync().trim();
    if (raw.isEmpty) return const E2eState(<String, Object?>{});
    return E2eState(jsonDecode(raw) as Map<String, Object?>);
  }

  static void merge(Map<String, Object?> patch) {
    final Map<String, Object?> next = <String, Object?>{
      ...read().values,
      ...patch,
    };
    _file.writeAsStringSync(jsonEncode(next));
  }

  String require(String key) {
    final Object? value = values[key];
    expect(value, isA<String>(), reason: '앞 단계가 남긴 $key 가 없습니다.');
    return value! as String;
  }

  /// 이번 실행이 쓰는 슬롯의 시작 시각(로컬).
  DateTime get slotStartsAt =>
      DateTime.parse(require('slotStartsAt')).toLocal();

  /// 회원이 예약하기 **전에** 이미 그 시각에 있던 예약 일정 id 들.
  ///
  /// 슬롯 시각이 매 실행 같은 10:00 이라, 이 기준선이 없으면 앞선 실행이 남긴 일정을
  /// 이번 것으로 착각한다.
  Set<String> get sessionIdsBefore => <String>{
    for (final Object? id
        in (values['sessionIdsBefore'] as List<Object?>?) ?? const <Object?>[])
      id! as String,
  };
}

/// 화면을 거치지 않고 서버 상태를 직접 확인할 때 쓰는 클라이언트.
///
/// UI 검증을 대신하라고 있는 것이 아니다 — "화면에 보였다" 와 "서버에 저장됐다" 는
/// 다른 주장이고, 이슈의 완료 조건은 둘 다 요구한다.
class E2eApi {
  E2eApi._(this._dio, this._auth);

  final Dio _dio;
  final Options _auth;

  static Future<E2eApi> login(String email) async {
    final Dio dio = Dio(
      BaseOptions(
        // 분석 시점에는 dart-define 이 없어 이 상수가 '' 로 보인다. 기본값과 같다고
        // 잡히지만, 실행 시에는 러너가 넘긴 주소가 들어온다.
        // ignore: avoid_redundant_argument_values
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final Response<Map<String, dynamic>> res = await dio
        .post<Map<String, dynamic>>(
          '/auth/login',
          data: <String, String>{'username': email, 'password': demoPassword},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
    return E2eApi._(
      dio,
      Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${res.data!['access_token']}',
        },
      ),
    );
  }

  /// 트레이너에게 도착한 상담 요청. 기본은 대기 중만, [all] 이면 처리한 것까지.
  Future<List<Map<String, dynamic>>> consultations({bool all = false}) async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      '/trainer/consultations',
      queryParameters: all ? <String, String>{'status': 'all'} : null,
      options: _auth,
    );
    return <Map<String, dynamic>>[
      for (final Object? row in res.data ?? const <Object?>[])
        row! as Map<String, dynamic>,
    ];
  }

  /// 이 회원이 담당 목록에 들어왔는가. 승인이 만드는 **연결**을 본다.
  Future<bool> isClientOf(String memberId) async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      '/trainer/clients',
      options: _auth,
    );
    for (final Object? row in res.data ?? const <Object?>[]) {
      final Map<String, dynamic> client = row! as Map<String, dynamic>;
      if (client['id'] == memberId || client['member_id'] == memberId) {
        return true;
      }
    }
    return false;
  }

  /// 이 회원 몫으로 잡힌 일정. 승인이 만드는 **일정**을 본다.
  ///
  /// 서버에 `member_id` 로 물어야 한다 — 일정 응답에는 그 필드가 **없어서**
  /// 전체 목록을 받아 걸러 내면 아무것도 못 찾는다.
  Future<List<Map<String, dynamic>>> scheduleFor(String memberId) async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      '/trainer/schedule',
      queryParameters: <String, String>{'member_id': memberId},
      options: _auth,
    );
    return <Map<String, dynamic>>[
      for (final Object? row in res.data ?? const <Object?>[])
        row! as Map<String, dynamic>,
    ];
  }

  Future<List<Map<String, dynamic>>> trainerSlots() async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      '/trainer/reservation-slots',
      options: _auth,
    );
    return <Map<String, dynamic>>[
      for (final Object? row in res.data ?? const <Object?>[])
        row! as Map<String, dynamic>,
    ];
  }

  /// 시작 시각이 [startsAt] 인 슬롯. 이번 실행이 만든 자리를 id 없이 찾아낸다.
  Future<Map<String, dynamic>?> slotAt(DateTime startsAt) async {
    for (final Map<String, dynamic> slot in await trainerSlots()) {
      final DateTime at = DateTime.parse(slot['starts_at'] as String).toUtc();
      if (at == startsAt.toUtc()) return slot;
    }
    return null;
  }

  Future<Map<String, dynamic>> slotById(String id) async {
    for (final Map<String, dynamic> slot in await trainerSlots()) {
      if (slot['id'] == id) return slot;
    }
    fail('슬롯 $id 를 서버에서 찾지 못했습니다.');
  }

  /// 그 날짜의 트레이너 일정. 예약이 만든 일정은 `note` 가 '회원 앱 예약' 이다
  /// (`reservation_service.reserve`).
  Future<List<Map<String, dynamic>>> sessionsOn(DateTime day) async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      '/trainer/schedule',
      queryParameters: <String, Object?>{'date': ymd(day)},
      options: _auth,
    );
    return <Map<String, dynamic>>[
      for (final Object? row in res.data ?? const <Object?>[])
        row! as Map<String, dynamic>,
    ];
  }

  /// 그 시각에 회원 앱 예약으로 생긴 일정들.
  ///
  /// 날짜·시각·회원 이름만으로는 **이번 실행의 것을 특정할 수 없다.** 슬롯 시각이
  /// 매 실행 같은 10:00 이라, 앞선 실행이 남긴 일정도 똑같이 걸린다. 그래서 호출부는
  /// 예약 전후의 id 차집합으로 이번 것을 고른다([E2eState] 의 `sessionIdsBefore`).
  Future<List<Map<String, dynamic>>> reservationSessionsAt(
    DateTime startsAt,
  ) async {
    // 서버는 일정의 날짜·시각을 **항상** 서울 기준으로 찍는다
    // (`reservation_service.reserve` 의 `astimezone(SEOUL)`). 그러니 비교할 벽시계도
    // 서울 것이어야 한다 — 러너 지역 시간으로 재면 KST 밖에서는 통째로 어긋나
    // '일정이 0건' 으로만 보인다(CI 는 UTC 라 9시간 차이가 났다).
    final DateTime local = _seoul(startsAt);
    final String hhmm =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return <Map<String, dynamic>>[
      for (final Map<String, dynamic> session in await sessionsOn(local))
        if (session['time'] == hhmm &&
            session['note'] == '회원 앱 예약' &&
            session['client_name'] == memberName)
          session,
    ];
  }

  // ── 채팅 (#639) ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> thread(String clientId) async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      '/trainer/clients/$clientId/chat',
      options: _auth,
    );
    return <Map<String, dynamic>>[
      for (final Object? row in res.data ?? const <Object?>[])
        row! as Map<String, dynamic>,
    ];
  }

  Future<List<Map<String, dynamic>>> threadWithBody(
    String clientId,
    String body,
  ) async => <Map<String, dynamic>>[
    for (final Map<String, dynamic> row in await thread(clientId))
      if (row['body'] == body) row,
  ];

  /// 픽스처용 — 회원 계정으로 메시지를 보낸다. 트레이너 화면을 **연 채로** 상대
  /// 메시지를 도착시켜야 polling 을 검증할 수 있는데, 두 앱을 한 프로세스에 띄울 수
  /// 없으므로 이 자리에서는 API 가 회원 역할을 대신한다.
  Future<void> sendAsMember(String text) async {
    final Dio dio = Dio(
      BaseOptions(
        // 분석 시점에는 dart-define 이 없어 이 상수가 '' 로 보인다. 기본값과 같다고
        // 잡히지만, 실행 시에는 러너가 넘긴 주소가 들어온다.
        // ignore: avoid_redundant_argument_values
        baseUrl: apiBaseUrl,
      ),
    );
    final Response<Map<String, dynamic>> login = await dio
        .post<Map<String, dynamic>>(
          '/auth/login',
          data: <String, String>{
            'username': memberEmail,
            'password': demoPassword,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
    await dio.post<Object?>(
      '/me/coach/chat',
      data: <String, Object?>{'text': text},
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${login.data!['access_token']}',
        },
      ),
    );
  }

  /// 트레이너의 스레드별 미읽음 수. 스레드가 없으면 0.
  Future<int> unreadFor(String clientId) async {
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>('/trainer/chat/unread', options: _auth);
    return ((res.data ?? const <String, dynamic>{})[clientId] as num?)
            ?.toInt() ??
        0;
  }

  Future<void> closeSlot(String id) async {
    await _dio.delete<Object?>(
      '/trainer/reservation-slots/$id',
      options: _auth,
    );
  }
}

/// VM 에는 구현이 없는 플러그인을 채운다.
///
/// 이 셋이 없으면 앱은 부팅 도중 `MissingPluginException` 으로 멈춘다. 실제 기기·
/// 브라우저에서는 플랫폼이 제공하는 것들이라, 여기서만 대신 준다.
void installPluginFakes() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async =>
            Directory.systemTemp.createTempSync('oncare_trainer_e2e').path,
      );
}

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    finder,
    findsWidgets,
    reason: '[$e2ePhase] $step 이(가) $timeout 안에 나타나지 않았습니다.',
  );
}

Future<void> pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    finder,
    findsNothing,
    reason: '[$e2ePhase] $step 이(가) $timeout 안에 사라지지 않았습니다.',
  );
}

/// 스크롤 목록 안에서 [target] 이 나올 때까지 끌어 내린다.
///
/// `ListView` 는 보이는 자식만 만든다. 실행을 거듭할수록 슬롯 목록이 길어져 새로 만든
/// 자리가 화면 밖으로 밀리는데, 그때 `find.byKey` 는 "없음" 을 돌려준다 — 화면에 안
/// 그려진 것과 만들어지지 않은 것이 구분되지 않는다.
Future<void> pumpUntilVisibleInList(
  WidgetTester tester,
  Finder target, {
  required Finder list,
  required String step,
  int maxDrags = 30,
}) async {
  for (int i = 0; i < maxDrags && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -160));
    await tester.pump(const Duration(milliseconds: 120));
  }
  expect(
    target,
    findsWidgets,
    reason: '[$e2ePhase] $step 을(를) 목록 끝까지 내려도 찾지 못했습니다.',
  );
}

/// 목업으로 통과하는 것을 막는 관문.
///
/// 이슈의 완료 조건이 "mock repository 만으로 통과하지 않는다" 라, 설정이 목업으로
/// 새면 조용히 초록불이 뜨는 대신 여기서 멈춘다.
void assertRealApiConfig() {
  final AppConfig config = AppConfig.fromEnvironment();
  expect(
    config.useMockApi,
    isFalse,
    reason: '--dart-define=USE_MOCK_API=false 로 실행해야 합니다.',
  );
  expect(apiBaseUrl, isNotEmpty, reason: 'API_BASE_URL 이 필요합니다.');
  expect(
    config.apiBaseUrl,
    apiBaseUrl,
    reason: '앱과 검증용 API 클라이언트가 같은 백엔드를 봐야 합니다.',
  );
}

/// 트레이너 웹의 기준 뷰포트(desktop 1440×1024 계약, 여유 폭 1600).
///
/// 기본 테스트 화면은 800×600 이라 사이드바가 접힌다 — 그 상태에서는 `sidebar-*`
/// 가 트리에 아예 없어서, 화면 이동이 전부 "위젯을 찾지 못함" 으로 깨진다.
void useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1024);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 로그아웃 상태에서 앱을 새로 띄운다. 재시작·재로그인 검증도 이것을 다시 부른다.
Future<void> bootSignedOut(WidgetTester tester) async {
  useDesktopViewport(tester);
  assertRealApiConfig();
  // 앞선 부팅이 남아 있으면 그 ProviderScope 의 세션이 그대로 살아 있어, 토큰을
  // 지워도 새 트리가 로그인 화면 대신 대시보드로 간다. 재시작 검증이 조용히
  // "로그인된 채로 계속" 을 통과시키지 않도록 먼저 트리를 비운다.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await const FlutterSecureStorage().deleteAll();
  await bootstrap();
  await pumpUntil(tester, find.byType(TrainerSignInPage), step: '로그인 화면');
}

Future<void> loginAsTrainer(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey<String>('trainer-login-email')),
      matching: find.byType(TextField),
    ),
    trainerEmail,
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey<String>('trainer-login-password')),
      matching: find.byType(TextField),
    ),
    demoPassword,
  );
  await tester.tap(find.byKey(const ValueKey<String>('trainer-login-submit')));
  await pumpUntil(tester, find.byType(DashboardPage), step: '트레이너 로그인');
}

/// 그 순간의 서울 벽시계. 한국은 1988년 이후 서머타임이 없어 고정 +9 로 충분하고,
/// 서버가 쓰는 `app.core.clock.SEOUL` 과 같은 값이 된다. 돌려주는 값은 UTC 플래그가
/// 붙어 있으니 **필드만** 읽어야 한다.
DateTime _seoul(DateTime value) => value.toUtc().add(const Duration(hours: 9));

String ymd(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
