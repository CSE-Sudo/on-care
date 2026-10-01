// 트레이너 웹 데모의 루틴 기능이 회원별 데이터로 돌고, 새로고침해도 남는지
// (#2668).
//
// 예전에는 김민수만 배정이 있었고, AI 제안·A/B 스냅샷·PT 개인운동은 모든 회원이
// 같았다. 배정·전달·제안 검토·PT 개인운동 상태는 메모리라 새로고침하면
// 사라졌다. 여기서는 "새로고침" 을 같은 DB 위에 저장소를 새로 만드는 것으로
// 흉내 낸다.
import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_rules.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_suggestions.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_options_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_context_source.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_options.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';

final RegExp _hangul = RegExp(r'[가-힣]');

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db);
  });
  tearDown(() => db.close());

  /// 그 회원에게 심어 둔 AI 개인운동 이름(순서대로).
  Future<List<String>> aiNames(String clientId) async => <String>[
    for (final row
        in await (db.select(db.clientAiRoutines)
              ..where((t) => t.clientId.equals(clientId))
              ..orderBy(<OrderingTerm Function($ClientAiRoutinesTable)>[
                (t) => OrderingTerm(expression: t.sortOrder),
              ]))
            .get())
      row.name,
  ];

  /// 프로그램이 붙은 시드 PT 일정들.
  Future<List<TrainerScheduleRow>> ptWithProgram() async =>
      <TrainerScheduleRow>[
        for (final row in await db.select(db.trainerScheduleEntries).get())
          if (row.clientId != null &&
              row.type == SessionType.personalTraining &&
              (jsonDecode(row.programJson) as List<Object?>).isNotEmpty)
            row,
      ];

  Future<void> setStatus(String id, String status) =>
      (db.update(db.trainerScheduleEntries)..where((t) => t.id.equals(id)))
          .write(TrainerScheduleEntriesCompanion(status: Value(status)));

  group('배정 루틴', () {
    test('김민수 말고도 회원마다 자기 배정이 있다', () async {
      final repo = MockTrainerRoutineRepository(db: db);
      addTearDown(repo.dispose);

      final List<AssignedRoutine> jisu = await repo
          .watchAssignedRoutines('seed-client-2')
          .first;
      final List<AssignedRoutine> sungho = await repo
          .watchAssignedRoutines('seed-client-3')
          .first;

      expect(jisu.map((r) => r.name), await aiNames('seed-client-2'));
      expect(sungho.map((r) => r.name), await aiNames('seed-client-3'));
      expect(
        jisu.map((r) => r.name).toSet(),
        isNot(sungho.map((r) => r.name).toSet()),
      );
      expect(
        await repo.watchAssignedRoutines('seed-client-1').first,
        isNotEmpty,
      );
    });

    test('근력 배정은 세트·횟수(또는 초)를 싣는다 — 0세트로 그리지 않는다', () async {
      final repo = MockTrainerRoutineRepository(db: db);
      addTearDown(repo.dispose);
      for (var n = 2; n <= 15; n++) {
        for (final AssignedRoutine r
            in await repo.watchAssignedRoutines('seed-client-$n').first) {
          if (r.type != '근력') continue;
          expect(r.sets, greaterThan(0), reason: '${r.id} ${r.name}');
          expect(
            (r.reps ?? 0) > 0 || (r.holdSeconds ?? 0) > 0,
            isTrue,
            reason: '${r.id} ${r.name}',
          );
        }
      }
      // 값은 시드 표에서 온다(#2705) — 이지수 스쿼트는 운동 기록의 값과 같다.
      final squat = (await repo.watchAssignedRoutines('seed-client-2').first)
          .firstWhere((r) => r.name == '스쿼트');
      expect((squat.sets, squat.reps, squat.weight), (3, 12, 40.0));
    });

    test('보낸 개인운동과 마지막 전달이 새로고침 뒤에도 남는다', () async {
      final before = MockTrainerRoutineRepository(db: db);
      addTearDown(before.dispose);
      await before.assignProgram('seed-client-2', <String, Object?>{
        'name': '개인운동',
        'delivery_kind': 'routine_only',
        'start_date': '2026-08-24',
        'sessions': <Object?>[
          <String, Object?>{
            'id': 's1',
            'name': '',
            'exercises': <Object?>[
              <String, Object?>{
                'id': 'e1',
                'name': '실내 자전거',
                'type': '유산소',
                'duration': 20,
              },
            ],
          },
        ],
      });

      final after = MockTrainerRoutineRepository(db: db);
      addTearDown(after.dispose);
      final List<AssignedRoutine> rows = await after
          .watchAssignedRoutines('seed-client-2')
          .first;
      expect(rows.first.name, '실내 자전거');
      expect(rows.first.deliveryKind, DeliveryKinds.routineOnly);
      final SentDelivery? latest = await after.fetchLatestDelivery(
        'seed-client-2',
      );
      expect(latest?.kind, DeliveryKinds.routineOnly);
      expect(latest?.routines.map((r) => r.name), <String>['실내 자전거']);
    });

    test('배정 취소도 새로고침 뒤에 남는다', () async {
      final before = MockTrainerRoutineRepository(db: db);
      addTearDown(before.dispose);
      final List<AssignedRoutine> seeded = await before
          .watchAssignedRoutines('seed-client-5')
          .first;
      await before.deleteRoutine('seed-client-5', seeded.first.id);

      final after = MockTrainerRoutineRepository(db: db);
      addTearDown(after.dispose);
      final List<AssignedRoutine> rows = await after
          .watchAssignedRoutines('seed-client-5')
          .first;
      expect(rows.length, seeded.length - 1);
      expect(rows.map((r) => r.id), isNot(contains(seeded.first.id)));
    });

    test('PT 프로그램을 보내면 PT 와 함께 간 전달로 남는다', () async {
      final schedule = DriftScheduleRepository(db);
      final TrainerScheduleRow pt = (await ptWithProgram()).first;
      await setStatus(pt.id, ScheduleStatus.done);
      final List<String> attached = <String>[
        for (final r in await schedule.fetchScheduledRoutines(pt.id))
          r.exercise.name,
      ];
      expect(attached, isNotEmpty);

      await schedule.sendProgram(pt.id);

      final repo = MockTrainerRoutineRepository(db: db);
      addTearDown(repo.dispose);
      final SentDelivery? latest = await repo.fetchLatestDelivery(pt.clientId!);
      expect(latest?.kind, DeliveryKinds.ptWithRoutine);
      expect(latest?.session?.id, pt.id);
      expect(latest?.hasProgram, isTrue);
      expect(latest?.routines.map((r) => r.name), attached);
      final List<AssignedRoutine> assigned = await repo
          .watchAssignedRoutines(pt.clientId!)
          .first;
      expect(
        assigned.take(attached.length).map((r) => r.scheduleId).toSet(),
        <String>{pt.id},
      );
    });

    test('취소된 PT 의 개인운동을 보내면 취소 뒤 전달로 남는다', () async {
      final schedule = DriftScheduleRepository(db);
      final TrainerScheduleRow pt = (await ptWithProgram()).first;
      await setStatus(pt.id, ScheduleStatus.cancelled);

      await schedule.sendScheduledRoutines(pt.id);

      final repo = MockTrainerRoutineRepository(db: db);
      addTearDown(repo.dispose);
      final SentDelivery? latest = await repo.fetchLatestDelivery(pt.clientId!);
      expect(latest?.kind, DeliveryKinds.cancelledRoutineOnly);
      expect(latest?.session?.status, ScheduleStatus.cancelled);
      expect(latest?.hasProgram, isFalse);
      expect(latest?.routines, isNotEmpty);
      // 새로고침한 스케줄도 보낸 것으로 읽는다.
      final rows = await DriftScheduleRepository(
        db,
      ).fetchScheduledRoutines(pt.id);
      expect(rows.every((r) => r.sent), isTrue);
    });
  });

  group('PT 에 붙은 개인운동', () {
    test('그 회원에게 심어 둔 AI 운동에서 오고, 회원마다 다르다', () async {
      final schedule = DriftScheduleRepository(db);
      final Set<String> combos = <String>{};
      for (final TrainerScheduleRow pt in await ptWithProgram()) {
        final List<String> names = <String>[
          for (final r in await schedule.fetchScheduledRoutines(pt.id))
            r.exercise.name,
        ];
        expect(await aiNames(pt.clientId!), containsAll(names));
        combos.add(names.join('|'));
      }
      // 예전에는 모든 PT 가 같은 두 개(저강도 걷기·코어 스트레칭)였다.
      expect(combos.length, greaterThan(1));
    });

    test('숨김·수정이 새로고침 뒤에도 남는다', () async {
      final List<TrainerScheduleRow> rows = await ptWithProgram();
      final schedule = DriftScheduleRepository(db);
      await schedule.dismissScheduledRoutines(rows[0].id);
      await schedule.updateScheduledRoutines(
        rows[1].id,
        const <RoutineExercise>[
          RoutineExercise(name: '실내 자전거', minutes: 20, type: '유산소'),
        ],
      );

      final reloaded = DriftScheduleRepository(db);
      expect(await reloaded.fetchScheduledRoutines(rows[0].id), isEmpty);
      final edited = await reloaded.fetchScheduledRoutines(rows[1].id);
      expect(edited.map((r) => r.exercise.name), <String>['실내 자전거']);
      expect(edited.single.exercise.source, 'trainer');
      expect(edited.single.sent, isFalse);
    });

    test('다시 심으면 데모 루틴 상태도 처음으로 돌아간다', () async {
      final TrainerScheduleRow pt = (await ptWithProgram()).first;
      await DriftScheduleRepository(db).dismissScheduledRoutines(pt.id);
      await DemoRoutineStore(db).assigned('seed-client-2');

      // 언어가 바뀌면 같은 날이라도 다시 심는다.
      await seedIfEmpty(db, language: DemoLanguage.en);

      expect(await DemoRoutineStore(db).readAssigned('seed-client-2'), isNull);
      expect(await DemoRoutineStore(db).readSession(pt.id), isNull);
    });
  });

  group('AI 루틴 제안', () {
    test('회원마다 다르고, 그 회원의 배정과 겹치지 않는다', () async {
      final repo = MockTrainerRoutineSuggestionRepository(db: db);
      final Set<String> firstNames = <String>{};
      for (var n = 2; n <= 15; n++) {
        final String id = 'seed-client-$n';
        final List<RoutineSuggestion> pending = await repo.pending(id);
        expect(pending, isNotEmpty, reason: id);
        expect(
          (await aiNames(
            id,
          )).toSet().intersection(pending.map((s) => s.name).toSet()),
          isEmpty,
          reason: id,
        );
        firstNames.add(pending.first.name);
      }
      expect(firstNames.length, 14);
    });

    test('회원마다 세 건이고 그중 하나는 세트·횟수가 있는 근력이다 (#1321)', () async {
      final repo = MockTrainerRoutineSuggestionRepository(db: db);
      for (var n = 2; n <= 15; n++) {
        final List<RoutineSuggestion> pending = await repo.pending(
          'seed-client-$n',
        );
        expect(pending, hasLength(3), reason: 'seed-client-$n');
        final strength = pending.where((s) => s.type == '근력').toList();
        expect(strength, hasLength(1), reason: 'seed-client-$n');
        expect(strength.single.sets, greaterThan(0));
      }
    });

    test('승인하면 배정이 되고, 새로고침해도 다시 나오지 않는다', () async {
      final routines = MockTrainerRoutineRepository(db: db);
      addTearDown(routines.dispose);
      final repo = MockTrainerRoutineSuggestionRepository(
        assignTo: routines,
        db: db,
      );
      final RoutineSuggestion first = (await repo.pending(
        'seed-client-4',
      )).first;

      await repo.approve(first.id, minutes: 7);

      final AssignedRoutine assigned =
          (await routines.watchAssignedRoutines('seed-client-4').first).first;
      expect(assigned.name, first.name);
      expect(assigned.minutes, 7);
      expect(assigned.source, 'ai');
      final reloaded = MockTrainerRoutineSuggestionRepository(db: db);
      expect(
        (await reloaded.pending('seed-client-4')).map((s) => s.id),
        isNot(contains(first.id)),
      );
      await expectLater(
        repo.approve(first.id),
        throwsA(isA<RoutineSuggestionAlreadyReviewed>()),
      );
    });

    test('개인운동만 전송에 실린 제안은 대기 목록에서 빠지고, 새로고침해도 '
        '돌아오지 않는다 (#2747)', () async {
      final repo = MockTrainerRoutineSuggestionRepository(db: db);
      final List<RoutineSuggestion> before = await repo.pending(
        'seed-client-3',
      );
      final RoutineSuggestion sent = before.first;
      final routines = MockTrainerRoutineRepository(db: db);
      addTearDown(routines.dispose);

      await routines.assignProgram('seed-client-3', <String, Object?>{
        'name': sent.name,
        'delivery_kind': 'routine_only',
        'start_date': '2026-08-24',
        'sessions': <Object?>[
          <String, Object?>{
            'id': 'routine-only-0',
            'name': sent.name,
            'exercises': <Object?>[
              <String, Object?>{
                'id': 'personal-0',
                'name': sent.name,
                'type': '유산소',
                'duration': 20,
              },
            ],
          },
        ],
        'suggestion_ids': <String>[sent.id],
      });

      // 같은 저장소도 다음 조회에서 바로 뺀다 — 화면은 전송 뒤 이 목록을
      // 다시 읽는다.
      final List<String> after = <String>[
        for (final s in await repo.pending('seed-client-3')) s.id,
      ];
      expect(after, isNot(contains(sent.id)));
      expect(after, hasLength(before.length - 1));
      final reloaded = MockTrainerRoutineSuggestionRepository(db: db);
      expect(
        (await reloaded.pending('seed-client-3')).map((s) => s.id),
        isNot(contains(sent.id)),
      );
    });

    test('전송에 실리지 않은 제안과 다른 회원의 제안은 그대로다 (#2747)', () async {
      final repo = MockTrainerRoutineSuggestionRepository(db: db);
      final List<String> mine = <String>[
        for (final s in await repo.pending('seed-client-3')) s.id,
      ];
      final List<String> other = <String>[
        for (final s in await repo.pending('seed-client-4')) s.id,
      ];
      final routines = MockTrainerRoutineRepository(db: db);
      addTearDown(routines.dispose);

      // 직접 넣은 운동만 보냈다 — 제안 id 가 없다.
      await routines.assignProgram('seed-client-3', <String, Object?>{
        'name': '실내 자전거',
        'delivery_kind': 'routine_only',
        'start_date': '2026-08-24',
        'sessions': <Object?>[
          <String, Object?>{
            'id': 'routine-only-0',
            'name': '실내 자전거',
            'exercises': <Object?>[
              <String, Object?>{
                'id': 'personal-0',
                'name': '실내 자전거',
                'type': '유산소',
                'duration': 20,
              },
            ],
          },
        ],
      });

      expect(
        (await repo.pending('seed-client-3')).map((s) => s.id).toList(),
        mine,
      );
      expect(
        (await repo.pending('seed-client-4')).map((s) => s.id).toList(),
        other,
      );
    });

    test('PT 일정 추가에 붙인 개인운동의 제안도 대기 목록에서 빠진다 (#2747)', () async {
      final repo = MockTrainerRoutineSuggestionRepository(db: db);
      final RoutineSuggestion sent = (await repo.pending(
        'seed-client-3',
      )).first;

      await DriftScheduleRepository(db).registerProgramSchedule(
        // 시드 일정과 겹치지 않는 먼 날짜·이른 시간이다.
        date: '2030-01-07',
        clientId: 'seed-client-3',
        clientName: '회원 3',
        time: '06:10',
        durationMinutes: 50,
        assignment: const <String, Object?>{'name': '하체 PT'},
        program: const <ProgramItem>[],
        personalRoutines: <RoutineExercise>[
          RoutineExercise(
            name: sent.name,
            minutes: sent.minutes,
            type: sent.type,
            source: 'ai',
            suggestionId: sent.id,
          ),
        ],
      );

      expect(
        (await MockTrainerRoutineSuggestionRepository(
          db: db,
        ).pending('seed-client-3')).map((s) => s.id),
        isNot(contains(sent.id)),
      );
    });

    test('이미 있는 PT 에 붙인 개인운동의 제안도 대기 목록에서 빠진다 (#2747)', () async {
      final repo = MockTrainerRoutineSuggestionRepository(db: db);
      final RoutineSuggestion sent = (await repo.pending(
        'seed-client-3',
      )).first;
      final TrainerScheduleRow pt = (await ptWithProgram()).first;

      await DriftScheduleRepository(
        db,
      ).updateScheduledRoutines(pt.id, <RoutineExercise>[
        RoutineExercise(
          name: sent.name,
          minutes: sent.minutes,
          type: sent.type,
          source: 'ai',
          suggestionId: sent.id,
        ),
      ]);

      expect(
        (await MockTrainerRoutineSuggestionRepository(
          db: db,
        ).pending('seed-client-3')).map((s) => s.id),
        isNot(contains(sent.id)),
      );
    });

    test('영어판은 id·시간·유형·세트·근거가 같고 이름·사유만 영어다', () {
      expect(
        demoMemberSuggestionsEn.keys,
        orderedEquals(demoMemberSuggestionsKo.keys),
      );
      for (final String member in demoMemberSuggestionsKo.keys) {
        final List<RoutineSuggestion> ko = demoMemberSuggestionsKo[member]!;
        final List<RoutineSuggestion> en = demoMemberSuggestionsEn[member]!;
        expect(en, hasLength(ko.length), reason: member);
        for (var i = 0; i < ko.length; i++) {
          expect(en[i].id, ko[i].id);
          expect(en[i].minutes, ko[i].minutes);
          expect(en[i].type, ko[i].type);
          expect(en[i].sets, ko[i].sets);
          expect(en[i].reps, ko[i].reps);
          expect(en[i].weight, ko[i].weight);
          expect(en[i].evidence, ko[i].evidence);
          expect(en[i].name, isNot(contains(_hangul)));
          expect(en[i].reason, isNot(contains(_hangul)));
        }
      }
    });
  });

  group('AI 루틴 A/B 생성', () {
    Future<RoutineOptions> generate(
      String memberId, {
      Set<RoutineContextSource>? sources,
    }) => MockTrainerRoutineOptionsRepository(db: db).generate(
      memberId,
      availableMinutes: null,
      intensityPreference: null,
      trainerNote: '',
      sources: sources,
    );

    test('스냅샷이 그 회원의 시드 지표에서 오고, 생성 방식은 지금 데모처럼 규칙형이다', () async {
      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-8'))).getSingle();

      final RoutineOptions o = await generate('seed-client-8');

      // 화면의 `규칙 기반 생성` 꼬리표가 남는다 — 지금 데모 화면 그대로다.
      expect(o.generatedBy, 'rule');
      expect(o.analysis.goal, client.goal);
      expect(o.analysis.sodiumTodayMg, client.sodiumMg);
      expect(o.analysis.recentMessages, isNotEmpty);
      expect(
        o.analysis.recentMessages.every(
          (l) => l.startsWith('회원: ') || l.startsWith('트레이너: '),
        ),
        isTrue,
      );
      // 추천 상태는 시드 기록으로 센다(#2674) — 오세라는 기록 2회라 학습 중이다.
      expect(o.analysis.recommendationStatus, RecommendationStatus.learning);

      final RoutineOptions other = await generate('seed-client-5');
      expect(other.analysis.goal, isNot(o.analysis.goal));
    });

    test('근거 문장은 서버 규칙형과 같다 — 고른 자료는 넣지 않고, 목표 이하면 꼬리표가 없다', () async {
      final RoutineOptions all = await generate(
        'seed-client-9',
        sources: RoutineContextSource.values.toSet(),
      );
      final RoutineOptions none = await generate(
        'seed-client-9',
        sources: const <RoutineContextSource>{},
      );
      expect(all.planA.rationale, none.planA.rationale);
      expect(all.planB.rationale, none.planB.rationale);

      final client = await (db.select(
        db.trainerClients,
      )..where((t) => t.id.equals('seed-client-9'))).getSingle();
      expect(
        all.planA.rationale,
        startsWith(
          client.sodiumMg > 2000
              ? '오늘 나트륨 ${client.sodiumMg}mg (목표 초과), '
              : '오늘 나트륨 ${client.sodiumMg}mg, ',
        ),
      );
    });

    test('A안 구성과 B안 문장이 서버 규칙형처럼 회원 지표로 갈린다', () async {
      for (var n = 2; n <= 15; n++) {
        final String id = 'seed-client-$n';
        final RoutineOptions o = await generate(id);
        // 반복 운동형이거나 통증 부위 때문에 구성이 바뀐 회원은 따로 본다
        // (`demo_routine_rules_test.dart`, #2704).
        if (o.planA.label != '회복·지속 중심' ||
            cautionsIn(o.analysis.goal, o.analysis.recentMessages).isNotEmpty) {
          continue;
        }
        final bool ease =
            o.analysis.sodiumOverTarget || o.analysis.avgCompletionRate < 50;
        // 나트륨 초과·완료율 50% 미만이면 목·어깨 스트레칭이 더해진다.
        expect(
          o.planA.exercises.map((e) => e.name),
          ease
              ? <String>['저강도 걷기', '코어 스트레칭', '목·어깨 스트레칭']
              : <String>['저강도 걷기', '코어 스트레칭'],
          reason: id,
        );
        expect(
          o.planA.exercises.fold<int>(0, (int a, e) => a + e.minutes),
          o.planA.totalMinutes,
          reason: id,
        );
        expect(
          o.planB.rationale,
          contains(o.analysis.avgCompletionRate >= 60 ? '상향 여력이 있어' : '점진적으로'),
          reason: id,
        );
      }
    });

    test('모르는 회원은 예전처럼 고정 스냅샷의 규칙형이다', () async {
      final RoutineOptions o = await generate('m1');
      expect(o.generatedBy, 'rule');
      expect(o.analysis.sodiumTodayMg, 2100);
    });
  });
}
