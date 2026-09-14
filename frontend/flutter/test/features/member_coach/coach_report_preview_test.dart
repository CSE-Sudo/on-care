/// 리포트 등록 안내와 그 미리보기 문서 (#1600).
///
/// 트레이너 앱의 짝은
/// `frontend/flutter_trainer/test/features/clients/client_detail_chat_test.dart`
/// 의 `리포트 전송 메시지는 …` 테스트다 — 같은 사건을 두 앱이 같은 정보 구조로
/// 그린다. 한쪽 문구만 고치면 여기서 깨진다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/member_weekly_report.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_card.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

final DateTime _weekStart = DateTime(2026, 8, 17);

/// 리포트 안내 한 줄만 들어 있는 스레드.
class _ReportThreadRepository extends MockMemberCoachRepository {
  _ReportThreadRepository();

  static final List<CoachMessage> messages = <CoachMessage>[
    CoachMessage(
      id: 'report-1',
      sender: CoachSender.trainer,
      body: '이번 주 리포트입니다.',
      timeLabel: '18:10',
      createdAt: DateTime(2026, 8, 24, 18, 10),
      reportWeekStart: _weekStart,
    ),
  ];

  @override
  Future<List<CoachMessage>> fetchChat() async => messages;

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(messages);
}

/// 리포트 안내가 온 **뒤에도** 대화가 이어진 스레드.
class _ReportThenChatRepository extends MockMemberCoachRepository {
  _ReportThenChatRepository();

  static final List<CoachMessage> messages = <CoachMessage>[
    CoachMessage(
      id: 'report-1',
      sender: CoachSender.trainer,
      body: '이번 주 리포트입니다.',
      timeLabel: '18:10',
      createdAt: DateTime(2026, 8, 24, 18, 10),
      reportWeekStart: _weekStart,
    ),
    CoachMessage(
      id: 'after-1',
      sender: CoachSender.me,
      body: '확인했습니다',
      timeLabel: '18:20',
      createdAt: DateTime(2026, 8, 24, 18, 20),
    ),
  ];

  @override
  Future<List<CoachMessage>> fetchChat() async => messages;

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(messages);
}

MemberWeeklyReport _report({
  List<ExerciseSession> sessions = const <ExerciseSession>[],
  List<double> minutes = const <double>[30, 0, 45, 0, 20, 0, 0],
  List<DietPeriodDay> days = const <DietPeriodDay>[],
  int booked = 2,
  int done = 1,
  int? sodiumTarget,
  MemberWeeklyReport? previous,
  DateTime? asOf,
}) => MemberWeeklyReport(
  weekStart: _weekStart,
  exercise: ExerciseWeek(
    sessions: sessions,
    dailyMinutes: minutes,
    dayLabels: const <String>['월', '화', '수', '목', '금', '토', '일'],
    totalMinutes: 95,
    totalCalories: 620,
    streakDays: 1,
    aiCoachMessage: '',
  ),
  diet: DietPeriod(days: days),
  sessionsBooked: booked,
  sessionsDone: done,
  sodiumTarget: sodiumTarget,
  previous: previous,
  asOf: asOf,
);

List<DietPeriodDay> _week() => <DietPeriodDay>[
  for (int i = 0; i < 7; i++)
    DietPeriodDay(
      date: DateTime(2026, 8, 17 + i),
      calories: i == 6 ? 0 : 1800 + (i * 50),
      sodiumMg: i == 6 ? 0 : 2100,
      sugarG: i == 6 ? 0 : 24.5,
    ),
];

void main() {
  Future<AppLocalizations> localizations(
    WidgetTester tester, {
    String lang = 'ko',
  }) async {
    late AppLocalizations l;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            l = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return l;
  }

  Future<void> pumpChat(
    WidgetTester tester, {
    MockMemberCoachRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          memberCoachRepositoryProvider.overrideWithValue(
            repository ?? _ReportThreadRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TrainerChatPage(trainerName: '김트레이너'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('리포트 등록 안내 (#1600)', () {
    testWidgets('말풍선이 아니라 대화 가운데 상자로 뜬다', (WidgetTester tester) async {
      await pumpChat(tester);

      expect(find.byType(CoachReportCard), findsOneWidget);
      expect(find.text('리포트가 등록되었어요'), findsOneWidget);
      expect(find.text('8월 17일 – 8월 23일'), findsOneWidget);
      expect(find.text('PDF 미리보기'), findsOneWidget);
      // 본문 그대로의 말풍선은 그리지 않는다 — 같은 사건이 두 번 보인다.
      expect(find.text('이번 주 리포트입니다.'), findsNothing);

      final Rect box = tester.getRect(find.byType(CoachReportCard));
      final Rect screen = tester.getRect(find.byType(MaterialApp));
      expect(
        (box.center.dx - screen.center.dx).abs(),
        lessThan(1.0),
        reason: '안내는 트레이너 말풍선처럼 한쪽에 붙지 않는다',
      );
    });

    testWidgets('뒤에 대화가 이어져도 안내는 맨 아래에 남는다', (WidgetTester tester) async {
      await pumpChat(tester, repository: _ReportThenChatRepository());

      final Rect card = tester.getRect(find.byType(CoachReportCard));
      final Rect lastBubble = tester.getRect(find.text('확인했습니다'));
      expect(
        card.top,
        greaterThan(lastBubble.bottom),
        reason: '리포트를 여는 자리는 대화가 늘어도 같은 곳이어야 한다',
      );
    });
  });

  group('리포트 미리보기 문서 (#1600)', () {
    testWidgets('트레이너 리포트와 같은 지표를 회원 기록으로 적는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(
          days: _week(),
          sessions: <ExerciseSession>[
            ExerciseSession(
              dayLabel: '월',
              type: ExerciseType.cardio,
              minutes: 30,
              calories: 210,
              name: '걷기',
              date: DateTime(2026, 8, 17),
            ),
          ],
        ),
      );

      expect(lines.first, '기간 2026-08-17 ~ 2026-08-23');
      // 지표는 절 제목 아래 글줄이 아니라 머리띠와 상자로 선다(#1619).
      expect(lines, contains('· 운동한 날: 3일'));
      expect(lines, contains('· 총 운동 시간: 95분'));
      expect(lines, contains('· 소모 칼로리: 620kcal'));
      expect(lines, contains('· PT 세션: 2회 중 1회'));
      // 평균은 **기록이 있는 날만으로** 나눈다 — 안 먹은 날의 0 이 평균을
      // 끌어내리면 실제로 먹은 양과 다른 숫자가 된다.
      expect(lines, contains('· 평균 섭취 칼로리: 1925kcal'));
      expect(lines, contains('· 평균 나트륨: 2100mg'));
      expect(lines, contains('· 평균 당류: 24.5g'));
      expect(lines, contains('· 운동 시간: 30분 / - / 45분 / - / 20분 / - / -'));
      expect(lines, contains('월요일 — 운동 걷기, 섭취 1800kcal'));
      // 기록이 없는 날은 0 을 적지 않는다.
      expect(lines, contains('일요일 — 운동 기록 없음, 섭취 기록 없음'));
      expect(lines.last, contains('회원님 기록으로 정리한 미리보기'));
    });

    testWidgets('운동 이름이 items 에만 있어도 요일별 상세에 적힌다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(
          days: _week(),
          sessions: <ExerciseSession>[
            // 데모 경로가 주는 모양 — 이름은 `items` 에 하나씩, `name` 은 비어
            // 있고 날짜도 없다. 예전에는 `name` 만 읽어 전부 걸러졌다.
            const ExerciseSession(
              dayLabel: '월',
              type: ExerciseType.cardio,
              minutes: 30,
              calories: 210,
              items: <String>['저강도 유산소 (걷기) 30분', '코어 강화 10분'],
            ),
          ],
        ),
      );

      expect(
        lines,
        contains('월요일 — 운동 저강도 유산소 (걷기) 30분, 코어 강화 10분, 섭취 1800kcal'),
      );
    });

    testWidgets('아직 오지 않은 요일은 기록 없음이라고 적지 않는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        // 그 주의 수요일에 세운 문서 — 목·금·토·일은 아직 오지 않았다.
        report: _report(days: _week(), asOf: DateTime(2026, 8, 19)),
      );

      expect(lines, contains('목요일 — 아직 지나지 않았어요'));
      expect(lines, contains('일요일 — 아직 지나지 않았어요'));
      expect(lines, isNot(contains('일요일 — 운동 기록 없음, 섭취 기록 없음')));
      // 지나간 날은 그대로 센다.
      expect(lines, contains(contains('화요일 — ')));
    });

    testWidgets('트레이너가 함께 보낸 글을 문서 안에서 읽는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week()),
        trainerNote: '이번 주는 나트륨을 조금만 줄여 봐요.',
      );

      expect(lines, contains('트레이너 메시지'));
      expect(lines, contains('이번 주는 나트륨을 조금만 줄여 봐요.'));
    });

    testWidgets('함께 온 글이 없으면 그 사실을 적는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week()),
      );

      expect(lines, contains('함께 온 메시지가 없어요.'));
    });

    testWidgets('잡힌 일정을 못 받아도 진행한 PT 는 기록에서 센다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week(), booked: 0, done: 2),
      );

      // 예전에는 잡힌 일정이 없으면 `PT 세션: 기록 없음` 이었다 — 그 주에 PT 를
      // 두 번 했는데도 아무 일 없던 주로 읽혔다.
      expect(lines, contains('· 진행한 PT: 2회'));
      expect(lines, isNot(contains('· PT 세션: 기록 없음')));
    });

    testWidgets('잡힌 일정도 진행한 PT 도 없으면 일정이 없다고 적는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week(), booked: 0, done: 0),
      );

      expect(lines, contains('· PT 세션: 잡힌 일정 없음'));
    });

    testWidgets('나트륨 초과 일수는 회원 자신의 목표로 세고 기준을 밝힌다', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week(), sodiumTarget: 2000),
      );

      // `_week()` 는 기록한 여섯 날 모두 2100mg 이다.
      expect(lines, contains('· 나트륨 목표 초과: 6일'));
      expect(lines, contains(contains('하루 2000mg 기준')));
    });

    testWidgets('요일별 값은 그래프로 그려도 같은 값을 말한다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week(), asOf: DateTime(2026, 8, 23)),
      );

      // 그래프 블록도 자기 값을 글로 든다 — 그림만 남으면 문서가 무엇을 말하는지
      // 확인할 길이 없다.
      expect(lines, contains('· 운동 시간: 30분 / - / 45분 / - / 20분 / - / -'));
      expect(lines, contains(startsWith('· 섭취 칼로리: ')));
      expect(lines, contains(startsWith('· 나트륨: ')));
    });

    testWidgets('값이 없거나 목표가 있어도 문서가 만들어진다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      const MemberReportPdfGenerator generator = MemberReportPdfGenerator();

      // 막대 높이를 나누는 자리가 0 이 되는 주 — 눈금이 무너지면 여기서 터진다.
      Uint8List? empty;
      Uint8List? withTarget;
      await tester.runAsync(() async {
        empty = await generator.generate(
          l: l,
          report: _report(minutes: const <double>[0, 0, 0, 0, 0, 0, 0]),
        );
        withTarget = await generator.generate(
          l: l,
          report: _report(days: _week(), sodiumTarget: 2000),
        );
      });

      expect(empty, isNotNull);
      expect(empty!.length, greaterThan(0));
      expect(withTarget, isNotNull);
      expect(withTarget!.length, greaterThan(0));
    });

    testWidgets('지난주가 있으면 견주고, 없으면 없다고 적는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> withLast = const MemberReportPdfGenerator()
          .textContent(
            l: l,
            report: _report(
              days: _week(),
              previous: _report(
                days: _week(),
                minutes: const <double>[20, 0, 0, 0, 0, 0, 0],
              ),
            ),
          );

      // 같은 지표의 이번 주·지난주·변화가 한 줄에 선다(#1619) — 예전에는
      // `지난주 대비` 라는 절이 따로 있었다.
      expect(withLast, contains('· 총 운동 시간: 95분 (지난주 95분, 변화 없음)'));
      expect(withLast, isNot(contains('지난주 기록이 없어 견줄 값이 없어요.')));

      final List<String> alone = const MemberReportPdfGenerator().textContent(
        l: l,
        report: _report(days: _week()),
      );
      expect(alone, contains('지난주 기록이 없어 견줄 값이 없어요.'));
    });
  });
}
