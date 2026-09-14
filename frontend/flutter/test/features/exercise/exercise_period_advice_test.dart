/// 운동 탭의 AI 맞춤 조언도 기간 토글을 따라간다. (#1574)
///
/// 식단 탭이 먼저 한 것(#1017)과 같은 규칙이다. 예전에는 조언이 주간 요약에
/// 실려 온 문장 하나뿐이라, `오늘` 을 보든 `전체` 를 보든 같은 말이 남았다 —
/// 그래프만 갈아 끼우면 조언이 지금 화면과 무관한 말이 된다.
///
/// 화면 순서도 여기서 함께 못 박는다. `직접 추가한 운동` 은 코칭이 말하는 것
/// (조언 → PT 일지 → 추천 개인운동) 아래에 선다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/design_system/theme/app_theme.dart';
import 'package:oncare/features/account/data/repositories/mock_account_repository.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_estimate.dart';
import 'package:oncare/features/exercise/domain/entities/exercise_week.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/widgets/own_exercise_records.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_card.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/ai_advice_card.dart';

const List<String> _dayLabels = <String>['월', '화', '수', '목', '금', '토', '일'];

ExerciseWeek _week() {
  final List<double> daily = List<double>.filled(7, 40);
  return ExerciseWeek(
    sessions: const <ExerciseSession>[],
    dailyMinutes: daily,
    dailyCalories: List<double>.filled(7, 280),
    cardioMinutes: daily,
    strengthMinutes: List<double>.filled(7, 0),
    stretchingMinutes: List<double>.filled(7, 0),
    dayLabels: _dayLabels,
    totalMinutes: 280,
    totalCalories: 1960,
    streakDays: 1,
    // 주간 요약이 들고 오는 옛 문장. 기간 조언이 이 값으로 되돌아가면 안 된다.
    aiCoachMessage: '주간 요약이 들고 온 옛 조언',
  );
}

/// 기간마다 다른 문장을 주는 대역. [pending] 에 든 기간은 응답을 붙잡아 두고,
/// [failing] 에 든 기간은 실패한다.
class _AdviceRepository implements ExerciseRepository {
  _AdviceRepository({
    this.pending = const <String>{},
    this.failing = const <String>{},
  });

  final Set<String> pending;
  final Set<String> failing;

  /// 기간별 요청 횟수 — 다시 시도가 정말 그 기간을 다시 부르는지 본다.
  final Map<String, int> calls = <String, int>{};

  @override
  Future<String> fetchAdvice(String period) {
    calls[period] = (calls[period] ?? 0) + 1;
    if (pending.contains(period)) return Completer<String>().future;
    if (failing.contains(period)) {
      return Future<String>.error(StateError('advice unavailable'));
    }
    return Future<String>.value('$period 기간 조언');
  }

  @override
  Future<ExerciseWeek> fetchThisWeek() async => _week();

  @override
  Future<ExerciseWeek> fetchWeek(DateTime weekStart) async => _week();

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
  Future<void> deleteSession(String id) async => throw UnimplementedError();

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

/// 조언 카드가 지금 보여 주는 글자 전부.
String _adviceText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AiAdviceShell),
        matching: find.byType(Text),
      ),
    )
    .map((Text t) => t.data ?? '')
    .join(' ');

Future<void> _pump(WidgetTester tester, ExerciseRepository repo) async {
  tester.view.physicalSize = const Size(500, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(repo));
  await tester.pumpAndSettle();
}

/// 기간 토글의 칸을 누른다. 0 = 오늘, 1 = 이번 주, 2 = 전체.
Future<void> _tapPeriod(WidgetTester tester, int index) async {
  final AppLocalizations l = AppLocalizations.of(
    tester.element(find.byType(ExercisePage)),
  );
  final String label = <String>[l.exToday, l.exThisWeek, l.exPeriodAll][index];
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('오늘 / 이번 주 / 전체가 각각 다른 조언을 보여 준다', (WidgetTester tester) async {
    final _AdviceRepository repo = _AdviceRepository();
    await _pump(tester, repo);

    expect(_adviceText(tester), contains('today 기간 조언'));

    await _tapPeriod(tester, 1);
    expect(_adviceText(tester), contains('week 기간 조언'));

    await _tapPeriod(tester, 2);
    expect(_adviceText(tester), contains('all 기간 조언'));
  });

  testWidgets('주간 조언을 기다리는 동안 오늘 조언으로 되돌아가지 않는다', (WidgetTester tester) async {
    final _AdviceRepository repo = _AdviceRepository(pending: <String>{'week'});
    await _pump(tester, repo);
    final String todayAdvice = _adviceText(tester);

    await _tapPeriod(tester, 1);

    expect(find.byKey(const ValueKey<String>('ai-advice-loading')), findsOne);
    expect(_adviceText(tester), isNot(contains(todayAdvice)));
    // 주간 요약이 들고 온 옛 문장으로도 내려앉지 않는다.
    expect(_adviceText(tester), isNot(contains('주간 요약이 들고 온 옛 조언')));
  });

  testWidgets('실패한 기간은 실패했다고 말하고 다시 시도할 길을 준다', (WidgetTester tester) async {
    final _AdviceRepository repo = _AdviceRepository(failing: <String>{'all'});
    await _pump(tester, repo);

    await _tapPeriod(tester, 2);

    expect(find.byKey(const ValueKey<String>('ai-advice-error')), findsOne);
    expect(_adviceText(tester), isNot(contains('today 기간 조언')));

    final int before = repo.calls['all']!;
    await tester.tap(find.byKey(const ValueKey<String>('ai-advice-retry')));
    await tester.pumpAndSettle();
    expect(repo.calls['all'], before + 1);
  });

  testWidgets('직접 추가한 운동은 추천 개인운동 아래에 선다', (WidgetTester tester) async {
    await _pump(tester, _AdviceRepository());

    final double coaching = tester
        .getTopLeft(find.byType(AiCoachingCard, skipOffstage: false))
        .dy;
    final double ownRecords = tester
        .getTopLeft(find.byType(OwnExerciseRecords, skipOffstage: false))
        .dy;
    // 위쪽은 "무엇을 해야 하나", 아래쪽은 "내가 무엇을 했나" 다.
    expect(ownRecords, greaterThan(coaching));
  });
}
