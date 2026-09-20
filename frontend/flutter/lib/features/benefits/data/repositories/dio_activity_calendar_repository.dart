import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/repositories/activity_calendar_repository.dart';

/// `/me/activity-calendar` 를 읽고 `/me/graph-color` 를 쓴다. (#2075, #2076)
class DioActivityCalendarRepository implements ActivityCalendarRepository {
  const DioActivityCalendarRepository(this._dio);

  final Dio _dio;

  /// 목업 인터셉터가 만든 409 응답은 상태코드 검사를 거치지 않고 돌아온다 —
  /// 성공 본문으로 읽지 않도록 실서버와 같은 오류로 바꾼다(보호권 저장소와 같다).
  static Map<String, Object?> _ok(Response<Map<String, Object?>> res) {
    final int status = res.statusCode ?? 0;
    if (status >= 400) {
      if (status == 404) throw const NotFoundError();
      if (status == 401 || status == 403) throw const UnauthorizedError();
      throw ServerError(statusCode: status);
    }
    final Map<String, Object?>? data = res.data;
    if (data == null) throw const ServerError();
    return data;
  }

  @override
  Future<ActivityCalendar> fetch({DateTime? from, DateTime? to}) async {
    try {
      return ActivityCalendar.fromJson(
        _ok(
          await _dio.get<Map<String, Object?>>(
            '/me/activity-calendar',
            queryParameters: <String, Object?>{
              if (from != null) 'from': _ymd(from),
              if (to != null) 'to': _ymd(to),
            },
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<GraphColorState> selectColor(String color) async {
    try {
      return GraphColorState.fromJson(
        _ok(
          await _dio.put<Map<String, Object?>>(
            '/me/graph-color',
            data: <String, Object?>{'color': color},
          ),
        ),
      );
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
