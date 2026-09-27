/// MY 탭 → 트레이너 리포트 화면과, 그 목록을 만드는 규칙. (#2232)
///
/// 리포트에는 목록 엔드포인트가 없다. 트레이너가 보낼 때 대화에 남는 안내
/// 한 줄이 곧 보낸 기록이라, 이 화면의 정확함은 **대화에서 무엇을 골라
/// 남기는가**에 달려 있다. 여기서 보는 것이 그 규칙이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/pages/coach_reports_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 고정한 오늘(2026-08-20 목)에서 본 직전 주.
final DateTime _lastWeek = DateTime(2026, 8, 10);
final DateTime _twoWeeksAgo = DateTime(2026, 8, 3);
final DateTime _threeWeeksAgo = DateTime(2026, 7, 27);

MemberWeeklyFeedback _sent(DateTime week) => MemberWeeklyFeedback(
  weekStart: week,
  submitted: true,
  condition: WeekCondition.good,
  intensity: WeekIntensity.right,
  submittedAt: DateTime(2026, 8, 16, 20),
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeMemberCoachRepository repository, {
  String locale = 'ko',
  Size size = const Size(420, 1400),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CoachReportsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _row(DateTime week) => find.byKey(
  ValueKey<String>(
    'coach-report-${week.year}-'
    '${week.month.toString().padLeft(2, '0')}-'
    '${week.day.toString().padLeft(2, '0')}',
  ),
);

/// 화면에 보이는 모든 글월.
List<String> _texts(WidgetTester tester) => <String>[
  for (final Element e in find.byType(Text).evaluate())
    if ((e.widget as Text).data != null) (e.widget as Text).data!,
];

void main() {
  setUp(() => useFixedKstDate());

  group('목록 만들기', () {
    test('리포트 안내만 골라 낸다 — 보통 대화는 리포트가 아니다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          plainMessage(),
          reportNotice(_lastWeek, id: 'r1'),
          plainMessage(id: 'p2', body: '다음 주에 봬요'),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final List<SentReportNotice> notices = await container.read(
        sentReportNoticesProvider.future,
      );

      expect(notices, hasLength(1));
      expect(notices.single.message.id, 'r1');
      expect(notices.single.weekStart, _lastWeek);
    });

    test('최신 주가 맨 위에 선다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(_threeWeeksAgo, id: 'r3'),
          reportNotice(_lastWeek, id: 'r1'),
          reportNotice(_twoWeeksAgo, id: 'r2'),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final List<SentReportNotice> notices = await container.read(
        sentReportNoticesProvider.future,
      );

      expect(
        notices.map((SentReportNotice n) => n.weekStart).toList(),
        <DateTime>[_lastWeek, _twoWeeksAgo, _threeWeeksAgo],
      );
    });

    test('같은 주를 두 번 보냈으면 마지막 것만 남는다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(
            _lastWeek,
            id: 'old',
            createdAt: DateTime(2026, 8, 16, 10),
          ),
          reportNotice(
            _lastWeek,
            id: 'new',
            createdAt: DateTime(2026, 8, 16, 21),
          ),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final List<SentReportNotice> notices = await container.read(
        sentReportNoticesProvider.future,
      );

      // 회원이 받은 것은 마지막 글이다. 두 줄로 서면 어느 것을 열지 알 수 없다.
      expect(notices, hasLength(1));
      expect(notices.single.message.id, 'new');
    });

    test('대화 순서가 뒤바뀌어 와도 마지막 것을 고른다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          reportNotice(
            _lastWeek,
            id: 'new',
            createdAt: DateTime(2026, 8, 16, 21),
          ),
          reportNotice(
            _lastWeek,
            id: 'old',
            createdAt: DateTime(2026, 8, 16, 10),
          ),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final List<SentReportNotice> notices = await container.read(
        sentReportNoticesProvider.future,
      );

      expect(notices.single.message.id, 'new');
    });

    test('보낸 시각은 안내가 온 시각이다', () async {
      final CoachMessage notice = reportNotice(
        _lastWeek,
        createdAt: DateTime(2026, 8, 16, 21, 5),
      );

      expect(
        SentReportNotice(message: notice, weekStart: _lastWeek).sentAt,
        DateTime(2026, 8, 16, 21, 5),
      );
    });

    test('대화가 비어 있으면 목록도 비어 있다', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberCoachRepositoryProvider.overrideWithValue(
            FakeMemberCoachRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(sentReportNoticesProvider.future), isEmpty);
    });
  });

  group('화면', () {
    testWidgets('받은 리포트가 주마다 한 줄씩 선다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(
          chat: <CoachMessage>[
            reportNotice(_lastWeek, id: 'r1'),
            reportNotice(_twoWeeksAgo, id: 'r2'),
          ],
        ),
      );

      expect(_row(_lastWeek), findsOneWidget);
      expect(_row(_twoWeeksAgo), findsOneWidget);
    });

    testWidgets('줄마다 어느 주인지와 언제 받았는지를 적는다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(
          chat: <CoachMessage>[
            reportNotice(
              _lastWeek,
              createdAt: DateTime(2026, 8, 16, 21),
            ),
          ],
        ),
      );

      expect(
        _texts(tester).any((String t) => t.contains('8월 10일')),
        isTrue,
        reason: '어느 주의 리포트인지가 줄에 없다',
      );
      expect(find.text('8월 16일 보냄'), findsOneWidget);
    });

    testWidgets('받은 리포트가 없으면 빈 자리를 설명한다', (tester) async {
      await _pump(tester, FakeMemberCoachRepository());

      expect(
        find.byKey(const ValueKey<String>('coach-reports-empty')),
        findsOneWidget,
      );
      expect(find.text('아직 받은 리포트가 없어요'), findsOneWidget);
      expect(find.text('담당 트레이너가 주간 리포트를 보내면 여기에 쌓여요'), findsOneWidget);
    });

    testWidgets('보낸 주간 피드백이 같은 화면 위쪽에 선다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(
          feedback: <DateTime, MemberWeeklyFeedback>{_lastWeek: _sent(_lastWeek)},
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('my-weekly-feedback-card')),
        findsOneWidget,
      );
      expect(find.text('🙂 좋았어요'), findsOneWidget);
    });

    testWidgets('피드백 칸이 읽는 주는 직전 주 하나다', (tester) async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        feedback: <DateTime, MemberWeeklyFeedback>{
          _lastWeek: _sent(_lastWeek),
          _twoWeeksAgo: _sent(_twoWeeksAgo),
        },
      );
      final ProviderContainer container = await _pump(tester, repository);

      final MemberWeeklyFeedback shown = await container.read(
        lastWeekFeedbackProvider.future,
      );
      expect(shown.weekStart, _lastWeek);
    });

    testWidgets('아직 안 낸 주에는 지금 보내기가 선다', (tester) async {
      await _pump(tester, FakeMemberCoachRepository());

      expect(find.text('직전 주 피드백을 아직 보내지 않았어요'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('my-weekly-feedback-send-now')),
        findsOneWidget,
      );
    });

    testWidgets('지금 보내기를 누르면 그 자리에서 시트가 열린다', (tester) async {
      await _pump(tester, FakeMemberCoachRepository());

      await tester.tap(
        find.byKey(const ValueKey<String>('my-weekly-feedback-send-now')),
      );
      await tester.pumpAndSettle();

      // 일요일이 아니어도 회원이 스스로 낼 수 있어야 한다 — 물음을 놓친 주가
      // 영영 빈칸으로 남지 않게.
      expect(
        find.byKey(const ValueKey<String>('weeklyFeedbackSheet')),
        findsOneWidget,
      );
    });

    testWidgets('이미 낸 주는 그 답이 채워진 채로 열린다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(
          feedback: <DateTime, MemberWeeklyFeedback>{
            _lastWeek: _sent(_lastWeek),
          },
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('my-weekly-feedback-send-now')),
      );
      await tester.pumpAndSettle();

      expect(find.text('이미 보낸 주예요. 다시 보내면 마지막 답으로 바뀌어요.'), findsOneWidget);
    });

    testWidgets('두 칸이 함께 선다 — 리포트와 피드백은 한 쌍이다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(
          chat: <CoachMessage>[reportNotice(_lastWeek)],
          feedback: <DateTime, MemberWeeklyFeedback>{
            _lastWeek: _sent(_lastWeek),
          },
        ),
      );

      expect(find.text('받은 리포트'), findsOneWidget);
      expect(find.text('보낸 주간 피드백'), findsOneWidget);
      expect(find.text('트레이너 리포트'), findsOneWidget);
    });

    testWidgets('영어에서 모든 자리가 번역되어 있다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(chat: <CoachMessage>[reportNotice(_lastWeek)]),
        locale: 'en',
      );

      expect(find.text('Trainer reports'), findsOneWidget);
      expect(find.text('Reports received'), findsOneWidget);
      expect(find.text('Weekly feedback you sent'), findsOneWidget);
    });

    testWidgets('영어에서 빈 목록의 안내도 번역되어 있다', (tester) async {
      await _pump(tester, FakeMemberCoachRepository(), locale: 'en');

      expect(find.text('No reports yet'), findsOneWidget);
    });

    testWidgets('영어 화면에 한글이 남아 있지 않다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(chat: <CoachMessage>[reportNotice(_lastWeek)]),
        locale: 'en',
      );

      final RegExp hangul = RegExp(r'[가-힣]');
      for (final String t in _texts(tester)) {
        expect(
          hangul.hasMatch(t),
          isFalse,
          reason: '영어 화면에 번역되지 않은 글이 있다: $t',
        );
      }
    });

    testWidgets('좁은 폭에서도 넘치지 않는다', (tester) async {
      await _pump(
        tester,
        FakeMemberCoachRepository(chat: <CoachMessage>[reportNotice(_lastWeek)]),
        size: const Size(320, 1400),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
