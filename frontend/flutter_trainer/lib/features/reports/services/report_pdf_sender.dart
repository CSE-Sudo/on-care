import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/core/utils/request_id.dart';

class ReportPdfSender {
  ReportPdfSender(this._dio);

  final Dio _dio;
  final Map<String, String> _requestIds = <String, String>{};

  /// 회원에게 함께 보이는 [message] 는 화면에서 현지화한 값을 받는다 — 서비스가
  /// 문구를 들고 있으면 영어 로케일에서도 한국어가 전송된다.
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    final key = '$clientId/${ymd(weekStart)}';
    final requestId = _requestIds.putIfAbsent(key, newClientRequestId);
    await _dio.post<Map<String, Object?>>(
      '/trainer/clients/${Uri.encodeComponent(clientId)}/report/send-pdf',
      data: FormData.fromMap(<String, Object?>{
        'week_start': ymd(weekStart),
        'message': message,
        'client_request_id': requestId,
        'pdf': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: MediaType('application', 'pdf'),
        ),
      }),
      // 서버는 최대 8MiB PDF를 받는다. dioProvider 의 기본 sendTimeout(10초)로는
      // 느린 회선에서 업로드가 끊겨, 저장은 안 됐는데 실패만 뜨는 상태가 된다.
      options: Options(sendTimeout: const Duration(minutes: 2)),
    );
    if (_requestIds[key] == requestId) _requestIds.remove(key);
  }
}

final reportPdfSenderProvider = Provider<ReportPdfSender>((ref) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  return ReportPdfSender(ref.watch(dioProvider));
});
