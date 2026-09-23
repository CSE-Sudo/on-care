import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/coaching_sheet.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// AI 건강 도우미 창 — 이전 디자인 복원(#1831).
const AppConfig _mock = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                TextButton(
                  onPressed: () => showCoachingSheet(context, ref: ref),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.aiCoach,
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('ai-coach')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_mock),
        // 담당 트레이너가 없는 회원 — 대화 버튼이 AI 챗봇으로 간다(#1823).
        memberCoachProvider.overrideWith((ref) => null),
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
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('머리에 Oni 아바타·AI 건강 도우미·오늘의 한 줄이 놓이고 닫기는 없다', (tester) async {
    await _open(tester);

    final Finder header = find.byKey(const Key('coachingSheetHeader'));
    expect(header, findsOneWidget);
    for (final Finder part in <Finder>[
      find.byType(OniAvatar),
      find.text('AI 건강 도우미'),
      find.text('오늘의 맞춤 조언을 모아봤어요'),
    ]) {
      expect(find.descendant(of: header, matching: part), findsOneWidget);
    }

    // 아바타가 왼쪽, 제목이 그 오른쪽이다 — 같은 줄에 있다.
    final Rect avatar = tester.getRect(
      find.descendant(of: header, matching: find.byType(OniAvatar)),
    );
    final Rect title = tester.getRect(find.text('AI 건강 도우미'));
    expect(avatar.right, lessThan(title.left));
    expect(title.center.dy, greaterThan(avatar.top));
    expect(title.center.dy, lessThan(avatar.bottom));

    // 제목 글자는 메인 파랑이다.
    final Text pill = tester.widget<Text>(find.text('AI 건강 도우미'));
    final BuildContext ctx = tester.element(find.text('AI 건강 도우미'));
    expect(pill.style?.color, ctx.oncare.brand.primary);

    // 회원 앱의 부분 창에는 닫기 X 를 두지 않는다 — 공용 X 도, 둥근 X 도
    // 없다(#2170).
    expect(find.byType(AppCloseButton), findsNothing);
    expect(find.byKey(const Key('coachingSheetClose')), findsNothing);
  });

  testWidgets('조언 카드는 왼쪽 알약 태그와 제목·본문이다', (tester) async {
    await _open(tester);

    expect(find.widgetWithText(AppTag, '식단'), findsOneWidget);
    expect(find.widgetWithText(AppTag, '운동'), findsOneWidget);
    final Rect tag = tester.getRect(find.widgetWithText(AppTag, '식단'));
    final Rect title = tester.getRect(find.text('아침 식단 훌륭, 점심 나트륨 주의'));
    expect(tag.right, lessThan(title.left));
  });

  testWidgets('바깥을 누르면 창이 닫히고, 대화 버튼은 AI 코치로 간다', (tester) async {
    await _open(tester);
    // 닫기 X 가 없는 대신 시트 위 빈 곳(막)을 눌러 닫는다.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('coachingSheet')), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coachingSheetCta')));
    await tester.pumpAndSettle();
    expect(find.text('ai-coach'), findsOneWidget);
  });
}
