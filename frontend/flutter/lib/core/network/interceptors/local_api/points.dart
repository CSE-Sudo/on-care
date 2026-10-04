// 포인트 사용처·쿠폰·식판·펫·주간 리포트 경로(/me/points/*, /me/coupons, /me/diet-tray 등).

part of '../local_api_interceptor.dart';

extension _LocalApiPoints on LocalApiInterceptor {
  //
  // 규칙은 [DemoCouponBook] 이 서버와 같게 들고 있다. 여기서는 경로와 응답 모양만
  // 잇는다. 409(잔액 부족 등)도 실서버처럼 상태코드로 돌려준다.

  Future<Response<Object?>> _pointsShop(RequestOptions options) async {
    // 끝난 주의 챌린지를 먼저 판정해 보상이 든 잔액으로 계산한다(#1789).
    await _settleChallenges();
    return _ok(options, _coupons.shopJson());
  }

  Future<Response<Object?>> _pointsExchange(RequestOptions options) async {
    final body = _jsonBody(options);
    return _couponResponse(
      options,
      _coupons.exchange(
        (body['item'] as String?) ?? '',
        option: body['option'] as String?,
        clientRequestId: body['client_request_id'] as String?,
      ),
    );
  }

  /// `GET /me/points/history`(#2146). `before` 날짜보다 앞을 받는다.
  Future<Response<Object?>> _pointsHistory(RequestOptions options) async => _ok(
    options,
    _points.historyJson(before: options.queryParameters['before'] as String?),
  );

  Future<Response<Object?>> _meCoupons(RequestOptions options) async =>
      _ok(options, _coupons.couponsJson());

  /// `GET /me/profile-pet`(#2021). 사용처 교환과 같은 원장을 본다.
  Future<Response<Object?>> _profilePet(RequestOptions options) async =>
      _ok(options, _coupons.pets.stateJson());

  /// `GET /me/weekly-reports`(#2022). 사용처 교환과 같은 원장을 본다.
  Future<Response<Object?>> _weeklyReports(RequestOptions options) async =>
      _ok(options, _coupons.reports.listJson());

  /// `GET /me/diet-tray`(#2150). 사진 기록일은 drift 에서 센다.
  Future<Response<Object?>> _dietTray(RequestOptions options) async => _ok(
    options,
    _coupons.dietTrayJson(photoDays: await _dietTrayPhotoDays()),
  );

  Future<Response<Object?>> _dietTrayClaim(RequestOptions options) async {
    final body = _jsonBody(options);
    return _couponResponse(
      options,
      _coupons.claimDietTray(
        photoDays: await _dietTrayPhotoDays(),
        clientRequestId: body['client_request_id'] as String?,
      ),
    );
  }

  /// 식판 구간(최근 28일, 오늘 포함) 안에서 식단 사진을 남긴 날 수.
  ///
  /// 서버는 사진 분석으로 저장한 끼니(`engine`)를 센다. 데모 행에는 엔진이 없어서
  /// 사진이 붙은 끼니(시드 에셋이나 방금 올린 원본)로 센다 — 손으로 적은 끼니는
  /// 둘 다 비어 있다.
  Future<int> _dietTrayPhotoDays() async {
    final String from = wireDate(_coupons.dietTrayWindowFrom());
    final String to = wireDate(_coupons.dietTrayWindowTo());
    return <String>{
      for (final row in await _db.select(_db.dietEntries).get())
        if ((row.photoAsset.isNotEmpty || row.photoBytes != null) &&
            row.date.compareTo(from) >= 0 &&
            row.date.compareTo(to) <= 0)
          row.date,
    }.length;
  }

  Future<Response<Object?>> _couponUse(RequestOptions options) async {
    // `/me/coupons/{id}/use` — 끝에서 두 번째 조각이 쿠폰 id 다.
    final List<String> segments = options.path.split('/');
    final String id = segments.length >= 2
        ? Uri.decodeComponent(segments[segments.length - 2])
        : '';
    return _couponResponse(options, _coupons.use(id));
  }

  Response<Object?> _couponResponse(
    RequestOptions options,
    DemoCouponResult result,
  ) => Response<Object?>(
    requestOptions: options,
    statusCode: result.statusCode,
    data: result.body,
  );
}
