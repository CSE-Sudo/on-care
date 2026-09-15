import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/entities/coupon.dart';
import 'package:oncare/features/benefits/domain/entities/points_shop.dart';
import 'package:oncare/features/benefits/domain/repositories/benefits_repository.dart';

/// `/me/points/*`·`/me/coupons` 를 읽고 쓴다. (#1787)
///
/// 실모드는 백엔드로, 데모 모드는 `LocalApiInterceptor` 가 같은 경로를 받는다.
class DioBenefitsRepository implements BenefitsRepository {
  const DioBenefitsRepository(this._dio);

  final Dio _dio;

  /// 목업 인터셉터가 만든 응답은 상태코드 검사를 거치지 않고 그대로 돌아온다
  /// (`handler.resolve`). 409(잔액 부족 등)를 성공 본문으로 읽지 않도록 여기서
  /// 실서버와 같은 오류로 바꾼다.
  static T _ok<T>(Response<T> res) {
    final int status = res.statusCode ?? 0;
    if (status >= 400) {
      if (status == 404) throw const NotFoundError();
      if (status == 401 || status == 403) throw const UnauthorizedError();
      throw ServerError(statusCode: status);
    }
    final T? data = res.data;
    if (data == null) throw const ServerError();
    return data;
  }

  @override
  Future<PointsShop> fetchShop() async {
    try {
      return PointsShop.fromJson(
        _ok(await _dio.get<Map<String, Object?>>('/me/points/shop')),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<CouponExchange> exchange(
    String itemId, {
    String? clientRequestId,
  }) async {
    try {
      return CouponExchange.fromJson(
        _ok(
          await _dio.post<Map<String, Object?>>(
            '/me/points/exchange',
            data: <String, Object?>{
              'item': itemId,
              'client_request_id': ?clientRequestId,
            },
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<List<Coupon>> fetchCoupons() async {
    try {
      final List<Object?> rows = _ok(
        await _dio.get<List<Object?>>('/me/coupons'),
      );
      return <Coupon>[
        for (final Object? raw in rows)
          Coupon.fromJson((raw! as Map<Object?, Object?>).cast<String, Object?>()),
      ];
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<Coupon> useCoupon(String couponId) async {
    try {
      return Coupon.fromJson(
        _ok(
          await _dio.post<Map<String, Object?>>(
            '/me/coupons/${Uri.encodeComponent(couponId)}/use',
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }
}
