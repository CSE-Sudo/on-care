import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/trainer_program_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saves, lists and reopens the trainer's program drafts (#708).
///
/// Two implementations sit behind this contract, selected by
/// [trainerProgramDraftRepositoryProvider] via [AppConfig.useMockApi]:
///  * [LocalTrainerProgramDraftRepository] — browser-local prefs for the
///    demo build, which has no account to save against;
///  * [DioTrainerProgramDraftRepository] — the real FastAPI backend, where a
///    draft survives a reload and a re-login.
///
/// A draft is not assigned to anyone. Assigning or scheduling it stays the
/// separate action it already is — the trainer reopens a draft and then uses
/// the existing buttons.
///
/// 코칭 화면의 자동 보관(#2873)도 같은 저장소를 쓴다. 그때는 payload 에
/// `member_id` 와 `workspace`(편집기 밖의 작성 상태)가 함께 실리고, 회원별로
/// [list] 의 `memberId` 로 찾는다. 배정과 무관하다는 점은 그대로다 — 보내는
/// 것은 여전히 코칭 화면의 기존 버튼이다.
abstract interface class TrainerProgramDraftRepository {
  /// Saved drafts, most recently updated first.
  ///
  /// [memberId] 를 주면 그 회원에게 자동 보관한 것만 돌려준다(#2873).
  Future<List<TrainerProgramDraftSummary>> list({String? memberId});

  /// One draft with its exercises, for loading back into the editor.
  Future<TrainerProgramDraft> read(String id);

  /// Saves a new draft. [payload] comes from `programDraftToJson`.
  Future<TrainerProgramDraft> create(Map<String, Object?> payload);

  /// Overwrites an existing draft with the editor's current contents.
  Future<TrainerProgramDraft> update(String id, Map<String, Object?> payload);

  Future<void> delete(String id);
}

/// Keeps drafts in browser-local prefs for the demo build.
///
/// The demo has no account behind it, so there is nowhere else to put them —
/// but a save that silently discarded the work would be worse than the
/// disabled button it replaces.
///
/// 웹에서 prefs 는 브라우저 저장소다. 사생활 보호 창·저장소 차단·용량 초과면
/// 읽기·쓰기가 던질 수 있다 — 읽기는 빈 목록으로, 쓰기는 [StateError] 로
/// 바꿔 부르는 쪽(자동 보관은 조용히 넘긴다)이 한 가지 예외만 다루게 한다.
class LocalTrainerProgramDraftRepository
    implements TrainerProgramDraftRepository {
  const LocalTrainerProgramDraftRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'trainer_program_drafts';

  List<Map<String, Object?>> _read() {
    final String? raw;
    try {
      raw = _prefs.getString(_key);
    } on Object {
      return <Map<String, Object?>>[];
    }
    if (raw == null) return <Map<String, Object?>>[];
    try {
      return (jsonDecode(raw) as List<Object?>)
          .map(
            (item) => (item! as Map<Object?, Object?>).cast<String, Object?>(),
          )
          .toList();
    } on Object {
      // A payload written by an older build is not worth crashing over.
      return <Map<String, Object?>>[];
    }
  }

  Future<void> _write(List<Map<String, Object?>> drafts) async {
    final bool ok;
    try {
      ok = await _prefs.setString(_key, jsonEncode(drafts));
    } on Object catch (error) {
      throw StateError('program drafts could not be stored: $error');
    }
    if (!ok) throw StateError('program drafts could not be stored');
  }

  @override
  Future<List<TrainerProgramDraftSummary>> list({String? memberId}) async {
    final drafts = _read()
      ..removeWhere(
        (draft) => memberId != null && draft['member_id'] != memberId,
      )
      ..sort(
        (a, b) =>
            (b['updated_at']! as String).compareTo(a['updated_at']! as String),
      );
    return drafts
        .map(
          (draft) => TrainerProgramDraftSummary(
            id: draft['id']! as String,
            name: draft['name'] as String? ?? '',
            goal: draft['goal'] as String? ?? '',
            period: draft['period'] as String? ?? '',
            sessionCount:
                ((draft['sessions'] as List<Object?>?) ?? const <Object?>[])
                    .length,
            exerciseCount:
                ((draft['sessions'] as List<Object?>?) ?? const <Object?>[])
                    .fold<int>(
                      0,
                      (count, session) =>
                          count +
                          (((session! as Map<Object?, Object?>)['exercises']
                                      as List<Object?>?) ??
                                  const <Object?>[])
                              .length,
                    ),
            updatedAt: DateTime.parse(draft['updated_at']! as String),
            memberId: draft['member_id'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<TrainerProgramDraft> read(String id) async {
    final match = _read().where((draft) => draft['id'] == id);
    if (match.isEmpty) throw StateError('program draft not found: $id');
    return TrainerProgramDraft.fromJson(match.first);
  }

  @override
  Future<TrainerProgramDraft> create(Map<String, Object?> payload) async {
    final drafts = _read();
    final now = nowKst();
    final stored = <String, Object?>{
      ...payload,
      'id': 'pgm-local-${now.microsecondsSinceEpoch}',
      'updated_at': now.toIso8601String(),
    };
    await _write(<Map<String, Object?>>[...drafts, stored]);
    return TrainerProgramDraft.fromJson(stored);
  }

  @override
  Future<TrainerProgramDraft> update(
    String id,
    Map<String, Object?> payload,
  ) async {
    final drafts = _read();
    final index = drafts.indexWhere((draft) => draft['id'] == id);
    if (index < 0) throw StateError('program draft not found: $id');
    final stored = <String, Object?>{
      ...drafts[index],
      ...payload,
      // 회원은 바꾸지 않는다 — 서버(`TrainerProgramDraftUpdate`)와 같다(#2873).
      'member_id': drafts[index]['member_id'],
      'id': id,
      'updated_at': nowKst().toIso8601String(),
    };
    drafts[index] = stored;
    await _write(drafts);
    return TrainerProgramDraft.fromJson(stored);
  }

  @override
  Future<void> delete(String id) async {
    final drafts = _read()..removeWhere((draft) => draft['id'] == id);
    await _write(drafts);
  }
}

/// Selects the backend-backed draft store, or the browser-local one for
/// demo / `USE_MOCK_API=true`.
final trainerProgramDraftRepositoryProvider =
    Provider<TrainerProgramDraftRepository>((ref) {
      ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
      final config = ref.watch(appConfigProvider);
      if (config.useMockApi) {
        return LocalTrainerProgramDraftRepository(
          ref.watch(sharedPreferencesProvider),
        );
      }
      return DioTrainerProgramDraftRepository(ref.watch(dioProvider));
    }, name: 'trainerProgramDraftRepository');

/// The trainer's saved drafts, most recently updated first. Invalidate
/// after a save or a delete.
final trainerProgramDraftsProvider =
    FutureProvider.autoDispose<List<TrainerProgramDraftSummary>>((ref) {
      return ref.watch(trainerProgramDraftRepositoryProvider).list();
    });
