import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/notification/data/repositories/notification_settings_repository.dart';

/// 저장 요청마다 완료 시점을 테스트가 정하는 대역.
class _ControlledRepository implements NotificationSettingsRepository {
  _ControlledRepository({this.failFetch = false});

  bool failFetch;
  int fetchCalls = 0;
  final Map<String, bool> stored = defaultNotificationSettings();
  final List<Completer<void>> pending = <Completer<void>>[];

  @override
  Future<Map<String, bool>> fetch() async {
    fetchCalls++;
    if (failFetch) throw StateError('fetch failed');
    return Map<String, bool>.from(stored);
  }

  @override
  Future<void> setValue(String key, bool value) {
    final Completer<void> done = Completer<void>();
    pending.add(done);
    return done.future.then((_) => stored[key] = value);
  }
}

ProviderContainer _container(NotificationSettingsRepository repo) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      notificationSettingsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

bool _value(ProviderContainer c, String key) =>
    c.read(notificationSettingsProvider).requireValue.valueOf(key);

void main() {
  test('저장하는 동안에도 바꾼 값이 바로 보인다', () async {
    final repo = _ControlledRepository();
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);

    final Future<bool> saving = c
        .read(notificationSettingsProvider.notifier)
        .setValue('notif_trainer_message', false);

    expect(_value(c, 'notif_trainer_message'), isFalse);
    repo.pending.single.complete();
    expect(await saving, isTrue);
  });

  test('저장에 성공하면 캐시가 그 값을 유지한다', () async {
    // 화면을 다시 열어도(같은 provider 를 다시 읽어도) 마지막 저장값이다.
    final repo = _ControlledRepository();
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);

    final Future<bool> saving = c
        .read(notificationSettingsProvider.notifier)
        .setValue('notif_weekly_report', true);
    repo.pending.single.complete();
    await saving;

    final NotificationSettingsState again = await c.read(
      notificationSettingsProvider.future,
    );
    expect(again.valueOf('notif_weekly_report'), isTrue);
    // 다시 읽는다고 서버를 또 부르지 않는다 — 저장 결과가 곧 최신값이다.
    expect(repo.fetchCalls, 1);
  });

  test('저장에 실패하면 직전 값으로 돌아가고 false 를 돌려준다', () async {
    final repo = _ControlledRepository();
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);
    final notifier = c.read(notificationSettingsProvider.notifier);

    // 1) 성공: 꺼짐 → 켜짐.
    final Future<bool> first = notifier.setValue('notif_weekly_report', true);
    repo.pending[0].complete();
    expect(await first, isTrue);
    // 2) 실패: 켜짐 → 꺼짐. 돌아갈 곳은 최초값(꺼짐)이 아니라 직전 값(켜짐).
    final Future<bool> second = notifier.setValue('notif_weekly_report', false);
    repo.pending[1].completeError(StateError('write failed'));

    expect(await second, isFalse);
    expect(_value(c, 'notif_weekly_report'), isTrue);
  });

  test('연속으로 바꾸면 늦게 온 옛 실패가 최신 값을 되돌리지 않는다', () async {
    final repo = _ControlledRepository();
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);
    final notifier = c.read(notificationSettingsProvider.notifier);

    final Future<bool> first = notifier.setValue(
      'notif_trainer_message',
      false,
    );
    final Future<bool> second = notifier.setValue(
      'notif_trainer_message',
      true,
    );
    repo.pending[1].complete();
    expect(await second, isTrue);
    repo.pending[0].completeError(StateError('write failed'));

    // 옛 요청의 실패는 알리지도, 되돌리지도 않는다.
    expect(await first, isTrue);
    expect(_value(c, 'notif_trainer_message'), isTrue);
  });

  test('한 항목의 실패가 다른 항목 값을 건드리지 않는다', () async {
    final repo = _ControlledRepository();
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);
    final notifier = c.read(notificationSettingsProvider.notifier);

    final Future<bool> a = notifier.setValue('notif_trainer_message', false);
    final Future<bool> b = notifier.setValue('notif_weekly_report', true);
    repo.pending[1].complete();
    repo.pending[0].completeError(StateError('write failed'));
    await Future.wait(<Future<bool>>[a, b]);

    expect(_value(c, 'notif_trainer_message'), isTrue);
    expect(_value(c, 'notif_weekly_report'), isTrue);
  });

  test('조회가 실패하면 기본값과 실패 표시를 돌려준다', () async {
    final repo = _ControlledRepository(failFetch: true);
    final c = _container(repo);

    final NotificationSettingsState state = await c.read(
      notificationSettingsProvider.future,
    );

    expect(state.loadFailed, isTrue);
    expect(state.values, defaultNotificationSettings());
  });

  test('다시 시도해 성공하면 실패 표시가 사라진다', () async {
    final repo = _ControlledRepository(failFetch: true);
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);

    repo
      ..failFetch = false
      ..stored['notif_trainer_message'] = false;
    c.invalidate(notificationSettingsProvider);
    final NotificationSettingsState state = await c.read(
      notificationSettingsProvider.future,
    );

    expect(state.loadFailed, isFalse);
    expect(state.valueOf('notif_trainer_message'), isFalse);
  });

  test('조회 실패 중에 바꾼 값도 실패 표시를 유지한 채 반영된다', () async {
    final repo = _ControlledRepository(failFetch: true);
    final c = _container(repo);
    await c.read(notificationSettingsProvider.future);

    final Future<bool> saving = c
        .read(notificationSettingsProvider.notifier)
        .setValue('notif_weekly_report', true);
    repo.pending.single.complete();
    await saving;

    final NotificationSettingsState state = c
        .read(notificationSettingsProvider)
        .requireValue;
    expect(state.valueOf('notif_weekly_report'), isTrue);
    expect(state.loadFailed, isTrue);
  });
}
