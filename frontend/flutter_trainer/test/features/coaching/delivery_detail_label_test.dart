import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/personal_routine_box.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_section.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

late AppLocalizations l;

void main() {
  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('ko'));
  });

  // 전송 이력은 "무엇을 보냈나" 를 적는 자리다. 이름만 적으면 몇 세트 몇 회
  // 몇 kg 로 보냈는지 보려고 일정을 다시 열어야 한다. (#2225)
  group('보낸 프로그램 한 줄', () {
    test('근력은 세트·횟수·중량까지 적는다', () {
      const item = ProgramItem(
        name: '레그프레스',
        type: '근력',
        sets: 4,
        reps: 10,
        weight: 70,
      );

      expect(programItemAmount(l, item), '4세트 · 10회 · 70kg');
    });

    test('버티는 운동은 횟수 대신 초로 적는다', () {
      const item = ProgramItem(
        name: '플랭크',
        type: '근력',
        sets: 3,
        reps: 12,
        holdSeconds: 45,
        weight: 0,
      );

      expect(programItemAmount(l, item), '3세트 · 45초 · 0kg');
    });

    test('근력이 아니면 시간으로 적는다', () {
      const item = ProgramItem(name: '트레드밀', type: '유산소', duration: 25);

      expect(programItemAmount(l, item), '25분');
    });
  });

  group('보낸 개인운동 한 줄', () {
    test('근력은 세트·횟수·중량까지 적는다', () {
      const routine = AssignedRoutine(
        id: 'r1',
        name: '덤벨컬',
        minutes: 15,
        type: '근력',
        reason: '',
        source: 'trainer',
        sets: 3,
        reps: 12,
        weight: 8,
      );

      expect(assignedRoutineLabel(l, routine), '덤벨컬 · 근력 · 3세트 · 12회 · 8kg');
    });

    test('근력이 아니면 시간으로 적는다', () {
      const routine = AssignedRoutine(
        id: 'r2',
        name: '저녁 산책',
        minutes: 20,
        type: '유산소',
        reason: '',
        source: 'trainer',
      );

      expect(assignedRoutineLabel(l, routine), '저녁 산책 · 유산소 · 20분');
    });
  });
}
