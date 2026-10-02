/// `전체` 그래프 오류의 다시 시도. (#2879)
///
/// 예전에는 오류 문구만 있어 빠져나갈 길이 없었다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_activity_status.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const ExerciseWeek _week = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
);

void main() {
  testWidgets('오류면 다시 시도 버튼이 있고 누르면 다시 받는다', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    int calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          // `전체`
          exerciseActivityPeriodProvider.overrideWith((ref) => 2),
          exerciseWeekProvider.overrideWith((ref) async => _week),
          exerciseAllPeriodProvider.overrideWith((ref) async {
            calls++;
            if (calls == 1) throw StateError('network down');
            return const <ExerciseDayBar>[];
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(24),
              child: ExerciseActivityStatus(week: _week),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExerciseActivityStatus)),
    );
    expect(find.byKey(const Key('exercise-all-period-error')), findsOneWidget);
    expect(find.text(l.exLoadError), findsOneWidget);
    expect(calls, 1);

    await tester.tap(find.byKey(const Key('exercise-all-period-retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byKey(const Key('exercise-all-period-error')), findsNothing);
    expect(find.text(l.exLoadEmpty), findsOneWidget);
  });
}
