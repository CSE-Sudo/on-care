/// 실 API E2E 공통 하네스 (회원 앱) — #637.
///
/// 트레이너 웹 쪽 `frontend/flutter_trainer/test_e2e/support/e2e_harness.dart` 와
/// 짝이다. 두 앱은 서로 다른 Dart 패키지라 한 프로세스에 함께 띄울 수 없어, 한
/// 시나리오를 단계로 쪼개 번갈아 실행한다.
///
/// ## 왜 `test_e2e/` 이고 `integration_test/` 가 아닌가
///
/// `flutter test integration_test/...` 는 실기기·브라우저 러너를 요구한다. 이 스위트는
/// 브라우저 없이 실 백엔드를 검증하므로 그 러너가 필요 없다. 대신
/// `IntegrationTestWidgetsFlutterBinding`(LiveBinding)을 써서 실제 위젯 트리와 실제
/// HTTP 를 얻는다 — `flutter test` 기본 바인딩은 FakeAsync 라 실 네트워크 응답이
/// 영원히 오지 않는다.
///
/// `test/` 밖에 둔 이유는 CI 다. `user-app-ci.yml` 의 `flutter test` 는 인자 없이 돌아
/// `test/` 만 훑는다. 백엔드가 없는 CI 에서 이 스위트가 딸려 돌면 무조건 깨진다.
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
import 'package:oncare/app/bootstrap.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart'
    show AppButton, AppTimeRangePickerDialog;
import 'package:shared_preferences/shared_preferences.dart';

const String memberEmail = 'minsu@oncare.com';
const String otherMemberEmail = 'jisu@oncare.com';

/// 픽스처 전용. 정원 1 짜리 경쟁용 슬롯을 여는 데만 쓴다.
const String trainerEmail = 'trainer@oncare.com';
const String trainerId = 'trainer-demo';

/// `trainer-demo` 가 소속된 헬스장. 상담 동선이 이 헬스장 상세를 거친다.
const String consultationGymId = 'gym-oncare-sinchon';
const String memberId = 'user-7d4e9a2c5f18';
const String otherMemberId = 'user-jisu';
const String demoPassword = 'oncare123';

const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const String e2ePhase = String.fromEnvironment('E2E_PHASE');
const String e2eStateFile = String.fromEnvironment('E2E_STATE_FILE');

/// 단계 사이로 넘기는 값. **화면에서 읽을 수 없는 id 만** 여기 담는다.
///
/// 잔여 좌석처럼 검증 대상인 것은 담지 않는다 — 파일로 넘기면 서버가 아니라 앞
/// 단계의 기억을 검증하게 된다.
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

  int requireInt(String key) {
    final Object? value = values[key];
    expect(value, isA<int>(), reason: '앞 단계가 남긴 $key 가 없습니다.');
    return value! as int;
  }
}

/// 화면을 거치지 않고 서버 상태를 직접 확인할 때 쓰는 클라이언트.
///
/// UI 검증을 대신하라고 있는 것이 아니다 — "화면에 보였다" 와 "서버에 저장됐다" 는
/// 다른 주장이고, 이슈의 완료 조건은 둘 다 요구한다.
class E2eApi {
  E2eApi._(this._dio, this._auth);

  final Dio _dio;
  final Options _auth;

  static Dio _plainDio() => Dio(
    BaseOptions(
      // 분석 시점에는 dart-define 이 없어 이 상수가 '' 로 보인다. 기본값과 같다고
      // 잡히지만, 실행 시에는 러너가 넘긴 주소가 들어온다.
      // ignore: avoid_redundant_argument_values
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      // 4xx 를 예외가 아니라 응답으로 받는다 — 예외 케이스 검증이 상태 코드를
      // 직접 비교하기 때문이다.
      validateStatus: (int? status) => status != null && status < 500,
    ),
  );

  static Future<E2eApi> login(String email) async {
    final Dio dio = _plainDio();
    final Response<Map<String, dynamic>> res = await dio
        .post<Map<String, dynamic>>(
          '/auth/login',
          data: <String, String>{'username': email, 'password': demoPassword},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
    expect(res.statusCode, 200, reason: '$email 로그인 실패');
    return E2eApi._(
      dio,
      Options(
        headers: <String, String>{
          'Authorization': 'Bearer ${res.data!['access_token']}',
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _list(String path) async {
    final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
      path,
      options: _auth,
    );
    return <Map<String, dynamic>>[
      for (final Object? row in res.data ?? const <Object?>[])
        row! as Map<String, dynamic>,
    ];
  }

  /// 실행마다 새 회원을 만든다. **시드 회원으로는 #640 을 검증할 수 없다** —
  /// 셋 다 이미 `trainer-demo` 담당이라 "승인이 담당 연결을 만든다" 가 성립하지
  /// 않고, 승인해 버리면 다음 실행이 같은 상태에서 시작하지 못한다.
  static Future<String> register(String email, {String? name}) async {
    final Dio dio = _plainDio();
    final Response<Map<String, dynamic>> res = await dio
        .post<Map<String, dynamic>>(
          '/auth/register',
          data: <String, String>{
            'email': email,
            'password': demoPassword,
            'name': name ?? 'E2E 회원',
          },
        );
    expect(res.statusCode, 201, reason: '$email 가입 실패: ${res.data}');
    return res.data!['id']! as String;
  }

  /// 계정을 지운다. 상담·담당 연결은 회원 행을 따라 함께 사라진다(FK CASCADE).
  ///
  /// **일정은 따라 지워지지 않는다** — `trainer_schedule.member_id` 는 SET NULL 이라
  /// 승인이 만든 상담 일정이 주인 없이 남는다. 그것은 [deleteTrainerSession] 으로
  /// 트레이너 쪽에서 따로 지운다.
  Future<void> deleteMe() async {
    final Response<Object?> res = await _dio.delete<Object?>(
      '/users/me',
      options: _auth,
    );
    expect(res.statusCode, 200, reason: '계정 삭제 실패: ${res.data}');
  }

  Future<List<Map<String, dynamic>>> myConsultations() =>
      _list('/consultations/me');

  /// 상담을 API 로 만든다. **UI 검증용이 아니라** 예외 케이스(중복·권한)용이다 —
  /// 그쪽은 화면이 아니라 서버 규칙을 보는 자리다.
  Map<String, Object?> _consultationBody(String trainerId) => <String, Object?>{
    'target_type': 'trainer',
    'trainer_id': trainerId,
    'exercise_goal': 'strength',
    'health_purpose_type': 'rehab',
    'preferred_date': DateTime.now().toIso8601String().substring(0, 10),
    // 시각 없는 `flexible` 은 서버가 422 로 막는다(#1587).
    'preferred_time_slot': consultPreferredTimeSlot,
    'message': 'E2E 예외 케이스',
    // 동의 없이는 서버가 422 다 (#1022).
    'data_sharing_consent': true,
  };

  Future<Map<String, dynamic>> createConsultation({
    required String trainerId,
  }) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          '/consultations',
          data: _consultationBody(trainerId),
          options: _auth,
        );
    expect(res.statusCode, 201, reason: '상담 생성 실패: ${res.data}');
    return res.data!;
  }

  Future<int> createConsultationStatus({required String trainerId}) async {
    final Response<Object?> res = await _dio.post<Object?>(
      '/consultations',
      data: _consultationBody(trainerId),
      options: _auth,
    );
    return res.statusCode!;
  }

  /// 이미 처리된 상담을 다시 처리하려 할 때의 응답(트레이너 토큰으로 부른다).
  Future<int> decideStatus(String consultationId, String action) async {
    final Response<Object?> res = await _dio.post<Object?>(
      '/trainer/consultations/$consultationId/$action',
      data: <String, Object?>{'note': '재처리 시도'},
      options: _auth,
    );
    return res.statusCode!;
  }

  Future<int> consultationStatusCode(String consultationId) async {
    final Response<Object?> res = await _dio.get<Object?>(
      '/consultations/$consultationId',
      options: _auth,
    );
    return res.statusCode!;
  }

  /// 대상 트레이너에게 도착한 상담 요청(트레이너 토큰으로 부른다).
  Future<List<Map<String, dynamic>>> trainerConsultations() =>
      _list('/trainer/consultations');

  /// 회원이 보는 담당 트레이너. 담당이 없으면 404 라 null 을 준다.
  Future<Map<String, dynamic>?> myCoach() async {
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>('/me/coach', options: _auth);
    return res.statusCode == 200 ? res.data : null;
  }

  /// 트레이너 일정 중 이 회원 몫. 승인이 만든 상담 일정을 여기서 확인한다.
  ///
  /// 서버에 `member_id` 로 물어야 한다 — 일정 응답에는 그 필드가 **없어서**
  /// 전체 목록을 받아 걸러 내면 아무것도 못 찾는다.
  Future<List<Map<String, dynamic>>> trainerScheduleFor(String memberId) async {
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

  Future<void> deleteTrainerSession(String sessionId) async {
    await _dio.delete<Object?>('/trainer/schedule/$sessionId', options: _auth);
  }

  Future<List<Map<String, dynamic>>> myReservations() =>
      _list('/reservations/me');

  Future<List<Map<String, dynamic>>> trainerSlots() =>
      _list('/trainers/$trainerId/slots');

  /// 회원에게 보이는 슬롯 하나. 마감·과거 슬롯은 목록에서 빠질 수 있어 null 을 준다.
  Future<Map<String, dynamic>?> slotById(String id) async {
    for (final Map<String, dynamic> slot in await trainerSlots()) {
      if (slot['id'] == id) return slot;
    }
    return null;
  }

  Future<Map<String, dynamic>?> reservationForSlot(String slotId) async {
    for (final Map<String, dynamic> row in await myReservations()) {
      if (row['slot_id'] == slotId) return row;
    }
    return null;
  }

  /// 상태 코드까지 보고 싶을 때 쓰는 원시 예약 호출(예외 케이스 검증용).
  Future<Response<Object?>> reserveRaw(String slotId) => _dio.post<Object?>(
    '/reservations',
    data: <String, String>{'slot_id': slotId},
    options: _auth,
  );

  Future<Response<Object?>> cancelRaw(String reservationId) =>
      _dio.delete<Object?>('/reservations/$reservationId', options: _auth);

  // ── 채팅 (#639) ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> coachChat() => _list('/me/coach/chat');

  /// 본문이 [body] 인 메시지들. 재시도가 한 건으로 접히는지 셀 때 쓴다.
  Future<List<Map<String, dynamic>>> coachChatWithBody(String body) async =>
      <Map<String, dynamic>>[
        for (final Map<String, dynamic> row in await coachChat())
          if (row['body'] == body) row,
      ];

  /// 회원 발신. [clientRequestId] 를 같은 값으로 두 번 보내면 서버가 한 건으로
  /// 접어야 한다 — 앱의 재시도가 정확히 이 모양이다(#605).
  Future<Response<Object?>> sendAsMember(
    String text, {
    String? clientRequestId,
  }) => _dio.post<Object?>(
    '/me/coach/chat',
    data: <String, Object?>{
      'text': text,
      'client_request_id': ?clientRequestId,
    },
    options: _auth,
  );

  Future<int> memberUnread() async {
    final Response<Map<String, dynamic>> res = await _dio
        .get<Map<String, dynamic>>('/me/coach/chat/unread', options: _auth);
    return (res.data!['unread'] as num).toInt();
  }

  Future<void> markMemberRead() async {
    await _dio.post<Object?>('/me/coach/chat/read', options: _auth);
  }

  /// 픽스처용 — 트레이너 계정으로 회원 [memberId] 스레드에 답장한다.
  Future<Response<Object?>> sendAsTrainer(
    String memberId,
    String text, {
    String? clientRequestId,
  }) => _dio.post<Object?>(
    '/trainer/clients/$memberId/chat',
    data: <String, Object?>{
      'text': text,
      'client_request_id': ?clientRequestId,
    },
    options: _auth,
  );

  Future<List<Map<String, dynamic>>> trainerThread(String memberId) =>
      _list('/trainer/clients/$memberId/chat');

  /// 픽스처용 — 트레이너 계정으로 슬롯을 연다. 정원은 늘 1이다(#1012) — 서버가
  /// 무엇을 보내든 그렇게 만든다. [sessionType] 만 고른다(`1:1 PT`/`상담`,
  /// #1083).
  Future<Map<String, dynamic>> createSlotAsTrainer({
    required DateTime startsAt,
    String sessionType = '1:1 PT',
  }) async {
    final Response<Map<String, dynamic>> res = await _dio
        .post<Map<String, dynamic>>(
          '/trainer/reservation-slots',
          data: <String, Object?>{
            'starts_at': startsAt.toUtc().toIso8601String(),
            'session_type': sessionType,
          },
          options: _auth,
        );
    expect(res.statusCode, 201, reason: '경쟁 검증용 슬롯 생성 실패');
    return res.data!;
  }

  Future<void> closeSlotAsTrainer(String slotId) async {
    await _dio.delete<Object?>(
      '/trainer/reservation-slots/$slotId',
      options: _auth,
    );
  }
}

/// VM 에는 구현이 없는 플러그인을 채운다.
///
/// 이 셋이 없으면 앱은 부팅 도중 `MissingPluginException` 으로 멈춘다. 실제 기기에서는
/// 플랫폼이 제공하는 것들이라, 여기서만 대신 준다.
void installPluginFakes() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async =>
            Directory.systemTemp.createTempSync('oncare_e2e').path,
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

/// 서버 상태가 [matcher] 를 만족할 때까지 다시 읽는다. (#910)
///
/// **화면이 정리됐다고 서버가 끝난 것은 아니다.** [pumpUntilAbsent] 로 카드가
/// 사라지기를 기다린 뒤 서버를 한 번만 보면, 요청 왕복이 늦는 날 아직 반영되지
/// 않은 상태를 읽는다 — 예약 취소 단계가 그렇게 깜빡였다.
///
/// 시간이 다하면 **마지막으로 읽은 값**으로 단언한다. 그래야 취소가 정말
/// 반영되지 않는 회귀도 그대로 잡히고, 실패 메시지에 실제 서버 상태가 남는다.
///
/// 화면이 아니라 서버를 기다리는 자리이지만 [tester] 를 받는다 — 앱이 계속
/// 돌아야 갱신·재조회가 진행되고, 펌프하지 않으면 그저 멈춰 서서 기다린다.
Future<T> pumpUntilServer<T>(
  WidgetTester tester,
  Future<T> Function() read,
  Matcher matcher, {
  required String step,
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 200),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  T value = await read();
  while (!matcher.matches(value, <dynamic, dynamic>{}) &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(interval);
    value = await read();
  }
  expect(
    value,
    matcher,
    reason: '[$e2ePhase] $step 이(가) $timeout 안에 서버에 반영되지 않았습니다.',
  );
  return value;
}

/// 목업으로 통과하는 것을 막는 관문.
///
/// 이슈의 완료 조건이 "mock repository 만으로 테스트가 통과하지 않는다" 라, 설정이
/// 목업으로 새면 조용히 초록불이 뜨는 대신 여기서 멈춘다.
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

/// 회원 앱의 기준 뷰포트. 기본 800×600 은 이 앱의 레이아웃과 어긋난다.
void useMobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 이번 테스트에서 모인 렌더링 넘침의 설명. 시나리오가 끝날 때 비워진다.
///
/// `FlutterErrorDetails` 를 그대로 들고 있다가 끝에서 문자열로 만들면, 그때는 위젯
/// 트리가 이미 해체돼 위치가 `DEFUNCT` 로만 남는다. 그래서 **터진 그 순간에** 설명을
/// 만들어 둔다.
List<String> _renderOverflows = <String>[];

/// 넘침 단언을 이번 테스트에 이미 걸어 뒀는가.
bool _overflowTearDownRegistered = false;

/// 넘침(overflow)으로 보고된 렌더링 오류인가.
///
/// 라이브러리 이름 대신 문구로 가른다 — 넘침은 `RenderFlex` 말고도 여러 렌더
/// 오브젝트가 같은 문장으로 보고한다.
bool _isRenderOverflow(FlutterErrorDetails details) =>
    details.exceptionAsString().contains('overflowed');

/// 실패 메시지에 넣을 한 건의 설명.
///
/// 렌더 오브젝트 덤프만으로는 **어느 화면인지** 알기 어렵다. 위젯 사슬은
/// `informationCollector` 가 들고 있으므로 함께 붙인다.
String _describeOverflow(FlutterErrorDetails details) {
  const int limit = 1200;
  final StringBuffer out = StringBuffer(details.exceptionAsString());
  final Iterable<DiagnosticsNode>? extra = details.informationCollector?.call();
  if (extra != null) {
    for (final DiagnosticsNode node in extra) {
      final String line = node.toStringDeep().trimRight();
      if (line.isNotEmpty) out.writeln('\n$line');
    }
  }
  final String text = out.toString();
  return text.length <= limit ? text : '${text.substring(0, limit)}…(생략)';
}

/// `bootstrap()` 이 덮어쓴 오류 핸들러 위에 넘침 감시를 다시 얹는다. (#844)
///
/// `lib/app/bootstrap.dart` 는 `FlutterError.onError` 를 **로깅 전용**으로 바꾼다.
/// 그래서 부팅 뒤에 나는 넘침은 테스트 실패가 아니라 로그 한 줄로 끝나고, 스위트는
/// 초록인데 화면은 잘려 있는 상태가 된다 — #840 이 정확히 그렇게 새어 나갔다.
///
/// 로깅은 그대로 두고(기존 출력이 달라지지 않는다) 넘침만 따로 모아, 시나리오가
/// 끝날 때 하나라도 있으면 실패시킨다.
///
/// **부팅할 때마다 다시 얹어야 한다.** 재시작 검증은 [bootSignedOut] 을 다시 부르고,
/// 그 안의 `bootstrap()` 이 핸들러를 새 것으로 갈아 끼워 앞서 얹은 감시를 지운다.
void _watchForOverflow() {
  final void Function(FlutterErrorDetails)? logging = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_isRenderOverflow(details)) {
      _renderOverflows.add(_describeOverflow(details));
    }
    logging?.call(details);
  };

  if (_overflowTearDownRegistered) return;
  _overflowTearDownRegistered = true;
  addTearDown(() {
    FlutterError.onError = logging;
    final List<String> found = List<String>.of(_renderOverflows);
    _renderOverflows = <String>[];
    _overflowTearDownRegistered = false;
    if (found.isEmpty) return;
    fail(
      '화면이 넘쳤습니다 — ${found.length}건. E2E 가 지나는 화면은 잘린 곳 없이 그려져야 합니다.\n\n'
      '${found.join('\n\n──────────\n\n')}',
    );
  });
}

/// 로그아웃 상태에서 앱을 새로 띄운다. 재시작·재로그인 검증도 이것을 다시 부른다.
Future<void> bootSignedOut(WidgetTester tester) async {
  useMobileViewport(tester);
  assertRealApiConfig();
  // 앞선 부팅이 남아 있으면 그 ProviderScope 의 세션이 그대로 살아 있어, 토큰을
  // 지워도 새 트리가 로그인 화면 대신 대시보드로 간다. 재시작 검증이 조용히
  // "로그인된 채로 계속" 을 통과시키지 않도록 먼저 트리를 비운다.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await const FlutterSecureStorage().deleteAll();
  await bootstrap();
  // 감시는 `bootstrap()` **뒤에** 얹는다 — 그 안에서 핸들러가 교체되므로 앞에
  // 얹으면 그대로 지워진다.
  _watchForOverflow();
  await pumpUntil(tester, find.byType(SignInPage), step: '로그인 화면');
}

Future<void> loginAsMember(WidgetTester tester, {String? email}) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey<String>('member-login-email')),
      matching: find.byType(TextField),
    ),
    email ?? memberEmail,
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey<String>('member-login-password')),
      matching: find.byType(TextField),
    ),
    demoPassword,
  );
  await tester.tap(find.byKey(const ValueKey<String>('member-login-submit')));
  await pumpUntil(tester, find.byType(DashboardPage), step: '회원 로그인');
}

/// 슬롯 하나를 골라 예약 확정 버튼이 뜬 상태로 만든다.
///
/// 칩은 **토글**이라(같은 칩을 다시 누르면 선택이 풀린다) 한 번 누르는 것으로는
/// "선택됨" 을 보장할 수 없다. 앞선 조작이 이미 이 칩을 골라 둔 상태였다면 그 한 번이
/// 선택을 푸는 쪽으로 작동한다. 그래서 결과(확정 버튼)를 보고 필요하면 한 번 더 누른다.
Future<Finder> selectSlotForReserve(WidgetTester tester, String slotId) async {
  final Finder chip = find.byKey(ValueKey<String>('slot-chip-$slotId'));
  final Finder confirm = find.byKey(const ValueKey<String>('reserve-confirm'));
  await pumpUntil(tester, chip, step: '슬롯 칩');

  for (int attempt = 0; attempt < 3; attempt++) {
    // 목록이 길면(내 예약이 쌓였거나 자리가 많으면) 칩이 화면 밖으로 밀린다. 그 상태의
    // `tap` 은 예외 없이 **엉뚱한 곳을 누르고** 조용히 지나간다.
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
    while (confirm.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (confirm.evaluate().isNotEmpty) return confirm;
  }
  fail('[$e2ePhase] 슬롯 $slotId 를 골랐는데 예약 확정 버튼이 뜨지 않았습니다.');
}

/// 운동 탭 헤더 → 담당 트레이너 채팅 화면.
///
/// 헤더 버튼은 모든 메인 탭에 같은 모양으로 있고 담당 트레이너가 있어야 눌린다.
Future<void> openTrainerChat(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('nav-exercise')));
  await pumpUntil(tester, find.byType(ExercisePage), step: '운동 화면');
  final Finder button = find.byKey(const Key('trainerChatHeaderButton'));
  await pumpUntil(tester, button, step: '트레이너 채팅 버튼');

  // 버튼은 담당 트레이너가 **로드되기 전까지** onTap 이 null 이다. 그 사이의 탭은
  // 예외 없이 아무 일도 일으키지 않으므로, 화면이 열릴 때까지 다시 누른다.
  final Finder page = find.byType(TrainerChatPage);
  for (int attempt = 0; attempt < 10 && page.evaluate().isEmpty; attempt++) {
    await tester.tap(button);
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
    while (page.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  expect(page, findsWidgets, reason: '[$e2ePhase] 트레이너 채팅 화면이 열리지 않았습니다.');
}

/// 헬스장 탭(= 헬스장 찾기) → 헬스장 카드 → 상세 → 상담 보낼 트레이너 고르기 →
/// 상담 신청 폼.
///
/// 폼까지 UI 로 들어간다. 라우트를 직접 push 하면 "회원이 상담을 신청할 수 있다" 가
/// 아니라 "그 화면이 열린다" 만 검증하게 된다. (#640)
///
/// 연결된 헬스장이 없는 회원의 헬스장 탭은 **찾기 화면 자체**다(#1133) — 예전의
/// 추천 트레이너 레일은 그 상태에서 더 이상 없다.
Future<void> openConsultationForm(WidgetTester tester, String targetId) async {
  await openGymTab(tester);
  final Finder card = find.byKey(const Key('gym-card-$consultationGymId'));
  await pumpUntil(tester, find.byType(GymFinderView), step: '헬스장 찾기 화면');

  // 카드는 화면에 들어오기 전까지 **만들어지지 않는다**. `ensureVisible` 은 이미
  // 있는 위젯만 옮기므로, 지연 목록에서는 스크롤로 만들어 내야 한다.
  //
  // 목록을 키로 집는다 — 찾기 화면의 결과는 지도 위 시트 안에 있고(#1274) 그
  // 시트에는 스크롤이 둘(시트 자신과 결과 목록)이라, "화면 안의 유일한 스크롤"
  // 로는 어느 쪽인지 정해지지 않는다.
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      240,
      scrollable: find.descendant(
        of: find.byKey(const Key('gym-result-list')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(card);
  await tester.pump();
  await tester.tap(card);

  final Finder start = find.byKey(const Key('gym-consult-start'));
  await pumpUntil(tester, start, step: '헬스장 상담 신청 버튼');
  await tester.ensureVisible(start);
  await tester.pump();
  await tester.tap(start);

  // 상담은 트레이너 한 사람에게 간다 — 소속 트레이너 중에서 고른다.
  final Finder pick = find.byKey(Key('gym-consult-trainer-$targetId'));
  await pumpUntil(tester, pick, step: '상담 트레이너 고르기');
  await tester.ensureVisible(pick);
  await tester.pump();
  await tester.tap(pick);

  // 폼의 **맨 위** 를 기다린다. 제출 버튼은 목록 끝이라 아직 만들어지지 않았다.
  await pumpUntil(
    tester,
    find.byKey(const Key('consult-form')),
    step: '상담 신청 폼',
  );
  await pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('consult-goal-0')),
    step: '운동 목표 칩',
  );
}

/// 폼이 한 화면보다 길다. 아래쪽 위젯은 스크롤해서 **만들어 낸 뒤에야** 잡힌다.
Future<Finder> _revealInForm(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('consult-form')),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(target);
  await tester.pump();
  return target;
}

/// [submitConsultation] 이 넣는 희망 시각. 서버에 남는 값
/// (`preferred_time_slot`)이 `$consultStartTime-$consultEndTime` 이라,
/// 시나리오가 그대로 단언할 수 있다.
///
/// **저녁 시각인 이유**: 승인은 이 시각에 상담 일정을 만드는데, 겹침 판정이
/// (날짜, 시각) 정확히 같은 자리를 본다. 데모 시드가 오늘 트레이너 타임라인에
/// 놓는 10:00·12:00·15:00·17:00 을 쓰면 승인이 409 로 막힌다.
///
/// 트레이너 앱 쪽 하네스의 같은 이름 상수와 **값이 같아야 한다** — 두 앱은
/// 서로 다른 패키지라 공유할 수 없고, 트레이너 단계가 이 값을 그대로 단언한다.
const String consultStartTime = '21:00';

/// [consultStartTime] 의 종료 시각.
const String consultEndTime = '22:00';

/// [submitConsultation] 이 서버에 남기는 `preferred_time_slot` 값.
const String consultPreferredTimeSlot = '$consultStartTime-$consultEndTime';

/// 상담 신청 폼을 채우고 제출한다. 선택지는 **문구가 아니라 자리**로 고른다 —
/// 문구는 번역이 바뀌면 흔들린다.
///
/// 날짜는 달력 다이얼로그가 뜬 뒤 '확인' 을 눌러 **오늘** 로 확정한다. 서버가
/// 오늘 이전을 거부하므로 오늘이 항상 유효하다.
Future<void> submitConsultation(
  WidgetTester tester, {
  required int goalIndex,
  required String message,
}) async {
  Future<void> tapChip(String prefix, int index) async {
    final Finder chip = await _revealInForm(
      tester,
      find.byKey(ValueKey<String>('$prefix-$index')),
    );
    await tester.tap(chip);
    await tester.pump();
  }

  // 데이터 공유 동의 없이는 보낼 수 없다 (#1022) — 수락되는 순간 넘어가는 것이
  // 회원의 건강 기록이라, 신청 화면에서 동의를 받는다.
  //
  // 폼을 스크롤하기 **전에** 짚는다. 폼이 지연 목록이라 아래로 내려가면 맨 위의
  // 동의 줄은 트리에서 사라진다.
  final Finder consent = find.descendant(
    of: find.byKey(const Key('consult-data-sharing-notice')),
    matching: find.byType(Checkbox),
  );
  await pumpUntil(tester, consent, step: '데이터 공유 동의');
  await tester.tap(consent);
  await tester.pump();

  await tapChip('consult-goal', goalIndex);

  final Finder date = await _revealInForm(
    tester,
    find.byKey(const Key('consult-date')),
  );
  await tester.tap(date);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // 날짜는 공용 달력 다이얼로그(#1701)다 — 처음 고른 날이 오늘이라 확인만 누른다.
  final Finder dialog = find.byType(DatePickerDialog);
  await pumpUntil(tester, dialog, step: '날짜 선택 다이얼로그');
  final String dateOkLabel = MaterialLocalizations.of(
    tester.element(dialog),
  ).okButtonLabel;
  await tester.tap(
    find.descendant(of: dialog, matching: find.text(dateOkLabel)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // "시간 협의"는 없앴다(#1587) — 희망 시각은 필수다. 상담 시간 선택창은
  // 시작·종료를 한 창에서 고른다(#1779). 시계판을 돌리는 대신 시작·종료 칸에
  // `HH:mm` 을 직접 넣는다: 제스처보다 흔들리지 않고, 값도 아래 단언과 맞춰
  // 고정할 수 있다.
  final Finder time = await _revealInForm(
    tester,
    find.byKey(const Key('consult-time')),
  );
  await tester.tap(time);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  final Finder timeDialog = find.byType(AppTimeRangePickerDialog);
  await pumpUntil(tester, timeDialog, step: '희망 시각 선택창');
  await tester.enterText(
    find.byKey(const ValueKey<String>('consult-time-range-start-input')),
    consultStartTime,
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey<String>('consult-time-range-end-input')),
    consultEndTime,
  );
  await tester.pump();
  // 확인은 창 아래 두 버튼(취소 / 확인)의 오른쪽이다 — 문구는 로케일마다
  // 달라 자리로 고른다. 창이 길어도 두 버튼은 본문 스크롤 밖이라 늘 보인다.
  await tester.tap(
    find.descendant(of: timeDialog, matching: find.byType(AppButton)).last,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  final Finder box = await _revealInForm(
    tester,
    find.byKey(const Key('consult-message')),
  );
  await tester.enterText(box, message);
  await tester.pump();

  final Finder submit = await _revealInForm(
    tester,
    find.byKey(const Key('consult-submit')),
  );
  await tester.tap(submit);
}

/// 운동 탭 → 헬스장 서브탭. 담당 트레이너의 예약 패널이 있는 자리다.
Future<void> openGymTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('nav-exercise')));
  await pumpUntil(tester, find.byType(ExercisePage), step: '운동 화면');
  await tester.tap(find.byKey(const ValueKey<String>('exercise-subtab-1')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
