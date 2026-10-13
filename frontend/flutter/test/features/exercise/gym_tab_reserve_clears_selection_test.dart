/// 예약이 잡히면 고른 자리를 비운다 — 내 예약을 다시 받는 동안 확정 버튼이
/// 다시 켜져 두 번째 자리를 잡을 수 있었다. 그 틈에 서버가 "다가오는 예약 있음"
/// 409 로 막으면 일반 실패가 아니라 먼저 취소하라고 알린다. (#3240)
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/data/repositories/dio_gym_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_tab.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';

import '../../support/consultation_test_support.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();

/// `POST /reservations` 에 정해 둔 상태·본문으로 답하는 어댑터.
class _ReserveAdapter implements HttpClientAdapter {
  _ReserveAdapter(this.status, this.body);

  final int status;
  final Object? body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

DioGymRepository _dioRepo(int status, Object? body) => DioGymRepository(
  Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..httpClientAdapter = _ReserveAdapter(status, body),
);

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

final TrainerSlot _open = TrainerSlot(
  id: 'slot-open',
  trainerId: _trainer.id,
  startsAt: DateTime(2026, 9, 1, 10),
  booked: false,
  sessionType: '1:1 PT',
);

/// 예약을 정해 둔 대로 받거나 막는 저장소.
class _ReserveRepository extends MockGymRepository {
  _ReserveRepository({this.error});

  final Object? error;
  int reserveCalls = 0;

  @override
  Future<void> reserve(String slotId) async {
    reserveCalls += 1;
    if (error != null) throw error!;
  }
}

/// 운동 탭처럼 고른 자리를 들고 있는 부모. `onSlot` 은 토글, `onReserved` 는 비우기다.
class _Host extends StatefulWidget {
  const _Host({required this.onReservedCalled});

  final VoidCallback onReservedCalled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? _selected = _open.id;

  @override
  Widget build(BuildContext context) => GymTab(
    selectedSlot: _selected,
    onSlot: (String s) => setState(() => _selected = _selected == s ? null : s),
    onReserved: () {
      widget.onReservedCalled();
      setState(() => _selected = null);
    },
  );
}

void main() {
  group('DioGymRepository.reserve', () {
    test('409 upcoming_reservation → UpcomingReservationError', () async {
      await expectLater(
        _dioRepo(409, <String, Object?>{
          'detail': <String, Object?>{
            'code': 'upcoming_reservation',
            'message': '이미 다가오는 예약이 있습니다.',
          },
        }).reserve('slot-1'),
        throwsA(
          isA<UpcomingReservationError>().having(
            (e) => e.slotId,
            'slotId',
            'slot-1',
          ),
        ),
      );
    });

    test('문자열 detail 의 409 는 지금처럼 마감(StateError)', () async {
      await expectLater(
        _dioRepo(409, <String, Object?>{
          'detail': '이미 예약한 슬롯입니다.',
        }).reserve('slot-1'),
        throwsA(
          allOf(isA<StateError>(), isNot(isA<UpcomingReservationError>())),
        ),
      );
    });
  });

  Future<int Function()> pumpTab(
    WidgetTester tester, {
    required GymRepository repository,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var reservedCalls = 0;

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
          myGymProvider.overrideWith((ref) async => _gym),
          myTrainerProvider.overrideWith((ref) async => _trainer),
          nearbyGymsProvider.overrideWith((ref) async => const <Gym>[_gym]),
          gymFinderResultsProvider.overrideWith(
            (ref) async => const <Gym>[_gym],
          ),
          trainerSlotsProvider(
            _trainer.id,
          ).overrideWith((ref) async => <TrainerSlot>[_open]),
          myReservationsProvider.overrideWith(
            (ref) async => const <MyReservation>[],
          ),
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
              child: _Host(onReservedCalled: () => reservedCalls += 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => reservedCalls;
  }

  final Finder confirm = find.byKey(const ValueKey<String>('reserve-confirm'));

  Future<void> tapReserve(WidgetTester tester) async {
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump();
  }

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('예약이 잡히면 고른 자리를 비워 확정 버튼이 다시 켜지지 않는다', (
    WidgetTester tester,
  ) async {
    final repo = _ReserveRepository();
    final reservedCalls = await pumpTab(tester, repository: repo);
    expect(confirm, findsOneWidget);

    await tapReserve(tester);
    await tester.pumpAndSettle();

    expect(repo.reserveCalls, 1);
    expect(reservedCalls(), 1);
    expect(confirm, findsNothing);
    await drainToast(tester);
  });

  testWidgets('예약이 실패하면 고른 자리를 그대로 두어 다시 시도할 수 있다', (
    WidgetTester tester,
  ) async {
    final repo = _ReserveRepository(
      error: StateError('slot no longer bookable: slot-open'),
    );
    final reservedCalls = await pumpTab(tester, repository: repo);

    await tapReserve(tester);
    await tester.pumpAndSettle();

    expect(repo.reserveCalls, 1);
    expect(reservedCalls(), 0);
    expect(confirm, findsOneWidget);
    await drainToast(tester);
  });

  testWidgets('다가오는 예약이 있다는 409 면 먼저 취소하라고 알린다', (WidgetTester tester) async {
    final repo = _ReserveRepository(
      error: const UpcomingReservationError('slot-open'),
    );
    final reservedCalls = await pumpTab(tester, repository: repo);

    await tapReserve(tester);

    expect(repo.reserveCalls, 1);
    expect(find.text(_ko.exReserveUpcomingExists), findsOneWidget);
    expect(find.text(_ko.exReserveFailed), findsNothing);
    // 예약이 잡힌 것이 아니므로 선택 해제 콜백은 부르지 않는다.
    expect(reservedCalls(), 0);
    await drainToast(tester);
  });
}
