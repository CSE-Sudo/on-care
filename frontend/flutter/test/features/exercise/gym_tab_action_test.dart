import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../support/consultation_test_support.dart';

const Gym _gym = Gym(
  id: 'gym-action-test',
  name: '액션 테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.5,
  rating: 4.9,
  tags: <String>['PT'],
);

const Trainer _trainer = Trainer(
  id: 'trainer-action-test',
  gymId: 'gym-action-test',
  name: '김액션',
  role: '전담 트레이너',
);

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-action-test',
  name: '김액션',
  specialty: '전담 트레이너',
  career: '5년',
  intro: '건강한 운동을 돕습니다.',
  gymName: '액션 테스트 헬스장',
  goal: '체력 강화',
);

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

ConsultationRequest _consultation(
  ConsultationStatus status, {
  String? decisionNote,
}) {
  return ConsultationRequest(
    id: 'consultation-${status.name}',

    trainerId: _trainer.id,
    trainerName: _trainer.name,
    trainerRole: _trainer.role,
    exerciseGoal: ExerciseGoal.weightLoss,
    healthPurposeType: HealthPurposeType.chronic,
    healthPurposeDetail: null,
    preferredDate: DateTime(2026, 8),
    preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 14, minute: 0)),
    message: null,
    status: status,
    createdAt: DateTime(2026, 7, 31),
    decisionNote: decisionNote,
    decidedAt: status == ConsultationStatus.pending
        ? null
        : DateTime(2026, 8, 2),
  );
}

void main() {
  late GoRouter router;
  late ConsultationRequestController consultationController;

  Future<void> pumpGymTab(
    WidgetTester tester, {
    ConsultationRequest? consultation,
    List<ConsultationRequest> additionalConsultations =
        const <ConsultationRequest>[],
    bool hasMyGym = true,
    Trainer? trainer = _trainer,
    MemberCoach? coach,
    int unread = 0,
    List<MyReservation> reservations = const <MyReservation>[],
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    consultationController = newTestConsultationController();
    if (consultation != null) {
      await seedPending(consultationController, consultation);
    }
    for (final ConsultationRequest request in additionalConsultations) {
      await seedPending(consultationController, request);
    }
    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.exerciseGym);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          myGymProvider.overrideWith((ref) async => hasMyGym ? _gym : null),
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          // 헬스장 상세·찾기는 제휴 + 카카오를 합친 provider 를 본다(#329).
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          myTrainerProvider.overrideWith((ref) async => trainer),
          // 트레이너 채팅 화면이 데모 안내 배너 노출을 이 설정으로 가른다.
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: Environment.dev,
              apiBaseUrl: 'http://localhost',
              useMockApi: true,
            ),
          ),
          trainerProvider(_trainer.id).overrideWith((ref) async => _trainer),
          gymTrainersProvider(
            _gym.id,
          ).overrideWith((ref) async => const <Trainer>[_trainer]),
          recommendedTrainersProvider.overrideWith(
            (ref) async => const <Trainer>[_trainer],
          ),
          consultationRequestControllerProvider.overrideWith(
            (ref) => consultationController,
          ),
          memberCoachRepositoryProvider.overrideWithValue(
            MockMemberCoachRepository(),
          ),
          memberCoachProvider.overrideWith((ref) async => coach),
          coachUnreadProvider.overrideWith((ref) => Stream<int>.value(unread)),
          myReservationsProvider.overrideWith((ref) async => reservations),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder myGymCard() => find.byKey(const Key('my-gym-info-card'));

  Finder reservationPanel() => find.byWidgetPredicate(
    (Widget widget) => widget.runtimeType.toString() == '_ReservationPanel',
  );

  Future<void> scrollToCard(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      myGymCard(),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('예약 패널은 다가오는 자리를 위에, 지난 예약을 아래에 둔다', (WidgetTester tester) async {
    // 서버는 늦은 예약부터 준다(#980) — 쪽을 나누려면 그 순서여야 한다. 그대로
    // 그리면 다음 주 자리가 내일 자리보다 위에 오고, 지난 예약이 그 사이에 섞인다.
    await pumpGymTab(
      tester,
      reservations: <MyReservation>[
        MyReservation(
          id: 'far',
          slotId: 'slot-far',
          trainerId: _trainer.id,
          startsAt: DateTime(2026, 9, 30, 10),
          cancellable: true,
        ),
        MyReservation(
          id: 'past',
          slotId: 'slot-past',
          trainerId: _trainer.id,
          startsAt: DateTime(2026, 8, 1, 10),
          cancellable: false,
        ),
        MyReservation(
          id: 'soon',
          slotId: 'slot-soon',
          trainerId: _trainer.id,
          startsAt: DateTime(2026, 9, 1, 10),
          cancellable: true,
        ),
      ],
    );
    await tester.scrollUntilVisible(
      reservationPanel(),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    double y(Finder finder) => tester.getTopLeft(finder).dy;

    expect(
      y(find.byKey(const ValueKey<String>('cancel-reservation-soon'))),
      lessThan(y(find.byKey(const ValueKey<String>('cancel-reservation-far')))),
    );
    // 지난 예약은 취소 버튼 대신 그 사실이 적히고, 예정된 자리 아래로 밀린다.
    expect(
      y(find.byKey(const ValueKey<String>('cancel-reservation-far'))),
      lessThan(y(find.text(l.exReservationPast))),
    );
  });

  testWidgets('legacy footer actions and their trailing space are removed', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester);
    await scrollToCard(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l.exGymInfo), findsNothing);
    expect(find.text(l.exConsultButton), findsNothing);
    expect(find.text(l.exViewConsultationRequest), findsNothing);
    expect(find.text(l.exMyGymSection), findsOneWidget);
    // 담당 트레이너 이름은 이제 카드 안에 한 줄로 있다 (#1187) — 예전에는
    // 예약 패널 머리에서만 스쳐 지나갔다.
    expect(
      find.descendant(of: myGymCard(), matching: find.text(_trainer.name)),
      findsWidgets,
    );

    expect(find.text(l.exTrainerAvailability(_trainer.name)), findsOneWidget);
    expect(
      tester.getTopLeft(reservationPanel()).dy,
      greaterThan(tester.getBottomLeft(myGymCard()).dy),
    );
  });

  testWidgets('연결된 헬스장이 없으면 찾기 화면이 그 자리에 있다 (#1133)', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester, hasMyGym: false);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    // 찾기 버튼을 눌러 시트를 여는 단계가 없다 — 화면이 곧 찾기다.
    expect(find.text(l.exFindGym), findsNothing);
    expect(find.text(l.exNearbyGyms), findsOneWidget);
    // '건강 요약 전달' 은 보내는 곳 없이 성공 스낵바만 띄웠다 — 실제로 동작하는
    // 다음 걸음(헬스장 상세 → 상담 신청)으로 바꿨다(#787).
    expect(find.textContaining('건강 요약'), findsNothing);
    expect(find.text('트레이너 채팅'), findsNothing);
  });

  testWidgets('connected gym does not duplicate the consultation action', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(
      tester,
      consultation: _consultation(ConsultationStatus.pending),
      coach: _coach,
    );
    await scrollToCard(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l.exViewConsultationRequest), findsNothing);
    expect(find.text(l.exGymInfo), findsNothing);
    expect(find.text(l.exConsultButton), findsNothing);
    expect(find.byKey(const Key('gymTrainerChatButton')), findsNothing);

    expect(find.text(l.exConsultPendingStatus), findsNothing);
  });

  testWidgets('connected trainer shows chat without a zero badge', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester, coach: _coach);
    await scrollToCard(tester);

    final Finder chatButton = find.byKey(const Key('gymTrainerChatButton'));
    expect(chatButton, findsOneWidget);
    expect(
      find.descendant(of: chatButton, matching: find.text('0')),
      findsNothing,
    );

    await tester.tap(chatButton);
    await tester.pumpAndSettle();

    expect(find.byType(TrainerChatPage), findsOneWidget);
    expect(find.text(_coach.name), findsOneWidget);
  });

  testWidgets('연결 헬스장이 없으면 탭 안에 채팅 버튼을 두지 않는다 (#1132)', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester, hasMyGym: false, coach: _coach);

    // 이 상태에서 할 일은 헬스장을 찾는 것이다. 담당 트레이너와의 채팅은
    // 모든 탭 헤더에 있는 채팅 버튼이 맡는다.
    expect(find.byKey(const Key('gymTrainerChatButton')), findsNothing);
  });

  testWidgets('pending consultation uses only the finder history shortcut', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(
      tester,
      hasMyGym: false,
      consultation: _consultation(ConsultationStatus.pending),
      coach: _coach,
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l.exViewConsultationRequest), findsNothing);
    expect(find.byKey(const Key('consult-history-shortcut')), findsOneWidget);
    expect(find.byKey(const Key('gymTrainerChatButton')), findsNothing);
  });

  testWidgets('pending consultation does not add a connected-gym summary', (
    WidgetTester tester,
  ) async {
    final ConsultationRequest recentAcceptedRequest = ConsultationRequest(
      id: 'consultation-recent-accepted',

      trainerId: 'another-trainer',
      trainerName: '박최근',
      trainerRole: '전담 트레이너',
      exerciseGoal: ExerciseGoal.weightLoss,
      healthPurposeType: HealthPurposeType.chronic,
      healthPurposeDetail: null,
      preferredDate: DateTime(2026, 8),
      preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 14, minute: 0)),
      message: null,
      status: ConsultationStatus.accepted,
      createdAt: DateTime(2026, 8),
    );
    await pumpGymTab(
      tester,
      consultation: _consultation(ConsultationStatus.pending),
      additionalConsultations: <ConsultationRequest>[recentAcceptedRequest],
      coach: _coach,
    );
    await scrollToCard(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l.exViewConsultationRequest), findsNothing);
    expect(find.byKey(const Key('gymTrainerChatButton')), findsNothing);
    expect(find.text(l.exConsultPendingStatus), findsNothing);
    expect(find.text('박최근'), findsNothing);
  });

  testWidgets('트레이너와 채팅 버튼은 헤더 채팅 아이콘과 같은 브랜드 색을 쓴다 (#1849)', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester, coach: _coach);
    await scrollToCard(tester);

    final AppButton chat = tester.widget<AppButton>(
      find.byKey(const Key('gymTrainerChatButton')),
    );
    // 헤더 아이콘은 `context.oncare.brand.primary` 로 그려진다 — 같은 대화로
    // 들어가는 버튼이니 브랜드 채움이어야 한다. 색 값은 적지 않는다.
    expect(chat.variant, AppButtonVariant.primary);
  });

  testWidgets('읽지 않은 메시지가 있어도 채팅 버튼에 배지가 없다', (WidgetTester tester) async {
    await pumpGymTab(tester, coach: _coach, unread: 7);
    await scrollToCard(tester);

    final Finder chatButton = find.byKey(const Key('gymTrainerChatButton'));
    expect(chatButton, findsOneWidget);
    // 같은 숫자를 헤더의 채팅 아이콘이 이미 말한다 — 버튼에는 달지 않는다.
    expect(
      find.descendant(of: chatButton, matching: find.text('7')),
      findsNothing,
    );
  });

  testWidgets('member without an active trainer has no chat action', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester);
    await scrollToCard(tester);

    expect(find.byKey(const Key('gymTrainerChatButton')), findsNothing);
  });

  for (final ConsultationStatus status in <ConsultationStatus>[
    ConsultationStatus.accepted,
    ConsultationStatus.rejected,
  ]) {
    testWidgets('${status.name} consultation does not show an action', (
      WidgetTester tester,
    ) async {
      await pumpGymTab(tester, consultation: _consultation(status));
      await scrollToCard(tester);

      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(find.text(l.exViewConsultationRequest), findsNothing);
    });
  }

  testWidgets('연결 화면에는 지난 상담 결과 요약을 다시 노출하지 않는다', (WidgetTester tester) async {
    await pumpGymTab(
      tester,
      consultation: _consultation(
        ConsultationStatus.rejected,
        decisionNote: '이번 달은 정원이 찼어요',
      ),
    );
    await scrollToCard(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text('이번 달은 정원이 찼어요'), findsNothing);
    expect(find.text(l.exConsultRejectedReasonLabel), findsNothing);
  });

  testWidgets('대기 중인 요청에는 결과 안내가 붙지 않는다', (WidgetTester tester) async {
    await pumpGymTab(
      tester,
      consultation: _consultation(ConsultationStatus.pending),
    );
    await scrollToCard(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l.exConsultAcceptedGuide), findsNothing);
    expect(find.text(l.exConsultRejectedNoReason), findsNothing);
  });

  testWidgets('my gym information keeps its detail route', (
    WidgetTester tester,
  ) async {
    await pumpGymTab(tester);
    await scrollToCard(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(
      find.descendant(of: myGymCard(), matching: find.text(_gym.name)),
    );
    await tester.pumpAndSettle();
    expect(find.text(l.exGymDetailTitle), findsOneWidget);
  });

  testWidgets('담당 트레이너가 없으면 예약 패널을 감춘다', (WidgetTester tester) async {
    await pumpGymTab(tester, trainer: null);
    await scrollToCard(tester);

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    // 헬스장 카드는 남지만, 없는 트레이너의 빈 시간·예약 버튼은 사라진다.
    expect(myGymCard(), findsOneWidget);
    expect(reservationPanel(), findsNothing);
    expect(find.text(l.exTrainerAvailability(_trainer.name)), findsNothing);
    // 연결 화면에서 추천 트레이너 레일도 함께 제거된다.
    expect(
      find.descendant(of: myGymCard(), matching: find.text(_trainer.name)),
      findsNothing,
    );
    expect(find.text(_trainer.name), findsNothing);
  });
}
