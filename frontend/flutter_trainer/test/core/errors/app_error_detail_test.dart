import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';

/// [AppError.fromDio] 가 서버 사유를 문자열·객체 두 형식 모두에서 읽는지(#2911).
DioException _bad(int status, Object? body) {
  final RequestOptions options = RequestOptions(path: '/trainer/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    message: 'technical dio text',
    response: Response<Object?>(
      requestOptions: options,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  test('문자열 detail 은 기존처럼 메시지가 된다', () {
    final AppError error = AppError.fromDio(
      _bad(404, <String, Object?>{'detail': '고객을 찾을 수 없습니다.'}),
    );

    expect(error, isA<NotFoundError>());
    expect(error.message, '고객을 찾을 수 없습니다.');
  });

  test('객체 detail 은 message 가 메시지가 된다', () {
    final AppError error = AppError.fromDio(
      _bad(403, <String, Object?>{
        'detail': <String, Object?>{
          'code': 'trainer_not_approved',
          'message': '승인을 기다리고 있어요.',
        },
      }),
    );

    expect(error, isA<ForbiddenError>());
    expect(error.message, '승인을 기다리고 있어요.');
  });

  test('사유가 없으면 Dio 문구로 물러난다', () {
    final AppError error = AppError.fromDio(
      _bad(422, <String, Object?>{
        'detail': <Object?>[
          <String, Object?>{'msg': 'field required'},
        ],
      }),
    );

    expect(error.message, 'technical dio text');
  });
}
