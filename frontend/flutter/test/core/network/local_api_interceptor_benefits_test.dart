/// 목업 API 의 포인트 사용처·쿠폰 — 실서버와 같은 규칙. (#1787)
///
/// 교환은 원장에서 포인트를 빼고, 모자라면 409. PT 재등록 쿠폰은 담당 트레이너가
/// 있어야 하고 사용 가능한 것은 한 장뿐. 건강식 쿠폰은 회원이 한 번 사용 처리한다.
/// 기한이 지나면 만료되고 포인트는 돌려주지 않으며, 담당이 끊기면 재등록 쿠폰을
/// 취소하고 돌려준다.
library;

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/benefits/data/repositories/dio_benefits_repository.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';

void main() {
  late AppDatabase db;
  late Dio dio;
  late DemoPointsLedger ledger;
  late DemoCouponBook book;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 9, 15, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ledger = DemoPointsLedger(openingBalance: 7300);
    book = DemoCouponBook(ledger: ledger, now: () => now, random: math.Random(7));
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      LocalApiInterceptor(
        db,
        Logger(level: Level.off),
        points: ledger,
        coupons: book,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    dio.close();
  });

  Future<Response<Object?>> exchange(String item, {String? requestId}) =>
      dio.post<Object?>(
        '/me/points/exchange',
        data: <String, Object?>{
          'item': item,
          'client_request_id': ?requestId,
        },
      );

  Future<List<Map<String, Object?>>> coupons() async {
    final Response<List<Object?>> res = await dio.get<List<Object?>>(
      '/me/coupons',
    );
    return <Map<String, Object?>>[
      for (final Object? row in res.data!)
        (row! as Map<Object?, Object?>).cast<String, Object?>(),
    ];
  }

  Future<int> balance() async {
    final Response<Map<String, Object?>> res = await dio
        .get<Map<String, Object?>>('/users/me/health');
    return res.data!['activity_points']! as int;
  }

  test('교환 목록은 서버와 같은 순서·가격·막힌 이유를 준다', () async {
    final PointsShop shop = await DioBenefitsRepository(dio).fetchShop();

    expect(shop.balance, 7300);
    expect(shop.hasTrainer, isTrue);
    expect(shop.items.map((ShopItem i) => i.id), <String>[
      'pt_renewal',
      'salad_discount',
      'protein_discount',
    ]);
    expect(shop.items.map((ShopItem i) => i.cost), <int>[5000, 1000, 1000]);
    expect(shop.items.every((ShopItem i) => i.available), isTrue);

    book.endTrainerLink();
    final PointsShop noTrainer = await DioBenefitsRepository(dio).fetchShop();
    expect(noTrainer.items.first.blockReason, ShopBlockReason.noTrainer);
  });

  test('교환하면 포인트가 빠지고 쿠폰이 생긴다', () async {
    final CouponExchange result = await DioBenefitsRepository(
      dio,
    ).exchange('salad_discount');

    expect(result.spent, 1000);
    expect(result.balance, 6300);
    expect(result.coupon.status, CouponStatus.issued);
    expect(result.coupon.redeemer, CouponRedeemer.member);
    expect(result.coupon.code, hasLength(8));
    expect(result.coupon.daysLeft, 30);
    expect(result.coupon.expiresOn, DateTime(2026, 10, 15));
    expect(await balance(), 6300);
    expect((await coupons()).single['id'], result.coupon.id);
  });

  test('잔액이 모자라면 409 이고 아무것도 바뀌지 않는다', () async {
    ledger = DemoPointsLedger(openingBalance: 900);
    book = DemoCouponBook(ledger: ledger, now: () => now);
    dio.interceptors
      ..clear()
      ..add(
        LocalApiInterceptor(
          db,
          Logger(level: Level.off),
          points: ledger,
          coupons: book,
        ),
      );

    final Response<Object?> res = await exchange('protein_discount');

    expect(res.statusCode, 409);
    expect(await balance(), 900);
    expect(await coupons(), isEmpty);
    await expectLater(
      DioBenefitsRepository(dio).exchange('protein_discount'),
      throwsA(anything),
    );
  });

  test('재등록 쿠폰은 사용 가능한 것이 한 장뿐이다', () async {
    expect((await exchange('pt_renewal')).statusCode, 201);
    expect((await exchange('pt_renewal')).statusCode, 409);
    expect(await balance(), 2300);

    final PointsShop shop = await DioBenefitsRepository(dio).fetchShop();
    expect(shop.items.first.blockReason, ShopBlockReason.activeCoupon);
  });

  test('건강식 쿠폰도 종류마다 사용하지 않은 것은 한 장뿐이다', () async {
    expect((await exchange('salad_discount')).statusCode, 201);
    expect((await exchange('salad_discount')).statusCode, 409);
    // 다른 종류는 따로 센다.
    expect((await exchange('protein_discount')).statusCode, 201);
    expect(await balance(), 5300);

    final PointsShop shop = await DioBenefitsRepository(dio).fetchShop();
    final Map<String, ShopItem> items = <String, ShopItem>{
      for (final ShopItem item in shop.items) item.id: item,
    };
    expect(items['salad_discount']!.available, isFalse);
    expect(items['salad_discount']!.blockReason, ShopBlockReason.activeCoupon);
    expect(items['protein_discount']!.blockReason, ShopBlockReason.activeCoupon);
    expect(items['pt_renewal']!.available, isTrue);

    // 사용하면 같은 종류를 다시 받을 수 있다.
    final String salad = (await coupons())
        .firstWhere((Map<String, Object?> c) => c['item'] == 'salad_discount')['id']!
        as String;
    await DioBenefitsRepository(dio).useCoupon(salad);
    expect((await exchange('salad_discount')).statusCode, 201);
    // 만료돼도 다시 받을 수 있다.
    now = DateTime(2026, 10, 16, 0, 1);
    expect((await exchange('protein_discount')).statusCode, 201);
    expect(await balance(), 3300);
  });

  test('같은 요청 id 로 다시 보내면 한 번만 쓴다', () async {
    final Response<Object?> first = await exchange('salad_discount', requestId: 'req-1');
    final Response<Object?> second = await exchange('salad_discount', requestId: 'req-1');

    expect(
      ((second.data! as Map<Object?, Object?>)['coupon']! as Map<Object?, Object?>)['id'],
      ((first.data! as Map<Object?, Object?>)['coupon']! as Map<Object?, Object?>)['id'],
    );
    expect(await balance(), 6300);
  });

  test('건강식·재등록 쿠폰 모두 회원 휴대폰에서 한 번 사용 처리한다', () async {
    await exchange('salad_discount');
    final String salad = (await coupons()).single['id']! as String;
    final Coupon used = await DioBenefitsRepository(dio).useCoupon(salad);
    final Coupon again = await DioBenefitsRepository(dio).useCoupon(salad);

    expect(used.status, CouponStatus.used);
    expect(again.status, CouponStatus.used);

    await exchange('pt_renewal');
    final String renewal = (await coupons())
        .firstWhere((Map<String, Object?> c) => c['item'] == 'pt_renewal')['id']!
        as String;
    // PT 재등록 쿠폰도 직원 확인 뒤 회원 휴대폰에서 사용 완료를 누른다.
    final Coupon renewalUsed = await DioBenefitsRepository(
      dio,
    ).useCoupon(renewal);
    expect(renewalUsed.status, CouponStatus.used);
    expect(renewalUsed.redeemer, CouponRedeemer.member);
    expect(renewalUsed.usedAt, isNotNull);
    // 두 번 눌러도 처음 사용 시각 그대로다.
    expect(again.usedAt, used.usedAt);
  });

  test('기한이 지나면 만료되고 포인트는 돌려주지 않는다', () async {
    await exchange('pt_renewal');
    await exchange('salad_discount');
    now = DateTime(2026, 10, 16, 0, 1);

    final List<Map<String, Object?>> rows = await coupons();
    expect(rows.every((Map<String, Object?> c) => c['status'] == 'expired'), isTrue);
    final String salad = rows
        .firstWhere((Map<String, Object?> c) => c['item'] == 'salad_discount')['id']!
        as String;
    expect((await dio.post<Object?>('/me/coupons/$salad/use')).statusCode, 409);

    book.endTrainerLink();
    expect(await balance(), 1300);
  });

  test('마지막 날까지는 쓸 수 있고 D-day 다', () async {
    await exchange('salad_discount');
    now = DateTime(2026, 10, 15, 23, 59);

    final Map<String, Object?> row = (await coupons()).single;
    expect(row['status'], 'issued');
    expect(row['days_left'], 0);
  });

  test('목업 헬스장·트레이너 해제는 재등록 쿠폰을 취소하고 포인트를 돌려준다', () async {
    final MockGymRepository gyms = MockGymRepository(coupons: book);
    await exchange('pt_renewal');
    await exchange('salad_discount');
    expect(await balance(), 1300);

    await gyms.disconnectMyTrainer();

    expect(await balance(), 6300);
    final List<Map<String, Object?>> rows = await coupons();
    expect(
      rows.firstWhere((Map<String, Object?> c) => c['item'] == 'pt_renewal')['status'],
      'cancelled',
    );
    expect(
      rows.firstWhere((Map<String, Object?> c) => c['item'] == 'salad_discount')['status'],
      'issued',
    );
    // 두 번 끊어도 두 번 돌려주지 않는다.
    await gyms.disconnectMyGym();
    expect(await balance(), 6300);
  });
}
