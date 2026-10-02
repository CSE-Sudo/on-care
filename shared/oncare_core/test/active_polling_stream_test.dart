import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_core/active_polling_stream.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'resume discards the in-flight response and immediately reloads',
    () async {
      final Completer<String> staleRequest = Completer<String>();
      final Completer<String> freshRequest = Completer<String>();
      final Completer<void> firstStarted = Completer<void>();
      final Completer<void> secondStarted = Completer<void>();
      final Completer<void> freshEmitted = Completer<void>();
      final List<String> emitted = <String>[];
      var calls = 0;

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final StreamSubscription<String> subscription =
          activePollingStream<String>(
            load: () {
              calls += 1;
              if (calls == 1) {
                firstStarted.complete();
                return staleRequest.future;
              }
              secondStarted.complete();
              return freshRequest.future;
            },
            interval: const Duration(days: 1),
          ).listen((String value) {
            emitted.add(value);
            if (value == 'fresh' && !freshEmitted.isCompleted) {
              freshEmitted.complete();
            }
          });

      try {
        await firstStarted.future;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

        expect(calls, 1);
        staleRequest.complete('stale');
        await secondStarted.future.timeout(const Duration(seconds: 1));

        expect(calls, 2);
        expect(emitted, isEmpty);

        freshRequest.complete('fresh');
        await freshEmitted.future.timeout(const Duration(seconds: 1));
        expect(emitted, <String>['fresh']);
      } finally {
        if (!staleRequest.isCompleted) staleRequest.complete('cleanup');
        if (!freshRequest.isCompleted) freshRequest.complete('cleanup');
        await subscription.cancel();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    },
  );

  // #2843: 잠깐의 실패는 마지막 값을 지키지만, 상태가 바뀌었다는 오류(담당 해제)는
  // 값을 받은 뒤에도 흘려보내야 한다.
  group('surfaceError', () {
    Future<List<Object>> collect({
      required Object failure,
      bool Function(Object error)? surfaceError,
    }) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var calls = 0;
      final List<Object> events = <Object>[];
      final StreamSubscription<String> sub = activePollingStream<String>(
        load: () async {
          calls += 1;
          if (calls == 1) return 'first';
          throw failure;
        },
        interval: const Duration(milliseconds: 5),
        surfaceError: surfaceError,
      ).listen(events.add, onError: events.add);
      try {
        // 첫 값 뒤로 몇 번 더 실패하도록 기다린다.
        while (calls < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      } finally {
        await sub.cancel();
      }
      return events;
    }

    test('지정하지 않으면 값을 받은 뒤의 실패는 감춘다', () async {
      final List<Object> events = await collect(failure: StateError('503'));

      expect(events, <Object>['first']);
    });

    test('참으로 고른 오류는 값을 받은 뒤에도 알린다', () async {
      final List<Object> events = await collect(
        failure: const FormatException('gone'),
        surfaceError: (Object error) => error is FormatException,
      );

      expect(events.first, 'first');
      expect(events.skip(1), isNotEmpty);
      expect(events.skip(1), everyElement(isA<FormatException>()));
    });

    test('고르지 않은 오류는 여전히 감춘다', () async {
      final List<Object> events = await collect(
        failure: StateError('503'),
        surfaceError: (Object error) => error is FormatException,
      );

      expect(events, <Object>['first']);
    });
  });
}
