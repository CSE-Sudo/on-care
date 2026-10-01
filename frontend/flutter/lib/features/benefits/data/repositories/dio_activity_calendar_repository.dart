import 'package:dio/dio.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/repositories/activity_calendar_repository.dart';

/// `/me/activity-calendar` 를 읽고 `/me/graph-color` 를 쓴다. (#2075, #2076)
class DioActivityCalendarRepository implements ActivityCalendarRepository {
  const DioActivityCalendarRepository(this._dio);

  final Dio _dio;

  /// 본문이 비면 실서버와 같은 오류로 바꾼다. 오류 응답은 실서버·데모(로컬 목업
  /// API, #2743) 모두 `DioException` 으로 와 아래 `AppError.fromDio` 가 받는다.
  static Map<String, Object?> _ok(Response<Map<String, Object?>> res) {
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
