/// 일요일에 들어오면 앱이 먼저 묻는다. (#2232)
///
/// 피드백은 주에 한 번이라, 화면 어딘가의 버튼으로만 두면 그 화면에 들어온
/// 주만 답이 쌓인다. 그렇다고 아무 때나 창을 띄우면 회원은 답하기보다 닫는
/// 법을 먼저 익힌다. 이 시험이 지키는 것은 그 둘 사이의 선이다 —
/// **물어야 할 때만, 한 번만.**
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_feedback_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_prompter.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';

/// 묻는 날들. 2026-08-23 은 일요일, 24 는 월요일.
final DateTime _sunday = DateTime(2026, 8, 23, 10);
final DateTime _monday = DateTime(2026, 8, 24, 10);
final DateTime _wednesday = DateTime(2026, 8, 26, 10);

/// 일요일과 그 다음 월요일이 함께 가리키는 한 주(8/17~8/23), 그리고 그 앞 주.
final DateTime _askedWeek = DateTime(2026, 8, 17);
final DateTime _weekBefore = DateTime(2026, 8, 10);

MemberWeeklyFeedback _sent(DateTime week) => MemberWeeklyFeedback(
  weekStart: week,
  submitted: true,
  condition: WeekCondition.good,
  intensity: WeekIntensity.right,
);

Finder get _sheet => find.byKey(const ValueKey<String>('weeklyFeedbackSheet'));

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeMemberCoachRepository repository, {
  String locale = 'ko',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 900);
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
        home: const WeeklyFeedbackPrompter(
          child: Scaffold(body: Center(child: Text('홈'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('일요일에 들어오면 묻는다', (tester) async {
    useFixedKstDate(_sunday);

    await _pump(tester, FakeMemberCoachRepository());

    expect(_sheet, findsOneWidget);
  });

  testWidgets('일요일에 묻는 주는 오늘이 속한 그 주다', (tester) async {
    useFixedKstDate(_sunday);
    final FakeMemberCoachRepository repository = FakeMemberCoachRepository();

    final ProviderContainer container = await _pump(tester, repository);

    expect(container.read(weeklyFeedbackPromptProvider).value, _askedWeek);
  });

  testWidgets('월요일에 한 번 더 묻는다 — 일요일을 놓친 회원을 위해', (tester) async {
    useFixedKstDate(_monday);

    final ProviderContainer container = await _pump(
      tester,
      FakeMemberCoachRepository(),
    );

    expect(_sheet, findsOneWidget);
    // 월요일에 묻는 것은 어제 끝난 주다 — 이제 막 시작한 주가 아니다. 그래서
    // 일요일에 물었을 주와 같은 주이고, 답이 어느 주로 가는지 흔들리지 않는다.
    expect(container.read(weeklyFeedbackPromptProvider).value, _askedWeek);
  });

  testWidgets('주 중간에는 묻지 않는다', (tester) async {
    useFixedKstDate(_wednesday);

    await _pump(tester, FakeMemberCoachRepository());

    // 주가 끝나지 않았는데 한 주를 돌아보라고 물을 수 없다.
    expect(_sheet, findsNothing);
  });

  testWidgets('이미 답한 주는 다시 묻지 않는다', (tester) async {
    useFixedKstDate(_sunday);

    await _pump(
      tester,
      FakeMemberCoachRepository(
        feedback: <DateTime, MemberWeeklyFeedback>{_askedWeek: _sent(_askedWeek)},
      ),
    );

    expect(_sheet, findsNothing);
  });

  testWidgets('앞 주에만 답했으면 끝난 주는 묻는다', (tester) async {
    useFixedKstDate(_sunday);

    await _pump(
      tester,
      FakeMemberCoachRepository(
        feedback: <DateTime, MemberWeeklyFeedback>{_weekBefore: _sent(_weekBefore)},
      ),
    );

    expect(_sheet, findsOneWidget);
  });

  testWidgets('담당 트레이너가 없으면 묻지 않는다', (tester) async {
    useFixedKstDate(_sunday);

    await _pump(tester, FakeMemberCoachRepository(coach: null));

    // 받는 사람이 없는 피드백은 아무 데도 닿지 않는다.
    expect(_sheet, findsNothing);
  });

  testWidgets('나중에를 누르면 그 세션에서는 다시 묻지 않는다', (tester) async {
    useFixedKstDate(_sunday);
    final ProviderContainer container = await _pump(
      tester,
      FakeMemberCoachRepository(),
    );
    expect(_sheet, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('weekly-feedback-later')),
    );
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(container.read(weeklyFeedbackDismissedProvider), isTrue);
  });

  testWidgets('물린 뒤 화면이 다시 그려져도 창이 돌아오지 않는다', (tester) async {
    useFixedKstDate(_sunday);
    final ProviderContainer container = await _pump(
      tester,
      FakeMemberCoachRepository(),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('weekly-feedback-later')),
    );
    await tester.pumpAndSettle();
    // 탭을 옮기거나 목록을 다시 읽는 것과 같은 일 — 셸은 그대로다.
    container.invalidate(memberWeeklyFeedbackProvider);
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
  });

  testWidgets('창을 두 겹으로 띄우지 않는다', (tester) async {
    useFixedKstDate(_sunday);
    final ProviderContainer container = await _pump(
      tester,
      FakeMemberCoachRepository(),
    );

    // 떠 있는 동안 값이 다시 와도(복귀·폴링) 한 겹으로 남아야 한다.
    container.invalidate(memberWeeklyFeedbackProvider);
    await tester.pumpAndSettle();

    expect(_sheet, findsOneWidget);
  });

  testWidgets('답을 보내면 창이 닫히고 물음이 사라진다', (tester) async {
    useFixedKstDate(_sunday);
    final FakeMemberCoachRepository repository = FakeMemberCoachRepository();
    final ProviderContainer container = await _pump(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('weekly-feedback-condition-good')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('weekly-feedback-intensity-right')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('weekly-feedback-send')));
    await tester.pumpAndSettle();

    expect(_sheet, findsNothing);
    expect(repository.saved.single.weekStart, _askedWeek);
    // 보냈는데 물음이 남아 있으면 보낸 것이 맞는지 알 수 없다.
    expect(container.read(weeklyFeedbackPromptProvider).value, isNull);
    // 보낸 것은 무르는 것과 다르다 — 물림 표시까지 서지는 않는다.
    expect(container.read(weeklyFeedbackDismissedProvider), isFalse);
  });

  testWidgets('영어에서도 같은 창이 뜬다', (tester) async {
    useFixedKstDate(_sunday);

    await _pump(tester, FakeMemberCoachRepository(), locale: 'en');

    expect(_sheet, findsOneWidget);
    expect(find.text('How was your week?'), findsOneWidget);
  });

  testWidgets('묻지 않는 날에도 셸은 그대로 그려진다', (tester) async {
    useFixedKstDate(_wednesday);

    await _pump(tester, FakeMemberCoachRepository());

    expect(find.text('홈'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
