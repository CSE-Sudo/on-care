/// 홈 코칭 시트의 조언은 기록·날짜가 바뀐 때에만 새로 읽는다. (#3351)
///
/// `aiCoachStateProvider` 는 자동 해제되지 않아 앱을 켠 뒤 처음 받은 내용을 계속
/// 보여 줬다 — 식단을 기록한 뒤에도 "오늘 식단을 기록해 보세요" 카드가 남고, 자정을
/// 넘겨도 어제의 인사말이었다. 여기서는 세 갱신 경로(식단·운동·날짜 변경)가 실제로
/// 저장소를 다시 부르는지, 그 밖에는 부르지 않는지를 본다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/router/day_change_refresh.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_refresh.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_refresh.dart';

import '../../helpers/mock_ai_coach_repository.dart';

/// 조언을 몇 번 받았는지 세고, 받을 때마다 다른 카드를 준다.
class _CountingRepository extends MockAiCoachRepository {
  int stateCalls = 0;

  @override
  Future<AiCoachState> fetchState() async {
    stateCalls++;
    return AiCoachState(
      greeting: '인사 $stateCalls',
      suggestions: <AiSuggestion>[
        AiSuggestion(
          tag: AiSuggestionTag.diet,
          title: '식단 카드 $stateCalls',
          body: '본문',
        ),
        const AiSuggestion(
          tag: AiSuggestionTag.exercise,
          title: '운동 카드',
          body: '본문',
        ),
      ],
    );
  }
}

void main() {
  late _CountingRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _CountingRepository();
    container = ProviderContainer(
      overrides: <Override>[aiCoachRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // 플로팅 버튼의 배지가 앱 수명 내내 읽고 있는 상태를 만든다.
    container.listen(aiCoachStateProvider, (_, _) {});
  });

  Future<AiCoachState> read() => container.read(aiCoachStateProvider.future);

  test('비우지 않으면 다시 받지 않는다 — 처음 받은 내용이 앱 수명 내내 남는다', () async {
    await read();
    await read();

    // 이것이 버그의 바탕이다. 누가 비워 주지 않으면 기록이 카드에 들어오지 않는다.
    expect(repo.stateCalls, 1);
  });

  test('식단 기록이 바뀌면 조언을 다시 받는다', () async {
    final AiCoachState before = await read();

    refreshDietRecords(container.invalidate);
    final AiCoachState after = await read();

    expect(repo.stateCalls, 2);
    expect(before.suggestions.first.title, '식단 카드 1');
    expect(after.suggestions.first.title, '식단 카드 2');
  });

  test('지난 날짜의 식단을 고쳐도 다시 받는다 — 이번 주 집계가 카드에 실린다', () async {
    await read();

    refreshDietRecords(
      container.invalidate,
      dates: <DateTime>[DateTime(2026, 8, 18)],
    );
    await read();

    expect(repo.stateCalls, 2);
  });

  test('운동 기록이 바뀌면 조언을 다시 받는다', () async {
    await read();

    refreshAfterExerciseChange(container.invalidate);
    final AiCoachState after = await read();

    expect(repo.stateCalls, 2);
    expect(after.greeting, '인사 2');
  });

  test('날이 바뀌면 조언을 다시 받고, 같은 날의 복귀에서는 받지 않는다', () async {
    DateTime today = DateTime(2026, 8, 20);
    final DayChangeRefresher refresher = DayChangeRefresher(today: () => today);
    await read();

    expect(refresher.refreshIfDayChanged(container.invalidate), isFalse);
    await read();
    expect(repo.stateCalls, 1);

    today = DateTime(2026, 8, 21);
    expect(refresher.refreshIfDayChanged(container.invalidate), isTrue);
    final AiCoachState after = await read();

    expect(repo.stateCalls, 2);
    expect(after.greeting, '인사 2');
  });

  test('다시 받는 동안에도 직전 내용을 들고 있다', () async {
    await read();

    refreshDietRecords(container.invalidate);
    final AsyncValue<AiCoachState> reloading = container.read(
      aiCoachStateProvider,
    );

    expect(reloading.isLoading, isTrue);
    expect(reloading.valueOrNull?.greeting, '인사 1');
    await read();
  });

  test('세 갱신 목록에 모두 들어 있다', () {
    expect(kDietChangeRefreshTargets, contains(same(aiCoachStateProvider)));
    expect(kExerciseChangeRefreshTargets, contains(same(aiCoachStateProvider)));
    expect(kDayChangeRefreshTargets, contains(same(aiCoachStateProvider)));
  });
}
