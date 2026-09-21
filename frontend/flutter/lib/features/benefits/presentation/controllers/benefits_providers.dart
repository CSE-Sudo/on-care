import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/benefits/data/repositories/dio_benefits_repository.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/entities/profile_pet.dart';
import 'package:oncare/features/benefits/domain/repositories/benefits_repository.dart';

/// 포인트 사용처·내 혜택 저장소. (#1787)
///
/// 모드마다 저장소를 가르지 않는다 — 데모 모드는 Dio 의 `LocalApiInterceptor` 가
/// 같은 경로를 받아 목업 포인트 원장으로 답한다.
final benefitsRepositoryProvider = Provider<BenefitsRepository>(
  (ref) => DioBenefitsRepository(ref.watch(dioProvider)),
  name: 'benefitsRepository',
);

/// 사용처 화면의 교환 목록. 화면을 떠나면 버리고 다시 열 때 새로 읽는다 — 그사이
/// 기록으로 적립했거나 담당이 바뀌었으면 교환 가능 여부가 달라져 있다.
final pointsShopProvider = FutureProvider.autoDispose<PointsShop>(
  (ref) => ref.watch(benefitsRepositoryProvider).fetchShop(),
  name: 'pointsShop',
);

/// 내 쿠폰. 교환·사용 처리 뒤, 쿠폰 알림을 눌렀을 때 다시 읽는다.
final myCouponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(benefitsRepositoryProvider).fetchCoupons(),
  name: 'myCoupons',
);

/// MY 프로필 이름 옆에 단 펫(#2021). MY 탭이 들고 있는 동안 살아 있고, 사용처에서
/// 펫을 달면 다시 읽는다. 읽지 못하면 이름만 그린다 — 꾸밈 때문에 프로필이 비지 않는다.
final profilePetProvider = FutureProvider<ProfilePet?>(
  (ref) => ref.watch(benefitsRepositoryProvider).fetchProfilePet(),
  name: 'profilePet',
);
