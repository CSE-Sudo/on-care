import 'package:oncare/core/advice/diet_advice.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/diet_period.dart';
import 'package:oncare/features/diet/domain/entities/food_nutrition_suggestion.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';

abstract class DietRepository {
  Future<DietDay> fetchToday();

  Future<DietDay> fetchByDate(DateTime date);

  /// 기간의 **날짜별 합계** — GET /diet/days?from=&to= (#2236)
  ///
  /// 기간 그래프가 쓰는 길이다. 예전에는 하루 조회를 날짜 수만큼 모았는데,
  /// `전체` 가 모든 기록을 그리게 되면서(#2079) 해가 바뀐 회원에게 수백 번의
  /// 왕복이 됐다.
  ///
  /// [from] 을 주지 않으면 **첫 기록일**부터다. 받은 구간은 응답이 말해 준다 —
  /// 돌려주는 [DietPeriod.days] 의 첫 칸과 끝 칸이 그 구간이고, 기록이 없는 날도
  /// 빈 칸으로 들어 있다.
  Future<DietPeriod> fetchPeriod({DateTime? from, DateTime? to});

  /// GET /diet/recommendations — 홈 "AI 추천 식단".
  ///
  /// 서버가 최근 식단·건강 목표를 근거로 카탈로그에서 고른 결과다. 실패해도
  /// 홈 화면이 비지 않도록, 호출부는 결과가 오기 전/에러 시 기본 추천을 그린다.
  Future<MealRecommendations> fetchRecommendations();

  /// 기간에 맞는 식단 조언. (#1017)
  ///
  /// [period] 는 화면의 기간 토글과 같은 이름(`today`·`week`·`all`)이다. 구간
  /// 경계는 서버가 정한다 — 앱과 트레이너웹이 각자 계산하면 같은 회원의
  /// `이번 주` 가 화면마다 다른 날부터 시작한다.
  ///
  /// 조언은 규칙 한 줄 + 다음 할 일 한 문장이다(#2251). [lang] 은 앱 언어(`ko`·
  /// `en`)로, 메뉴 이름과 AI 가 만드는 문장이 그 언어로 온다.
  Future<DietAdvice> fetchAdvice(String period, {String lang = 'ko'});

  /// Upload a food photo for AI analysis (POST /diet/analyze). The server
  /// recognizes the foods, maps nutrition from the public DB, persists a
  /// diet entry, and returns the analysis.
  ///
  /// [photo] carries the bytes together with the file name and MIME type
  /// that describe them, so the multipart part the server validates always
  /// matches the actual image (see [MealPhoto]).
  ///
  /// [idempotencyKey], when supplied, lets the server dedupe a retried
  /// request (lost-response case) so the same photo isn't recorded twice.
  /// Generate it once per capture and reuse it across retries.
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  });

  /// DELETE /diet/entries/{id} — remove a diet entry.
  Future<void> deleteEntry(String id);

  /// PUT /diet/entries/{id} — edit an entry's date, meal type, time, foods,
  /// and nutrition values corrected from the analysis result.
  ///
  /// [date] 는 `YYYY-MM-DD` 다. 사진 분석은 저장한 시각의 날짜로 기록을 남기는데,
  /// 지난 식사의 사진을 나중에 올리는 일이 있어 실제로 먹은 날로 옮길 수 있어야
  /// 한다(#1241). 아직 오지 않은 날은 서버가 거절한다.
  Future<DietEntry> updateEntry({
    required String id,
    String? date,
    String? mealType,
    String? timeLabel,
    List<FoodItem>? foods,
    int? totalCalories,
    int? sodiumMg,
    double? sugarG,
  });

  /// POST /diet/entries — 사진 없이 회원이 직접 적은 끼니를 저장한다(#2151).
  ///
  /// 합계는 서버가 [foods] 에서 낸다. 포인트는 적립되지 않는다 — 적립은 사진
  /// 분석 저장만 한다. [date] 는 `YYYY-MM-DD` 이고 비우면 오늘이다.
  /// [idempotencyKey] 는 [analyze] 와 같다 — 저장 한 번에 하나 만들어 재시도에
  /// 그대로 쓴다.
  Future<DietEntry> createEntry({
    required String date,
    required String mealType,
    required List<FoodItem> foods,
    String? idempotencyKey,
  });

  /// POST /diet/nutrition — 음식 이름으로 공공 영양 DB 값을 찾는다. (#1896)
  ///
  /// 수정 화면이 이름을 고쳤을 때 **제안**에 쓴다. 계산은 분석 보정과 같은
  /// 것이라, 이름으로 찾은 값과 사진 분석이 준 값이 갈리지 않는다.
  ///
  /// [amountG] 를 주면 그 양으로 환산하고, 안 주면 DB 가 아는 1회 섭취량을 쓴다.
  /// 찾지 못했거나 양을 정할 수 없으면 **null** — 그때 화면은 아무것도 제안하지
  /// 않는다. [name] 은 비어 있으면 안 된다(서버가 400).
  Future<FoodNutritionSuggestion?> lookupFoodNutrition({
    required String name,
    double? amountG,
  });
}
