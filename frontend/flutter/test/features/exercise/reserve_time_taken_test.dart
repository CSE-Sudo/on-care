/// 트레이너의 다른 일정과 겹친 예약 — 서버 409 `schedule_overlap` 을 마감과
/// 구분해 알아보고, 회원에게 재시도 대신 다른 시간을 고르라고 알린다. (#2284)
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
import 'package:oncare/gen/l10n/app_localizations_en.dart';
import 'package:oncare/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../support/consultation_test_support.dart';

final AppLocalizationsKo _ko = AppLocalizationsKo();
final AppLocalizationsEn _en = AppLocalizationsEn();

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

DioGymRepository _repo(int status, Object? body) => DioGymRepository(
  Dio(BaseOptions(baseUrl: 'http://localhost'))
    ..httpClientAdapter = _ReserveAdapter(status, body),
);

/// 서버 예약 경로가 겹침으로 막을 때의 실제 본문 — 다른 회원의 일정은 싣지
/// 않는다.
const Map<String, Object?> _overlapBody = <String, Object?>{
  'detail': <String, Object?>{
    'code': 'schedule_overlap',
    'message': '이 시간은 트레이너의 다른 일정과 겹쳐 예약할 수 없어요.',
  },
};

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

/// 예약만 정해 둔 오류로 막는 저장소.
class _FailingReserveRepository extends MockGymRepository {
  _FailingReserveRepository(this.error);

  final Object error;
  int reserveCalls = 0;

  @override
  Future<void> reserve(String slotId) async {
    reserveCalls += 1;
    throw error;
  }
}

void main() {
  group('DioGymRepository.reserve', () {
    test('409 schedule_overlap → SlotTimeTakenError', () async {
      await expectLater(
        _repo(409, _overlapBody).reserve('slot-1'),
        throwsA(
          isA<SlotTimeTakenError>().having((e) => e.slotId, 'slotId', 'slot-1'),
        ),
      );
    });

    test('자리가 찬 409 는 지금처럼 StateError(마감)', () async {
      await expectLater(
        _repo(409, <String, Object?>{
          'detail': '이미 예약이 찬 자리입니다.',
        }).reserve('slot-1'),
        throwsA(allOf(isA<StateError>(), isNot(isA<SlotTimeTakenError>()))),
      );
    });

    test('다른 코드의 409 도 마감으로 남는다', () async {
      await expectLater(
        _repo(409, <String, Object?>{
          'detail': <String, Object?>{'code': 'slot_full'},
        }).reserve('slot-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('410·404 는 겹침이 아니다', () async {
      await expectLater(
        _repo(410, _overlapBody).reserve('slot-1'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        _repo(404, _overlapBody).reserve('slot-1'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('헬스장 탭 예약', () {
    Future<int Function()> pumpTab(
      WidgetTester tester, {
      required GymRepository repository,
      Locale locale = const Locale('ko'),
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var slotLoads = 0;

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
            trainerSlotsProvider(_trainer.id).overrideWith((ref) async {
              slotLoads += 1;
              return <TrainerSlot>[_open];
            }),
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
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: GymTab(selectedSlot: _open.id, onSlot: (String _) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return () => slotLoads;
    }

    Future<void> tapReserve(WidgetTester tester) async {
      final Finder button = find.byKey(
        const ValueKey<String>('reserve-confirm'),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
    }

    Future<void> drainToast(WidgetTester tester) async {
      await tester.pump(OnCareMotion.toastErrorVisible);
      await tester.pumpAndSettle();
    }

    testWidgets('겹침이면 다른 시간을 고르라고 알리고 자리 목록을 새로 읽는다', (
      WidgetTester tester,
    ) async {
      final repo = _FailingReserveRepository(
        const SlotTimeTakenError('slot-open'),
      );
      final slotLoads = await pumpTab(tester, repository: repo);
      final before = slotLoads();

      await tapReserve(tester);

      expect(repo.reserveCalls, 1);
      expect(find.text(_ko.exReserveTimeTaken), findsOneWidget);
      expect(find.text(_ko.exReserveFailed), findsNothing);
      await tester.pumpAndSettle();
      expect(slotLoads(), greaterThan(before));
      // 버튼이 다시 풀려 다른 시간을 고를 수 있다.
      final AppButton button = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('reserve-confirm')),
      );
      expect(button.onPressed, isNotNull);
      await drainToast(tester);
    });

    testWidgets('English: the overlap notice reads in English', (
      WidgetTester tester,
    ) async {
      await pumpTab(
        tester,
        repository: _FailingReserveRepository(
          const SlotTimeTakenError('slot-open'),
        ),
        locale: const Locale('en'),
      );

      await tapReserve(tester);

      expect(find.text(_en.exReserveTimeTaken), findsOneWidget);
      expect(find.text(_en.exReserveFailed), findsNothing);
      await drainToast(tester);
    });

    testWidgets('겹침이 아닌 실패는 지금처럼 다시 시도하라고 한다', (WidgetTester tester) async {
      await pumpTab(
        tester,
        repository: _FailingReserveRepository(
          StateError('slot no longer bookable: slot-open'),
        ),
      );

      await tapReserve(tester);

      expect(find.text(_ko.exReserveFailed), findsOneWidget);
      expect(find.text(_ko.exReserveTimeTaken), findsNothing);
      await drainToast(tester);
    });
  });
}
