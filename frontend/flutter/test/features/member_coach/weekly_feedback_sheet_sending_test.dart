/// 주간 피드백을 보내는 동안 시트가 닫히지 않고, 보낸 뒤 아래 화면을 닫지
/// 않는다. (#3096)
///
/// 예전에는 보내기 전에 잡아 둔 navigator 로 성공 뒤 `pop` 했다. 보내는 중에
/// 바깥을 눌러 시트가 먼저 닫히면, 그 `pop` 이 아래의 코치 리포트 화면을 닫았다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/weekly_feedback_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/fake_member_coach_repository.dart';
import '../../helpers/fixed_clock.dart';

final DateTime _week = DateTime(2026, 9, 14);

const Key _below = Key('below-page');

Future<FakeMemberCoachRepository> _pump(WidgetTester tester) async {
  useFixedKstDate(DateTime(2026, 9, 20, 21));
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeMemberCoachRepository repo = FakeMemberCoachRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        memberCoachRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  // 코치 리포트 화면처럼 시트를 띄우는 아래 화면.
                  builder: (BuildContext inner) => Scaffold(
                    key: _below,
                    body: TextButton(
                      onPressed: () =>
                          openWeeklyFeedbackSheet(inner, weekStart: _week),
                      child: const Text('피드백'),
                    ),
                  ),
                ),
              ),
              child: const Text('리포트'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('리포트'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('피드백'));
  await tester.pumpAndSettle();
  return repo;
}

/// 두 문항에 답하고 보내기를 누른다 — 보내기는 [saveGate] 에 걸려 있다.
Future<void> _answerAndSend(
  WidgetTester tester,
  FakeMemberCoachRepository repo,
) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>('weekly-feedback-condition-${WeekCondition.tired.wire}'),
    ),
  );
  await tester.pump();
  await tester.tap(
    find.byKey(
      ValueKey<String>(
        'weekly-feedback-intensity-${WeekIntensity.tooHard.wire}',
      ),
    ),
  );
  await tester.pump();
  repo.saveGate = Completer<void>();
  await tester.tap(find.byKey(const ValueKey<String>('weekly-feedback-send')));
  await tester.pump();
}

Future<void> _finish(
  WidgetTester tester,
  FakeMemberCoachRepository repo,
) async {
  repo.saveGate!.complete();
  await tester.pump();
  await tester.pump(OnCareMotion.toastEnter);
}

Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(OnCareMotion.toastVisible);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('보내는 중에는 바깥을 눌러도·뒤로 가도 닫히지 않고, 보낸 뒤 시트만 닫힌다', (
    WidgetTester tester,
  ) async {
    final FakeMemberCoachRepository repo = await _pump(tester);
    await _answerAndSend(tester, repo);

    // 시트 위쪽 바깥(어두운 막)을 누른다.
    await tester.tapAt(const Offset(200, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('weeklyFeedbackSheet')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('weeklyFeedbackSheet')), findsOneWidget);

    await _finish(tester, repo);
    expect(find.text('주간 피드백을 보냈어요'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(find.byKey(const Key('weeklyFeedbackSheet')), findsNothing);
    expect(find.byKey(_below), findsOneWidget);

    await _drainToast(tester);
  });

  testWidgets('보내는 중에 시트가 먼저 닫혔으면 보낸 뒤 아래 화면을 닫지 않는다', (
    WidgetTester tester,
  ) async {
    final FakeMemberCoachRepository repo = await _pump(tester);
    await _answerAndSend(tester, repo);

    // 끌어 내리기처럼 `PopScope` 를 거치지 않고 시트가 닫힌 경우.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weeklyFeedbackSheet')), findsNothing);

    await _finish(tester, repo);
    expect(find.text('주간 피드백을 보냈어요'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(find.byKey(_below), findsOneWidget);

    await _drainToast(tester);
  });
}
