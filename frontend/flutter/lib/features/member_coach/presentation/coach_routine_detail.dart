import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart'
    show exerciseWeightLabel;
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 추천 운동 한 줄 — `레그프레스 · 4세트 · 12회 · 60kg · 휴식 90초`.
///
/// 엔티티가 아니라 여기서 만든다. 세트·분·초 같은 단위는 로케일마다 다른데
/// 도메인 엔티티는 [AppLocalizations] 에 닿을 수 없어, 예전에는 영어 화면에서도
/// 한글 단위가 그대로 나왔다(#1933).
///
/// 값은 **수**다(#1904). 서버가 `_loose_int`·`_loose_float` 로 이미 숫자만 남겨
/// 내려보내므로(`"자체중량"` → null, `"10회"` → 10) 화면이 문자열을 다시 되짚을
/// 일이 없다. 적히지 않은 칸은 건너뛴다 — 0 을 적으면 트레이너가 정한 값처럼
/// 읽힌다.
String coachRoutineExerciseLabel(
  AppLocalizations l,
  CoachRoutineExercise exercise,
) {
  final String detail = _detail(l, exercise);
  return detail.isEmpty ? exercise.name : '${exercise.name} · $detail';
}

/// 이름 뒤에 붙는 요약. 값이 하나도 없으면 빈 문자열이다.
///
/// 구분자는 앱의 나머지 표기와 같은 ` · ` 다 — 세트와 횟수 사이만 `×` 를 쓰면
/// 같은 값이 화면마다 다른 모양으로 읽힌다(#1904).
String _detail(AppLocalizations l, CoachRoutineExercise exercise) {
  final int? sets = exercise.sets;
  final int? reps = exercise.reps;
  final double? weight = exercise.weight;
  final int? duration = exercise.duration;
  final int? rest = exercise.rest;
  return <String>[
    if (sets != null && sets > 0) l.exSetsCount(sets),
    if (reps != null && reps > 0) l.exRepsCount(reps),
    if (duration != null && duration > 0) l.exDurationMinutes(duration),
    if (weight != null && weight > 0) exerciseWeightLabel(l, weight),
    if (rest != null && rest > 0) l.exRestSeconds(rest),
  ].join(' · ');
}
