import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/dashboard/domain/entities/dashboard_summary.dart';
import 'package:oncare/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:oncare/features/dashboard/presentation/widgets/dashboard_content.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 홈 요약 — 일정 한 건만 있는 최소 형태.
const DashboardSummary _summary = DashboardSummary(
  indicators: <HealthIndicator>[
    HealthIndicator(label: '칼로리', current: 1860, max: 2000, unit: 'kcal'),
  ],
  macros: DietMacros(
    carbsG: 200,
    proteinG: 100,
    fatG: 60,
    carbsPct: 44,
    proteinPct: 24,
    fatPct: 32,
  ),
  dietEntries: 1,
  exerciseMinutes: 30,
  exerciseCalories: 300,
  exerciseCount: 1,
  todaySchedule: <ScheduleItem>[
    ScheduleItem(time: '18:00', title: '병원 정기검진', emoji: '🏥'),
  ],
  weekScore: 80,
  weekScoreDelta: 5,
  sodiumWarning: '',
  exerciseFeedback: '',
);

CoachSession _session({
  String time = '10:00',
  String type = '1:1 PT',
  String status = '예정',
  DateTime? date,
}) => CoachSession(
  id: 'sched-$time',
  date: date ?? nowKst(),
  time: time,
  type: type,
  durationMinutes: 50,
  status: status,
);

Future<void> _pump(WidgetTester tester, {List<CoachSession>? sessions}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(
            profile: const UserProfile(
              id: 'member',
              name: '테스트',
              email: 'member@example.com',
            ),
          ),
        ),
        dashboardSummaryProvider.overrideWith((ref) async => _summary),
        memberCoachRepositoryProvider.overrideWithValue(
          MockMemberCoachRepository(),
        ),
        if (sessions != null)
          coachSessionsProvider.overrideWith((ref) async => sessions),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: DashboardContent()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // 홈 하단 오늘의 일정 카드는 지금 화면에 걸지 않았다 (#1055). 트레이너 세션을
  // 내 일정과 섞는 규칙은 그 카드 안에 있어, 카드가 돌아올 때 이 검사도 함께
  // 돌아온다 — 지우면 규칙이 무엇이었는지가 사라진다.
  group('오늘의 일정 카드 (지금은 화면에서 내려 둠)', skip: '#1055 에서 주석 처리', () {
    testWidgets('트레이너가 잡은 오늘 PT 가 홈 일정에 나타난다', (WidgetTester tester) async {
      await _pump(tester, sessions: <CoachSession>[_session()]);

      expect(find.text('1:1 PT'), findsOneWidget);
      // 내가 만든 일정도 그대로 남는다.
      expect(find.text('병원 정기검진'), findsOneWidget);
    });

    testWidgets('시간순으로 섞인다', (WidgetTester tester) async {
      // '다음에 뭐가 있는지'를 한 번에 읽으려면 두 출처가 시간순이어야 한다.
      await _pump(tester, sessions: <CoachSession>[_session()]);

      final double ptY = tester.getTopLeft(find.text('1:1 PT')).dy;
      final double checkupY = tester.getTopLeft(find.text('병원 정기검진')).dy;
      expect(ptY, lessThan(checkupY));
    });

    testWidgets('완료된 세션은 오늘의 일정에 남지 않는다', (WidgetTester tester) async {
      await _pump(tester, sessions: <CoachSession>[_session(status: '완료')]);

      expect(find.text('1:1 PT'), findsNothing);
    });

    testWidgets('다른 날 세션은 오늘에 끼어들지 않는다', (WidgetTester tester) async {
      await _pump(
        tester,
        sessions: <CoachSession>[
          _session(date: nowKst().add(const Duration(days: 3))),
        ],
      );

      expect(find.text('1:1 PT'), findsNothing);
    });

    testWidgets('날짜가 없는 세션은 걸러진다', (WidgetTester tester) async {
      // 서버가 깨진 날짜를 줘도 화면이 흔들리지 않아야 한다.
      await _pump(
        tester,
        sessions: <CoachSession>[
          const CoachSession(
            id: 'broken',
            date: null,
            time: '09:00',
            type: '1:1 PT',
            durationMinutes: 50,
            status: '예정',
          ),
        ],
      );

      expect(find.text('1:1 PT'), findsNothing);
    });

    testWidgets('데모 홈 일정은 지금과 같다', (WidgetTester tester) async {
      // override 없이 — 데모는 목 저장소가 빈 목록을 주므로 카드가 그대로다.
      await _pump(tester);

      expect(find.text('병원 정기검진'), findsOneWidget);
      expect(find.text('1:1 PT'), findsNothing);
    });
  });
}
