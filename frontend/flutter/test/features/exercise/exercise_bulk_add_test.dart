/// 운동 여러 개 한 번에 추가. (#2544)
///
/// 추가 시트에서 `운동 하나 더` 로 운동을 모아 두고 한 번에 저장한다. 저장은
/// 요청 하나다 — 서버가 전부 저장하거나 하나도 저장하지 않는다.
library;

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
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

const ExerciseWeek _emptyWeek = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dayLabels: _dayLabels,
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
);

/// 저장 요청을 받아 두는 대역. [fail] 이면 저장이 실패한다.
class _BatchRepository implements ExerciseRepository {
  final List<List<ExerciseSessionDraft>> requests =
      <List<ExerciseSessionDraft>>[];
  bool fail = false;

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async =>
      const ExerciseAdvice(message: '조언');

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek;

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _emptyWeek;

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
  ) async {
    requests.add(List<ExerciseSessionDraft>.of(drafts));
    if (fail) throw Exception('저장 실패');
    return ExerciseSessionsAdded(
      sessions: <ExerciseSession>[
        for (int i = 0; i < drafts.length; i++)
          ExerciseSession(
            id: 'added-$i',
            dayLabel: _dayLabels[drafts[i].date.weekday - 1],
            type: drafts[i].type,
            minutes: drafts[i].minutes,
            calories: drafts[i].calories,
            name: drafts[i].name,
            date: drafts[i].date,
          ),
      ],
    );
  }

  @override
  Future<void> deleteSession(String id) async {}

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
  }) async => throw UnimplementedError();
}

const Key _sheet = Key('exerciseAddSheet');
const Key _saveButton = Key('exerciseSaveButton');
const Key _cancelButton = Key('exerciseCancelButton');
const Key _addAnother = Key('exerciseAddAnotherButton');

Future<void> _open(
  WidgetTester tester,
  _BatchRepository repo, {
  ExerciseSession? session,
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[exerciseRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showExerciseAddSheet(context, session: session),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// 근력 운동 하나를 폼에 적는다. 근력은 세트 기본값(12세트)이 있어 시간 휠을
/// 굴리지 않아도 저장할 수 있다.
Future<void> _fillStrength(WidgetTester tester, String name) async {
  final Finder chip = find.widgetWithText(AppChoiceChip, '근력');
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  final Finder field = find.byKey(const Key('exerciseNameField'));
  await tester.ensureVisible(field);
  await tester.enterText(field, name);
  await tester.pumpAndSettle();
}

String _saveLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(_saveButton), matching: find.byType(Text)),
    )
    .data!;

void main() {
  testWidgets('운동을 담아 두고 한 번에 저장하면 요청 하나로 모두 보낸다', (
    WidgetTester tester,
  ) async {
    final _BatchRepository repo = _BatchRepository();
    await _open(tester, repo);

    await _fillStrength(tester, '스쿼트');
    await _tapKey(tester, _addAnother);
    // 담으면 폼의 이름이 비고, 위에 `추가할 운동` 목록이 선다.
    expect(find.text('추가할 운동 1'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('exerciseNameField')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      isEmpty,
    );

    await _fillStrength(tester, '데드리프트');
    await _tapKey(tester, _addAnother);
    expect(find.text('추가할 운동 2'), findsOneWidget);
    expect(_saveLabel(tester), '2개 저장');

    // 폼에 이름을 적으면 그 운동도 함께 저장된다 — 개수가 따라간다.
    await _fillStrength(tester, '벤치프레스');
    expect(_saveLabel(tester), '3개 저장');

    await _tapKey(tester, _saveButton);

    expect(repo.requests, hasLength(1));
    expect(
      repo.requests.single.map((ExerciseSessionDraft d) => d.name),
      <String>['스쿼트', '데드리프트', '벤치프레스'],
    );
    expect(
      repo.requests.single.every(
        (ExerciseSessionDraft d) => d.type == ExerciseType.strength,
      ),
      isTrue,
    );
    expect(find.byKey(_sheet), findsNothing);
    expect(find.text('운동 3개가 기록됐어요'), findsOneWidget);
  });

  testWidgets('폼의 이름이 비어 있으면 담아 둔 것만 저장한다', (WidgetTester tester) async {
    final _BatchRepository repo = _BatchRepository();
    await _open(tester, repo);

    await _fillStrength(tester, '스쿼트');
    await _tapKey(tester, _addAnother);
    // 한 건이면 개수를 말하지 않는다.
    expect(_saveLabel(tester), '저장');

    await _tapKey(tester, _saveButton);

    expect(repo.requests.single.map((ExerciseSessionDraft d) => d.name), <String>[
      '스쿼트',
    ]);
    expect(find.text('운동이 기록됐어요'), findsOneWidget);
  });

  testWidgets('담은 운동을 빼면 저장에 실리지 않는다', (WidgetTester tester) async {
    final _BatchRepository repo = _BatchRepository();
    await _open(tester, repo);

    await _fillStrength(tester, '스쿼트');
    await _tapKey(tester, _addAnother);
    await _fillStrength(tester, '런지');
    await _tapKey(tester, _addAnother);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('exerciseQueueItem-0')),
        matching: find.byKey(const Key('exerciseQueueRemoveButton')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('추가할 운동 1'), findsOneWidget);
    expect(find.text('스쿼트'), findsNothing);

    await _tapKey(tester, _saveButton);
    expect(repo.requests.single.map((ExerciseSessionDraft d) => d.name), <String>[
      '런지',
    ]);
  });

  testWidgets('이름 없이 담으려 하면 막힌다', (WidgetTester tester) async {
    final _BatchRepository repo = _BatchRepository();
    await _open(tester, repo);

    await _tapKey(tester, _addAnother);

    expect(find.text('운동 이름을 입력해주세요'), findsOneWidget);
    expect(find.textContaining('추가할 운동'), findsNothing);
  });

  testWidgets('담아 둔 운동이 있으면 취소할 때 버릴지 묻는다', (WidgetTester tester) async {
    final _BatchRepository repo = _BatchRepository();
    await _open(tester, repo);

    await _fillStrength(tester, '스쿼트');
    await _tapKey(tester, _addAnother);

    await _tapKey(tester, _cancelButton);
    expect(find.text('추가할 운동을 버릴까요?'), findsOneWidget);

    // 시트의 취소와 창의 취소가 함께 보인다 — 위에 뜬 창 쪽이다.
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.text('추가할 운동 1'), findsOneWidget);

    await _tapKey(tester, _cancelButton);
    await tester.tap(find.text('버리기'));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsNothing);
    expect(repo.requests, isEmpty);
  });

  testWidgets('저장이 실패하면 담아 둔 목록이 그대로 남는다', (WidgetTester tester) async {
    final _BatchRepository repo = _BatchRepository()..fail = true;
    await _open(tester, repo);

    await _fillStrength(tester, '스쿼트');
    await _tapKey(tester, _addAnother);
    await _fillStrength(tester, '런지');
    await _tapKey(tester, _saveButton);

    expect(repo.requests, hasLength(1));
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.text('추가할 운동 1'), findsOneWidget);
    expect(_saveLabel(tester), '2개 저장');
  });

  testWidgets('수정 시트에는 운동 하나 더가 없다', (WidgetTester tester) async {
    await _open(
      tester,
      _BatchRepository(),
      session: ExerciseSession(
        id: 'ex-1',
        dayLabel: '월',
        type: ExerciseType.cardio,
        minutes: 30,
        calories: 120,
        name: '걷기',
        date: DateTime(2026, 9, 14),
      ),
    );

    expect(find.byKey(_addAnother), findsNothing);
    expect(_saveLabel(tester), '저장');
  });
}
