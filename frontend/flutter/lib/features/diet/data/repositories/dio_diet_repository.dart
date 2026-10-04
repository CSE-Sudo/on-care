import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/core/network/request_extras.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_entry_key_conflict.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/domain/entities/food_nutrition_suggestion.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/domain/repositories/diet_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Real-network implementation of [DietRepository]. Issues HTTP
/// requests via [Dio]; the dev/local build serves them out of
/// `LocalApiInterceptor` (drift-backed). FastAPI takes over once
/// `USE_MOCK_API=false`.
class DioDietRepository implements DietRepository {
  DioDietRepository(this._dio);

  final Dio _dio;

  /// 사진 분석 응답 대기 시간. 전역 receiveTimeout(15초)으로는 모자란다(#2847).
  ///
  /// 서버는 한 요청 안에서 비전 인식(인식기 타임아웃 60초) → 공공 영양 DB 보강
  /// → 끼니 저장·포인트 적립·사진 저장까지 한다. 15초에 끊으면 서버는 계속
  /// 처리해 끼니를 저장하는데 앱은 실패 화면을 띄운다. 인식 상한에 보강·저장
  /// 시간을 더해 90초를 둔다.
  @visibleForTesting
  static const Duration analyzeTimeout = Duration(seconds: 90);

  /// 오늘 조언 응답 대기 시간(#2847).
  ///
  /// 오늘 조언은 4주 추천 메뉴 리스트를 쓰고, 리스트를 새로 만들 차례면 서버가
  /// LLM 을 최대 15초 기다린 뒤 카탈로그로 대체한다(`diet_menu_plan.py`
  /// `LLM_TIMEOUT_SEC`). 앱이 같은 15초에 끊으면 서버가 정상으로 돌려주는 대체
  /// 조언을 받지 못하고 카드를 오류로 그린다. 서버 대기보다 넉넉히 30초를 둔다.
  @visibleForTesting
  static const Duration adviceTimeout = Duration(seconds: 30);

  @override
  Future<DietDay> fetchToday() async {
    final res = await _dio.get<Map<String, Object?>>('/diet/days/today');
    return DietDay.fromJson(res.data!);
  }

  @override
  Future<DietDay> fetchByDate(DateTime date) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/diet/days/${wireDate(date)}',
    );
    return DietDay.fromJson(res.data!);
  }

  @override
  Future<DietPeriod> fetchPeriod({DateTime? from, DateTime? to}) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/diet/days',
      queryParameters: <String, String>{
        if (from != null) 'from': wireDate(from),
        if (to != null) 'to': wireDate(to),
      },
    );
    return DietPeriod.fromJson(res.data!);
  }

  @override
  Future<MealRecommendations> fetchRecommendations() async {
    final res = await _dio.get<Map<String, Object?>>('/diet/recommendations');
    return MealRecommendations.fromJson(res.data!);
  }

  @override
  Future<DietAdvice> fetchAdvice(String period, {String lang = 'ko'}) async {
    final res = await _dio.get<Map<String, Object?>>(
      '/diet/advice',
      queryParameters: <String, Object?>{'period': period, 'lang': lang},
      options: Options(receiveTimeout: adviceTimeout),
    );
    return DietAdvice.fromJson(res.data ?? const <String, Object?>{});
  }

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
    String? date,
  }) async {
    // multipart 본문은 한 번만 읽힌다 — 다시 보낼 때는 새로 만든다.
    FormData form() => FormData.fromMap(<String, Object?>{
      'image': MultipartFile.fromBytes(
        photo.bytes,
        filename: photo.filename,
        // Sniffed from the bytes — the server 415s when the declared MIME
        // doesn't match what it can decode (an iPhone HEIC sent as JPEG).
        contentType: DioMediaType.parse(photo.mimeType),
      ),
      'meal_type': mealType,
      'idempotency_key': ?idempotencyKey,
      'date': ?date,
    });
    Future<Response<Map<String, Object?>>> send() =>
        _dio.post<Map<String, Object?>>(
          '/diet/analyze',
          data: form(),
          // 데모 백엔드가 이 사진을 기록에 붙여 두었다가 끼니 카드에 그린다.
          // 서버로 나가는 값이 아니다 — multipart 본문은 한 번만 읽히므로
          // 인터셉터가 거기서 바이트를 꺼내 갈 수는 없다.
          options: Options(
            receiveTimeout: analyzeTimeout,
            extra: <String, Object?>{kMealPhotoBytesExtra: photo.bytes},
          ),
        );
    try {
      Response<Map<String, Object?>> res;
      try {
        res = await send();
      } on DioException catch (e) {
        // 응답을 기다리다 끊겼다고 실패로 단정하지 않는다(#2847). 서버는 앱이
        // 끊은 뒤에도 끝까지 처리해 끼니를 저장했을 수 있다. 같은 멱등키로 한
        // 번 더 보내면 서버는 저장분을 그대로 돌려준다(새로 저장·적립하지
        // 않는다) — 저장돼 있으면 그대로 성공이다. 키가 없으면 다시 보내는
        // 것이 중복 저장이라 하지 않는다.
        if (e.type != DioExceptionType.receiveTimeout ||
            idempotencyKey == null) {
          rethrow;
        }
        res = await send();
      }
      return DietAnalysisResult.fromResponse(res.data!);
    } on DioException catch (e) {
      // The screen has to tell "this photo will never work" (415) apart from
      // "the recognizer hiccuped" (502) to know whether offering a retry is
      // honest, and it must not type-test DioException to do it.
      // 서버가 이유를 코드로 알려 준 거절(음식 없음·오늘 한도·분석 꺼짐)은
      // 상태 코드보다 그 코드가 정확하다(#2848, #2827, #2812).
      final DietAnalysisRejected? rejected =
          DietAnalysisRejected.fromResponseData(e.response?.data);
      if (rejected != null) throw rejected;
      throw AppError.fromDio(e);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    await _dio.delete<Map<String, Object?>>('/diet/entries/$id');
  }

  @override
  Future<FoodNutritionSuggestion?> lookupFoodNutrition({
    required String name,
    double? amountG,
  }) async {
    final res = await _dio.post<Map<String, Object?>>(
      '/diet/nutrition',
      data: <String, Object?>{'name': name, 'amount_g': ?amountG},
    );
    return FoodNutritionSuggestion.fromJson(res.data!);
  }

  @override
  Future<DietEntry> createEntry({
    required String date,
    required String mealType,
    required List<FoodItem> foods,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _dio.post<Map<String, Object?>>(
        '/diet/entries',
        data: <String, Object?>{
          'date': date,
          'meal_type': mealType,
          'foods': foods.map(_foodJson).toList(),
          'idempotency_key': ?idempotencyKey,
        },
      );
      return DietEntry.fromJson(res.data!);
    } on DioException catch (e) {
      // 이 키로는 다른 끼니가 이미 저장돼 있다(#3095).
      if (e.response?.statusCode == 409) throw const DietEntryKeyConflict();
      rethrow;
    }
  }

  /// 음식 한 줄의 전송 표현. 직접 추가와 수정이 같은 모양을 보낸다.
  static Map<String, Object?> _foodJson(FoodItem food) => <String, Object?>{
    'name': food.name,
    'calories': food.calories,
    // 섭취량은 나머지 값의 기준이라 함께 싣는다. 빠뜨리면 다음에 이 끼니를
    // 열었을 때 양을 모르는 기록이 되어, 양으로 영양을 움직이는 길이 저장 한
    // 번에 끊긴다(#1876).
    'amount_g': food.amountG,
    'sodium_mg': food.sodiumMg,
    'sugar_g': food.sugarG,
    'carbs_g': food.carbsG,
    'protein_g': food.proteinG,
    'fat_g': food.fatG,
    // 음식마다 출처를 되돌려 보낸다(#2105). 빠뜨리면 서버가 빠진 값을
    // 채우므로, 손대지 않은 음식까지 원래 출처를 잃는다.
    'source': food.source.name,
    // 표시 이름은 회원이 이름을 그대로 둔 음식에만 실린다(#2850). 빼고 보내면
    // 서버가 지운다 — 바꾼 이름이 회원이 쓴 표시 이름이기 때문이다.
    'display_name': ?food.displayName,
  };

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
        if (foods != null) 'foods': foods.map(_foodJson).toList(),
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
