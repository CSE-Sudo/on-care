/// 목업 API 의 교환·식판·챌린지 거절 — 실서버와 같은 상태 코드·사유 문장. (#3363)
///
/// 앱은 서버 사유 문장으로 실패 까닭을 가른다([BenefitRejection]). 목업이 다른
/// 문장을 주면 데모 모드에서만 "다시 시도" 로 물러나므로, 목업의 거절이 저장소를
/// 거쳐 같은 까닭으로 읽히는지 본다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/benefits/data/repositories/dio_benefits_repository.dart';
import 'package:oncare/features/benefits/data/repositories/dio_challenge_repository.dart';
import 'package:oncare/features/benefits/domain/benefit_rejection.dart';

void main() {
  late AppDatabase db;
  late Dio dio;
  late DemoPointsLedger ledger;
  late DateTime now;

  /// 2026-09-14 는 월요일이다 — 챌린지 참가 요일.
  void build({int balance = 30000, bool hasTrainer = true}) {
    ledger = DemoPointsLedger(openingBalance: balance);
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: ledger,
        coupons: DemoCouponBook(
          ledger: ledger,
          now: () => now,
          hasTrainer: hasTrainer,
        ),
        challenges: DemoWeeklyChallenge(ledger: ledger, now: () => now),
      ),
    );
  }

  setUp(() {
    now = DateTime(2026, 9, 14, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<BenefitRejection> rejectionOf(Future<Object?> Function() call) async {
    try {
      await call();
    } on Object catch (error) {
      return BenefitRejection.of(error);
    }
    fail('거절되지 않았다');
  }

  Future<BenefitRejection> exchangeRejection(String item) =>
      rejectionOf(() => DioBenefitsRepository(dio).exchange(item));

  group('교환', () {
    test('잔액이 모자라면 잔액 부족과 모자란 만큼', () async {
      build(balance: 100);

      final BenefitRejection r = await exchangeRejection('streak_shield');

      expect(r.kind, BenefitRejectionKind.insufficientPoints);
      expect(r.shortfall, 200);
    });

    test('보호권을 최대로 가지면 보호권 한도', () async {
      build();
      final DioBenefitsRepository repo = DioBenefitsRepository(dio);
      BenefitRejection? rejection;
      for (int i = 0; i < 10 && rejection == null; i++) {
        try {
          await repo.exchange('streak_shield');
        } on Object catch (error) {
          rejection = BenefitRejection.of(error);
        }
      }

      expect(rejection?.kind, BenefitRejectionKind.shieldLimit);
    });

    test('사용하지 않은 같은 쿠폰이 있으면 이미 보유', () async {
      build();
      await DioBenefitsRepository(dio).exchange('pt_renewal');

      final BenefitRejection r = await exchangeRejection('pt_renewal');

      expect(r.kind, BenefitRejectionKind.alreadyOwned);
    });

    test('담당 트레이너가 없으면 막힘이고 사유를 들고 온다', () async {
      build(hasTrainer: false);

      final BenefitRejection r = await exchangeRejection('pt_renewal');

      expect(r.kind, BenefitRejectionKind.blocked);
      expect(r.detail, '담당 트레이너가 있어야 교환할 수 있어요.');
    });

    test('없는 항목은 404 라 막힘이다', () async {
      build();

      final BenefitRejection r = await exchangeRejection('nope');

      expect(r.kind, BenefitRejectionKind.blocked);
      expect(r.retryable, isFalse);
    });

    test('같은 요청 키로 다시 보낸 보호권 교환은 포인트를 한 번만 뺀다', () async {
      build(balance: 1000);
      final DioBenefitsRepository repo = DioBenefitsRepository(dio);

      await repo.exchange('streak_shield', clientRequestId: 'exchange-1');
      await repo.exchange('streak_shield', clientRequestId: 'exchange-1');

      expect(ledger.balance, 700);
      await repo.exchange('streak_shield', clientRequestId: 'exchange-2');
      expect(ledger.balance, 400);
    });
  });

  group('식판 받기', () {
    test('사진 기록일이 모자라면 막힘이고 사유를 들고 온다', () async {
      build();

      final BenefitRejection r = await rejectionOf(
        () => DioBenefitsRepository(dio).claimDietTray(),
      );

      expect(r.kind, BenefitRejectionKind.blocked);
      expect(r.detail, contains('더 필요해요'));
    });
  });

  group('챌린지 참가', () {
    test('이번 주에 이미 참가했으면 이미 보유', () async {
      build();
      final DioChallengeRepository repo = DioChallengeRepository(dio);
      await repo.join(clientRequestId: 'challenge-1');

      final BenefitRejection r = await rejectionOf(
        () => repo.join(clientRequestId: 'challenge-2'),
      );

      expect(r.kind, BenefitRejectionKind.alreadyOwned);
    });

    test('같은 요청 키로 다시 보내면 거절이 아니라 처음 참가를 돌려준다', () async {
      build(balance: 1000);
      final DioChallengeRepository repo = DioChallengeRepository(dio);

      await repo.join(clientRequestId: 'challenge-1');
      await repo.join(clientRequestId: 'challenge-1');

      expect(ledger.balance, 900);
    });

    test('잔액이 모자라면 잔액 부족과 모자란 만큼', () async {
      build(balance: 60);

      final BenefitRejection r = await rejectionOf(
        () => DioChallengeRepository(dio).join(),
      );

      expect(r.kind, BenefitRejectionKind.insufficientPoints);
      expect(r.shortfall, 40);
    });

    test('참가 요일이 지나면 막힘이고 사유를 들고 온다', () async {
      now = DateTime(2026, 9, 16, 10);
      build();

      final BenefitRejection r = await rejectionOf(
        () => DioChallengeRepository(dio).join(),
      );

      expect(r.kind, BenefitRejectionKind.blocked);
      expect(r.detail, '주간 챌린지는 월·화요일에만 참가할 수 있어요.');
    });
  });
}
