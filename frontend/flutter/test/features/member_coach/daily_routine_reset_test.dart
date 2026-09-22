/// 추천 개인운동은 매일 새로 체크하는 목록이다. (#2161)
///
/// 트레이너가 바꾸기 전까지 같은 목록이 날마다 미완료로 다시 시작하고, 지난
/// 날짜는 그날 목록과 그날 한 것을 보여 주되 체크할 수 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  test('다음 날 목록은 미완료로 다시 시작하고, 어제 한 것은 어제에 남는다', () async {
    final DateTime day1 = DateTime(2026, 8, 20, 9);
    final DateTime day2 = DateTime(2026, 8, 21, 9);
    useFixedKstDate(day1);
    final MockMemberCoachRepository coach = MockMemberCoachRepository();
    final String id = (await coach.fetchRoutines()).first.id;

    await coach.completeRoutine(id, minutes: 20);
    expect((await coach.fetchRoutines()).first.completed, isTrue);

    debugNowKstOverride = () => day2;
    expect((await coach.fetchRoutines()).first.completed, isFalse);
    final CoachRoutine yesterday = (await coach.fetchRoutinesOn(
      day1,
    )).firstWhere((CoachRoutine r) => r.id == id);
    expect(yesterday.completed, isTrue);
    expect(yesterday.completedMinutes, 20);

    // 기간 되짚기(#2162)가 읽는 모양 — 날마다 한 칸, 오늘까지.
    final List<RoutineDay> days = coach.routineDaysBetween(
      DateTime(2026, 8, 20),
      DateTime(2026, 8, 25),
    );
    expect(days.map((RoutineDay d) => d.date.day), <int>[20, 21]);
    expect(
      days.first.routines.firstWhere((CoachRoutine r) => r.id == id).completed,
      isTrue,
    );

    // 취소하면 오늘부터 빠지고, 걸려 있던 어제는 그대로다.
    await coach.deleteRoutine(id);
    expect(
      (await coach.fetchRoutines()).map((CoachRoutine r) => r.id),
      isNot(contains(id)),
    );
    expect(
      (await coach.fetchRoutinesOn(day1)).map((CoachRoutine r) => r.id),
      contains(id),
    );
  });

  testWidgets('지난 날짜의 목록은 체크할 수 없다', (WidgetTester tester) async {
    useFixedKstDate();
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost',
              useMockApi: true,
            ),
          ),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiCoachingCard(
                day: todayKst().subtract(const Duration(days: 1)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aiCoachingCardPast')), findsOneWidget);
    expect(find.byKey(const Key('coachRoutinePastReadOnly')), findsOneWidget);
    final Iterable<Checkbox> boxes = tester.widgetList<Checkbox>(
      find.byType(Checkbox),
    );
    expect(boxes, isNotEmpty);
    expect(boxes.every((Checkbox box) => box.onChanged == null), isTrue);
  });
}
