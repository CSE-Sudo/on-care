import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/shared/models/client_alerts.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// 프로그램을 짜기 전에 회원 현황이 가리키는 방향. (#2373)
///
/// AI 를 부르지 않는다 — 같은 회원 데이터에는 언제나 같은 방향이 나와야
/// 트레이너가 이 줄을 기준으로 삼을 수 있다.
enum ProgramDirection {
  /// 완료율이 낮다 — 강도를 낮춰 완수 경험부터 만든다.
  lowerIntensity,

  /// 나트륨 초과가 반복된다 — 유산소 비중을 늘린다.
  moreCardio,

  /// 둘 다다.
  lowerIntensityMoreCardio,

  /// 두 신호 모두 없다.
  keep,

  /// 판단할 기록이 없다. 기록이 없는 회원에게 `현재 강도 유지` 라고 하면
  /// 근거 없는 말이 된다.
  noData,
}

/// [client] 의 회원 현황에서 방향을 정한다.
///
/// 기준은 다른 화면과 같은 값을 쓴다 — 이 줄만 다른 선으로 판단하면 같은
/// 회원이 리포트에서는 괜찮고 프로그램 탭에서는 강도를 낮추라는 말을 듣는다.
/// - 완료율: [recordedCompletionMean] < [lowCompletionThreshold]
///   (주의 배지·주간 리포트와 같은 정의)
/// - 나트륨: 이번 주 초과일이 [summarySodiumOverDays] 를 넘을 때. 하루 튄 값은
///   패턴이 아니다 — 주간 리포트의 식단 주의와 같은 선이다.
ProgramDirection programDirectionFor(TrainerClient client) {
  final double? completion = recordedCompletionMean(client);
  final bool hasDiet = client.sodiumWeek.any((mg) => mg > 0);
  if (completion == null && !hasDiet) return ProgramDirection.noData;

  final bool low = completion != null && completion < lowCompletionThreshold;
  final bool sodium = client.sodiumOverDays > summarySodiumOverDays;
  if (low && sodium) return ProgramDirection.lowerIntensityMoreCardio;
  if (low) return ProgramDirection.lowerIntensity;
  if (sodium) return ProgramDirection.moreCardio;
  return ProgramDirection.keep;
}

/// 확정한 구성의 강도가 회원 현황과 어긋나는가 — 프로그램 검토 단계의 강도
/// 확인 줄이 쓴다. (#2374)
///
/// 최근 완료율이 낮은데([programDirectionFor] 가 강도를 낮추라는 회원) 강도를
/// `high` 로 골랐을 때다. 1단계 `권장 방향` 과 같은 판단을 써서, 두 단계가 같은
/// 회원에게 다른 말을 하지 않는다.
bool intensityConflictsWithDirection(TrainerClient client, String intensity) {
  if (intensity != 'high') return false;
  final ProgramDirection direction = programDirectionFor(client);
  return direction == ProgramDirection.lowerIntensity ||
      direction == ProgramDirection.lowerIntensityMoreCardio;
}
