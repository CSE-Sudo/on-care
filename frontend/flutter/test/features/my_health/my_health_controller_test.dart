import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/my_health/data/repositories/mock_my_health_repository.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';

void main() {
  test('myHealthStateProvider returns the account-hub state', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        // Default repo is DioMyHealthRepository (Stage 9.9); use the
        // in-memory mock for the unit test.
        myHealthRepositoryProvider.overrideWithValue(
          const MockMyHealthRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final state = await container.read(myHealthStateProvider.future);
    expect(state.profile.name, '김민수');
    expect(state.profile.email, 'minsu@oncare.com');
    expect(state.profile.id, 'user-7d4e9a2c5f18');
    expect(state.activityPoints, kDemoOpeningPoints);
  });
}
