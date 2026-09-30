import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 데모 리포트의 AI 요약 고정본(#2669).
///
/// 데모에는 모델이 없다. 규칙 기반 요약만 내면 실서버에서 늘 보이는 `생성`
/// 배지와 모델이 쓴 듯한 머리 문장을 데모에서 볼 수 없다. 그래서 그 주의
/// **가장 위험한 주의사항 종류**마다 미리 써 둔 머리 문장을 고르고, 근거 줄은
/// 규칙 요약의 것을 그대로 쓴다 — 수치는 리포트 화면이 보여 주는 값과 같다.
///
/// 머리 문장은 숫자를 말하지 않는다. 요일에 따라 시드 수치가 달라져도 문장이
/// 그래프와 어긋나지 않게 하려는 것이다. 근거가 하나도 없는 주는 규칙 요약
/// (`기록 없음`)을 그대로 돌려준다 — 없는 기록을 생성된 문장으로 꾸미지 않는다.
ReportSummary demoGeneratedReportSummary(
  AppLocalizations l,
  WeeklyReport report,
  TrainerClient client,
) {
  final ReportSummary rule = ruleReportSummary(l, report, client);
  if (rule.points.isEmpty) return rule;
  final List<SummaryWatchpoint> watch = summaryWatchpoints(l, report);
  final String kind = watch.isEmpty ? _steady : watch.first.kind;
  final bool english = l.localeName.startsWith('en');
  final Map<String, String Function(String)> lines = english
      ? _headlinesEn
      : _headlinesKo;
  final String Function(String)? line = lines[kind];
  if (line == null) return rule;
  return ReportSummary(
    headline: line(client.name),
    points: rule.points,
    generatedBy: 'llm',
  );
}

const String _steady = 'steady';

final Map<String, String Function(String)> _headlinesKo =
    <String, String Function(String)>{
      _steady: (n) =>
          '$n님은 이번 주 운동과 식단을 계획대로 잘 이어 갔어요. 지금 리듬을 '
          '지키면서 다음 주에는 운동 강도를 조금 올려 봐도 좋겠습니다.',
      'completion': (n) =>
          '$n님은 이번 주 운동 이행이 주춤했어요. 일정이 빠듯했는지 먼저 물어보고, '
          '다음 주는 짧은 루틴부터 다시 붙여 보는 것을 권해 드려요.',
      'skipped': (n) =>
          '$n님이 이번 주 몇몇 운동을 건너뛰었어요. 통증이나 난이도 때문인지 '
          '확인하고, 대신할 동작을 함께 정해 두면 좋겠습니다.',
      'sodium': (n) =>
          '$n님은 이번 주 짠 식사가 잦았어요. 국물과 가공식품을 줄이는 작은 '
          '목표 하나를 함께 정해 보세요.',
      'sugar': (n) =>
          '$n님은 이번 주 단 음식과 음료가 잦았어요. 간식을 과일이나 견과로 '
          '바꾸는 것부터 제안해 보세요.',
      'calories': (n) =>
          '$n님의 이번 주 섭취 열량이 목표에서 벗어났어요. 끼니를 거르거나 몰아 '
          '먹은 날이 있었는지 식단 기록을 함께 짚어 보세요.',
      'macro': (n) =>
          '$n님은 이번 주 탄수화물·단백질·지방 배분이 목표와 달랐어요. 끼니 '
          '구성을 함께 점검해 균형을 맞춰 보세요.',
    };

final Map<String, String Function(String)> _headlinesEn =
    <String, String Function(String)>{
      _steady: (n) =>
          '$n kept workouts and meals on plan this week. Hold this rhythm '
          'and consider nudging the training intensity up next week.',
      'completion': (n) =>
          "$n's workouts slipped this week. Ask whether the schedule was "
          'tight, then rebuild with a shorter routine next week.',
      'skipped': (n) =>
          '$n skipped a few exercises this week. Check whether pain or '
          'difficulty was the reason and agree on substitutes together.',
      'sodium': (n) =>
          '$n had salty meals often this week. Set one small goal together, '
          'such as cutting back on soups and processed foods.',
      'sugar': (n) =>
          '$n had sweets and sugary drinks often this week. Start by '
          'suggesting fruit or nuts as snacks instead.',
      'calories': (n) =>
          "$n's intake drifted from the calorie goal this week. Review the "
          'meal log together for skipped or oversized meals.',
      'macro': (n) =>
          "$n's carb, protein and fat split differed from the goals this "
          'week. Go over meal composition together to rebalance it.',
    };
