import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 추천 운동 한 줄 — `레그프레스 · 4세트 × 12회 · 60kg · 휴식 90초`.
///
/// 엔티티가 아니라 여기서 만든다. 세트·분·초 같은 단위는 로케일마다 다른데
/// 도메인 엔티티는 [AppLocalizations] 에 닿을 수 없어, 예전에는 영어 화면에서도
/// 한글 단위가 그대로 나왔다(#1933).
///
/// 값은 트레이너가 적은 문자열 그대로다 — "자체중량"·"10~12회" 처럼 숫자가
/// 아닐 수 있다(#709). 그래서 숫자로 읽히는 값만 단위를 붙여 옮기고, 그렇지
/// 않으면 적은 대로 보여 준다. 임의로 숫자만 뽑아내면 트레이너의 표현이 사라진다.
String coachRoutineExerciseLabel(
  AppLocalizations l,
  CoachRoutineExercise exercise,
) {
  final String detail = _detail(l, exercise);
  return detail.isEmpty ? exercise.name : '${exercise.name} · $detail';
}

/// 이름 뒤에 붙는 요약. 값이 하나도 없으면 빈 문자열이다.
String _detail(AppLocalizations l, CoachRoutineExercise exercise) {
  final String sets = _unit(exercise.sets, l.exSetsCount);
  final String reps = _unit(exercise.reps, l.exRepsCount);
  return <String>[
    if (sets.isNotEmpty && reps.isNotEmpty)
      '$sets × $reps'
    else if (sets.isNotEmpty)
      sets
    else if (reps.isNotEmpty)
      reps,
    if (exercise.duration.isNotEmpty)
      _unit(exercise.duration, l.exDurationMinutes),
    // `-` 는 트레이너 편집기가 "중량 없음" 자리에 채워 두는 값이다.
    if (exercise.weight.isNotEmpty && exercise.weight != '-') exercise.weight,
    if (exercise.rest.isNotEmpty) _unit(exercise.rest, l.exRestSeconds),
  ].join(' · ');
}

/// 숫자로 읽히면 [format] 으로 단위를 붙이고, 아니면 적힌 그대로 둔다.
String _unit(String value, String Function(int) format) {
  final int? number = int.tryParse(value.trim());
  return number == null ? value : format(number);
}
