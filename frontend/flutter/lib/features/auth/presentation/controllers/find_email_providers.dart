import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/auth/data/repositories/dio_find_email_repository.dart';
import 'package:oncare/features/auth/domain/find_email.dart';

/// 아이디(가입 이메일) 찾기 요청(#3337). 데모 빌드에서도 같은 저장소를 쓴다 —
/// 요청은 기기 안 목업 API 가 받는다(가입 요청과 같은 길).
final findEmailRepositoryProvider = Provider<FindEmailRepository>(
  (ref) => DioFindEmailRepository(ref.watch(dioProvider)),
  name: 'findEmailRepository',
);
