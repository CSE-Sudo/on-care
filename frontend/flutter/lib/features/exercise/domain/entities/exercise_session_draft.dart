import 'package:oncare/core/points/points_award.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';

/// 아직 저장하지 않은 운동 기록 한 건 — 추가 시트가 모아 두었다가 한 번에
/// 보내는 값이다. (#2544)
///
/// [sets]·[reps]·[holdSeconds]·[weight] 는 근력 기록에만 있는 값이다 —
/// 근력은 시간이 아니라 세트·횟수·무게로 읽는 운동이라 회원이 적은 수를
/// 그대로 싣는다. 다른 유형은 null 이고, 서버도 근력이 아닌 기록에서는 이
/// 값들을 버린다. (#1262, #1276, #1310)
///
/// [holdSeconds] 는 플랭크처럼 **버티는** 운동이 한 세트를 버틴 시간이고,
/// [reps] 와 한 자리를 나눠 쓴다 — 이 값을 실으면 서버가 횟수를 비운다.
/// 한 세트를 회로든 초로든 한 번만 잰다(#1969).
///
/// [durationSeconds] 는 회원이 시·분·초 휠로 적은 걸린 시간이다(#2071).
/// 보내면 서버가 그 초로 `minutes` 를 다시 계산한다 — 분 칸은 주간 집계와
/// 트레이너웹이 읽으므로 늘 차 있어야 한다. 근력은 분이 세트에서 나오는
/// 값이라 싣지 않는다.
///
/// [calories] 는 화면이 보여 준 미리보기 값이다. 서버는 쓰지 않고 다시
/// 계산하지만(#1312), 서버가 없는 경로(목업 저장소)는 이 값을 기록에 남긴다.
class ExerciseSessionDraft {
  const ExerciseSessionDraft({
    required this.type,
    required this.minutes,
    required this.calories,
    required this.date,
    this.name = '',
    this.intensity = ExerciseIntensity.moderate,
    this.sets,
    this.reps,
    this.holdSeconds,
    this.durationSeconds,
    this.weight,
  });

  final ExerciseType type;
  final int minutes;
  final int calories;

  /// 회원이 달력에서 고른 날.
  final DateTime date;
  final String name;
  final ExerciseIntensity intensity;
  final int? sets;
  final int? reps;
  final int? holdSeconds;
  final int? durationSeconds;
  final double? weight;

  /// 날짜만 바꾼 사본. 추가 시트의 날짜는 모아 둔 운동 전부에 공통이라,
  /// 저장하는 순간의 날짜로 맞춘다.
  ExerciseSessionDraft withDate(DateTime value) => ExerciseSessionDraft(
    type: type,
    minutes: minutes,
    calories: calories,
    date: value,
    name: name,
    intensity: intensity,
    sets: sets,
    reps: reps,
    holdSeconds: holdSeconds,
    durationSeconds: durationSeconds,
    weight: weight,
  );

  /// 화면에 미리 보여 줄 기록 모양. 저장된 기록 줄과 같은 표기 함수
  /// (`exerciseAmountLabel` 등)를 그대로 쓰려고 만든다 — id 는 없다.
  ExerciseSession toPreview() => ExerciseSession(
    dayLabel: '',
    type: type,
    minutes: minutes,
    calories: calories,
    intensity: intensity,
    sets: sets,
    reps: reps,
    holdSeconds: holdSeconds,
    durationSeconds: durationSeconds,
    name: name,
    weight: weight,
    date: date,
  );
}

/// `POST /exercise/sessions` 의 결과 — 저장된 기록들(요청 순서)과 이번 적립
/// 합계. (#2544)
///
/// 적립은 기록마다가 아니라 한 벌이다. 회원에게는 한 번 저장한 일이라 알림도
/// 한 번이다. 서버가 적립을 싣지 않은 응답(옛 목업)이면 [points] 는 null 이다.
class ExerciseSessionsAdded {
  const ExerciseSessionsAdded({required this.sessions, this.points});

  factory ExerciseSessionsAdded.fromJson(Map<String, Object?> json) =>
      ExerciseSessionsAdded(
        sessions: ((json['sessions'] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .map(ExerciseSession.fromJson)
            .toList(growable: false),
        points: PointsAward.fromJson(json['points']),
      );

  final List<ExerciseSession> sessions;
  final PointsAward? points;
}
