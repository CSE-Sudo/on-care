import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/search_match.dart';

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

  /// 검색 기준 좌표에서의 거리(km, 소수 첫째 자리). 거리가 없으면 null.
  ///
  /// 회원 앱 헬스장 찾기와 같은 표기(`0.4km`)다(#3223).
  String? get distanceLabel {
    final int? meters = distanceMeters;
    if (meters == null) return null;
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  TrainerGymCandidate withDistance(int? meters) => TrainerGymCandidate(
    id: id,
    name: name,
    address: address,
    registered: registered,
    lat: lat,
    lng: lng,
    phone: phone,
    distanceMeters: meters,
  );
}

/// 소속 헬스장의 부가 정보 — `GET·PUT /trainer/me/gym/profile`(#2700).
///
/// 회원 앱 헬스장 목록·상세에 그대로 나가는 값이다. 평점은 트레이너가 고치는
/// 값이 아니라 담지 않는다.
class TrainerGymInfo {
  const TrainerGymInfo({
    required this.gymId,
    required this.name,
    this.weekdayHours = '',
    this.weekendHours = '',
    this.phone = '',
    this.tags = const <String>[],
  });

  factory TrainerGymInfo.fromJson(Map<String, Object?> json) => TrainerGymInfo(
    gymId: json['gym_id']! as String,
    name: json['name'] as String? ?? '',
    weekdayHours: json['weekday_hours'] as String? ?? '',
    weekendHours: json['weekend_hours'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    tags: List<String>.unmodifiable(
      (json['tags'] as List<Object?>? ?? const <Object?>[]).whereType<String>(),
    ),
  );

  final String gymId;
  final String name;
  final String weekdayHours;
  final String weekendHours;
  final String phone;
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
    'gym_id': gymId,
    'name': name,
    'weekday_hours': weekdayHours,
    'weekend_hours': weekendHours,
    'phone': phone,
    'tags': tags,
  };
}

/// `PUT /trainer/me/gym/profile` 로 보내는 값(#2700). 화면은 네 칸을 늘 함께
/// 보낸다 — 빈 문자열·빈 목록은 "비운다"이다.
class TrainerGymInfoUpdate {
  const TrainerGymInfoUpdate({
    required this.weekdayHours,
    required this.weekendHours,
    required this.phone,
    required this.tags,
  });

  /// 서버 상한과 같다 — 태그 개수·한 태그 글자 수.
  static const int maxTags = 10;
  static const int maxTagLength = 20;

  /// 영업시간 칸·전화 칸 글자 수 상한(`gym_profiles` 컬럼 길이).
  static const int maxHoursLength = 50;
  static const int maxPhoneLength = 20;

  final String weekdayHours;
  final String weekendHours;
  final String phone;
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
    'weekday_hours': weekdayHours,
    'weekend_hours': weekendHours,
    'phone': phone,
    'tags': tags,
  };
}

abstract class TrainerProfileRepository {
  Future<TrainerProfile> fetch();

  /// 헬스장 이름·주소로 찾는다. 등록된 곳이 먼저, 카카오 결과가 뒤에 온다.
  ///
  /// [lat]·[lng] 를 주면(현재 위치를 얻은 뒤) 결과에 거리가 붙는다. 둘 다 있을
  /// 때만 보낸다 — 서버는 한쪽만 온 좌표를 거절한다.
  Future<List<TrainerGymCandidate>> searchGyms(
    String query, {
    double? lat,
    double? lng,
  });

  /// 현재 위치 주변 헬스장을 가까운 순으로(#3223). 좌표는 이 요청에만 쓰고
  /// 저장하지 않는다.
  Future<List<TrainerGymCandidate>> nearbyGyms({
    required double lat,
    required double lng,
  });

  Future<TrainerProfile> update(TrainerProfileUpdate update);

  /// [gym] 을 소속으로 정한다. 처음 고른 카카오 헬스장은 서버가 이때 목록에
  /// 넣는다.
  Future<TrainerProfile> selectGym(TrainerGymCandidate gym);

  /// 소속 헬스장의 영업시간·전화·태그(#2700). 소속이 없으면 409 오류다.
  Future<TrainerGymInfo> fetchGymInfo();

  /// 소속 헬스장 정보를 고친다. 소속 트레이너 누구나 고칠 수 있고 마지막
  /// 저장이 남는다. 프로필의 `gym.hours`·`gym.phone` 도 서버가 함께 바꾸므로
  /// 화면은 저장 뒤 [fetch] 로 프로필을 다시 읽는다.
  Future<TrainerGymInfo> updateGymInfo(TrainerGymInfoUpdate update);
}

class DioTrainerProfileRepository implements TrainerProfileRepository {
  DioTrainerProfileRepository(this._dio);

  final Dio _dio;

  @override
  Future<TrainerProfile> fetch() =>
      _profileCall(() => _dio.get<Map<String, Object?>>('/trainer/me'));

  @override
  Future<List<TrainerGymCandidate>> searchGyms(
    String query, {
    double? lat,
    double? lng,
  }) => _gymList('/trainer/gyms/search', <String, Object?>{
    'query': query,
    if (lat != null && lng != null) ...<String, Object?>{
      'lat': lat,
      'lng': lng,
    },
  });

  @override
  Future<List<TrainerGymCandidate>> nearbyGyms({
    required double lat,
    required double lng,
  }) => _gymList('/trainer/gyms/nearby', <String, Object?>{
    'lat': lat,
    'lng': lng,
  });

  Future<List<TrainerGymCandidate>> _gymList(
    String path,
    Map<String, Object?> query,
  ) async {
    try {
      final response = await _dio.get<List<Object?>>(
        path,
        queryParameters: query,
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

  @override
  Future<TrainerGymInfo> fetchGymInfo() => _gymInfoCall(
    () => _dio.get<Map<String, Object?>>('/trainer/me/gym/profile'),
  );

  @override
  Future<TrainerGymInfo> updateGymInfo(TrainerGymInfoUpdate update) =>
      _gymInfoCall(
        () => _dio.put<Map<String, Object?>>(
          '/trainer/me/gym/profile',
          data: update.toJson(),
        ),
      );

  Future<TrainerGymInfo> _gymInfoCall(
    Future<Response<Map<String, Object?>>> Function() call,
  ) async {
    try {
      final response = await call();
      final data = response.data;
      if (data == null) {
        throw const ServerError(message: '헬스장 정보 응답이 비어 있습니다.');
      }
      return TrainerGymInfo.fromJson(data);
    } on DioException catch (error) {
      throw _mapDio(error);
    }
  }

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

  /// 데모에서 고친 헬스장 정보를 헬스장 id 별로 적어 두는 키(#2700).
  static const String gymInfoStorageKey = 'demo_trainer_gym_info';

  /// 헬스장 id → 고친 헬스장 정보. 처음 읽을 때 [gymInfoStorageKey] 에서 채운다.
  Map<String, TrainerGymInfo>? _gymInfos;

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

  /// 헬스장을 가리키는 일반 낱말. 데모 헬스장은 모두 헬스장이라 이 낱말은 비교에서
  /// 뺀다 — `강남 헬스장` 은 `강남` 으로 찾고, `헬스장` 만 치면 전부 보인다. 실 API
  /// 에서 카카오가 '헬스장' 으로 주변 헬스장을 모두 주는 것과 같다. 낱말 전체가
  /// 같을 때만 뺀다(`온케어짐` 의 `짐` 은 빼지 않는다).
  static const Set<String> _genericGymWords = <String>{
    '헬스',
    '헬스장',
    '헬스클럽',
    '짐',
    '피트니스',
    'gym',
    'fitness',
  };

  /// 데모 헬스장 검색. (#3223)
  ///
  /// 이름·주소는 서버와 같은 규칙([matchesSearchQuery] — 대소문자·띄어쓰기·단어
  /// 순서 무시)으로 비교한다. 그래도 맞는 데모 헬스장이 없으면 **빈 목록 대신
  /// 데모 헬스장 전체**를 준다. 데모에는 카카오가 없어 트레이너가 자기 헬스장
  /// 이름(실제 상호)을 치면 항상 빈 목록이었고, 가입한 트레이너가 소속을 정하지
  /// 못한 채 막혔다.
  @override
  Future<List<TrainerGymCandidate>> searchGyms(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final List<String> terms = searchTerms(query);
    if (terms.isEmpty) return const <TrainerGymCandidate>[];
    final List<TrainerGymCandidate> gyms = <TrainerGymCandidate>[
      for (final TrainerGymCandidate gym in _gyms)
        if (lat != null && lng != null && gym.hasLocation)
          gym.withDistance(_haversineMeters(lat, lng, gym.lat!, gym.lng!))
        else
          gym,
    ];
    final String specific = terms
        .where((String term) => !_genericGymWords.contains(term))
        .join(' ');
    if (specific.isEmpty) return gyms;
    final List<TrainerGymCandidate> matched = <TrainerGymCandidate>[
      for (final TrainerGymCandidate gym in gyms)
        if (matchesSearchQuery(specific, <String>[gym.name, gym.address])) gym,
    ];
    return matched.isEmpty ? gyms : matched;
  }

  /// 데모 주변 찾기(#3223). 데모 헬스장은 신촌·강남 몇 곳뿐이라 반경으로 자르면
  /// 신촌 밖에서는 늘 빈 목록이 된다 — 반경 없이 전부 거리를 붙여 가까운 순으로
  /// 준다. 거리는 서버(`_haversine_m`)와 같은 계산이다.
  @override
  Future<List<TrainerGymCandidate>> nearbyGyms({
    required double lat,
    required double lng,
  }) async {
    final List<TrainerGymCandidate> out = <TrainerGymCandidate>[
      for (final TrainerGymCandidate gym in _gyms)
        if (gym.hasLocation)
          gym.withDistance(_haversineMeters(lat, lng, gym.lat!, gym.lng!)),
    ];
    out.sort(
      (TrainerGymCandidate a, TrainerGymCandidate b) =>
          a.distanceMeters!.compareTo(b.distanceMeters!),
    );
    return out;
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

  Future<Map<String, TrainerGymInfo>> _savedGymInfos() async {
    final Map<String, TrainerGymInfo>? cached = _gymInfos;
    if (cached != null) return cached;
    final Map<String, TrainerGymInfo> infos = <String, TrainerGymInfo>{};
    final String? saved = await db?.readValue(gymInfoStorageKey);
    if (saved != null) {
      try {
        final Object? decoded = jsonDecode(saved);
        if (decoded is Map<String, Object?>) {
          for (final MapEntry<String, Object?> entry in decoded.entries) {
            final Object? value = entry.value;
            if (value is Map<String, Object?> && value['gym_id'] is String) {
              infos[entry.key] = TrainerGymInfo.fromJson(value);
            }
          }
        }
      } on FormatException {
        // 깨진 값은 버리고 프로필에서 다시 만든다.
      }
    }
    return _gymInfos = infos;
  }

  @override
  Future<TrainerGymInfo> fetchGymInfo() async {
    final TrainerProfile profile = await _current();
    final String? gymId = profile.gym.id;
    if (gymId == null) {
      throw const ServerError(
        statusCode: 409,
        message: '소속 헬스장이 없습니다. 헬스장을 먼저 설정하세요.',
      );
    }
    final TrainerGymInfo? saved = (await _savedGymInfos())[gymId];
    if (saved != null) return saved;
    // 고친 적이 없으면 소속을 정할 때 복사해 둔 값에서 시작한다 — 서버도
    // 평일 영업시간·전화를 그 자리에 복사한다.
    return TrainerGymInfo(
      gymId: gymId,
      name: profile.gym.name,
      weekdayHours: profile.gym.hours,
      phone: profile.gym.phone,
    );
  }

  @override
  Future<TrainerGymInfo> updateGymInfo(TrainerGymInfoUpdate update) async {
    final TrainerGymInfo current = await fetchGymInfo();
    final TrainerGymInfo next = TrainerGymInfo(
      gymId: current.gymId,
      name: current.name,
      weekdayHours: update.weekdayHours.trim(),
      weekendHours: update.weekendHours.trim(),
      phone: update.phone.trim(),
      tags: List<String>.unmodifiable(<String>{
        for (final String tag in update.tags)
          if (tag.trim().isNotEmpty) tag.trim(),
      }),
    );
    final Map<String, TrainerGymInfo> infos = await _savedGymInfos();
    infos[next.gymId] = next;
    await db?.putValue(
      gymInfoStorageKey,
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, TrainerGymInfo> e in infos.entries)
          e.key: e.value.toJson(),
      }),
    );
    // 서버처럼 프로필의 복사본(평일 영업시간·전화)도 맞춘다.
    _profile = _profile.copyWith(
      gym: TrainerGym(
        id: _profile.gym.id,
        name: _profile.gym.name,
        address: _profile.gym.address,
        hours: next.weekdayHours,
        phone: next.phone,
        lat: _profile.gym.lat,
        lng: _profile.gym.lng,
      ),
    );
    await _persist();
    return next;
  }
}

/// 프로필의 소속 헬스장 카드가 보이는 헬스장 정보 — 태그·주말 영업시간(#2700).
///
/// 소속이 있을 때만 읽는다. 헬스장 정보를 저장하거나 소속을 바꾸면 화면이
/// 무효화한다.
final trainerGymInfoProvider = FutureProvider.autoDispose<TrainerGymInfo>((
  ref,
) {
  return ref.watch(trainerProfileRepositoryProvider).fetchGymInfo();
}, name: 'trainerGymInfo');

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

/// 두 좌표 사이 거리(m, 절삭). 백엔드 `gym_service._haversine_m` 과 같은 계산이다.
int _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371000;
  double rad(double deg) => deg * math.pi / 180;
  final double dp = rad(lat2 - lat1);
  final double dl = rad(lng2 - lng1);
  final double a =
      math.pow(math.sin(dp / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return (r * 2 * math.asin(math.sqrt(a))).toInt();
}
