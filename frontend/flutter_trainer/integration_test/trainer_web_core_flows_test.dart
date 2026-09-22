import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:oncare_trainer/app/bootstrap.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_shell.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/features/auth/presentation/pages/trainer_sign_in_page.dart';
import 'package:oncare_trainer/features/clients/presentation/pages/clients_page.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/diet_view.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/workout_view.dart';
import 'package:oncare_trainer/features/consultations/presentation/pages/consultations_page.dart';
import 'package:oncare_trainer/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:oncare_trainer/features/messages/presentation/pages/messages_page.dart';
import 'package:oncare_trainer/features/schedule/presentation/pages/schedule_page.dart';
import 'package:oncare_ui/oncare_ui.dart'
    show AppButton, AppDialog, OnCareBrand;

const String _trainerEmail = 'trainer@oncare.com';
const String _memberEmail = 'jisu@oncare.com';
const String _password = 'oncare123';
const String _clientId = 'user-7d4e9a2c5f18';
const String _consultationMemberName = '이지수';
const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const Duration _fixtureApiTimeout = Duration(seconds: 15);
const String _rejectionNote = '#624 E2E 반복 실행 확인';

/// 회원 스레드가 열린 자리 — 채팅은 이제 `/messages` 가 소유한다. (#692)
final String _chatLocation = AppRoutes.messagesFor(_clientId);

/// 열린 스레드를 가리키는 finder. `ChatView` 타입으로 찾으면 고객 상세에도 같은
/// 위젯이 있던 시절 기준이라, 스레드가 실제로 **메시지 화면**에 떴는지 못 가린다.
final Finder _chatThread = find.byKey(
  const ValueKey<String>('messages-thread-$_clientId'),
);

/// 초안이 빠져나간 입력창 — 전송이 서버까지 갔다는 신호다.
/// 입력창은 공용 입력줄(`AppChatInputBar`) 안에 있어, 키는 입력줄 전체에 붙는다(#1704).
final Finder _chatComposer = find.byKey(
  const ValueKey<String>('client-chat-input'),
);

final Finder _clearedChatInput = find.descendant(
  of: _chatComposer,
  matching: find.byWidgetPredicate(
    (widget) => widget is TextField && (widget.controller?.text ?? '').isEmpty,
    description: 'cleared chat composer',
  ),
);

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (finder.evaluate().isEmpty &&
      tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets, reason: '$step timed out after $timeout.');
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (finder.evaluate().isNotEmpty &&
      tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsNothing, reason: '$step timed out after $timeout.');
}

String _location(WidgetTester tester) {
  final context = tester.element(find.byType(AppShell));
  return GoRouter.of(context).routeInformationProvider.value.uri.toString();
}

Future<void> _bootSignedOut(WidgetTester tester) async {
  final config = AppConfig.fromEnvironment();
  expect(
    config.useMockApi,
    isFalse,
    reason: 'Run with --dart-define=USE_MOCK_API=false.',
  );
  expect(
    config.apiBaseUrl,
    _apiBaseUrl,
    reason: 'The app and E2E fixture API must use the same API_BASE_URL.',
  );
  expect(_apiBaseUrl, isNotEmpty);

  await const FlutterSecureStorage().deleteAll();
  await bootstrap();
  await _pumpUntil(
    tester,
    find.byType(TrainerSignInPage),
    step: 'login screen boot',
  );
}

Future<void> _loginThroughUi(WidgetTester tester) async {
  final email = find.descendant(
    of: find.byKey(const ValueKey<String>('trainer-login-email')),
    matching: find.byType(TextField),
  );
  final password = find.descendant(
    of: find.byKey(const ValueKey<String>('trainer-login-password')),
    matching: find.byType(TextField),
  );
  await tester.enterText(email, _trainerEmail);
  await tester.enterText(password, _password);
  await tester.tap(find.byKey(const ValueKey<String>('trainer-login-submit')));
  await _pumpUntil(tester, find.byType(DashboardPage), step: 'trainer login');
  expect(_location(tester), AppRoutes.dashboard);
}

Future<void> _openSidebar(WidgetTester tester, String route) async {
  await tester.tap(find.byKey(ValueKey<String>('sidebar-$route')));
  await tester.pump();
}

Future<void> _openClient(WidgetTester tester) async {
  await _openSidebar(tester, AppRoutes.clients);
  await _pumpUntil(
    tester,
    find.byType(ClientsPage),
    step: 'clients navigation',
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('client-$_clientId')),
    step: 'seed client load',
  );
  await tester.tap(find.byKey(const ValueKey<String>('client-$_clientId')));
  await _pumpUntil(tester, find.byType(DietView), step: 'client diet section');
  expect(_location(tester), AppRoutes.clientDetail(_clientId));
}

/// 사이드바 → 메시지 → 회원 스레드.
///
/// 트레이너 웹 Figma 정렬(#665, #676) 이후 채팅은 고객 상세의 `client-chat-button`
/// 이 아니라 **메시지 화면**에 있다. 고객 상세의 메시지 버튼도 결국 여기로 보내고
/// (`/clients/<id>/chat` 은 라우터가 `/messages?client=<id>` 로 넘긴다), 회원 스레드는
/// `messages-thread-<id>` 로 뜬다. (#692)
Future<void> _openClientChat(WidgetTester tester) async {
  await _openSidebar(tester, AppRoutes.messages);
  await _pumpUntil(
    tester,
    find.byType(MessagesPage),
    step: 'messages navigation',
  );
  final conversation = find.byKey(
    const ValueKey<String>('messages-conversation-$_clientId'),
  );
  await _pumpUntil(tester, conversation, step: 'client conversation load');
  await tester.tap(conversation);
  await _pumpUntil(tester, _chatThread, step: 'client chat thread');
  expect(_location(tester), _chatLocation);
}

/// 앱을 통째로 다시 띄운다 — 새로고침에 준하는 재부팅.
///
/// integration_test 에는 WebDriver 새로고침 명령이 없다. 프로덕션 루트를 버리고
/// 다시 부팅하면 새로고침이 기대는 계약 하나가 그대로 걸린다: **보안 저장소의 세션이
/// 살아남아 로그인 화면으로 되돌아가지 않는가.**
///
/// 다만 **여기서 딥링크 복원은 확인할 수 없다.** 진짜 새로고침은 페이지를 다시
/// 읽어 부팅 위치를 다시 계산하지만, 이 재부팅은 같은 페이지 안에서 위젯 트리만
/// 다시 세운다 — 부팅 위치는 페이지가 처음 열린 주소(`/`)로 고정된다. 그래서 세션이
/// 복원되면 인증 게이트가 대시보드로 보낸다. 이 스위트가 처음부터 딥링크 복원을
/// 단언하고 있었지만, 스크립트의 헬스 체크가 막혀 한 번도 실행되지 않아 드러나지
/// 않았다. (#692)
///
/// 브라우저 URL 로 돌아오는 계약 자체는 #701 에서 라우터에 들어갔고, 부팅 위치를
/// 주입하는 위젯 테스트(`test/app/router/app_router_test.dart`)가 지킨다.
Future<void> _reboot(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await bootstrap();
  // 셸이 떴다는 것 자체가 세션이 살아남았다는 뜻이다 — 복원에 실패하면 인증 게이트가
  // 로그인 화면을 붙들고 있어 셸이 아예 오지 않는다.
  await _pumpUntil(tester, find.byType(AppShell), step: 'app reboot');
  // 로그인 화면은 라우트가 걷히는 동안 한두 프레임 더 트리에 남는다. 곧바로 단언하면
  // 세션이 멀쩡한데도 "복원 실패" 로 잡힌다.
  await _pumpUntilAbsent(
    tester,
    find.byType(TrainerSignInPage),
    step: 'sign-in screen dismissed after reboot',
  );
  expect(_location(tester), AppRoutes.dashboard);
}

String _ymd(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// 픽스처 전용 클라이언트. 앱이 쓰는 Dio 와 별개다.
final Dio _fixtureApi = Dio(
  BaseOptions(
    // 분석 시점에는 dart-define 이 없어 이 상수가 '' 로 보인다. 기본값과 같다고
    // 잡히지만, 실행 시에는 러너가 넘긴 주소가 들어온다.
    // ignore: avoid_redundant_argument_values
    baseUrl: _apiBaseUrl,
    connectTimeout: _fixtureApiTimeout,
    sendTimeout: _fixtureApiTimeout,
    receiveTimeout: _fixtureApiTimeout,
  ),
);

/// 회원 토큰 — **한 번만 받아 재사용한다.**
///
/// 각 테스트가 로그아웃 상태에서 부팅하므로 화면 로그인만으로도 한 번 돌 때 네 번이다.
/// 픽스처까지 매번 로그인하면 백엔드 인증 한도(IP·엔드포인트당 분당 10 회,
/// `rate_limit_auth_per_minute`)에 걸려, 검증에 닿기도 전에 429 로 죽는다. 스위트를
/// 연달아 돌리면 특히 그렇다. (CodeRabbit 지적)
String? _cachedMemberToken;

Future<Options> _memberAuth() async {
  final cached = _cachedMemberToken;
  if (cached == null) {
    final login = await _fixtureApi.post<Map<String, dynamic>>(
      '/auth/login',
      data: <String, String>{'username': _memberEmail, 'password': _password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    _cachedMemberToken = login.data!['access_token'] as String;
  }
  return Options(
    headers: <String, String>{'Authorization': 'Bearer $_cachedMemberToken'},
  );
}

/// 트레이너 토큰 — 회원 토큰과 같은 이유로 한 번만 받는다(인증 한도).
///
/// 상담은 트레이너가 연 자리를 골라 신청하므로(#1873), 픽스처가 자리를 열 때 쓴다.
String? _cachedTrainerToken;

Future<Options> _trainerAuth() async {
  final cached = _cachedTrainerToken;
  if (cached == null) {
    final login = await _fixtureApi.post<Map<String, dynamic>>(
      '/auth/login',
      data: <String, String>{'username': _trainerEmail, 'password': _password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    _cachedTrainerToken = login.data!['access_token'] as String;
  }
  return Options(
    headers: <String, String>{'Authorization': 'Bearer $_cachedTrainerToken'},
  );
}

/// 상담을 신청할 빈 자리 하나의 id. (#1873)
///
/// 이미 열린 자리가 있으면 그것을 쓴다 — 이 스위트는 상담을 거절로 끝내고 거절은
/// 자리를 되돌려 주므로, 다음 실행이 같은 자리를 다시 고른다. 매번 새로 열면 로컬
/// DB 에 자리가 한없이 쌓인다. 없을 때만 모레 저녁에 연다(폼 하한 4시간을 넘긴다).
Future<String> _openConsultationSlot() async {
  final open = await _fixtureApi.get<List<dynamic>>(
    '/consultations/slots',
    queryParameters: <String, String>{'trainer_id': 'trainer-demo'},
    options: await _memberAuth(),
  );
  final slots = open.data ?? const <dynamic>[];
  if (slots.isNotEmpty) {
    return (slots.first as Map<String, dynamic>)['id'] as String;
  }
  final twoDays = DateTime.now().add(const Duration(days: 2));
  final created = await _fixtureApi.post<Map<String, dynamic>>(
    '/trainer/reservation-slots',
    options: await _trainerAuth(),
    data: <String, Object?>{
      'starts_at': DateTime(
        twoDays.year,
        twoDays.month,
        twoDays.day,
        19,
      ).toUtc().toIso8601String(),
      'duration_minutes': 30,
      'session_type': '1:1 PT',
    },
  );
  return created.data!['id'] as String;
}

/// 회원 계정으로 본 상담 요청 목록. 픽스처 준비와 결과 확인이 같은 창구를 쓴다.
Future<List<Map<String, dynamic>>> _memberConsultations() async {
  final mine = await _fixtureApi.get<List<dynamic>>(
    '/consultations/me',
    options: await _memberAuth(),
  );
  return <Map<String, dynamic>>[
    for (final item in mine.data ?? const <dynamic>[])
      item as Map<String, dynamic>,
  ];
}

/// 회원이 보는 상담 요청 한 건 — 트레이너가 남긴 결과·사유가 그대로 오는지 본다.
Future<Map<String, dynamic>> _memberConsultation(String id) async {
  final rows = await _memberConsultations();
  return rows.firstWhere(
    (row) => row['id'] == id,
    orElse: () => throw StateError('상담 요청 $id 이 회원 목록에 없습니다.'),
  );
}

Future<String> _ensurePendingConsultation() async {
  for (final row in await _memberConsultations()) {
    if (row['status'] == 'pending' && row['trainer_id'] == 'trainer-demo') {
      return row['id'] as String;
    }
  }

  final created = await _fixtureApi.post<Map<String, dynamic>>(
    '/consultations',
    options: await _memberAuth(),
    data: <String, Object?>{
      'target_type': 'trainer',
      'trainer_id': 'trainer-demo',
      'exercise_goal': 'fitness',
      'health_purpose_type': 'general',
      'health_purpose_detail': null,
      // 희망 날짜·시각 대신 트레이너가 연 자리를 고른다(#1873).
      'slot_id': await _openConsultationSlot(),
      'message': '#624 브라우저 E2E 상담 요청',
      // 동의 없이는 서버가 받지 않는다(#1022).
      'data_sharing_consent': true,
    },
  );
  return created.data!['id'] as String;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, client evidence, and a session that survives a reboot', (
    tester,
  ) async {
    await _bootSignedOut(tester);
    await _loginThroughUi(tester);
    await _openClient(tester);

    // 식단·운동은 더 이상 서로 다른 탭이 아니다 — 한 스크롤에 함께 있고 URL 의
    // section 은 순서만 정한다(#665, #676). 둘 다 떠 있는지로 확인한다.
    await _pumpUntil(
      tester,
      find.byType(WorkoutView),
      step: 'client workout evidence',
    );
    expect(find.byType(DietView), findsWidgets);

    await _openClientChat(tester);

    // 재부팅해도 로그인 화면으로 되돌아가지 않는다. 열려 있던 스레드로는 돌아오지
    // 않는다 — 라우터가 시작 위치를 로그인 화면으로 고정해 두어 세션이 복원되면
    // 대시보드로 간다(`_reboot` 참고).
    await _reboot(tester);
    await _openClientChat(tester);
  });

  testWidgets('chat message is sent once and survives page re-entry', (
    tester,
  ) async {
    await _bootSignedOut(tester);
    await _loginThroughUi(tester);
    await _openClientChat(tester);

    final message = '#624 E2E ${DateTime.now().toUtc().toIso8601String()}';
    await tester.enterText(
      find.byKey(const ValueKey<String>('client-chat-input')),
      message,
    );
    // `enterText` 는 프레임을 그려 주지 않는다. 안 그리고 바로 누르면 전송 핸들러가
    // 빈 입력을 읽고 조용히 돌아간다.
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: _chatComposer,
        matching: find.byIcon(Icons.send_rounded),
      ),
    );
    // 입력창은 **서버 저장이 끝난 뒤에만** 비워진다(`ChatView._send`) — 실패하면 초안이
    // 그대로 남는다. 입력창이 비는 것을 기다려야 "보냈다" 를 기다리는 것이 된다.
    // 글자만 찾으면 입력창에 남은 초안이 잡혀, 전송이 안 나가도 통과한다.
    await _pumpUntil(tester, _clearedChatInput, step: 'chat send accepted');
    await _pumpUntil(tester, find.text(message), step: 'chat send result');
    expect(find.text(message), findsOneWidget);

    // 재부팅하고 스레드로 다시 들어오면, 방금 보낸 말이 로컬 상태가 아니라 서버에서
    // 다시 온다. 한 건으로만 남는지도 여기서 걸린다(중복 발신 회귀).
    await _reboot(tester);
    await _openClientChat(tester);
    await _pumpUntil(
      tester,
      find.text(message),
      step: 'chat server refetch after re-entry',
    );
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('pending consultation is rejected through its dialog', (
    tester,
  ) async {
    final consultationId = await _ensurePendingConsultation();
    await _bootSignedOut(tester);
    await _loginThroughUi(tester);

    // 스케줄의 인박스 아이콘은 현재 스케줄 위에 상담 요청 모달을 연다.
    await _openSidebar(tester, AppRoutes.schedule);
    await _pumpUntil(
      tester,
      find.byType(SchedulePage),
      step: 'schedule navigation',
    );
    await tester.tap(find.byKey(const Key('consult-inbox-entry')));
    await _pumpUntil(
      tester,
      find.byType(ConsultationsPage),
      step: 'consultation inbox page',
    );

    final requestKey = ValueKey<String>('consultation-$consultationId');
    await _pumpUntil(
      tester,
      find.byKey(requestKey),
      step: 'prepared pending consultation',
    );
    expect(find.text(_consultationMemberName), findsWidgets);
    // 거절 버튼 키는 카드마다 같으므로 요청 카드 안에서 찾는다 — 대기 중인 요청이
    // 여러 건이면 그냥 누르는 순간 남의 요청을 거절한다.
    await tester.tap(
      find.descendant(
        of: find.byKey(requestKey),
        matching: find.byKey(
          ValueKey<String>('consultation-reject-$consultationId'),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      find.byType(AppDialog),
      step: 'consultation rejection dialog',
    );
    await tester.enterText(
      find.byKey(const Key('consultation-reject-reason')),
      _rejectionNote,
    );
    // 사유가 비면 확인 버튼이 비활성이다. `enterText` 는 프레임을 그려 주지 않으므로
    // 여기서 한 번 그려야 버튼이 눌리는 상태로 바뀐다 — 안 그리면 탭이 조용히
    // 무시되고 다이얼로그가 그대로 남는다.
    final rejectConfirm = find.byWidgetPredicate(
      (widget) =>
          widget is AppButton &&
          widget.key == const Key('consultation-reject-confirm') &&
          widget.onPressed != null,
      description: 'enabled rejection confirm button',
    );
    await _pumpUntil(tester, rejectConfirm, step: 'rejection note accepted');
    await tester.tap(rejectConfirm);
    // 시트는 대기 중인 요청만 보여 준다 — 거절한 건은 목록에서 빠진다.
    await _pumpUntilAbsent(
      tester,
      find.byKey(requestKey),
      step: 'pending consultation list refresh',
    );

    // 시트에는 처리 이력을 다시 여는 자리가 없다(예전 페이지의 "전체 보기"). 사유가
    // 회원에게 그대로 갔는지는 회원 계정으로 서버에 물어 확인한다.
    final decided = await _memberConsultation(consultationId);
    expect(decided['status'], 'rejected');
    expect(decided['decision_note'], _rejectionNote);
  });

  testWidgets('schedule date selection opens the booked client', (
    tester,
  ) async {
    await _bootSignedOut(tester);
    await _loginThroughUi(tester);
    await _openSidebar(tester, AppRoutes.schedule);
    await _pumpUntil(
      tester,
      find.byType(SchedulePage),
      step: 'schedule navigation',
    );

    // 보기는 주간 시간표 하나뿐이라 라우트에 `v=` 가 없다(#988).
    expect(_location(tester), isNot(contains('v=')));

    // 시간표는 월~일 한 주만 보여 준다. 같은 주 안의 다른 날을 고른다 —
    // 내일은 다음 주일 수 있어 요일 칸이 화면에 없을 수 있다.
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final anotherDay = _ymd(monday) == _ymd(today)
        ? monday.add(const Duration(days: 1))
        : monday;
    await tester.tap(
      find.byKey(ValueKey<String>('schedule-day-${_ymd(anotherDay)}')),
    );
    await tester.pump();
    expect(_location(tester), contains('d=${_ymd(anotherDay)}'));
    final selectedDay = find.descendant(
      of: find.byKey(ValueKey<String>('schedule-day-${_ymd(anotherDay)}')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color ==
                OnCareBrand.trainer.surface,
      ),
    );
    expect(
      selectedDay,
      findsOneWidget,
      reason: 'selected schedule date and URL diverged',
    );
    await tester.tap(
      find.byKey(ValueKey<String>('schedule-day-${_ymd(today)}')),
    );
    await _pumpUntil(
      tester,
      find.text('김민수'),
      step: 'booked client schedule block',
    );

    // 시간표의 블록을 누르면 상세 패널이 그 세션을 펼친 채로 연다.
    await tester.tap(find.text('김민수').first);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('session-delete-chip')),
      step: 'booked client actions',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('week-detail')),
        matching: find.text('김민수'),
      ),
      findsWidgets,
      reason: 'detail panel did not open the booked client',
    );
  });
}
