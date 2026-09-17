/// 헬스장 탭 `트레이너와 채팅` 버튼에는 읽지 않음 배지가 없다.
///
/// 같은 숫자를 헤더의 채팅 아이콘이 이미 말한다. 그쪽은 어느 탭에 있든 보이는
/// 자리라 알림의 몫을 거기서 하고, 이 버튼은 같은 대화로 들어가는 두 번째
/// 입구일 뿐이다 — 배지를 함께 달면 한 화면이 같은 말을 두 번 한다.
///
/// 예전에는 여기에도 배지가 있었고 그 원형을 재는 테스트였다 (#1138).
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
        coachUnreadProvider.overrideWith((ref) => Stream<int>.value(unread)),
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

/// 버튼 안에 경고색으로 칠해진 상자(=배지)가 있는가.
Finder _badge() => find.descendant(
  of: find.byKey(const Key('gymTrainerChatButton')),
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration! as BoxDecoration).color == OnCareColors.danger,
  ),
);

void main() {
  for (final int unread in <int>[1, 7, 120]) {
    testWidgets('읽지 않은 메시지가 $unread 건이어도 배지를 그리지 않는다', (
      WidgetTester tester,
    ) async {
      await _pump(tester, unread);

      expect(find.byKey(const Key('gymTrainerChatButton')), findsOneWidget);
      expect(_badge(), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('gymTrainerChatButton')),
          matching: find.text('$unread'),
        ),
        findsNothing,
      );
    });
  }

  testWidgets('99 를 넘겨도 `99+` 가 붙지 않는다', (WidgetTester tester) async {
    await _pump(tester, 120);
    expect(find.text('99+'), findsNothing);
  });
}
