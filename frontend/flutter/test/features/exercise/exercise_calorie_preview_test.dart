/// 예상 소모 칼로리는 운동 이름이 찬 뒤에만 뜬다. (#1312)
///
/// 예전에는 시트를 여는 순간 기본값(유산소·30분·보통)만으로 숫자가 떠 있었다.
/// 이름 칸은 계산에 아무 영향이 없었으므로, 그 숫자가 무엇을 근거로 나왔는지도
/// 이름 칸이 왜 필수인지도 화면에서 읽히지 않았다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/exercise_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const ExerciseWeek _emptyWeek = ExerciseWeek(
  sessions: <ExerciseSession>[],
  dailyMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dailyCalories: <double>[0, 0, 0, 0, 0, 0, 0],
  cardioMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  strengthMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  stretchingMinutes: <double>[0, 0, 0, 0, 0, 0, 0],
  dayLabels: <String>['월', '화', '수', '목', '금', '토', '일'],
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
);

/// 이름이 종목 참조표에 붙은 것처럼 답하는 저장소. 서버가 하는 일을 대신한다 —
/// 앱은 계산하지 않고 받아서 보여 주기만 한다.
class _CatalogRepository implements ExerciseRepository {
  final List<String> askedNames = <String>[];

  @override
  Future<ExerciseCalorieEstimate> previewCalories({
    required ExerciseType type,
    required String name,
    required int minutes,
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
  }) async {
    askedNames.add(name);
    // 표기가 달라도 같은 종목으로 접는 것이 서버 매칭기의 일이다 — 여기서는
    // 그 결과만 흉내 낸다.
    if (name.contains('러닝머신') || name.contains('런닝머신')) {
      return ExerciseCalorieEstimate(
        calories: 290 * minutes ~/ 30,
        source: ExerciseCalorieSource.db,
        matchedName: '러닝머신',
      );
    }
    return ExerciseCalorieEstimate(
      calories: estimateExerciseCalories(type, minutes, intensity: intensity),
    );
  }

  @override
  Future<String> fetchAdvice(String period) async => '';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek;

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _emptyWeek;

  @override
  Future<void> deleteSession(String id) async {}

  @override
  Future<ExerciseSession> addSession({
    required ExerciseType type,
    required int minutes,
    required int calories,
    required DateTime date,
    String name = '',
    ExerciseIntensity intensity = ExerciseIntensity.moderate,
    int? sets,
    int? reps,
    double? weight,
  }) async => throw UnimplementedError();

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
    double? weight,
  }) async => throw UnimplementedError();
}

Future<void> _openSheet(
  WidgetTester tester,
  _CatalogRepository repository, {
  ExerciseSession? session,
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        exerciseRepositoryProvider.overrideWithValue(repository),
      ],
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

AppLocalizations _l(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byKey(const Key('exerciseAddContent'))),
);

/// 이름을 적고 조작이 멎기를 기다린다 — 미리보기는 글자마다 부르지 않는다.
Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('exerciseNameField')), name);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이름을 적기 전에는 확정된 숫자 대신 안내가 뜬다', (WidgetTester tester) async {
    final repository = _CatalogRepository();
    await _openSheet(tester, repository);
    final AppLocalizations l = _l(tester);
    final Finder box = find.byKey(const Key('exerciseCalorieBox'));

    expect(
      find.descendant(of: box, matching: find.text(l.exCaloriesNeedName)),
      findsOneWidget,
    );
    // 이름이 없으면 물어볼 것도 없다 — 서버를 부르지 않는다.
    expect(repository.askedNames, isEmpty);
  });

  testWidgets('이름을 적으면 그 종목 기준으로 계산된 값과 근거가 함께 뜬다', (
    WidgetTester tester,
  ) async {
    final repository = _CatalogRepository();
    await _openSheet(tester, repository);
    final AppLocalizations l = _l(tester);
    final Finder box = find.byKey(const Key('exerciseCalorieBox'));

    await _typeName(tester, '런닝머신');

    expect(repository.askedNames, contains('런닝머신'));
    expect(
      find.descendant(of: box, matching: find.text(l.unitKcalValue(290))),
      findsOneWidget,
    );
    // 회원이 적은 말과 종목 이름이 다를 수 있다 — 무엇으로 계산했는지 보여 준다.
    expect(
      find.descendant(
        of: box,
        matching: find.text(l.exCaloriesFromCatalog('러닝머신')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('종목으로 접히지 않는 이름은 어림값이라고 말한다', (WidgetTester tester) async {
    final repository = _CatalogRepository();
    await _openSheet(tester, repository);
    final AppLocalizations l = _l(tester);
    final Finder box = find.byKey(const Key('exerciseCalorieBox'));

    await _typeName(tester, 'PT 하체날');

    expect(
      find.descendant(of: box, matching: find.text(l.exCaloriesRoughEstimate)),
      findsOneWidget,
    );
  });

  testWidgets('이름을 지우면 숫자도 사라진다', (WidgetTester tester) async {
    final repository = _CatalogRepository();
    await _openSheet(tester, repository);
    final AppLocalizations l = _l(tester);
    final Finder box = find.byKey(const Key('exerciseCalorieBox'));

    await _typeName(tester, '런닝머신');
    expect(
      find.descendant(of: box, matching: find.text(l.unitKcalValue(290))),
      findsOneWidget,
    );

    // 아까 숫자가 남아 있으면 그 값이 무엇의 값인지 알 수 없다.
    await _typeName(tester, '');
    expect(
      find.descendant(of: box, matching: find.text(l.exCaloriesNeedName)),
      findsOneWidget,
    );
  });

  testWidgets('수정 시트는 이름이 이미 차 있어 열자마자 값이 보인다', (WidgetTester tester) async {
    final repository = _CatalogRepository();
    await _openSheet(
      tester,
      repository,
      session: const ExerciseSession(
        id: 'ex-1',
        dayLabel: '월',
        type: ExerciseType.cardio,
        name: '러닝머신',
        minutes: 30,
        calories: 290,
      ),
    );
    final AppLocalizations l = _l(tester);

    expect(repository.askedNames, contains('러닝머신'));
    expect(
      find.descendant(
        of: find.byKey(const Key('exerciseCalorieBox')),
        matching: find.text(l.unitKcalValue(290)),
      ),
      findsOneWidget,
    );
  });
}
