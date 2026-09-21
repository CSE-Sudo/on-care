import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';

/// 프로그램 편집기가 들고 있는 운동 한 행의 초안.
///
/// 회원 앱의 운동 추가 시트와 같은 칸을 받는다(#1276) — 날짜·종류·이름·
/// 시간(또는 세트·횟수·중량)·강도, 그리고 그 값들에서 나오는 예상 칼로리.
///
/// 이름만 컨트롤러다. 나머지는 숫자·날짜·선택값이라 자유 입력이 아니고,
/// 편집기가 값을 직접 바꾸고 setState 한다.
class ProgramDraft {
  ProgramDraft({
    required String name,
    required this.type,
    required this.date,
    required this.minutes,
    required this.sets,
    required this.reps,
    required this.holdSeconds,
    required this.isHold,
    required this.weight,
    required this.intensity,
  }) : name = TextEditingController(text: name);

  factory ProgramDraft.fromItem(ProgramItem item) => ProgramDraft(
    name: item.name,
    type: normaliseRoutineType(item.type),
    date: item.date ?? _today(),
    minutes: item.duration ?? 30,
    sets: item.sets ?? 3,
    reps: item.reps ?? 10,
    holdSeconds: item.holdSeconds ?? 60,
    // 저장된 행이 든 칸이 곧 이 운동을 재는 단위다 — 초가 있으면 초로
    // 열린다(#1969).
    isHold: item.holdSeconds != null,
    weight: item.weight ?? 20,
    intensity: normaliseRoutineIntensity(item.intensity),
  );

  /// 새 운동 행의 기본값 — 근력 3세트 10회 20kg, 보통 강도.
  ///
  /// [date] 는 이 운동이 속한 세션의 날짜를 그대로 받는다(#1489 후속) — 운동
  /// 행마다 날짜를 따로 고르게 하면 세션 날짜와 어긋날 수 있는 두 번째
  /// 입력이 생긴다. 넘기지 않으면 오늘로 떨어진다.
  factory ProgramDraft.empty({DateTime? date}) => ProgramDraft(
    name: '',
    type: '근력',
    date: date ?? _today(),
    minutes: 30,
    sets: 3,
    reps: 10,
    holdSeconds: 60,
    // 새 행은 회로 연다. 이름을 적으면 종목표가 버티는 운동이라고 할 때
    // 초로 바뀐다(`syncMeasureToName`).
    isHold: false,
    weight: 20,
    intensity: 'moderate',
  );

  static DateTime _today() {
    final DateTime now = nowKst();
    return DateTime(now.year, now.month, now.day);
  }

  final TextEditingController name;

  /// 운동 유형 계약값.
  String type;

  /// 이 운동을 하는 날.
  DateTime date;

  /// 유산소·스트레칭·기타의 운동 시간(분). 근력은 세트로 재므로 쓰지 않는다.
  int minutes;

  /// 근력의 세트 수·한 세트당 횟수·중량(kg). 다른 유형에서는 쓰지 않는다.
  ///
  /// 시간과 따로 들고 있어야 유형을 근력↔유산소로 오갈 때 각자의 값이 남는다 —
  /// 하나로 쓰면 30분이 30세트가 되어 돌아온다.
  int sets;
  int reps;

  /// 버티는 운동이면 한 세트를 버티는 시간(초). [reps] 와 한 자리를 나눠
  /// 쓰지만 값은 따로 들고 있어야, 회↔초를 오갈 때 각자의 값이 남는다 —
  /// 한 칸을 같이 쓰면 10회가 10초로 돌아온다. (#1969)
  int holdSeconds;

  /// 지금 이 운동을 초로 재는가. 이름 해석이 기본값을 주고, 트레이너가
  /// 고르면 그 선택이 이긴다([measureChosenByUser]).
  bool isHold;

  /// 트레이너가 회↔초를 직접 골랐는가. 고른 뒤에는 이름이 바뀌어도
  /// 종목표가 그 선택을 덮지 않는다.
  bool measureChosenByUser = false;

  double weight;

  /// 운동 강도 계약값.
  String intensity;

  bool get isStrength => type == '근력';

  /// 지금 이름이 **버티는 운동**이면 초로 재도록 맞춘다. (#1969)
  ///
  /// 트레이너가 직접 고른 뒤에는 아무것도 하지 않는다 — 종목표는 기본값일
  /// 뿐이고, 고르는 것은 짜는 사람이다. 이름 칸이 바뀔 때 부른다.
  void syncMeasureToName() {
    if (measureChosenByUser) return;
    isHold = isIsometricExerciseName(name.text);
  }

  /// 트레이너가 회↔초를 골랐다.
  void chooseMeasure({required bool hold}) {
    isHold = hold;
    measureChosenByUser = true;
  }

  /// 저장·칼로리 계산이 쓰는 분. 근력이면 세트에서 환산한 값이다 — 서버는
  /// 여전히 분을 요구하고 주간 운동 시간도 분으로 센다.
  int get effectiveMinutes => isStrength ? minutesFromSets(sets) : minutes;

  /// 예상 소모 칼로리. 운동 이름이 비어 있으면 null 이다 — 이름 없이 확정된
  /// 숫자를 띄우지 않는다(#1312).
  RoutineCalorieEstimate? get calories => estimateRoutineCalories(
    name: name.text,
    type: type,
    minutes: effectiveMinutes,
    intensity: intensity,
  );

  /// 이 행을 저장 형태로. 근력이 아니면 세트·횟수·중량을 싣지 않는다 —
  /// 유산소를 세트로 세는 화면은 없다.
  ProgramItem toItem({String session = ''}) => ProgramItem(
    name: name.text.trim(),
    type: type,
    date: date,
    duration: isStrength ? null : minutes,
    sets: isStrength ? sets : null,
    // 한 세트는 회로든 초로든 한 번만 잰다 — 고르지 않은 쪽은 비운다(#1969).
    reps: isStrength && !isHold ? reps : null,
    holdSeconds: isStrength && isHold ? holdSeconds : null,
    weight: isStrength ? weight : null,
    intensity: intensity,
    session: session,
  );

  void dispose() {
    name.dispose();
  }
}
