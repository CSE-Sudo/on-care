import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/domain/entities/signup_consent.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/consent_repository.dart';

/// 실서버 동의 상태. (#2819)
class DioConsentRepository implements ConsentRepository {
  DioConsentRepository(this._dio);

  final Dio _dio;

  @override
  Future<bool> submit(List<String> consents) async {
    final res = await _dio.post<Map<String, Object?>>(
      '/users/me/consents',
      data: <String, Object?>{'consents': consents},
    );
    return res.data?['consent_required'] == true;
  }
}

/// 데모 동의 상태. 데모 계정은 동의를 마친 것으로 둔다 — 데모 진입마다 동의
/// 화면이 끼면 시연 흐름이 끊긴다. 저장은 서버와 같은 필수 규칙만 본다.
class MockConsentRepository implements ConsentRepository {
  const MockConsentRepository();

  @override
  Future<bool> submit(List<String> consents) async {
    if (!TrainerSignupConsent.hasAllRequired(consents.toSet())) {
      throw ArgumentError.value(consents, 'consents', 'consent_required');
    }
    return false;
  }
}

/// [AppConfig] 로 동의 저장소를 고른다 — 인증 저장소와 같은 기준이다.
final consentRepositoryProvider = Provider<ConsentRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return const MockConsentRepository();
  }
  return DioConsentRepository(ref.watch(dioProvider));
}, name: 'consentRepository');
