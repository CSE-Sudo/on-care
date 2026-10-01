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
/// 이 응답에는 끼니 기록 횟수가 없어 `끼니 기록일` 은 `미집계` 로 선다 —
/// 트레이너 웹도 서버에서 읽을 때 같다. [today] 는 이번 주인지 가를 기준일로,
/// 없으면 지금 서울 시각이다.
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
    weekCompletion: ints('week_completion'),
    sodiumWeek: ints('sodium_week'),
    caloriesWeek: ints('calories_week'),
    sugarWeek: doubles('sugar_week'),
    carbsWeek: doubles('carbs_week'),
    proteinWeek: doubles('protein_week'),
    fatWeek: doubles('fat_week'),
    calorieTarget: optInt('calorie_target'),
    sodiumTarget: optInt('sodium_target'),
    sugarTarget: optDouble('sugar_target'),
    carbsTarget: optDouble('carbs_target'),
    proteinTarget: optDouble('protein_target'),
    fatTarget: optDouble('fat_target'),
    days: <ReportSheetDay>[
      for (final Object? day
          in json['days'] as List<Object?>? ?? const <Object?>[])
        if (day is Map<String, dynamic>)
          ReportSheetDayData(
            completion: (day['completion'] as num?)?.toInt() ?? 0,
            exercises: (day['exercises'] as List<Object?>? ?? const <Object?>[])
                .whereType<String>()
                .toList(growable: false),
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
