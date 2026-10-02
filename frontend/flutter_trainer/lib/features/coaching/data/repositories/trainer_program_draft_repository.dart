import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
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
abstract interface class TrainerProgramDraftRepository {
  /// Saved drafts, most recently updated first.
  Future<List<TrainerProgramDraftSummary>> list();

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
class LocalTrainerProgramDraftRepository
    implements TrainerProgramDraftRepository {
  const LocalTrainerProgramDraftRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'trainer_program_drafts';

  List<Map<String, Object?>> _read() {
    final raw = _prefs.getString(_key);
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

  Future<void> _write(List<Map<String, Object?>> drafts) =>
      _prefs.setString(_key, jsonEncode(drafts));

  @override
  Future<List<TrainerProgramDraftSummary>> list() async {
    final drafts = _read()
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
