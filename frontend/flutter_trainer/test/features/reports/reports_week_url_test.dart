/// 리포트 화면의 주는 URL 이 원본이다 (#2289).
///
/// 리포트 탭은 다른 탭에 다녀와도 살아 있다(StatefulShellRoute). 그래서 주를
/// 화면이 처음 열릴 때 한 번만 정하면, 채팅의 리포트 카드가 지난 주를
/// 가리켜도 보던 주가 그대로 열린다. 이 파일이 보는 것은 URL 과 화면의 주가
/// 언제나 같은 주를 말하는가다 — 들어오는 링크, 화살표, 회원 전환, 새로고침.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_nav.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// 지난 주에는 데모 전송 기록이 붙지 않도록 시드 밖의 id 로 짠 로스터.
final List<TrainerClient> _roster = <TrainerClient>[
  makeClient(id: 'a', name: '가회원'),
  makeClient(id: 'h', name: '하회원'),
];

/// [kMidWeekKst](2026-08-20 목) 기준의 주들.
final DateTime _thisWeek = DateTime(2026, 8, 17);
final DateTime _lastWeek = DateTime(2026, 8, 10);
final DateTime _twoWeeksAgo = DateTime(2026, 8, 3);

void main() {
  final Finder prevWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
  );
  final Finder nextWeek = find.descendant(
    of: find.byType(ReportWeekNav),
    matching: find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
  );
  final Finder goThisWeek = find.byKey(
    const ValueKey<String>('reports-go-this-week'),
  );
  final Finder backToList = find.byKey(
    const ValueKey<String>('reports-back-to-list'),
  );

  /// ③ 전송 단계에만 있는 피드백 입력창. 머리의 회원 검색창과 가르려고
  /// 안내 문구로 찾는다.
  final Finder feedbackField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == '회원에게 전달할 코칭 피드백을 작성하세요.',
  );
  final Finder nextStep = find.byKey(
    const ValueKey<String>('report-step-next'),
  );

  /// 작업대 카드 제목 줄의 주 표시 — `8월 10일 – 8월 16일`.
  String koRange(DateTime monday) {
    final DateTime sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return '${monday.month}월 ${monday.day}일 – '
        '${sunday.month}월 ${sunday.day}일';
  }

  String enRange(DateTime monday) {
    final DateTime sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return '${monday.month}/${monday.day} – ${sunday.month}/${sunday.day}';
  }

  /// URL 의 query 만 떼어 본다 — 순서에 매이지 않게.
  Map<String, String> query(WidgetTester tester) =>
      Uri.parse(currentLocation(tester)).queryParameters;

  Future<void> pump(
    WidgetTester tester, {
    String? at,
    String? bootAt,
    Locale locale = const Locale('ko'),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    useFixedKstDate();
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      bootAt: bootAt,
      locale: locale,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(_roster),
        ),
      ],
    );
    await settle(tester);
  }

  /// 편집기에서 작업대로 돌아간다.
  Future<void> back(WidgetTester tester) async {
    await tester.tap(backToList);
    await settle(tester);
  }

  /// 편집기를 [stage] 단계까지 넘긴다.
  Future<void> advance(WidgetTester tester, int stage) async {
    for (int i = 0; i < stage; i++) {
      await tester.tap(nextStep);
      await settle(tester);
    }
  }

  group('들어오는 링크', () {
    testWidgets('살아 있는 탭에 지난 주 링크가 오면 그 주로 옮긴다', (tester) async {
      await pump(tester, at: AppRoutes.reportFor('a'));
      expect(find.text('가회원님 주간 리포트'), findsOneWidget);

      // 채팅 탭에 다녀온다 — 리포트 탭은 그동안 살아 있다.
      await goTo(tester, AppRoutes.messagesFor('a'));
      // 채팅의 리포트 카드가 하는 일 그대로다(chat_view.dart).
      await goTo(tester, AppRoutes.reportFor('a', weekStart: _twoWeeksAgo));

      expect(find.text('가회원님 주간 리포트'), findsOneWidget);
      await back(tester);
      expect(find.text(koRange(_twoWeeksAgo)), findsWidgets);
      expect(query(tester)['week'], '2026-08-03');
      expect(tester.takeException(), isNull);
    });

    testWidgets('같은 회원의 다른 주 링크는 편집 단계를 처음으로 되돌린다', (tester) async {
      await pump(tester, at: AppRoutes.reportFor('a', weekStart: _lastWeek));
      await advance(tester, 2);
      expect(feedbackField, findsWidgets);

      await goTo(tester, AppRoutes.reportFor('a', weekStart: _twoWeeksAgo));

      // ③ 전송 단계의 피드백 입력창이 사라졌다 — ① 이번 주 확인이다.
      expect(feedbackField, findsNothing);
      await back(tester);
      expect(find.text(koRange(_twoWeeksAgo)), findsWidgets);
    });

    testWidgets('같은 주 링크는 쓰던 단계를 지킨다', (tester) async {
      await pump(tester, at: AppRoutes.reportFor('a', weekStart: _lastWeek));
      await advance(tester, 2);

      await goTo(tester, AppRoutes.messagesFor('a'));
      // 월요일이 아닌 날로 와도 같은 주다.
      await goTo(
        tester,
        AppRoutes.reportFor('a', weekStart: DateTime(2026, 8, 13)),
      );

      expect(feedbackField, findsWidgets);
    });

    testWidgets('주가 빠진 링크는 이번 주로 돌아온다', (tester) async {
      await pump(tester, at: AppRoutes.reportFor(null, weekStart: _lastWeek));
      expect(find.text(koRange(_lastWeek)), findsWidgets);

      // 대시보드·검색처럼 주를 모르는 곳에서 온 링크다.
      await goTo(tester, AppRoutes.reports);

      expect(find.text(koRange(_thisWeek)), findsWidgets);
      expect(goThisWeek, findsNothing);
    });

    testWidgets('월요일이 아닌 날은 그 주의 월요일로 맞춘다', (tester) async {
      await pump(
        tester,
        at: AppRoutes.reportFor(null, weekStart: DateTime(2026, 8, 16)),
      );

      expect(find.text(koRange(_lastWeek)), findsWidgets);
    });
  });

  group('주 이동이 URL 을 바꾼다', () {
    testWidgets('이전 주로 가면 URL 에 주가 실린다', (tester) async {
      await pump(tester, at: AppRoutes.reports);
      expect(query(tester).containsKey('week'), isFalse);

      await tester.tap(prevWeek);
      await settle(tester);

      expect(find.text(koRange(_lastWeek)), findsWidgets);
      expect(query(tester)['week'], '2026-08-10');
      expect(query(tester).containsKey('client'), isFalse);

      await tester.tap(prevWeek);
      await settle(tester);
      expect(query(tester)['week'], '2026-08-03');
    });

    testWidgets('이번 주로 돌아오면 URL 에서 주가 빠진다', (tester) async {
      await pump(tester, at: AppRoutes.reports);
      await tester.tap(prevWeek);
      await settle(tester);

      await tester.tap(nextWeek);
      await settle(tester);

      expect(find.text(koRange(_thisWeek)), findsWidgets);
      expect(currentLocation(tester), AppRoutes.reports);
    });

    testWidgets('`오늘` 버튼도 URL 을 이번 주로 되돌린다', (tester) async {
      await pump(
        tester,
        at: AppRoutes.reportFor(null, weekStart: _twoWeeksAgo),
      );

      await tester.tap(goThisWeek);
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.reports);
      expect(find.text(koRange(_thisWeek)), findsWidgets);
    });

    testWidgets('이번 주에서는 다음 주로 가지 않는다', (tester) async {
      await pump(tester, at: AppRoutes.reports);

      expect(tester.widget<IconButton>(nextWeek).onPressed, isNull);
    });

    testWidgets('달을 넘어 옮겨도 월요일에 선다', (tester) async {
      // 9/7 주에서 한 주 앞은 8/31 — 달 경계에서도 날짜로 센다.
      useFixedKstDate(DateTime(2026, 9, 9, 13));
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.reports,
        extraOverrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(_roster),
          ),
        ],
      );
      await settle(tester);

      await tester.tap(prevWeek);
      await settle(tester);
      expect(query(tester)['week'], '2026-08-31');

      await tester.tap(prevWeek);
      await settle(tester);
      expect(query(tester)['week'], '2026-08-24');
    });
  });

  group('회원을 바꿔도 주는 그대로다', () {
    testWidgets('작업대에서 고른 주로 편집기가 열린다', (tester) async {
      await pump(tester, at: AppRoutes.reports);
      await tester.tap(prevWeek);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey<String>('reports-queue-h')));
      await settle(tester);

      expect(find.text('하회원님 주간 리포트'), findsOneWidget);
      expect(query(tester), <String, String>{
        'client': 'h',
        'week': '2026-08-10',
      });
    });

    testWidgets('편집기에서 작업대로 돌아와도 그 주에 머문다', (tester) async {
      await pump(tester, at: AppRoutes.reportFor('h', weekStart: _lastWeek));

      await back(tester);

      expect(find.byType(ReportWorkbench), findsOneWidget);
      expect(find.text(koRange(_lastWeek)), findsWidgets);
      expect(query(tester), <String, String>{'week': '2026-08-10'});

      await tester.tap(find.byKey(const ValueKey<String>('reports-queue-a')));
      await settle(tester);
      expect(query(tester), <String, String>{
        'client': 'a',
        'week': '2026-08-10',
      });
    });

    testWidgets('이번 주에 고르면 URL 에 주를 싣지 않는다', (tester) async {
      await pump(tester, at: AppRoutes.reports);

      await tester.tap(find.byKey(const ValueKey<String>('reports-queue-a')));
      await settle(tester);

      expect(currentLocation(tester), AppRoutes.reportFor('a'));
    });
  });

  group('새로고침 — URL 로 부팅', () {
    testWidgets('작업대의 지난 주로 다시 열린다', (tester) async {
      await pump(tester, bootAt: '/reports?week=2026-08-10');

      expect(find.byType(ReportWorkbench), findsOneWidget);
      expect(find.text(koRange(_lastWeek)), findsWidgets);
      expect(goThisWeek, findsOneWidget);
    });

    testWidgets('편집기의 지난 주로 다시 열린다', (tester) async {
      await pump(tester, bootAt: '/reports?client=h&week=2026-08-03');

      expect(find.text('하회원님 주간 리포트'), findsOneWidget);
      await back(tester);
      expect(find.text(koRange(_twoWeeksAgo)), findsWidgets);
    });

    testWidgets('주를 옮긴 URL 을 그대로 다시 열면 같은 주다', (tester) async {
      await pump(tester, at: AppRoutes.reports);
      await tester.tap(prevWeek);
      await settle(tester);
      await tester.tap(prevWeek);
      await settle(tester);
      final String saved = currentLocation(tester);

      await goTo(tester, AppRoutes.dashboard);
      await goTo(tester, saved);

      expect(find.text(koRange(_twoWeeksAgo)), findsWidgets);
    });
  });

  group('잘못된 week 값', () {
    for (final String raw in <String>[
      'garbage',
      '2026-02-30',
      '2026-13-01',
      '2026-8-3',
      '',
    ]) {
      testWidgets('`$raw` 는 이번 주로 연다', (tester) async {
        await pump(
          tester,
          bootAt: '/reports?week=${Uri.encodeQueryComponent(raw)}',
        );

        expect(find.byType(ReportWorkbench), findsOneWidget);
        expect(find.text(koRange(_thisWeek)), findsWidgets);
        expect(goThisWeek, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('아직 오지 않은 주는 이번 주로 당긴다', (tester) async {
      await pump(tester, bootAt: '/reports?week=2026-09-14');

      expect(find.text(koRange(_thisWeek)), findsWidgets);
      expect(tester.widget<IconButton>(nextWeek).onPressed, isNull);
    });

    testWidgets('살아 있는 탭에 잘못된 주가 와도 이번 주로 연다', (tester) async {
      await pump(tester, at: AppRoutes.reportFor(null, weekStart: _lastWeek));

      await goTo(tester, '/reports?week=nope');

      expect(find.text(koRange(_thisWeek)), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('영어', () {
    testWidgets('지난 주 링크와 주 이동이 영어 화면에서도 같다', (tester) async {
      await pump(
        tester,
        at: AppRoutes.reportFor(null, weekStart: _twoWeeksAgo),
        locale: const Locale('en'),
      );
      expect(find.text(enRange(_twoWeeksAgo)), findsWidgets);

      await tester.tap(nextWeek);
      await settle(tester);

      expect(find.text(enRange(_lastWeek)), findsWidgets);
      expect(query(tester)['week'], '2026-08-10');
      expect(tester.takeException(), isNull);
    });
  });
}
