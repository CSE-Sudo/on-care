/// 운동 기록을 지우는 동안 화면이 닫히지 않고, 지운 뒤 갱신이 빠지지 않는다.
/// (#3096)
///
/// 예전에는 지우기 요청 중에 뒤로 가기로 편집 시트·상세 화면을 닫을 수 있었고,
/// 닫힌 화면의 `ref` 로 갱신하다 던져 서버는 지웠는데 `삭제하지 못했어요` 가
/// 떴다. 이번 주 목록·그래프도 지운 기록을 계속 보였다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_record_detail_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_ui/oncare_ui.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 지우기를 [gate] 가 풀릴 때까지 붙잡는 대역. 이번 주 조회 수를 센다.
class _GatedDeleteRepository implements ExerciseRepository {
  _GatedDeleteRepository(this.sessions);

  final List<ExerciseSession> sessions;
  Completer<void>? gate;
  int weekCalls = 0;
  int deletes = 0;

  ExerciseWeek get _week => ExerciseWeek(
    sessions: List<ExerciseSession>.of(sessions),
    dailyMinutes: const <double>[0, 0, 0, 0, 0, 0, 0],
    dayLabels: _dayLabels,
    totalMinutes: 0,
    totalCalories: 0,
    streakDays: 0,
    aiCoachMessage: '',
  );

  @override
  Future<void> deleteSession(String id) async {
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    deletes++;
    sessions.removeWhere((ExerciseSession s) => s.id == id);
  }

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async =>
      const ExerciseAdvice(message: '조언');

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    weekCalls++;
    return _week;
  }

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _week;

  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async => ExerciseCalorieEstimate(
    calories: estimateExerciseCalories(type, minutes, intensity: intensity),
  );

  @override
  Future<ExerciseSessionsAdded> addSessions(
    List<ExerciseSessionDraft> drafts,
  ) => throw UnimplementedError();

  @override
  Future<ExerciseSession> updateSession({
    required String id,
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) => throw UnimplementedError();
}

ExerciseSession _session(String id, DateTime date) => ExerciseSession(
  id: id,
  dayLabel: _dayLabels[date.weekday - 1],
  type: ExerciseType.cardio,
  minutes: 30,
  calories: 120,
  name: '걷기 $id',
  date: date,
);

void main() {
  late _GatedDeleteRepository repo;

  Future<void> pump(
    WidgetTester tester, {
    required Widget Function(BuildContext context) open,
  }) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          exerciseRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                // 운동 탭의 주간 그래프가 이번 주를 보고 있는 상태.
                ref.watch(exerciseWeekProvider);
                return open(context);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 확인창의 `삭제` 를 누른다 — 지우기 요청이 [gate] 에 걸린 채 남는다.
  Future<void> confirmDelete(WidgetTester tester) async {
    repo.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('exerciseDeleteButton')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제').last);
    await tester.pump();
  }

  /// 시스템 뒤로 가기 — `PopScope` 가 막으면 화면이 그대로다.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> finishDelete(WidgetTester tester) async {
    repo.gate!.complete();
    await tester.pump();
    await tester.pump(OnCareMotion.toastEnter);
  }

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(OnCareMotion.toastVisible);
    await tester.pumpAndSettle();
  }

  testWidgets('상세 화면은 상자를 지우는 중에 뒤로 가기로 닫히지 않는다', (WidgetTester tester) async {
    final DateTime today = todayKst();
    // 두 건 — 하나를 지워도 화면이 남아 있다.
    repo = _GatedDeleteRepository(<ExerciseSession>[
      _session('ex-1', today),
      _session('ex-2', today),
    ]);
    await pump(
      tester,
      open: (BuildContext context) => TextButton(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ExerciseDayDetailPage(date: today),
          ),
        ),
        child: const Text('열기'),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exerciseRecordDetailPage')), findsOneWidget);
    // 상자의 휴지통은 연필을 눌러 고치는 중에 보인다.
    await tester.tap(find.byKey(const Key('exercise-detail-edit')));
    await tester.pumpAndSettle();
    await confirmDelete(tester);

    await pressBack(tester);
    expect(find.byKey(const Key('exerciseRecordDetailPage')), findsOneWidget);

    await finishDelete(tester);
    expect(repo.deletes, 1);
    expect(find.text('운동 기록을 삭제했어요'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(repo.weekCalls, 2);
    // 지운 뒤에는 다시 뒤로 갈 수 있다.
    await pressBack(tester);
    expect(find.byKey(const Key('exerciseRecordDetailPage')), findsNothing);

    await drainToast(tester);
  });
}
