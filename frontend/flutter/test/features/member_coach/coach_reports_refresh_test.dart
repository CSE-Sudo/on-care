/// 받은 리포트 목록 — 새 리포트가 오면 다시 읽는다. (#2643)
///
/// 예전에는 한 번 읽은 목록이 세션 내내 남아 새 리포트가 앱을 다시 켜기 전까지
/// 보이지 않았다. 읽기 실패에는 `보내지 못했어요`·`PDF 를 열지 못했어요` 가 떴다.
/// 목록이 대화가 아니라 서버의 받은 리포트 목록에서 오는 것은 #3348 —
/// `received_reports_test.dart` 가 본다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/pages/coach_reports_page.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 2026-06-01 (월).
final DateTime _week1 = DateTime(2026, 6);
final DateTime _week2 = DateTime(2026, 7, 6);

Future<List<ReceivedReport>> _notices(ProviderContainer container) async {
  container.listen(receivedReportsProvider, (_, _) {});
  return (await container.read(receivedReportsProvider.future)).reports;
}

ProviderContainer _container(MemberCoachRepository repository) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 받은 리포트 목록을 읽지 못하는 대역.
class _ReportsFailRepository extends FakeMemberCoachRepository {
  @override
  Future<ReceivedReportsPage> fetchReceivedReports({DateTime? before}) =>
      Future<ReceivedReportsPage>.error(StateError('reports unavailable'));
}

/// 피드백을 읽지 못하는 대역.
class _FeedbackFailsRepository extends FakeMemberCoachRepository {
  @override
  Future<MemberWeeklyFeedback> fetchWeeklyFeedback({DateTime? weekStart}) =>
      Future<MemberWeeklyFeedback>.error(StateError('feedback unavailable'));
}

/// 폴링을 손으로 흘려보내는 대역.
class _LiveRepository extends FakeMemberCoachRepository {
  _LiveRepository({super.chat});

  final StreamController<List<CoachMessage>> _polls =
      StreamController<List<CoachMessage>>.broadcast();

  @override
  Stream<List<CoachMessage>> watchChat() async* {
    yield pageCoachChat(chat);
    yield* _polls.stream;
  }

  void arrive(List<CoachMessage> messages) {
    chat.addAll(messages);
    _polls.add(pageCoachChat(chat));
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  ProviderContainer container, {
  Widget home = const CoachReportsPage(),
  String locale = 'ko',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(DateTime week) => find.byKey(
  ValueKey<String>(
    'coach-report-${week.year}-'
    '${week.month.toString().padLeft(2, '0')}-'
    '${week.day.toString().padLeft(2, '0')}',
  ),
);

void main() {
  setUp(() => useFixedKstDate());

  group('새 리포트 알아채기', () {
    test('새 리포트 안내가 왔는지 가린다', () {
      final List<CoachMessage> before = <CoachMessage>[
        plainMessage(),
        reportNotice(_week1, id: 'r1'),
      ];

      expect(hasNewReportNotice(before, before), isFalse);
      expect(
        hasNewReportNotice(before, <CoachMessage>[
          ...before,
          plainMessage(id: 'p2'),
        ]),
        isFalse,
        reason: '보통 메시지는 리포트가 아니다',
      );
      expect(
        hasNewReportNotice(before, <CoachMessage>[
          ...before,
          reportNotice(_week2, id: 'r2'),
        ]),
        isTrue,
      );
    });
  });

  group('새로 읽기', () {
    testWidgets('화면에 다시 들어오면 목록을 새로 읽는다', (tester) async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[reportNotice(_week1, id: 'r1')],
      );
      final ProviderContainer container = _container(repository);
      await _pumpPage(tester, container);
      expect(_row(_week1), findsOneWidget);
      expect(_row(_week2), findsNothing);

      // 화면을 떠난 사이 새 리포트가 왔다.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // 같은 테마를 둔다 — 테마 없는 앱에서 돌아오면 테마 전환 애니메이션
          // 중간 프레임에 앱 토큰이 없어 화면이 그려지지 않는다.
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repository.chat.add(reportNotice(_week2, id: 'r2'));

      await _pumpPage(tester, container);

      expect(_row(_week1), findsOneWidget);
      expect(_row(_week2), findsOneWidget);
    });

    testWidgets('채팅이 새 리포트 안내를 받으면 목록을 다시 읽는다', (tester) async {
      final _LiveRepository repository = _LiveRepository(
        chat: <CoachMessage>[reportNotice(_week1, id: 'r1')],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost',
              useMockApi: false,
            ),
          ),
          memberCoachRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      // 목록을 듣고 있는 누군가 — 없으면 autoDispose 로 이미 사라진다.
      final List<ReceivedReport> first = await _notices(container);
      expect(first, hasLength(1));
      await _pumpPage(
        tester,
        container,
        home: const TrainerChatPage(trainerName: '김트레이너'),
      );

      repository.arrive(<CoachMessage>[
        reportNotice(_week2, id: 'r2', createdAt: DateTime(2026, 8, 19, 21)),
      ]);
      await tester.pumpAndSettle();

      final ReceivedReportsState next = await container.read(
        receivedReportsProvider.future,
      );
      expect(next.reports.map((ReceivedReport n) => n.id).toSet(), <String>{
        'r1',
        'r2',
      });
    });
  });

  group('오류 문구', () {
    testWidgets('목록을 읽지 못하면 불러오지 못했다고 말한다', (tester) async {
      await _pumpPage(tester, _container(_ReportsFailRepository()));

      expect(find.text('받은 리포트를 불러오지 못했어요'), findsOneWidget);
      // 예전 문구 — 문서를 열다 실패한 것이 아니다.
      expect(find.text('PDF를 열지 못했어요. 다시 시도해 주세요'), findsNothing);
    });

    testWidgets('피드백을 읽지 못하면 불러오지 못했다고 말한다', (tester) async {
      await _pumpPage(tester, _container(_FeedbackFailsRepository()));

      expect(find.text('보낸 주간 피드백을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('주간 피드백을 보내지 못했어요. 다시 시도해 주세요'), findsNothing);
    });

    testWidgets('영어에서도 읽기 실패 문구가 번역되어 있다', (tester) async {
      await _pumpPage(
        tester,
        _container(_ReportsFailRepository()),
        locale: 'en',
      );

      expect(find.text("Couldn't load your reports"), findsOneWidget);
    });

    testWidgets('영어에서 피드백 읽기 실패 문구가 번역되어 있다', (tester) async {
      await _pumpPage(
        tester,
        _container(_FeedbackFailsRepository()),
        locale: 'en',
      );

      expect(
        find.text("Couldn't load the weekly feedback you sent"),
        findsOneWidget,
      );
    });

    testWidgets('다시 시도하면 목록을 다시 읽는다', (tester) async {
      final _FlakyReportsRepository repository = _FlakyReportsRepository(
        chat: <CoachMessage>[reportNotice(_week1, id: 'r1')],
      );
      await _pumpPage(tester, _container(repository));
      expect(find.text('받은 리포트를 불러오지 못했어요'), findsOneWidget);

      repository.failing = false;
      final AppLocalizations l = lookupAppLocalizations(const Locale('ko'));
      await tester.tap(find.text(l.actionRetry).last);
      await tester.pumpAndSettle();

      expect(_row(_week1), findsOneWidget);
    });
  });
}

/// 처음에는 목록을 읽지 못하다가 풀리는 대역.
class _FlakyReportsRepository extends FakeMemberCoachRepository {
  _FlakyReportsRepository({super.chat});

  bool failing = true;

  @override
  Future<ReceivedReportsPage> fetchReceivedReports({DateTime? before}) {
    if (failing) {
      return Future<ReceivedReportsPage>.error(
        StateError('reports unavailable'),
      );
    }
    return super.fetchReceivedReports(before: before);
  }
}
