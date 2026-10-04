/// 트레이너 채팅 사진의 멱등키 — 한마디가 다르면 다른 키, 409 뒤에는 새 키. (#3095)
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/clients/data/repositories/chat_pdf_repository.dart';

void main() {
  late Dio dio;
  late DioTrainerChatImageRepository repository;
  late List<String?> sentIds;
  late int? failNextWith;

  setUp(() {
    sentIds = <String?>[];
    failNextWith = null;
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final FormData form = options.data as FormData;
          sentIds.add(
            form.fields
                .where(
                  (MapEntry<String, String> f) => f.key == 'client_request_id',
                )
                .map((MapEntry<String, String> f) => f.value)
                .firstOrNull,
          );
          final int? status = failNextWith;
          failNextWith = null;
          if (status != null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: status == 0
                    ? DioExceptionType.receiveTimeout
                    : DioExceptionType.badResponse,
                response: status == 0
                    ? null
                    : Response<Object?>(
                        requestOptions: options,
                        statusCode: status,
                        data: <String, Object?>{
                          'detail': '같은 client_request_id에 다른 메시지를 보낼 수 없습니다.',
                        },
                      ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Map<String, Object?>>(
              requestOptions: options,
              statusCode: 201,
              data: const <String, Object?>{},
            ),
          );
        },
      ),
    );
    repository = DioTrainerChatImageRepository(dio);
  });

  tearDown(() => dio.close());

  final Uint8List photo = Uint8List.fromList(<int>[1, 2, 3, 4]);

  Future<void> send(String message) => repository.send(
    clientId: 'user-1',
    bytes: photo,
    fileName: 'pose.jpg',
    message: message,
  );

  test('응답을 잃은 뒤 같은 한마디로 다시 보내면 같은 키다', () async {
    failNextWith = 0;
    await expectLater(send('자세 보세요'), throwsA(anything));
    await send('자세 보세요');
    expect(sentIds[0], isNotNull);
    expect(sentIds[1], sentIds[0]);
  });

  test('한마디를 고쳐 다시 보내면 새 키다', () async {
    failNextWith = 0;
    await expectLater(send('자세 보세요'), throwsA(anything));
    await send('이 자세 참고해 주세요');
    expect(sentIds[1], isNot(sentIds[0]));
  });

  test('409 는 ChatImageAlreadySent 이고 그 키를 버린다', () async {
    failNextWith = 409;
    await expectLater(send('자세 보세요'), throwsA(isA<ChatImageAlreadySent>()));
    await send('자세 보세요');
    expect(sentIds[1], isNot(sentIds[0]));
  });

  test('열쇠에 한마디가 들어간다', () {
    expect(
      DioTrainerChatImageRepository.requestKeyOf('u', 'a.jpg', 4, '하나'),
      isNot(DioTrainerChatImageRepository.requestKeyOf('u', 'a.jpg', 4, '둘')),
    );
  });

  test('파일 이름·한마디의 / 가 다른 조합과 같은 열쇠를 만들지 않는다', () {
    expect(
      DioTrainerChatImageRepository.requestKeyOf('u', 'a/1', 4, '2'),
      isNot(DioTrainerChatImageRepository.requestKeyOf('u', 'a', 1, '4/2')),
    );
  });
}
