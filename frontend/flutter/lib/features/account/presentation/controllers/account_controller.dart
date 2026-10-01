import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/data/repositories/dio_account_repository.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/domain/repositories/account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => DioAccountRepository(ref.watch(dioProvider)),
  name: 'accountRepository',
);

class ProfileController extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() {
    return ref.watch(accountRepositoryProvider).fetchProfile();
  }

  /// PUT 응답에 포함된 최신 프로필을 홈·식단·운동 화면에 즉시 공유한다.
  void applyUpdatedProfile(UserProfile profile) {
    state = AsyncData<UserProfile>(profile);
  }

  /// 서버의 지금 프로필을 읽어 공유하고 돌려준다(#2655).
  ///
  /// 담당 트레이너도 같은 목표·신체 칸을 고친다. 들고 있던 값으로 편집을 열면
  /// 그 사이 트레이너가 바꾼 값을 옛 값으로 보여 주고 덮을 수 있다. 읽지
  /// 못하면 던진다 — 부르는 쪽이 들고 있던 값으로 이어 간다.
  Future<UserProfile> refreshFromServer() async {
    final UserProfile fresh = await ref
        .read(accountRepositoryProvider)
        .fetchProfile();
    state = AsyncData<UserProfile>(fresh);
    return fresh;
  }
}

final profileProvider = AsyncNotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
  name: 'profile',
);
