/// 데모와 실서버가 같은 화면에서 같은 진입점을 보이는지 비교한다. (#2792)
///
/// 데모와 실서버 화면이 다르면 데모가 기준이고, 실서버에 있는데 데모에 없는
/// 것은 데모에 더한다. 그런데 빈 목록·고정값·로컬 인터셉터의 라우트 누락·시드에
/// 없는 데이터 종류처럼 **데이터 때문에** 생기는 차이는 코드 텍스트에 드러나지
/// 않아 PR gate 의 검사(#2791)로는 못 잡는다(예: PT 일정이 데모에서만 빈 목록,
/// #2659). 여기서는 같은 화면을 두 번 그린다.
///
///  * **데모** — 앱의 목업 모드 그대로: `useMockApi: true`, 공유 픽스처로 시드한
///    drift, 목업 저장소. 데이터 provider 는 덮지 않는다 — 덮으면 데모가 실제로
///    무엇을 주는지 볼 수 없다.
///  * **실서버** — `useMockApi: false` 에 `dioProvider` 만 가짜 서버로 바꾼다.
///    가짜 서버는 실서버와 같은 모양의 고정 응답을 준다. 저장소·파서는 앱 것
///    그대로다.
///
/// 비교는 값이 아니라 진입점(탭·버튼·카드)이 **있다·없다** 만 본다 — 데모 시드의
/// 값이 바뀌어도 흔들리지 않게. 실서버 쪽은 고정 응답이라 진입점이 모두 서야
/// 한다. 데모에서 빠진 것이 있으면 데모를 실서버에 맞춘다.
///
/// 일부러 다르게 둔 곳은 `.github/demo-divergence-allowlist.txt`(PR gate 와 같은
/// 목록)에 적는다. 진입점이 [ParityEntry.allowlisted] 로 그 경로를 달고 있으면, 그
/// 줄이 목록에 남아 있는 동안 비교에서 뺀다.
///
/// **아이콘·키·문구로 진입점을 찾는다.** 화면의 아이콘·키·버튼 문구를 일괄로
/// 바꿀 때는 `test_e2e/`·`integration_test/` 와 함께 이 파일도 고친다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/demo_exercise.dart';
import '../helpers/demo_parity.dart';
import '../helpers/fixed_clock.dart';

/// 2026-08-20(목) 20:00 KST. 데모의 오늘 PT(18:00)와 가짜 서버의 오늘 PT(10:00)가
/// 모두 끝난 뒤다. 데모 픽스처는 오늘을 늘 PT 날로 둔다.
final DateTime _now = DateTime(2026, 8, 20, 20);

enum _Mode { demo, real }

Finder _keyPrefix(String prefix) => find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith(prefix),
);

// ---------------------------------------------------------------------------
// 실서버 대역
// ---------------------------------------------------------------------------

/// 실서버와 같은 모양의 고정 응답을 주는 가짜 서버. 모르는 경로는 404 다 —
/// 화면이 그 경로 없이도 진입점을 세우는지가 곧 실서버의 빈 응답과 같다.
class _FakeServer implements HttpClientAdapter {
  /// 404 로 답한 경로. 실패하면 메시지에 싣는다.
  final Set<String> unknown = <String>{};

  static const Map<String, Object?> _coach = <String, Object?>{
    'trainer_id': 'trainer-parity',
    'name': '박트레이너',
    'specialty': '퍼스널 트레이너',
    'career': '5년',
    'intro': '',
    'gym': <String, Object?>{'name': '비교 헬스장'},
    'goal': '',
  };

  static final Map<String, Object?> _routes = <String, Object?>{
    'GET /me/coach': _coach,
    // 오늘 끝난 수업 하나와 다음 주 예정 하나 — `오늘 완료한 PT` 카드와 그 안의
    // `다음 PT` 가 선다.
    'GET /me/coach/sessions': <Object?>[
      <String, Object?>{
        'id': 'session-today',
        'date': '2026-08-20',
        'time': '10:00',
        'client_name': '김회원',
        'type': '1:1 PT',
        'duration_minutes': 50,
        'status': '완료',
        'session_number': 3,
        'note': '자세가 좋아졌어요.',
        'program': <Object?>[
          <String, Object?>{'name': '스쿼트', 'sets': 3, 'reps': 12, 'weight': 40},
        ],
      },
      <String, Object?>{
        'id': 'session-next',
        'date': '2026-08-27',
        'time': '10:00',
        'client_name': '김회원',
        'type': '1:1 PT',
        'duration_minutes': 50,
        'status': '예정',
        'note': '',
        'program': <Object?>[],
      },
    ],
    'GET /reservations/me': <Object?>[],
    'GET /exercise/weeks/current': <String, Object?>{
      'sessions': <Object?>[],
      'day_labels': <Object?>['월', '화', '수', '목', '금', '토', '일'],
      'daily_minutes': <Object?>[30, 0, 30, 0, 0, 0, 0],
      'total_minutes': 60,
      'total_calories': 360,
      'streak_days': 1,
      'ai_coach_message': '',
    },
    'GET /notifications': <Object?>[
      <String, Object?>{
        'id': 'alert-1',
        'title': '트레이너가 메시지를 보냈어요',
        'body': '오늘 수업 수고하셨어요.',
        'time_ago': '방금',
        'category': 'coach_chat',
        'read': false,
      },
    ],
    'GET /notifications/unread-count': <String, Object?>{'unread': 1},
    'GET /me/coach/chat': <Object?>[
      <String, Object?>{
        'id': 'message-1',
        'sender': 'trainer',
        'body': '오늘 수업 수고하셨어요.',
        'time_label': '오전 10:50',
        'created_at': '2026-08-20T01:50:00Z',
      },
    ],
    'POST /me/coach/chat/read': <String, Object?>{},
    // 홈
    'GET /dashboard/summary': <String, Object?>{
      'indicators': <Object?>[
        <String, Object?>{
          'label': '칼로리',
          'current': 1500,
          'max': 2000,
          'unit': 'kcal',
        },
      ],
      'diet_entries': 3,
      'exercise_minutes': 30,
      'nutrition_week': <Object?>[
        for (int d = 0; d < 7; d++)
          <String, Object?>{'label': '$d', 'calories': 1500},
      ],
    },
    'GET /diet/recommendations': <String, Object?>{
      'items': <Object?>[
        <String, Object?>{'key': 'chicken_salad', 'reason_key': 'sodium'},
      ],
      'personalized': false,
      'trainer_pick': <String, Object?>{
        'slot': 'dinner',
        'name': '닭가슴살 스테이크',
        'tag': 'protein_high',
        'keyword': '고단백',
        'trainer_name': '박트레이너',
      },
    },
    'GET /users/me/profile': <String, Object?>{
      'name': '김회원',
      'email': 'member@oncare.test',
    },
    // 식단
    'GET /diet/days/today': <String, Object?>{
      'entries': <Object?>[
        <String, Object?>{
          'id': 'meal-1',
          'meal_type': 'lunch',
          'time_label': '12:30',
          'foods': <Object?>[
            <String, Object?>{'name': '현미밥', 'calories': 300},
          ],
          'total_calories': 300,
        },
      ],
      'total_calories': 300,
      'total_sodium_mg': 400,
      'total_sugar_g': 2,
      'ai_coach_message': '',
    },
    'GET /diet/advice': <String, Object?>{
      'message': '단백질을 조금 더 챙겨 보세요.',
      'analysis': '',
      'action': '',
    },
    'GET /me/records/span': <String, Object?>{
      'diet_first_date': '2026-08-01',
      'exercise_first_date': '2026-08-01',
    },
    // MY
    'GET /users/me/health': <String, Object?>{
      'profile': <String, Object?>{
        'name': '김회원',
        'email': 'member@oncare.test',
      },
      'risk': <String, Object?>{'title': '', 'body': '', 'level': 'low'},
      'activity_points': 120,
      'settings': <Object?>[],
    },
    'GET /me/activity-calendar': <String, Object?>{
      'days': <Object?>[],
      'color': <String, Object?>{'current': 'blue'},
    },
    'GET /me/profile-pet': <String, Object?>{'pet': null},
    'GET /me/gym': <String, Object?>{'id': 'gym-parity', 'name': '비교 헬스장'},
    'GET /trainers/trainer-parity': <String, Object?>{
      'id': 'trainer-parity',
      'name': '박트레이너',
      'gym_id': 'gym-parity',
    },
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String key = '${options.method} ${options.uri.path}';
    if (!_routes.containsKey(key)) {
      unknown.add(key);
      return _json(<String, Object?>{'detail': 'not found'}, 404);
    }
    return _json(_routes[key]);
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

// ---------------------------------------------------------------------------
// 두 모드로 띄우기
// ---------------------------------------------------------------------------

/// [mode] 로 [page] 를 띄운다. 실서버 모드면 가짜 서버를 돌려준다.
Future<_FakeServer?> _pump(WidgetTester tester, _Mode mode, Widget page) async {
  final AppDatabase db = mode == _Mode.demo
      ? await seededDemoDatabase(tester)
      : emptyDemoDatabase();
  final _FakeServer? server = mode == _Mode.real ? _FakeServer() : null;

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appLoggerProvider.overrideWithValue(Logger(level: Level.off)),
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'http://localhost',
            useMockApi: mode == _Mode.demo,
          ),
        ),
        appDatabaseProvider.overrideWithValue(db),
        if (server != null)
          dioProvider.overrideWith((ref) {
            final Dio dio = Dio(
              BaseOptions(
                baseUrl: 'http://localhost',
                validateStatus: (int? status) => status != null && status < 400,
              ),
            )..httpClientAdapter = server;
            ref.onDispose(dio.close);
            return dio;
          }),
        // 배지의 주기적 폴링 — 두 모드 모두 멈춘다. 배지 숫자는 비교하지 않는다.
        notificationUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
        coachInvitesProvider.overrideWith(
          (ref) => Stream<List<CoachInvite>>.value(const <CoachInvite>[]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  // 목업 저장소의 지연과 첫 응답을 기다린다. 채팅처럼 폴링하는 화면이 있어
  // `pumpAndSettle` 대신 정해진 만큼만 돈다.
  for (int i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return server;
}

/// 지금 화면에 선 진입점의 이름.
Set<String> _present(
  WidgetTester tester,
  Type page,
  List<ParityEntry> entries,
) {
  final AppLocalizations l = AppLocalizations.of(
    tester.element(find.byType(page)),
  );
  return <String>{
    for (final ParityEntry e in entries)
      if (e.find(l).evaluate().isNotEmpty) e.name,
  };
}

/// [page] 를 두 모드로 그려 [entries] 를 비교한다.
Future<void> _expectParity(
  WidgetTester tester, {
  required Widget page,
  required List<ParityEntry> entries,
}) async {
  useFixedKstDate(_now);
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final List<ParityEntry> compared = withoutAllowlisted(entries);

  final _FakeServer? server = await _pump(tester, _Mode.real, page);
  final Set<String> real = _present(tester, page.runtimeType, compared);
  // 탭을 떠나며 폴링을 끝낸다 — 다음 모드가 새 ProviderScope 로 시작한다.
  await tester.pumpWidget(const SizedBox.shrink());

  await _pump(tester, _Mode.demo, page);
  final Set<String> demo = _present(tester, page.runtimeType, compared);
  await tester.pumpWidget(const SizedBox.shrink());

  final List<String> names = <String>[
    for (final ParityEntry e in compared) e.name,
  ];
  expect(
    real,
    names.toSet(),
    reason:
        '실서버 대역에서 진입점이 서지 않았다 — 대역 응답을 고친다. '
        '404 로 답한 경로: ${(server?.unknown.toList() ?? <String>[])..sort()}',
  );
  expect(
    <String>[
      for (final String n in names)
        if (!demo.contains(n)) n,
    ],
    isEmpty,
    reason:
        '실서버에 있는 진입점이 데모에 없다. 데모가 기준이므로 데모(시드·목업 '
        '저장소·로컬 인터셉터)에 더한다. 일부러 다르게 둔 것이면 '
        '.github/demo-divergence-allowlist.txt 에 적는다.',
  );
}

void main() {
  testWidgets('운동 탭 — 알림·채팅 입구, 하위 탭, 오늘 완료한 PT, 다음 PT', (
    WidgetTester tester,
  ) async {
    await _expectParity(
      tester,
      page: const ExercisePage(),
      entries: <ParityEntry>[
        ParityEntry('알림 종', (l) => find.byTooltip(l.pageNotificationTitle)),
        ParityEntry(
          '트레이너 채팅 버튼',
          (_) => find.byKey(const Key('trainerChatHeaderButton')),
        ),
        ParityEntry(
          '운동 기록 탭',
          (_) => find.byKey(const ValueKey<String>('exercise-subtab-0')),
        ),
        ParityEntry(
          '헬스장 탭',
          (_) => find.byKey(const ValueKey<String>('exercise-subtab-1')),
        ),
        ParityEntry(
          '오늘 완료한 PT 카드',
          (_) => find.byKey(const Key('completedPtSessionCard')),
        ),
        ParityEntry(
          '다음 PT 일정',
          (l) => find.byWidgetPredicate(
            (Widget w) =>
                w is AppTag &&
                w.icon == AppIcons.eventAvailable &&
                w.label != l.exNextPtNone,
          ),
        ),
      ],
    );
  });

  testWidgets('알림함 — 알림 줄과 모두 읽음', (WidgetTester tester) async {
    await _expectParity(
      tester,
      page: const NotificationPage(),
      entries: <ParityEntry>[
        ParityEntry('알림 줄', (_) => _keyPrefix('notification-row-')),
        ParityEntry(
          '모두 읽음',
          (l) => find.byWidgetPredicate(
            (Widget w) =>
                w is AppButton &&
                w.label == l.alertMarkAllRead &&
                w.onPressed != null,
          ),
        ),
      ],
    );
  });

  testWidgets('코치 채팅 — 메시지·입력·이모티콘·사진 첨부', (WidgetTester tester) async {
    await _expectParity(
      tester,
      page: const TrainerChatPage(trainerName: '박트레이너'),
      entries: <ParityEntry>[
        ParityEntry('메시지', (_) => _keyPrefix('coach-message-bubble-')),
        ParityEntry(
          '입력줄',
          (_) => find.byKey(const ValueKey<String>('member-chat-input')),
        ),
        ParityEntry('보내기', (l) => find.byTooltip(l.a11ySendMessage)),
        ParityEntry('이모티콘', (l) => find.byTooltip(l.a11yOpenEmotes)),
        ParityEntry('사진 첨부', (l) => find.byTooltip(l.coachPhotoAttach)),
      ],
    );
  });

  testWidgets('홈 — 알림·채팅 입구, AI 코칭, 자세히, 주간 그래프, 추천 식단', (
    WidgetTester tester,
  ) async {
    await _expectParity(
      tester,
      page: const DashboardPage(),
      entries: <ParityEntry>[
        ParityEntry('알림 종', (l) => find.byTooltip(l.pageNotificationTitle)),
        ParityEntry(
          '트레이너 채팅 버튼',
          (_) => find.byKey(const Key('trainerChatHeaderButton')),
        ),
        ParityEntry(
          'AI 코칭 배너',
          (_) => find.byKey(const ValueKey<String>('home-coaching-banner')),
        ),
        ParityEntry('자세히', (l) => find.text(l.homeDetails)),
        ParityEntry(
          '주간 칼로리 그래프',
          (_) =>
              find.byKey(const ValueKey<String>('dashboard-nutrition-chart')),
        ),
        ParityEntry(
          '운동 주간 카드',
          (_) => find.byKey(const ValueKey<String>('dashboard-exercise-week')),
        ),
        ParityEntry('추천 식단', (_) => find.byKey(const Key('rec-meal-source'))),
        ParityEntry('트레이너 추천 식단', (l) => find.text(l.homeMealSourceTrainer)),
      ],
    );
  });

  testWidgets('식단 — 알림·채팅 입구, 주 이동, 기간 탭, 요약, AI 피드백, 끼니', (
    WidgetTester tester,
  ) async {
    await _expectParity(
      tester,
      page: const DietRecordPage(),
      entries: <ParityEntry>[
        ParityEntry('알림 종', (l) => find.byTooltip(l.pageNotificationTitle)),
        ParityEntry(
          '트레이너 채팅 버튼',
          (_) => find.byKey(const Key('trainerChatHeaderButton')),
        ),
        ParityEntry('지난 주', (l) => find.byTooltip(l.a11yPrevWeek)),
        ParityEntry(
          '기간 탭',
          (_) => find.byKey(const ValueKey<String>('diet-period-toggle')),
        ),
        ParityEntry(
          '영양 요약',
          (_) => find.byKey(const Key('nutrition-summary-card')),
        ),
        ParityEntry('AI 피드백', (l) => find.text(l.dietAiFeedback)),
        ParityEntry(
          '끼니 기록 머리',
          (_) => find.byKey(const ValueKey<String>('meal-log-header')),
        ),
        ParityEntry(
          '끼니 추가',
          (l) => find.byWidgetPredicate(
            (Widget w) => w is AppButton && w.label == l.dietAddMeal,
          ),
        ),
        ParityEntry('끼니 카드', (_) => _keyPrefix('mealCard-')),
      ],
    );
  });

  testWidgets('MY — 알림·채팅 입구, 헬스장·트레이너, 리포트, 포인트, 설정, 로그아웃', (
    WidgetTester tester,
  ) async {
    await _expectParity(
      tester,
      page: const MyHealthPage(),
      entries: <ParityEntry>[
        ParityEntry('알림 종', (l) => find.byTooltip(l.pageNotificationTitle)),
        ParityEntry(
          '트레이너 채팅 버튼',
          (_) => find.byKey(const Key('trainerChatHeaderButton')),
        ),
        ParityEntry('프로필', (_) => find.byKey(const Key('profileNameLine'))),
        ParityEntry('트레이너 연동', (l) => find.text(l.trainerSyncEntryLabel)),
        ParityEntry('헬스장 카드', (_) => find.byKey(const Key('my-gym-info-card'))),
        ParityEntry(
          '담당 트레이너',
          (_) => find.byKey(const Key('gym-trainer-line-mine')),
        ),
        ParityEntry(
          '코치 리포트',
          (_) => find.byKey(const ValueKey<String>('my-coach-reports-entry')),
        ),
        ParityEntry('포인트', (_) => find.byKey(const Key('pointsBanner'))),
        ParityEntry('프로필 설정', (l) => find.text(l.myProfileTitle)),
        ParityEntry('건강 목표', (l) => find.text(l.myHealthGoalsTitle)),
        ParityEntry('알림 설정', (l) => find.text(l.myNotifTitle)),
        ParityEntry('이용 안내', (l) => find.text(l.myGuideTitle)),
        ParityEntry('고객 지원', (l) => find.text(l.mySupportTitle)),
        ParityEntry(
          '로그아웃',
          (_) => find.byKey(const ValueKey<String>('my-logout-button')),
        ),
      ],
    );
  });

  test('예외 목록을 읽는다', () {
    // 형식이 어긋나면 위 비교가 모두 무너진다 — 따로 드러낸다.
    expect(readDemoDivergenceAllowlist(), isNotEmpty);
  });
}
