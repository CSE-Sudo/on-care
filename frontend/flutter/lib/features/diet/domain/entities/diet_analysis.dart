import 'package:oncare/core/points/points_award.dart';

/// Result of POST /diet/analyze — the recognized foods + nutrition the
/// server materialised (and already persisted as a diet entry).
class RecognizedFood {
  const RecognizedFood({
    required this.name,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    required this.source,
  });

  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;
  final String source; // "db"(공공 영양 DB 매핑) | "estimate"(LLM 추정)

  bool get isFromDb => source == 'db';

  factory RecognizedFood.fromJson(Map<String, Object?> json) => RecognizedFood(
    name: json['name']! as String,
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
    source: (json['source'] as String?) ?? 'estimate',
  );
}

class DietAnalysisResult {
  const DietAnalysisResult({
    required this.entryId,
    required this.foods,
    required this.totalCalories,
    required this.totalSodiumMg,
    required this.totalSugarG,
    required this.coachComment,
    this.totalCarbsG = 0,
    this.totalProteinG = 0,
    this.totalFatG = 0,
    this.points,
  });

  final String entryId;

  /// 이 끼니로 받은 포인트와 잔액(#1786). 이 필드를 모르는 서버면 null 이다.
  final PointsAward? points;
  final List<RecognizedFood> foods;
  final int totalCalories;
  final int totalSodiumMg;
  final double totalSugarG;

  /// 총 탄수화물·단백질·지방(g). 서버는 이미 함께 내려주고 있었는데 앱이 읽지
  /// 않아, 분석 결과가 칼로리·나트륨·당류만 말했다(#1432). 값이 없는 응답은
  /// 0 으로 떨어진다 — 화면은 서버가 준 값을 그대로 적는다.
  final double totalCarbsG;
  final double totalProteinG;
  final double totalFatG;

  final String coachComment;

  factory DietAnalysisResult.fromResponse(Map<String, Object?> json) {
    final analysis =
        (json['analysis'] as Map<String, Object?>?) ??
        const <String, Object?>{};
    return DietAnalysisResult(
      entryId: (json['entry_id'] as String?) ?? '',
      foods: ((analysis['foods'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map(RecognizedFood.fromJson)
          .toList(),
      totalCalories: (analysis['total_calories'] as num?)?.toInt() ?? 0,
      totalSodiumMg: (analysis['total_sodium_mg'] as num?)?.toInt() ?? 0,
      totalSugarG: (analysis['total_sugar_g'] as num?)?.toDouble() ?? 0,
      totalCarbsG: (analysis['total_carbs_g'] as num?)?.toDouble() ?? 0,
      totalProteinG: (analysis['total_protein_g'] as num?)?.toDouble() ?? 0,
      totalFatG: (analysis['total_fat_g'] as num?)?.toDouble() ?? 0,
      coachComment: (analysis['coach_comment'] as String?) ?? '',
      points: PointsAward.fromJson(json['points']),
    );
  }
}
