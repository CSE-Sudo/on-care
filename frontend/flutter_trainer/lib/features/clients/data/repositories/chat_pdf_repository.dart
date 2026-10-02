import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:oncare_core/request_id.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

class TrainerChatPdfRepository {
  const TrainerChatPdfRepository(this._dio);

  final Dio _dio;

  Future<Uint8List> download(String path) async {
    final response = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }
}

final trainerChatPdfRepositoryProvider = Provider<TrainerChatPdfRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  return TrainerChatPdfRepository(ref.watch(dioProvider));
});

/// 채팅에 붙이는 사진의 전송. (#921)
///
/// 리포트 PDF 와 자리를 나눈 이유는 만들어지는 방식이 다르기 때문이다 — 리포트는
/// 앱이 그려 낸 산출물이고, 사진은 트레이너가 고른 파일이다.
///
/// 구현은 둘이다([trainerChatImageRepositoryProvider] 가 고른다):
///  * [DioTrainerChatImageRepository] — 실서버 `/chat/image`;
///  * [DemoTrainerChatImageRepository] — 데모. 로컬 대화에 바이트째 붙는다(#2493).
abstract interface class TrainerChatImageRepository {
  /// 사진 한 장을 담당 회원에게 보낸다. [message] 는 비어도 된다 — 사진만
  /// 보내는 것이 자연스러운 경우가 있다.
  Future<void> send({
    required String clientId,
    required Uint8List bytes,
    required String fileName,
    String message = '',
  });
}

/// 데모의 사진 전송. 서버 대신 드리프트 대화에 붙인다. (#2493)
class DemoTrainerChatImageRepository implements TrainerChatImageRepository {
  const DemoTrainerChatImageRepository(this._chat);

  final DriftChatRepository _chat;

  @override
  Future<void> send({
    required String clientId,
    required Uint8List bytes,
    required String fileName,
    String message = '',
  }) => _chat.sendTrainerImage(
    clientId: clientId,
    bytes: bytes,
    fileName: fileName,
    message: message,
  );
}

class DioTrainerChatImageRepository implements TrainerChatImageRepository {
  DioTrainerChatImageRepository(this._dio);

  final Dio _dio;

  /// 같은 전송 시도에 붙는 멱등키. 끊긴 네트워크로 다시 눌러도 사진이 두 번
  /// 가지 않게, 파일과 회원 조합마다 한 번만 만들고 재사용한다.
  final Map<String, String> _requestIds = <String, String>{};

  @override
  Future<void> send({
    required String clientId,
    required Uint8List bytes,
    required String fileName,
    String message = '',
  }) async {
    final key = '$clientId/$fileName/${bytes.length}';
    final requestId = _requestIds.putIfAbsent(key, newClientRequestId);
    try {
      await _dio.post<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/chat/image',
        data: FormData.fromMap(<String, Object?>{
          'message': message,
          'client_request_id': requestId,
          'image': MultipartFile.fromBytes(
            bytes,
            filename: fileName,
            // 서버는 바이트를 보고 형식을 정한다. 여기서 붙이는 값은 참고용이라
            // 실제 형식과 어긋나도 저장되는 것이 달라지지 않는다.
            contentType: MediaType('image', 'jpeg'),
          ),
        }),
        // 사진은 본문보다 크다 — 기본 sendTimeout 으로는 느린 회선에서
        // 끊긴다(리포트 PDF 전송과 같은 이유).
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
      _requestIds.remove(key);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 413 || status == 415) {
        final body = e.response?.data;
        final detail = body is Map ? body['detail'] : null;
        throw ValidationError(message: detail is String ? detail : null);
      }
      throw AppError.fromDio(e);
    }
  }
}

final trainerChatImageRepositoryProvider = Provider<TrainerChatImageRepository>(
  (ref) {
    ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
    if (ref.watch(appConfigProvider).useMockApi) {
      // 사진을 보내도 회원이 답한다(#2790).
      final chat = DemoRepliesChatRepository(
        ref.watch(appDatabaseProvider),
        replyDelay: demoChatReplyDelay,
      );
      ref.onDispose(chat.dispose);
      return DemoTrainerChatImageRepository(chat);
    }
    return DioTrainerChatImageRepository(ref.watch(dioProvider));
  },
);
