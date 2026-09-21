/// 운동 이름 예시와 저장 버튼. (#1460)
///
/// 종류를 바꿔도 예시가 `예) 스쿼트, 러닝머신` 하나로 고정이라, 근력을 고른
/// 사람에게 유산소 예시가 함께 보였다. 저장은 이 시트를 끝내는 동작인데 배경
/// 없는 글자 버튼이라 보조 버튼과 위계가 같았다.
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
import 'package:oncare_ui/oncare_ui.dart';

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

class _StubRepository implements ExerciseRepository {
  @override
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _emptyWeek;

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _emptyWeek;

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
  }) async => throw UnimplementedError();

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

Future<void> _openSheet(WidgetTester tester, {ExerciseSession? session}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        exerciseRepositoryProvider.overrideWithValue(_StubRepository()),
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

/// 이름 입력의 지금 예시 문구.
String _hint(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('exerciseNameField')),
        matching: find.byType(TextField),
      ),
    )
    .decoration!
    .hintText!;

Future<void> _pickType(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('운동 종류마다 그 종류의 예시를 보여 준다', (WidgetTester tester) async {
    await _openSheet(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byKey(const Key('exerciseAddContent'))),
    );

    // 기본은 유산소다.
    expect(_hint(tester), l.exExerciseNameHintCardio);

    await _pickType(tester, l.exTypeStrength);
    expect(_hint(tester), l.exExerciseNameHintStrength);

    await _pickType(tester, l.exTypeFlexibility);
    expect(_hint(tester), l.exExerciseNameHintFlexibility);

    await _pickType(tester, l.exTypeOtherChip);
    expect(_hint(tester), l.exExerciseNameHintOther);
  });

  testWidgets('종류를 바꿔도 적어 둔 이름은 그대로다', (WidgetTester tester) async {
    await _openSheet(tester);
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byKey(const Key('exerciseAddContent'))),
    );

    await tester.enterText(find.byKey(const Key('exerciseNameField')), '아침 러닝');
    await tester.pumpAndSettle();
    await _pickType(tester, l.exTypeStrength);

    expect(find.text('아침 러닝'), findsOneWidget);
    // 예시만 바뀐다 — 적어 둔 이름을 덮어쓰지 않는다.
    expect(_hint(tester), l.exExerciseNameHintStrength);
  });

  testWidgets('수정 모드는 저장된 이름을 그대로 연다', (WidgetTester tester) async {
    await _openSheet(
      tester,
      session: const ExerciseSession(
        id: 'e-1',
        dayLabel: '월',
        type: ExerciseType.strength,
        minutes: 36,
        calories: 210,
        name: '스쿼트',
        sets: 5,
      ),
    );
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byKey(const Key('exerciseAddContent'))),
    );

    expect(find.text('스쿼트'), findsOneWidget);
    // 비워야 그 종류의 예시가 보인다.
    await tester.enterText(find.byKey(const Key('exerciseNameField')), '');
    await tester.pumpAndSettle();
    expect(_hint(tester), l.exExerciseNameHintStrength);
  });

  testWidgets('저장은 취소 오른쪽의 주요(브랜드 채움) 버튼이다', (WidgetTester tester) async {
    await _openSheet(tester);

    // 시트를 끝내는 동작이라 보조 버튼과 위계가 달라야 한다 — 규격의 주요
    // 버튼(브랜드 채움·흰 글자)이다(#1701).
    final Finder saveFinder = find.byKey(const Key('exerciseSaveButton'));
    final Finder cancelFinder = find.byKey(const Key('exerciseCancelButton'));
    final AppButton save = tester.widget<AppButton>(saveFinder);
    final AppButton cancel = tester.widget<AppButton>(cancelFinder);
    expect(save.variant, AppButtonVariant.primary);
    expect(save.fullWidth, isTrue);
    // 저장 중이 아니면 눌린다.
    expect(save.onPressed, isNotNull);

    // 식단 수정 화면과 같은 두 버튼 — [취소] 왼쪽, [저장] 오른쪽, 같은 크기로
    // 폭 반반이다(#1782).
    expect(cancel.variant, AppButtonVariant.secondary);
    expect(cancel.onPressed, isNotNull);
    expect(save.size, OnCareButtonSize.medium);
    expect(cancel.size, save.size);
    expect(
      tester.getCenter(cancelFinder).dx,
      lessThan(tester.getCenter(saveFinder).dx),
    );
    expect(tester.getSize(cancelFinder), tester.getSize(saveFinder));
  });
}
