/// 받은 리포트 목록 — 대화 전체에서 고르고, 새 리포트가 오면 다시 읽는다. (#2643)
///
/// 예전에는 대화의 최신 50건만 읽어 몇 주 전 리포트가 목록에서 사라졌고, 한 번
/// 읽은 목록이 세션 내내 남아 새 리포트가 앱을 다시 켜기 전까지 보이지 않았다.
/// 읽기 실패에는 `보내지 못했어요`·`PDF 를 열지 못했어요` 가 떴다.
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
final DateTime _week3 = DateTime(2026, 8, 10);

/// [from] 부터 [to] 전까지의 보통 대화 — 리포트가 아니다.
List<CoachMessage> _lines(int from, int to) => <CoachMessage>[
  for (int i = from; i < to; i++) chatLine(i),
];

/// 대화 [minute] 분 자리에 놓인 리포트 안내.
CoachMessage _reportAt(int minute, DateTime week, {String? id}) => reportNotice(
  week,
  id: id ?? 'report-$minute',
  createdAt: chatLine(minute).createdAt,
);

Future<List<SentReportNotice>> _notices(ProviderContainer container) {
  container.listen(sentReportNoticesProvider, (_, _) {});
  return container.read(sentReportNoticesProvider.future);
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

/// 커서를 무시하고 언제나 같은 쪽을 주는 대역 — 멈춤 조건을 본다.
class _IgnoresCursorRepository extends FakeMemberCoachRepository {
  _IgnoresCursorRepository({super.chat});

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async {
    chatCursors.add(before);
    return pageCoachChat(chat);
  }
}

/// 부를 때마다 새 메시지 한 쪽을 끝없이 주는 대역 — 상한을 본다.
class _EndlessRepository extends FakeMemberCoachRepository {
  int _next = 0;

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) async {
    chatCursors.add(before);
    final int start = _next;
    _next += chatPageSize;
    return <CoachMessage>[
      for (int i = start; i < start + chatPageSize; i++)
        chatLine(-i, id: 'endless-$i'),
    ];
  }
}

/// 대화를 읽지 못하는 대역.
class _ChatFailsRepository extends FakeMemberCoachRepository {
  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) =>
      Future<List<CoachMessage>>.error(StateError('chat unavailable'));
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

  group('대화를 끝까지 읽기', () {
    test('50건보다 앞에 있던 리포트도 목록에 선다', () async {
      // 120건짜리 대화. 리포트는 5번째와 60번째 — 둘 다 최신 50건 밖이다.
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: <CoachMessage>[
          ..._lines(0, 120).where((CoachMessage m) {
            return m.id != chatLine(5).id && m.id != chatLine(60).id;
          }),
          _reportAt(5, _week1),
          _reportAt(60, _week2),
          _reportAt(119, _week3, id: 'report-latest'),
        ],
      );

      final List<SentReportNotice> notices = await _notices(
        _container(repository),
      );

      expect(
        notices.map((SentReportNotice n) => n.weekStart).toList(),
        <DateTime>[_week3, _week2, _week1],
      );
    });

    test('한 쪽이 다 찼으면 가장 오래된 메시지를 커서로 앞 쪽을 받는다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: _lines(0, 120),
      );

      final List<CoachMessage> all = await fetchWholeCoachChat(repository);

      expect(all, hasLength(120));
      expect(
        repository.chatCursors.map((CoachMessage? m) => m?.id).toList(),
        <String?>[null, chatLine(70).id, chatLine(20).id],
      );
    });

    test('한 쪽이 덜 차면 더 부르지 않는다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: _lines(0, 30),
      );

      await fetchWholeCoachChat(repository);

      expect(repository.chatCursors, <CoachMessage?>[null]);
    });

    test('쪽 경계가 정확히 맞아떨어지면 빈 쪽을 받고 멈춘다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: _lines(0, chatPageSize * 2),
      );

      final List<CoachMessage> all = await fetchWholeCoachChat(repository);

      expect(all, hasLength(chatPageSize * 2));
      expect(repository.chatCursors, hasLength(3));
    });

    test('커서를 무시하는 서버를 만나도 새로 받은 것이 없으면 멈춘다', () async {
      final _IgnoresCursorRepository repository = _IgnoresCursorRepository(
        chat: _lines(0, 120),
      );

      final List<CoachMessage> all = await fetchWholeCoachChat(repository);

      expect(all, hasLength(chatPageSize));
      expect(repository.chatCursors, hasLength(2));
    });

    test('끝없이 새 쪽을 주는 서버도 상한에서 멈춘다', () async {
      final _EndlessRepository repository = _EndlessRepository();

      final List<CoachMessage> all = await fetchWholeCoachChat(
        repository,
        maxPages: 4,
      );

      expect(repository.chatCursors, hasLength(4));
      expect(all, hasLength(chatPageSize * 4));
    });

    test('받은 대화는 오래된 → 최신으로 겹침 없이 선다', () async {
      final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
        chat: _lines(0, 120).reversed.toList(),
      );

      final List<CoachMessage> all = await fetchWholeCoachChat(repository);
      final List<String> ids = <String>[for (final CoachMessage m in all) m.id];

      expect(ids, <String>[for (int i = 0; i < 120; i++) chatLine(i).id]);
    });
  });

  group('리포트 고르기', () {
    test('리포트 안내만 고르고 같은 주는 마지막 것 하나만 남긴다', () {
      final List<SentReportNotice> notices = selectReportNotices(<CoachMessage>[
        plainMessage(),
        reportNotice(_week2, id: 'old', createdAt: DateTime(2026, 7, 12, 9)),
        reportNotice(_week2, id: 'new', createdAt: DateTime(2026, 7, 12, 21)),
        reportNotice(_week1, id: 'r1'),
      ]);

      expect(
        notices.map((SentReportNotice n) => n.message.id).toList(),
        <String>['new', 'r1'],
      );
    });

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
      final List<SentReportNotice> first = await _notices(container);
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

      final List<SentReportNotice> next = await container.read(
        sentReportNoticesProvider.future,
      );
      expect(next.map((SentReportNotice n) => n.message.id).toSet(), <String>{
        'r1',
        'r2',
      });
    });
  });

  group('오류 문구', () {
    testWidgets('목록을 읽지 못하면 불러오지 못했다고 말한다', (tester) async {
      await _pumpPage(tester, _container(_ChatFailsRepository()));

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
      await _pumpPage(tester, _container(_ChatFailsRepository()), locale: 'en');

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
      final _FlakyChatRepository repository = _FlakyChatRepository(
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

/// 처음에는 대화를 읽지 못하다가 풀리는 대역.
class _FlakyChatRepository extends FakeMemberCoachRepository {
  _FlakyChatRepository({super.chat});

  bool failing = true;

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) {
    if (failing) {
      return Future<List<CoachMessage>>.error(StateError('chat unavailable'));
    }
    return super.fetchChat(before: before);
  }
}
