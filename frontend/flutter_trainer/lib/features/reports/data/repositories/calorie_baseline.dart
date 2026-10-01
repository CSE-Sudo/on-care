import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';

/// ① 섭취 칼로리 줄이 견주는 **평소** — 직전 몇 주의 하루 평균. (#2232)
///
/// 회원은 자기 앱에서 이번 주 칼로리를 이미 본다. 트레이너에게 그것만 다시
/// 보여 주면 새로 아는 것이 없다. 트레이너가 여기서 답해야 하는 질문은
/// `2,340kcal 이 이 사람에게 많은 수인가` 인데, 그 기준이 화면에 없으면
/// 판단이 기억에서 나온다 — 회원이 열다섯 명이면 기억은 틀린다.
const int kCalorieBaselineWeeks = 4;

/// 견줄 주 수를 넷으로 둔 까닭: 직전 한 주를 기준으로 삼으면 그 주가 아프거나
/// 출장이었을 때 **기준 자체가 거짓**이 된다. 평범한 이번 주가 `확 늘었다` 로
/// 읽히고, 트레이너는 그 주에 없던 문제를 고치려 든다. 넉 주는 그런 한 주에
/// 휘둘리지 않는, 이 회원의 평소에 가깝다.
///
/// 기록한 날만 센다. 안 적은 날을 0 으로 세면 성실히 적은 주가 오히려 적게
/// 먹은 주로 보인다 — ① 의 다른 평균과 같은 규칙이다.
///
/// 아직 읽히지 않았거나 넉 주 내내 기록이 없으면 null 이고, 그때는 비교 줄을
/// 아예 그리지 않는다. `평소 0kcal` 은 모른다는 뜻이 아니라 굶었다는 뜻이다.
///
/// 값은 그 주 리포트가 함께 싣고 온다([WeeklyReport.calorieBaseline], #2863).
/// 예전에는 직전 4주 리포트를 같은 family 로 다시 읽어 칼로리 배열만 꺼냈다 —
/// 회원 한 명을 열 때마다 리포트·회원 피드백 요청이 4주치 더 나갔다. 실서버는
/// `WeeklyReportOut.calorie_baseline` 으로, 데모는 drift 이력으로 같은 규칙을
/// 센다.
final calorieBaselineProvider = Provider.autoDispose.family<double?, ReportKey>(
  (ref, key) => ref.watch(
    weeklyReportProvider(
      key,
    ).select((AsyncValue<WeeklyReport> r) => r.valueOrNull?.calorieBaseline),
  ),
  name: 'calorieBaseline',
);
