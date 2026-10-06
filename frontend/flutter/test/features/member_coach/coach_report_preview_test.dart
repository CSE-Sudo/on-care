/// 리포트 등록 안내와 그 미리보기 문서 (#1600, #2652).
///
/// 트레이너 앱의 짝은
/// `frontend/flutter_trainer/test/features/clients/client_detail_chat_test.dart`
/// 의 `리포트 전송 메시지는 …` 테스트다 — 같은 사건을 두 앱이 같은 정보 구조로
/// 그린다. 한쪽 문구만 고치면 여기서 깨진다.
///
/// 미리보기 문서는 트레이너 웹과 같은 결과지 한 장이다(#2652). 결과지 자체의
/// 규칙은 `shared/oncare_report` 의 테스트가 지키고, 여기서는 회원 앱이 그 한 장에
/// 무엇을 싣는지(트레이너 글·감지 기록·언어·테마)를 본다.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_card.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_report/oncare_report.dart';
import 'package:oncare_ui/oncare_ui.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

final DateTime _weekStart = DateTime(2026, 8, 17);

ReportSheetInputs _inputs({String name = '김민수', int? completion = 82}) =>
    ReportSheetInputs(
      week: ReportSheetWeekData(
        memberName: name,
        weekStart: _weekStart,
        sessionsBooked: 2,
        sessionsDone: 1,
        completionAvg: completion,
        sodiumAvg: 2100,
        isCurrentWeek: false,
        caloriesWeek: const <int>[1800, 1850, 1900, 1950, 2000, 2050, 0],
        sugarWeek: const <double>[24.5, 24.5, 24.5, 24.5, 24.5, 24.5, 0],
        sodiumWeek: const <int>[2100, 2100, 2100, 2100, 2100, 2100, 0],
        weekCompletion: const <int>[80, 0, 90, 0, 75, 0, 0],
      ),
    );

/// 굽기를 흉내 낸다 — 작은 흰 그림 한 장.
Future<CapturedWidget> _fakeCapture(
  Widget child, {
  required double width,
  required double pixelRatio,
}) async => CapturedWidget(
  rgba: Uint8List.fromList(List<int>.filled(4 * 4, 255)),
  width: 2,
  height: 2,
);

Future<CapturedWidget> _brokenCapture(
  Widget child, {
  required double width,
  required double pixelRatio,
}) async => throw StateError('renderer unavailable');

Future<void> _noYield() async {}

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
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      messages;

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
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      messages;

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(messages);
}

/// 같은 시각이면 id가 작은 리포트 안내가 먼저 서야 하는 스레드.
class _SameTimeReportRepository extends MockMemberCoachRepository {
  _SameTimeReportRepository();

  static final DateTime createdAt = DateTime(2026, 8, 24, 18, 10);
  static final List<CoachMessage> messages = <CoachMessage>[
    CoachMessage(
      id: 'b-message',
      sender: CoachSender.me,
      body: '동시 메시지',
      timeLabel: '18:10',
      createdAt: createdAt,
    ),
    CoachMessage(
      id: 'a-report',
      sender: CoachSender.trainer,
      body: '이번 주 리포트입니다.',
      timeLabel: '18:10',
      createdAt: createdAt,
      reportWeekStart: _weekStart,
    ),
  ];

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async =>
      messages;

  @override
  Stream<List<CoachMessage>> watchChat() =>
      Stream<List<CoachMessage>>.value(messages);
}

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
      expect(find.text('주간 리포트를 받았어요'), findsOneWidget);
      expect(find.text('8월 17일 ~ 8월 23일'), findsOneWidget);
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

    testWidgets('뒤에 대화가 이어지면 안내는 발생 시각 위치에 남는다 (#2127)', (
      WidgetTester tester,
    ) async {
      await pumpChat(tester, repository: _ReportThenChatRepository());

      final Rect card = tester.getRect(find.byType(CoachReportCard));
      final Rect lastBubble = tester.getRect(find.text('확인했습니다'));
      expect(
        card.bottom,
        lessThan(lastBubble.top),
        reason: '리포트 뒤에 온 메시지는 안내 카드 아래에 있어야 한다',
      );
    });

    testWidgets('발생 시각이 같으면 id 순으로 안내와 메시지를 정렬한다 (#2127)', (
      WidgetTester tester,
    ) async {
      await pumpChat(tester, repository: _SameTimeReportRepository());

      final Rect card = tester.getRect(find.byType(CoachReportCard));
      final Rect bubble = tester.getRect(find.text('동시 메시지'));
      expect(card.bottom, lessThan(bubble.top));
    });
  });

  group('리포트 미리보기 문서 (#2652)', () {
    testWidgets('트레이너가 함께 보낸 글이 트레이너 피드백 칸에 실린다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(),
        feedback: trainerReportFeedback('  이번 주 수고하셨어요.  '),
      );

      expect(lines, contains('트레이너 피드백'));
      expect(lines, contains('이번 주 수고하셨어요.'));
      expect(lines, isNot(contains('피드백 없음')));
    });

    testWidgets('함께 온 글이 없으면 트레이너 웹과 같이 피드백 없음이라고 적는다', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(),
        feedback: trainerReportFeedback('   '),
      );
      expect(lines, contains('피드백 없음'));
    });

    testWidgets('문서 제목과 항목 이름은 트레이너 웹 결과지와 같다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(),
        feedback: trainerReportFeedback('글'),
      );
      expect(lines.first, '주간 리포트');
      expect(lines, contains('· 회원: 김민수'));
      expect(lines, contains('· 운동 완료율: 82%'));
      expect(lines, contains('· 완료 PT: 1/2회 (50%)'));
      expect(lines, contains('· 나트륨: 2,100mg'));
    });

    testWidgets('기록이 없는 값은 0 이 아니라 미집계다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(completion: null),
        feedback: trainerReportFeedback(''),
      );
      expect(lines, contains('· 운동 완료율: 미집계'));
    });

    testWidgets('이름을 모르면 회원 줄을 비워 두지 않고 뺀다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(name: ''),
        feedback: trainerReportFeedback(''),
      );
      expect(lines.where((String s) => s.startsWith('· 회원')), isEmpty);
    });

    testWidgets('영어 화면이면 영어 결과지다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester, lang: 'en');
      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(),
        feedback: trainerReportFeedback(''),
      );
      expect(lines.first, 'Weekly report');
      expect(lines, contains('Trainer feedback'));
      expect(lines, contains('No feedback'));
    });

    testWidgets('포인트로 받은 리포트는 트레이너 칸에 감지 기록을 싣는다 (#2022)', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l = await localizations(tester);
      final MemberReportFeedback feedback = pointsReportFeedback(l, <String>[
        '무릎 통증 감지 2회',
      ]);
      expect(feedback.title, l.coachReportPdfSectionInsights);
      expect(feedback.text, contains('무릎 통증 감지 2회'));
      expect(feedback.text, contains(l.coachReportPdfSelfMadeNote));

      final List<String> lines = const MemberReportPdfGenerator().textContent(
        l: l,
        inputs: _inputs(),
        feedback: feedback,
      );
      expect(lines, contains(l.coachReportPdfSectionInsights));
      expect(lines, isNot(contains('트레이너 피드백')));
    });

    testWidgets('감지가 없던 주는 없다고, 못 읽은 주는 이유만 적는다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      final MemberReportFeedback none = pointsReportFeedback(
        l,
        const <String>[],
      );
      expect(none.text, contains(l.coachReportPdfNoInsights));

      final MemberReportFeedback unread = pointsReportFeedback(l, null);
      expect(unread.text, isNot(contains(l.coachReportPdfNoInsights)));
      expect(unread.text, l.coachReportPdfSelfMadeNote);
    });

    testWidgets('트레이너 글은 제목을 바꾸지 않는다', (WidgetTester tester) async {
      expect(trainerReportFeedback('글').title, isNull);
    });

    testWidgets('결과지는 트레이너 웹 테마로 굽는다 — 회원 앱 파랑이 아니다', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l = await localizations(tester);
      late OnCareTokens tokens;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MemberReportPdfGenerator.frame(
            l,
            Builder(
              builder: (BuildContext context) {
                tokens = context.oncare;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(tokens.brand.primary, OnCareBrand.trainer.primary);
      expect(tokens.brand.primary, isNot(OnCareBrand.member.primary));
    });

    testWidgets('결과지 한 장이 앱 밖에서도 그려진다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      tester.view.physicalSize = const Size(
        ReportSheetDocument.width,
        ReportSheetDocument.height,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MemberReportPdfGenerator.frame(
            l,
            MemberReportPdfGenerator.sheet(
              inputs: _inputs(),
              feedback: trainerReportFeedback('이번 주 수고하셨어요.'),
              today: DateTime(2026, 8, 30),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ReportSheetDocument), findsOneWidget);
      expect(find.text('이번 주 수고하셨어요.'), findsOneWidget);
      expect(find.text('김민수'), findsWidgets);
    });

    testWidgets('포인트 리포트는 결과지 아래 칸 제목이 참고 기록이다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      tester.view.physicalSize = const Size(
        ReportSheetDocument.width,
        ReportSheetDocument.height,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MemberReportPdfGenerator.frame(
            l,
            MemberReportPdfGenerator.sheet(
              inputs: _inputs(),
              feedback: pointsReportFeedback(l, const <String>[]),
              today: DateTime(2026, 8, 30),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l.coachReportPdfSectionInsights), findsOneWidget);
      expect(find.text('트레이너 피드백'), findsNothing);
    });

    testWidgets('구운 결과지를 PDF 한 부로 낸다', (WidgetTester tester) async {
      final AppLocalizations l = await localizations(tester);
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes =
            await const MemberReportPdfGenerator(
              capture: _fakeCapture,
              yieldFrame: _noYield,
            ).generate(
              l: l,
              inputs: _inputs(),
              feedback: trainerReportFeedback('글'),
            );
      });
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    testWidgets('굽지 못하면 글자 문서로 물러선다 — 리포트가 안 열리지는 않는다', (
      WidgetTester tester,
    ) async {
      final AppLocalizations l = await localizations(tester);
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes =
            await const MemberReportPdfGenerator(
              capture: _brokenCapture,
              yieldFrame: _noYield,
            ).generate(
              l: l,
              inputs: _inputs(),
              feedback: trainerReportFeedback('글'),
            );
      });
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
