/// 운동 기록 상세의 수정 모드가 회원이 고치지 않은 값을 저장하거나, 고친 값을
/// 말없이 버리지 않는다 — #3234.
///
/// - 무게·횟수가 비어 있는 근력 기록(푸시업 등)을 기본값 20kg·10회로 채우지
///   않는다. 그 기본값 때문에 같은 날 다른 상자만 고쳐도 이 기록이 저장됐다.
/// - 수정 중 `날짜 변경` 뒤 새 자료를 받는 동안 상자를 빼지 않아 고치던 값이 남는다.
/// - 초를 분으로 바꾸는 규칙이 추가 시트·서버와 같다(2분 30초 → 2분).
///
/// 수정 화면의 숫자가 서버와 어긋나지 않는다 — #3365.
///
/// - 고친 값의 소모 칼로리는 앱이 따로 어림하지 않고 서버 미리보기를 보인다.
/// - `날짜 변경` 은 그날 기록을 한 요청으로 옮긴다. 실패하면 화면도 그대로다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_session_draft.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_record_detail_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

/// 2026-08-20 (목). 같은 주 수요일로 옮긴다.
final DateTime _today = DateTime(2026, 8, 20);

ExerciseSession _session({
  required String id,
  required DateTime date,
  required String name,
  ExerciseType type = ExerciseType.cardio,
  int minutes = 40,
  int calories = 280,
  int? sets,
  int? reps,
  double? weight,
  int? durationSeconds,
}) => ExerciseSession(
  id: id,
  dayLabel: _dayLabels[date.weekday - 1],
  date: date,
  type: type,
  minutes: minutes,
  calories: calories,
  name: name,
  sets: sets,
  reps: reps,
  weight: weight,
  durationSeconds: durationSeconds,
);

/// 수정 요청을 받아 두는 대역. 고친 날짜는 다음 조회에 반영한다.
class _Repo implements ExerciseRepository {
  _Repo(this.sessions);

  final List<ExerciseSession> sessions;
  final List<Map<String, Object?>> updates = <Map<String, Object?>>[];

  /// `날짜 변경` 이 보낸 묶음 이동 — (기록 id 들, 옮길 날).
  final List<(List<String>, DateTime)> moves = <(List<String>, DateTime)>[];

  /// 참이면 묶음 이동이 실패한다 — 아무 기록도 옮겨지지 않는다.
  bool failMove = false;

  /// 미리보기 요청 — 서버가 받은 (이름, 유형, 분).
  final List<(String, ExerciseType, int)> previews =
      <(String, ExerciseType, int)>[];

  /// 서버가 내줄 소모 칼로리. null 이면 앱의 유형 평균과 같은 값을 낸다.
  int? serverCalories;

  /// 참이면 미리보기가 실패한다.
  bool failPreview = false;

  /// 채워 두면 이번 주 조회가 이것이 끝날 때까지 기다린다.
  Completer<void>? gate;

  @override
  Future<ExerciseWeek> fetchThisWeek() async {
    await gate?.future;
    return ExerciseWeek(
      sessions: List<ExerciseSession>.of(sessions),
      dailyMinutes: List<double>.filled(7, 40),
      dailyCalories: List<double>.filled(7, 280),
      cardioMinutes: List<double>.filled(7, 40),
      strengthMinutes: List<double>.filled(7, 0),
      stretchingMinutes: List<double>.filled(7, 0),
      dayLabels: _dayLabels,
      totalMinutes: 280,
      totalCalories: 1960,
      streakDays: 1,
      aiCoachMessage: '',
    );
  }

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) => fetchThisWeek();

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async =>
      const ExerciseAdvice(message: '조언');

  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async {
    previews.add((name, type, minutes));
    if (failPreview) throw StateError('preview failed');
    return ExerciseCalorieEstimate(
      calories:
          serverCalories ??
          estimateExerciseCalories(type, minutes, intensity: intensity),
    );
  }

  @override
  Future<void> moveSessions(List<String> ids, DateTime date) async {
    moves.add((ids, date));
    if (failMove) throw StateError('move failed');
    for (int i = 0; i < sessions.length; i++) {
      final ExerciseSession s = sessions[i];
      if (!ids.contains(s.id)) continue;
      sessions[i] = _session(
        id: s.id!,
        date: date,
        name: s.name,
        type: s.type,
        minutes: s.minutes,
        calories: s.calories,
        sets: s.sets,
        reps: s.reps,
        weight: s.weight,
        durationSeconds: s.durationSeconds,
      );
    }
  }

  @override
  Future<ExerciseSessionsAdded> addSessions(
    List<ExerciseSessionDraft> drafts,
  ) async => throw UnimplementedError();

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
  }) async {
    updates.add(<String, Object?>{
      'id': id,
      'minutes': minutes,
      'date': date,
      'sets': sets,
      'reps': reps,
      'weight': weight,
      'durationSeconds': durationSeconds,
    });
    final int i = sessions.indexWhere((ExerciseSession s) => s.id == id);
    final ExerciseSession saved = _session(
      id: id,
      date: date,
      name: name,
      type: type,
      minutes: minutes,
      calories: calories,
      sets: sets,
      reps: reps,
      weight: weight,
      durationSeconds: durationSeconds,
    );
    sessions[i] = saved;
    return saved;
  }
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  useFixedKstDate();
  tester.view.physicalSize = const Size(500, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: Environment.dev,
            apiBaseUrl: 'https://example.test',
            useMockApi: true,
          ),
        ),
        exerciseRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ExerciseDayDetailPage(date: _today),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(EditableText),
);

String _textOf(WidgetTester tester, String key) =>
    tester.widget<EditableText>(_field(key)).controller.text;

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(_field(key));
  await tester.enterText(_field(key), text);
  await tester.pump();
}

void main() {
  _Repo pushUpAndRun() => _Repo(<ExerciseSession>[
    _session(
      id: 'push-up',
      date: _today,
      name: '푸시업',
      type: ExerciseType.strength,
      minutes: 6,
      calories: 40,
      sets: 3,
    ),
    _session(id: 'run', date: _today, name: '러닝'),
  ]);

  testWidgets('다른 상자만 고쳐 저장하면 맨몸 근력 기록은 보내지 않는다', (tester) async {
    final _Repo repo = pushUpAndRun();
    await _pump(tester, repo);
    await _tapKey(tester, const Key('exercise-detail-edit'));

    // 비어 있던 횟수·무게는 기본값으로 채우지 않는다.
    expect(_textOf(tester, 'exercise-detail-reps-push-up'), isEmpty);
    expect(_textOf(tester, 'exercise-detail-weight-push-up'), isEmpty);

    await _type(tester, 'exercise-detail-minutes-run', '50');
    await _tapKey(tester, const Key('exerciseSaveButton'));

    expect(repo.updates.map((Map<String, Object?> u) => u['id']), <String>[
      'run',
    ]);
  });

  testWidgets('맨몸 근력 기록의 세트만 고치면 횟수·무게는 빈 채로 보낸다', (tester) async {
    final _Repo repo = pushUpAndRun();
    await _pump(tester, repo);
    await _tapKey(tester, const Key('exercise-detail-edit'));

    await _type(tester, 'exercise-detail-sets-push-up', '4');
    await _tapKey(tester, const Key('exerciseSaveButton'));

    expect(repo.updates, hasLength(1));
    final Map<String, Object?> sent = repo.updates.single;
    expect(sent['id'], 'push-up');
    expect(sent['sets'], 4);
    expect(sent['reps'], isNull);
    expect(sent['weight'], isNull);
  });

  testWidgets('수정 중 날짜를 옮겨도 새 자료를 받는 동안 고치던 값이 남는다', (tester) async {
    final _Repo repo = pushUpAndRun();
    await _pump(tester, repo);
    await _tapKey(tester, const Key('exercise-detail-edit'));
    await _type(tester, 'exercise-detail-minutes-run', '55');

    // 옮긴 뒤 다시 받는 조회를 붙들어 둔다.
    repo.gate = Completer<void>();
    await _tapKey(tester, const Key('exercise-detail-date-change'));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('portraitDatePickerCalendar')),
        matching: find.text('19'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('portraitDatePickerConfirm')));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 날짜 이동은 날짜만 옮긴다 — 고치던 값은 아직 상자에만 있고 저장되지 않았다.
    expect(repo.moves.single.$1, unorderedEquals(<String>['push-up', 'run']));
    expect(repo.updates, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('exercise-detail-editor-run')),
      findsOneWidget,
    );
    expect(_textOf(tester, 'exercise-detail-minutes-run'), '55');

    repo.gate!.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('exercise-detail-editor-run')),
      findsOneWidget,
    );
    expect(_textOf(tester, 'exercise-detail-minutes-run'), '55');
  });

  testWidgets('2분 30초는 미리보기도 저장도 2분이다', (tester) async {
    final _Repo repo = _Repo(<ExerciseSession>[
      _session(id: 'run', date: _today, name: '러닝', minutes: 10),
    ]);
    await _pump(tester, repo);
    await _tapKey(tester, const Key('exercise-detail-edit'));

    await _type(tester, 'exercise-detail-minutes-run', '2');
    await _type(tester, 'exercise-detail-seconds-run', '30');
    await _tapKey(tester, const Key('exerciseSaveButton'));

    expect(repo.updates.single['minutes'], 2);
    expect(repo.updates.single['durationSeconds'], 150);
  });
  group('소모 칼로리 미리보기 (#3365)', () {
    /// 상자 아래 소모 칼로리 칸의 글자.
    String calorieBox(WidgetTester tester, String id) {
      final Finder texts = find.descendant(
        of: find.byKey(ValueKey<String>('exercise-detail-calorie-box-$id')),
        matching: find.byType(Text),
      );
      return tester
          .widgetList<Text>(texts)
          .map((Text t) => t.data ?? '')
          .join(' ');
    }

    /// 디바운스가 끝나고 응답이 그려질 때까지 기다린다.
    Future<void> settlePreview(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    _Repo run() =>
        _Repo(<ExerciseSession>[_session(id: 'run', date: _today, name: '러닝')]);

    testWidgets('이름을 바꾸면 서버가 계산한 값을 보인다', (tester) async {
      final _Repo repo = run()..serverCalories = 417;
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));

      await _type(tester, 'exercise-detail-name-field-run', '수영');
      await settlePreview(tester);

      // 시간·유형이 그대로여도 이름이 바뀌면 서버 값이 달라진다 — 앱이 저장된
      // 값을 그대로 두면 저장 직후 숫자가 바뀐다.
      expect(repo.previews.single, ('수영', ExerciseType.cardio, 40));
      expect(calorieBox(tester, 'run'), contains('417'));
      expect(calorieBox(tester, 'run'), isNot(contains('280')));
    });

    testWidgets('시간을 바꿔도 비례 계산이 아니라 서버 값이다', (tester) async {
      final _Repo repo = run()..serverCalories = 333;
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));

      await _type(tester, 'exercise-detail-minutes-run', '50');
      await settlePreview(tester);

      expect(repo.previews.single, ('러닝', ExerciseType.cardio, 50));
      // 예전 비례 계산이면 280 × 50 / 40 = 350 이다.
      expect(calorieBox(tester, 'run'), contains('333'));
      expect(calorieBox(tester, 'run'), isNot(contains('350')));
    });

    testWidgets('응답을 받기 전에는 직전 값을 그대로 둔다', (tester) async {
      final _Repo repo = run()..serverCalories = 333;
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));

      await _type(tester, 'exercise-detail-minutes-run', '50');

      // 아직 묻지 않았다 — 앱이 어림한 숫자를 끼워 넣지 않는다.
      expect(repo.previews, isEmpty);
      expect(calorieBox(tester, 'run'), contains('280'));
      await settlePreview(tester);
    });

    testWidgets('글자마다 묻지 않고 조작이 멎은 뒤 한 번 묻는다', (tester) async {
      final _Repo repo = run();
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));

      await _type(tester, 'exercise-detail-minutes-run', '5');
      await _type(tester, 'exercise-detail-minutes-run', '55');
      await settlePreview(tester);

      expect(repo.previews.single, ('러닝', ExerciseType.cardio, 55));
    });

    testWidgets('저장된 값으로 되돌리면 저장된 칼로리이고 묻지 않는다', (tester) async {
      final _Repo repo = run()..serverCalories = 333;
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));
      await _type(tester, 'exercise-detail-minutes-run', '50');
      await settlePreview(tester);

      await _type(tester, 'exercise-detail-minutes-run', '40');
      await settlePreview(tester);

      expect(repo.previews, hasLength(1));
      expect(calorieBox(tester, 'run'), contains('280'));
    });

    testWidgets('미리보기가 실패하면 유형 평균으로 채우고 저장은 된다', (tester) async {
      final _Repo repo = run()..failPreview = true;
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));

      await _type(tester, 'exercise-detail-minutes-run', '50');
      await settlePreview(tester);

      final int fallback = estimateExerciseCalories(ExerciseType.cardio, 50);
      expect(calorieBox(tester, 'run'), contains('$fallback'));
      await _tapKey(tester, const Key('exerciseSaveButton'));
      expect(repo.updates.single['minutes'], 50);
    });

    testWidgets('이름을 지운 동안에는 묻지 않는다', (tester) async {
      final _Repo repo = run();
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));

      await _type(tester, 'exercise-detail-name-field-run', '');
      await settlePreview(tester);

      expect(repo.previews, isEmpty);
    });

    testWidgets('취소하면 받아 둔 값을 버리고 저장된 칼로리로 돌아간다', (tester) async {
      final _Repo repo = run()..serverCalories = 333;
      await _pump(tester, repo);
      await _tapKey(tester, const Key('exercise-detail-edit'));
      await _type(tester, 'exercise-detail-minutes-run', '50');
      await settlePreview(tester);

      await _tapKey(tester, const Key('exerciseCancelButton'));

      expect(find.textContaining('333'), findsNothing);
      expect(find.textContaining('280'), findsWidgets);
    });
  });

  group('날짜 변경 (#3365)', () {
    Future<void> moveToThe19th(WidgetTester tester) async {
      await _tapKey(tester, const Key('exercise-detail-date-change'));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('portraitDatePickerCalendar')),
          matching: find.text('19'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portraitDatePickerConfirm')));
      await tester.pumpAndSettle();
    }

    testWidgets('그날 기록을 한 요청으로 옮긴다', (tester) async {
      final _Repo repo = pushUpAndRun();
      await _pump(tester, repo);

      await moveToThe19th(tester);

      // 기록마다 수정 요청을 보내지 않는다 — 중간에 실패하면 일부만 옮겨진다.
      expect(repo.updates, isEmpty);
      expect(repo.moves, hasLength(1));
      expect(repo.moves.single.$1, unorderedEquals(<String>['push-up', 'run']));
      expect(repo.moves.single.$2, DateTime(2026, 8, 19));
      expect(
        repo.sessions.map((ExerciseSession s) => s.date),
        everyElement(DateTime(2026, 8, 19)),
      );
    });

    testWidgets('실패하면 어떤 기록도 옮겨지지 않고 화면도 그날에 남는다', (tester) async {
      final _Repo repo = pushUpAndRun()..failMove = true;
      await _pump(tester, repo);

      await moveToThe19th(tester);

      expect(repo.moves, hasLength(1));
      expect(repo.updates, isEmpty);
      expect(
        repo.sessions.map((ExerciseSession s) => s.date),
        everyElement(_today),
      );
      // 두 기록 모두 원래 날 화면에 그대로 있다.
      expect(
        find.byKey(const ValueKey<String>('exercise-detail-card-push-up')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('exercise-detail-card-run')),
        findsOneWidget,
      );
    });
  });
}
