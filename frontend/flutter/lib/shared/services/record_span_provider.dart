import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';

/// 회원이 식단·운동을 **처음 남긴 날**. `GET /me/records/span` (#2236)
///
/// `전체` 그래프가 어디서부터 그릴지를 정하는 값이다(#2079). 식단과 운동이 각자
/// 제 첫 기록일을 가진다 — 한쪽만 기록해 온 회원의 빈 칸이 다른 쪽 때문에
/// 늘어나지 않게 한다. 기록이 없으면 null 이고, 그때 `전체` 는 오늘 하루만
/// 그린다.
class RecordSpan {
  const RecordSpan({this.dietFirstDate, this.exerciseFirstDate});

  factory RecordSpan.fromJson(Map<String, Object?> json) => RecordSpan(
    dietFirstDate: _date(json['diet_first_date']),
    exerciseFirstDate: _date(json['exercise_first_date']),
  );

  /// 기록이 하나도 없는 회원(또는 아직 못 읽은 상태).
  static const RecordSpan empty = RecordSpan();

  final DateTime? dietFirstDate;
  final DateTime? exerciseFirstDate;

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

/// 기록 시작일. 실패하면 [RecordSpan.empty] 로 떨어진다 — 시작일 하나 때문에
/// 그래프가 통째로 오류 화면이 되지 않게 한다(그때 `전체` 는 오늘만 그린다).
final recordSpanProvider = FutureProvider<RecordSpan>((ref) async {
  final Dio dio = ref.watch(dioProvider);
  final Response<Map<String, Object?>> res = await dio
      .get<Map<String, Object?>>('/me/records/span');
  final Map<String, Object?>? body = res.data;
  return body == null ? RecordSpan.empty : RecordSpan.fromJson(body);
}, name: 'recordSpan');
