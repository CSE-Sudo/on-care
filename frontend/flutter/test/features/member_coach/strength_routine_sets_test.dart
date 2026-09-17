/// 근력 개인운동은 **세트**로 읽는다. (#1901)
///
/// 픽스처와 서버(`RoutineOut`)가 진작부터 `sets`·`reps`·`weight` 를 내려보내고
/// 있었는데 `CoachRoutine` 에 받을 칸이 없어 화면 직전에 버려졌다. 그래서 근력
/// 루틴이 `근력 · 10분` 으로만 보였고, 같은 루틴을 세트로 세는 운동 현황 링·주간
/// 목표와 수가 갈렸다(#1262).
///
/// 세트를 들지 않은 루틴은 분으로 둔다 — 기록은 분에서 세트를 되짚지만, 배정은
/// 적힌 수가 곧 값이라 없는 세트를 지어내지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-sets',
  name: '김트레이너',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '온케어짐',
  goal: '',
);

/// 데모 픽스처의 `코어 강화` 와 같은 값이다 — 근력 10분, 3세트 · 15회 · 0kg.
const CoachRoutine _strength = CoachRoutine(
  id: 'r-strength',
  name: '코어 강화',
  minutes: 10,
  type: '근력',
  reason: '기초대사량 향상',
  source: 'ai',
  sets: 3,
  reps: 15,
  weight: 0,
);

const CoachRoutine _cardio = CoachRoutine(
  id: 'r-cardio',
  name: '저강도 유산소 (걷기)',
  minutes: 30,
  type: '유산소',
  reason: '혈압 안정에 효과적',
  source: 'ai',
);

/// 세트를 모르는 근력 루틴 — 이 칸이 생기기 전에 배정된 것.
const CoachRoutine _strengthWithoutSets = CoachRoutine(
  id: 'r-legacy',
  name: '전신 근력',
  minutes: 12,
  type: '근력',
  reason: '기초 근력',
  source: 'trainer',
);

Widget _app(List<CoachRoutine> routines) => ProviderScope(
  overrides: <Override>[
    memberCoachProvider.overrideWith((ref) async => _coach),
    coachRoutinesProvider.overrideWith((ref) async => routines),
    coachUnreadProvider.overrideWith((ref) => Stream<int>.value(0)),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SingleChildScrollView(child: AiCoachingCard())),
  ),
);

Future<AppLocalizations> _pump(
  WidgetTester tester,
  List<CoachRoutine> routines,
) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(routines));
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(AiCoachingCard)));
}

void main() {
  testWidgets('근력 루틴은 세트·횟수·중량으로 읽힌다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(tester, <CoachRoutine>[_strength]);

    // 운동 현황 링·주간 목표가 세는 것과 같은 수다.
    expect(
      find.text(
        '근력 · ${l.exSetsCount(3)} · ${l.exRepsCount(15)} · 0${l.exUnitKg}',
      ),
      findsOneWidget,
    );
    // 분으로 적던 예전 표기는 남지 않는다.
    expect(find.text('근력 · ${l.unitMinutesValue(10)}'), findsNothing);
  });

  testWidgets('유산소 루틴은 지금처럼 분으로 남는다', (WidgetTester tester) async {
    final AppLocalizations l = await _pump(tester, <CoachRoutine>[_cardio]);

    expect(find.text('유산소 · ${l.unitMinutesValue(30)}'), findsOneWidget);
  });

  testWidgets('세트를 모르는 근력 루틴은 분으로 둔다 — 없는 세트를 지어내지 않는다', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l = await _pump(tester, <CoachRoutine>[
      _strengthWithoutSets,
    ]);

    expect(find.text('근력 · ${l.unitMinutesValue(12)}'), findsOneWidget);
    // 12분 / 3 = 4세트. 기록이라면 이렇게 되짚지만(#1262), 배정은 트레이너가
    // 적은 수가 곧 값이라 만들어 적지 않는다.
    expect(find.textContaining(l.exSetsCount(4)), findsNothing);
  });

  test('서버 응답의 sets·reps·weight 를 읽는다', () {
    final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
      'id': 'r-1',
      'name': '코어 강화',
      'minutes': 10,
      'type': '근력',
      'reason': '기초대사량 향상',
      'source': 'ai',
      'sets': 3,
      'reps': 15,
      'weight': 0,
    });

    expect(routine.sets, 3);
    expect(routine.reps, 15);
    expect(routine.weight, 0);
  });

  test('이 필드를 모르는 옛 응답은 null 로 떨어진다', () {
    final CoachRoutine routine = coachRoutineFromJson(<String, Object?>{
      'id': 'r-old',
      'name': '전신 근력',
      'minutes': 12,
      'type': '근력',
      'reason': '기초 근력',
      'source': 'trainer',
    });

    expect(routine.sets, isNull);
    expect(routine.reps, isNull);
    expect(routine.weight, isNull);
  });

  test('완료를 표시해도 배정 값(세트·횟수·중량)은 그대로 남는다', () {
    final CoachRoutine done = _strength.copyWith(completed: true);

    expect(done.sets, 3);
    expect(done.reps, 15);
    expect(done.weight, 0);
  });
}
