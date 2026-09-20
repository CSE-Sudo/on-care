/// 세션 전환은 주간 챌린지를 다시 읽게 한다. (#1789)
///
/// 두 provider 는 auto-dispose 지만, 사용처·내 혜택·운동 화면을 연 채로 계정이
/// 바뀌면 살아남아 앞 계정의 참가·진행을 보여 준다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/session/session_feature_reset.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';

import '../benefits/fake_challenge_repository.dart';

void main() {
  test('세션 리셋 뒤 보고 있던 챌린지를 다시 읽는다', () async {
    final FakeChallengeRepository repo = FakeChallengeRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        challengeRepositoryProvider.overrideWithValue(repo),
        sessionFeatureResetOverride(),
      ],
    );
    addTearDown(container.dispose);
    container.listen(weeklyChallengeProvider, (_, _) {});

    await container.read(weeklyChallengeProvider.future);
    expect(repo.weeklyCalls, 1);

    container.read(sessionFeatureResetProvider)();
    await container.read(weeklyChallengeProvider.future);

    expect(repo.weeklyCalls, 2);
  });
}
