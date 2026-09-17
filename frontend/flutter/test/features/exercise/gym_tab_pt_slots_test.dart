/// 헬스장 탭의 1:1 PT 예약 표기. (#1072)
///
/// 트레이너는 1:1 PT 만 진행한다 — 자리는 비었거나 예약된 둘 중 하나이고,
/// 다음 일정이 잡혀 있으면 빈 자리를 더 고를 이유가 없다. 헬스장이 없는 회원은
/// 이 탭에서 할 일이 헬스장 찾기뿐이라 지도가 맨 앞에 온다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_tab.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../support/consultation_test_support.dart';

const Gym _gym = Gym(
  id: 'gym-pt',
  name: '1:1 테스트 헬스장',
  address: '서울시 테스트구',
  distanceKm: 0.4,
  rating: 4.8,
  tags: <String>['PT'],
  lat: 37.5559,
  lng: 126.9368,
);

const Trainer _trainer = Trainer(
  id: 'trainer-pt',
  gymId: 'gym-pt',
  name: '김트레이너',
  role: '전담 트레이너',
);

final DateTime _openAt = DateTime(2026, 9, 1, 10);
final DateTime _bookedAt = DateTime(2026, 9, 2, 10);
final DateTime _consultAt = DateTime(2026, 9, 3, 10);
final DateTime _groupAt = DateTime(2026, 9, 4, 10);

List<TrainerSlot> get _slots => <TrainerSlot>[
  TrainerSlot(
    id: 'slot-open',
    trainerId: _trainer.id,
    startsAt: _openAt,
    booked: false,
    sessionType: '1:1 PT',
  ),
  TrainerSlot(
    id: 'slot-booked',
    trainerId: _trainer.id,
    startsAt: _bookedAt,
    booked: true,
    sessionType: '1:1 PT',
  ),
  TrainerSlot(
    id: 'slot-consultation',
    trainerId: _trainer.id,
    startsAt: _consultAt,
    booked: false,
    sessionType: '상담',
  ),
  // 계약에 없던 종류가 섞여 오는 경우. 화면은 상담을 빼는 것이 아니라 1:1 PT 만
  // 남기므로 이 자리도 나오지 않는다 (#1849).
  TrainerSlot(
    id: 'slot-group',
    trainerId: _trainer.id,
    startsAt: _groupAt,
    booked: false,
    sessionType: '그룹',
  ),
];

void main() {
  Future<AppLocalizations> pumpTab(
    WidgetTester tester, {
    bool hasMyGym = true,
    List<MyReservation> reservations = const <MyReservation>[],
    String? selectedSlot,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
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
          myGymProvider.overrideWith((ref) async => hasMyGym ? _gym : null),
          myTrainerProvider.overrideWith((ref) async => _trainer),
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          recommendedTrainersProvider.overrideWith(
            (ref) async => const <Trainer>[],
          ),
          trainerSlotsProvider(_trainer.id).overrideWith((ref) async => _slots),
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
              child: GymTab(selectedSlot: selectedSlot, onSlot: (String _) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  }

  testWidgets('슬롯은 시간 범위를 표시하고 마감 문구 없이 두 열로 배치된다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await pumpTab(tester);

    expect(find.textContaining('잔여'), findsNothing);
    expect(find.text(l.exSlotFull), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('slot-chip-slot-open')),
        matching: find.byType(Text),
      ),
      findsOneWidget,
      reason: '고르기 칩은 한 줄 라벨이다(#1701)',
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('slot-chip-slot-open'))),
      tester.getSize(
        find.byKey(const ValueKey<String>('slot-chip-slot-booked')),
      ),
      reason: '비활성 색상 외에는 같은 슬롯 크기를 쓴다',
    );
    // 종류는 칩마다 적지 않고 예약 상자 제목 줄에 한 번 적는다(#1701).
    expect(
      find.descendant(
        of: find.byKey(const Key('my-gym-reservation-panel')),
        matching: find.text(l.exSlotTypePersonalTraining),
      ),
      findsOneWidget,
    );
    final Rect open = tester.getRect(
      find.byKey(const ValueKey<String>('slot-chip-slot-open')),
    );
    final Rect booked = tester.getRect(
      find.byKey(const ValueKey<String>('slot-chip-slot-booked')),
    );
    expect(open.top, booked.top);
    expect(open.width, closeTo(booked.width, 0.1));
  });

  testWidgets('빈 예약 시간 제목은 트레이너 이름을 그대로 쓴다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(tester);

    expect(find.text(l.exTrainerAvailability(_trainer.name)), findsOneWidget);
    expect(find.text('김트레이너 빈 예약 시간'), findsOneWidget);
    // AI 표식 대신 예약 성격에 맞는 아이콘이 붙는다.
    expect(find.byIcon(AppIcons.eventAvailable), findsOneWidget);
  });

  testWidgets('연결된 헬스장은 정보 다음에 예약 상자만 배치한다 (#1287)', (
    WidgetTester tester,
  ) async {
    await pumpTab(tester);

    final Finder infoCard = find.byKey(const Key('my-gym-info-card'));
    final Finder reservationPanel = find.byKey(
      const Key('my-gym-reservation-panel'),
    );
    expect(infoCard, findsOneWidget);
    expect(reservationPanel, findsOneWidget);
    expect(
      tester.getTopLeft(reservationPanel).dy,
      greaterThan(tester.getBottomLeft(infoCard).dy),
    );
    expect(find.text('추천 헬스장'), findsNothing);
    expect(find.text('추천 트레이너'), findsNothing);
  });

  testWidgets('다음 일정이 있으면 빈 예약 시간 영역을 감춘다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(
      tester,
      reservations: <MyReservation>[
        MyReservation(
          id: 'res-next',
          slotId: 'slot-open',
          trainerId: _trainer.id,
          startsAt: _openAt,
          cancellable: true,
        ),
      ],
    );

    // 내 예약은 남고, 자리를 더 고르는 영역만 사라진다.
    expect(find.text(l.exMyReservations), findsOneWidget);
    expect(find.text(l.exTrainerAvailability(_trainer.name)), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('slot-chip-slot-open')),
      findsNothing,
    );
  });

  testWidgets('지난 예약만 있으면 빈 예약 시간을 다시 보여준다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(
      tester,
      reservations: <MyReservation>[
        MyReservation(
          id: 'res-past',
          slotId: 'slot-old',
          trainerId: _trainer.id,
          startsAt: DateTime(2026, 8, 1, 10),
          cancellable: false,
        ),
      ],
    );

    expect(find.text(l.exTrainerAvailability(_trainer.name)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('slot-chip-slot-open')),
      findsOneWidget,
    );
  });

  testWidgets('연결된 헬스장이 없으면 헬스장 찾기 화면이 그대로 뜬다 (#1133)', (
    WidgetTester tester,
  ) async {
    await pumpTab(tester, hasMyGym: false);

    // 지도만 든 빈 카드와 `헬스장 찾기` 버튼 대신 찾기 화면 자체가 온다.
    expect(find.byType(GymFinderView), findsOneWidget);
    expect(find.text('헬스장 찾기'), findsNothing);
    // 추천 헬스장·추천 트레이너 섹션도 이 상태에서는 없다.
    expect(find.text('추천 헬스장'), findsNothing);
    expect(find.text('추천 트레이너'), findsNothing);
    // 트레이너와 채팅 버튼도 없다 (#1132) — 헤더의 채팅 버튼이 그 자리를 맡는다.
    expect(find.text('트레이너와 채팅'), findsNothing);
  });

  testWidgets('연결된 헬스장에서는 상담 자리를 내주지 않는다 (#1136)', (WidgetTester tester) async {
    final AppLocalizations l = await pumpTab(tester);

    // 이미 연결된 헬스장이라 상담은 지난 걸음이다 — 1:1 PT 자리만 남는다.
    expect(
      find.byKey(const ValueKey<String>('slot-chip-slot-consultation')),
      findsNothing,
    );
    expect(find.text(l.exSlotTypeConsultation), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('slot-chip-slot-open')),
      findsOneWidget,
    );
  });

  testWidgets('예약 확정 버튼은 자리 칩과 채팅 버튼 사이에서 혼자 커지지 않는다', (
    WidgetTester tester,
  ) async {
    await pumpTab(tester, selectedSlot: 'slot-open');

    final AppButton confirm = tester.widget<AppButton>(
      find.byKey(const ValueKey<String>('reserve-confirm')),
    );
    // 같은 탭의 `트레이너와 채팅`(기본 medium)과 같은 높이다. large(52)는 36짜리
    // 자리 칩들 사이에서 혼자 크게 섰다.
    expect(confirm.size, OnCareButtonSize.medium);
  });

  testWidgets('1:1 PT 가 아닌 자리는 종류가 무엇이든 내주지 않는다 (#1849)', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await pumpTab(tester);

    // 제목 줄이 종류를 `1:1 PT` 로 못 박으므로, 상담 말고 다른 종류가 섞여 와도
    // 칩으로 나와서는 안 된다.
    expect(
      find.byKey(const ValueKey<String>('slot-chip-slot-group')),
      findsNothing,
    );
    expect(find.text('그룹'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('my-gym-reservation-panel')),
        matching: find.text(l.exSlotTypePersonalTraining),
      ),
      findsOneWidget,
    );
  });
}
