import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/coaching_draft_autosaver.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';

/// 부른 순서를 남기는 메모리 저장소.
class _RecordingRepository implements TrainerProgramDraftRepository {
  final Map<String, Map<String, Object?>> rows =
      <String, Map<String, Object?>>{};
  final List<String> calls = <String>[];
  int _seq = 0;

  /// 다음 `create` 를 이 완료자가 끝낼 때까지 붙잡는다.
  Completer<void>? holdCreate;

  /// 다음 `update` 가 던질 오류.
  Object? failUpdate;

  /// `read` 가 던진다.
  bool failRead = false;

  TrainerProgramDraft _draft(String id) {
    final Map<String, Object?> row = rows[id]!;
    return TrainerProgramDraft.fromJson(<String, Object?>{
      ...row,
      'id': id,
      'updated_at': '2026-10-02T09:00:00Z',
    });
  }

  @override
  Future<List<TrainerProgramDraftSummary>> list({String? memberId}) async {
    calls.add('list');
    return <TrainerProgramDraftSummary>[
      for (final MapEntry<String, Map<String, Object?>> e in rows.entries)
        if (memberId == null || e.value['member_id'] == memberId)
          TrainerProgramDraftSummary(
            id: e.key,
            name: e.value['name'] as String? ?? '',
            goal: '',
            period: '',
            sessionCount: 0,
            exerciseCount: 0,
            updatedAt: DateTime(2026, 10, 2),
            memberId: e.value['member_id'] as String?,
          ),
    ];
  }

  @override
  Future<TrainerProgramDraft> read(String id) async {
    calls.add('read $id');
    if (failRead) throw const NetworkError();
    if (!rows.containsKey(id)) throw StateError('missing $id');
    return _draft(id);
  }

  @override
  Future<TrainerProgramDraft> create(Map<String, Object?> payload) async {
    final Completer<void>? hold = holdCreate;
    holdCreate = null;
    if (hold != null) await hold.future;
    final String id = 'pgm-${++_seq}';
    calls.add('create $id ${payload['name']}');
    rows[id] = Map<String, Object?>.of(payload);
    return _draft(id);
  }

  @override
  Future<TrainerProgramDraft> update(
    String id,
    Map<String, Object?> payload,
  ) async {
    calls.add('update $id ${payload['name']}');
    final Object? error = failUpdate;
    failUpdate = null;
    if (error != null) throw error;
    if (!rows.containsKey(id)) throw const NotFoundError();
    rows[id] = <String, Object?>{
      ...rows[id]!,
      ...payload,
      'member_id': rows[id]!['member_id'],
    };
    return _draft(id);
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete $id');
    rows.remove(id);
  }
}

Map<String, Object?> _payload(String name) => <String, Object?>{
  'name': name,
  'goal': '',
  'period': '',
  'memo': '',
  'sessions': const <Object?>[],
  'workspace': <String, Object?>{'version': 1},
};

/// 보관기의 기본 대기 시간 그대로 돈다.
const Duration _delay = kCoachingAutosaveDelay;

/// 코칭 화면 자동 보관기 (#2873).
///
/// 타이머는 위젯 테스트의 가짜 시계로 돌린다 — `pump(시간)` 만큼만 흐른다.
void main() {
  late _RecordingRepository repo;
  late CoachingDraftAutosaver saver;

  void setUpSaver() {
    repo = _RecordingRepository();
    saver = CoachingDraftAutosaver(repo);
    addTearDown(saver.dispose);
  }

  testWidgets('입력이 멈추고 기다린 뒤에 한 번만 보관한다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(const Duration(seconds: 2));
    saver.schedule('m1', _payload('둘'));
    await tester.pump(const Duration(seconds: 2));
    // 두 번째 입력이 타이머를 다시 걸었다 — 아직 보관하지 않았다.
    expect(repo.calls, isEmpty);
    expect(saver.hasPending('m1'), isTrue);

    await tester.pump(const Duration(seconds: 1));

    expect(repo.calls, <String>['create pgm-1 둘']);
    expect(repo.rows['pgm-1']!['member_id'], 'm1');
    expect(saver.hasPending('m1'), isFalse);
  });

  testWidgets('처음에는 만들고 그 뒤로는 같은 초안을 덮어쓴다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    saver.schedule('m1', _payload('둘'));
    await tester.pump(_delay);

    expect(repo.calls, <String>['create pgm-1 하나', 'update pgm-1 둘']);
    expect(repo.rows, hasLength(1));
  });

  testWidgets('마지막으로 보관한 것과 같으면 다시 보관하지 않는다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    // 다시 그릴 때마다 같은 내용이 들어온다.
    saver.schedule('m1', _payload('하나'));
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);

    expect(repo.calls, <String>['create pgm-1 하나']);
    expect(saver.hasPending('m1'), isFalse);
  });

  testWidgets('회원마다 따로 기다리고 따로 보관한다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('회원1'));
    await tester.pump(const Duration(seconds: 2));
    saver.schedule('m2', _payload('회원2'));
    await tester.pump(const Duration(seconds: 1));

    expect(repo.calls, <String>['create pgm-1 회원1']);
    await tester.pump(const Duration(seconds: 2));
    expect(repo.calls, <String>['create pgm-1 회원1', 'create pgm-2 회원2']);
    expect(repo.rows['pgm-2']!['member_id'], 'm2');
  });

  testWidgets('flush 는 기다리지 않고 지금 보관한다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await saver.flush('m1');

    expect(repo.calls, <String>['create pgm-1 하나']);
    await tester.pump(_delay);
    expect(repo.calls, hasLength(1));
  });

  testWidgets('discard 는 기다리던 보관을 거두고 그 회원 초안을 모두 지운다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    // 다른 탭이 따로 만든 초안도 함께 지운다.
    await repo.create(<String, Object?>{
      ..._payload('다른 탭'),
      'member_id': 'm1',
    });
    await repo.create(<String, Object?>{
      ..._payload('남의 회원'),
      'member_id': 'm2',
    });
    saver.schedule('m1', _payload('기다리던 것'));

    await saver.discard('m1');
    await tester.pump(_delay);

    expect(saver.hasPending('m1'), isFalse);
    expect(repo.rows.keys, <String>['pgm-3']);
    expect(repo.calls.where((c) => c.startsWith('update')), isEmpty);
  });

  testWidgets('보관이 도는 중에 discard 가 오면 보관이 끝난 뒤 지운다', (tester) async {
    setUpSaver();
    final Completer<void> hold = Completer<void>();
    repo.holdCreate = hold;
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    // create 가 붙잡혀 있는 동안 버린다.
    final Future<void> discarding = saver.discard('m1');
    hold.complete();
    await discarding;

    // 순서가 뒤집혔으면 지운 뒤에 만든 초안이 남는다.
    expect(repo.rows, isEmpty);
    expect(repo.calls.first, 'create pgm-1 하나');
    expect(repo.calls.last, 'delete pgm-1');
  });

  testWidgets('보관이 도는 중에 버렸으면 같은 내용을 다시 보관한다 (#3101)', (tester) async {
    setUpSaver();
    final Completer<void> hold = Completer<void>();
    repo.holdCreate = hold;
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    final Future<void> discarding = saver.discard('m1');
    hold.complete();
    await discarding;
    expect(repo.rows, isEmpty);

    // 끝난 보관이 `보관했다` 고 적어 두면 같은 내용은 건너뛴다 — 서버에는 없다.
    saver.schedule('m1', _payload('하나'));
    expect(saver.hasPending('m1'), isTrue);
    await tester.pump(_delay);

    expect(repo.calls.last, 'create pgm-2 하나');
    expect(repo.rows.keys, <String>['pgm-2']);
  });

  testWidgets('버린 뒤 끝난 덮어쓰기는 지운 초안 id 를 남기지 않는다 (#3101)', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    expect(repo.calls.last, 'create pgm-1 하나');

    // 덮어쓰기가 줄에 올라간 뒤 버린다.
    saver.schedule('m1', _payload('둘'));
    final Future<void> flushing = saver.flush('m1');
    final Future<void> discarding = saver.discard('m1');
    await flushing;
    await discarding;
    expect(repo.rows, isEmpty);

    // 지운 pgm-1 을 덮어쓰지 않고 새로 만든다.
    saver.schedule('m1', _payload('둘'));
    await tester.pump(_delay);
    expect(repo.calls.last, 'create pgm-2 둘');
  });

  testWidgets('지운 다음 다시 쓰면 새 초안을 만든다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    await saver.discard('m1');

    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);

    expect(repo.calls.last, 'create pgm-2 하나');
  });

  testWidgets('load 는 그 회원 초안을 읽고, 이어서 쓰면 그 초안을 덮어쓴다', (tester) async {
    setUpSaver();
    await repo.create(<String, Object?>{..._payload('보관본'), 'member_id': 'm1'});
    repo.calls.clear();

    final TrainerProgramDraft? loaded = await saver.load('m1');
    expect(loaded!.id, 'pgm-1');
    expect(loaded.memberId, 'm1');

    saver.schedule('m1', _payload('이어서'));
    await tester.pump(_delay);
    expect(repo.calls.last, 'update pgm-1 이어서');
  });

  testWidgets('load 는 없거나 읽지 못하면 null 이다', (tester) async {
    setUpSaver();
    expect(await saver.load('m1'), isNull);

    await repo.create(<String, Object?>{..._payload('보관본'), 'member_id': 'm2'});
    repo.failRead = true;
    expect(await saver.load('m2'), isNull);
  });

  testWidgets('다른 곳에서 지워졌으면 다음 보관은 새로 만든다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    repo.rows.clear();

    saver.schedule('m1', _payload('둘'));
    await tester.pump(_delay);
    expect(repo.calls.last, 'update pgm-1 둘');

    saver.schedule('m1', _payload('셋'));
    await tester.pump(_delay);
    expect(repo.calls.last, 'create pgm-2 셋');
  });

  testWidgets('네트워크 실패는 조용히 넘기고 같은 초안을 다시 덮어쓴다', (tester) async {
    setUpSaver();
    saver.schedule('m1', _payload('하나'));
    await tester.pump(_delay);
    repo.failUpdate = const NetworkError();

    saver.schedule('m1', _payload('둘'));
    await tester.pump(_delay);
    expect(repo.rows['pgm-1']!['name'], '하나');

    // 실패한 것은 보관한 것으로 치지 않는다 — 같은 내용이어도 다시 보관한다.
    saver.schedule('m1', _payload('둘'));
    await tester.pump(_delay);
    expect(repo.calls.last, 'update pgm-1 둘');
    expect(repo.rows['pgm-1']!['name'], '둘');
    expect(repo.rows, hasLength(1));
  });

  testWidgets('dispose 는 기다리던 보관을 거두고 더 받지 않는다', (tester) async {
    repo = _RecordingRepository();
    saver = CoachingDraftAutosaver(repo);
    saver.schedule('m1', _payload('하나'));

    saver.dispose();
    await tester.pump(_delay);
    // 로그아웃·계정 전환 뒤 앞 계정의 작성 내용을 저장하지 않는다.
    expect(repo.calls, isEmpty);
    expect(saver.hasPending('m1'), isFalse);

    saver.schedule('m1', _payload('둘'));
    await tester.pump(_delay);
    expect(repo.calls, isEmpty);
  });
}
