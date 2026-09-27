import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// Editable fields accepted by `PUT /v1/trainer/me`.
///
/// Dio's base URL already contains `/v1`, so the request path stays
/// `/trainer/me` rather than duplicating the API prefix.
class TrainerProfileUpdate {
  const TrainerProfileUpdate({
    required this.phone,
    required this.specialty,
    required this.careerYears,
    required this.intro,
    required this.certifications,
    this.gymName,
    this.gymAddress,
    this.gymHours,
    this.gymPhone,
  });

  final String phone;
  final String specialty;
  final int careerYears;
  final String intro;
  final List<String> certifications;
  final String? gymName;
  final String? gymAddress;
  final String? gymHours;
  final String? gymPhone;

  Map<String, Object?> toJson() => <String, Object?>{
    'phone': phone,
    'specialty': specialty,
    'career_years': careerYears,
    'intro': intro,
    'certifications': certifications,
    if (gymName != null) 'gym_name': gymName,
    if (gymAddress != null) 'gym_address': gymAddress,
    if (gymHours != null) 'gym_hours': gymHours,
    if (gymPhone != null) 'gym_phone': gymPhone,
  };
}

class TrainerGymChoice {
  const TrainerGymChoice({
    required this.id,
    required this.name,
    required this.address,
    this.hours = '',
    this.phone = '',
  });

  final String id;
  final String name;
  final String address;
  final String hours;
  final String phone;
}

abstract class TrainerProfileRepository {
  Future<TrainerProfile> fetch();

  Future<List<TrainerGymChoice>> listGyms();

  Future<TrainerProfile> update(TrainerProfileUpdate update);

  Future<TrainerProfile> setGym(String gymId);

  Future<TrainerProfile> clearGym();
}

class DioTrainerProfileRepository implements TrainerProfileRepository {
  DioTrainerProfileRepository(this._dio);

  final Dio _dio;

  @override
  Future<TrainerProfile> fetch() =>
      _profileCall(() => _dio.get<Map<String, Object?>>('/trainer/me'));

  @override
  Future<List<TrainerGymChoice>> listGyms() async {
    try {
      final response = await _dio.get<List<Object?>>('/gyms');
      return <TrainerGymChoice>[
        for (final row in response.data ?? const <Object?>[])
          if (row is Map<String, Object?> && row['id'] is String)
            TrainerGymChoice(
              id: row['id']! as String,
              name: row['name'] as String? ?? '',
              address: row['address'] as String? ?? '',
              hours: row['weekday_hours'] as String? ?? '',
              phone: row['phone'] as String? ?? '',
            ),
      ];
    } on DioException catch (error) {
      throw _mapDio(error);
    }
  }

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) => _profileCall(
    () => _dio.put<Map<String, Object?>>('/trainer/me', data: update.toJson()),
  );

  @override
  Future<TrainerProfile> setGym(String gymId) => _profileCall(
    () => _dio.put<Map<String, Object?>>(
      '/trainer/me/gym',
      data: <String, Object?>{'gym_id': gymId},
    ),
  );

  @override
  Future<TrainerProfile> clearGym() =>
      _profileCall(() => _dio.delete<Map<String, Object?>>('/trainer/me/gym'));

  Future<TrainerProfile> _profileCall(
    Future<Response<Map<String, Object?>>> Function() call,
  ) async {
    try {
      final response = await call();
      final data = response.data;
      if (data == null) {
        throw const ServerError(message: '프로필 응답이 비어 있습니다.');
      }
      return trainerProfileFromJson(data);
    } on DioException catch (error) {
      throw _mapDio(error);
    }
  }

  AppError _mapDio(DioException error) {
    final detail = _detail(error.response?.data);
    final code = error.response?.statusCode;
    if (code == 400 || code == 422) {
      return ValidationError(message: detail ?? '입력값을 확인해 주세요.');
    }
    if (code == 409) {
      return ServerError(
        statusCode: code,
        message: detail ?? '현재 소속 상태와 충돌합니다.',
      );
    }
    if (code == 404) {
      return NotFoundError(message: detail ?? '헬스장을 찾을 수 없습니다.');
    }
    return AppError.fromDio(error);
  }

  String? _detail(Object? data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    return null;
  }
}

/// Stateful mock with the same mutation contract as the real repository.
class MockTrainerProfileRepository implements TrainerProfileRepository {
  /// [language] 데모의 프로필로 시작한다 (#2304).
  MockTrainerProfileRepository({this.language = DemoLanguage.ko})
    : _profile = seedTrainerProfileFor(language);

  final DemoLanguage language;
  TrainerProfile _profile;

  @override
  Future<TrainerProfile> fetch() async => _profile;

  @override
  Future<List<TrainerGymChoice>> listGyms() async => <TrainerGymChoice>[
    TrainerGymChoice(
      id: 'gym-1',
      name: language.isEnglish ? 'OnCare Gym Sinchon' : '온케어짐 신촌점',
      address: language.isEnglish ? 'Seodaemun-gu, Seoul' : '서울 서대문구',
      hours: '06:00 – 23:00',
      phone: '02-1234-5678',
    ),
    TrainerGymChoice(
      id: 'gym-2',
      name: language.isEnglish ? 'OnCare Gym Gangnam' : '온케어짐 강남점',
      address: language.isEnglish ? 'Gangnam-gu, Seoul' : '서울 강남구',
      hours: '06:00 – 24:00',
      phone: '02-9876-5432',
    ),
  ];

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) async {
    _profile = _profile.copyWith(
      phone: update.phone,
      specialty: update.specialty,
      // 숫자로 남긴다 — 단위는 화면이 로케일에 맞춰 붙인다 (#2304).
      careerYears: update.careerYears,
      intro: update.intro,
      certifications: List<String>.unmodifiable(update.certifications),
      gym: update.gymName == null
          ? _profile.gym
          : TrainerGym(
              name: update.gymName!,
              address: update.gymAddress ?? '',
              hours: update.gymHours ?? '',
              phone: update.gymPhone ?? '',
            ),
    );
    return _profile;
  }

  @override
  Future<TrainerProfile> setGym(String gymId) async {
    TrainerGymChoice? choice;
    for (final item in await listGyms()) {
      if (item.id == gymId) {
        choice = item;
        break;
      }
    }
    if (choice == null) {
      throw const NotFoundError(message: '헬스장을 찾을 수 없습니다.');
    }
    _profile = _profile.copyWith(
      gym: TrainerGym(
        id: gymId,
        name: choice.name,
        address: choice.address,
        hours: choice.hours,
        phone: choice.phone,
      ),
    );
    return _profile;
  }

  @override
  Future<TrainerProfile> clearGym() async {
    _profile = _profile.copyWith(
      gym: const TrainerGym(name: '', address: '', hours: '', phone: ''),
    );
    return _profile;
  }
}

final trainerProfileRepositoryProvider = Provider<TrainerProfileRepository>((
  ref,
) {
  ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
  final config = ref.watch(appConfigProvider);
  if (config.useMockApi) {
    return MockTrainerProfileRepository(
      language: ref.watch(demoLanguageProvider),
    );
  }
  return DioTrainerProfileRepository(ref.watch(dioProvider));
}, name: 'trainerProfileRepository');

final trainerGymChoicesProvider =
    FutureProvider.autoDispose<List<TrainerGymChoice>>((ref) {
      return ref.watch(trainerProfileRepositoryProvider).listGyms();
    }, name: 'trainerGymChoices');
