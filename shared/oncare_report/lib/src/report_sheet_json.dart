/// 서버의 `WeeklyReportOut` 을 결과지의 한 주로 읽는다. (#2652)
///
/// 트레이너 웹은 `/trainer/clients/{id}/report` 로, 회원 앱은
/// `/me/coach/weekly-report` 로 **같은 모양**의 응답을 받는다. 두 앱이 한 규칙으로
/// 읽어야 같은 주가 같은 결과지가 된다 — 트레이너 웹 `weeklyReportFromJson` 과
/// 같은 규칙이다.
library;

import 'package:oncare_report/src/report_sheet_data.dart';
import 'package:oncare_report/src/report_sheet_values.dart';

/// `WeeklyReportOut` 한 건. [answers] 는 다른 응답(주간 피드백)에서 온다.
///
/// 요일별 끼니 기록 수(`meal_counts`)와 그날 배정된 개인운동 수
/// (`days[].assigned`)도 읽는다(#2772). 두 칸이 없는 옛 응답이면 끼니 수가 비어
/// `끼니 기록일` 이 `미집계` 로 서고, 개인운동 분모는 실제로 한 운동 수로
/// 되돌아간다. 배정이 0 이하이면 배정을 모르는 날(null)로 읽는다 — 0 은 쉬는
/// 날과 구분되지 않는다(#2232). [today] 는 이번 주인지 가를 기준일로, 없으면
/// 지금 서울 시각이다.
ReportSheetWeekData reportSheetWeekFromJson(
  Map<String, dynamic> json, {
  ReportSheetAnswers? answers,
  DateTime? today,
}) {
  int? optInt(String key) => (json[key] as num?)?.toInt();
  double? optDouble(String key) => (json[key] as num?)?.toDouble();
  List<int> ints(String key) =>
      (json[key] as List<Object?>? ?? const <Object?>[])
          .whereType<num>()
          .map((num n) => n.toInt())
          .toList(growable: false);
  // 이행률은 걸린 것이 없는 날이 null 이다(#2513). 자리를 지켜야 요일이 밀리지
  // 않는다 — null 을 걸러 내면 화요일 값이 월요일 칸에 선다.
  List<int?> nullableInts(String key) =>
      (json[key] as List<Object?>? ?? const <Object?>[])
          .map((Object? v) => v is num ? v.toInt() : null)
          .toList(growable: false);
  List<double> doubles(String key) =>
      (json[key] as List<Object?>? ?? const <Object?>[])
          .whereType<num>()
          .map((num n) => n.toDouble())
          .toList(growable: false);
  final DateTime now = today ?? reportNowKst();
  final DateTime weekStart = reportWeekStartOf(
    DateTime.tryParse(json['week_start'] as String? ?? '') ?? now,
  );
  final Object? name = json['member_name'];
  return ReportSheetWeekData(
    memberName: name is String ? name : '',
    weekStart: weekStart,
    isCurrentWeek: weekStart == reportWeekStartOf(now),
    sessionsBooked: optInt('sessions_booked') ?? 0,
    sessionsDone: optInt('sessions_done') ?? 0,
    completionAvg: optInt('completion_avg'),
    sodiumAvg: optInt('sodium_avg'),
    weekCompletion: nullableInts('week_completion'),
    sodiumWeek: ints('sodium_week'),
    caloriesWeek: ints('calories_week'),
    sugarWeek: doubles('sugar_week'),
    carbsWeek: doubles('carbs_week'),
    proteinWeek: doubles('protein_week'),
    fatWeek: doubles('fat_week'),
    mealCounts: ints('meal_counts'),
    calorieTarget: optInt('calorie_target'),
    sodiumTarget: optInt('sodium_target'),
    sugarTarget: optDouble('sugar_target'),
    carbsTarget: optDouble('carbs_target'),
    proteinTarget: optDouble('protein_target'),
    fatTarget: optDouble('fat_target'),
    // 실효 단백질 목표(#2898). 트레이너 화면 탄단지 막대와 같은 선으로 견준다.
    effectiveProteinTarget: optDouble('effective_protein_target'),
    days: <ReportSheetDay>[
      for (final Object? day
          in json['days'] as List<Object?>? ?? const <Object?>[])
        if (day is Map<String, dynamic>)
          ReportSheetDayData(
            completion: (day['completion'] as num?)?.toInt() ?? 0,
            exercises: (day['exercises'] as List<Object?>? ?? const <Object?>[])
                .whereType<String>()
                .toList(growable: false),
            assigned: switch (day['assigned']) {
              final num n when n > 0 => n.toInt(),
              _ => null,
            },
            // 그날 완료한 개인운동 수(#3115). 없는 옛 응답이면 운동 기록에서 센다.
            assignedDone: switch (day['assigned_done']) {
              final num n when n >= 0 => n.toInt(),
              _ => null,
            },
          ),
    ],
    answers: answers,
  );
}

/// `MemberWeeklyFeedbackOut` 한 건. 답을 내지 않았거나 읽지 못하면 null.
///
/// `submitted` 가 false 면 서버가 빈 값을 채워 보낸다 — 그 값을 답으로 읽지
/// 않는다.
ReportSheetAnswersData? reportSheetAnswersFromJson(Map<String, dynamic> json) {
  if (json['submitted'] != true) return null;
  String text(String key) {
    final Object? value = json[key];
    return value is String ? value : '';
  }

  return ReportSheetAnswersData.fromWire(
    condition: text('condition'),
    intensity: text('intensity'),
    painArea: text('pain_area'),
    painOn: text('pain_on'),
    note: text('note'),
  );
}
