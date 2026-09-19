import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';

/// Result of POST /diet/analyze — the recognized foods + nutrition the
/// server materialised (and already persisted as a diet entry).
class RecognizedFood {
  const RecognizedFood({
    required this.name,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    required this.source,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.amountG,
  });

  final String name;
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// 영양 출처(#2105). 분석 완료 시트에서 음식을 고쳐 저장할 때 음식마다 그대로
  /// 되돌려 보낸다 — 안 보내면 손대지 않은 음식까지 서버 기본값으로 덮인다.
  final FoodSource source;

  /// 음식별 탄수화물·단백질·지방(g). 서버는 음식마다 함께 주는데 앱은 합계만
  /// 읽고 있었다. 분석 완료 시트에서 음식을 고쳐 다시 보낼 때 이 값이 없으면
  /// 그 저장 한 번으로 탄단지가 0 이 된다(#1853, #2097).
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 이 음식의 내용량(g) — 함께 온 영양이 무엇을 재고 나온 값인가다(#1876).
  /// 서버가 양을 얻지 못했으면 null 이다. `0` 도 null 로 읽는다 — 0g 은
  /// 안 먹었다는 말이지 모른다는 말이 아니다.
  final double? amountG;

  factory RecognizedFood.fromJson(Map<String, Object?> json) => RecognizedFood(
    name: json['name']! as String,
    calories: (json['calories'] as num?)?.toInt() ?? 0,
    sodiumMg: (json['sodium_mg'] as num?)?.toInt() ?? 0,
    sugarG: (json['sugar_g'] as num?)?.toDouble() ?? 0,
    source: FoodSource.fromJson(json['source']),
    carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
    proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
    fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
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
