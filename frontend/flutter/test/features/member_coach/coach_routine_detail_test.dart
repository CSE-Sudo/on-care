import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/coach_routine_detail.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 추천 운동 줄의 단위가 로케일을 따라가는지. (#1933)
///
/// 예전에는 엔티티가 `'$sets세트'` 처럼 한글을 직접 이어 붙여, 영어 화면에서도
/// `Squat · 4세트 × 12 · 휴식 60초` 가 나왔다.
///
/// 값은 수로 든다(#1904). 서버(`ProgramDraftExercise`)가 `_loose_int` 로 이미
/// 숫자만 남겨 내려보내므로, 화면이 문자열을 다시 되짚을 일이 없다.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  const CoachRoutineExercise strength = CoachRoutineExercise(
    name: '레그프레스',
    sets: 4,
    reps: 12,
    weight: 60,
    rest: 90,
  );

  test('한국어는 단위를 붙여 읽힌다', () {
    // 구분자는 앱의 나머지 표기와 같은 ` · ` 다 — 세트·횟수 사이만 `×` 를 쓰면
    // 같은 값이 화면마다 다른 모양이 된다(#1904).
    expect(
      coachRoutineExerciseLabel(ko, strength),
      '레그프레스 · 4세트 · 12회 · 60kg · 휴식 90초',
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
      duration: 20,
    );
    expect(coachRoutineExerciseLabel(ko, cardio), '트레드밀 · 20분');
    expect(coachRoutineExerciseLabel(en, cardio), '트레드밀 · 20 min');
  });

  test('값이 하나도 없으면 이름만 남는다', () {
    expect(
      coachRoutineExerciseLabel(en, const CoachRoutineExercise(name: '플랭크')),
      '플랭크',
    );
  });

  test('적지 않은 칸은 건너뛴다 — 0 을 적으면 정한 값처럼 읽힌다', () {
    expect(
      coachRoutineExerciseLabel(
        ko,
        const CoachRoutineExercise(name: '버피', sets: 3, weight: 0),
      ),
      '버피 · 3세트',
    );
  });

  test('서버가 수로 보낸 값이 줄에 그대로 실린다', () {
    // 예전 매퍼는 `_str(entry['sets'])` 로 받아, 수로 온 값을 전부 빈 문자열로
    // 떨어뜨렸다 — 실서버에서는 이름만 남고 세트·횟수·중량이 사라졌다.
    final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
      'id': 'r-wire',
      'name': '하체',
      'minutes': 40,
      'type': '근력',
      'reason': '',
      'source': 'trainer',
      'exercises': <Object?>[
        <String, Object?>{
          'name': '레그프레스',
          'sets': 4,
          'reps': 12,
          'weight': 62.5,
          'memo': '',
        },
      ],
    });

    expect(
      coachRoutineExerciseLabel(ko, routine.exercises.single),
      '레그프레스 · 4세트 · 12회 · 62.5kg',
    );
  });
}
