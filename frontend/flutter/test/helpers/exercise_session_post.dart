import 'package:dio/dio.dart';

/// 운동 기록 한 건을 `POST /exercise/sessions` 로 저장한다. (#2544)
///
/// 이 경로는 목록(`{"sessions": [...]}`)을 받고 목록을 돌려준다. 대부분의
/// 시험은 한 건을 넣고 그 한 건을 읽으므로, 여기서 감싸고 풀어 준다 — 기록
/// 한 칸에 `points` 를 더한 모양이다. 실패 응답은 그대로 돌려준다.
Future<Response<Map<String, Object?>>> postExerciseSession(
  Dio dio,
  Map<String, Object?> data, {
  Options? options,
}) async {
  final Response<Map<String, Object?>> res = await dio
      .post<Map<String, Object?>>(
        '/exercise/sessions',
        data: <String, Object?>{
          'sessions': <Map<String, Object?>>[data],
        },
        options: options,
      );
  final Map<String, Object?>? body = res.data;
  final Object? sessions = body?['sessions'];
  if ((res.statusCode ?? 0) >= 300 || sessions is! List || sessions.isEmpty) {
    return res;
  }
  return Response<Map<String, Object?>>(
    requestOptions: res.requestOptions,
    statusCode: res.statusCode,
    headers: res.headers,
    data: <String, Object?>{
      ...(sessions.first as Map<Object?, Object?>).cast<String, Object?>(),
      'points': body!['points'],
    },
  );
}
