/// 세션 전환은 내 혜택의 보호권 구역을 다시 읽게 한다. (#1788)
///
/// 보호권 구역은 순회 비용 때문에 값을 들고 있으므로(auto-dispose 아님), 데모에서
/// 로그인으로 넘어갈 때 리셋이 비우지 않으면 앞 계정의 보유 수·보호한 날이 남는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';

import '../exercise/fake_streak_shield_repository.dart';

void main() {
  test('세션 리셋 뒤 보고 있던 보호권 구역을 다시 읽는다', () async {
    final FakeStreakShieldRepository repo = FakeStreakShieldRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        streakShieldRepositoryProvider.overrideWithValue(repo),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    container.listen(myStreakShieldsProvider, (_, _) {});

    await container.read(myStreakShieldsProvider.future);
    expect(repo.fetchCalls, 1);

    container.read(sessionFeatureResetProvider)();
    await container.read(myStreakShieldsProvider.future);

    expect(repo.fetchCalls, 2);
  });
}
