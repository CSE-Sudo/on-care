/// 트레이너 채팅의 옛 쪽 받기와, 그 뒤 폴링이 주는 최신 쪽을 합치는 일. (#2640)
///
/// 옛 쪽을 받아 둔 채 새 메시지가 오면 폴링의 최신 쪽이 앞으로 밀린다. 받아 둔
/// 쪽이 그때의 최신 쪽까지 함께 들고 있지 않으면 경계 메시지가 빠진다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/member_coach/domain/coach_chat_thread.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

import '../../helpers/fake_member_coach_repository.dart';

List<String> _ids(Iterable<CoachMessage> messages) => <String>[
  for (final CoachMessage m in messages) m.id,
];

List<CoachMessage> _lines(int from, int to) => <CoachMessage>[
  for (int i = from; i < to; i++) chatLine(i),
];

/// 화면이 그리는 대화 — 받아 둔 것과 폴링의 최신 쪽을 합친 것.
List<CoachMessage> _shown(
  ProviderContainer container,
  List<CoachMessage> latest,
) =>
    mergeCoachThread(container.read(coachChatHistoryProvider).messages, latest);

/// 걸어 둔 비동기 일을 흘려보낸다.
Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<ProviderContainer> _container(
  FakeMemberCoachRepository repository,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  // 화면처럼 둘 다 듣고 있게 한다 — autoDispose 라 듣는 이가 없으면 사라진다.
  container
    ..listen(coachChatProvider, (_, _) {})
    ..listen(coachChatHistoryProvider, (_, _) {});
  await container.read(coachChatProvider.future);
  return container;
}

void main() {
  test('옛 쪽을 받기 전에는 받아 둔 것이 없다 — 최신 쪽만으로 온전하다', () async {
    final ProviderContainer container = await _container(
      FakeMemberCoachRepository(chat: _lines(0, 120)),
    );

    container
        .read(coachChatHistoryProvider.notifier)
        .absorbLatest(_lines(70, 120));

    expect(container.read(coachChatHistoryProvider).messages, isEmpty);
  });

  test('옛 쪽을 받으면 그 앞 한 쪽이 붙는다', () async {
    final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
      chat: _lines(0, 120),
    );
    final ProviderContainer container = await _container(repository);
    final List<CoachMessage> latest = container.read(coachChatProvider).value!;

    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(latest.first);

    expect(repository.chatCursors.last?.id, latest.first.id);
    expect(_ids(_shown(container, latest)), _ids(_lines(20, 120)));
    expect(container.read(coachChatHistoryProvider).exhausted, isFalse);
  });

  test('한 쪽이 덜 차면 더 받을 것이 없다', () async {
    final ProviderContainer container = await _container(
      FakeMemberCoachRepository(chat: _lines(0, 70)),
    );
    final List<CoachMessage> latest = container.read(coachChatProvider).value!;

    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(latest.first);

    expect(container.read(coachChatHistoryProvider).exhausted, isTrue);
    expect(_ids(_shown(container, latest)), _ids(_lines(0, 70)));
  });

  test('옛 쪽을 받은 뒤 새 메시지가 와도 경계 메시지가 빠지지 않는다', () async {
    final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
      chat: _lines(0, 120),
    );
    final ProviderContainer container = await _container(repository);
    final List<CoachMessage> first = container.read(coachChatProvider).value!;
    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(first.first);

    // 새 메시지 하나 — 폴링의 최신 쪽이 m[71..120] 으로 밀린다.
    repository.chat.add(chatLine(120));
    final List<CoachMessage> next = pageCoachChat(repository.chat);
    expect(_ids(next), isNot(contains(chatLine(70).id)));
    container.read(coachChatHistoryProvider.notifier).absorbLatest(next);

    final List<CoachMessage> shown = _shown(container, next);
    expect(_ids(shown), _ids(_lines(20, 121)));
    expect(_ids(shown), contains(chatLine(70).id));
  });

  test('같은 메시지가 두 번 그려지지 않는다', () async {
    final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
      chat: _lines(0, 120),
    );
    final ProviderContainer container = await _container(repository);
    final List<CoachMessage> latest = container.read(coachChatProvider).value!;
    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(latest.first);

    container.read(coachChatHistoryProvider.notifier).absorbLatest(latest);
    final List<String> ids = _ids(_shown(container, latest));

    expect(ids.toSet().length, ids.length);
  });

  test('폴링 사이에 한 쪽이 넘게 와서 겹침이 끊기면 그 틈을 받아 메운다', () async {
    final FakeMemberCoachRepository repository = FakeMemberCoachRepository(
      chat: _lines(0, 120),
    );
    final ProviderContainer container = await _container(repository);
    final List<CoachMessage> first = container.read(coachChatProvider).value!;
    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(first.first);

    // 80건이 한꺼번에 왔다 — 새 최신 쪽 m[150..199] 는 받아 둔 m[20..119] 와
    // 하나도 겹치지 않는다. 그 사이 m[120..149] 가 비어 있다.
    repository.chat.addAll(_lines(120, 200));
    final List<CoachMessage> next = pageCoachChat(repository.chat);
    container.read(coachChatHistoryProvider.notifier).absorbLatest(next);
    await _settle();

    expect(repository.chatCursors.last?.id, chatLine(150).id);
    expect(_ids(_shown(container, next)), _ids(_lines(20, 200)));
  });

  test('틈을 메우다 실패해도 받아 둔 것은 그대로다', () async {
    final _FailingOlderRepository repository = _FailingOlderRepository(
      chat: _lines(0, 120),
    );
    final ProviderContainer container = await _container(repository);
    final List<CoachMessage> first = container.read(coachChatProvider).value!;
    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(first.first);
    final List<String> before = _ids(
      container.read(coachChatHistoryProvider).messages,
    );

    repository
      ..failOlder = true
      ..chat.addAll(_lines(120, 200));
    final List<CoachMessage> next = pageCoachChat(repository.chat);
    container.read(coachChatHistoryProvider.notifier).absorbLatest(next);
    await _settle();

    final List<String> kept = _ids(
      container.read(coachChatHistoryProvider).messages,
    );
    expect(kept, containsAll(before));
    expect(kept, containsAll(_ids(next)));
  });

  test('옛 쪽을 받다 실패해도 받아 둔 것을 버리지 않는다', () async {
    final _FailingOlderRepository repository = _FailingOlderRepository(
      chat: _lines(0, 120),
    )..failOlder = true;
    final ProviderContainer container = await _container(repository);
    final List<CoachMessage> latest = container.read(coachChatProvider).value!;

    await container
        .read(coachChatHistoryProvider.notifier)
        .loadOlder(latest.first);

    final CoachChatHistoryState state = container.read(
      coachChatHistoryProvider,
    );
    expect(state.loading, isFalse);
    expect(state.exhausted, isFalse);
  });
}

/// 커서가 있는 조회만 실패시킬 수 있는 대역.
class _FailingOlderRepository extends FakeMemberCoachRepository {
  _FailingOlderRepository({super.chat});

  bool failOlder = false;

  @override
  Future<List<CoachMessage>> fetchChat({CoachMessage? before}) {
    if (before != null && failOlder) {
      return Future<List<CoachMessage>>.error(StateError('older failed'));
    }
    return super.fetchChat(before: before);
  }
}
