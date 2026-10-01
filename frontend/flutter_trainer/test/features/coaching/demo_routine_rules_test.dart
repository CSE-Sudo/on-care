// 데모 A/B 생성이 서버 규칙형의 안전 주의·반복 운동 규칙을 따르는지 (#2704).
//
// 서버 `routine_ai.rule_based_plans` 는 건강 주의사항·최근 대화에서 통증 부위를
// 읽어 부담이 큰 동작을 빼고, 최근 기록에 반복된 운동이 있으면 그 운동으로
// A/B 를 짠다. 데모는 늘 고정 라이브러리였다.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_rules.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';

void main() {
  group('규칙 표', () {
    test('대화에서 통증 부위를 찾고 그 부위 부담 동작을 뺀다', () {
      final List<String> cautions = cautionsIn('', <String>['회원: 허리가 아파요']);
      expect(cautions, <String>['허리']);
      final parts = safeParts(<(String, String, int)>[
        ('인터벌 러닝', '유산소', 3),
        ('스쿼트', '근력', 2),
        ('플랭크', '근력', 1),
      ], cautions);
      expect(parts.map((p) => p.$1), <String>['스쿼트', '플랭크', '코어 스트레칭']);
    });

    test('주의할 말이 없으면 구성을 그대로 둔다 — 같은 목록이다', () {
      final List<(String, String, int)> parts = <(String, String, int)>[
        ('인터벌 러닝', '유산소', 3),
      ];
      expect(identical(safeParts(parts, const <String>[]), parts), isTrue);
    });

    test('전문가 확인이 필요한 말이면 강도를 올리지 않는다', () {
      expect(needsProfessionalCheck('', <String>['회원: 어지럼이 있어요']), isTrue);
      expect(needsProfessionalCheck('혈압 관리', const <String>[]), isFalse);
    });

    test('이력 줄에서 운동 이름만 남기고, 안 한 운동은 세지 않는다', () {
      expect(historyExerciseName('스쿼트 3세트 · 12회 · 40kg ✓'), '스쿼트');
      expect(historyExerciseName('걷기 ✓ (10분만)'), '걷기');
      expect(historyExerciseName('플랭크 ✗ (피로)'), '');
      expect(historyExerciseName(<String, Object?>{'name': '벤치프레스'}), '벤치프레스');
      expect(
        frequentExercises(<List<Object?>>[
          <Object?>['걷기 25분 ✓', '데드리프트 ✗'],
          <Object?>['걷기 ✓', '데드리프트 ✗'],
          <Object?>['스쿼트 ✓'],
        ]),
        <String>['걷기'],
      );
    });
  });

  group('데모 A/B', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    Future<RoutineOptions> generate(String memberId) =>
        MockTrainerRoutineOptionsRepository(db: db).generate(
          memberId,
          availableMinutes: null,
          intensityPreference: null,
          trainerNote: '',
        );

    test('반복 운동이 있는 회원은 그 운동으로 짠다 (정하윤 걷기)', () async {
      final RoutineOptions o = await generate('seed-client-4');

      expect(o.planA.label, '기존 패턴 유지형');
      expect(o.planB.label, '점진적 강화형');
      expect(o.planA.exercises.map((e) => e.name), contains('걷기'));
      expect(o.planA.rationale, contains('반복 확인된 운동(걷기)'));
      expect(o.generatedBy, 'rule');
      expect(
        o.planA.exercises.fold<int>(0, (int a, e) => a + e.minutes),
        o.planA.totalMinutes,
      );
    });

    test('대화에 통증이 있으면 부담 동작을 빼고 주의 문구를 붙인다', () async {
      for (var n = 1; n <= 15; n++) {
        final RoutineOptions o = await generate('seed-client-$n');
        final List<String> cautions = cautionsIn(
          o.analysis.goal,
          o.analysis.recentMessages,
        );
        if (cautions.isEmpty) continue;
        for (final RoutinePlan plan in <RoutinePlan>[o.planA, o.planB]) {
          expect(
            plan.rationale,
            contains('주의사항(${cautions.join(', ')}) 반영'),
            reason: 'seed-client-$n',
          );
          for (final RoutineExercise e in plan.exercises) {
            expect(
              avoidsFor(e.name, cautions),
              isFalse,
              reason: 'seed-client-$n ${e.name}',
            );
          }
        }
      }
    });

    test('추천 상태·기록 횟수를 서버와 같은 규칙으로 센다 (#2674)', () async {
      // 김민수는 6주에 걸친 기록 — 맞춤, 이지수는 기록 몇 회 — 학습 중,
      // 임도현은 기록 없음 — 템플릿.
      final RoutineOptions kim = await generate('seed-client-1');
      final RoutineOptions jisu = await generate('seed-client-2');
      final RoutineOptions dohyun = await generate('seed-client-7');

      expect(
        kim.analysis.recommendationStatus,
        RecommendationStatus.personalized,
      );
      expect(kim.analysis.historySessionCount, greaterThanOrEqualTo(6));
      expect(kim.analysis.analysisPeriodDays, 42);
      expect(jisu.analysis.recommendationStatus, RecommendationStatus.learning);
      expect(
        dohyun.analysis.recommendationStatus,
        RecommendationStatus.template,
      );
      expect(dohyun.analysis.historySessionCount, 0);
      // 기록이 적으면 조건을 제안하지 않는다 — 서버와 같다.
      expect(dohyun.analysis.suggestedAvailableMinutes, isNull);
      // 기록이 쌓인 회원은 가장 최근 배정의 시간으로 조건을 제안한다.
      expect(jisu.analysis.suggestedAvailableMinutes, isNotNull);
    });

    test('참고한 최근 대화는 서버처럼 최근 14일 것만 싣는다 (#2674)', () async {
      // 문가영은 마지막 대화가 3주 전이다 — 실서버는 그 대화를 싣지 않는다.
      final RoutineOptions gayoung = await generate('seed-client-12');
      final RoutineOptions sera = await generate('seed-client-8');

      expect(gayoung.analysis.recentMessages, isEmpty);
      expect(sera.analysis.recentMessages, isNotEmpty);
      expect(sera.analysis.recentMessages.length, lessThanOrEqualTo(10));
    });

    test('B안은 고른 강도를 그대로 옮기고 3:2:1 로 나눈다 (#2715)', () async {
      final repo = MockTrainerRoutineOptionsRepository(db: db);
      for (final (String pref, String label) in <(String, String)>[
        ('low', '낮음'),
        ('moderate', '보통'),
        ('high', '높음'),
      ]) {
        final RoutineOptions o = await repo.generate(
          'm1',
          availableMinutes: 30,
          intensityPreference: pref,
          trainerNote: '',
        );
        expect(o.planB.intensity, label, reason: pref);
        expect(o.planB.exercises.map((e) => e.minutes), <int>[15, 10, 5]);
      }
    });
  });

  test('반올림은 서버(파이썬)처럼 절반이면 짝수 쪽이다', () {
    expect(pyRound(2.5), 2);
    expect(pyRound(3.5), 4);
    expect(pyRound(2.4), 2);
    expect(pyRound(2.6), 3);
    expect(pyRound(10), 10);
  });
}
