/// 탈퇴 확인창의 "잃는 것" 건수 — 엔티티·읽기·문구. (#3006)
///
/// 실서버는 `GET /users/me/deletion-preview` 하나로 네 숫자를 준다. 데모는 PT
/// 예약·상담 요청을 목 저장소가 들고 있어 그 둘을 저장소에서 다시 센다. 어느
/// 쪽이든 읽기가 실패하면 확인창은 일반 문구로 물러서고 탈퇴는 막지 않는다.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/account/domain/entities/account_deletion_preview.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/my_health/presentation/controllers/withdraw_preview_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';

import '../../helpers/mock_account_repository.dart';

class _Gym extends Fake implements GymRepository {
  _Gym(this.reservations);

  final List<MyReservation> reservations;

  @override
  Future<List<MyReservation>> fetchMyReservations({
    int limit = reservationPageSize,
    DateTime? before,
    String? beforeId,
  }) async => reservations;
}

class _Consultations extends Fake implements ConsultationRepository {
  _Consultations(this.statuses);

  final List<String> statuses;

  @override
  Future<List<ConsultationRequest>> fetchMine({int limit = 50}) async =>
      <ConsultationRequest>[
        for (int i = 0; i < statuses.length; i++)
          consultationFromJson(<String, Object?>{
            'id': 'c$i',
            'status': statuses[i],
          }),
      ];
}

MyReservation _reservation(String id, DateTime startsAt) => MyReservation(
  id: id,
  slotId: 'slot-$id',
  trainerId: 'trainer-kim',
  startsAt: startsAt,
  cancellable: true,
);

AppConfig _config({required bool mock}) => AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: mock,
);

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('AccountDeletionPreview', () {
    test('서버 응답을 읽는다', () {
      final AccountDeletionPreview p =
          AccountDeletionPreview.fromJson(<String, Object?>{
            'points': 1200,
            'active_coupons': 2,
            'upcoming_reservations': 1,
            'pending_consultations': 3,
          });
      expect(
        p,
        const AccountDeletionPreview(
          points: 1200,
          activeCoupons: 2,
          upcomingReservations: 1,
          pendingConsultations: 3,
        ),
      );
      expect(p.hasLosses, isTrue);
    });

    test('빠지거나 음수인 값은 0 으로 읽는다', () {
      final AccountDeletionPreview p = AccountDeletionPreview.fromJson(
        <String, Object?>{'points': -5, 'active_coupons': 'x'},
      );
      expect(p, const AccountDeletionPreview());
      expect(p.hasLosses, isFalse);
    });

    test('copyWith 는 준 칸만 바꾼다', () {
      const AccountDeletionPreview p = AccountDeletionPreview(points: 10);
      expect(
        p.copyWith(upcomingReservations: 2),
        const AccountDeletionPreview(points: 10, upcomingReservations: 2),
      );
    });
  });

  group('withdrawConfirmMessage', () {
    test('미리보기가 없으면 기본 문구 그대로다', () {
      expect(withdrawConfirmMessage(ko, null), ko.myWithdrawConfirm);
    });

    test('잃는 것이 없으면 숫자 줄을 달지 않는다', () {
      expect(
        withdrawConfirmMessage(ko, const AccountDeletionPreview()),
        ko.myWithdrawConfirm,
      );
    });

    test('0 이 아닌 것만, 정해진 순서로 한 줄씩', () {
      final String message = withdrawConfirmMessage(
        ko,
        const AccountDeletionPreview(points: 1500, pendingConsultations: 2),
      );
      expect(
        message,
        '${ko.myWithdrawConfirm}\n\n'
        '${ko.myWithdrawLosePoints(1500)}\n'
        '${ko.myWithdrawCancelConsultations(2)}',
      );
      expect(message, contains('1,500P'));
      expect(message, isNot(contains(ko.myWithdrawLoseCoupons(0))));
    });

    test('영어 문구도 숫자를 싣는다', () {
      final String message = withdrawConfirmMessage(
        en,
        const AccountDeletionPreview(activeCoupons: 1, upcomingReservations: 3),
      );
      expect(message, contains(en.myWithdrawLoseCoupons(1)));
      expect(message, contains(en.myWithdrawCancelReservations(3)));
      expect(en.myWithdrawLoseCoupons(1), isNot(en.myWithdrawLoseCoupons(2)));
    });
  });

  group('loadWithdrawPreview', () {
    test('읽은 값을 그대로 돌려준다', () async {
      expect(
        await loadWithdrawPreview(
          () async => const AccountDeletionPreview(points: 3),
        ),
        const AccountDeletionPreview(points: 3),
      );
    });

    test('실패하면 null — 확인창이 기본 문구로 물러선다', () async {
      expect(
        await loadWithdrawPreview(() async => throw Exception('offline')),
        isNull,
      );
    });

    test('늦으면 기다리지 않는다', () async {
      final Completer<AccountDeletionPreview> never =
          Completer<AccountDeletionPreview>();
      expect(
        await loadWithdrawPreview(
          () => never.future,
          timeout: const Duration(milliseconds: 10),
        ),
        isNull,
      );
    });
  });

  group('withdrawPreviewLoaderProvider', () {
    test('실서버는 서버가 준 네 숫자를 그대로 쓴다', () async {
      final MockAccountRepository account = MockAccountRepository()
        ..deletionPreview = const AccountDeletionPreview(
          points: 900,
          activeCoupons: 1,
          upcomingReservations: 2,
          pendingConsultations: 1,
        );
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config(mock: false)),
          accountRepositoryProvider.overrideWithValue(account),
        ],
      );
      addTearDown(c.dispose);

      expect(
        await c.read(withdrawPreviewLoaderProvider)(),
        account.deletionPreview,
      );
    });

    test('데모는 예약·상담 요청을 목 저장소에서 다시 센다', () async {
      final DateTime now = nowKst();
      final MockAccountRepository account = MockAccountRepository()
        ..deletionPreview = const AccountDeletionPreview(
          points: 1240,
          activeCoupons: 1,
        );
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config(mock: true)),
          accountRepositoryProvider.overrideWithValue(account),
          gymRepositoryProvider.overrideWithValue(
            _Gym(<MyReservation>[
              _reservation('future-1', now.add(const Duration(days: 1))),
              _reservation('future-2', now.add(const Duration(hours: 3))),
              // 이미 지난 수업은 취소될 것이 없다.
              _reservation('past', now.subtract(const Duration(days: 2))),
            ]),
          ),
          consultationRepositoryProvider.overrideWithValue(
            _Consultations(<String>['pending', 'accepted', 'cancelled']),
          ),
        ],
      );
      addTearDown(c.dispose);

      expect(
        await c.read(withdrawPreviewLoaderProvider)(),
        const AccountDeletionPreview(
          points: 1240,
          activeCoupons: 1,
          upcomingReservations: 2,
          pendingConsultations: 1,
        ),
      );
    });
  });
}
