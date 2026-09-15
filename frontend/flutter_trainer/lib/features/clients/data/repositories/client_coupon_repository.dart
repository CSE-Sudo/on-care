import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/clients/domain/entities/renewal_coupon.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 회원의 PT 재등록 쿠폰을 확인하고 사용 처리한다. (#1787)
///
/// 회원이 포인트로 교환한 쿠폰은 **현재 담당 트레이너**만 본다. 회원 상세 머리줄의
/// `재등록 쿠폰` 배지가 [fetchRenewalCoupons] 가 비어 있지 않을 때만 서고, 배지를
/// 누른 확인창에서 [redeem] 한다. 되돌리기는 없다.
///
/// 두 구현이 [clientCouponRepositoryProvider] 뒤에 있고 [AppConfig.useMockApi] 로
/// 갈린다.
abstract interface class ClientCouponRepository {
  /// 이 회원이 가진 사용 가능한 재등록 쿠폰. 담당이 아니면 [NotFoundError].
  Future<List<RenewalCoupon>> fetchRenewalCoupons(String clientId);

  /// 사용 처리한다. 이미 사용된 쿠폰의 재요청은 같은 결과다 — 더블 클릭이 두 번
  /// 처리되지 않는다. 만료·취소는 [ServerError](409).
  Future<RenewalCoupon> redeem(String clientId, String couponId);
}

/// 데모 빌드는 브라우저 로컬 prefs 에 쿠폰을 둔다.
///
/// 회원 앱 데모와는 다른 앱이라 그쪽에서 교환한 쿠폰이 넘어오지 않는다. 배지와
/// 확인창을 데모에서 보여 줄 수 있도록, 처음 읽을 때 이지수 회원(`seed-client-2`)이
/// 사흘 전에 교환해 둔 쿠폰 한 장을 넣어 둔다. 김민수(`seed-client-1`)는 회원 앱
/// 데모의 잔액(1240P)으로 5000P 쿠폰을 교환할 수 없어 넣지 않는다.
class DemoClientCouponRepository implements ClientCouponRepository {
  const DemoClientCouponRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'trainer_renewal_coupons';

  /// 데모 쿠폰을 가진 회원.
  static const String demoCouponClientId = 'seed-client-2';

  Map<String, List<RenewalCoupon>> _read() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) return _seed();
    try {
      final Map<String, Object?> decoded = (jsonDecode(raw) as Map<Object?, Object?>)
          .cast<String, Object?>();
      return <String, List<RenewalCoupon>>{
        for (final MapEntry<String, Object?> entry in decoded.entries)
          entry.key: <RenewalCoupon>[
            for (final Object? item in (entry.value as List<Object?>?) ?? <Object?>[])
              RenewalCoupon.fromJson(
                (item! as Map<Object?, Object?>).cast<String, Object?>(),
              ),
          ],
      };
    } on Object {
      // 예전 빌드가 쓴 값 때문에 화면을 죽이지 않는다 — 빈 목록에서 시작한다.
      return <String, List<RenewalCoupon>>{};
    }
  }

  Future<void> _write(Map<String, List<RenewalCoupon>> coupons) {
    return _prefs.setString(
      _key,
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, List<RenewalCoupon>> entry in coupons.entries)
          entry.key: entry.value.map((RenewalCoupon c) => c.toJson()).toList(),
      }),
    );
  }

  static Map<String, List<RenewalCoupon>> _seed() {
    final DateTime today = todayKst();
    final DateTime issued = DateTime(today.year, today.month, today.day - 3);
    final DateTime lastDay = DateTime(issued.year, issued.month, issued.day + 30);
    return <String, List<RenewalCoupon>>{
      demoCouponClientId: <RenewalCoupon>[
        RenewalCoupon(
          id: 'cpn-demo-renewal',
          item: 'pt_renewal',
          benefit: 'PT 재등록 10,000원 할인',
          status: 'issued',
          issuedOn: issued,
          expiresOn: lastDay,
          daysLeft: 27,
        ),
      ],
    };
  }

  @override
  Future<List<RenewalCoupon>> fetchRenewalCoupons(String clientId) async {
    final DateTime today = todayKst();
    return <RenewalCoupon>[
      for (final RenewalCoupon coupon
          in _read()[clientId] ?? const <RenewalCoupon>[])
        if (coupon.usable && !today.isAfter(coupon.expiresOn)) coupon,
    ];
  }

  @override
  Future<RenewalCoupon> redeem(String clientId, String couponId) async {
    final Map<String, List<RenewalCoupon>> all = _read();
    final List<RenewalCoupon> coupons = all[clientId] ?? <RenewalCoupon>[];
    final int index = coupons.indexWhere((RenewalCoupon c) => c.id == couponId);
    if (index < 0) throw const NotFoundError(message: '쿠폰을 찾을 수 없어요.');
    final RenewalCoupon coupon = coupons[index];
    // 이미 사용됐으면 같은 결과다 — 서버와 같은 멱등 규칙.
    if (coupon.status == 'used') return coupon;
    if (!coupon.usable || todayKst().isAfter(coupon.expiresOn)) {
      throw const ServerError(statusCode: 409, message: '만료된 쿠폰이에요.');
    }
    final RenewalCoupon used = coupon.copyWith(status: 'used');
    coupons[index] = used;
    all[clientId] = coupons;
    await _write(all);
    return used;
  }
}

/// 실 백엔드 — `/trainer/clients/{member_id}/coupons`.
class DioClientCouponRepository implements ClientCouponRepository {
  const DioClientCouponRepository(this._dio);

  final Dio _dio;

  String _base(String clientId) =>
      '/trainer/clients/${Uri.encodeComponent(clientId)}/coupons';

  @override
  Future<List<RenewalCoupon>> fetchRenewalCoupons(String clientId) async {
    try {
      final Response<List<dynamic>> res = await _dio.get<List<dynamic>>(
        _base(clientId),
      );
      return <RenewalCoupon>[
        for (final dynamic item in res.data ?? const <dynamic>[])
          RenewalCoupon.fromJson(
            (item! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
      ];
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<RenewalCoupon> redeem(String clientId, String couponId) async {
    try {
      final Response<Map<String, Object?>> res = await _dio
          .post<Map<String, Object?>>(
            '${_base(clientId)}/${Uri.encodeComponent(couponId)}/redeem',
          );
      final Map<String, Object?>? data = res.data;
      if (data == null) throw const ServerError();
      return RenewalCoupon.fromJson(data);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}

/// 현재 모드에 맞는 저장소.
final clientCouponRepositoryProvider = Provider<ClientCouponRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return DemoClientCouponRepository(ref.watch(sharedPreferencesProvider));
  }
  return DioClientCouponRepository(ref.watch(dioProvider));
}, name: 'clientCouponRepository');

/// 회원 상세 배지가 읽는 사용 가능한 재등록 쿠폰. 사용 처리 뒤에 invalidate 한다.
///
/// 읽기에 실패하면 배지를 그리지 않을 뿐이다 — 쿠폰 확인은 회원 상세의 주된 일이
/// 아니라서, 여기서 오류 화면을 띄울 이유가 없다.
final clientRenewalCouponsProvider = FutureProvider.autoDispose
    .family<List<RenewalCoupon>, String>(
      (ref, String clientId) => ref
          .watch(clientCouponRepositoryProvider)
          .fetchRenewalCoupons(clientId),
      name: 'clientRenewalCoupons',
    );
