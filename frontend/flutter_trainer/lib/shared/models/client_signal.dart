import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 목록의 PT 관리 신호 종류. (#2204)
///
/// "누가 흐름이 끊겼나, 누가 목표에서 벗어났나, 누가 불편을 호소하나" 에 답한다.
/// 선언 순서가 곧 **급한 순서**다 — 목록 배지·우선순위 정렬이 이 순서를 쓴다.
///
/// 답장 대기를 뺀 일곱 가지는 서버가 계산해 로스터에 싣는다(`signals`, 기준은
/// 백엔드 `client_signals.py`). 답장 대기만 앱이 안 읽은 메시지 수로 센다 —
/// 실시간 값이라 로스터 시점으로 굳히면 답장한 뒤에도 배지가 남는다.
enum ClientSignalKind {
  discomfort('discomfort'),
  recordGap('record_gap'),
  noShow('no_show'),
  routineMissed('routine_missed'),
  exerciseGoalLow('exercise_goal_low'),
  calorieOff('calorie_off'),
  proteinLow('protein_low'),
  unanswered('unanswered');

  const ClientSignalKind(this.wire);

  /// 서버 계약값(`kind`). **번역하지 않는다.**
  final String wire;

  /// 필터 칩처럼 수치 없이 종류만 말하는 자리의 이름.
  String label(AppLocalizations l) => switch (this) {
    ClientSignalKind.discomfort => l.clientsSignalDiscomfort,
    ClientSignalKind.recordGap => l.clientsSignalRecordGap,
    ClientSignalKind.noShow => l.clientsSignalNoShow,
    ClientSignalKind.routineMissed => l.clientsSignalRoutineMissed,
    ClientSignalKind.exerciseGoalLow => l.clientsSignalExerciseGoalLow,
    ClientSignalKind.calorieOff => l.clientsSignalCalorieOff,
    ClientSignalKind.proteinLow => l.clientsSignalProteinLow,
    ClientSignalKind.unanswered => l.clientsSignalUnanswered,
  };

  /// 배지 색. 예전 배지와 같은 규칙이다 — 빨강 = 주의, 남색 =
  /// 트레이너가 처리할 일(답장). 주의의 세기를 주황·회색으로 나누지 않는다:
  /// 예전에 완만한 주의를 주황으로 두었다가, 회원이 빨갛게 보는 것을 트레이너는
  /// 주황으로 봐서 두 앱이 같은 사실을 다른 세기로 말했다(#690). 급한 정도는
  /// 색이 아니라 배지의 순서가 말한다.
  AppTagTone get tone => this == ClientSignalKind.unanswered
      ? AppTagTone.brand
      : AppTagTone.danger;

  /// 이 신호를 다루는 회원 상세 탭 — 대시보드 할 일이 누르면 가는 곳.
  /// 몸 상태·출석은 대화로 먼저 묻고, 식단 신호는 식단, 나머지는 운동이다.
  String get detailSection => switch (this) {
    ClientSignalKind.discomfort ||
    ClientSignalKind.noShow ||
    ClientSignalKind.unanswered => 'chat',
    ClientSignalKind.calorieOff || ClientSignalKind.proteinLow => 'diet',
    ClientSignalKind.recordGap ||
    ClientSignalKind.routineMissed ||
    ClientSignalKind.exerciseGoalLow => 'workout',
  };

  /// 식단 신호인가 — 대시보드 할 일의 `식단` 분류.
  bool get isDiet =>
      this == ClientSignalKind.calorieOff ||
      this == ClientSignalKind.proteinLow;

  /// 회원의 상태에서 나온 신호인가. 답장 대기는 트레이너 자신의 받은편지함이라
  /// `주의 회원` 에 세지 않는다.
  bool get isAttention => this != ClientSignalKind.unanswered;

  static ClientSignalKind? fromWire(String raw) {
    for (final kind in ClientSignalKind.values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

/// 신호 하나와 그 근거 값. 신호마다 쓰는 값만 채워진다.
class ClientSignal {
  /// Creates a signal.
  const ClientSignal(
    this.kind, {
    this.days,
    this.count,
    this.percent,
    this.over,
  });

  /// 서버 `ClientSignalOut` JSON. 모르는 `kind` 는 null — 새 신호가 서버에 먼저
  /// 생겨도 앱이 깨지지 않고 그 신호만 건너뛴다.
  static ClientSignal? fromJson(Map<String, Object?> json) {
    final kind = ClientSignalKind.fromWire(
      json['kind'] is String ? json['kind']! as String : '',
    );
    if (kind == null) return null;
    int? n(Object? v) => v is num ? v.toInt() : null;
    final direction = json['direction'];
    return ClientSignal(
      kind,
      days: n(json['days']),
      count: n(json['count']),
      percent: n(json['percent']),
      over: direction == 'over'
          ? true
          : direction == 'under'
          ? false
          : null,
    );
  }

  final ClientSignalKind kind;

  /// 기록 끊김(마지막 기록부터 지난 날, 30 이면 30일 넘게)·배정 루틴 미수행(걸려
  /// 있던 날 수).
  final int? days;

  /// 노쇼·취소 반복 횟수.
  final int? count;

  /// 운동 목표 달성률·칼로리 이탈 폭·단백질 섭취율(%).
  final int? percent;

  /// 칼로리 이탈 방향 — true 면 과다, false 면 부족.
  final bool? over;

  /// 서버 JSON 모양. 데모 로스터가 같은 모양으로 저장한다.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wire,
    'days': ?days,
    'count': ?count,
    'percent': ?percent,
    if (over != null) 'direction': over! ? 'over' : 'under',
  };

  /// 목록 배지 문구 — 근거 값이 있으면 함께 말한다(`기록 끊김 4일`).
  String badgeLabel(AppLocalizations l) => switch (kind) {
    ClientSignalKind.recordGap when days != null =>
      days! >= 30
          ? l.clientsSignalRecordGapLong
          : l.clientsSignalRecordGapDays(days!),
    ClientSignalKind.noShow when count != null => l.clientsSignalNoShowCount(
      count!,
    ),
    ClientSignalKind.exerciseGoalLow when percent != null =>
      l.clientsSignalExerciseGoalLowPercent(percent!),
    ClientSignalKind.calorieOff when over != null =>
      over! ? l.clientsSignalCalorieOver : l.clientsSignalCalorieUnder,
    _ => kind.label(l),
  };

  /// 할 일처럼 **무엇을 얼마나** 손볼지 정하는 자리의 문구 — 근거 수치를
  /// 빠짐없이 붙인다(`칼로리 22% 과다`). 목록 배지([badgeLabel])는 훑는
  /// 자리라 짧게 둔다.
  String detailLabel(AppLocalizations l) => switch (kind) {
    ClientSignalKind.calorieOff when over != null && percent != null =>
      over!
          ? l.clientsSignalCalorieOverPercent(percent!)
          : l.clientsSignalCalorieUnderPercent(percent!),
    ClientSignalKind.proteinLow when percent != null =>
      l.clientsSignalProteinPercent(percent!),
    ClientSignalKind.routineMissed when days != null =>
      l.clientsSignalRoutineMissedDays(days!),
    _ => badgeLabel(l),
  };
}

/// [signals] 를 급한 순으로 — 서버 순서를 믿되, 데모 데이터나 옛 응답이 순서를
/// 어겨도 목록은 같은 규칙으로 선다.
List<ClientSignal> sortedSignals(Iterable<ClientSignal> signals) =>
    signals.toList()..sort((a, b) => a.kind.index.compareTo(b.kind.index));

/// [client] 의 목록 배지 전부, 급한 순. 답장 대기는 안 읽은 메시지가 있을 때만
/// 맨 뒤에 붙는다 — `답장 필요` 카운터가 이미 그 수를 보여 준다.
List<ClientSignal> rosterSignalsFor(TrainerClient client, {int unread = 0}) =>
    <ClientSignal>[
      ...sortedSignals(client.signals),
      if (unread > 0) const ClientSignal(ClientSignalKind.unanswered),
    ];

/// `주의 회원` 인가 — 답장 대기를 뺀 신호가 하나라도 있다. 대시보드의 주의 회원
/// 수와 그걸 눌러 여는 목록이 같은 규칙을 쓴다.
bool needsAttention(TrainerClient client) =>
    client.signals.any((s) => s.kind.isAttention);
