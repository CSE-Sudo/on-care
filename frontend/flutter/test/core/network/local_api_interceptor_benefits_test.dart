/// 목업 API 의 포인트 사용처·쿠폰 — 실서버와 같은 규칙. (#1787)
///
/// 교환은 원장에서 포인트를 빼고, 모자라면 409. PT 재등록 3만원 할인(21,000P)은 담당
/// 트레이너가, 개인 락커 1개월 무료(7,000P)는 연결한 헬스장이 있어야 하고 사용 가능한
/// 것은 종류마다 한 장뿐이다. 락커는 한 달에 한 번이다. 기한이 지나면 만료되고 포인트는
/// 돌려주지 않으며, 담당이 끊기면 재등록 쿠폰을, 헬스장이 끊기면 락커 쿠폰을 취소하고
/// 돌려준다.
library;

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
    ledger = DemoPointsLedger(openingBalance: 30000);
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

  Future<Map<String, ShopItem>> shopItems() async {
    final PointsShop shop = await DioBenefitsRepository(dio).fetchShop();
    return <String, ShopItem>{for (final ShopItem item in shop.items) item.id: item};
  }

  String idOf(List<Map<String, Object?>> rows, String item) =>
      rows.firstWhere((Map<String, Object?> c) => c['item'] == item)['id']!
          as String;

  test('교환 목록은 서버와 같은 순서·가격·막힌 이유를 준다', () async {
    final PointsShop shop = await DioBenefitsRepository(dio).fetchShop();

    expect(shop.balance, 30000);
    expect(shop.hasTrainer, isTrue);
    expect(shop.hasGym, isTrue);
    expect(shop.items.map((ShopItem i) => i.id), <String>[
      'pt_renewal',
      'locker_month',
      'streak_shield',
      'graph_color',
      // 채팅 이모티콘 24시간 이용권(#2020) — 쿠폰이 아니라 이용권이다.
      'emote_pass_24h',
      // MY 프로필 펫 이모지(#2021) — 7일 동안 이름 옆에 단다.
      'profile_pet',
    ]);
    expect(
      shop.items.map((ShopItem i) => i.cost),
      <int>[21000, 7000, 300, 150, 300, 200],
    );
    expect(
      shop.items.map((ShopItem i) => i.requiresTrainer),
      // 채팅 이모티콘 이용권은 트레이너 채팅에만 쓰인다(#2142).
      <bool>[true, false, false, false, true, false],
    );
    expect(
      shop.items.map((ShopItem i) => i.requiresGym),
      <bool>[false, true, false, false, false, false],
    );
    expect(shop.items.every((ShopItem i) => i.available), isTrue);

    book.endTrainerLink();
    Map<String, ShopItem> items = await shopItems();
    expect(items['pt_renewal']!.blockReason, ShopBlockReason.noTrainer);
    expect(items['emote_pass_24h']!.blockReason, ShopBlockReason.noTrainer);
    expect(items['locker_month']!.available, isTrue);

    book.endGymLink();
    items = await shopItems();
    expect(items['locker_month']!.blockReason, ShopBlockReason.noGym);
    expect((await DioBenefitsRepository(dio).fetchShop()).hasGym, isFalse);
  });

  test('프로필 펫을 달면 이름 옆에 붙고 카드가 남은 기간을 싣는다 (#2021)', () async {
    final DioBenefitsRepository repo = DioBenefitsRepository(dio);
    await repo.exchange('profile_pet', option: 'cat');

    expect((await repo.fetchProfilePet())!.kind, 'cat');
    final ShopItem card = (await shopItems())['profile_pet']!;
    expect(card.blockReason, ShopBlockReason.activePet);
    expect(card.remainingSeconds, 7 * 86400);

    now = now.add(const Duration(days: 7));
    expect(await repo.fetchProfilePet(), isNull);
    expect((await shopItems())['profile_pet']!.available, isTrue);
  });

  test('주간 리포트는 담당이 없을 때만 서고 지난주를 한 번만 산다 (#2022)', () async {
    final DioBenefitsRepository repo = DioBenefitsRepository(dio);
    // 데모 회원은 담당이 있다 — 트레이너가 등록해 주므로 항목이 없다.
    expect((await shopItems()).containsKey('weekly_report'), isFalse);

    book.endTrainerLink();
    expect((await shopItems())['weekly_report']!.available, isTrue);
    await repo.exchange('weekly_report');

    expect((await repo.fetchWeeklyReports()).weeks, hasLength(1));
    expect(
      (await shopItems())['weekly_report']!.blockReason,
      ShopBlockReason.weekOwned,
    );
    await expectLater(repo.exchange('weekly_report'), throwsA(anything));
  });

  test('교환하면 포인트가 빠지고 헬스장이 적힌 쿠폰이 생긴다', () async {
    final CouponExchange result = await DioBenefitsRepository(
      dio,
    ).exchange('locker_month');

    final Coupon coupon = result.coupon!;
    expect(result.spent, 7000);
    expect(result.balance, 23000);
    expect(coupon.status, CouponStatus.issued);
    expect(coupon.gymName, kDemoGymName);
    expect(coupon.trainerName, isEmpty);
    expect(coupon.daysLeft, 30);
    expect(coupon.expiresOn, DateTime(2026, 10, 15));
    expect(await balance(), 23000);
    expect((await coupons()).single['id'], coupon.id);
  });

  test('잔액이 모자라면 409 이고 아무것도 바뀌지 않는다', () async {
    ledger = DemoPointsLedger(openingBalance: 6900);
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

    final Response<Object?> res = await exchange('locker_month');

    expect(res.statusCode, 409);
    expect(await balance(), 6900);
    expect(await coupons(), isEmpty);
    await expectLater(
      DioBenefitsRepository(dio).exchange('locker_month'),
      throwsA(anything),
    );
  });

  test('카탈로그 밖 항목은 교환할 수 없다', () async {
    expect((await exchange('unknown_item')).statusCode, 404);
    expect(await balance(), 30000);
    expect(await coupons(), isEmpty);
  });

  test('재등록 쿠폰은 사용 가능한 것이 한 장뿐이다', () async {
    expect((await exchange('pt_renewal')).statusCode, 201);
    expect((await exchange('pt_renewal')).statusCode, 409);
    expect(await balance(), 9000);

    expect(
      (await shopItems())['pt_renewal']!.blockReason,
      ShopBlockReason.activeCoupon,
    );
  });

  test('락커 쿠폰은 한 달에 한 번이다', () async {
    expect((await exchange('locker_month')).statusCode, 201);
    // 사용하지 않은 쿠폰이 있으면 그 이유가 먼저다.
    expect((await exchange('locker_month')).statusCode, 409);
    expect(
      (await shopItems())['locker_month']!.blockReason,
      ShopBlockReason.activeCoupon,
    );

    // 써도 같은 달에는 다시 받을 수 없다.
    await DioBenefitsRepository(dio).useCoupon(idOf(await coupons(), 'locker_month'));
    expect(
      (await shopItems())['locker_month']!.blockReason,
      ShopBlockReason.monthlyLimit,
    );
    final Response<Object?> again = await exchange('locker_month');
    expect(again.statusCode, 409);
    expect(
      (again.data! as Map<Object?, Object?>)['detail'],
      '이번 달에는 이미 교환했어요.',
    );
    expect(await balance(), 23000);

    // 다음 달이 되면 다시 받는다.
    now = DateTime(2026, 10, 1, 9);
    expect((await shopItems())['locker_month']!.available, isTrue);
    expect((await exchange('locker_month')).statusCode, 201);
    expect(await balance(), 16000);
  });

  test('같은 요청 id 로 다시 보내면 한 번만 쓴다', () async {
    final Response<Object?> first = await exchange('locker_month', requestId: 'req-1');
    final Response<Object?> second = await exchange('locker_month', requestId: 'req-1');

    expect(
      ((second.data! as Map<Object?, Object?>)['coupon']! as Map<Object?, Object?>)['id'],
      ((first.data! as Map<Object?, Object?>)['coupon']! as Map<Object?, Object?>)['id'],
    );
    expect(await balance(), 23000);
  });

  test('락커·재등록 쿠폰 모두 회원 휴대폰에서 한 번 사용 처리한다', () async {
    await exchange('locker_month');
    final String locker = (await coupons()).single['id']! as String;
    final Coupon used = await DioBenefitsRepository(dio).useCoupon(locker);
    final Coupon again = await DioBenefitsRepository(dio).useCoupon(locker);

    expect(used.status, CouponStatus.used);
    expect(again.status, CouponStatus.used);

    await exchange('pt_renewal');
    // PT 재등록 쿠폰도 직원 확인 뒤 회원 휴대폰에서 사용 완료를 누른다.
    final Coupon renewalUsed = await DioBenefitsRepository(
      dio,
    ).useCoupon(idOf(await coupons(), 'pt_renewal'));
    expect(renewalUsed.status, CouponStatus.used);
    expect(renewalUsed.usedAt, isNotNull);
    // 두 번 눌러도 처음 사용 시각 그대로다.
    expect(again.usedAt, used.usedAt);
  });

  test('기한이 지나면 만료되고 포인트는 돌려주지 않는다', () async {
    await exchange('pt_renewal');
    await exchange('locker_month');
    now = DateTime(2026, 10, 16, 0, 1);

    final List<Map<String, Object?>> rows = await coupons();
    expect(rows.every((Map<String, Object?> c) => c['status'] == 'expired'), isTrue);
    final String locker = idOf(rows, 'locker_month');
    expect((await dio.post<Object?>('/me/coupons/$locker/use')).statusCode, 409);

    book
      ..endTrainerLink()
      ..endGymLink();
    expect(await balance(), 2000);
  });

  test('마지막 날까지는 쓸 수 있고 D-day 다', () async {
    await exchange('locker_month');
    now = DateTime(2026, 10, 15, 23, 59);

    final Map<String, Object?> row = (await coupons()).single;
    expect(row['status'], 'issued');
    expect(row['days_left'], 0);
  });

  test('목업 트레이너 해제는 재등록 쿠폰을, 헬스장 해제는 락커 쿠폰을 취소하고 돌려준다', () async {
    final MockGymRepository gyms = MockGymRepository(coupons: book);
    await exchange('pt_renewal');
    await exchange('locker_month');
    expect(await balance(), 2000);

    await gyms.disconnectMyTrainer();

    expect(await balance(), 23000);
    List<Map<String, Object?>> rows = await coupons();
    String statusOf(String item) =>
        rows.firstWhere((Map<String, Object?> c) => c['item'] == item)['status']!
            as String;
    expect(statusOf('pt_renewal'), 'cancelled');
    expect(statusOf('locker_month'), 'issued');

    await gyms.disconnectMyGym();

    expect(await balance(), 30000);
    rows = await coupons();
    expect(statusOf('locker_month'), 'cancelled');
    // 두 번 끊어도 두 번 돌려주지 않는다.
    await gyms.disconnectMyGym();
    expect(await balance(), 30000);
    final Map<String, ShopItem> items = await shopItems();
    expect(items['pt_renewal']!.blockReason, ShopBlockReason.noTrainer);
    expect(items['locker_month']!.blockReason, ShopBlockReason.noGym);
  });
}
