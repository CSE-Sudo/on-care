/// 영어 로케일 회귀 방지 (#847).
///
/// 다국어의 실패는 조용하다 — 문구 하나를 arb 로 옮기지 않아도 한국어 화면은
/// 멀쩡하고, 영어로 켰을 때만 그 자리만 한국어로 남는다. 그래서 화면을 영어로
/// 띄워 **한글이 남아 있지 않은지**를 직접 본다. 트레이너 앱이 #501 에서
/// 세운 관문과 같은 성격이다.
///
/// **화면 전체가 아니라 위젯 단위로 본다.** 회원 앱은 목업 모드에서 가상의 서버
/// 응답(끼니 이름·코치 문구·트레이너 이름 같은 한국어 콘텐츠)을 그린다. 그것은
/// 앱이 쓴 문구가 아니라 데이터라 번역 대상이 아니므로, 데이터가 비어 있는 상태의
/// 위젯을 띄워 **앱이 쓴 문구만** 남긴다.
///
/// 의도적으로 한국어인 값(여기서 걸리지 않는 것):
///  * 계약값 — `health_focus` 의 건강 목표 저장 값(`체중 감량` 등), `exercise_flows` 의
///    `_weekdayLabels`(서버로 나가는 `dayLabel`), `ScheduleCategory`·수행 강도의
///    enum 값. 화면에는 표시 문구가 대신 그려진다.
///  * 개발자용 문구 — `session_controller` 의 `Exception`, 카카오맵 로더의
///    `StateError`. 화면에 닿지 않는다(로그인 실패는 `authSignInFailed` 를 띄운다).
///  * 데모 시드 — 목업 리포지터리가 만든 가상의 콘텐츠.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/domain/repositories/notification_repository.dart';
import 'package:oncare/features/notification/presentation/controllers/notification_controller.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare/features/schedule/domain/entities/schedule_event.dart';
import 'package:oncare/features/schedule/presentation/controllers/schedule_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/modals/add_event_dialog.dart';
import 'package:oncare/shared/widgets/modals/day_events_sheet.dart';
import 'package:oncare/shared/widgets/modals/schedule_calendar_sheet.dart';

const AppConfig _mockConfig = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://example.test',
  useMockApi: true,
);

final RegExp _hangul = RegExp(r'[가-힣]');

/// 화면에 그려진 모든 `Text` 위젯의 문자열.
Iterable<String> _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((String s) => s.trim().isNotEmpty);

/// `Semantics`·`Tooltip` 의 라벨. 눈에 보이지 않지만 스크린리더가 읽는다.
Iterable<String> _semanticLabels(WidgetTester tester) => <String>[
  ...tester
      .widgetList<Semantics>(find.byType(Semantics))
      .map((Semantics s) => s.properties.label ?? ''),
  ...tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .map((Tooltip t) => t.message ?? ''),
].where((String s) => s.trim().isNotEmpty);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required String lang,
    List<Override> overrides = const <Override>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_mockConfig),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoHangul(WidgetTester tester, String surface) {
    final leftovers = <String>[
      ..._renderedText(tester),
      ..._semanticLabels(tester),
    ].where(_hangul.hasMatch).toList();
    expect(
      leftovers,
      isEmpty,
      reason: '영어 로케일인데 $surface 에 한국어가 남았어요: $leftovers',
    );
  }

  // ── 일정 계열 — 이번에 문구 계층을 손댄 자리 ─────────────────────────────

  testWidgets('일정 추가 대화상자에 한글이 남지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAddEventDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      lang: 'en',
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expectNoHangul(tester, '일정 추가 대화상자');
  });

  testWidgets('그 날의 일정 시트에 한글이 남지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              // 일정이 없는 날 — 남는 것은 앱이 쓴 문구뿐이다.
              onPressed: () => showDayEventsSheet(
                context,
                date: DateTime(2026, 8, 12),
                events: const <ScheduleEvent>[],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      lang: 'en',
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expectNoHangul(tester, '그 날의 일정 시트');
  });

  testWidgets('일정 관리 시트에 한글이 남지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showScheduleCalendarSheet(
                context,
                initialDate: DateTime(2026, 8, 12),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      lang: 'en',
      overrides: <Override>[
        // 카테고리 범례와 요일 머리만 남기고 데모 일정은 비운다.
        scheduleMonthProvider.overrideWith(
          (Ref ref, String month) async => const <ScheduleEvent>[],
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expectNoHangul(tester, '일정 관리 시트');
  });

  // ── MY · 알림 · 코칭 ────────────────────────────────────────────────────

  testWidgets('건강 목표 시트에 한글이 남지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      const HealthGoalsPage(),
      lang: 'en',
      overrides: <Override>[profileProvider.overrideWith(_EmptyProfile.new)],
    );

    expectNoHangul(tester, '건강 목표 시트');
  });

  testWidgets('알림함 빈 상태에 한글이 남지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      const NotificationPage(),
      lang: 'en',
      overrides: <Override>[
        notificationControllerProvider.overrideWith(
          (Ref ref) => NotificationController(
            _EmptyNotificationRepository(),
            seed: const <AlertItem>[],
          ),
        ),
      ],
    );

    expectNoHangul(tester, '알림함');
  });

  testWidgets('AI 코칭 카드에 한글이 남지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      const Scaffold(body: SingleChildScrollView(child: AiCoachingCard())),
      lang: 'en',
      overrides: <Override>[
        // 담당 트레이너·루틴은 서버가 주는 데이터다. 비워 두면 카드에는 앱이 쓴
        // 제목과 안내만 남는다.
        memberCoachProvider.overrideWith((Ref ref) async => null),
        coachRoutinesProvider.overrideWith(
          (Ref ref) async => const <CoachRoutine>[],
        ),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
    );

    expectNoHangul(tester, 'AI 코칭 카드');
  });

  // ── 반대 방향 ───────────────────────────────────────────────────────────

  testWidgets('한국어 로케일은 그대로 한국어로 그려진다', (WidgetTester tester) async {
    // 영어만 보다가 한국어 키를 비워 두는 실수를 잡는다.
    await pump(
      tester,
      const HealthGoalsPage(),
      lang: 'ko',
      overrides: <Override>[profileProvider.overrideWith(_EmptyProfile.new)],
    );

    expect(_renderedText(tester).any(_hangul.hasMatch), isTrue);
  });
}

/// 값이 비어 있는 프로필 — 목표 시트가 입력 라벨만 그리게 한다.
class _EmptyProfile extends ProfileController {
  @override
  Future<UserProfile> build() async =>
      const UserProfile(id: 'test-user', name: '', email: '');
}

class _EmptyNotificationRepository implements NotificationRepository {
  @override
  Future<List<AlertItem>> fetchPage({
    int limit = notificationPageSize,
    String? before,
    String? beforeId,
  }) async => const <AlertItem>[];

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<int> unreadCount() async => 0;
}
