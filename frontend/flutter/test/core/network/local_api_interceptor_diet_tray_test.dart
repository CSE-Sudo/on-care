/// 목업 API 의 분석용 식판 — 서버 `diet_tray_service` 와 같은 규칙. (#2150)
///
/// 최근 28일(오늘 포함) 중 사진이 붙은 끼니를 남긴 날이 20일 이상이고 담당이 있으면
/// 0P 수령 쿠폰을 받는다. 손으로 적은 끼니·창 밖의 날은 세지 않는다. 사용 완료하면
/// 받음이고 다시 받지 못한다. 담당이 끊기면 받지 않은 쿠폰은 취소된다.
library;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/benefits/data/repositories/dio_benefits_repository.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/diet_tray.dart';

void main() {
  late AppDatabase db;
  late Dio dio;
  late DemoPointsLedger ledger;
  late DemoCouponBook book;
  late DioBenefitsRepository repo;
  final DateTime now = DateTime(2026, 9, 15, 10);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = DemoPointsLedger(openingBalance: 1000);
    book = DemoCouponBook(ledger: ledger, now: () => now);
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: ledger,
        coupons: book,
      ),
    );
    repo = DioBenefitsRepository(dio);
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  String ymd(int daysAgo) {
    final DateTime d = DateTime(now.year, now.month, now.day - daysAgo);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  int seq = 0;

  /// [from]일 전부터 거슬러 [days]일 동안 하루 한 끼를 넣는다. [photo] 가 거짓이면
  /// 손으로 적은 끼니다.
  Future<void> addMeals(int days, {int from = 0, bool photo = true}) async {
    for (int i = from; i < from + days; i++) {
      await db
          .into(db.dietEntries)
          .insert(
            DietEntriesCompanion.insert(
              id: 'tray-${seq++}',
              date: ymd(i),
              mealType: 'lunch',
              timeLabel: '12:00',
              foodsJson: '[]',
              totalCalories: 500,
              photoAsset: photo
                  ? const Value<String>('assets/demo/meal.jpg')
                  : const Value<String>.absent(),
            ),
          );
    }
  }

  test('사진 끼니를 남긴 날만 창 안에서 센다', () async {
    await addMeals(19);
    await addMeals(1, from: 20, photo: false);
    await addMeals(2, from: 28);

    final DietTray tray = await repo.fetchDietTray();
    expect(tray.photoDays, 19);
    expect(tray.requiredDays, 20);
    expect(tray.windowDays, 28);
    expect(tray.status, DietTrayStatus.progress);
    expect(tray.daysLeft, 1);
    await expectLater(repo.claimDietTray(), throwsA(anything));

    await addMeals(1, from: 27);
    expect((await repo.fetchDietTray()).status, DietTrayStatus.claimable);
  });

  test('받으면 0P 수령 쿠폰이 내 쿠폰에 서고, 사용 완료하면 다시 받지 못한다', () async {
    await addMeals(20);

    final DietTray claimed = await repo.claimDietTray(clientRequestId: 'r1');
    expect(claimed.status, DietTrayStatus.issued);
    final Coupon coupon = claimed.coupon!;
    expect(coupon.item, 'diet_tray');
    expect(coupon.cost, 0);
    expect(coupon.gymName, kDemoGymName);
    expect(coupon.noExpiry, isTrue);
    expect(coupon.daysLeft, 0);
    expect(ledger.balance, 1000);

    // 같은 요청의 재시도는 한 장이다.
    final DietTray again = await repo.claimDietTray(clientRequestId: 'r1');
    expect(again.coupon!.id, coupon.id);
    expect(
      (await repo.fetchCoupons()).where((Coupon c) => c.item == 'diet_tray'),
      hasLength(1),
    );

    await repo.useCoupon(coupon.id);
    expect((await repo.fetchDietTray()).status, DietTrayStatus.received);
    await expectLater(
      repo.claimDietTray(clientRequestId: 'r2'),
      throwsA(anything),
    );
  });

  test('담당이 끊기면 받지 않은 쿠폰이 취소되고 담당 없음으로 돌아간다', () async {
    await addMeals(20);
    final String id = (await repo.claimDietTray()).coupon!.id;

    book.endTrainerLink();

    final Coupon row = (await repo.fetchCoupons()).firstWhere(
      (Coupon c) => c.id == id,
    );
    expect(row.status, CouponStatus.cancelled);
    final DietTray tray = await repo.fetchDietTray();
    expect(tray.status, DietTrayStatus.progress);
    expect(tray.hasTrainer, isFalse);
  });

  test('교환 경로로는 받을 수 없다', () async {
    await addMeals(20);
    final Response<Object?> res = await dio.post<Object?>(
      '/me/points/exchange',
      data: <String, Object?>{'item': 'diet_tray'},
    );
    expect(res.statusCode, 404);
  });
}
