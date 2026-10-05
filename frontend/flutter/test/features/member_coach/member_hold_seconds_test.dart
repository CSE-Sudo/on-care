/// 버티는 근력 운동은 **세트 · 초**로 읽는다. (#3138)
///
/// 서버는 #1969 이후 근력 한 세트를 횟수(`reps`) 또는 버티는 시간
/// (`hold_seconds`) 중 하나로 잰다. 플랭크처럼 버티는 운동이면 `reps` 가 비고
/// 초가 `hold_seconds` 에 실린다. 회원 앱이 이 값을 읽지 않아 트레이너가
/// `3세트 · 60초` 로 보낸 처방이 회원에게는 `3세트` 로만 보였다 — 트레이너
/// 웹은 같은 값을 `60초` 로 보여 주므로, 두 앱이 같은 처방을 다르게 말했다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/coach_routine_detail.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

final AppLocalizations _ko = lookupAppLocalizations(const Locale('ko'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

/// 서버 `RoutineOut` 모양 — 버티는 근력 개인운동 하나.
Map<String, Object?> _holdRoutineJson({Object? holdSeconds = 60}) =>
    <String, Object?>{
      'id': 'r-plank',
      'name': '플랭크',
      'minutes': 6,
      'type': '근력',
      'reason': '',
      'source': 'trainer',
      'sets': 3,
      'reps': null,
      'hold_seconds': holdSeconds,
      'weight': 0,
    };

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-hold',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '온케어짐',
  goal: '',
);

Widget _app(
  List<CoachRoutine> routines, {
  Locale locale = const Locale('ko'),
}) => ProviderScope(
  overrides: <Override>[
    memberCoachProvider.overrideWith((ref) async => _coach),
    coachRoutinesProvider.overrideWith((ref) async => routines),
    coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SingleChildScrollView(child: AiCoachingCard())),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  List<CoachRoutine> routines, {
  Locale locale = const Locale('ko'),
}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(routines, locale: locale));
  await tester.pumpAndSettle();
}

void main() {
  group('DTO 세 경로가 hold_seconds 를 읽는다', () {
    test('추천 개인운동(RoutineOut)', () {
      final CoachRoutine routine = coachRoutineFromJson(_holdRoutineJson());

      expect(routine.holdSeconds, 60);
      expect(routine.sets, 3);
      expect(routine.reps, isNull);
    });

    test('프로그램 세션의 운동 구성(ProgramDraftExercise)', () {
      final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
        'id': 'r-session',
        'name': '코어',
        'minutes': 20,
        'type': '근력',
        'reason': '',
        'source': 'trainer',
        'program_name': '코어 4주',
        'session_name': '세션 A',
        'exercises': <Object?>[
          <String, Object?>{
            'name': '플랭크',
            'sets': 3,
            'reps': null,
            'hold_seconds': 45,
            'weight': 0,
          },
          <String, Object?>{'name': '스쿼트', 'sets': 4, 'reps': 12, 'weight': 40},
        ],
      });

      expect(routine.exercises.first.holdSeconds, 45);
      expect(routine.exercises.first.reps, isNull);
      // 횟수로 재는 운동은 초가 없다.
      expect(routine.exercises.last.holdSeconds, isNull);
      expect(routine.exercises.last.reps, 12);
    });

    test('PT 수업 프로그램(ProgramItem)', () {
      final CoachSession session = coachSessionFromJson(<String, Object?>{
        'id': 's-1',
        'date': '2026-03-02',
        'time': '18:00',
        'type': '1:1 PT',
        'duration_minutes': 50,
        'status': '완료',
        'program': <Object?>[
          <String, Object?>{
            'name': '플랭크',
            'sets': 3,
            'reps': null,
            'hold_seconds': 60,
            'weight': 0,
          },
        ],
      });

      final CoachProgramItem plank = session.program.single;
      expect(plank.holdSeconds, 60);
      expect(plank.reps, 0);
      expect(plank.sets, 3);
    });

    test('hold_seconds 를 모르는 옛 응답은 오류 없이 null 이다', () {
      final Map<String, Object?> legacy = _holdRoutineJson()
        ..remove('hold_seconds');
      expect(coachRoutineFromJson(legacy).holdSeconds, isNull);

      final CoachSession session = coachSessionFromJson(<String, Object?>{
        'id': 's-legacy',
        'date': '2026-03-02',
        'time': '18:00',
        'type': '1:1 PT',
        'duration_minutes': 50,
        'status': '완료',
        'program': <Object?>[
          <String, Object?>{'name': '벤치프레스', 'sets': 4, 'reps': 10},
        ],
      });
      expect(session.program.single.holdSeconds, isNull);
      expect(session.program.single.reps, 10);
    });

    test('0·음수·수가 아닌 값은 적지 않은 것으로 읽는다', () {
      for (final Object? raw in <Object?>[0, -5, '60', null]) {
        expect(
          coachRoutineFromJson(_holdRoutineJson(holdSeconds: raw)).holdSeconds,
          isNull,
          reason: '$raw',
        );
      }
    });

    test('완료 표시(copyWith)에도 버티는 초가 남는다', () {
      final CoachRoutine routine = coachRoutineFromJson(_holdRoutineJson());
      expect(routine.copyWith(completed: true).holdSeconds, 60);
    });
  });

  group('표시 문자열', () {
    test('버티는 운동은 횟수 자리에 초를 적는다', () {
      expect(
        strengthAmountParts(_ko, sets: 3, holdSeconds: 60).join(' · '),
        '3세트 · 60초',
      );
      expect(
        strengthAmountParts(_en, sets: 3, holdSeconds: 60).join(' · '),
        '${_en.exSetsCount(3)} · 60 sec',
      );
    });

    test('횟수만 있으면 지금처럼 횟수다', () {
      expect(
        strengthAmountParts(_ko, sets: 4, reps: 12, weight: 40).join(' · '),
        '4세트 · 12회 · 40kg',
      );
    });

    test('초가 있으면 남은 횟수 값보다 초가 앞선다 — 한 세트를 두 단위로 적지 않는다', () {
      expect(
        strengthAmountParts(_ko, sets: 3, reps: 10, holdSeconds: 30),
        <String>['3세트', '30초'],
      );
    });

    test('맨몸(0kg)과 0초는 적지 않는다', () {
      expect(
        strengthAmountParts(_ko, sets: 3, holdSeconds: 0, weight: 0),
        <String>['3세트'],
      );
    });

    test('영어 줄에는 한글이 남지 않는다', () {
      final String label = strengthAmountParts(
        _en,
        sets: 3,
        holdSeconds: 60,
        weight: 5,
      ).join(' · ');
      expect(RegExp(r'[가-힣]').hasMatch(label), isFalse);
      expect(label, contains(_en.exHoldSecondsCount(60)));
    });

    test('배정 근력 루틴의 양(exerciseAmountLabelOf)', () {
      expect(
        exerciseAmountLabelOf(
          _ko,
          type: ExerciseType.strength,
          minutes: 6,
          sets: 3,
          holdSeconds: 60,
          weight: 0,
          setsFromMinutesWhenUnknown: false,
        ),
        '3세트 · 60초',
      );
    });

    test('직접 기록한 버티기 운동도 같은 규칙이다', () {
      final ExerciseSession plank = ExerciseSession(
        id: 'ex-plank',
        dayLabel: '월',
        type: ExerciseType.strength,
        minutes: 6,
        calories: 36,
        name: '플랭크',
        sets: 3,
        holdSeconds: 45,
        weight: 0,
        date: DateTime(2026, 3, 2),
      );
      expect(exerciseAmountLabel(_ko, plank), '3세트 · 45초');
    });

    test('프로그램 세션 구성 줄(coachRoutineExerciseLabel)', () {
      expect(
        coachRoutineExerciseLabel(
          _ko,
          const CoachRoutineExercise(
            name: '플랭크',
            sets: 3,
            holdSeconds: 60,
            weight: 0,
          ),
        ),
        '플랭크 · 3세트 · 60초',
      );
      expect(
        coachRoutineExerciseLabel(
          _ko,
          const CoachRoutineExercise(
            name: '스쿼트',
            sets: 4,
            reps: 12,
            weight: 40,
            rest: 90,
          ),
        ),
        '스쿼트 · 4세트 · 12회 · 40kg · 휴식 90초',
      );
    });
  });

  group('추천 운동 카드', () {
    testWidgets('버티는 개인운동은 `근력 · 3세트 · 60초` 로 읽힌다', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <CoachRoutine>[
        coachRoutineFromJson(_holdRoutineJson()),
      ]);

      expect(find.text('근력 · 3세트 · 60초'), findsOneWidget);
      // 예전에는 세트만 남았다.
      expect(find.text('근력 · 3세트'), findsNothing);
    });

    testWidgets('영어 화면은 `60 sec` 로 읽힌다', (WidgetTester tester) async {
      await _pump(tester, <CoachRoutine>[
        coachRoutineFromJson(_holdRoutineJson()),
      ], locale: const Locale('en'));

      expect(find.textContaining('60 sec'), findsOneWidget);
      expect(find.textContaining('60초'), findsNothing);
    });

    testWidgets('운동 하나짜리 세션은 그 운동의 초를 오른쪽 양으로 올린다', (
      WidgetTester tester,
    ) async {
      // 개인운동만 보낸 배정은 행에 세트·횟수를 남기지 않고 운동 구성에 둔다
      // (#2581). 양은 그 운동의 값에서 읽는다.
      await _pump(tester, const <CoachRoutine>[
        CoachRoutine(
          id: 'r-only',
          name: '플랭크',
          minutes: 6,
          type: '근력',
          reason: '',
          source: 'trainer',
          deliveryKind: 'routine_only',
          exercises: <CoachRoutineExercise>[
            CoachRoutineExercise(
              name: '플랭크',
              sets: 3,
              holdSeconds: 60,
              weight: 0,
            ),
          ],
        ),
      ]);

      expect(find.text('근력 · 3세트 · 60초'), findsOneWidget);
    });

    testWidgets('프로그램 세션의 구성 줄에도 초가 붙는다', (WidgetTester tester) async {
      await _pump(tester, const <CoachRoutine>[
        CoachRoutine(
          id: 'r-program',
          name: '코어',
          minutes: 20,
          type: '근력',
          reason: '',
          source: 'trainer',
          programName: '코어 4주',
          sessionName: '세션 A',
          exercises: <CoachRoutineExercise>[
            CoachRoutineExercise(
              name: '플랭크',
              sets: 3,
              holdSeconds: 45,
              weight: 0,
            ),
            CoachRoutineExercise(name: '스쿼트', sets: 4, reps: 12, weight: 40),
          ],
        ),
      ]);

      expect(find.text('플랭크 · 3세트 · 45초'), findsOneWidget);
      expect(find.text('스쿼트 · 4세트 · 12회 · 40kg'), findsOneWidget);
    });
  });
}
