/// 프로필 펫은 받은 남은 시간이 지나면 다시 읽어 사라진다. (#3098)
///
/// 만료는 받을 때 한 번만 판정되므로, 앱을 켜 둔 채 만료 시각을 넘기면 다시 켤
/// 때까지 이름 옆 펫이 남았다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/benefits/domain/entities/profile_pet.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';

import 'fake_benefits_repository.dart';

class _CountingRepository extends FakeBenefitsRepository {
  _CountingRepository({super.pet});

  int fetches = 0;

  @override
  Future<ProfilePet?> fetchProfilePet() async {
    fetches++;
    return pet;
  }
}

void main() {
  testWidgets('남은 시간이 지나면 다시 읽어 null 이 된다', (tester) async {
    final _CountingRepository repo = _CountingRepository(
      pet: ProfilePet.fromStateJson(<String, Object?>{
        'pet': <String, Object?>{'kind': 'dog', 'remaining_seconds': 5},
      }),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[benefitsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<ProfilePet?>> sub = container.listen(
      profilePetProvider,
      (_, _) {},
    );
    addTearDown(sub.close);

    await tester.pump();
    expect(sub.read().valueOrNull?.kind, 'dog');
    expect(repo.fetches, 1);

    // 서버는 만료 펫을 내려 주지 않는다.
    repo.pet = null;
    await tester.pump(const Duration(seconds: 4));
    expect(repo.fetches, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repo.fetches, 2);
    expect(sub.read().valueOrNull, isNull);
    expect(sub.read().hasValue, isTrue);
  });

  testWidgets('펫이 없으면 타이머를 걸지 않는다', (tester) async {
    final _CountingRepository repo = _CountingRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[benefitsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<AsyncValue<ProfilePet?>> sub = container.listen(
      profilePetProvider,
      (_, _) {},
    );
    addTearDown(sub.close);

    await tester.pump();
    await tester.pump(const Duration(days: 8));

    expect(repo.fetches, 1);
    expect(sub.read().valueOrNull, isNull);
  });
}
