import 'dart:async';

import 'package:dio/dio.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/active_polling_stream.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/data/dtos/client_dtos.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_diet_entry.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_period.dart';
import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/clients/domain/repositories/client_data_refresher.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// 로스터 한 쪽의 인원. 서버 기본값과 같다(#980).
const int rosterPageSize = 50;

/// 이어 받을 쪽 수의 상한 — 담당 회원 2,500명이면 어떤 트레이너의 명단도 덮는다.
/// 서버가 같은 쪽을 계속 돌려주는 상황에서 고리가 멈추지 않는 것만 막는다.
const int _rosterPageLimit = 50;

/// Reads a trainer's clients + their diet/history from the FastAPI backend.
/// Selected when `USE_MOCK_API=false` (see [clientRepositoryProvider]).
///
/// Reads revalidate when their screen subscribes and when the app/browser
/// returns to the foreground. Roster mutations have no
/// backend endpoint (the roster is derived from trainer↔member links), so
/// they throw [UnsupportedError] — the demo-only add/activate UI is hidden
/// in real-API mode.
class DioClientRepository implements ClientRepository, ClientDataRefresher {
  DioClientRepository(
    this._dio, {
    this.pollInterval = const Duration(seconds: 30),
  });

  final Dio _dio;

  /// 명단과 그 회원의 기록을 다시 읽는 주기.
  ///
  /// 회원이 식단 사진을 올리거나 운동을 마치는 것은 트레이너가 누르는 일이
  /// 아니라, 여기서 따라잡지 않으면 옆에 띄워 둔 화면이 낡은 값을 계속
  /// 보여 준다 — 코칭은 그 값을 보면서 하는 일이라 값이 낡으면 판단이
  /// 낡는다(#918). 채팅(3초)만큼 잦을 이유는 없다. 기록은 초 단위가 아니라
  /// 분 단위로 쌓인다.
  final Duration pollInterval;

  final StreamController<String?> _refreshes =
      StreamController<String?>.broadcast(sync: true);

  @override
  bool get supportsRosterMutations => false;

  @override
  Stream<List<TrainerClient>> watchClients() =>
      activePollingStream<List<TrainerClient>>(
        load: _fetchClients,
        interval: pollInterval,
        refreshes: _refreshesFor(null),
      );

  /// The roster endpoint carries no chat-recency signal, so priority
  /// ordering falls back to the server's own order. Emitting an empty map
  /// (not nothing) lets the ordering resolve immediately.
  @override
  Stream<Map<String, DateTime>> watchLastChatAt() =>
      Stream<Map<String, DateTime>>.value(const <String, DateTime>{});

  @override
  Stream<List<ClientDietEntry>> watchDiet(String clientId) =>
      activePollingStream<List<ClientDietEntry>>(
        load: () => _fetchDiet(clientId),
        interval: pollInterval,
        refreshes: _refreshesFor(clientId),
      );

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      activePollingStream<List<RoutineHistoryEntry>>(
        load: () => _fetchHistory(clientId),
        interval: pollInterval,
        refreshes: _refreshesFor(clientId),
      );

  Stream<void> _refreshesFor(String? clientId) => _refreshes.stream
      .where(
        (String? target) =>
            target == null || clientId == null || target == clientId,
      )
      .map((_) {});

  @override
  void refreshAllClientData() => _refreshes.add(null);

  @override
  void refreshClientData(String clientId) => _refreshes.add(clientId);

  @override
  Future<ClientExerciseWeek> fetchExerciseWeek(
    String clientId, {
    DateTime? weekStart,
  }) async {
    final path =
        '/trainer/clients/${Uri.encodeComponent(clientId)}/exercise-week';
    try {
      final response = await _dio.get<Map<String, Object?>>(
        path,
        queryParameters: weekStart == null
            ? null
            : <String, String>{'week_start': ymd(clientMondayOf(weekStart))},
      );
      return ClientExerciseWeek.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  /// 일별 식단 집계를 **리포트 응답**에서 만든다.
  ///
  /// 끼니 목록(`/diet?date=`)을 날마다 부르면 한 달에 서른 번 넘게 오간다.
  /// 리포트는 한 주의 일별 칼로리·나트륨·당류를 한 번에 주므로, 한 달이라도
  /// 요청은 다섯 번 남짓이다. 두 경로 모두 같은 `diet_entries` 를 읽는다.
  @override
  Future<String> fetchDietAdvice(String clientId, ClientPeriod period) async {
    final String wire = switch (period) {
      ClientPeriod.today => 'today',
      ClientPeriod.week => 'week',
      ClientPeriod.month => 'all',
    };
    try {
      final response = await _dio.get<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/diet-advice',
        queryParameters: <String, Object?>{'period': wire},
      );
      return (response.data?['message'] as String?) ?? '';
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<String> fetchExerciseAdvice(
    String clientId,
    ClientPeriod period,
  ) async {
    // 식단 조언과 같은 계약이다(#1017, #1025) — 두 카드가 한 화면에 나란히
    // 서므로 같은 이름으로 같은 것을 묻는다.
    final String wire = switch (period) {
      ClientPeriod.today => 'today',
      ClientPeriod.week => 'week',
      ClientPeriod.month => 'all',
    };
    try {
      final response = await _dio.get<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/exercise-advice',
        queryParameters: <String, Object?>{'period': wire},
      );
      return (response.data?['message'] as String?) ?? '';
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<ClientDietPeriod> fetchDietPeriod(
    String clientId,
    ClientDateRange range,
  ) async {
    // 기간을 **한 번에** 받는다(#2236). 예전에는 주간 리포트를 주 수만큼
    // 불렀는데, `전체` 가 모든 기록을 그리게 되면서(#2079) 해가 바뀐 회원에게
    // 쉰 번이 넘는 왕복이 됐다. 회원 앱(`GET /diet/days`)과 같은 집계다.
    try {
      final response = await _dio.get<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/diet/days',
        queryParameters: <String, String>{
          'from': ymd(range.from),
          'to': ymd(range.to),
        },
      );
      final Map<String, Object?> body = response.data ?? const <String, Object?>{};
      final Map<String, ClientDietDay> byDate = <String, ClientDietDay>{};
      for (final Object? row
          in (body['days'] as List<Object?>?) ?? const <Object?>[]) {
        if (row is! Map<String, Object?>) continue;
        final DateTime? date = DateTime.tryParse(row['date'] as String? ?? '');
        if (date == null) continue;
        final DateTime day = DateTime(date.year, date.month, date.day);
        double number(String key) => (row[key] as num?)?.toDouble() ?? 0;
        byDate[ymd(day)] = ClientDietDay(
          date: day,
          calories: (row['total_calories'] as num?)?.toInt() ?? 0,
          sodiumMg: (row['total_sodium_mg'] as num?)?.toInt() ?? 0,
          sugarG: number('total_sugar_g'),
          carbsG: number('carbs_g'),
          proteinG: number('protein_g'),
          fatG: number('fat_g'),
        );
      }
      return ClientDietPeriod(
        range: range,
        days: <ClientDietDay>[
          for (final DateTime date in clientRangeDates(range))
            byDate[ymd(date)] ?? ClientDietDay(date: date),
        ],
      );
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<ClientRecordSpan> fetchRecordSpan(String clientId) async {
    try {
      final response = await _dio.get<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/records/span',
      );
      final Map<String, Object?>? body = response.data;
      return body == null
          ? ClientRecordSpan.empty
          : ClientRecordSpan.fromJson(body);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  /// 로스터 전체. 서버가 한 쪽씩 주므로(#980) 명단이 끝날 때까지 이어 받는다.
  ///
  /// 화면에 "더 보기" 를 두지 않는 이유: 담당 회원 목록은 사이드바 개수·검색·차트가
  /// 모두 **전체**를 전제로 읽는 자리라, 절반만 들고 있으면 트레이너가 명단이 잘린 줄
  /// 모른 채 빠진 회원을 찾게 된다. 상한은 한 응답이 인원수만큼 커지는 것을 막는
  /// 장치이고, 여기서는 그 쪽들을 이어 붙여 같은 목록을 만든다. 트레이너 한 명이
  /// 감당하는 인원만큼만 도는 고리다.
  Future<List<TrainerClient>> _fetchClients() async {
    final List<TrainerClient> all = <TrainerClient>[];
    String? afterId;
    // 명단 길이에 상한을 두지 않되, 서버가 같은 쪽을 계속 주는 상황에서 매달리지는
    // 않도록 쪽 수를 넉넉히 제한한다.
    for (int page = 0; page < _rosterPageLimit; page++) {
      final List<TrainerClient> rows = await _getList(
        '/trainer/clients',
        trainerClientFromJson,
        query: <String, Object?>{'limit': rosterPageSize, 'after_id': ?afterId},
      );
      all.addAll(rows);
      if (rows.length < rosterPageSize) break;
      afterId = rows.last.id;
    }
    return List<TrainerClient>.unmodifiable(all);
  }

  Future<List<ClientDietEntry>> _fetchDiet(String clientId) => _getList(
    '/trainer/clients/${Uri.encodeComponent(clientId)}/diet',
    clientDietEntryFromJson,
  );

  @override
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  ) async {
    // 주 단위 응답의 `sessions` 에 그날 한 운동이 실려 온다. 그 주를 한 번 읽어
    // 해당 요일만 고른다 — 날짜별 엔드포인트를 따로 두지 않아도 된다.
    final ClientExerciseWeek week = await fetchExerciseWeek(
      clientId,
      weekStart: clientMondayOf(date),
    );
    final int index = date.weekday - 1;
    if (index < 0 || index >= week.dayLabels.length) {
      return const <ClientExerciseItem>[];
    }
    return week.itemsByDayLabel[week.dayLabels[index]] ??
        const <ClientExerciseItem>[];
  }

  @override
  Future<List<ClientDietEntry>> fetchDietOn(String clientId, DateTime date) =>
      // 같은 엔드포인트가 `date` 를 받는다 — 날짜를 주지 않으면 오늘이다.
      _getList(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/diet',
        clientDietEntryFromJson,
        query: <String, String>{'date': ymd(date)},
      );

  Future<List<RoutineHistoryEntry>> _fetchHistory(String clientId) => _getList(
    '/trainer/clients/${Uri.encodeComponent(clientId)}/history',
    routineHistoryEntryFromJson,
  );

  @override
  Future<RoutineHistoryEntry> updateHistoryFeedback(
    String clientId,
    String historyId,
    String feedback,
  ) async {
    final String path =
        '/trainer/clients/${Uri.encodeComponent(clientId)}/history/'
        '${Uri.encodeComponent(historyId)}/feedback';
    try {
      final Response<Map<String, Object?>> response = await _dio.put(
        path,
        data: <String, Object?>{'feedback': feedback.trim()},
      );
      final Map<String, Object?>? data = response.data;
      if (data == null) throw const FormatException('Missing history row.');
      return routineHistoryEntryFromJson(data);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<MemberHealthProfile> fetchHealthProfile(String clientId) async {
    try {
      final response = await _dio.get<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/health-profile',
      );
      return MemberHealthProfile.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  @override
  Future<MemberHealthProfile> updateHealthProfile(
    String clientId,
    Map<String, Object?> values,
  ) async {
    try {
      final response = await _dio.put<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(clientId)}/health-profile',
        data: values,
      );
      return MemberHealthProfile.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
  }

  /// GETs a JSON array and maps each element with [fromJson]. Transport /
  /// HTTP failures (incl. 404 for a client that isn't this trainer's)
  /// surface as a typed [AppError].
  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, Object?>) fromJson, {
    Map<String, Object?>? query,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(path, queryParameters: query);
      final data = res.data ?? const <dynamic>[];
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw FormatException(
                'Expected an object in the response list for $path.',
              );
            }
            return fromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (e) {
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<bool> clientNameExists(String name) => throw UnsupportedError(
    'clientNameExists is demo-only (no backend endpoint).',
  );

  @override
  Future<bool> addClient({required String name, required String goal}) =>
      throw UnsupportedError('addClient is demo-only (no backend endpoint).');

  /// Flips the trainer's 활성/휴면 management state for [id] (#707).
  ///
  /// This is not an unassignment — the backend keeps the trainer↔member link
  /// and every record behind it, and the member app sees no change.
  ///
  /// The roster is re-fetched only after the server confirms, so a failed
  /// call leaves the badge showing the last state the server actually has.
  @override
  Future<void> setClientActive(String id, bool active) async {
    try {
      await _dio.put<Map<String, Object?>>(
        '/trainer/clients/${Uri.encodeComponent(id)}/status',
        data: <String, Object?>{'active': active},
      );
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
    _refreshes.add(id);
  }

  @override
  Future<void> removeClient(String id) async {
    try {
      await _dio.delete<void>('/trainer/clients/${Uri.encodeComponent(id)}');
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
    _refreshes.add(null);
  }

  @override
  Future<void> restoreClient(String id) async {
    try {
      await _dio.put<void>(
        '/trainer/clients/${Uri.encodeComponent(id)}/registration',
      );
    } on DioException catch (error) {
      throw AppError.fromDio(error);
    }
    _refreshes.add(null);
  }
}
