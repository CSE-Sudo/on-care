/// 버티는 운동의 초 — 한 세트를 **한 번만** 잰다. (#1969)
///
/// 플랭크·행잉처럼 버티는 운동은 한 세트를 몇 회가 아니라 몇 초로 잰다. 초를
/// 담을 칸이 없던 동안 트레이너는 `플랭크 3세트 · 60초` 를 **이름에** 적을
/// 수밖에 없었고, 이름에 적힌 글자는 어떤 집계에도 잡히지 않았다.
///
/// 여기서 지키는 것은 셋이다.
///
/// 1. 홀드 초는 `reps` 와 **한 자리를 나눠 쓴다** — 둘이 한 줄에 함께 서지 않는다.
/// 2. 화면에 읽히는 한 줄이 회가 아니라 초로 적힌다.
/// 3. 이름 해석이 `회/초` 의 기본값을 준다 — 확정이 아니라 기본값이다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/coaching/data/dtos/routine_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/exercise_estimate.dart';
import 'package:oncare_trainer/features/schedule/data/dtos/schedule_dtos.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/presentation/models/program_draft.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/session_program_section.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

void main() {
  group('이름 해석이 회/초의 기본값을 준다', () {
    test('플랭크는 버티는 운동이다', () {
      expect(isIsometricExerciseName('플랭크'), isTrue);
      // 트레이너가 적는 말이 종목 이름 그대로는 아니다.
      expect(isIsometricExerciseName('사이드 플랭크'), isTrue);
    });

    test('회로 재는 종목은 그대로다', () {
      expect(isIsometricExerciseName('스쿼트'), isFalse);
      expect(isIsometricExerciseName('벤치프레스'), isFalse);
    });
  });

  group('ProgramItem', () {
    test('버티는 운동은 초를 들고 횟수를 비운다', () {
      const item = ProgramItem(
        name: '플랭크',
        sets: 3,
        reps: 10,
        holdSeconds: 60,
        weight: 0,
      );

      final normalised = item.byType;

      expect(normalised.holdSeconds, 60);
      // 한 세트를 두 단위로 적으면 어느 쪽이 맞는지 알 수 없다.
      expect(normalised.reps, isNull);
      expect(normalised.sets, 3);
    });

    test('유산소는 홀드도 들지 않는다', () {
      const item = ProgramItem(
        name: '걷기',
        type: '유산소',
        duration: 30,
        holdSeconds: 60,
      );

      expect(item.byType.holdSeconds, isNull);
    });

    test('계약 형태를 오가도 초가 살아남는다', () {
      const item = ProgramItem(
        name: '플랭크',
        sets: 3,
        holdSeconds: 45,
        weight: 0,
      );

      final restored = programItemFromJson(programItemToJson(item));

      expect(restored.holdSeconds, 45);
      expect(restored.reps, isNull);
    });
  });

  group('ProgramDraft', () {
    test('초가 적힌 행은 초 칸으로 열린다', () {
      const item = ProgramItem(
        name: '플랭크',
        sets: 3,
        holdSeconds: 45,
        weight: 0,
      );

      final draft = ProgramDraft.fromItem(item);
      addTearDown(draft.dispose);

      expect(draft.isHold, isTrue);
      expect(draft.holdSeconds, 45);
      expect(draft.toItem().holdSeconds, 45);
      expect(draft.toItem().reps, isNull);
    });

    test('이름이 버티는 운동이면 초로 묻는다', () {
      final draft = ProgramDraft.empty();
      addTearDown(draft.dispose);

      expect(draft.isHold, isFalse);
      draft.name.text = '플랭크';
      draft.syncMeasureToName();

      expect(draft.isHold, isTrue);
    });

    test('트레이너가 고른 단위는 이름이 덮지 않는다', () {
      final draft = ProgramDraft.empty();
      addTearDown(draft.dispose);

      // 종목표는 기본값일 뿐이고, 고르는 것은 짜는 사람이다.
      draft.chooseMeasure(hold: false);
      draft.name.text = '플랭크';
      draft.syncMeasureToName();

      expect(draft.isHold, isFalse);
      expect(draft.toItem().reps, 10);
      expect(draft.toItem().holdSeconds, isNull);
    });
  });

  group('배정 payload', () {
    test('홀드를 보내면 횟수는 실리지 않는다', () {
      const routine = AssignedRoutine(
        id: '',
        name: '플랭크',
        minutes: 9,
        type: '근력',
        reason: '코어 안정화',
        source: 'trainer',
        sets: 3,
        reps: 10,
        holdSeconds: 60,
        weight: 0,
      );

      final body = assignRoutineToJson(routine);

      expect(body['hold_seconds'], 60);
      expect(body['reps'], isNull);
    });

    test('회로 재는 배정은 홀드를 싣지 않는다', () {
      const routine = AssignedRoutine(
        id: '',
        name: '스쿼트',
        minutes: 9,
        type: '근력',
        reason: '하체 근력',
        source: 'trainer',
        sets: 3,
        reps: 12,
        weight: 40,
      );

      final body = assignRoutineToJson(routine);

      expect(body['reps'], 12);
      expect(body['hold_seconds'], isNull);
    });
  });

  testWidgets('프로그램 한 줄은 회가 아니라 초로 읽힌다', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // 행이 규격 토큰(`context.oncare`)을 읽는다 — 앱과 같은 테마를 준다.
        theme: OnCareTheme.light(
          brand: OnCareBrand.trainer,
          density: OnCareDensity.web,
        ),
        home: const Scaffold(
          body: SessionProgramRow(
            index: 0,
            item: ProgramItem(
              name: '플랭크',
                    sets: 3,
              holdSeconds: 60,
              weight: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('60초'), findsOneWidget);
    expect(find.textContaining('60회'), findsNothing);
  });
}
