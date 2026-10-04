import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/trainer_chat_header_button.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const MemberCoach _coach = MemberCoach(
  trainerId: 'coach-1',
  name: '김트레이너',
  specialty: '체형 교정',
  career: '5년',
  intro: '',
  gymName: '신촌 짐',
  goal: '',
);

/// 규격 아이콘 버튼이 활성으로 그려지는지 읽는다 — 비활성이면 버튼이 흐린
/// 비활성 색으로 칠해지므로, 화면에서 사용자가 구별하는 근거와 같은 것을 본다.
bool _drawnEnabled(WidgetTester tester) {
  return tester
          .widget<IconButton>(
            find.descendant(
              of: find.byType(AppIconButton),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Override coachOverride,
    int unread = 0,
  }) async {
    // AI 챗봇 입구는 라우터로 화면을 연다. 도착한 화면은 표지 글자로 확인한다.
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: TrainerChatHeaderButton()),
        ),
        GoRoute(
          path: AppRoutes.aiCoach,
          builder: (_, _) => const Scaffold(body: Text('ai-coach-route')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          coachOverride,
          coachUnreadProvider.overrideWith((ref) => Stream<int>.value(unread)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('담당 트레이너가 있으면 활성으로 그린다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith((ref) async => _coach),
    );

    expect(_drawnEnabled(tester), isTrue);
    // 트레이너가 있는 회원에게 AI 챗봇 입구는 없다(#1823).
    expect(find.byKey(const Key('aiChatHeaderButton')), findsNothing);
  });

  // 안읽음 배지는 두 앱 공용 [AppCountBadge] 다(#1418, #1702) — 한 자리 수는
  // 정원이고, 두 자리 이상은 같은 높이의 알약이다. 지운 홈 코치 카드(#3104)의
  // 배지 단언을 실제로 배지를 다는 이 버튼으로 옮겼다.
  group('안읽음 배지 모양', () {
    Size badgeSize(WidgetTester tester) =>
        tester.getSize(find.byType(AppCountBadge));

    testWidgets('한 자리 수 배지는 정원이다', (WidgetTester tester) async {
      await pump(
        tester,
        coachOverride: memberCoachProvider.overrideWith((ref) async => _coach),
        unread: 1,
      );
      final Size size = badgeSize(tester);
      expect(size.width, size.height);
    });

    testWidgets('99+ 도 같은 높이의 배지로 줄여 적는다', (WidgetTester tester) async {
      await pump(
        tester,
        coachOverride: memberCoachProvider.overrideWith((ref) async => _coach),
        unread: 120,
      );
      final Size size = badgeSize(tester);
      // 세 글자는 원에 욱여넣지 않고 같은 높이의 알약으로 늘어난다.
      expect(size.height, OnCareSize.countBadgeMin);
      expect(size.width, greaterThanOrEqualTo(size.height));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('안 읽은 것이 없으면 배지를 그리지 않는다', (WidgetTester tester) async {
      await pump(
        tester,
        coachOverride: memberCoachProvider.overrideWith((ref) async => _coach),
      );
      expect(find.byType(AppCountBadge), findsNothing);
      expect(find.text('0'), findsNothing);
    });
  });

  testWidgets('담당 트레이너가 없으면 같은 자리가 AI 챗봇 입구로 바뀐다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith((ref) async => null),
    );

    expect(find.byKey(const Key('trainerChatHeaderButton')), findsNothing);
    final Finder ai = find.byKey(const Key('aiChatHeaderButton'));
    expect(ai, findsOneWidget);
    // 꽉 찬 말풍선 안에 크기가 다른 별들 — 대화 입구라는 것과 AI 라는 것이
    // 아이콘만으로 함께 읽혀야 한다(#1900).
    final Finder glyph = find.descendant(
      of: ai,
      matching: find.byType(AppAiChatGlyph),
    );
    expect(glyph, findsOneWidget);
    // 말풍선은 등록부의 아이콘이고, 별은 그 위에 그려 넣는다.
    expect(
      find.descendant(of: glyph, matching: find.byIcon(AppIcons.chat)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: glyph, matching: find.byType(CustomPaint)),
      findsWidgets,
    );
    // 흐린 비활성 버튼이 아니라 눌리는 버튼이다.
    expect(_drawnEnabled(tester), isTrue);
  });

  testWidgets('담당 트레이너가 없을 때 누르면 AI 챗봇 화면으로 간다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith((ref) async => null),
    );

    await tester.tap(find.byKey(const Key('aiChatHeaderButton')));
    await tester.pumpAndSettle();

    expect(find.text('ai-coach-route'), findsOneWidget);
  });

  testWidgets('담당 조회에 실패하면 AI 챗봇 입구로 단정하지 않는다', (WidgetTester tester) async {
    await pump(
      tester,
      coachOverride: memberCoachProvider.overrideWith(
        (ref) => Future<MemberCoach?>.error(Exception('offline')),
      ),
    );

    // 담당이 있는지 모르는 채로 입구를 바꾸면, 트레이너가 있는 회원에게 AI
    // 챗봇을 내미는 셈이다.
    expect(find.byKey(const Key('aiChatHeaderButton')), findsNothing);
    expect(find.byKey(const Key('trainerChatHeaderButton')), findsOneWidget);
    expect(_drawnEnabled(tester), isFalse);
  });

  testWidgets('조회 중에는 없다고 단정하지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // 끝나지 않는 Future — 로딩 상태로 붙잡아 둔다.
          memberCoachProvider.overrideWith(
            (ref) => Completer<MemberCoach?>().future,
          ),
          coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TrainerChatHeaderButton()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('aiChatHeaderButton')), findsNothing);
    await tester.tap(find.byKey(const Key('trainerChatHeaderButton')));
    await tester.pump();

    // 로딩 중에 "트레이너가 없다" 고 말하면 거짓이 된다.
    expect(find.text('담당 트레이너를 불러오는 중이에요'), findsOneWidget);
  });

  // #2843: 조회 실패는 "담당이 없다" 가 아니다. 서로 다른 문구여야 하고, 실패면
  // 같은 탭으로 다시 읽는다.
  group('조회 실패', () {
    testWidgets('누르면 없다가 아니라 불러오지 못했다고 알린다', (WidgetTester tester) async {
      await pump(
        tester,
        coachOverride: memberCoachProvider.overrideWith(
          (ref) => Future<MemberCoach?>.error(Exception('offline')),
        ),
      );

      await tester.tap(find.byKey(const Key('trainerChatHeaderButton')));
      await tester.pump();

      expect(find.text('담당 트레이너 정보를 불러오지 못해 다시 불러오고 있어요'), findsOneWidget);
      expect(
        find.text('담당 트레이너가 아직 없어요. 운동 탭에서 헬스장·트레이너를 연결해 보세요'),
        findsNothing,
      );
    });

    testWidgets('누르면 다시 읽어 트레이너 버튼이 살아난다', (WidgetTester tester) async {
      var calls = 0;
      await pump(
        tester,
        coachOverride: memberCoachProvider.overrideWith((ref) {
          calls += 1;
          if (calls == 1) {
            return Future<MemberCoach?>.error(Exception('offline'));
          }
          return Future<MemberCoach?>.value(_coach);
        }),
      );
      expect(_drawnEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('trainerChatHeaderButton')));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(_drawnEnabled(tester), isTrue);
      expect(find.byKey(const Key('aiChatHeaderButton')), findsNothing);
    });

    test('영어에서도 실패와 로딩 문구가 갈린다', () {
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

      expect(en.coachTrainerRetrying, isNot(en.coachTrainerNone));
      expect(en.coachTrainerRetrying, isNot(en.coachTrainerLoading));
      expect(en.coachTrainerLoadFailed, isNot(en.coachTrainerNone));
      expect(en.coachTrainerRetrying, isNot(matches(RegExp('[가-힣]'))));
    });
  });
}
