import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fixed_clock.dart';

/// 직접 추가한 운동 기록이 운동 탭에 남는다. (#1428)
///
/// 하단 `+` 로 저장한 기록은 주간 통계·그래프에만 반영되고 개별 기록을 볼 자리가
/// 없었다 — 특히 기본값인 **오늘** 로 적으면 다시 찾을 수도, 고칠 수도 없었다.
/// 식단 탭의 `식사 추가` 처럼 기록을 보는 문맥 안에서 추가하고 결과를 본다.
const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

String _labelOf(DateTime date) => _dayLabels[date.weekday - 1];

/// 오늘 하나는 회원이 직접 적은 기록, 하나는 PT 일지인 주.
ExerciseWeek _week({
  List<ExerciseSession> sessions = const <ExerciseSession>[],
}) {
  // 어느 날을 골라도 그날의 요약이 그려지도록 한 주를 고르게 채운다 —
  // 분이 0 인 날은 `기록 없음` 화면으로 빠져 PT 일지 자리가 없다.
  final List<double> daily = List<double>.filled(7, 40);
  return ExerciseWeek(
    sessions: sessions,
    dailyMinutes: daily,
    dailyCalories: List<double>.filled(7, 280),
    cardioMinutes: daily,
    strengthMinutes: List<double>.filled(7, 0),
    stretchingMinutes: List<double>.filled(7, 0),
    dayLabels: _dayLabels,
    totalMinutes: 280,
    totalCalories: 1960,
    streakDays: 1,
    aiCoachMessage: '',
  );
}

ExerciseSession _memberSession({
  required String id,
  required DateTime date,
  String name = '아침 러닝',
  ExerciseType type = ExerciseType.cardio,
  int minutes = 40,
  int calories = 280,
  int? sets,
  int? reps,
  double? weight,
}) => ExerciseSession(
  id: id,
  dayLabel: _labelOf(date),
  date: date,
  type: type,
  minutes: minutes,
  calories: calories,
  name: name,
  sets: sets,
  reps: reps,
  weight: weight,
);

/// 저장·삭제 호출을 받아 두는 대역. 주간 자료는 저장한 기록을 반영한다.
class _RecordingRepository implements ExerciseRepository {
  _RecordingRepository(this._sessions);

  final List<ExerciseSession> _sessions;

  DateTime? addedDate;
  String? deletedId;

  @override
  Future<String> fetchAdvice(String period) async => '조언';

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _week(sessions: _sessions);

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async =>
      _week(sessions: _sessions);

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
  }) async {
    addedDate = date;
    final ExerciseSession saved = _memberSession(
      id: 'added',
      date: date,
      name: name,
      type: type,
      minutes: minutes,
      calories: calories,
    );
    _sessions.add(saved);
    return saved;
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
  Future<void> deleteSession(String id) async {
    deletedId = id;
    _sessions.removeWhere((ExerciseSession s) => s.id == id);
  }

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

Widget _app(ExerciseRepository repo) => ProviderScope(
  overrides: <Override>[
    appConfigProvider.overrideWithValue(
      const AppConfig(
        environment: Environment.dev,
        apiBaseUrl: 'https://example.test',
        useMockApi: true,
      ),
    ),
    exerciseRepositoryProvider.overrideWithValue(repo),
    accountRepositoryProvider.overrideWithValue(MockAccountRepository()),
    memberCoachRepositoryProvider.overrideWithValue(
      MockMemberCoachRepository() as MemberCoachRepository,
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('ko'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ExercisePage(),
  ),
);

void main() {
  DateTime today() {
    final DateTime now = nowKst();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> pumpExercise(
    WidgetTester tester,
    ExerciseRepository repo,
  ) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
  }

  testWidgets('오늘 직접 추가한 기록이 오늘 화면에 개별 항목으로 보인다', (tester) async {
    useFixedKstDate();
    await pumpExercise(
      tester,
      _RecordingRepository(<ExerciseSession>[
        _memberSession(id: 'own-1', date: today()),
      ]),
    );

    expect(
      find.byKey(const ValueKey<String>('exercise-own-records')),
      findsOneWidget,
    );
    expect(find.text('아침 러닝'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('exercise-own-record-own-1')),
      findsOneWidget,
    );
  });

  testWidgets('저장한 값(유형·운동량·강도·칼로리)이 그대로 보인다', (tester) async {
    useFixedKstDate();
    await pumpExercise(
      tester,
      _RecordingRepository(<ExerciseSession>[
        _memberSession(
          id: 'own-strength',
          date: today(),
          name: '스쿼트',
          type: ExerciseType.strength,
          minutes: 36,
          calories: 210,
          sets: 5,
          reps: 12,
          weight: 60,
        ),
      ]),
    );

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );
    expect(find.text('스쿼트'), findsOneWidget);
    expect(find.text(l.exTypeStrength), findsWidgets);
    // 근력은 세트·횟수·중량으로 읽는다 — 분으로 적으면 화면마다 다른 수가 된다.
    expect(
      find.text('${l.exSetsCount(5)} · ${l.exRepsCount(12)} · 60${l.exUnitKg}'),
      findsOneWidget,
    );
    expect(find.text(l.exLevelModerate), findsWidgets);
    expect(find.text('210 ${l.unitKcal}'), findsWidgets);
  });

  testWidgets('운동 탭 안의 추가 버튼은 하단 + 와 같은 시트를 연다', (tester) async {
    useFixedKstDate();
    await pumpExercise(tester, _RecordingRepository(<ExerciseSession>[]));

    final Finder add = find.byKey(
      const ValueKey<String>('exercise-add-button'),
    );
    expect(add, findsOneWidget);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    // 같은 추가 폼이다 — 하단 `+` → 운동이 여는 시트와 같은 내용 키를 쓴다.
    expect(find.byKey(const Key('exerciseAddContent')), findsOneWidget);
  });

  testWidgets('운동 탭에서 고른 날짜가 추가 폼의 기본 날짜가 된다', (tester) async {
    useFixedKstDate();
    await pumpExercise(tester, _RecordingRepository(<ExerciseSession>[]));

    // 오늘이 아닌 이번 주의 다른 날을 고른다.
    final DateTime target = today().weekday == DateTime.monday
        ? today().add(const Duration(days: 1))
        : today().subtract(const Duration(days: 1));
    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();

    final Finder add = find.byKey(
      const ValueKey<String>('exercise-add-button'),
    );
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );
    // 폼의 날짜 칸이 고른 날을 가리킨다.
    expect(
      find.descendant(
        of: find.byKey(const Key('exerciseDateField')),
        matching: find.textContaining('${target.month}'),
      ),
      findsWidgets,
      reason: l.exExerciseDate,
    );
  });

  testWidgets('기록에서 수정과 삭제로 들어갈 수 있다', (tester) async {
    useFixedKstDate();
    final _RecordingRepository repo = _RecordingRepository(<ExerciseSession>[
      _memberSession(id: 'own-1', date: today()),
    ]);
    await pumpExercise(tester, repo);

    // 수정 — 같은 시트가 그 기록으로 열린다.
    final Finder edit = find.byKey(
      const ValueKey<String>('exercise-own-record-edit-own-1'),
    );
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final AppLocalizations l = AppLocalizations.of(
      tester.element(find.byType(ExercisePage)),
    );
    expect(find.text(l.exEditExercise), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const Key('exerciseAddContent'))),
    ).pop();
    await tester.pumpAndSettle();

    // 삭제 — 목록 줄이 아니라 수정 시트 맨 아래에서, 확인창을 거친 뒤에만
    // 지운다(#1523). 다시 연필을 눌러 시트를 연다.
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final Finder remove = find.byKey(const Key('exerciseDeleteButton'));
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    // 확인창의 제목은 시트의 삭제 버튼과 같은 문구(`exDeleteExercise`)를 쓴다
    // — 버튼은 확인창 아래 그대로 남아 있으므로, 본문으로 확인창만 짚는다.
    expect(find.text(l.exDeleteExerciseBody), findsOneWidget);
    expect(repo.deletedId, isNull, reason: '확인 전에는 지우지 않는다');

    await tester.tap(find.widgetWithText(TextButton, l.actionDelete));
    await tester.pumpAndSettle();
    expect(repo.deletedId, 'own-1');
    // 목록이 곧바로 최신 상태가 된다.
    expect(find.text('아침 러닝'), findsNothing);
  });

  testWidgets('PT 일지·배정 루틴은 직접 기록 목록에 섞이지 않는다', (tester) async {
    useFixedKstDate();
    final DateTime target = today().weekday == DateTime.monday
        ? today().add(const Duration(days: 1))
        : today().subtract(const Duration(days: 1));
    await pumpExercise(
      tester,
      _RecordingRepository(<ExerciseSession>[
        _memberSession(id: 'own-1', date: target, name: '내가 적은 러닝'),
        ExerciseSession(
          id: 'pt-1',
          dayLabel: _labelOf(target),
          date: target,
          type: ExerciseType.strength,
          minutes: 50,
          calories: 300,
          source: ExerciseSource.trainerPt,
          assignedRoutineName: 'PT 세션',
        ),
      ]),
    );

    await tester.tap(find.text('${target.day}').first);
    await tester.pumpAndSettle();

    final Finder section = find.byKey(
      const ValueKey<String>('exercise-own-records'),
    );
    expect(
      find.descendant(of: section, matching: find.text('내가 적은 러닝')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: section, matching: find.textContaining('PT 세션')),
      findsNothing,
    );
    // PT 일지는 자기 자리 — `완료한 PT` 카드 — 에 그대로 남는다(#1884). 종목을
    // 들지 않은 세션은 이름과 운동량을 한 줄로 붙여 적는다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('exercise-pt-records')),
        matching: find.textContaining('PT 세션'),
      ),
      findsOneWidget,
    );
  });
}
