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
    this.amountG,
  });

  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;
  final String source; // "db"(공공 영양 DB 매핑) | "estimate"(LLM 추정)

  /// 이 음식의 내용량(g) — 함께 온 영양이 무엇을 재고 나온 값인가다(#1876).
  /// 서버가 양을 얻지 못했으면 null 이다. `0` 도 null 로 읽는다 — 0g 은
  /// 안 먹었다는 말이지 모른다는 말이 아니다.
  final double? amountG;

  bool get isFromDb => source == 'db';

  factory RecognizedFood.fromJson(Map<String, Object?> json) => RecognizedFood(
    name: json['name']! as String,
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
    source: (json['source'] as String?) ?? 'estimate',
    amountG: switch (json['amount_g']) {
      final num g when g > 0 => g.toDouble(),
      _ => null,
    },
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
    this.timeLabel = '',
    this.points,
  });

  final String entryId;

  /// 저장된 기록의 시각(`HH:MM`). 끼니 카드가 쓰는 것과 같은 서버 값이다 —
  /// 앱이 제 시계로 다시 계산하면 저장된 값과 어긋날 수 있어 서버가 내려주는
  /// 것을 그대로 쓴다. 이 필드를 모르는 서버면 빈 문자열이다(#1897).
  final String timeLabel;

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

  /// 끼니 전체의 내용량(g). **모든 음식의 양을 알 때만** 그 합이다.
  ///
  /// 하나라도 모르면 null 이다 — 아는 것만 더하면 그 끼니를 덜 먹은 것처럼
  /// 읽히고, 옆의 칼로리는 모든 음식을 더한 값이라 둘이 서로 다른 양을 말하게
  /// 된다(#1964).
  double? get totalAmountG {
    if (foods.isEmpty) return null;
    double sum = 0;
    for (final RecognizedFood food in foods) {
      final double? grams = food.amountG;
      if (grams == null) return null;
      sum += grams;
    }
    return sum;
  }

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
      timeLabel: (json['time_label'] as String?) ?? '',
      points: PointsAward.fromJson(json['points']),
    );
  }
}
