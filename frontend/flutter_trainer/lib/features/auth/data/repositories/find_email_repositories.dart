import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/auth/domain/repositories/find_email_repository.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';
import 'package:oncare_ui/oncare_ui.dart' show AppInputRules;

/// 실 서버 이메일 찾기(#3439). 트레이너 전용 경로를 부른다 — 회원 경로
/// (`/auth/find-email`)는 회원 계정만 찾는다.
class DioFindEmailRepository implements FindEmailRepository {
  const DioFindEmailRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<FoundEmailAccount>> find({
    required String name,
    required String phone,
  }) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '/auth/trainer/find-email',
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

/// 데모 빌드의 이메일 찾기(#3439). 서버와 같은 규칙으로 데모 트레이너
/// ([seedTrainerProfile]) 만 찾는다 — 이름(앞뒤 공백·대소문자 무시)과 번호(숫자만
/// 비교)가 모두 맞으면 가린 이메일 하나, 아니면 빈 목록이다.
class MockFindEmailRepository implements FindEmailRepository {
  const MockFindEmailRepository();

  @override
  Future<List<FoundEmailAccount>> find({
    required String name,
    required String phone,
  }) async {
    final String wantedPhone = _digits(phone);
    if (name.trim().isEmpty ||
        wantedPhone.length != AppInputRules.phoneDigits ||
        !wantedPhone.startsWith('010')) {
      throw const FindEmailError(FindEmailFailure.invalidInput);
    }
    const TrainerProfile demo = seedTrainerProfile;
    final bool matches =
        demo.name.trim().toLowerCase() == name.trim().toLowerCase() &&
        _digits(demo.phone) == wantedPhone;
    return <FoundEmailAccount>[
      if (matches) FoundEmailAccount(maskedEmail: maskEmail(demo.email)),
    ];
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  /// 서버(`mask_email`)와 같은 가림 — 앞 두 글자와 도메인만 남긴다. 로컬 부분이
  /// 두 글자 이하면 덜 보여 주고, `***` 는 늘 세 글자다.
  static String maskEmail(String address) {
    final int at = address.indexOf('@');
    if (at < 0) return '***';
    final String local = address.substring(0, at);
    final int visible = (local.length - 1).clamp(0, 2);
    return '${local.substring(0, visible)}***${address.substring(at)}';
  }
}

/// 지금 빌드의 이메일 찾기 리포지토리 — 데모면 목업, 아니면 실 서버.
final findEmailRepositoryProvider = Provider<FindEmailRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    return const MockFindEmailRepository();
  }
  return DioFindEmailRepository(ref.watch(dioProvider));
}, name: 'findEmailRepository');
