import 'package:dio/dio.dart';
import 'package:oncare/features/auth/domain/find_email.dart';

/// 아이디(가입 이메일) 찾기 요청(#3337). 데모 빌드에서는 같은 요청을 기기 안
/// 목업 API(`LocalApiInterceptor`)가 받는다.
class DioFindEmailRepository implements FindEmailRepository {
  const DioFindEmailRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<FoundEmailAccount>> find({
    required String name,
    required String phone,
  }) async {
    final Response<Map<String, Object?>> res;
    try {
      res = await _dio.post<Map<String, Object?>>(
        '/auth/find-email',
        data: <String, String>{'name': name, 'phone': phone},
      );
    } on DioException catch (e) {
      throw FindEmailError(switch (e.response?.statusCode) {
        422 => FindEmailFailure.invalidInput,
        429 => FindEmailFailure.tooMany,
        _ => FindEmailFailure.temporary,
      });
    }
    final Object? accounts = res.data?['accounts'];
    // 목록이 아예 없는 응답은 "찾지 못함" 이 아니라 규약이 어긋난 것이다.
    if (accounts is! List) {
      throw const FindEmailError(FindEmailFailure.temporary);
    }
    return <FoundEmailAccount>[
      for (final Object? item in accounts) ?FoundEmailAccount.fromJson(item),
    ];
  }
}
