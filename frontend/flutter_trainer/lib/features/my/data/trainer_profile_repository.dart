import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/features/auth/data/dtos/trainer_me_dto.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// Editable fields accepted by `PUT /v1/trainer/me`.
///
/// Dio's base URL already contains `/v1`, so the request path stays
/// `/trainer/me` rather than duplicating the API prefix.
///
/// 헬스장 이름·주소는 여기서 보내지 않는다(#2543) — 서버가 소속에서만 파생하고,
/// 보내면 409 다. 소속은 [TrainerProfileRepository.selectGym] 으로 정한다.
class TrainerProfileUpdate {
  const TrainerProfileUpdate({
    required this.phone,
    required this.specialty,
    required this.careerYears,
    required this.intro,
    required this.certifications,
  });

  final String phone;
  final String specialty;
  final int careerYears;
  final String intro;
  final List<String> certifications;

  Map<String, Object?> toJson() => <String, Object?>{
    'phone': phone,
    'specialty': specialty,
    'career_years': careerYears,
    'intro': intro,
    'certifications': certifications,
  };
}

/// 소속으로 고를 수 있는 헬스장 — `GET /trainer/gyms/search` 한 줄(#2543).
///
/// [registered] 면 이미 서버 목록에 있는 곳, 아니면 카카오에서 찾은 곳이다.
/// 고르는 경로가 둘로 갈리므로([TrainerProfileRepository.selectGym]) 화면은
/// 이 값을 몰라도 된다.
class TrainerGymCandidate {
  const TrainerGymCandidate({
    required this.id,
    required this.name,
    required this.address,
    required this.registered,
    this.lat,
    this.lng,
    this.phone = '',
    this.distanceMeters,
  });

  factory TrainerGymCandidate.fromJson(Map<String, Object?> json) =>
      TrainerGymCandidate(
        id: json['id']! as String,
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        registered: json['registered'] == true,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        phone: json['phone'] as String? ?? '',
        distanceMeters: (json['distance_meters'] as num?)?.toInt(),
      );

  final String id;
  final String name;
  final String address;
  final bool registered;
  final double? lat;
  final double? lng;
  final String phone;
  final int? distanceMeters;

  /// 지도에 핀을 찍을 수 있는가.
  bool get hasLocation => lat != null && lng != null;
}

abstract class TrainerProfileRepository {
  Future<TrainerProfile> fetch();

  /// 헬스장 이름·주소로 찾는다. 등록된 곳이 먼저, 카카오 결과가 뒤에 온다.
  Future<List<TrainerGymCandidate>> searchGyms(String query);

  Future<TrainerProfile> update(TrainerProfileUpdate update);

  /// [gym] 을 소속으로 정한다. 처음 고른 카카오 헬스장은 서버가 이때 목록에
  /// 넣는다.
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym);
}

class DioTrainerProfileRepository implements TrainerProfileRepository {
  DioTrainerProfileRepository(this._dio);

  final Dio _dio;

  @override
  Future<TrainerProfile> fetch() =>
      _profileCall(() => _dio.get<Map<String, Object?>>('/trainer/me'));

  @override
  Future<List<TrainerGymCandidate>> searchGyms(String query) async {
    try {
      final response = await _dio.get<List<Object?>>(
        '/trainer/gyms/search',
        queryParameters: <String, Object?>{'query': query},
      );
      return <TrainerGymCandidate>[
        for (final row in response.data ?? const <Object?>[])
          if (row is Map<String, Object?> && row['id'] is String)
            TrainerGymCandidate.fromJson(row),
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
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym) => _profileCall(
    () => gym.registered
        ? _dio.put<Map<String, Object?>>(
            '/trainer/me/gym',
            data: <String, Object?>{'gym_id': gym.id},
          )
        // 이름은 서버가 카카오를 다시 찾을 검색어다 — 저장값은 서버가 고른다.
        : _dio.put<Map<String, Object?>>(
            '/trainer/me/gym/kakao',
            data: <String, Object?>{'kakao_place_id': gym.id, 'name': gym.name},
          ),
  );

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
    if (code == 409 || code == 503) {
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
///
/// [db] 가 있으면 고친 프로필·소속 헬스장을 키-값 저장소에 적어 두고 다시
/// 읽는다(#2669) — 예전에는 메모리뿐이라 새로고침하면 시드 프로필로 돌아갔다.
/// 없으면(단위 테스트) 메모리에만 둔다.
class MockTrainerProfileRepository implements TrainerProfileRepository {
  /// [language] 데모의 프로필로 시작한다 (#2304).
  MockTrainerProfileRepository({this.language = DemoLanguage.ko, this.db})
    : _profile = seedTrainerProfileFor(language);

  final DemoLanguage language;

  /// 고친 값을 적어 두는 데모 저장소.
  final AppDatabase? db;
  TrainerProfile _profile;
  bool _restored = false;

  /// 고친 값을 적어 두는 키. 시드 프로필 위에 얹을 칸만 담는다.
  static const String storageKey = 'demo_trainer_profile';

  Future<TrainerProfile> _current() async {
    if (_restored) return _profile;
    _restored = true;
    final String? saved = await db?.readValue(storageKey);
    if (saved == null) return _profile;
    final Object? decoded;
    try {
      decoded = jsonDecode(saved);
    } on FormatException {
      return _profile;
    }
    if (decoded is! Map<String, Object?>) return _profile;
    String? text(Map<String, Object?> json, String key) =>
        json[key] is String ? json[key]! as String : null;
    final Object? gym = decoded['gym'];
    _profile = _profile.copyWith(
      phone: text(decoded, 'phone'),
      specialty: text(decoded, 'specialty'),
      careerYears: (decoded['career_years'] as num?)?.toInt(),
      intro: text(decoded, 'intro'),
      certifications: decoded['certifications'] is List
          ? List<String>.unmodifiable(
              (decoded['certifications']! as List<Object?>).whereType<String>(),
            )
          : null,
      gym: gym is Map<String, Object?>
          ? TrainerGym(
              id: text(gym, 'id'),
              name: text(gym, 'name') ?? '',
              address: text(gym, 'address') ?? '',
              hours: text(gym, 'hours') ?? '',
              phone: text(gym, 'phone') ?? '',
              lat: (gym['lat'] as num?)?.toDouble(),
              lng: (gym['lng'] as num?)?.toDouble(),
            )
          : null,
    );
    return _profile;
  }

  Future<void> _persist() async {
    await db?.putValue(
      storageKey,
      jsonEncode(<String, Object?>{
        'phone': _profile.phone,
        'specialty': _profile.specialty,
        'career_years': _profile.careerYears,
        'intro': _profile.intro,
        'certifications': _profile.certifications,
        'gym': <String, Object?>{
          'id': _profile.gym.id,
          'name': _profile.gym.name,
          'address': _profile.gym.address,
          'hours': _profile.gym.hours,
          'phone': _profile.gym.phone,
          'lat': _profile.gym.lat,
          'lng': _profile.gym.lng,
        },
      }),
    );
  }

  /// 데모 검색 결과. 앞 둘은 등록된 헬스장, 뒤는 카카오에서 찾은 곳이다 —
  /// 데모에서도 두 경로가 모두 보이게 한다. 좌표는 지도 핀용이다.
  ///
  /// 셋 다 가상 헬스장이다. 가상 트레이너(김태오)가 실재 업체를 소속으로 고르는
  /// 장면이 되지 않도록 카카오 결과 자리에도 실재 상호·전화를 쓰지 않는다(#2811).
  List<TrainerGymCandidate> get _gyms => <TrainerGymCandidate>[
    TrainerGymCandidate(
      id: kDemoTrainerGymId,
      name: seedTrainerProfileFor(language).gym.name,
      address: seedTrainerProfileFor(language).gym.address,
      registered: true,
      lat: kDemoTrainerGymLat,
      lng: kDemoTrainerGymLng,
      phone: '02-1234-5678',
    ),
    TrainerGymCandidate(
      id: 'gym-2',
      name: language.isEnglish ? 'OnCare Gym Gangnam' : '온케어짐 강남점',
      address: language.isEnglish
          ? '396 Gangnam-daero, Gangnam-gu, Seoul'
          : '서울 강남구 강남대로 396',
      registered: true,
      lat: 37.4979,
      lng: 127.0276,
      phone: '02-9876-5432',
    ),
    TrainerGymCandidate(
      id: 'gym-demo-yeonhui',
      name: language.isEnglish ? 'OnCare Yeonhui Studio' : '온케어 연희 스튜디오',
      address: language.isEnglish
          ? '25 Yeonhui-ro, Seodaemun-gu, Seoul'
          : '서울 서대문구 연희로 25',
      registered: false,
      lat: 37.5665,
      lng: 126.9300,
    ),
  ];

  @override
  Future<TrainerProfile> fetch() => _current();

  @override
  Future<List<TrainerGymCandidate>> searchGyms(String query) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return const <TrainerGymCandidate>[];
    return <TrainerGymCandidate>[
      for (final TrainerGymCandidate gym in _gyms)
        if (gym.name.toLowerCase().contains(q) ||
            gym.address.toLowerCase().contains(q) ||
            // 데모에서 무엇을 쳐도 결과가 보이게 '헬스'·'gym' 은 모두 맞춘다.
            q.contains('헬스') ||
            q.contains('gym'))
          gym,
    ];
  }

  @override
  Future<TrainerProfile> update(TrainerProfileUpdate update) async {
    await _current();
    _profile = _profile.copyWith(
      phone: update.phone,
      specialty: update.specialty,
      // 숫자로 남긴다 — 단위는 화면이 로케일에 맞춰 붙인다 (#2304).
      careerYears: update.careerYears,
      intro: update.intro,
      certifications: List<String>.unmodifiable(update.certifications),
    );
    await _persist();
    return _profile;
  }

  @override
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym) async {
    await _current();
    _profile = _profile.copyWith(
      gym: TrainerGym(
        id: gym.id,
        name: gym.name,
        address: gym.address,
        // 카카오는 영업시간을 주지 않는다 — 서버와 같게 빈 값이다.
        hours: gym.id == kDemoTrainerGymId ? _profile.gym.hours : '',
        phone: gym.phone,
        lat: gym.lat,
        lng: gym.lng,
      ),
    );
    await _persist();
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
      db: ref.watch(appDatabaseProvider),
    );
  }
  return DioTrainerProfileRepository(ref.watch(dioProvider));
}, name: 'trainerProfileRepository');
