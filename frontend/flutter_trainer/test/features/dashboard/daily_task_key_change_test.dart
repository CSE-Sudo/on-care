/// 오늘 할 일의 키 단위 저장. (#2886)
///
/// 체크할 때마다 그날 목록 전체를 덮어쓰면, 두 탭·기기에서 서로 다른 할 일을
/// 체크했을 때 나중에 저장한 쪽이 앞의 체크를 지웠다. 이제 누른 키 하나만
/// 보내고, 서버(데모는 로컬 저장소)가 저장된 집합에 그 키만 반영한다.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/dashboard/data/daily_task_progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

TaskKeyChange _change(
  String key,
  TaskKeyAction action, {
  Set<String> keys = const <String>{},
  Set<String>? seen,
  Set<String> carriedOver = const <String>{},
}) => TaskKeyChange(
  key: key,
  action: action,
  keys: keys,
  seen: seen ?? keys,
  carriedOver: carriedOver,
);

const String _today = '2026-08-20';

void main() {
  group('applyTaskKeyChange', () {
    test('체크는 그 키만 더하고 다른 탭이 체크한 키는 남긴다', () {
      // 다른 탭이 report-a 를 체크해 저장했다. 이 탭은 그걸 모른 채 report-b 를
      // 체크한다.
      const DailyTaskSnapshot saved = DailyTaskSnapshot(
        total: 2,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{'report-b'},
        completedKeys: <String>{'report-a'},
      );
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: saved,
        change: _change(
          'report-b',
          TaskKeyAction.check,
          keys: <String>{'report-a', 'report-b'},
        ),
      );
      expect(next.completedKeys, <String>{'report-a', 'report-b'});
      expect(next.pendingKeys, isEmpty);
      expect(next.completed, 2);
      expect(next.total, 2);
    });

    test('해제는 그 키만 뺀다', () {
      const DailyTaskSnapshot saved = DailyTaskSnapshot(
        total: 2,
        completedToday: 2,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
        completedKeys: <String>{'report-a', 'report-b'},
      );
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: saved,
        change: _change(
          'report-a',
          TaskKeyAction.uncheck,
          keys: <String>{'report-a', 'report-b'},
        ),
      );
      expect(next.completedKeys, <String>{'report-b'});
      expect(next.pendingKeys, <String>{'report-a'});
    });

    test('지운 키는 다른 탭의 체크로 되살아나지 않는다', () {
      const DailyTaskSnapshot saved = DailyTaskSnapshot(
        total: 1,
        completedToday: 0,
        completedCarriedOver: 0,
        pendingKeys: <String>{'report-b'},
        dismissedKeys: <String>{'report-a'},
        completedKeys: <String>{},
      );
      // 옛 화면은 아직 report-a 를 보여 준다.
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: saved,
        change: _change(
          'report-b',
          TaskKeyAction.check,
          keys: <String>{'report-a', 'report-b'},
        ),
      );
      expect(next.dismissedKeys, <String>{'report-a'});
      expect(next.pendingKeys, isNot(contains('report-a')));
      expect(next.completedKeys, <String>{'report-b'});
      expect(next.total, 1);
    });

    test('지우면 체크도 함께 빠진다', () {
      const DailyTaskSnapshot saved = DailyTaskSnapshot(
        total: 1,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
        completedKeys: <String>{'report-a'},
      );
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: saved,
        change: _change(
          'report-a',
          TaskKeyAction.dismiss,
          keys: <String>{'report-a'},
        ),
      );
      expect(next.completedKeys, isEmpty);
      expect(next.dismissedKeys, <String>{'report-a'});
      expect(next.total, 0);
    });

    test('화면이 모르는 저장 키는 그대로, 화면에서 사라진 키는 뺀다', () {
      const DailyTaskSnapshot saved = DailyTaskSnapshot(
        total: 3,
        completedToday: 2,
        completedCarriedOver: 0,
        pendingKeys: <String>{'consultation-late'},
        completedKeys: <String>{'consultation-new', 'consultation-done'},
      );
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: saved,
        change: _change(
          'report-a',
          TaskKeyAction.check,
          keys: <String>{'report-a'},
          // 처리한 상담은 화면에 나타났다가 사라졌다.
          seen: <String>{'report-a', 'consultation-done'},
        ),
      );
      expect(next.completedKeys, <String>{'consultation-new', 'report-a'});
      expect(next.pendingKeys, <String>{'consultation-late'});
      expect(next.total, 3);
    });

    test('완료 수는 전체 수를 넘지 않는다', () {
      const DailyTaskSnapshot saved = DailyTaskSnapshot(
        total: 3,
        completedToday: 3,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
        completedKeys: <String>{'a', 'b', 'c'},
      );
      for (final TaskKeyAction action in TaskKeyAction.values) {
        final DailyTaskSnapshot next = applyTaskKeyChange(
          saved: saved,
          change: _change(
            'a',
            action,
            keys: <String>{'a'},
            seen: <String>{'a', 'b', 'c'},
          ),
        );
        expect(
          next.completed,
          lessThanOrEqualTo(next.total),
          reason: '$action',
        );
      }
    });

    test('이월분 완료는 따로 센다', () {
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: null,
        change: _change(
          'consultation-2',
          TaskKeyAction.check,
          keys: <String>{'consultation-2', 'report-a'},
          carriedOver: <String>{'consultation-2'},
        ),
      );
      expect(next.completedCarriedOver, 1);
      expect(next.completedToday, 0);
      expect(next.total, 2);
    });

    test('옛 기록(체크 키 없음)의 미완료와 지운 키는 잃지 않는다', () {
      const DailyTaskSnapshot legacy = DailyTaskSnapshot(
        total: 2,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{'consultation-2'},
        dismissedKeys: <String>{'program-z'},
      );
      final DailyTaskSnapshot next = applyTaskKeyChange(
        saved: legacy,
        change: _change(
          'report-a',
          TaskKeyAction.check,
          keys: <String>{'report-a'},
        ),
      );
      expect(next.completedKeys, <String>{'report-a'});
      expect(next.pendingKeys, <String>{'consultation-2'});
      expect(next.dismissedKeys, <String>{'program-z'});
    });
  });

  group('restoreTaskKey', () {
    test('실패한 키만 되돌리고 다른 키의 변경은 둔다', () {
      const DailyTaskSnapshot before = DailyTaskSnapshot(
        total: 2,
        completedToday: 0,
        completedCarriedOver: 0,
        pendingKeys: <String>{'a', 'b'},
        completedKeys: <String>{},
      );
      // a, b 를 연달아 체크했고 a 만 실패했다.
      const DailyTaskSnapshot current = DailyTaskSnapshot(
        total: 2,
        completedToday: 2,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
        completedKeys: <String>{'a', 'b'},
      );
      final DailyTaskSnapshot restored = restoreTaskKey(
        current: current,
        before: before,
        key: 'a',
      );
      expect(restored.completedKeys, <String>{'b'});
      expect(restored.pendingKeys, <String>{'a'});
      expect(restored.total, 2);
    });

    test('실패한 삭제는 지운 표시를 걷고 체크를 되살린다', () {
      const DailyTaskSnapshot before = DailyTaskSnapshot(
        total: 1,
        completedToday: 1,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
        completedKeys: <String>{'a'},
      );
      const DailyTaskSnapshot current = DailyTaskSnapshot(
        total: 0,
        completedToday: 0,
        completedCarriedOver: 0,
        pendingKeys: <String>{},
        dismissedKeys: <String>{'a'},
        completedKeys: <String>{},
      );
      final DailyTaskSnapshot restored = restoreTaskKey(
        current: current,
        before: before,
        key: 'a',
      );
      expect(restored.dismissedKeys, isEmpty);
      expect(restored.completedKeys, <String>{'a'});
    });
  });

  group('LocalDailyTaskProgressStore.applyKey', () {
    test('저장된 그날 기록에 얹어 저장하고 다시 읽힌다', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final LocalDailyTaskProgressStore store = LocalDailyTaskProgressStore(
        prefs,
      );
      await store.applyKey(
        _today,
        _change('a', TaskKeyAction.check, keys: <String>{'a', 'b'}),
      );
      final DailyTaskSnapshot second = await store.applyKey(
        _today,
        _change('b', TaskKeyAction.check, keys: <String>{'a', 'b'}),
      );
      expect(second.completedKeys, <String>{'a', 'b'});

      final DailyTaskHistory history = await store.load();
      expect(history.read(_today)?.completedKeys, <String>{'a', 'b'});
    });
  });

  group('DioDailyTaskProgressStore.applyKey', () {
    late _MockDio dio;

    setUp(() => dio = _MockDio());

    test('키 하나와 화면의 키 목록만 보내고 서버의 그날 상태를 돌려준다', () async {
      when(
        () => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(),
          statusCode: 200,
          data: <String, dynamic>{
            'date': _today,
            'total': 2,
            'completed_today': 2,
            'completed_carried_over': 0,
            'pending_keys': <String>[],
            'dismissed_keys': <String>[],
            // 다른 기기의 체크(a)가 함께 온다.
            'completed_keys': <String>['a', 'b'],
          },
        ),
      );

      final DailyTaskSnapshot result = await DioDailyTaskProgressStore(dio)
          .applyKey(
            _today,
            _change(
              'b',
              TaskKeyAction.check,
              keys: <String>{'b', 'a'},
              carriedOver: <String>{'a'},
            ),
          );

      final List<dynamic> captured = verify(
        () => dio.post<Map<String, dynamic>>(
          captureAny(),
          data: captureAny(named: 'data'),
        ),
      ).captured;
      expect(captured[0], '/trainer/dashboard/task-progress/$_today/keys');
      expect(captured[1], <String, Object?>{
        'key': 'b',
        'action': 'check',
        'keys': <String>['a', 'b'],
        'seen': <String>['a', 'b'],
      });
      expect(result.completedKeys, <String>{'a', 'b'});
    });

    test('실패하면 AppError 다', () async {
      when(
        () => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(),
            statusCode: 500,
          ),
        ),
      );
      await expectLater(
        DioDailyTaskProgressStore(dio).applyKey(
          _today,
          _change('a', TaskKeyAction.check, keys: <String>{'a'}),
        ),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('DailyTaskHistoryController.apply', () {
    late _FakeStore store;
    late ProviderContainer container;

    setUp(() {
      store = _FakeStore();
      container = ProviderContainer(
        overrides: <Override>[
          dailyTaskProgressStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> ready() async {
      container.listen(dailyTaskHistoryProvider, (_, _) {});
      await container.read(dailyTaskHistoryProvider.future);
    }

    DailyTaskSnapshot? today() =>
        container.read(dailyTaskHistoryProvider).valueOrNull?.read(_today);

    test('먼저 반영하고, 응답이 오면 서버 상태(다른 기기 변경 포함)로 바꾼다', () async {
      await ready();
      final Completer<DailyTaskSnapshot> response =
          Completer<DailyTaskSnapshot>();
      store.answers.add(() => response.future);

      final Future<void> applying = container
          .read(dailyTaskHistoryProvider.notifier)
          .apply(
            _today,
            _change('b', TaskKeyAction.check, keys: <String>{'a', 'b'}),
          );
      await Future<void>.delayed(Duration.zero);
      expect(today()?.completedKeys, <String>{'b'});
      expect(
        container.read(dailyTaskHistoryProvider.notifier).hasPendingChanges(),
        isTrue,
      );

      response.complete(
        const DailyTaskSnapshot(
          total: 2,
          completedToday: 2,
          completedCarriedOver: 0,
          pendingKeys: <String>{},
          completedKeys: <String>{'a', 'b'},
        ),
      );
      await applying;
      expect(today()?.completedKeys, <String>{'a', 'b'});
      expect(
        container.read(dailyTaskHistoryProvider.notifier).hasPendingChanges(),
        isFalse,
      );
    });

    test('실패하면 그 키만 되돌리고 오류를 알린다', () async {
      await ready();
      store.answers.add(
        () => Future<DailyTaskSnapshot>.error(const NetworkError()),
      );

      await expectLater(
        container
            .read(dailyTaskHistoryProvider.notifier)
            .apply(
              _today,
              _change('a', TaskKeyAction.check, keys: <String>{'a'}),
            ),
        throwsA(isA<AppError>()),
      );
      expect(today()?.completedKeys ?? const <String>{}, isEmpty);
    });

    test('요청은 순서대로 보낸다', () async {
      await ready();
      final Completer<DailyTaskSnapshot> first = Completer<DailyTaskSnapshot>();
      store.answers.add(() => first.future);
      final notifier = container.read(dailyTaskHistoryProvider.notifier);
      final Future<void> a = notifier.apply(
        _today,
        _change('a', TaskKeyAction.check, keys: <String>{'a'}),
      );
      final Future<void> b = notifier.apply(
        _today,
        _change('a', TaskKeyAction.uncheck, keys: <String>{'a'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.sent.map((TaskKeyChange c) => c.action), <TaskKeyAction>[
        TaskKeyAction.check,
      ]);

      first.complete(
        applyTaskKeyChange(
          saved: null,
          change: _change('a', TaskKeyAction.check, keys: <String>{'a'}),
        ),
      );
      await Future.wait(<Future<void>>[a, b]);
      expect(store.sent.map((TaskKeyChange c) => c.action), <TaskKeyAction>[
        TaskKeyAction.check,
        TaskKeyAction.uncheck,
      ]);
    });
  });
}

/// 응답을 붙잡거나 실패시킬 수 있는 저장소. [answers] 를 앞에서부터 하나씩 쓰고,
/// 비어 있으면 같은 규칙으로 바로 답한다.
class _FakeStore implements DailyTaskProgressStore {
  final List<TaskKeyChange> sent = <TaskKeyChange>[];
  final List<Future<DailyTaskSnapshot> Function()> answers =
      <Future<DailyTaskSnapshot> Function()>[];
  DailyTaskHistory history = const DailyTaskHistory();

  @override
  Future<DailyTaskHistory> load() async => history;

  @override
  Future<void> save(String date, DailyTaskSnapshot snapshot) async {}

  @override
  Future<DailyTaskSnapshot> applyKey(String date, TaskKeyChange change) {
    sent.add(change);
    if (answers.isNotEmpty) return answers.removeAt(0)();
    return Future<DailyTaskSnapshot>.value(
      applyTaskKeyChange(saved: history.read(date), change: change),
    );
  }
}
