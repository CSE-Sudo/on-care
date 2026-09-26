import 'package:dio/dio.dart';

import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';

/// Network-side [ExerciseRepository]. dev/local builds get served by
/// `LocalApiInterceptor` (drift-backed); prod hits FastAPI.
class DioExerciseRepository implements ExerciseRepository {
  DioExerciseRepository(this._dio);
  final Dio _dio;

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    final res = await _dio.get<Map<String, Object?>>('/exercise/weeks/current');
    return ExerciseWeek.fromJson(res.data!);
  }

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/exercise/weeks',
      queryParameters: <String, String>{
        if (from != null) 'from': _ymd(from),
        if (to != null) 'to': _ymd(to),
      },
    );
    final Map<String, Object?> body = res.data ?? const <String, Object?>{};
    return <ExercisePeriodWeek>[
      for (final Object? row
          in (body['weeks'] as List<Object?>?) ?? const <Object?>[])
        if (row is Map<String, Object?>)
          (
            weekStart:
                DateTime.tryParse(row['week_start'] as String? ?? '') ??
                DateTime(0),
            week: ExerciseWeek.fromBriefJson(row),
          ),
    ];
  }

  /// `YYYY-MM-DD` — 서버가 날짜 질의에 쓰는 형식.
  String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/exercise/weeks/current',
      queryParameters: <String, Object?>{'week_start': _dateString(weekStart)},
    );
    return ExerciseWeek.fromJson(res.data!);
  }

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/exercise/advice',
      queryParameters: <String, Object?>{'period': period},
    );
    return ExerciseAdvice.fromJson(res.data ?? const <String, Object?>{});
  }

  static String _dateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async {
    final res = await _dio.post<Map<String, Object?>>(
      '/exercise/calories',
      data: <String, Object?>{
        'type': type.name,
        'name': name,
        'minutes': minutes,
        'intensity': intensity.name,
      },
    );
    return ExerciseCalorieEstimate.fromJson(res.data!);
  }

  @override
  Future<ExerciseSession> addSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    final res = await _dio.post<Map<String, Object?>>(
      '/exercise/sessions',
      data: _sessionBody(
        type: type,
        minutes: minutes,
        calories: calories,
        date: date,
        name: name,
        intensity: intensity,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        durationSeconds: durationSeconds,
        weight: weight,
      ),
    );
    return ExerciseSession.fromJson(res.data!);
  }

  /// 생성·수정이 같은 몸통을 쓴다 — 한쪽에만 필드를 더하면 수정한 기록에서
  /// 그 값이 조용히 사라진다.
  ///
  /// `sets`·`reps`·`hold_seconds`·`weight` 는 null 이어도 실어 보낸다. 유형을
  /// 근력에서 바꾼 수정이면 그 null 이 옛 값을 지우는데, 빼고 보내면 서버가
  /// 예전 값을 그대로 둔다. 회↔초를 되돌린 수정도 같은 이유로 둘을 함께
  /// 보내야 한다 — 초만 지우고 횟수를 보내지 않으면 옛 초가 남는다(#1969).
  static Map<String, Object?> _sessionBody({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    required String name,
    required ExerciseIntensity intensity,
    required int? sets,
    required int? reps,
    required int? holdSeconds,
    required int? durationSeconds,
    required double? weight,
  }) => <String, Object?>{
    'type': type.name,
    'name': name,
    'minutes': minutes,
    'sets': sets,
    'reps': reps,
    'hold_seconds': holdSeconds,
    'duration_seconds': durationSeconds,
    'weight': weight,
    'calories': calories,
    'intensity': intensity.name,
    'date': _dateString(date),
  };

  @override
  Future<void> deleteSession(String id) async {
    await _dio.delete<Map<String, Object?>>('/exercise/sessions/$id');
  }

  @override
  Future<ExerciseSession> updateSession({
    required String id,
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    final res = await _dio.put<Map<String, Object?>>(
      '/exercise/sessions/$id',
      data: _sessionBody(
        type: type,
        minutes: minutes,
        calories: calories,
        date: date,
        name: name,
        intensity: intensity,
        sets: sets,
        reps: reps,
        holdSeconds: holdSeconds,
        durationSeconds: durationSeconds,
        weight: weight,
      ),
    );
    return ExerciseSession.fromJson(res.data!);
  }
}
