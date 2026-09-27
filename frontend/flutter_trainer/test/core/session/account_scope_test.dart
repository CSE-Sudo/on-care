// 계정 경계와 계정 범위 provider 의 수명. (#2285)
//
// 두 가지를 본다.
//  1. 세션이 언제 계정 경계를 넘었다고 알리는가 — 로그인·로그아웃·데모·복구·
//     만료는 경계이고, 같은 계정 안의 프로필 편집은 경계가 아니다.
//  2. `keepAliveForAccount` 를 부른 provider 가 경계에서 어떻게 되는가 — 계정이
//     그대로면 값을 들고 있고, 경계를 넘으면 이전 값을 싣지 않은 채 새로 시작한다.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/shared/models/trainer_profile.dart';

import '../../helpers/account_switch_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('세션이 알리는 계정 경계', () {
    Future<(ProviderContainer, SessionController, List<int>)> start({
      TestTrainer? persisted,
      bool rejectProfile = false,
    }) async {
      final setup = makeAccountSwitchContainer(persisted: persisted);
      setup.auth.rejectProfile = rejectProfile;
      final ProviderContainer container = setup.container;
      final List<int> scopes = <int>[];
      container.listen<int>(
        accountScopeProvider,
        (_, int next) => scopes.add(next),
        fireImmediately: true,
      );
      final SessionController controller = container.read(
        sessionControllerProvider.notifier,
      );
      await settleAsync();
      return (container, controller, scopes);
    }

    test('처음 값은 0 이고 복구가 로그아웃으로 끝나면 한 번 올라간다', () async {
      final (container, _, scopes) = await start();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(scopes, <int>[0, 1]);
    });

    test('저장된 토큰으로 복구하면 로그인한 계정으로 한 번 올라간다', () async {
      final (container, _, scopes) = await start(persisted: TestTrainer.a);
      expect(
        container.read(sessionControllerProvider).profile?.email,
        TestTrainer.a.email,
      );
      expect(scopes, <int>[0, 1]);
    });

    test('복구가 만료로 끝나도 경계다 — 로그아웃 버튼을 거치지 않는 세션 종료', () async {
      final (container, _, scopes) = await start(
        persisted: TestTrainer.a,
        rejectProfile: true,
      );
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedOut,
      );
      expect(scopes.last, greaterThan(0));
    });

    test('로그인 → 로그아웃 → 다른 계정 로그인은 매번 올라간다', () async {
      final (container, controller, scopes) = await start();
      final int base = container.read(accountScopeProvider);

      await controller.login(email: TestTrainer.a.email, password: 'pw');
      final int afterA = container.read(accountScopeProvider);
      expect(afterA, greaterThan(base));

      await controller.signOut();
      final int afterSignOut = container.read(accountScopeProvider);
      expect(afterSignOut, greaterThan(afterA));

      await controller.login(email: TestTrainer.b.email, password: 'pw');
      expect(container.read(accountScopeProvider), greaterThan(afterSignOut));
      // 값은 줄지 않고 한 칸씩만 오른다 — 되돌아간 번호가 예전 세션과 겹치면
      // 그 세션의 값이 되살아날 수 있다.
      for (int i = 1; i < scopes.length; i++) {
        expect(scopes[i], scopes[i - 1] + 1);
      }
    });

    test('같은 계정으로 다시 로그인해도 로그아웃을 사이에 두면 올라간다', () async {
      final (container, controller, _) = await start();
      await controller.login(email: TestTrainer.a.email, password: 'pw');
      final int first = container.read(accountScopeProvider);
      await controller.signOut();
      await controller.login(email: TestTrainer.a.email, password: 'pw');
      expect(container.read(accountScopeProvider), first + 2);
    });

    test('같은 계정의 프로필 편집은 경계가 아니다', () async {
      final (container, controller, _) = await start();
      await controller.login(email: TestTrainer.a.email, password: 'pw');
      final int before = container.read(accountScopeProvider);

      final profile = container.read(sessionControllerProvider).profile!;
      controller.replaceProfile(profile.copyWith(name: '새 이름'));

      expect(container.read(sessionControllerProvider).profile?.name, '새 이름');
      expect(container.read(accountScopeProvider), before);
    });

    test('데모 진입은 경계이고, 데모 안의 프로필 편집은 경계가 아니다', () async {
      final (container, controller, _) = await start();
      final int before = container.read(accountScopeProvider);

      controller.enterDemo();
      final int inDemo = container.read(accountScopeProvider);
      expect(inDemo, before + 1);

      controller.replaceProfile(
        (await _anyProfile(container, controller)).copyWith(name: '데모 이름'),
      );
      expect(container.read(accountScopeProvider), inDemo);
    });

    test('로그아웃 상태 표시는 로그아웃에서만 켜진다', () async {
      final (container, controller, _) = await start();
      expect(container.read(accountSignedOutProvider), isTrue);
      await controller.login(email: TestTrainer.a.email, password: 'pw');
      expect(container.read(accountSignedOutProvider), isFalse);
      await controller.signOut();
      expect(container.read(accountSignedOutProvider), isTrue);
      controller.enterDemo();
      expect(container.read(accountSignedOutProvider), isFalse);
    });

    test('데모에서 나와 실계정으로 들어가면 올라간다', () async {
      final (container, controller, _) = await start();
      controller.enterDemo();
      final int inDemo = container.read(accountScopeProvider);

      await controller.signOut();
      await controller.login(email: TestTrainer.b.email, password: 'pw');

      expect(container.read(accountScopeProvider), inDemo + 2);
    });
  });

  group('keepAliveForAccount', () {
    test('계정이 그대로면 구독자가 없어도 값을 들고 있다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      int builds = 0;
      final provider = FutureProvider.autoDispose<int>((ref) async {
        keepAliveForAccount(ref);
        return ++builds;
      });

      expect(await container.read(provider.future), 1);
      await _drainScheduler();
      expect(await container.read(provider.future), 1);
      expect(builds, 1);
    });

    test('계정이 바뀌면 구독자 없는 provider 는 버려진다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      int disposed = 0;
      final provider = FutureProvider.autoDispose<String>((ref) async {
        keepAliveForAccount(ref);
        ref.onDispose(() => disposed++);
        return 'account-${ref.read(accountScopeProvider)}';
      });

      expect(await container.read(provider.future), 'account-0');
      container.read(accountScopeProvider.notifier).state++;
      await _drainScheduler();

      expect(disposed, 1);
      expect(container.exists(provider), isFalse);
    });

    test('버려진 뒤 처음 읽으면 이전 계정의 값을 싣지 않은 로딩이다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final Completer<String> second = Completer<String>();
      final provider = FutureProvider.autoDispose<String>((ref) {
        keepAliveForAccount(ref);
        return ref.read(accountScopeProvider) == 0
            ? Future<String>.value('A 의 값')
            : second.future;
      });

      expect(await container.read(provider.future), 'A 의 값');
      container.read(accountScopeProvider.notifier).state++;
      await _drainScheduler();

      final AsyncValue<String> first = container.read(provider);
      expect(first.isLoading, isTrue);
      expect(first.hasValue, isFalse);
      expect(first.valueOrNull, isNull);

      second.complete('B 의 값');
      expect(await container.read(provider.future), 'B 의 값');
    });

    test('구독 중에 경계를 넘고 구독이 끝나면, 다음 경계에서 버려진다', () async {
      // 앱의 실제 순서다: 로그아웃하는 순간 화면은 아직 값을 보고 있고(다시 계산),
      // 로그인 화면으로 넘어가며 구독이 끝나고, 다음 계정이 로그인한다(경계).
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = FutureProvider.autoDispose<String>((ref) async {
        keepAliveForAccount(ref);
        final int scope = ref.watch(accountScopeProvider);
        return switch (scope) {
          0 => 'A 의 값',
          1 => throw StateError('로그아웃 상태 — 401'),
          _ => Completer<String>().future,
        };
      });

      final sub = container.listen(provider, (_, _) {});
      expect(await container.read(provider.future), 'A 의 값');

      container.read(accountScopeProvider.notifier).state++; // 로그아웃
      await _drainScheduler();
      // 다시 계산된 상태는 Riverpod 규칙대로 이전 값을 싣고 있다.
      expect(container.read(provider).valueOrNull, 'A 의 값');

      sub.close(); // 로그인 화면으로
      await _drainScheduler();
      container.read(accountScopeProvider.notifier).state++; // B 로그인
      await _drainScheduler();

      final AsyncValue<String> forB = container.read(provider);
      expect(forB.hasValue, isFalse, reason: 'B 에게 A 의 값이 실려 오면 안 된다');
      expect(forB.isLoading, isTrue);
    });

    test('로그아웃 상태에서는 구독이 끝나는 즉시 버려진다', () async {
      // 로그아웃하는 순간 화면이 아직 구독 중이라 다시 계산되더라도, 로그인
      // 화면으로 넘어가 구독이 끝나면 다음 로그인을 기다리지 않고 버려진다.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      int disposed = 0;
      final provider = FutureProvider.autoDispose<String>((ref) async {
        keepAliveForAccount(ref);
        ref.onDispose(() => disposed++);
        return 'account-${ref.watch(accountScopeProvider)}';
      });

      final sub = container.listen(provider, (_, _) {});
      expect(await container.read(provider.future), 'account-0');

      container.read(accountSignedOutProvider.notifier).state = true;
      container.read(accountScopeProvider.notifier).state++; // 로그아웃
      await _drainScheduler();
      expect(container.exists(provider), isTrue, reason: '아직 구독 중이다');

      sub.close(); // 로그인 화면으로
      await _drainScheduler();
      expect(container.exists(provider), isFalse);
      expect(disposed, greaterThanOrEqualTo(2));
    });

    test('family 도 계정이 바뀌면 모든 항목이 버려진다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final List<String> disposed = <String>[];
      final provider = FutureProvider.autoDispose.family<String, String>((
        ref,
        id,
      ) async {
        keepAliveForAccount(ref);
        ref.onDispose(() => disposed.add(id));
        return id;
      });

      await container.read(provider('m1').future);
      await container.read(provider('m2').future);
      container.read(accountScopeProvider.notifier).state++;
      await _drainScheduler();

      expect(disposed, unorderedEquals(<String>['m1', 'm2']));
    });
  });
}

/// 데모 세션에는 프로필이 없을 수 있다 — 편집 경로를 태우려면 하나 쥐여 준다.
Future<TrainerProfile> _anyProfile(
  ProviderContainer container,
  SessionController controller,
) async {
  return container.read(sessionControllerProvider).profile ??
      (await FakeTrainerAuthRepository().fetchProfile(
        TestTrainer.a.accessToken,
      ));
}

/// Riverpod 의 폐기·재계산 예약이 돌 때까지 기다린다.
Future<void> _drainScheduler() => Future<void>.delayed(Duration.zero);
