import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http_parser/http_parser.dart';
import 'package:oncare_core/request_id.dart';

import 'package:oncare_trainer/core/utils/date_format.dart';

/// 리포트 PDF 전송의 업로드·응답 대기 한도.
const Duration reportPdfTimeout = Duration(minutes: 2);

class ReportPdfSender {
  ReportPdfSender(this._dio);

  final Dio _dio;

  /// 재시도 열쇠 → 그 전송의 `client_request_id`. 성공하면 지운다.
  final Map<String, String> _requestIds = <String, String>{};

  /// 같은 요청 id 를 다시 쓸 전송인지 가르는 열쇠 — 회원·주·**보낼 문구**.
  ///
  /// 문구를 넣는 이유(#2773): 서버는 같은 `client_request_id` 에 본문이 다르면
  /// 409 로 거절한다. 예전 열쇠(회원·주)는 문구를 고쳐도 같은 id 를 써서, 첫
  /// 전송이 응답 대기 중에 끊긴 뒤(서버에는 저장됨) 문구를 고쳐 다시 보내면
  /// 새로고침 전까지 409 만 반복됐다. 이제 같은 문구의 재시도만 같은 id 를
  /// 쓰고(서버가 중복 없이 처음 메시지를 돌려준다), 고친 문구는 새 전송이다.
  /// 이미 보낸 주에 다시 보내는 것은 화면의 재전송 확인(#2288)이 묻는다.
  ///
  /// 서버처럼 앞뒤 공백을 걷어 비교한다 — 서버는 걷은 본문을 저장하고 견준다.
  static String requestKeyOf({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) => '$clientId/${ymd(weekStart)}/${message.trim()}';

  /// [requestKeyOf] 열쇠에 지금 걸려 있는 요청 id. 테스트가 재사용을 본다.
  @visibleForTesting
  String? pendingRequestId({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) =>
      _requestIds[requestKeyOf(
        clientId: clientId,
        weekStart: weekStart,
        message: message,
      )];

  /// 회원에게 함께 보이는 [message] 는 화면에서 현지화한 값을 받는다 — 서비스가
  /// 문구를 들고 있으면 영어 로케일에서도 한국어가 전송된다.
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {
    final key = requestKeyOf(
      clientId: clientId,
      weekStart: weekStart,
      message: message,
    );
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
      // 응답 대기도 같은 만큼 준다(#2773) — 기본 receiveTimeout(15초)이면 서버가
      // PDF 를 저장하고 답하기 전에 앱이 끊어, 회원은 받았는데 트레이너 화면에는
      // `전송 실패` 가 떴다.
      options: Options(
        sendTimeout: reportPdfTimeout,
        receiveTimeout: reportPdfTimeout,
      ),
    );
    if (_requestIds[key] == requestId) _requestIds.remove(key);
  }
}
