/// 화면 언어가 바뀌면 서버 문장을 다시 읽는다(#2719).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/locale_text_refresh.dart';
import 'package:oncare/features/ai_coach/data/repositories/mock_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/shared/services/locale_provider.dart';

/// 코칭 피드백을 몇 번 읽었는지 센다.
class _CountingAiCoachRepository extends MockAiCoachRepository {
  int fetches = 0;

  @override
  Future<AiCoachState> fetchState() {
    fetches += 1;
    return super.fetchState();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingAiCoachRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _CountingAiCoachRepository();
    container = ProviderContainer(
      overrides: <Override>[
        aiCoachRepositoryProvider.overrideWithValue(repo),
        localeProvider.overrideWith((ref) => const Locale('ko')),
      ],
    );
    addTearDown(container.dispose);
    container.read(localeTextRefreshProvider);
  });

  test('언어가 바뀌면 코칭 피드백을 새 언어로 다시 읽는다', () async {
    await container.read(aiCoachStateProvider.future);
    expect(repo.fetches, 1);

    container.read(localeProvider.notifier).state = const Locale('en');
    await container.read(aiCoachStateProvider.future);

    expect(repo.fetches, 2);
  });

  test('같은 언어를 다시 고르면 읽지 않는다', () async {
    await container.read(aiCoachStateProvider.future);

    container.read(localeProvider.notifier).state = const Locale('ko');
    await container.read(aiCoachStateProvider.future);

    expect(repo.fetches, 1);
  });
}
