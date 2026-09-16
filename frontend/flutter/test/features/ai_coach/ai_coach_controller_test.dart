import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/ai_coach/data/repositories/mock_ai_coach_repository.dart';
import 'package:oncare/features/ai_coach/domain/entities/ai_coach_state.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';

void main() {
  test('aiCoachStateProvider returns greeting + suggestions', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        // Default repo is DioAiCoachRepository (Stage 9.9); use the
        // in-memory mock for the unit test.
        aiCoachRepositoryProvider.overrideWithValue(MockAiCoachRepository()),
      ],
    );
    addTearDown(container.dispose);
    final state = await container.read(aiCoachStateProvider.future);
    expect(state.greeting, isNotEmpty);
    expect(state.suggestions, isNotEmpty);
    expect(
      state.suggestions.map((AiSuggestion s) => s.tag).toSet().length,
      greaterThan(1),
    );
  });
}
