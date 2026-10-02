import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart' show keepWords;

/// 추천 개인운동의 효과 한 줄 (#2570).
///
/// 운동 이름 바로 아래 선다. 운동 구성 줄이 있어도 먼저 서고, 효과가 있으면
/// `reason`(AI 자동 추천의 긴 안내·옛 운동 이름 나열)은 카드에 싣지 않는다.
const MemberCoach _coach = MemberCoach(
  trainerId: 'trainer-1',
  name: '김태오',
  specialty: '퍼스널 트레이너',
  career: '7년',
  intro: '',
  gymName: '온케어짐',
  goal: '체중 감량 · 혈압 관리',
);

Future<void> _pump(WidgetTester tester, List<CoachRoutine> routines) async {
  await tester.pumpWidget(
    ProviderScope(
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
        home: const Scaffold(
          body: SingleChildScrollView(child: AiCoachingCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('응답의 effect 를 읽고, 모르는 옛 응답은 빈 값이다', () {
    final CoachRoutine withEffect = coachRoutineFromJson(<String, Object?>{
      'id': 'r1',
      'name': '걷기',
      'type': '유산소',
      'reason': '',
      'source': 'trainer',
      'effect': '혈압 관리에 도움',
    });
    expect(withEffect.effect, '혈압 관리에 도움');
    // 완료 표시로 복사해도 남는다.
    expect(withEffect.copyWith(completed: true).effect, '혈압 관리에 도움');

    final CoachRoutine legacy = coachRoutineFromJson(<String, Object?>{
      'id': 'r2',
      'name': '걷기',
      'type': '유산소',
      'reason': '예전 사유',
      'source': 'trainer',
    });
    expect(legacy.effect, '');
  });

  testWidgets('효과가 이름 아래 서고, 있으면 reason 은 싣지 않는다', (WidgetTester tester) async {
    await _pump(tester, const <CoachRoutine>[
      CoachRoutine(
        id: 'walk',
        name: '저강도 걷기',
        minutes: 20,
        type: '유산소',
        reason: '회복 목적의 가벼운 유산소예요. 대화할 수 있는 속도로 걸어 보세요.',
        source: 'ai',
        effect: '체력 향상·만성질환 예방',
      ),
    ]);

    expect(find.text(keepWords('체력 향상·만성질환 예방')), findsOneWidget);
    expect(find.textContaining('대화할 수 있는 속도로'), findsNothing);
    // 이름 바로 아래다.
    expect(
      tester.getTopLeft(find.text(keepWords('체력 향상·만성질환 예방'))).dy,
      greaterThan(tester.getTopLeft(find.text('저강도 걷기')).dy),
    );
  });

  testWidgets('운동 구성 줄이 있어도 효과가 먼저 선다', (WidgetTester tester) async {
    await _pump(tester, const <CoachRoutine>[
      CoachRoutine(
        id: 'stretch',
        name: '하체 스트레칭',
        minutes: 15,
        type: '스트레칭',
        reason: '햄스트링 스트레칭',
        source: 'trainer',
        programName: '하체 스트레칭',
        // 제목과 다른 운동이라 구성 줄이 무엇을 하는지 말한다(#2581).
        exercises: <CoachRoutineExercise>[
          CoachRoutineExercise(name: '햄스트링 스트레칭', duration: 15),
        ],
        effect: '유연성·부상 예방',
      ),
    ]);

    final Finder effect = find.byKey(
      const ValueKey<String>('routine-effect-stretch'),
    );
    final Finder composition = find.text('햄스트링 스트레칭 · 15분');
    expect(effect, findsOneWidget);
    expect(composition, findsOneWidget);
    expect(
      tester.getTopLeft(effect).dy,
      lessThan(tester.getTopLeft(composition).dy),
    );
  });

  testWidgets('효과가 없는 옛 배정은 예전처럼 reason 을 보인다', (WidgetTester tester) async {
    await _pump(tester, const <CoachRoutine>[
      CoachRoutine(
        id: 'legacy',
        name: '코어 스트레칭',
        minutes: 10,
        type: '스트레칭',
        reason: '허리 부담 완화',
        source: 'trainer',
      ),
    ]);
    expect(find.text(keepWords('허리 부담 완화')), findsOneWidget);
  });

  test('목업은 픽스처의 효과를 싣는다 — 트레이너가 고친 줄까지', () async {
    final List<CoachRoutine> routines = await MockMemberCoachRepository()
        .fetchRoutines();
    expect(
      routines.map((CoachRoutine r) => r.effect),
      containsAll(<String>['체지방 감량에 도움', '오른쪽 어깨 보호']),
    );
  });

  group('개인운동만 전송의 소제목 (#2581)', () {
    CoachRoutine session(String id, String name, String kind) => CoachRoutine(
      id: id,
      name: name,
      minutes: 20,
      type: '유산소',
      reason: '',
      source: 'trainer',
      programName: '이번 주 개인운동',
      sessionName: name,
      sessionOrder: id == 'a' ? 0 : 1,
      deliveryKind: kind,
    );

    testWidgets('개인운동만 으로 여럿 보내도 카드 안 소제목이 없다', (WidgetTester tester) async {
      await _pump(tester, <CoachRoutine>[
        session('a', '저강도 걷기', 'routine_only'),
        session('b', '힙 브리지', 'routine_only'),
      ]);
      expect(find.text('이번 주 개인운동'), findsNothing);
      expect(find.text('저강도 걷기'), findsOneWidget);
    });

    testWidgets('다른 여러 세션 프로그램은 지금처럼 이름을 얹는다', (WidgetTester tester) async {
      await _pump(tester, <CoachRoutine>[
        session('a', '세션 A', ''),
        session('b', '세션 B', ''),
      ]);
      expect(find.text('이번 주 개인운동'), findsOneWidget);
    });

    test('응답의 delivery_kind 를 읽는다', () {
      final CoachRoutine r = coachRoutineFromJson(<String, Object?>{
        'id': 'r',
        'name': '걷기',
        'type': '유산소',
        'reason': '',
        'source': 'trainer',
        'delivery_kind': 'routine_only',
      });
      expect(r.isRoutineOnly, isTrue);
      expect(r.copyWith(completed: true).isRoutineOnly, isTrue);
    });
  });

  group('운동 하나짜리 줄의 구성 줄 (#2581)', () {
    testWidgets('이름이 같으면 구성 줄을 적지 않고, 세트·횟수는 오른쪽에 선다', (
      WidgetTester tester,
    ) async {
      // 서버는 프로그램 세션 행에 세트를 남기지 않고 분만 둔다.
      await _pump(tester, const <CoachRoutine>[
        CoachRoutine(
          id: 'bridge',
          name: '개인운동',
          minutes: 12,
          type: '근력',
          reason: '힙 브리지',
          source: 'trainer',
          programName: '개인운동',
          sessionName: '힙 브리지',
          deliveryKind: 'routine_only',
          exercises: <CoachRoutineExercise>[
            CoachRoutineExercise(name: '힙 브리지', sets: 3, reps: 15),
          ],
        ),
      ]);
      expect(find.text('힙 브리지'), findsOneWidget);
      expect(find.text('힙 브리지 · 3세트 · 15회'), findsNothing);
      expect(find.textContaining('3세트 · 15회'), findsOneWidget);
      expect(find.textContaining('12분'), findsNothing);
    });

    testWidgets('시간 운동은 그 운동의 초를 오른쪽에 적는다', (WidgetTester tester) async {
      await _pump(tester, const <CoachRoutine>[
        CoachRoutine(
          id: 'walk',
          name: '개인운동',
          minutes: 1,
          type: '유산소',
          reason: '걷기',
          source: 'trainer',
          programName: '개인운동',
          sessionName: '걷기',
          deliveryKind: 'routine_only',
          exercises: <CoachRoutineExercise>[
            CoachRoutineExercise(name: '걷기', duration: 1, durationSeconds: 45),
          ],
        ),
      ]);
      expect(find.text('걷기 · 45초'), findsNothing);
      expect(find.textContaining('45초'), findsOneWidget);
    });

    testWidgets('운동이 여럿이면 구성 줄을 그대로 적는다', (WidgetTester tester) async {
      await _pump(tester, const <CoachRoutine>[
        CoachRoutine(
          id: 'pt',
          name: '하체',
          minutes: 20,
          type: '근력',
          reason: '',
          source: 'trainer',
          exercises: <CoachRoutineExercise>[
            CoachRoutineExercise(name: '스쿼트', sets: 3, reps: 10),
            CoachRoutineExercise(name: '런지', sets: 3, reps: 12),
          ],
        ),
      ]);
      expect(find.text('스쿼트 · 3세트 · 10회'), findsOneWidget);
      expect(find.text('런지 · 3세트 · 12회'), findsOneWidget);
    });
  });
}
