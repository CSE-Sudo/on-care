/// 하단 `+` 로 기록을 추가하면 그 기록의 탭으로 옮겨 간다. (#1434)
///
/// 홈이나 MY 에서 적으면 성공 토스트만 뜨고 그 탭에 남아, 방금 저장한 것을
/// 보려면 사용자가 식단·운동 탭을 다시 찾아가야 했다. 옮기는 것은 **저장에
/// 성공했을 때만**이다 — 취소하거나 실패하면 보던 탭에 남는다.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/router/app_router.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/advice/exercise_advice.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

ExerciseWeek _emptyWeek() => ExerciseWeek(
  sessions: const <ExerciseSession>[],
  dailyMinutes: List<double>.filled(7, 0),
  dailyCalories: List<double>.filled(7, 0),
  cardioMinutes: List<double>.filled(7, 0),
  strengthMinutes: List<double>.filled(7, 0),
  stretchingMinutes: List<double>.filled(7, 0),
  dayLabels: _dayLabels,
  totalMinutes: 0,
  totalCalories: 0,
  streakDays: 0,
  aiCoachMessage: '',
);

/// 저장은 성공, 나머지는 쓰지 않는 대역.
class _SavingRepository implements ExerciseRepository {
  bool saved = false;

  @override
  Future<ExerciseAdvice> fetchAdvice(String period) async =>
      const ExerciseAdvice(message: '조언');

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek();

  @override
  Future<List<ExercisePeriodWeek>> fetchPeriod({
    DateTime? from,
    DateTime? to,
  }) async => const <ExercisePeriodWeek>[];

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _emptyWeek();

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
    int? holdSeconds,
    int? durationSeconds,
    double? weight,
  }) async {
    saved = true;
    return ExerciseSession(
      id: 'added',
      dayLabel: _dayLabels[date.weekday - 1],
      date: date,
      type: type,
      minutes: minutes,
      calories: calories,
      name: name,
    );
  }

  /// 시트가 여는 순간 부르지 않는다 — 이름이 찬 뒤에만 온다(#1312). 여기서는
  /// 앱이 아는 유형 평균을 그대로 돌려준다.
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

void main() {
  late GoRouter router;

  Future<void> pumpShell(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    router = buildAppRouter(config: _config);
    addTearDown(router.dispose);
    router.go(AppRoutes.dashboard);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  Future<void> openAddSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('recordAddButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('운동을 저장하면 운동 탭으로 옮겨 간다', (WidgetTester tester) async {
    final _SavingRepository repo = _SavingRepository();
    await pumpShell(
      tester,
      overrides: <Override>[exerciseRepositoryProvider.overrideWithValue(repo)],
    );
    expect(location(), contains('/dashboard'));

    await openAddSheet(tester);
    // 시트는 루트 내비게이터 위에 뜬다 — 로컬라이제이션은 그 안의 위젯에서
    // 읽는다(`MaterialApp` 자체 element 에는 아직 delegate 가 없다).
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.text(l.navExercise).last);
    await tester.pumpAndSettle();

    // 이름과 시간을 적고 저장한다 — 둘 중 하나라도 비면 저장이 막힌다.
    // 시트는 0시 0분 0초로 열린다(#2071).
    await tester.enterText(find.byType(TextField).first, '아침 러닝');
    await tester.pump();
    await _rollWheel(tester, 1, 30);
    await tester.tap(find.text(l.exSave));
    await tester.pumpAndSettle();

    expect(repo.saved, isTrue);
    expect(location(), contains('/exercise'));
  });

  testWidgets('운동 추가를 닫기만 하면 보던 탭에 남는다', (WidgetTester tester) async {
    final _SavingRepository repo = _SavingRepository();
    await pumpShell(
      tester,
      overrides: <Override>[exerciseRepositoryProvider.overrideWithValue(repo)],
    );

    await openAddSheet(tester);
    // 시트는 루트 내비게이터 위에 뜬다 — 로컬라이제이션은 그 안의 위젯에서
    // 읽는다(`MaterialApp` 자체 element 에는 아직 delegate 가 없다).
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.text(l.navExercise).last);
    await tester.pumpAndSettle();

    // 시트를 저장하지 않고 닫는다.
    Navigator.of(
      tester.element(find.byKey(const Key('exerciseAddContent'))),
    ).pop();
    await tester.pumpAndSettle();

    expect(repo.saved, isFalse);
    expect(location(), contains('/dashboard'));
  });

  testWidgets('기록 종류 시트를 닫기만 하면 탭이 바뀌지 않는다', (WidgetTester tester) async {
    await pumpShell(tester);

    await openAddSheet(tester);
    await tester.tapAt(const Offset(10, 10)); // 스크림 탭
    await tester.pumpAndSettle();

    expect(location(), contains('/dashboard'));
  });
}

/// 시·분 휠의 [column] 번째 칸을 [steps] 칸만큼 굴린다. (#2071)
///
/// 시트 안이라 부모 스크롤이 휠과 아레나를 다툰다. 슬롭(`kTouchSlop`)을 **넘는**
/// 첫 이동이 승부를 가르고 그 이동 자체는 버려지므로, 그 뒤의 이동이 그대로
/// 칸 수다.
Future<void> _rollWheel(WidgetTester tester, int column, int steps) async {
  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(find.byType(ListWheelScrollView).at(column)),
  );
  await gesture.moveBy(const Offset(0, -kTouchSlop - 1));
  await gesture.moveBy(Offset(0, -40.0 * steps));
  await gesture.up();
  await tester.pumpAndSettle();
}
