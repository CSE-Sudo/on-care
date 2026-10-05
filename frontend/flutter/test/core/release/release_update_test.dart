import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/release/release_probe.dart';
import 'package:oncare/core/release/release_update.dart';

import '../../helpers/fake_release_probe.dart';

/// 새 버전 확인의 비교·상태 규칙(#3023).
void main() {
  group('normalizeReleaseSha', () {
    test('앞뒤 공백·개행을 떼고 소문자로 맞춘다', () {
      expect(normalizeReleaseSha('  ${kNextSha.toUpperCase()}\n'), kNextSha);
      expect(normalizeReleaseSha('abc1234\r\n'), 'abc1234');
    });

    test('SHA 모양이 아니면 null', () {
      expect(normalizeReleaseSha(null), isNull);
      expect(normalizeReleaseSha(''), isNull);
      expect(normalizeReleaseSha('   \n'), isNull);
      expect(normalizeReleaseSha('abc12'), isNull);
      expect(normalizeReleaseSha('<!doctype html><html></html>'), isNull);
      expect(normalizeReleaseSha('${kNextSha}0'), isNull);
      expect(normalizeReleaseSha('zzzzzzzz'), isNull);
    });
  });

  group('isNewerRelease', () {
    test('다른 SHA 면 새 배포다', () {
      expect(isNewerRelease(current: kCurrentSha, latest: kNextSha), isTrue);
    });

    test('같은 SHA 는 공백·대소문자가 달라도 새 배포가 아니다', () {
      expect(
        isNewerRelease(
          current: kCurrentSha,
          latest: ' ${kCurrentSha.toUpperCase()}\n',
        ),
        isFalse,
      );
    });

    test('내장 SHA 가 비었거나 응답이 SHA 가 아니면 판단하지 않는다', () {
      expect(isNewerRelease(current: '', latest: kNextSha), isFalse);
      expect(isNewerRelease(current: kCurrentSha, latest: null), isFalse);
      expect(isNewerRelease(current: kCurrentSha, latest: 'oops'), isFalse);
    });
  });

  test('테스트 빌드에는 내장 SHA 가 없고 확인 간격은 10분이다', () {
    expect(kReleaseSha, isEmpty);
    expect(kReleaseCheckInterval, const Duration(minutes: 10));
  });

  test('웹이 아닌 빌드(모바일 앱·테스트)는 브라우저 기능이 없다', () {
    expect(createReleaseProbe(), isNull);
  });

  test('ReleaseUpdateState 는 닫은 SHA 와 같으면 배너를 내린다', () {
    const ReleaseUpdateState none = ReleaseUpdateState();
    expect(none.showBanner, isFalse);
    final ReleaseUpdateState found = none.copyWith(latestSha: kNextSha);
    expect(found.showBanner, isTrue);
    final ReleaseUpdateState closed = found.copyWith(dismissedSha: kNextSha);
    expect(closed.showBanner, isFalse);
    expect(closed.copyWith(latestSha: kLaterSha).showBanner, isTrue);
  });

  group('ReleaseUpdateController', () {
    late FakeReleaseProbe probe;
    late StreamController<void> ticks;

    setUp(() {
      probe = FakeReleaseProbe();
      ticks = StreamController<void>.broadcast();
    });

    tearDown(() async {
      await ticks.close();
      await probe.close();
    });

    ProviderContainer start({String sha = kCurrentSha, bool withProbe = true}) {
      final ProviderContainer container = ProviderContainer(
        overrides: withProbe
            ? releaseOverrides(probe, sha: sha, ticks: ticks.stream)
            : <Override>[
                releaseShaProvider.overrideWithValue(sha),
                releaseProbeProvider.overrideWithValue(null),
                releaseCheckTicksProvider.overrideWithValue(ticks.stream),
              ],
      );
      addTearDown(container.dispose);
      container.listen(releaseUpdateProvider, (_, _) {});
      return container;
    }

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    bool showing(ProviderContainer c) =>
        c.read(releaseUpdateProvider).showBanner;

    test('시작 직후 한 번 확인하고 다른 SHA 면 배너를 띄운다', () async {
      probe.latest = '$kNextSha\n';
      final ProviderContainer c = start();
      await flush();
      expect(probe.fetchCount, 1);
      expect(showing(c), isTrue);
      expect(c.read(releaseUpdateProvider).latestSha, kNextSha);
    });

    test('같은 SHA 면 배너를 띄우지 않는다', () async {
      probe.latest = kCurrentSha;
      final ProviderContainer c = start();
      await flush();
      expect(probe.fetchCount, 1);
      expect(showing(c), isFalse);
    });

    test('읽기 실패는 조용히 넘기고 다음 확인에서 다시 본다', () async {
      probe.error = StateError('offline');
      final ProviderContainer c = start();
      await flush();
      expect(showing(c), isFalse);

      probe
        ..error = null
        ..latest = kNextSha;
      ticks.add(null);
      await flush();
      expect(probe.fetchCount, 2);
      expect(showing(c), isTrue);
    });

    test('SHA 가 아닌 응답(오류 페이지 등)에는 배너를 띄우지 않는다', () async {
      probe.latest = '<html>Not Found</html>';
      final ProviderContainer c = start();
      await flush();
      expect(showing(c), isFalse);
    });

    test('내장 SHA 가 비면 확인 자체를 하지 않는다', () async {
      probe.latest = kNextSha;
      final ProviderContainer c = start(sha: '');
      await flush();
      ticks.add(null);
      probe.visible.add(null);
      await flush();
      expect(probe.fetchCount, 0);
      expect(showing(c), isFalse);
    });

    test('브라우저 기능이 없으면(모바일·테스트) 아무것도 하지 않는다', () async {
      final ProviderContainer c = start(withProbe: false);
      await flush();
      await c.read(releaseUpdateProvider.notifier).check();
      await c.read(releaseUpdateProvider.notifier).reload();
      expect(showing(c), isFalse);
    });

    test('탭이 다시 보이면 바로 확인한다', () async {
      probe.latest = kCurrentSha;
      final ProviderContainer c = start();
      await flush();
      probe.latest = kNextSha;
      probe.visible.add(null);
      await flush();
      expect(probe.fetchCount, 2);
      expect(showing(c), isTrue);
    });

    test('주기 신호마다 확인한다', () async {
      probe.latest = kCurrentSha;
      start();
      await flush();
      ticks
        ..add(null)
        ..add(null);
      await flush();
      expect(probe.fetchCount, greaterThanOrEqualTo(2));
    });

    test('확인이 진행 중이면 겹쳐 부르지 않는다', () async {
      probe
        ..latest = kNextSha
        ..hold = true;
      final ProviderContainer c = start();
      await flush();
      final ReleaseUpdateController controller = c.read(
        releaseUpdateProvider.notifier,
      );
      unawaited(controller.check());
      unawaited(controller.check());
      await flush();
      expect(probe.fetchCount, 1);
      probe.release();
      await flush();
      expect(showing(c), isTrue);
    });

    test('닫으면 같은 배포에는 다시 띄우지 않고, 더 새 배포에는 다시 띄운다', () async {
      probe.latest = kNextSha;
      final ProviderContainer c = start();
      await flush();
      c.read(releaseUpdateProvider.notifier).dismiss();
      expect(showing(c), isFalse);

      ticks.add(null);
      await flush();
      expect(showing(c), isFalse);

      probe.latest = kLaterSha;
      ticks.add(null);
      await flush();
      expect(showing(c), isTrue);
      expect(c.read(releaseUpdateProvider).latestSha, kLaterSha);
    });

    test('새 배포가 없을 때 닫기는 아무것도 바꾸지 않는다', () async {
      probe.latest = kCurrentSha;
      final ProviderContainer c = start();
      await flush();
      c.read(releaseUpdateProvider.notifier).dismiss();
      expect(c.read(releaseUpdateProvider).dismissedSha, isNull);
    });

    test('새로고침은 브라우저에 맡긴다', () async {
      final ProviderContainer c = start();
      await flush();
      await c.read(releaseUpdateProvider.notifier).reload();
      expect(probe.reloadCount, 1);
    });

    test('정리되면 신호를 더 듣지 않는다', () async {
      probe.latest = kCurrentSha;
      final ProviderContainer c = start();
      await flush();
      c.dispose();
      ticks.add(null);
      probe.visible.add(null);
      await flush();
      expect(probe.fetchCount, 1);
      expect(ticks.hasListener, isFalse);
      expect(probe.visible.hasListener, isFalse);
    });

    group('새로고침(#3204)', () {
      test('누르는 즉시 배너를 내리고, 받으러 간 배포를 남긴 뒤 새로고침한다', () async {
        probe.latest = kNextSha;
        final ProviderContainer c = start();
        await flush();
        expect(showing(c), isTrue);

        final Future<void> pending = c
            .read(releaseUpdateProvider.notifier)
            .reload();
        // 브라우저가 진입 파일을 받는 동안에도 배너는 이미 내려가 있다.
        expect(showing(c), isFalse);
        expect(c.read(releaseUpdateProvider).dismissedSha, kNextSha);
        await pending;
        expect(probe.reloadCount, 1);
        expect(probe.reloadedShaAtReload, <String?>[kNextSha]);
        expect(probe.reloadedSha, kNextSha);
      });

      test('새로고침이 늦는 동안 확인이 와도 같은 배포는 다시 띄우지 않는다', () async {
        probe.latest = kNextSha;
        final ProviderContainer c = start();
        await flush();
        await c.read(releaseUpdateProvider.notifier).reload();

        ticks.add(null);
        probe.visible.add(null);
        await flush();
        expect(showing(c), isFalse);
      });

      test('새 번들이 받으러 간 배포면 기록을 지우고 안내하지 않는다', () async {
        probe
          ..latest = kNextSha
          ..reloadedSha = kNextSha;
        final ProviderContainer c = start(sha: kNextSha);
        await flush();
        expect(probe.reloadedSha, isNull);
        expect(showing(c), isFalse);
        expect(c.read(releaseUpdateProvider).dismissedSha, isNull);
      });

      test('기록은 공백·대소문자가 달라도 같은 배포로 본다', () async {
        probe
          ..latest = kNextSha
          ..reloadedSha = ' ${kNextSha.toUpperCase()}\n';
        start(sha: kNextSha);
        await flush();
        expect(probe.reloadedSha, isNull);
      });

      test('새로고침해도 옛 번들이면 같은 배포 안내를 되풀이하지 않는다', () async {
        probe
          ..latest = kNextSha
          ..reloadedSha = kNextSha;
        final ProviderContainer c = start();
        await flush();
        expect(probe.fetchCount, 1);
        expect(showing(c), isFalse);
        expect(c.read(releaseUpdateProvider).latestSha, kNextSha);
        expect(c.read(releaseUpdateProvider).dismissedSha, kNextSha);
        // 기록은 남는다 — 이 탭에서 다시 새로고침해도 같은 배포로는 안내하지 않는다.
        expect(probe.reloadedSha, kNextSha);
        // 스스로 다시 새로고침하지 않는다.
        expect(probe.reloadCount, 0);

        ticks.add(null);
        probe.visible.add(null);
        await flush();
        expect(showing(c), isFalse);
      });

      test('옛 번들에 머문 뒤에도 더 새 배포는 다시 안내한다', () async {
        probe
          ..latest = kNextSha
          ..reloadedSha = kNextSha;
        final ProviderContainer c = start();
        await flush();
        expect(showing(c), isFalse);

        probe.latest = kLaterSha;
        ticks.add(null);
        await flush();
        expect(showing(c), isTrue);
        expect(c.read(releaseUpdateProvider).latestSha, kLaterSha);
      });

      test('새로고침 한 바퀴: 옛 번들이 다시 떠도 배너가 돌아오지 않는다', () async {
        probe.latest = kNextSha;
        final ProviderContainer first = start();
        await flush();
        expect(showing(first), isTrue);
        await first.read(releaseUpdateProvider.notifier).reload();

        // 브라우저가 옛 번들을 다시 실었다 — 같은 탭 저장소, 같은 내장 SHA.
        final ProviderContainer second = start();
        await flush();
        expect(showing(second), isFalse);
        expect(probe.reloadCount, 1);
      });

      test('기록이 SHA 가 아니면 무시하고 평소처럼 안내한다', () async {
        probe
          ..latest = kNextSha
          ..reloadedSha = 'not-a-sha';
        final ProviderContainer c = start();
        await flush();
        expect(showing(c), isTrue);
      });

      test('탭 저장소를 못 써도 안내와 새로고침은 그대로 한다', () async {
        probe
          ..latest = kNextSha
          ..storageError = StateError('storage blocked');
        final ProviderContainer c = start();
        await flush();
        expect(showing(c), isTrue);

        await c.read(releaseUpdateProvider.notifier).reload();
        expect(showing(c), isFalse);
        expect(probe.reloadCount, 1);
      });

      test('새로고침이 실패해도 오류를 내지 않고 배너는 내려간 채다', () async {
        probe
          ..latest = kNextSha
          ..reloadError = StateError('blocked');
        final ProviderContainer c = start();
        await flush();
        await c.read(releaseUpdateProvider.notifier).reload();
        expect(showing(c), isFalse);
        expect(probe.reloadCount, 1);
      });

      test('안내할 배포가 없으면 기록 없이 새로고침만 한다', () async {
        probe.latest = kCurrentSha;
        final ProviderContainer c = start();
        await flush();
        await c.read(releaseUpdateProvider.notifier).reload();
        expect(probe.reloadCount, 1);
        expect(probe.reloadedSha, isNull);
        expect(c.read(releaseUpdateProvider).dismissedSha, isNull);
      });
    });
  });
}
