/// 회원별 지난 리포트 — provider 층. (#2394)
///
/// 이 파일이 지키는 것:
///  * [memberReportHistoryProvider] 는 첫 쪽을 읽고, `더 보기`([loadMore])로
///    다음 쪽을 뒤에 붙인다 — 같은 주는 두 번 서지 않는다.
///  * `더 보기` 가 실패해도 이미 읽은 줄은 남고 실패만 알린다.
///  * 더 없거나 이미 불러오는 중이면 `더 보기` 는 저장소를 다시 묻지 않는다.
///  * [memberReportHistoryViewProvider] 는 이번 세션에 보낸 것을 얹는다 — 같은
///    주는 세션 기록이 이기고, 다른 회원 것은 끼우지 않는다.
///  * 첫 쪽 실패는 오류로 넘긴다(빈 이력으로 삼키지 않는다).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/data/member_report_history_provider.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';

import '../../helpers/fixed_clock.dart';

MemberReportHistoryItem _item(DateTime week, {String preview = '서버 첫 줄'}) =>
    MemberReportHistoryItem(
      weekStart: week,
      sentAt: DateTime(week.year, week.month, week.day + 6, 20),
      read: true,
      feedbackPreview: preview,
    );

/// 쪽을 정해 둔 저장소. 누가 어떤 `before` 로 물었는지 적는다.
class _FakeRepository implements ReportRepository {
  _FakeRepository(this.pages);

  /// `before` 별 응답. null 열쇠가 첫 쪽이다.
  final Map<DateTime?, MemberReportHistoryPage> pages;

  /// 이 `before` 로 물으면 실패한다.
  final Set<DateTime?> failOn = <DateTime?>{};

  /// 이 값이 있으면 응답을 여기서 붙잡아 둔다.
  Completer<void>? gate;

  final List<(String, DateTime?)> asked = <(String, DateTime?)>[];

  @override
  Future<MemberReportHistoryPage> memberReportHistory({
    required String clientId,
    DateTime? before,
    int limit = memberReportHistoryPageSize,
  }) async {
    asked.add((clientId, before));
    if (gate case final Completer<void> g) await g.future;
    if (failOn.contains(before)) throw StateError('history failed');
    return pages[before] ?? const MemberReportHistoryPage.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeRepository repo) {
  final ProviderContainer container = ProviderContainer(
    overrides: [reportRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final DateTime w1 = DateTime(2026, 8, 17);
  final DateTime w2 = DateTime(2026, 8, 10);
  final DateTime w3 = DateTime(2026, 8, 3);
  final DateTime w4 = DateTime(2026, 7, 27);

  setUp(() => useFixedKstDate(DateTime(2026, 8, 20, 13)));

  Future<MemberReportHistoryState> firstPage(
    ProviderContainer container,
    String id,
  ) {
    // autoDispose 라 읽는 동안 붙잡아 둔다.
    container.listen(memberReportHistoryProvider(id), (_, _) {});
    return container.read(memberReportHistoryProvider(id).future);
  }

  group('memberReportHistoryProvider', () {
    test('첫 쪽을 그 회원으로, before 없이 읽는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1), _item(w2)],
          nextBefore: w2,
        ),
      });
      final ProviderContainer container = _container(repo);

      final MemberReportHistoryState state = await firstPage(container, 'c1');
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2]);
      expect(state.hasMore, isTrue);
      expect(state.oldestLoaded, w2);
      expect(repo.asked, <(String, DateTime?)>[('c1', null)]);
    });

    test('더 보기는 다음 쪽 커서로 물어 뒤에 붙인다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1), _item(w2)],
          nextBefore: w2,
        ),
        w2: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w3), _item(w4)],
        ),
      });
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');

      await container
          .read(memberReportHistoryProvider('c1').notifier)
          .loadMore();

      final MemberReportHistoryState state = container
          .read(memberReportHistoryProvider('c1'))
          .requireValue;
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2, w3, w4]);
      expect(state.hasMore, isFalse);
      expect(state.loadingMore, isFalse);
      expect(repo.asked.last, ('c1', w2));
    });

    test('다음 쪽에 이미 있는 주가 다시 와도 한 번만 선다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1), _item(w2)],
          nextBefore: w2,
        ),
        w2: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[
            _item(w2, preview: '겹침'),
            _item(w3),
          ],
        ),
      });
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');

      await container
          .read(memberReportHistoryProvider('c1').notifier)
          .loadMore();

      final MemberReportHistoryState state = container
          .read(memberReportHistoryProvider('c1'))
          .requireValue;
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2, w3]);
      expect(state.items[1].feedbackPreview, '서버 첫 줄');
    });

    test('더 보기가 실패해도 읽은 줄은 남고 실패만 알린다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
          nextBefore: w1,
        ),
      })..failOn.add(w1);
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');

      await container
          .read(memberReportHistoryProvider('c1').notifier)
          .loadMore();

      final AsyncValue<MemberReportHistoryState> value = container.read(
        memberReportHistoryProvider('c1'),
      );
      expect(value.hasError, isFalse);
      final MemberReportHistoryState state = value.requireValue;
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1]);
      expect(state.loadMoreFailed, isTrue);
      expect(state.loadingMore, isFalse);
      // 커서는 남아 다시 누르면 같은 쪽을 묻는다.
      expect(state.nextBefore, w1);
    });

    test('실패 뒤 다시 누르면 실패 표시를 지우고 다시 묻는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
          nextBefore: w1,
        ),
        w1: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w2)],
        ),
      })..failOn.add(w1);
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');
      final MemberReportHistoryController notifier = container.read(
        memberReportHistoryProvider('c1').notifier,
      );
      await notifier.loadMore();

      repo.failOn.clear();
      await notifier.loadMore();

      final MemberReportHistoryState state = container
          .read(memberReportHistoryProvider('c1'))
          .requireValue;
      expect(state.loadMoreFailed, isFalse);
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2]);
    });

    test('더 없으면 더 보기는 저장소를 묻지 않는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
        ),
      });
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');

      await container
          .read(memberReportHistoryProvider('c1').notifier)
          .loadMore();

      expect(repo.asked, hasLength(1));
    });

    test('불러오는 중에 다시 눌러도 같은 쪽을 두 번 묻지 않는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
          nextBefore: w1,
        ),
        w1: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w2)],
        ),
      });
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');
      final MemberReportHistoryController notifier = container.read(
        memberReportHistoryProvider('c1').notifier,
      );

      repo.gate = Completer<void>();
      final Future<void> first = notifier.loadMore();
      expect(
        container
            .read(memberReportHistoryProvider('c1'))
            .requireValue
            .loadingMore,
        isTrue,
      );
      await notifier.loadMore();
      repo.gate!.complete();
      await first;

      expect(repo.asked.where((a) => a.$2 == w1), hasLength(1));
      expect(
        container
            .read(memberReportHistoryProvider('c1'))
            .requireValue
            .items
            .map((i) => i.weekStart),
        <DateTime>[w1, w2],
      );
    });

    test('첫 쪽 실패는 빈 이력이 아니라 오류다', () async {
      final _FakeRepository repo = _FakeRepository(
        <DateTime?, MemberReportHistoryPage>{},
      )..failOn.add(null);
      final ProviderContainer container = _container(repo);

      await expectLater(firstPage(container, 'c1'), throwsA(isA<StateError>()));
      expect(
        container.read(memberReportHistoryProvider('c1')).hasError,
        isTrue,
      );
    });

    test('회원마다 따로 읽는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
        ),
      });
      final ProviderContainer container = _container(repo);
      await firstPage(container, 'c1');
      await firstPage(container, 'c2');

      expect(repo.asked.map((a) => a.$1), <String>['c1', 'c2']);
    });
  });

  group('memberReportHistoryViewProvider', () {
    Future<MemberReportHistoryState> view(
      ProviderContainer container,
      String id,
    ) async {
      container.listen(memberReportHistoryViewProvider(id), (_, _) {});
      await container.read(memberReportHistoryProvider(id).future);
      return container.read(memberReportHistoryViewProvider(id)).requireValue;
    }

    test('이번 세션에 보낸 주가 맨 위에 서고 같은 주는 세션 기록이 이긴다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[
            _item(w2, preview: '옛 글'),
            _item(w3),
          ],
        ),
      });
      final ProviderContainer container = _container(repo);
      container
          .read(reportSendLogProvider.notifier)
          .record(clientId: 'c1', weekStart: w1, message: '이번 주 글');
      container
          .read(reportSendLogProvider.notifier)
          .record(clientId: 'c1', weekStart: w2, message: '다시 쓴 글');

      final MemberReportHistoryState state = await view(container, 'c1');
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2, w3]);
      expect(state.items[0].feedbackPreview, '이번 주 글');
      expect(state.items[1].feedbackPreview, '다시 쓴 글');
      expect(state.items[1].read, isFalse);
    });

    test('다른 회원에게 보낸 것은 끼우지 않는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w2)],
        ),
      });
      final ProviderContainer container = _container(repo);
      container
          .read(reportSendLogProvider.notifier)
          .record(clientId: 'c2', weekStart: w1, message: '남의 글');

      final MemberReportHistoryState state = await view(container, 'c1');
      expect(state.items.map((i) => i.weekStart), <DateTime>[w2]);
    });

    test('보내면 열려 있는 화면에 곧바로 선다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w2)],
        ),
      });
      final ProviderContainer container = _container(repo);
      await view(container, 'c1');

      container
          .read(reportSendLogProvider.notifier)
          .record(clientId: 'c1', weekStart: w1, message: '방금 보냄');

      expect(
        container
            .read(memberReportHistoryViewProvider('c1'))
            .requireValue
            .items
            .first
            .feedbackPreview,
        '방금 보냄',
      );
    });

    test('아직 불러오지 않은 쪽의 주는 세션 기록이라도 얹지 않는다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1), _item(w2)],
          nextBefore: w2,
        ),
      });
      final ProviderContainer container = _container(repo);
      container
          .read(reportSendLogProvider.notifier)
          .record(clientId: 'c1', weekStart: w4, message: '옛 주');

      final MemberReportHistoryState state = await view(container, 'c1');
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2]);
    });

    test('마지막 쪽까지 읽었으면 더 오래된 세션 주도 선다', () async {
      final _FakeRepository repo = _FakeRepository({
        null: MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1), _item(w2)],
        ),
      });
      final ProviderContainer container = _container(repo);
      container
          .read(reportSendLogProvider.notifier)
          .record(clientId: 'c1', weekStart: w4, message: '옛 주');

      final MemberReportHistoryState state = await view(container, 'c1');
      expect(state.items.map((i) => i.weekStart), <DateTime>[w1, w2, w4]);
    });

    test('첫 쪽 실패는 그대로 오류로 넘긴다', () async {
      final _FakeRepository repo = _FakeRepository(
        <DateTime?, MemberReportHistoryPage>{},
      )..failOn.add(null);
      final ProviderContainer container = _container(repo);
      container.listen(memberReportHistoryViewProvider('c1'), (_, _) {});
      await expectLater(
        container.read(memberReportHistoryProvider('c1').future),
        throwsA(isA<StateError>()),
      );

      expect(
        container.read(memberReportHistoryViewProvider('c1')).hasError,
        isTrue,
      );
    });
  });
}
