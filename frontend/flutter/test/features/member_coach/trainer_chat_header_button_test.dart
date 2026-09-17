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
          coachUnreadProvider.overrideWith((ref) async => 0),
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
          coachUnreadProvider.overrideWith((ref) async => 0),
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
}
