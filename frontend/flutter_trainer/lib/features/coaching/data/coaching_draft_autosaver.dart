import 'dart:async';
import 'dart:convert';

import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';

/// 입력이 멈추고 자동 보관할 때까지 기다리는 시간(#2873).
///
/// 칸 하나를 고칠 때마다 저장하면 글자마다 요청이 나간다. 몇 초 기다렸다가 그
/// 사이의 변경을 한 번에 싣는다.
const Duration kCoachingAutosaveDelay = Duration(seconds: 3);

/// 코칭 화면의 작성 중 내용을 회원별로 자동 보관한다. (#2873)
///
/// - [schedule]: 새 내용을 받으면 회원별 타이머를 다시 건다(디바운스). 마지막
///   으로 보관한 것과 같으면 아무것도 하지 않는다 — 화면을 다시 그릴 때마다 같은
///   내용이 들어와도 저장이 미뤄지거나 반복되지 않는다.
/// - 회원 하나에 초안 하나다. 처음에는 만들고(`member_id` 를 붙여), 그 뒤로는
///   같은 초안을 덮어쓴다.
/// - 저장·삭제는 한 줄로 차례로 처리한다. 보관이 도는 중에 [discard] 가 오면
///   보관이 끝난 뒤 지운다 — 순서가 뒤집히면 지운 초안이 되살아난다.
/// - 자동 보관이 실패해도 알리지 않는다. 화면의 작성 내용은 그대로이고, 다음
///   변경에서 다시 시도한다. 이탈 경고(#2873 1단계)가 마지막 안전망이다.
class CoachingDraftAutosaver {
  CoachingDraftAutosaver(
    this._repository, {
    this.delay = kCoachingAutosaveDelay,
  });

  final TrainerProgramDraftRepository _repository;

  /// 입력이 멈춘 뒤 보관까지 기다리는 시간.
  final Duration delay;

  /// 회원 → 그 회원의 자동 보관 초안 id. 아직 모르면 없다.
  final Map<String, String> _draftIds = <String, String>{};

  /// 회원 → 마지막으로 보관한 본문(JSON 문자열).
  final Map<String, String> _saved = <String, String>{};

  /// 회원 → 기다리는 본문과 그 JSON 문자열.
  final Map<String, ({Map<String, Object?> payload, String encoded})> _pending =
      <String, ({Map<String, Object?> payload, String encoded})>{};

  final Map<String, Timer> _timers = <String, Timer>{};

  /// 저장소 작업 줄. 앞 작업이 실패해도 뒤 작업은 돈다.
  Future<void> _queue = Future<void>.value();

  bool _disposed = false;

  /// [memberId] 에게 기다리는 보관이 있는가.
  bool hasPending(String memberId) => _pending.containsKey(memberId);

  /// [payload] 를 [delay] 뒤에 보관하도록 건다. 새로 들어오면 타이머를 다시 건다.
  void schedule(String memberId, Map<String, Object?> payload) {
    if (_disposed) return;
    final String encoded = jsonEncode(payload);
    if (_pending[memberId]?.encoded == encoded) return;
    if (!_pending.containsKey(memberId) && _saved[memberId] == encoded) return;
    _pending[memberId] = (payload: payload, encoded: encoded);
    _timers.remove(memberId)?.cancel();
    _timers[memberId] = Timer(delay, () => unawaited(_save(memberId)));
  }

  /// 기다리지 않고 지금 보관한다. [memberId] 를 비우면 모든 회원이다.
  Future<void> flush([String? memberId]) {
    final List<String> members = memberId == null
        ? _pending.keys.toList()
        : <String>[if (_pending.containsKey(memberId)) memberId];
    return Future.wait<void>(<Future<void>>[
      for (final String member in members) _save(member),
    ]);
  }

  /// [memberId] 의 기다리는 보관만 거둔다. 이미 보관한 초안은 남는다.
  void cancel(String memberId) {
    _timers.remove(memberId)?.cancel();
    _pending.remove(memberId);
  }

  /// [memberId] 에게 자동 보관해 둔 초안. 없거나 읽지 못하면 `null` 이다.
  ///
  /// 여럿이면(다른 탭이 따로 만든 경우) 가장 최근 것을 쓰고, 그 id 로 이어서
  /// 덮어쓴다.
  Future<TrainerProgramDraft?> load(String memberId) => _run(() async {
    try {
      final List<TrainerProgramDraftSummary> found = await _repository.list(
        memberId: memberId,
      );
      if (found.isEmpty) {
        _draftIds.remove(memberId);
        return null;
      }
      final TrainerProgramDraft draft = await _repository.read(found.first.id);
      _draftIds[memberId] = draft.id;
      return draft;
    } on Object {
      return null;
    }
  });

  /// [memberId] 의 자동 보관을 지운다 — 기다리는 보관도 거둔다. 전송·템플릿
  /// 저장이 끝났거나 트레이너가 `버리기` 를 골랐다.
  Future<void> discard(String memberId) {
    cancel(memberId);
    _saved.remove(memberId);
    return _run(() async {
      try {
        final Set<String> ids = <String>{
          ?_draftIds.remove(memberId),
          for (final TrainerProgramDraftSummary d in await _repository.list(
            memberId: memberId,
          ))
            d.id,
        };
        for (final String id in ids) {
          await _repository.delete(id);
        }
      } on Object {
        // 지우지 못한 초안은 다음에 들어올 때 다시 묻는다 — 잃는 것은 없다.
      }
    });
  }

  /// 기다리는 보관을 거두고 더 받지 않는다. 화면이 사라질 때 부른다.
  ///
  /// 마저 저장하지 않는다 — 코칭 화면은 탭을 옮겨도 남아 있어, 사라지는 것은
  /// 로그아웃·계정 전환 때다. 그때 저장하면 앞 계정의 작성 내용이 다음 세션의
  /// 저장소로 간다.
  void dispose() {
    _disposed = true;
    _pending.clear();
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  Future<void> _save(String memberId) {
    _timers.remove(memberId)?.cancel();
    final ({Map<String, Object?> payload, String encoded})? next = _pending
        .remove(memberId);
    if (next == null) return Future<void>.value();
    return _run(() async {
      try {
        final String? id = _draftIds[memberId];
        if (id == null) {
          final TrainerProgramDraft created = await _repository.create(
            <String, Object?>{...next.payload, 'member_id': memberId},
          );
          _draftIds[memberId] = created.id;
        } else {
          await _repository.update(id, next.payload);
        }
        _saved[memberId] = next.encoded;
      } on Object catch (error) {
        // 다른 탭·기기에서 지워졌으면 다음 보관은 새로 만든다. 그 밖의 실패
        // (네트워크 등)는 같은 초안을 다시 덮어쓴다 — 새로 만들면 겹친다.
        if (error is NotFoundError || error is StateError) {
          _draftIds.remove(memberId);
        }
      }
    });
  }

  Future<T> _run<T>(Future<T> Function() task) {
    final Future<T> result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
