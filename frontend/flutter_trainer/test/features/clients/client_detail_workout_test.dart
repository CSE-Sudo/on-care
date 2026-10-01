import 'dart:io';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_item.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/clients/domain/entities/routine_history_entry.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/sent_delivery.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

/// Seeded client ids by display name — the detail is addressed by id.
const Map<String, String> seedClientIds = <String, String>{
  '김민수': 'seed-client-1',
  '이지수': 'seed-client-2',
  '박성호': 'seed-client-3',
};

/// 김민수의 값은 시드가 아니라 공유 픽스처가 정한다(#757). 기대값을 여기에 적으면
/// 픽스처와 두 벌이 되어 한쪽만 고쳤을 때 조용히 갈린다.
final DemoFixture _fixture = DemoFixture.parse(
  File('../../shared/demo_fixture/assets/kim_minsu.json').readAsStringSync(),
);

/// 운동 이력 맨 위 줄의 날짜 라벨. 오늘을 따라 움직인다.
/// 날짜 줄이 하루를 적는 형태. 미션 카드가 날짜를 따로 적던 시절의
/// `8/23 (오늘)` 은 사라졌다 — 카드를 펼친 줄이 그 날을 말한다(#1025).
/// 세로로 넉넉한 화면.
///
/// 날짜별 기록이 한 목록으로 합쳐지면서(#1025) 기본 800×600 에서는 아래쪽
/// 항목이 한참 밖에 있다. 이 묶음의 테스트들은 배치가 아니라 **무엇이 보이는가**
/// 를 재므로, 스크롤 곡예 대신 화면을 키운다.
void _useTallSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 3000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

String _rowLabel(DateTime d) {
  const List<String> weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];
  return '${d.month}월 ${d.day}일 (${weekdays[d.weekday - 1]})';
}

String _todayRowLabel() => _rowLabel(nowKst());

/// 운동 이력 세 줄 안에서 김민수가 거른 항목의 이름. 화면은 ✓/✗ 표시를 떼고
/// 취소선으로 보여 주므로 이름만 남는다.
/// 거른 항목 하나와 그것이 있던 날. 날짜별 목록은 그 날을 펼쳐야 항목이
/// 보이므로(#1025), 이름만으로는 어디를 펼칠지 알 수 없다.
({DateTime day, String name}) _minsuSkipped() {
  final List<FixtureDay> recent = _fixture
      .daysFor(nowKst())
      .reversed
      .where((FixtureDay d) => d.exercises.isNotEmpty)
      .take(3)
      .toList();
  for (final FixtureDay day in recent) {
    for (final FixtureExercise exercise in day.exercises) {
      if (!exercise.done) {
        return (day: DateTime.parse(day.date), name: exercise.name);
      }
    }
  }
  throw StateError('최근 사흘에 거른 항목이 없다 — 취소선 렌더링을 볼 수 없다');
}

/// 운동 기록만 정해진 세 줄로 바꾼다 — 나머지는 데모 DB 그대로.
///
/// 기간 경계는 픽스처가 아니라 오늘을 기준으로 봐야 하므로, 시드가 무엇을
/// 담고 있든 흔들리지 않게 날짜를 직접 만든다(#1114).
class _DatedHistoryRepository extends DriftClientRepository {
  _DatedHistoryRepository(super.db);

  static const String todayLabel = '오늘-기록';
  static const String oldLabel = '한참-전-기록';
  static const String undatedLabel = '날짜-없는-기록';

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) {
    final DateTime today = todayKst();
    return Stream<List<RoutineHistoryEntry>>.value(<RoutineHistoryEntry>[
      _entry(todayLabel, today),
      _entry(undatedLabel, null),
      _entry(oldLabel, today.subtract(const Duration(days: 30))),
    ]);
  }

  RoutineHistoryEntry _entry(String label, DateTime? completedAt) =>
      RoutineHistoryEntry(
        dateLabel: label,
        label: 'PT 세션 · 트레이너 지도',
        completionRate: 100,
        // 표식을 종목 이름에 둔다 — 기록 카드는 더 이상 `dateLabel` 을 그리지
        // 않는다(그 날은 카드를 펼친 줄이 말한다, #1025).
        exercises: <ClientExerciseItem>[
          ClientExerciseItem.nameOnly('$label ✓'),
        ],
        clientFeedback: '',
        trainerNote: '',
        completedAt: completedAt,
      );
}

/// 실 API 모양의 이력 둘 — UTC 완료 시각과 서버 운동일(`date`). (#2748)
///
/// 하나는 KST 오전 7시 30분에 마쳤고 운동일을 주지 않는 옛 서버 행이다(UTC 로는
/// 전날). 하나는 어제 운동을 오늘 소급 체크한 행이다(완료 시각은 오늘, 운동일은
/// 어제).
class _KstDayHistoryRepository extends DriftClientRepository {
  _KstDayHistoryRepository(super.db);

  static const String earlyLabel = 'KST-이른아침-기록';
  static const String backfillLabel = '소급-체크-기록';

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) {
    final DateTime today = todayKst();
    final DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime utcOfKst(DateTime day, int hour, int minute) => DateTime.utc(
      day.year,
      day.month,
      day.day,
      hour,
      minute,
    ).subtract(kstOffset);
    return Stream<List<RoutineHistoryEntry>>.value(<RoutineHistoryEntry>[
      _entry(earlyLabel, completedAt: utcOfKst(today, 7, 30)),
      _entry(
        backfillLabel,
        completedAt: utcOfKst(today, 10, 0),
        date: yesterday,
      ),
    ]);
  }

  RoutineHistoryEntry _entry(
    String label, {
    required DateTime completedAt,
    DateTime? date,
  }) => RoutineHistoryEntry(
    id: label,
    dateLabel: label,
    label: 'PT 세션 · 트레이너 지도',
    completionRate: 100,
    exercises: <ClientExerciseItem>[ClientExerciseItem.nameOnly('$label ✓')],
    clientFeedback: '',
    trainerNote: '',
    completedAt: completedAt,
    date: date,
  );
}

/// Fails the first `watchHistory`; every other read still succeeds.
class _HistoryFailsOnceRepository extends DriftClientRepository {
  _HistoryFailsOnceRepository(super.db);

  int watchHistoryCalls = 0;

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) {
    watchHistoryCalls++;
    if (watchHistoryCalls == 1) {
      return Stream<List<RoutineHistoryEntry>>.error(
        Exception('history transport detail'),
      );
    }
    return super.watchHistory(clientId);
  }
}

/// 수행을 마친 배정 하나와 아직 안 한 배정 하나를 들고 있는 저장소.
///
/// 데모 시드에는 완료된 배정이 없어, "완료한 것에는 취소가 없다" 를 시드만으로는
/// 볼 수 없다(#1020).
class _MixedRoutineRepository implements TrainerRoutineRepository {
  // 전송 이력의 `직전 전송` 은 이 테스트가 보지 않는다(#2225).
  @override
  Future<SentDelivery?> fetchLatestDelivery(String memberId) async => null;

  @override
  Future<void> assignRoutine(
    String memberId,
    AssignedRoutine routine, {
    String? clientRequestId,
  }) async {}

  @override
  Future<void> assignProgram(
    String memberId,
    Map<String, Object?> payload,
  ) async {}

  @override
  Stream<List<AssignedRoutine>> watchAssignedRoutines(String memberId) =>
      Stream<List<AssignedRoutine>>.value(const <AssignedRoutine>[
        AssignedRoutine(
          id: 'done-1',
          name: '이미 한 루틴',
          minutes: 30,
          type: '근력',
          reason: '',
          source: 'trainer',
          completed: true,
        ),
        AssignedRoutine(
          id: 'todo-1',
          name: '아직 안 한 루틴',
          minutes: 20,
          type: '유산소',
          reason: '',
          source: 'ai',
        ),
      ]);

  @override
  Future<void> updateRoutine(
    String memberId,
    String routineId, {
    String? name,
    int? minutes,
    int? durationSeconds,
    String? type,
    String? reason,
  }) async {}

  @override
  Future<void> deleteRoutine(String memberId, String routineId) async {}
}

/// 피드백·메모가 든 개인 운동 기록 하나 — 카드가 그 글을 그리지 않는지 본다.
class _NotedHistoryRepository extends DriftClientRepository {
  _NotedHistoryRepository(super.db)
    : entry = RoutineHistoryEntry(
        id: 'assigned-ex-r1',
        dateLabel: '8/13 (오늘)',
        // 날짜별 목록은 이 값으로 날을 가른다(#1025, #1114). 오늘 것이라고
        // 말하는 기록이므로 오늘에 놓는다.
        completedAt: nowKst(),
        label: '코어 운동',
        completionRate: 100,
        exercises: <ClientExerciseItem>[
          ClientExerciseItem.nameOnly('코어 운동 · 30분'),
        ],
        clientFeedback: '마지막 세트가 힘들었어요',
        trainerNote: '자세가 안정적이었어요',
        assignedRoutineId: 'r1',
      );

  final RoutineHistoryEntry entry;

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      Stream<List<RoutineHistoryEntry>>.value(<RoutineHistoryEntry>[entry]);
}

/// 오늘 PT 이력이 있고, 회원이 따로 러닝·줄넘기를 적은 날. (#2534)
///
/// 운동 행에는 이력 카드와 겹치는 것(PT 완료 자동 기록·배정 운동 완료)과, 이력
/// 줄과 이름이 같은 `member` 행도 섞어 둔다 — 직접 기록 카드에 그것들이
/// 새어 나오지 않는지 본다.
class _PtDayWithOwnLogsRepository extends DriftClientRepository {
  _PtDayWithOwnLogsRepository(super.db);

  @override
  Stream<List<RoutineHistoryEntry>> watchHistory(String clientId) =>
      Stream<List<RoutineHistoryEntry>>.value(<RoutineHistoryEntry>[
        RoutineHistoryEntry(
          id: 'sched-hist-today',
          dateLabel: '',
          completedAt: nowKst(),
          label: 'PT 세션 · 트레이너 지도',
          completionRate: 100,
          exercises: const <ClientExerciseItem>[
            ClientExerciseItem(
              name: '데드리프트',
              type: 'strength',
              sets: 4,
              reps: 8,
            ),
          ],
          clientFeedback: '',
          trainerNote: '',
        ),
      ]);

  @override
  Future<List<ClientExerciseItem>> fetchExercisesOn(
    String clientId,
    DateTime date,
  ) async {
    if (ymd(date) != ymd(todayKst())) return const <ClientExerciseItem>[];
    return const <ClientExerciseItem>[
      // PT 완료가 남긴 자동 기록 — 이력 카드가 이미 말한다.
      ClientExerciseItem(
        name: '데드리프트',
        type: 'strength',
        sets: 4,
        reps: 8,
        source: 'trainer_pt',
      ),
      // 배정 운동 완료 — 출처를 `member` 로 둔 옛 시드도 배정 id 로 거른다.
      ClientExerciseItem(
        name: '코어 운동',
        minutes: 20,
        source: 'member',
        assignedRoutineId: 'r1',
      ),
      // 이력 줄과 이름이 같은 행 — 같은 운동을 두 번 보이지 않는다.
      ClientExerciseItem(
        name: '데드리프트',
        type: 'strength',
        sets: 4,
        reps: 8,
        source: 'member',
      ),
      // 회원이 앱에서 직접 적은 것.
      ClientExerciseItem(
        name: '러닝',
        type: 'cardio',
        minutes: 66,
        durationSeconds: 3930,
        source: 'member',
      ),
      ClientExerciseItem(
        name: '줄넘기',
        type: 'cardio',
        minutes: 1,
        durationSeconds: 45,
        source: 'member',
      ),
    ];
  }
}

/// 운동 한 줄(`_ExerciseLine`)은 화면 비공개 위젯이라 키 접두사로 찾는다.
final Finder _exerciseLines = find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('workout-exercise-line-'),
);

void main() {
  group('ClientRepository.watchHistory', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test(
      'seeds every logged day, newest first, with decoded exercises',
      () async {
        final history = await DriftClientRepository(
          db,
        ).watchHistory('seed-client-1').first;
        // 예전에는 최근 사흘만 시딩했다. 날짜별 기록이 이력을 그날에 붙이면서
        // 사흘 밖의 날이 비어 보였다 — 픽스처가 가진 날을 모두 옮긴다(#1025).
        // 몇 일인지는 픽스처가 정하므로 숫자를 적지 않고 그쪽에서 센다.
        final int loggedDays = _fixture
            .daysFor(nowKst())
            .where((FixtureDay d) => d.exercises.isNotEmpty)
            .length;
        expect(history.length, loggedDays);
        expect(history.length, greaterThan(3));
        // 날짜 라벨은 오늘을 따라 움직인다. 예전에는 `'7/12 (오늘)'` 로 박혀 있어
        // 데모를 언제 열든 7월 12일이 "오늘"이었다(#757).
        final DateTime now = nowKst();
        expect(history.first.dateLabel, '${now.month}/${now.day} (오늘)');
        expect(history.first.completionRate, 100);
        // 종목 이름은 픽스처가 정한다 — 여기 적으면 두 벌이 된다. 수행 표시는
        // 이름이 아니라 `done` 이 든다(#1902).
        expect(
          history.first.exercises
              .where((ClientExerciseItem e) => e.done)
              .map((ClientExerciseItem e) => e.name),
          contains(_fixture.daysFor(nowKst()).last.exercises.first.name),
        );
        expect(history.first.trainerNote, isNotEmpty);
        // Later entries have no trainer note (box hidden).
        expect(history[1].trainerNote, isEmpty);
      },
    );

    test('returns per-client data (clients differ)', () async {
      final seongho = await DriftClientRepository(
        db,
      ).watchHistory('seed-client-3').first;
      expect(seongho.last.completionRate, 0); // 7/3 · all skipped
      expect(seongho.first.trainerNote, contains('벤치 중량'));
    });
  });

  group('운동 행의 출처 (#2534)', () {
    test('주간 응답의 출처·배정 id 로 직접 기록을 가린다', () {
      final ClientExerciseWeek week = ClientExerciseWeek.fromJson(
        <String, Object?>{
          'day_labels': <String>['월'],
          'daily_minutes': <int>[90],
          'daily_calories': <int>[500],
          'sessions': <Object?>[
            <String, Object?>{
              'day_label': '월',
              'name': '러닝',
              'type': 'cardio',
              'minutes': 30,
              'source': 'member',
            },
            <String, Object?>{
              'day_label': '월',
              'name': '스쿼트',
              'type': 'strength',
              'minutes': 30,
              'source': 'trainer_pt',
            },
            <String, Object?>{
              'day_label': '월',
              'name': '코어 운동',
              'type': 'strength',
              'minutes': 30,
              'source': 'member',
              'assigned_routine_id': 'r1',
            },
          ],
        },
      );
      expect(
        week.itemsByDayLabel['월']!.map((ClientExerciseItem e) => e.isMemberLog),
        <bool>[true, false, false],
      );
    });

    test('출처를 싣지 않던 응답은 서버 기본값인 직접 기록으로 읽는다', () {
      final ClientExerciseWeek week = ClientExerciseWeek.fromJson(
        <String, Object?>{
          'day_labels': <String>['월'],
          'daily_minutes': <int>[30],
          'daily_calories': <int>[200],
          'sessions': <Object?>[
            <String, Object?>{
              'day_label': '월',
              'name': '러닝',
              'type': 'cardio',
              'minutes': 30,
            },
          ],
        },
      );
      expect(week.itemsByDayLabel['월']!.single.isMemberLog, isTrue);
    });

    test('출처를 모르는 행(데모·이력 줄)은 직접 기록이 아니다', () {
      expect(const ClientExerciseItem(name: '러닝').isMemberLog, isFalse);
    });
  });

  group('ClientRepository.fetchExerciseWeek', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db);
    });
    tearDown(() => db.close());

    test('derives demo weekly totals from the same client week', () async {
      final week = await DriftClientRepository(
        db,
      ).fetchExerciseWeek('seed-client-1');
      expect(week.dayLabels, hasLength(7));
      expect(week.dailyMinutes, hasLength(7));
      expect(week.workoutCount, greaterThan(0));
      expect(week.totalMinutes, week.dailyMinutes.reduce((a, b) => a + b));
      expect(week.totalCalories, week.dailyCalories.reduce((a, b) => a + b));
    });
  });

  group('WorkoutView', () {
    // 식단·운동은 자기 `ListView` 를 만들지 않는다(#1024) — 신체·목표·메모
    // 패널과 하나의 스크롤을 공유하도록 `embedded: true` 로 그려진다. 그
    // 공유 스크롤(`ListView`) 자체가 `client-detail-tabs-$clientId` 키를
    // 달고 있다.
    Finder detailScrollable(String clientId) => find
        .descendant(
          of: find.byKey(ValueKey<String>('client-detail-tabs-$clientId')),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> openWorkout(WidgetTester tester, String clientName) async {
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail(
          seedClientIds[clientName]!,
          section: 'workout',
        ),
      );
    }

    testWidgets('운동 기록 카드는 종류와 운동 줄만 그린다 (#2329)', (tester) async {
      _useTallSurface(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) => _NotedHistoryRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );

      final Finder line = find.byKey(
        const ValueKey<String>('workout-exercise-line-assigned-ex-r1-0'),
      );
      await tester.scrollUntilVisible(
        line,
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('코어 운동'), findsWidgets);

      // 기록에 글이 남아 있어도 카드는 그리지 않는다 — 피드백은 채팅·메모에서
      // 모은다.
      expect(find.text('마지막 세트가 힘들었어요'), findsNothing);
      expect(find.text('자세가 안정적이었어요'), findsNothing);
      expect(find.text('트레이너 피드백'), findsNothing);
      expect(find.textContaining('회원 피드백'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('routine-feedback-assigned-ex-r1')),
        findsNothing,
      );
      // 완료 배지(`100%`·트로피)와 `1/1` 도 없다.
      expect(
        find.byKey(const ValueKey<String>('workout-done-count-assigned-ex-r1')),
        findsNothing,
      );
      expect(find.byIcon(Symbols.emoji_events_rounded), findsNothing);
    });

    testWidgets('운동 이번 주에 날짜별 기록이 서고 AI 카드는 없다 (#1025, #2329)', (tester) async {
      _useTallSurface(tester);
      await openWorkout(tester, '김민수');
      await tester.tap(_periodSegment('이번 주'));
      await settle(tester);

      expect(
        find.byKey(const ValueKey<String>('exercise-ai-analysis')),
        findsNothing,
      );
      expect(find.text('AI 기간 분석'), findsNothing);

      // 오늘은 처음부터 펼쳐져 있다 — 이 목록이 예전 `운동 기록` 카드 목록을
      // 대신하므로, 오늘 것까지 눌러야 보이면 한 번 더 손이 간다(#1025).
      final Finder records = find.byKey(
        const ValueKey<String>('exercise-daily-records'),
      );
      expect(records, findsOneWidget);
      final Finder todayRow = find.byKey(
        ValueKey<String>('client-day-tile-${ymd(todayKst())}'),
      );
      expect(
        find.descendant(
          of: todayRow,
          matching: find.byIcon(AppIcons.expandMore),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: records,
          matching: find.textContaining('운동 시간', findRichText: true),
        ),
        findsWidgets,
      );
      // 알약은 "얼마나" 를 말한다. 무엇으로 채워졌는지는 이름이 말한다.
      expect(
        find.descendant(of: records, matching: _exerciseLines),
        findsWidgets,
      );
    });

    testWidgets('운동 전체에도 AI 카드 없이 날짜별 기록이 선다 (#2329)', (tester) async {
      await openWorkout(tester, '김민수');
      await tester.tap(_periodSegment('전체'));
      await settle(tester);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('exercise-daily-records')),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(
        find.byKey(const ValueKey<String>('exercise-ai-analysis')),
        findsNothing,
      );
      expect(find.text('AI 전체 분석'), findsNothing);
      final Finder todayRow = find.byKey(
        ValueKey<String>('client-day-tile-${ymd(todayKst())}'),
      );
      expect(
        find.descendant(
          of: todayRow,
          matching: find.byIcon(AppIcons.expandMore),
        ),
        findsOneWidget,
      );
    });

    testWidgets('김민수 운동 기록이 날짜별로 보이고 메모·완료 배지는 없다', (tester) async {
      _useTallSurface(tester);
      await openWorkout(tester, '김민수');

      // 운동현황이 화면 맨 위다(#1025).
      expect(find.text('운동 현황'), findsOneWidget);
      expect(find.text('이번 주 완료율'), findsNothing);

      // 오늘 줄은 토글이 아닌 일반 박스로 항상 펼쳐져 있다.
      final Finder todayRow = find.byKey(
        ValueKey<String>('client-day-tile-${ymd(todayKst())}'),
      );
      expect(find.text(_todayRowLabel()), findsOneWidget);
      expect(todayRow, findsOneWidget);
      expect(
        find.descendant(
          of: todayRow,
          matching: find.byIcon(AppIcons.expandMore),
        ),
        findsNothing,
      );
      // 오늘 기록은 펼쳐져 운동 줄이 보인다. 시드의 트레이너 메모·회원
      // 피드백과 완료 배지는 그리지 않는다(#2329).
      expect(_exerciseLines, findsWidgets);
      expect(find.text('트레이너 피드백'), findsNothing);
      expect(find.text('무릎 가동범위 체크 필요. 다음 세션 중량 조절 예정.'), findsNothing);
      expect(find.textContaining('회원 피드백'), findsNothing);
      expect(find.byIcon(Symbols.emoji_events_rounded), findsNothing);

      // 거른 항목은 지난 날에 있다. 이 목록은 고른 기간만 다루므로(식단과
      // 같은 규칙, #1025) 기간을 넓힌 뒤 그 날을 펼친다.
      final ({DateTime day, String name}) skipped = _minsuSkipped();
      await tester.tap(_periodSegment('전체'));
      await settle(tester);
      final Finder skippedRow = find.text(_rowLabel(skipped.day));
      expect(skippedRow, findsOneWidget);
      // 줄은 이름 뒤에 값이 붙는다 — `하체 스트레칭 · 15분`(#1902).
      if (find.textContaining(skipped.name).evaluate().isEmpty) {
        await tester.tap(skippedRow);
        await settle(tester);
      }
      expect(find.textContaining(skipped.name), findsWidgets);
    });

    testWidgets('아직 하지 않은 개인 운동을 이 화면에서 취소한다 (#1020)', (tester) async {
      _useTallSurface(tester);
      await openWorkout(tester, '김민수');

      // 배정된 루틴 목록·PT 이력을 되살린 것이 아니다 — 물릴 수 있는 것만
      // 온다(#1025 는 그 목록을 걷어낸 채로 둔다).
      final Finder pending = find.byKey(
        const ValueKey<String>('workout-pending-routines'),
      );
      expect(pending, findsOneWidget);
      expect(find.textContaining('저강도 유산소 (걷기)'), findsOneWidget);

      final Finder cancel = find.byKey(
        const ValueKey<String>(
          'workout-cancel-routine-seed-routine-user-7d4e9a2c5f18-0',
        ),
      );
      expect(cancel, findsOneWidget);

      // 확인 없이 지우지 않는다.
      await tester.tap(cancel);
      await settle(tester);
      expect(find.text('프로그램을 삭제할까요?'), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(AppDialog), matching: find.text('취소')),
      );
      await settle(tester);
      expect(find.textContaining('저강도 유산소 (걷기)'), findsOneWidget);

      // 확인하면 실제로 사라진다 — 데모 저장소가 배정을 들고 있어 취소가
      // 목록에 반영된다(#1020).
      await tester.tap(cancel);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(AppButton, '삭제'),
        ),
      );
      await settle(tester);
      expect(find.textContaining('저강도 유산소 (걷기)'), findsNothing);
      // 나머지 배정은 그대로다.
      expect(find.textContaining('하체 스트레칭'), findsOneWidget);

      // 이번 주·전체는 지나간 기록을 되짚는 화면이라 '앞으로 할 일' 은 접는다.
      await tester.tap(_periodSegment('이번 주'));
      await settle(tester);
      expect(pending, findsNothing);
      expect(find.textContaining('하체 스트레칭'), findsNothing);

      await tester.tap(_periodSegment('오늘'));
      await settle(tester);
      expect(pending, findsOneWidget);
    });

    testWidgets('취소는 이미 완료한 운동 기록을 건드리지 않는다 (#1020)', (tester) async {
      _useTallSurface(tester);
      await openWorkout(tester, '김민수');

      // 오늘 줄은 처음부터 펼쳐져 있고 그 안에 완료한 기록이 있다.
      final int linesBefore = _exerciseLines.evaluate().length;
      expect(linesBefore, greaterThan(0));

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'workout-cancel-routine-seed-routine-user-7d4e9a2c5f18-0',
          ),
        ),
      );
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(AppButton, '삭제'),
        ),
      );
      await settle(tester);

      // 배정만 사라지고 기록은 그대로다 — 한 일이 없던 일이 되지 않는다.
      expect(find.textContaining('저강도 유산소 (걷기)'), findsNothing);
      expect(_exerciseLines.evaluate().length, linesBefore);
    });

    testWidgets('오늘 한 개인 운동도 남아 오늘 완료로 보이고 취소할 수 있다 (#2161)', (tester) async {
      _useTallSurface(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        extraOverrides: <Override>[
          trainerRoutineRepositoryProvider.overrideWithValue(
            _MixedRoutineRepository(),
          ),
        ],
      );

      // 개인 운동은 매일 새로 체크하는 목록이다 — 오늘 한 것도 내일 다시
      // 걸리므로 이 자리에 남고, 오늘 했는지만 표시한다.
      expect(find.text('매일 하는 개인 운동'), findsOneWidget);
      expect(find.textContaining('아직 안 한 루틴'), findsOneWidget);
      expect(find.textContaining('이미 한 루틴'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('workout-routine-done-done-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('workout-routine-done-todo-1')),
        findsNothing,
      );
      // 취소는 목록에서 내릴 뿐 이미 한 기록을 지우지 않으니, 완료한 것도
      // 물릴 수 있다 — 서버는 행을 남기고 그날부터 목록에서 뺀다.
      expect(
        find.byKey(const ValueKey<String>('workout-cancel-routine-todo-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('workout-cancel-routine-done-1')),
        findsOneWidget,
      );
    });

    testWidgets('날짜를 모르는 기록은 어느 기간에서도 사라지지 않는다 (#1114)', (tester) async {
      _useTallSurface(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) => _DatedHistoryRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );

      Finder marker(String label) => find.text(label);

      // 오늘: 오늘 기록은 그 날 줄 안에, 날짜 없는 기록은 따로 모인 자리에.
      // 한참 전 기록은 이 기간에 없다.
      expect(marker(_DatedHistoryRepository.todayLabel), findsOneWidget);
      expect(marker(_DatedHistoryRepository.undatedLabel), findsOneWidget);
      expect(marker(_DatedHistoryRepository.oldLabel), findsNothing);
      expect(find.text('날짜를 알 수 없는 기록'), findsOneWidget);

      // 전체로 넓히면 날짜 없는 기록은 그대로 있고, 지난 기록은 그 날 줄에
      // 가 있다 — 접혀 있으므로 펼쳐야 보인다.
      await tester.tap(_periodSegment('전체'));
      await settle(tester);
      expect(marker(_DatedHistoryRepository.undatedLabel), findsOneWidget);

      final DateTime old30 = todayKst().subtract(const Duration(days: 30));
      await tester.tap(find.text(_rowLabel(old30)));
      await settle(tester);
      expect(marker(_DatedHistoryRepository.oldLabel), findsOneWidget);
    });

    testWidgets('개인운동 이력은 KST 운동일 줄에 묶인다 (#2748)', (tester) async {
      _useTallSurface(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) => _KstDayHistoryRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );

      // 오늘: KST 07:30 에 마친 기록은 오늘 줄에 있다(예전에는 UTC 날짜로 묶여
      // 전날 줄에 붙었다). 어제 운동을 오늘 체크한 기록은 오늘 줄에 없다.
      expect(find.text(_KstDayHistoryRepository.earlyLabel), findsOneWidget);
      expect(find.text(_KstDayHistoryRepository.backfillLabel), findsNothing);
      // 날짜를 아는 기록뿐이라 따로 모인 자리는 없다.
      expect(find.text('날짜를 알 수 없는 기록'), findsNothing);

      // 전체로 넓혀 어제 줄을 펼치면 소급 체크한 기록이 그 운동일에 있다.
      await tester.tap(_periodSegment('전체'));
      await settle(tester);
      final DateTime yesterday = todayKst().subtract(const Duration(days: 1));
      await tester.tap(find.text(_rowLabel(yesterday)));
      await settle(tester);
      expect(find.text(_KstDayHistoryRepository.backfillLabel), findsOneWidget);
    });

    testWidgets('이력이 있는 날에도 회원이 직접 기록한 운동이 보인다 (#2534)', (tester) async {
      _useTallSurface(tester);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail('seed-client-1', section: 'workout'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) =>
                _PtDayWithOwnLogsRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );

      final String today = ymd(todayKst());
      // 이력 카드는 그대로다.
      expect(
        find.byKey(
          const ValueKey<String>('workout-exercise-line-sched-hist-today-0'),
        ),
        findsOneWidget,
      );

      // 그 아래 `직접 기록` 카드 한 장에 회원이 적은 두 줄만 선다.
      final Finder card = find.byKey(
        ValueKey<String>('workout-member-log-$today'),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('직접 기록')),
        findsOneWidget,
      );
      Finder ownLine(int i) =>
          find.byKey(ValueKey<String>('workout-member-log-line-$today-$i'));
      expect(ownLine(0), findsOneWidget);
      expect(ownLine(1), findsOneWidget);
      expect(ownLine(2), findsNothing);
      expect(
        find.descendant(of: card, matching: find.text('러닝 · 1시간 5분 30초')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('줄넘기 · 45초')),
        findsOneWidget,
      );

      // PT 자동 기록·배정 완료·이력과 같은 이름의 행은 직접 기록에 없다.
      expect(
        find.descendant(of: card, matching: find.textContaining('데드리프트')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('코어 운동')),
        findsNothing,
      );
    });

    testWidgets('기록 카드는 색 띠 없는 흰 판이다 (#1025)', (tester) async {
      _useTallSurface(tester);
      await openWorkout(tester, '김민수');

      // 배포된 화면과 같은 판이다 — 네 변이 같은 머리카락 테두리이고, 완료
      // 상태를 판 자체가 색으로 말하지 않는다. 색은 오른쪽 배지에만 있다.
      //
      // 그림자를 가진 판만 고른다. 안쪽의 메모 상자도 왼쪽에 색 띠가 있지만
      // 그건 배포본에도 있는 것이고 그림자가 없다.
      // 판은 공용 [AppCard] 다 — 흰 바탕·네 변 같은 테두리가 컴포넌트에 묶여
      // 있고, 선택 채움(브랜드색)으로 칠해지지 않아야 한다.
      final Iterable<AppCard> cards = tester.widgetList<AppCard>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('exercise-daily-records')),
          matching: find.byType(AppCard),
        ),
      );
      expect(cards, isNotEmpty);
      for (final AppCard card in cards) {
        expect(card.selected, isFalse, reason: '기록 카드에 색이 다시 입혀졌습니다.');
      }
    });

    testWidgets('a failed 운동 기록 load does not take 운동현황 with it', (
      tester,
    ) async {
      // 운동현황(ClientExerciseStatusCard) 은 기록 목록과 다른 provider를
      // 쓴다 — /history 가 실패해도 위 운동현황은 그대로 보여야 한다.
      final container = await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.clientDetail(seedClientIds['김민수']!, section: 'workout'),
        extraOverrides: <Override>[
          clientRepositoryProvider.overrideWith(
            (ref) =>
                _HistoryFailsOnceRepository(ref.watch(appDatabaseProvider)),
          ),
        ],
      );

      // 운동현황은 화면 맨 위라 실패해도 바로 보인다.
      expect(find.text('운동 현황'), findsOneWidget);
      // The failure is reported in place, where the history would be.
      await tester.scrollUntilVisible(
        find.text('운동 기록을 불러오지 못했어요'),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );
      expect(find.text('운동 기록을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('history transport detail'), findsNothing);

      // 재시도 버튼은 안내 문구 바로 아래라, 문구가 보이는 지점에서 아직
      // 화면 밖일 수 있다 — 눌러야 할 것을 직접 끌어올린다.
      final retry = find.descendant(
        of: find.byKey(
          const ValueKey<String>('workout-history-retry-seed-client-1'),
        ),
        matching: find.byType(AppButton),
      );
      await tester.ensureVisible(retry);
      await settle(tester);
      await tester.tap(retry);
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text(_todayRowLabel()),
        150,
        scrollable: detailScrollable('seed-client-1'),
      );

      final repository =
          container.read(clientRepositoryProvider)
              as _HistoryFailsOnceRepository;
      expect(repository.watchHistoryCalls, 2);
      expect(find.text(_todayRowLabel()), findsOneWidget);
    });
  });
}

/// 기간 토글에서 [label] 칸. 세그먼트는 칸마다 키가 없어 토글 안의 글자로 찾는다.
Finder _periodSegment(String label) => find.descendant(
  of: find.byKey(const ValueKey<String>('client-period-toggle')),
  matching: find.text(label),
);
