import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/entities/profile_pet.dart';

/// 포인트 사용처와 내 혜택(쿠폰). (#1787)
///
/// 구현은 Dio 하나다 — 데모 모드에서는 `LocalApiInterceptor` 가 같은 경로를 받아
/// 서버와 같은 규칙으로 답한다(식단과 같은 방식). 그래서 교환한 포인트가 목업
/// 원장에서 빠져 MY 잔액과 한 숫자로 움직인다.
///
/// 내 혜택은 나중에 연속 기록 보호권·챌린지(#1788, #1789)도 담는다. 그때 이 계약에
/// 조회를 더한다.
abstract interface class BenefitsRepository {
  /// 교환 항목과 항목별 교환 가능 여부.
  Future<PointsShop> fetchShop();

  /// 포인트를 써서 쿠폰을 발급한다. [clientRequestId] 가 같은 재시도는 두 번
  /// 쓰지 않는다. 규칙에 막히면(잔액 부족 등) 서버 오류로 올라온다.
  ///
  /// [option] 은 항목이 여러 갈래일 때 고른 갈래다 — 그래프 색 바꾸기(#2076)에서
  /// 어느 색을 열지, 프로필 펫(#2021)에서 어느 펫을 달지 싣는다. 갈래가 없는 항목은
  /// 주지 않는다.
  Future<CouponExchange> exchange(
    String itemId, {
    String? option,
    String? clientRequestId,
  });

  /// 내 쿠폰 — 사용 가능한 것 먼저.
  Future<List<Coupon>> fetchCoupons();

  /// 회원이 스스로 사용 완료를 누르는 쿠폰을 사용 처리한다. 되돌리기는 없다.
  Future<Coupon> useCoupon(String couponId);

  /// MY 프로필 이름 옆에 단 펫(#2021). 달고 있지 않거나 기간이 끝났으면 null.
  Future<ProfilePet?> fetchProfilePet();
}
