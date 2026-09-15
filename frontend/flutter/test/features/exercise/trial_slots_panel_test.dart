/// 트레이너 상세의 포인트 체험 예약 상자. (#1790)
///
/// 담당 트레이너가 없는 회원에게만 체험 자리가 `포인트 체험` 으로 보이고, 파란 2열
/// 확인창을 거쳐 예약한다. 막힌 이유(이미 이용·포인트 부족)는 버튼을 막고 알린다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/trial_slots_panel.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const Trainer _trainer = Trainer(
  id: 'trainer-trial',
  gymId: 'gym-trial',
  name: '체험트레이너',
  role: '퍼스널 트레이너',
);

const Trainer _otherTrainer = Trainer(
  id: 'trainer-mine',
  gymId: 'gym-trial',
  name: '담당트레이너',
);

final DateTime _trialAt = DateTime(2026, 9, 20, 10);

TrainerSlot _trialSlot({String? blocked}) => TrainerSlot(
  id: 'slot-trial',
  trainerId: _trainer.id,
  startsAt: _trialAt,
  booked: false,
  sessionType: kPointsTrialSessionType,
  durationMinutes: kPointsTrialMinutes,
  pointsCost: kPointsTrialCost,
  trialBlockedReason: blocked,
);

final TrainerSlot _ptSlot = TrainerSlot(
  id: 'slot-pt',
  trainerId: _trainer.id,
  startsAt: DateTime(2026, 9, 21, 10),
  booked: false,
  sessionType: '1:1 PT',
);

/// 예약·취소 호출만 기록하는 저장소.
class _RecordingGymRepository extends MockGymRepository {
  final List<String> reserved = <String>[];
  final List<String> cancelled = <String>[];

  @override
  Future<void> reserve(String slotId) async => reserved.add(slotId);

  @override
  Future<void> cancelReservation(String reservationId) async =>
      cancelled.add(reservationId);
}

void main() {
  Future<AppLocalizations> pumpPanel(
    WidgetTester tester, {
    required _RecordingGymRepository repository,
    Trainer? myTrainer,
    List<TrainerSlot>? slots,
    List<MyReservation> reservations = const <MyReservation>[],
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
          gymRepositoryProvider.overrideWithValue(repository),
          myTrainerProvider.overrideWith((ref) async => myTrainer),
          trainerSlotsProvider(_trainer.id).overrideWith(
            (ref) async => slots ?? <TrainerSlot>[_trialSlot(), _ptSlot],
          ),
          myReservationsProvider.overrideWith((ref) async => reservations),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: TrialSlotsPanel(trainer: _trainer),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
  }

  AppButton bookButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.byKey(const Key('trainer-trial-book')));

  testWidgets('담당이 없으면 체험 자리만 포인트 체험으로 보이고 파란 2열 확인창 뒤 예약한다', (
    WidgetTester tester,
  ) async {
    final _RecordingGymRepository repository = _RecordingGymRepository();
    final AppLocalizations l = await pumpPanel(tester, repository: repository);

    expect(find.byKey(const Key('trainer-trial-panel')), findsOneWidget);
    expect(find.text(l.exTrialTag), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('trial-slot-chip-slot-trial')),
      findsOneWidget,
    );
    // 일반 1:1 PT 자리는 체험 상자에 들어오지 않는다.
    expect(
      find.byKey(const ValueKey<String>('trial-slot-chip-slot-pt')),
      findsNothing,
    );
    expect(find.textContaining('10:00–10:20'), findsOneWidget);
    // 자리를 고르기 전에는 예약 버튼이 막혀 있다.
    expect(bookButton(tester).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('trial-slot-chip-slot-trial')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trainer-trial-book')));
    await tester.pumpAndSettle();

    expect(find.text(l.exTrialConfirmTitle), findsOneWidget);
    final Finder pair = find.byType(AppButtonPair);
    expect(pair, findsOneWidget);
    // 포인트를 쓰는 확인이라 빨간(파괴) 버튼이 아니라 파란 버튼이다.
    expect(tester.widget<AppButtonPair>(pair).destructive, isFalse);
    expect(repository.reserved, isEmpty);

    await tester.tap(
      find.descendant(of: pair, matching: find.text(l.exTrialConfirmAction)),
    );
    await tester.pumpAndSettle();

    expect(repository.reserved, <String>['slot-trial']);
  });

  testWidgets('담당 트레이너가 있으면 체험 상자를 그리지 않는다', (WidgetTester tester) async {
    await pumpPanel(
      tester,
      repository: _RecordingGymRepository(),
      myTrainer: _otherTrainer,
    );

    expect(find.byKey(const Key('trainer-trial-panel')), findsNothing);
  });

  testWidgets('이미 이용한 트레이너면 이유를 알리고 예약을 막는다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpPanel(
      tester,
      repository: _RecordingGymRepository(),
      slots: <TrainerSlot>[_trialSlot(blocked: TrialBlockedReason.trialUsed)],
    );

    expect(find.text(l.exTrialUsed), findsOneWidget);
    expect(bookButton(tester).onPressed, isNull);
  });

  testWidgets('포인트가 모자라면 필요한 포인트를 알린다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpPanel(
      tester,
      repository: _RecordingGymRepository(),
      slots: <TrainerSlot>[
        _trialSlot(blocked: TrialBlockedReason.insufficientPoints),
      ],
    );

    expect(
      find.text(l.exTrialInsufficient(l.myPointsCost(kPointsTrialCost))),
      findsOneWidget,
    );
    expect(bookButton(tester).onPressed, isNull);
  });

  testWidgets('24시간 이내 체험 취소는 포인트를 돌려받지 못한다고 알린다', (WidgetTester tester) async {
    final _RecordingGymRepository repository = _RecordingGymRepository();
    final AppLocalizations l = await pumpPanel(
      tester,
      repository: repository,
      reservations: <MyReservation>[
        MyReservation(
          id: 'res-trial',
          slotId: 'slot-trial',
          trainerId: _trainer.id,
          startsAt: _trialAt,
          cancellable: true,
          sessionType: kPointsTrialSessionType,
          pointsCost: kPointsTrialCost,
        ),
      ],
    );

    expect(find.text(l.exTrialMyBooking), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('cancel-trial-res-trial')),
    );
    await tester.pumpAndSettle();

    final String points = l.myPointsCost(kPointsTrialCost);
    expect(find.text(l.exTrialCancelForfeitBody(points)), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AppButtonPair),
        matching: find.text(l.exCancelReservation),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.cancelled, <String>['res-trial']);
  });

  testWidgets('24시간 전 체험 취소는 포인트 반환을 알린다', (WidgetTester tester) async {
    final AppLocalizations l = await pumpPanel(
      tester,
      repository: _RecordingGymRepository(),
      reservations: <MyReservation>[
        MyReservation(
          id: 'res-trial',
          slotId: 'slot-trial',
          trainerId: _trainer.id,
          startsAt: _trialAt,
          cancellable: true,
          sessionType: kPointsTrialSessionType,
          pointsCost: kPointsTrialCost,
          pointsRefundable: true,
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('cancel-trial-res-trial')),
    );
    await tester.pumpAndSettle();

    final MaterialLocalizations m = MaterialLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final String when = l.exSlotWhen(m.formatMediumDate(_trialAt), '10:00');
    expect(
      find.text(
        l.exTrialCancelRefundBody(when, l.myPointsCost(kPointsTrialCost)),
      ),
      findsOneWidget,
    );
  });
}
