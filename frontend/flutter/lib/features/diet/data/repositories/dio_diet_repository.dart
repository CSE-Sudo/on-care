import 'package:dio/dio.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/network/request_extras.dart';
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

  final Dio _dio;

  @override
  Future<DietDay> fetchToday() async {
    final res = await _dio.get<Map<String, Object?>>('/diet/days/today');
    return DietDay.fromJson(res.data!);
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
    // 응답을 그대로 쓴다. 서버가 보낸 음식을 저장하고 끼니 합계도 그 음식에서
    // 다시 내므로(#1892), 앱이 보낸 값으로 응답을 덮어쓸 이유가 없다.
    //
    // 예전에는 덮어썼다 — 서버가 `foods` 를 통째로 버리는데도 200 을 줘서,
    // 화면을 맞추려면 앱이 기억하고 있는 수밖에 없었다. 그 우회는 고친 값이
    // 앱 메모리에만 남게 했고(다시 켜면 옛 음식), 오늘 화면에만 걸려 지난
    // 날짜는 여전히 옛 값을 보여 줬으며, 항목을 통째로 갈아 끼우느라 거기
    // 빠뜨린 사진과 코멘트를 화면에서 지우기도 했다(#1871).
    return DietEntry.fromJson(res.data!);
  }
}
