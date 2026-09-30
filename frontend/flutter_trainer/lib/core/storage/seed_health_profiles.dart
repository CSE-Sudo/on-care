import 'dart:convert';

import 'package:oncare_trainer/core/storage/app_database.dart';

/// 담당 회원 15명의 신체 정보와 식단·운동 목표(#2597).
///
/// 키는 `seed-client-N` 의 N 이다. 백엔드 시드(`seed_trainer._MEMBER_BODY_GOALS`)
/// 와 **같은 값**이다 — 데모와 실서버가 같은 회원을 다른 몸으로 그리지 않게
/// 두 곳을 함께 고친다. 값은 회원마다 건강 목표(체중 감량·근력 향상·재활 …)에
/// 맞춰 골랐고, 칼로리는 탄·단·지 배분과 어긋나지 않게 두었다. 범위는
/// `AppGoalRanges` 안이다.
///
/// 성별·건강 목표는 여기 넣지 않는다 — 로스터가 이미 말하고 있는 값을
/// 읽는다(#960, #1818).
const Map<int, Map<String, num>> seedHealthProfiles = <int, Map<String, num>>{
  // 김민수 — 체중 감량·혈압 관리. 식단 목표는 회원 앱 프로필 목업과 같다.
  1: <String, num>{
    'height_cm': 175,
    'weight_kg': 82,
    'daily_calories': 2000,
    'daily_carbs_g': 275,
    'daily_sugar_g': 50,
    'daily_protein_g': 100,
    'daily_fat_g': 55,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 350,
    'weekly_cardio_minutes': 180,
    'weekly_strength_sets': 18,
    'weekly_flexibility_minutes': 60,
  },
  // 이지수 — 체중 감량·체력 강화.
  2: <String, num>{
    'height_cm': 163,
    'weight_kg': 62,
    'daily_calories': 1600,
    'daily_carbs_g': 200,
    'daily_sugar_g': 40,
    'daily_protein_g': 95,
    'daily_fat_g': 45,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 300,
    'weekly_cardio_minutes': 150,
    'weekly_strength_sets': 18,
    'weekly_flexibility_minutes': 60,
  },
  // 박성호 — 근력 향상.
  3: <String, num>{
    'height_cm': 178,
    'weight_kg': 76,
    'daily_calories': 2600,
    'daily_carbs_g': 320,
    'daily_sugar_g': 50,
    'daily_protein_g': 150,
    'daily_fat_g': 75,
    'daily_sodium_mg': 2300,
    'daily_burn_kcal': 300,
    'weekly_cardio_minutes': 60,
    'weekly_strength_sets': 36,
    'weekly_flexibility_minutes': 40,
  },
  // 정하윤 — 체력 강화·재활.
  4: <String, num>{
    'height_cm': 160,
    'weight_kg': 54,
    'daily_calories': 1800,
    'daily_carbs_g': 240,
    'daily_sugar_g': 45,
    'daily_protein_g': 85,
    'daily_fat_g': 55,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 220,
    'weekly_cardio_minutes': 120,
    'weekly_strength_sets': 12,
    'weekly_flexibility_minutes': 90,
  },
  // 최우진 — 체력 강화.
  5: <String, num>{
    'height_cm': 180,
    'weight_kg': 74,
    'daily_calories': 2500,
    'daily_carbs_g': 330,
    'daily_sugar_g': 50,
    'daily_protein_g': 120,
    'daily_fat_g': 70,
    'daily_sodium_mg': 2300,
    'daily_burn_kcal': 400,
    'weekly_cardio_minutes': 180,
    'weekly_strength_sets': 24,
    'weekly_flexibility_minutes': 60,
  },
  // 강서연 — 체중 감량. 칼로리·당류는 회원 앱 기본값(2,000kcal·50g)이다 —
  // 데모 장면(2,260kcal 로 목표를 넘긴 날, 저녁 치킨만 당류를 짚는 끼니)이
  // 그 목표로 짜여 있다.
  6: <String, num>{
    'height_cm': 165,
    'weight_kg': 68,
    'daily_calories': 2000,
    'daily_carbs_g': 250,
    'daily_sugar_g': 50,
    'daily_protein_g': 110,
    'daily_fat_g': 55,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 350,
    'weekly_cardio_minutes': 180,
    'weekly_strength_sets': 15,
    'weekly_flexibility_minutes': 60,
  },
  // 임도현 — 자세 교정.
  7: <String, num>{
    'height_cm': 172,
    'weight_kg': 70,
    'daily_calories': 2300,
    'daily_carbs_g': 300,
    'daily_sugar_g': 50,
    'daily_protein_g': 110,
    'daily_fat_g': 65,
    'daily_sodium_mg': 2300,
    'daily_burn_kcal': 250,
    'weekly_cardio_minutes': 90,
    'weekly_strength_sets': 18,
    'weekly_flexibility_minutes': 120,
  },
  // 오세라 — 혈압 관리. 나트륨을 낮게 잡는다.
  8: <String, num>{
    'height_cm': 158,
    'weight_kg': 60,
    'daily_calories': 1700,
    'daily_carbs_g': 230,
    'daily_sugar_g': 40,
    'daily_protein_g': 80,
    'daily_fat_g': 50,
    'daily_sodium_mg': 1500,
    'daily_burn_kcal': 250,
    'weekly_cardio_minutes': 150,
    'weekly_strength_sets': 12,
    'weekly_flexibility_minutes': 60,
  },
  // 배준혁 — 체력 강화·운동 습관.
  9: <String, num>{
    'height_cm': 176,
    'weight_kg': 78,
    'daily_calories': 2400,
    'daily_carbs_g': 320,
    'daily_sugar_g': 50,
    'daily_protein_g': 120,
    'daily_fat_g': 68,
    'daily_sodium_mg': 2300,
    'daily_burn_kcal': 350,
    'weekly_cardio_minutes': 150,
    'weekly_strength_sets': 21,
    'weekly_flexibility_minutes': 60,
  },
  // 신유나 — 재활. 운동량을 낮추고 유연성을 늘린다.
  10: <String, num>{
    'height_cm': 162,
    'weight_kg': 52,
    'daily_calories': 1800,
    'daily_carbs_g': 240,
    'daily_sugar_g': 45,
    'daily_protein_g': 85,
    'daily_fat_g': 55,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 180,
    'weekly_cardio_minutes': 90,
    'weekly_strength_sets': 9,
    'weekly_flexibility_minutes': 120,
  },
  // 한지호 — 식습관 개선·운동 습관.
  11: <String, num>{
    'height_cm': 174,
    'weight_kg': 80,
    'daily_calories': 2200,
    'daily_carbs_g': 280,
    'daily_sugar_g': 40,
    'daily_protein_g': 110,
    'daily_fat_g': 60,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 300,
    'weekly_cardio_minutes': 150,
    'weekly_strength_sets': 15,
    'weekly_flexibility_minutes': 60,
  },
  // 문가영 — 체력 강화.
  12: <String, num>{
    'height_cm': 167,
    'weight_kg': 58,
    'daily_calories': 1900,
    'daily_carbs_g': 250,
    'daily_sugar_g': 45,
    'daily_protein_g': 90,
    'daily_fat_g': 55,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 280,
    'weekly_cardio_minutes': 150,
    'weekly_strength_sets': 15,
    'weekly_flexibility_minutes': 60,
  },
  // 류태경 — 근력 향상·식습관 개선.
  13: <String, num>{
    'height_cm': 168,
    'weight_kg': 60,
    'daily_calories': 2000,
    'daily_carbs_g': 240,
    'daily_sugar_g': 40,
    'daily_protein_g': 120,
    'daily_fat_g': 60,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 250,
    'weekly_cardio_minutes': 60,
    'weekly_strength_sets': 30,
    'weekly_flexibility_minutes': 40,
  },
  // 백서진 — 식습관 개선.
  14: <String, num>{
    'height_cm': 170,
    'weight_kg': 72,
    'daily_calories': 2200,
    'daily_carbs_g': 290,
    'daily_sugar_g': 40,
    'daily_protein_g': 100,
    'daily_fat_g': 62,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 250,
    'weekly_cardio_minutes': 120,
    'weekly_strength_sets': 15,
    'weekly_flexibility_minutes': 60,
  },
  // 노은채 — 운동 습관.
  15: <String, num>{
    'height_cm': 161,
    'weight_kg': 55,
    'daily_calories': 1800,
    'daily_carbs_g': 240,
    'daily_sugar_g': 45,
    'daily_protein_g': 80,
    'daily_fat_g': 52,
    'daily_sodium_mg': 2000,
    'daily_burn_kcal': 220,
    'weekly_cardio_minutes': 150,
    'weekly_strength_sets': 12,
    'weekly_flexibility_minutes': 60,
  },
};

/// [seedHealthProfiles] 를 데모 저장소에 넣는다 — **저장된 값이 없는 회원만**.
///
/// 데모는 트레이너가 신체·목표 창에서 저장한 값을 같은 키
/// (`member_health_profile:<id>`)에 둔다. 날이 바뀔 때마다 시드가 다시 돌아도
/// 트레이너가 고친 값이 되돌아가지 않게, 비어 있을 때만 쓴다.
Future<void> seedDemoHealthProfiles(AppDatabase db) async {
  for (final MapEntry<int, Map<String, num>> e in seedHealthProfiles.entries) {
    final String key = 'member_health_profile:seed-client-${e.key}';
    if (await db.readValue(key) != null) continue;
    await db.putValue(key, jsonEncode(e.value));
  }
}
