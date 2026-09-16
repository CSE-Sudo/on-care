import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/storage/prefs_store.dart';
import 'package:oncare/features/app_guide/domain/guide_step.dart';
import 'package:oncare/features/app_guide/presentation/controllers/app_guide_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 첫 홈 진입 가이드의 진행(#1857) — 순서대로 넘어가고, 끝나면 다시 뜨지 않는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('처음에는 꺼져 있다', () async {
    final ProviderContainer container = await containerWith(
      const <String, Object>{},
    );

    expect(container.read(appGuideControllerProvider).active, isFalse);
    expect(container.read(appGuideControllerProvider).step, isNull);
  });

  test('시작하면 첫 자리부터 순서대로 짚고 마지막에서 끝난다', () async {
    final ProviderContainer container = await containerWith(
      const <String, Object>{},
    );
    final AppGuideController controller = container.read(
      appGuideControllerProvider.notifier,
    );

    controller.start();
    expect(container.read(appGuideControllerProvider).step, kGuideSteps.first);
    expect(container.read(appGuideControllerProvider).stepNumber, 1);
    expect(
      container.read(appGuideControllerProvider).totalSteps,
      kGuideSteps.length,
    );

    for (final GuideStepId expected in kGuideSteps.skip(1)) {
      controller.next();
      expect(container.read(appGuideControllerProvider).step, expected);
    }
    expect(container.read(appGuideControllerProvider).isLast, isTrue);

    controller.next();
    expect(container.read(appGuideControllerProvider).active, isFalse);
    // 끝까지 본 회원에게 같은 덮개를 다시 내밀지 않는다.
    expect(container.read(appPrefsProvider).homeGuideDone, isTrue);
  });

  test('건너뛰면 바로 끝나고 본 것으로 남는다', () async {
    final ProviderContainer container = await containerWith(
      const <String, Object>{},
    );
    final AppGuideController controller = container.read(
      appGuideControllerProvider.notifier,
    );

    controller.start();
    controller.next();
    controller.skip();

    expect(container.read(appGuideControllerProvider).active, isFalse);
    expect(container.read(appPrefsProvider).homeGuideDone, isTrue);
  });

  test('새로 가입하면 다시 보여 준다', () async {
    // 본 기억은 계정이 아니라 기기에 남는다 — 한 기기에서 두 번째 계정을 만들면
    // 가입했는데도 가이드가 없는 일이 생겼다.
    final ProviderContainer container = await containerWith(
      const <String, Object>{'home_guide_done': true},
    );
    final AppGuideController controller = container.read(
      appGuideControllerProvider.notifier,
    );

    controller.resetSeen();
    controller.start();

    expect(container.read(appGuideControllerProvider).active, isTrue);
    expect(container.read(appPrefsProvider).homeGuideDone, isFalse);
  });

  test('이미 본 회원에게는 다시 뜨지 않는다', () async {
    final ProviderContainer container = await containerWith(
      const <String, Object>{'home_guide_done': true},
    );

    container.read(appGuideControllerProvider.notifier).start();

    expect(container.read(appGuideControllerProvider).active, isFalse);
  });

  test('설정 저장소가 없어도 가이드는 뜬다', () {
    // 일부 화면 테스트는 SharedPreferences 를 넣지 않는다 — 그때 안내가 통째로
    // 사라지는 것보다, 뜨되 본 기억만 남기지 않는 편이 낫다.
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appGuideControllerProvider.notifier).start();

    expect(container.read(appGuideControllerProvider).active, isTrue);
  });
}
