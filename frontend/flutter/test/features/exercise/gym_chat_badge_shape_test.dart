/// 트레이너와 채팅 버튼의 읽지 않음 배지는 정원이다. (#1138)
///
/// 좌우 여백만 주면 글자 높이만큼 세로로 길어져 알약처럼 보였다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_tab.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../support/consultation_test_support.dart';

const Gym _gym = Gym(
  id: 'gym-badge',
  name: '배지 테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['PT'],
);

const Trainer _trainer = Trainer(
  id: 'trainer-badge',
  gymId: 'gym-badge',
  name: '김트레이너',
  role: '전담 트레이너',
);

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-badge',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '배지 테스트 헬스장',
  goal: '',
);

Future<void> _pump(WidgetTester tester, int unread) async {
  tester.view.physicalSize = const Size(420, 1600);
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
        trainerSlotsProvider(
          _trainer.id,
        ).overrideWith((ref) async => const <TrainerSlot>[]),
        myReservationsProvider.overrideWith(
          (ref) async => const <MyReservation>[],
        ),
        recommendedGymsProvider.overrideWith((ref) async => const <Gym>[]),
        recommendedTrainersProvider.overrideWith(
          (ref) async => const <Trainer>[],
        ),
        gymFinderResultsProvider.overrideWith((ref) async => const <Gym>[]),
        consultationRequestControllerProvider.overrideWith(
          (ref) => newTestConsultationController(),
        ),
        memberCoachProvider.overrideWith((ref) async => _coach),
        coachUnreadProvider.overrideWith((ref) async => unread),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: GymTab(selectedSlot: null, onSlot: _noop),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop(String _) {}

/// 배지 = 빨간 원. 버튼 안에서 그 색으로 칠해진 상자를 찾는다.
Size _badgeSize(WidgetTester tester) {
  final Finder badge = find
      .descendant(
        of: find.byKey(const Key('gymTrainerChatButton')),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == OnCareColors.danger,
        ),
      )
      .first;
  return tester.getSize(badge);
}

void main() {
  testWidgets('한 자리 수 배지는 정원이다', (WidgetTester tester) async {
    await _pump(tester, 1);
    final Size size = _badgeSize(tester);
    expect(size.width, size.height);
  });

  testWidgets('99+ 도 같은 원 안에 들어간다', (WidgetTester tester) async {
    await _pump(tester, 120);
    final Size size = _badgeSize(tester);
    expect(size.width, size.height);
    expect(find.text('99+'), findsOneWidget);
  });
}
