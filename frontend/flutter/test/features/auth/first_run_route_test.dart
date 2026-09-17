/// 첫 설정을 끝내지 않은 회원은 로그인 뒤 그 화면으로 간다. (#1927)
///
/// 예전에는 `/onboarding` 으로 가는 길이 가입 직후 한 줄뿐이라, 도중에 앱을
/// 닫거나 기기를 바꾸면 생년월일·키·체중·건강 목표가 빈 채로 남고 다시 들어갈
/// 길이 없었다.
library;

import 'package:flutter/material.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 헬퍼는 `WidgetRef` 를 받으므로 위젯 하나를 세워 그 ref 를 빌려 쓴다.
  Future<String> routeFor(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: Consumer(
          builder: (BuildContext context, WidgetRef r, _) {
            ref = r;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return firstRouteAfterSignIn(ref);
  }

  Future<Override> prefs({required bool seen}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (seen) 'onboarding_done': true,
    });
    return sharedPreferencesProvider.overrideWithValue(
      await SharedPreferences.getInstance(),
    );
  }

  testWidgets('첫 설정을 끝낸 회원은 홈으로 간다', (WidgetTester tester) async {
    final String route = await routeFor(
      tester,
      overrides: <Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_done)),
      ],
    );
    expect(route, AppRoutes.dashboard);
  });

  testWidgets('첫 설정을 안 한 회원은 첫 설정으로 간다', (WidgetTester tester) async {
    final String route = await routeFor(
      tester,
      overrides: <Override>[
        await prefs(seen: false),
        profileProvider.overrideWith(() => _StubProfile(_notDone)),
      ],
    );
    expect(route, AppRoutes.onboarding);
  });

  testWidgets('프로필을 못 받아 와도 이미 끝낸 기기면 홈으로 간다', (WidgetTester tester) async {
    // 망이 나빴다는 이유로 이미 끝낸 회원을 다시 폼에 세우지 않는다.
    final String route = await routeFor(
      tester,
      overrides: <Override>[
        await prefs(seen: true),
        profileProvider.overrideWith(_FailingProfile.new),
      ],
    );
    expect(route, AppRoutes.dashboard);
  });

  testWidgets('프로필을 못 받아 왔고 기기 기록도 없으면 첫 설정으로 간다', (
    WidgetTester tester,
  ) async {
    final String route = await routeFor(
      tester,
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
