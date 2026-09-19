/// 홈 추천 식단이 앱 수명 내내 고정되지 않는다. (#1938)
///
/// `dietRecommendationsProvider` 는 무효화되는 곳이 세션 초기화 하나뿐이었다.
/// 홈에는 당겨서 새로고침이 없고 탭 전환·복귀 갱신도 이 값을 건드리지 않아,
/// 앱을 켠 순간의 추천이 하루 종일 남았다. 첫 조회가 실패하면 기본 추천이
/// 앱을 끌 때까지 고정됐다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/diet/domain/entities/meal_recommendation.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';

void main() {
  test('무효화하면 추천을 다시 읽는다', () async {
    int loads = 0;
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dietRecommendationsProvider.overrideWith((ref) async {
          loads++;
          return MealRecommendations.fallback;
        }),
      ],
    );
    addTearDown(container.dispose);
    // 듣는 사람이 있어야 무효화가 다시 읽기로 이어진다.
    container.listen(dietRecommendationsProvider, (_, _) {});

    await container.read(dietRecommendationsProvider.future);
    expect(loads, 1);

    container.invalidate(dietRecommendationsProvider);
    await container.read(dietRecommendationsProvider.future);

    // 홈 브랜치 갱신·복귀 갱신이 이 무효화를 부른다(`main_shell.dart`).
    expect(loads, 2);
  });
}
