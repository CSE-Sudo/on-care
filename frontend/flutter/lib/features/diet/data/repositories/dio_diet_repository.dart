import 'package:dio/dio.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/network/request_extras.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';

/// Real-network implementation of [DietRepository]. Issues HTTP
/// requests via [Dio]; the dev/local build serves them out of
/// `LocalApiInterceptor` (drift-backed). FastAPI takes over once
/// `USE_MOCK_API=false`.
class DioDietRepository implements DietRepository {
  DioDietRepository(this._dio);
  static const Duration _entryOverrideTtl = Duration(minutes: 5);

  final Dio _dio;
  final Map<String, DietEntry> _entryOverrides = <String, DietEntry>{};
  final Map<String, DateTime> _entryOverrideUpdatedAt = <String, DateTime>{};

  @override
  Future<DietDay> fetchToday() async {
    final res = await _dio.get<Map<String, Object?>>('/diet/days/today');
    final day = DietDay.fromJson(res.data!);
    _pruneStaleOverrides(day);
    return _applyOverrides(day);
  }

  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/diet/days/${_formatDate(date)}',
    );
    return DietDay.fromJson(res.data!);
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Future<MealRecommendations> fetchRecommendations() async {
    final res = await _dio.get<Map<String, Object?>>('/diet/recommendations');
    return MealRecommendations.fromJson(res.data!);
  }

  @override
  Future<String> fetchAdvice(String period) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/diet/advice',
      queryParameters: <String, Object?>{'period': period},
    );
    return (res.data?['message'] as String?) ?? '';
  }

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) async {
    final form = FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(
        photo.bytes,
        filename: photo.filename,
        // Sniffed from the bytes — the server 415s when the declared MIME
        // doesn't match what it can decode (an iPhone HEIC sent as JPEG).
        contentType: DioMediaType.parse(photo.mimeType),
      ),
      'meal_type': mealType,
      'idempotency_key': ?idempotencyKey,
    });
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/diet/analyze',
        data: form,
        // 데모 백엔드가 이 사진을 기록에 붙여 두었다가 끼니 카드에 그린다.
        // 서버로 나가는 값이 아니다 — multipart 본문은 한 번만 읽히므로
        // 인터셉터가 거기서 바이트를 꺼내 갈 수는 없다.
        options: Options(
          extra: <String, Object?>{kMealPhotoBytesExtra: photo.bytes},
        ),
      );
      return DietAnalysisResult.fromResponse(res.data!);
    } on DioException catch (e) {
      // The screen has to tell "this photo will never work" (415) apart from
      // "the recognizer hiccuped" (502) to know whether offering a retry is
      // honest, and it must not type-test DioException to do it.
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    await _dio.delete<Map<String, Object?>>('/diet/entries/$id');
    _entryOverrides.remove(id);
    _entryOverrideUpdatedAt.remove(id);
  }

  @override
  Future<DietEntry> updateEntry({
    required String id,
    String? date,
    String? mealType,
    String? timeLabel,
    List<FoodItem>? foods,
    int? totalCalories,
    int? sodiumMg,
    double? sugarG,
  }) async {
    final res = await _dio.put<Map<String, Object?>>(
      '/diet/entries/$id',
      data: <String, Object?>{
        'date': ?date,
        'meal_type': ?mealType,
        'time_label': ?timeLabel,
        if (foods != null)
          'foods': foods
              .map(
                (FoodItem food) => <String, Object?>{
                  'name': food.name,
                  'calories': food.calories,
                  // 섭취량은 나머지 값의 기준이라 함께 싣는다. 빠뜨리면 다음에
                  // 이 끼니를 열었을 때 양을 모르는 기록이 되어, 양으로 영양을
                  // 움직이는 길이 저장 한 번에 끊긴다(#1876).
                  'amount_g': food.amountG,
                  'sodium_mg': food.sodiumMg,
                  'sugar_g': food.sugarG,
                  'carbs_g': food.carbsG,
                  'protein_g': food.proteinG,
                  'fat_g': food.fatG,
                },
              )
              .toList(),
        'total_calories': ?totalCalories,
        'sodium_mg': ?sodiumMg,
        'sugar_g': ?sugarG,
      },
    );
    final returned = DietEntry.fromJson(res.data!);
    final updatedFoods = foods ?? returned.foods;
    final editedMacros = foods == null
        ? null
        : (
            carbsG: updatedFoods.fold<double>(
              0,
              (double sum, FoodItem food) => sum + food.carbsG,
            ),
            proteinG: updatedFoods.fold<double>(
              0,
              (double sum, FoodItem food) => sum + food.proteinG,
            ),
            fatG: updatedFoods.fold<double>(
              0,
              (double sum, FoodItem food) => sum + food.fatG,
            ),
          );
    final updated = DietEntry(
      id: returned.id,
      mealType: mealType == null
          ? returned.mealType
          : MealType.values.byName(mealType),
      timeLabel: timeLabel ?? returned.timeLabel,
      foods: updatedFoods,
      totalCalories: totalCalories ?? returned.totalCalories,
      sodiumMg: sodiumMg ?? returned.sodiumMg,
      sugarG: sugarG ?? returned.sugarG,
      carbsG: editedMacros?.carbsG ?? returned.carbsG,
      proteinG: editedMacros?.proteinG ?? returned.proteinG,
      fatG: editedMacros?.fatG ?? returned.fatG,
      // 수정은 끼니 내용만 바꾼다. 이 오버라이드가 원본 항목을 통째로 갈아
      // 끼우므로, 여기 빠뜨린 값은 화면에서 사라진다 — 사진을 빠뜨리면 이름만
      // 고쳐도 끼니 카드가 이모지로 떨어졌다.
      photoAsset: returned.photoAsset,
      photoUrl: returned.photoUrl,
      aiComment: returned.aiComment,
    );
    _entryOverrides[id] = updated;
    _entryOverrideUpdatedAt[id] = nowKst();
    return updated;
  }

  void _pruneStaleOverrides(DietDay day) {
    if (_entryOverrides.isEmpty) return;

    final now = nowKst();
    final serverIds = day.entries
        .map((DietEntry entry) => entry.id)
        .whereType<String>()
        .toSet();
    final staleIds = <String>[];

    for (final id in _entryOverrides.keys) {
      final updatedAt = _entryOverrideUpdatedAt[id];
      final isExpired =
          updatedAt == null || now.difference(updatedAt) > _entryOverrideTtl;
      if (isExpired || !serverIds.contains(id)) {
        staleIds.add(id);
      }
    }

    for (final id in staleIds) {
      _entryOverrides.remove(id);
      _entryOverrideUpdatedAt.remove(id);
    }
  }

  DietDay _applyOverrides(DietDay day) {
    if (_entryOverrides.isEmpty) return day;
    final entries = day.entries
        .map((DietEntry entry) => _entryOverrides[entry.id] ?? entry)
        .toList();
    return DietDay(
      entries: entries,
      totalCalories: entries.fold<int>(
        0,
        (int total, DietEntry entry) => total + entry.totalCalories,
      ),
      macros: _toDietMacros(_sumMacroGrams(entries)),
      totalSodiumMg: entries.fold<int>(
        0,
        (int total, DietEntry entry) => total + entry.sodiumMg,
      ),
      totalSugarG: entries.fold<double>(
        0,
        (double total, DietEntry entry) => total + entry.sugarG,
      ),
      aiCoachMessage: day.aiCoachMessage,
    );
  }
}

typedef _MacroGrams = ({double carbsG, double proteinG, double fatG});

_MacroGrams _sumMacroGrams(Iterable<DietEntry> entries) => (
  carbsG: entries.fold<double>(
    0,
    (double sum, DietEntry entry) => sum + entry.carbsG,
  ),
  proteinG: entries.fold<double>(
    0,
    (double sum, DietEntry entry) => sum + entry.proteinG,
  ),
  fatG: entries.fold<double>(
    0,
    (double sum, DietEntry entry) => sum + entry.fatG,
  ),
);

// Keep this 4/4/9 largest-remainder calculation in sync with
// the backend calculate_macros implementation.
DietMacros _toDietMacros(_MacroGrams grams) {
  final energies = <double>[
    grams.carbsG * 4,
    grams.proteinG * 4,
    grams.fatG * 9,
  ];
  final totalEnergy = energies.fold<double>(
    0,
    (double sum, double energy) => sum + energy,
  );
  final percentages = <int>[0, 0, 0];
  if (totalEnergy > 0) {
    final raw = energies
        .map((double energy) => energy / totalEnergy * 100)
        .toList();
    for (var index = 0; index < percentages.length; index++) {
      percentages[index] = raw[index].floor();
    }
    final ranked = <int>[0, 1, 2]
      ..sort((int a, int b) {
        final fraction = (raw[b] - percentages[b]).compareTo(
          raw[a] - percentages[a],
        );
        return fraction == 0 ? b.compareTo(a) : fraction;
      });
    final remaining =
        100 - percentages.fold<int>(0, (int sum, int value) => sum + value);
    for (final index in ranked.take(remaining)) {
      percentages[index]++;
    }
  }
  return DietMacros(
    carbsG: grams.carbsG,
    proteinG: grams.proteinG,
    fatG: grams.fatG,
    carbsPct: percentages[0],
    proteinPct: percentages[1],
    fatPct: percentages[2],
  );
}
