/// 헬스장 탭에서 잡은 예약이 운동 기록의 `다음 PT` 에 그대로 뜬다. (#1137)
///
/// 예약해 놓고도 `다음 PT 일정이 아직 없어요` 가 떠 있으면, 방금 한 일이
/// 어디에도 남지 않은 것처럼 보인다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const Gym _gym = Gym(
  id: 'gym-next-pt',
  name: '다음PT 테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['PT'],
);

const Trainer _trainer = Trainer(
  id: 'trainer-next-pt',
  gymId: 'gym-next-pt',
  name: '김트레이너',
  role: '전담 트레이너',
);

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-next-pt',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '다음PT 테스트 헬스장',
  goal: '',
);

Future<AppLocalizations> _pump(
  WidgetTester tester, {
  required List<MyReservation> reservations,
}) async {
  tester.view.physicalSize = const Size(420, 2200);
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
        myGymProvider.overrideWith((ref) async => _gym),
        myTrainerProvider.overrideWith((ref) async => _trainer),
        myReservationsProvider.overrideWith((ref) async => reservations),
        memberCoachProvider.overrideWith((ref) async => _coach),
        // 트레이너가 잡아 준 일정은 없다 — 예약만으로 다음 PT 가 서야 한다.
        coachSessionsProvider.overrideWith(
          (ref) async => const <CoachSession>[],
        ),
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ExercisePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(ExercisePage)));
}

void main() {
  testWidgets('예약이 없으면 아직 일정이 없다고 말한다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(
      tester,
      reservations: const <MyReservation>[],
    );

    expect(find.text(l.exNextPtNone), findsOneWidget);
  });

  testWidgets('예약을 확정하면 그 일정이 다음 PT 로 뜬다', (WidgetTester tester) async {
    final DateTime at = nowKst().add(const Duration(days: 3));
    final AppLocalizations l = await _pump(
      tester,
      reservations: <MyReservation>[
        MyReservation(
          id: 'res-1',
          slotId: 'slot-1',
          trainerId: _trainer.id,
          startsAt: DateTime(at.year, at.month, at.day, 19),
          cancellable: true,
        ),
      ],
    );

    expect(find.text(l.exNextPtNone), findsNothing);
    expect(find.textContaining('다음 PT'), findsWidgets);
  });

  testWidgets('지난 예약(취소 불가)은 다음 PT 가 아니다', (WidgetTester tester) async {
    final DateTime at = nowKst().subtract(const Duration(days: 3));
    final AppLocalizations l = await _pump(
      tester,
      reservations: <MyReservation>[
        MyReservation(
          id: 'res-old',
          slotId: 'slot-old',
          trainerId: _trainer.id,
          startsAt: DateTime(at.year, at.month, at.day, 19),
          cancellable: false,
        ),
      ],
    );

    expect(find.text(l.exNextPtNone), findsOneWidget);
  });
}
