import 'package:oncare/features/diet/domain/entities/diet_day.dart';

/// 기간 뷰의 하루. 하루 상세( [DietDay] )에서 화면이 그리는 세 수치만 남긴다.
class DietPeriodDay {
  const DietPeriodDay({
    required this.date,
    required this.calories,
    required this.sodiumMg,
    required this.sugarG,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
  });

  /// `GET /diet/days?from=&to=` 의 한 칸. 하루 합계만 실려 온다(#2236).
  factory DietPeriodDay.fromJson(Map<String, Object?> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    final DateTime parsed =
        DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime(0);
    return DietPeriodDay(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      calories: (json['total_calories'] as num?)?.toInt() ?? 0,
      sodiumMg: (json['total_sodium_mg'] as num?)?.toInt() ?? 0,
      sugarG: number('total_sugar_g'),
      carbsG: number('carbs_g'),
      proteinG: number('protein_g'),
      fatG: number('fat_g'),
    );
  }

  /// 그날의 [DietDay] 를 접어 만든다. 합산 규칙은 하루 요약과 공유한다
  /// ([DietDayTotals]) — 따로 계산하면 두 화면의 숫자가 조용히 어긋난다.
  factory DietPeriodDay.from(DateTime date, DietDay day) => DietPeriodDay(
    date: date,
    calories: day.effectiveCalories,
    sodiumMg: day.effectiveSodiumMg,
    sugarG: day.effectiveSugarG,
    carbsG: day.effectiveCarbsG,
    proteinG: day.effectiveProteinG,
    fatG: day.effectiveFatG,
  );

  final DateTime date;
  final int calories;
  final int sodiumMg;
  final double sugarG;

  /// 그날의 탄단지(g). 이번 달 칼로리 막대를 셋으로 쌓아 그리고, 툴팁이 각
  /// 수치를 적는다(#7 요청).
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 탄단지가 내는 칼로리 — 탄·단 4kcal/g, 지 9kcal/g.
  ///
  /// 막대를 쌓을 때 쓰는 값이다. 그램으로 쌓으면 지방 1g 이 탄수화물 1g 과 같은
  /// 높이를 차지해, 칼로리 막대인데 칼로리와 다른 이야기를 하게 된다.
  double get carbsKcal => carbsG * 4;
  double get proteinKcal => proteinG * 4;
  double get fatKcal => fatG * 9;

  /// 탄단지 합이 실제로 있는가. 실서버가 영양을 주지 않은 날은 0 이라, 그런
  /// 날은 쌓지 않고 한 색으로 그린다.
  bool get hasMacros => carbsG > 0 || proteinG > 0 || fatG > 0;

  /// 기록이 있었던 날인가. 칼로리를 기준으로 본다 — 물만 마신 날은 없다고
  /// 보는 편이 평균을 사실에 가깝게 만든다.
  bool get hasRecord => calories > 0;
}

/// 한 기간(이번 주·이번 달)의 식단 집계.
///
/// 합계가 아니라 **하루 평균**이 이 값의 머리 숫자다. 주(7일)와 달(28~31일)은
/// 길이가 다르므로 합계끼리 견주면 언제나 달이 크게 나온다. 평균은 **기록이
/// 있는 날만으로** 나눈다 — 기록하지 않은 날의 0 이 평균을 끌어내리면 실제로
/// 먹은 양과 다른 숫자가 된다.
class DietPeriod {
  const DietPeriod({required this.days});

  /// `GET /diet/days?from=&to=` 응답. 기록이 없는 날도 빈 칸으로 들어 있어
  /// 화면이 날짜를 다시 맞춰 보지 않아도 된다(#2236).
  factory DietPeriod.fromJson(Map<String, Object?> json) => DietPeriod(
    days: <DietPeriodDay>[
      for (final Object? row
          in (json['days'] as List<Object?>?) ?? const <Object?>[])
        if (row is Map<String, Object?>) DietPeriodDay.fromJson(row),
    ],
  );

  final List<DietPeriodDay> days;

  List<DietPeriodDay> get logged =>
      days.where((DietPeriodDay d) => d.hasRecord).toList();

  int get loggedDays => logged.length;

  bool get isEmpty => loggedDays == 0;

  int get totalCalories =>
      days.fold<int>(0, (int a, DietPeriodDay d) => a + d.calories);
  int get totalSodiumMg =>
      days.fold<int>(0, (int a, DietPeriodDay d) => a + d.sodiumMg);
  double get totalSugarG =>
      days.fold<double>(0, (double a, DietPeriodDay d) => a + d.sugarG);

  double get avgCalories => loggedDays == 0 ? 0 : totalCalories / loggedDays;
  double get avgSodiumMg => loggedDays == 0 ? 0 : totalSodiumMg / loggedDays;
  double get avgSugarG => loggedDays == 0 ? 0 : totalSugarG / loggedDays;
}
