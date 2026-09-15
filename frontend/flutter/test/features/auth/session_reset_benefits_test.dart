/// 세션 전환은 포인트 사용처·내 쿠폰을 다시 읽게 한다. (#1787)
///
/// 두 provider 는 auto-dispose 지만, 사용처나 내 혜택 화면을 연 채로 데모에서
/// 로그인으로 넘어가면 살아남아 앞 계정의 잔액·교환 가능 여부·쿠폰 코드를 보여 준다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';

import '../benefits/fake_benefits_repository.dart';

class _CountingBenefitsRepository extends FakeBenefitsRepository {
  int shopCalls = 0;
  int couponCalls = 0;

  @override
  Future<PointsShop> fetchShop() {
    shopCalls++;
    return super.fetchShop();
  }

  @override
  Future<List<Coupon>> fetchCoupons() {
    couponCalls++;
    return super.fetchCoupons();
  }
}

void main() {
  test('세션 리셋 뒤 보고 있던 사용처·쿠폰을 다시 읽는다', () async {
    final _CountingBenefitsRepository repo = _CountingBenefitsRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        benefitsRepositoryProvider.overrideWithValue(repo),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    // 화면이 보고 있는 상태 — auto-dispose 가 버리지 못한다.
    container
      ..listen(pointsShopProvider, (_, _) {})
      ..listen(myCouponsProvider, (_, _) {});

    await container.read(pointsShopProvider.future);
    await container.read(myCouponsProvider.future);
    expect(repo.shopCalls, 1);
    expect(repo.couponCalls, 1);

    container.read(sessionFeatureResetProvider)();
    await container.read(pointsShopProvider.future);
    await container.read(myCouponsProvider.future);

    expect(repo.shopCalls, 2);
    expect(repo.couponCalls, 2);
  });
}
