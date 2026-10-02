/// 첫 설정을 끝내지 않은 회원은 로그인 뒤 그 화면으로 간다. (#1927)
///
/// 예전에는 `/onboarding` 으로 가는 길이 가입 직후 한 줄뿐이라, 도중에 앱을
/// 닫거나 기기를 바꾸면 생년월일·키·체중·건강 목표가 빈 채로 남고 다시 들어갈
/// 길이 없었다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/account/presentation/first_run_route.dart';

import 'package:shared_preferences/shared_preferences.dart';

const UserProfile _done = UserProfile(
  id: 'u1',
  onboarded: true,
  name: '김민수',
  email: 'minsu@oncare.com',
  birthDate: '1990-01-01',
  gender: 'male',
);

const UserProfile _notDone = UserProfile(
  id: 'u1',
  name: '',
  email: 'minsu@oncare.com',
);

/// 첫 설정을 건너뛴 회원(#2855) — 값은 비어 있지만 다시 묻지 않는다.
const UserProfile _skipped = UserProfile(
  id: 'u1',
  onboardingSkipped: true,
  name: '',
  email: 'minsu@oncare.com',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 헬퍼는 위젯이 아니라 컨테이너를 받는다 — 로그인에 성공하면 라우터가 그
  /// 자리에서 로그인 화면을 갈아 치우기 때문이다.
  Future<String> routeFor({required List<Override> overrides}) async {
    final ProviderContainer container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return firstRouteAfterSignIn(container);
  }

  Future<Override> prefs({required bool seen}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (seen) 'onboarding_done': true,
    });
    return sharedPreferencesProvider.overrideWithValue(
      await SharedPreferences.getInstance(),
    );
  }

  test('첫 설정을 끝낸 회원은 홈으로 간다', () async {
    final String route = await routeFor(
      overrides: <Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_done)),
      ],
    );
    expect(route, AppRoutes.dashboard);
  });

  test('첫 설정을 안 한 회원은 첫 설정으로 간다', () async {
    final String route = await routeFor(
      overrides: <Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_notDone)),
      ],
    );
    expect(route, AppRoutes.onboarding);
  });

  group('건너뛰기 (#2855)', () {
    test('첫 설정을 건너뛴 회원은 홈으로 간다', () async {
      final String route = await routeFor(
        overrides: <Override>[
          await prefs(seen: false),
          profileProvider.overrideWith(() => _StubProfile(_skipped)),
        ],
      );
      expect(route, AppRoutes.dashboard);
    });

    test('건너뛴 회원을 홈으로 보내면 이 기기에도 남긴다', () async {
      final Override prefsOverride = await prefs(seen: false);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          prefsOverride,
          profileProvider.overrideWith(() => _StubProfile(_skipped)),
        ],
      );
      addTearDown(container.dispose);

      await firstRouteAfterSignIn(container);

      expect(container.read(appPrefsProvider).onboardingDone, isTrue);
    });

    test('끝내지도 건너뛰지도 않은 회원(폼에서 앱을 닫음)은 첫 설정으로 간다', () async {
      // #2630 의 의도 — 건너뛰기를 누르지 않았으면 다시 데려온다.
      expect(_notDone.onboarded, isFalse);
      expect(_notDone.onboardingSkipped, isFalse);
      final String route = await routeFor(
        overrides: <Override>[
          await prefs(seen: false),
          profileProvider.overrideWith(() => _StubProfile(_notDone)),
        ],
      );
      expect(route, AppRoutes.onboarding);
    });

    test('끝냈거나 건너뛰었으면 첫 설정이 정리된 계정이다', () {
      expect(_done.firstRunSettled, isTrue);
      expect(_skipped.firstRunSettled, isTrue);
      expect(_notDone.firstRunSettled, isFalse);
    });

    test('프로필 응답의 onboarding_skipped 를 읽는다', () {
      final UserProfile parsed = UserProfile.fromJson(<String, Object?>{
        'id': 'u1',
        'name': '',
        'email': 'a@b.c',
        'onboarded': false,
        'onboarding_skipped': true,
      });
      expect(parsed.onboardingSkipped, isTrue);
      expect(parsed.firstRunSettled, isTrue);
      // 옛 서버 응답(칸 없음)은 건너뛰지 않은 것으로 읽는다.
      expect(
        UserProfile.fromJson(<String, Object?>{
          'id': 'u1',
          'name': '',
          'email': 'a@b.c',
        }).onboardingSkipped,
        isFalse,
      );
    });
  });

  test('프로필을 못 받아 와도 이미 끝낸 기기면 홈으로 간다', () async {
    // 망이 나빴다는 이유로 이미 끝낸 회원을 다시 폼에 세우지 않는다.
    final String route = await routeFor(
      overrides: <Override>[
        await prefs(seen: true),
        profileProvider.overrideWith(_FailingProfile.new),
      ],
    );
    expect(route, AppRoutes.dashboard);
  });

  test('프로필을 못 받아 왔고 기기 기록도 없으면 첫 설정으로 간다', () async {
    final String route = await routeFor(
      overrides: <Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(_FailingProfile.new),
      ],
    );
    expect(route, AppRoutes.onboarding);
  });
}

class _StubProfile extends ProfileController {
  _StubProfile(this._value);

  final UserProfile _value;

  @override
  Future<UserProfile> build() async => _value;
}

class _FailingProfile extends ProfileController {
  @override
  Future<UserProfile> build() async => throw Exception('offline');
}
