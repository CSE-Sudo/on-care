/// 추천 개인운동은 매일 새로 체크하는 목록이다. (#2161)
///
/// 트레이너가 바꾸기 전까지 같은 목록이 날마다 미완료로 다시 시작하고, 지난
/// 날짜는 그날 목록과 그날 한 것을 보여 준다. 지난 날짜는 연필을 눌러야
/// 빠뜨린 체크를 고칠 수 있다(#2506).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
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

    // 담당 트레이너가 배정한 것은 회원이 지우지 못한다 — 실서버 403 과 같다
    // (#1020, #2666). 목록도 그대로다.
    await expectLater(coach.deleteRoutine(id), throwsA(isA<ForbiddenError>()));
    expect(
      (await coach.fetchRoutines()).map((CoachRoutine r) => r.id),
      contains(id),
    );
  });

  test('담당이 없으면 추천을 지울 수 있고, 걸려 있던 어제는 그대로다 (#2161)', () async {
    final DateTime day1 = DateTime(2026, 8, 20, 9);
    final DateTime day2 = DateTime(2026, 8, 21, 9);
    useFixedKstDate(day1);
    final MockMemberCoachRepository coach = MockMemberCoachRepository(
      linked: () => false,
    );
    final String id = (await coach.fetchRoutines()).first.id;

    debugNowKstOverride = () => day2;
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

  test('빠뜨린 체크를 지난 날짜로 하고 풀 수 있다 (#2506)', () async {
    final DateTime day1 = DateTime(2026, 8, 20, 9);
    final DateTime day2 = DateTime(2026, 8, 21, 9);
    useFixedKstDate(day1);
    final MockMemberCoachRepository coach = MockMemberCoachRepository();
    final String id = (await coach.fetchRoutines()).first.id;

    debugNowKstOverride = () => day2;
    // 데모의 지난 날짜 완료는 공유 픽스처가 정한다 — 먼저 풀어 빈 칸에서 시작한다.
    await coach.uncompleteRoutine(id, day: DateTime(2026, 8, 20));
    expect(
      (await coach.fetchRoutinesOn(
        day1,
      )).firstWhere((CoachRoutine r) => r.id == id).completed,
      isFalse,
    );
    final CoachRoutine done = await coach.completeRoutine(
      id,
      minutes: 15,
      day: DateTime(2026, 8, 20),
    );
    expect(done.completed, isTrue);
    // 기록은 그날에 놓이고 오늘 목록은 그대로다.
    expect(done.completedAt, DateTime(2026, 8, 20, 12));
    expect((await coach.fetchRoutines()).first.completed, isFalse);
    expect(
      (await coach.fetchRoutinesOn(
        day1,
      )).firstWhere((CoachRoutine r) => r.id == id).completed,
      isTrue,
    );

    await coach.uncompleteRoutine(id, day: DateTime(2026, 8, 20));
    expect(
      (await coach.fetchRoutinesOn(
        day1,
      )).firstWhere((CoachRoutine r) => r.id == id).completed,
      isFalse,
    );

    // 아직 오지 않은 날은 실서버처럼 거절한다.
    expect(
      () => coach.completeRoutine(id, minutes: 5, day: DateTime(2026, 8, 22)),
      throwsArgumentError,
    );
  });

  testWidgets('지난 날짜는 연필을 눌러야 체크할 수 있다 (#2506)', (WidgetTester tester) async {
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
    // 보기 상태 — 눌릴 것처럼 보이는 체크 박스가 없고, 안내도 아직 없다.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(const Key('coachRoutinePastEditHint')), findsNothing);

    await tester.tap(find.byKey(const Key('coachRoutinePastEdit')));
    await tester.pumpAndSettle();

    // 연필을 누르면 체크 박스가 살아나고 트레이너에게 어떻게 보이는지 말한다.
    final Iterable<Checkbox> boxes = tester.widgetList<Checkbox>(
      find.byType(Checkbox),
    );
    expect(boxes, isNotEmpty);
    expect(boxes.every((Checkbox box) => box.onChanged != null), isTrue);
    expect(find.byKey(const Key('coachRoutinePastEditHint')), findsOneWidget);
    expect(find.byKey(const Key('coachRoutinePastEdit')), findsNothing);

    await tester.tap(find.byKey(const Key('coachRoutinePastEditDone')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('오늘 목록에는 연필이 없고 바로 체크한다', (WidgetTester tester) async {
    useFixedKstDate();
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
          home: const Scaffold(
            body: SingleChildScrollView(child: AiCoachingCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('coachRoutinePastEdit')), findsNothing);
    final Iterable<Checkbox> boxes = tester.widgetList<Checkbox>(
      find.byType(Checkbox),
    );
    expect(boxes, isNotEmpty);
    expect(boxes.every((Checkbox box) => box.onChanged != null), isTrue);
  });
}
