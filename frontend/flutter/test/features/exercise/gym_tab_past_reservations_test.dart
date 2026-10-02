/// 헬스장 탭 트레이너 패널의 지난 예약 접기. (#2879)
///
/// 서버는 지난 예약도 함께 준다. 모두 그리면 PT 를 꾸준히 받는 회원일수록
/// 패널이 지난 줄로 길어져 다가오는 예약과 빈 자리 고르기가 아래로 밀렸다.
/// 다가오는 예약은 모두, 지난 예약은 최근 몇 건만 두고 나머지는 `더 보기` 로 접는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_tab.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../support/consultation_test_support.dart';

const Gym _gym = Gym(
  id: 'gym-past',
  name: '지난 예약 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['PT'],
  lat: 37.5559,
  lng: 126.9368,
);

const Trainer _trainer = Trainer(
  id: 'trainer-past',
  gymId: 'gym-past',
  name: '김트레이너',
  role: '전담 트레이너',
);

/// 지난 예약 [count] 건 — KST 고정 날짜, 최근 것부터(서버 순서와 같다).
List<MyReservation> _past(int count) => <MyReservation>[
  for (int i = 0; i < count; i++)
    MyReservation(
      id: 'past-$i',
      slotId: 'slot-past-$i',
      trainerId: _trainer.id,
      startsAt: DateTime(2026, 9, 20 - i, 10),
      cancellable: false,
    ),
];

MyReservation get _upcoming => MyReservation(
  id: 'next',
  slotId: 'slot-next',
  trainerId: _trainer.id,
  startsAt: DateTime(2026, 10, 5, 10),
  cancellable: true,
);

void main() {
  Future<AppLocalizations> pumpTab(
    WidgetTester tester,
    List<MyReservation> reservations,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          recommendedTrainersProvider.overrideWith(
            (ref) async => const <Trainer>[],
          ),
          trainerSlotsProvider(_trainer.id).overrideWith(
            (ref) async => <TrainerSlot>[
              TrainerSlot(
                id: 'slot-open',
                trainerId: _trainer.id,
                startsAt: DateTime(2026, 10, 6, 10),
                booked: false,
                sessionType: '1:1 PT',
              ),
            ],
          ),
          myReservationsProvider.overrideWith((ref) async => reservations),
          consultationRequestControllerProvider.overrideWith(
            (ref) => newTestConsultationController(),
          ),
          memberCoachProvider.overrideWith((ref) async => null),
          coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GymTab(selectedSlot: null, onSlot: (String _) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  }

  const Key toggle = Key('reservations-past-toggle');

  testWidgets('지난 예약이 많으면 최근 몇 건만 보이고 나머지는 접힌다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(tester, <MyReservation>[
      _upcoming,
      ..._past(8),
    ]);

    // 다가오는 예약은 그대로 맨 위에 있고 취소할 수 있다.
    expect(
      find.byKey(const ValueKey<String>('cancel-reservation-next')),
      findsOneWidget,
    );
    expect(
      find.text(l.exReservationPast),
      findsNWidgets(kRecentPastReservations),
    );
    expect(find.byKey(toggle), findsOneWidget);
    expect(
      find.text(l.exReservationPastMore(8 - kRecentPastReservations)),
      findsOneWidget,
    );
  });

  testWidgets('더 보기를 누르면 모두 펼치고 다시 접을 수 있다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(tester, _past(6));

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.text(l.exReservationPast), findsNWidgets(6));
    expect(find.text(l.exReservationPastLess), findsOneWidget);

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(
      find.text(l.exReservationPast),
      findsNWidgets(kRecentPastReservations),
    );
  });

  testWidgets('지난 예약이 몇 건뿐이면 접지 않는다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(
      tester,
      _past(kRecentPastReservations),
    );

    expect(
      find.text(l.exReservationPast),
      findsNWidgets(kRecentPastReservations),
    );
    expect(find.byKey(toggle), findsNothing);
  });

  testWidgets('지난 예약만 쌓여도 빈 자리 고르기가 보인다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(tester, _past(20));

    expect(find.text(l.exTrainerAvailability(_trainer.name)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('slot-chip-slot-open')),
      findsOneWidget,
    );
    expect(
      find.text(l.exReservationPast),
      findsNWidgets(kRecentPastReservations),
    );
  });
}
