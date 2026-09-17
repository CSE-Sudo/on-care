import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/coach_routine_detail.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 추천 운동 줄의 단위가 로케일을 따라가는지. (#1933)
///
/// 예전에는 엔티티가 `'$sets세트'` 처럼 한글을 직접 이어 붙여, 영어 화면에서도
/// `Squat · 4세트 × 12 · 휴식 60초` 가 나왔다.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  const CoachRoutineExercise strength = CoachRoutineExercise(
    name: '레그프레스',
    sets: '4',
    reps: '12',
    weight: '60kg',
    rest: '90',
  );

  test('한국어는 예전 그대로 읽힌다', () {
    expect(
      coachRoutineExerciseLabel(ko, strength),
      '레그프레스 · 4세트 × 12회 · 60kg · 휴식 90초',
    );
  });

  test('영어 줄에는 한글이 남지 않는다', () {
    final String label = coachRoutineExerciseLabel(en, strength);
    expect(label, contains('4 sets'));
    expect(label, contains('12 reps'));
    expect(label, contains('Rest 90s'));
    expect(
      RegExp(r'[가-힣]').hasMatch(label.replaceFirst(strength.name, '')),
      isFalse,
    );
  });

  test('분 단위도 로케일을 따른다', () {
    const CoachRoutineExercise cardio = CoachRoutineExercise(
      name: '트레드밀',
      duration: '20',
    );
    expect(coachRoutineExerciseLabel(ko, cardio), '트레드밀 · 20분');
    expect(coachRoutineExerciseLabel(en, cardio), '트레드밀 · 20 min');
  });

  test('숫자가 아닌 값은 트레이너가 적은 그대로 둔다', () {
    const CoachRoutineExercise freeform = CoachRoutineExercise(
      name: '푸시업',
      sets: '3',
      reps: '10~12회',
      weight: '자체중량',
    );
    expect(
      coachRoutineExerciseLabel(en, freeform),
      '푸시업 · 3 sets × 10~12회 · 자체중량',
    );
  });

  test('값이 하나도 없으면 이름만 남는다', () {
    expect(
      coachRoutineExerciseLabel(en, const CoachRoutineExercise(name: '플랭크')),
      '플랭크',
    );
  });

  test("중량 자리의 '-' 는 빈 값이다", () {
    expect(
      coachRoutineExerciseLabel(
        ko,
        const CoachRoutineExercise(name: '버피', sets: '3', weight: '-'),
      ),
      '버피 · 3세트',
    );
  });
}
