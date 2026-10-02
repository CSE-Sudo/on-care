import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The demo build's memo store. Its reads used to hand back a `const` list,
/// which every mutating caller then tried to sort or edit in place — so a
/// client with no memos yet failed to load instead of showing an empty
/// list (#814).
Future<LocalTrainerMemoRepository> _repoWith(
  Map<String, Object> initialValues,
) async {
  SharedPreferences.setMockInitialValues(initialValues);
  return LocalTrainerMemoRepository(await SharedPreferences.getInstance());
}

Map<String, Object?> _memoJson({
  required String id,
  required String body,
  required String createdAt,
}) => <String, Object?>{
  'id': id,
  'body': body,
  'source': 'trainer',
  'insight_id': null,
  'insight_kind': '',
  'created_at': createdAt,
  'updated_at': createdAt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a client with no memos reads as an empty list, not a failure',
    () async {
      final repo = await _repoWith(<String, Object>{});

      await expectLater(repo.fetch('m1'), completion(isEmpty));
    },
  );

  test('a payload from an older build reads as an empty list', () async {
    final repo = await _repoWith(<String, Object>{
      'trainer_memos:m1': '{"not":"a list"}',
    });

    await expectLater(repo.fetch('m1'), completion(isEmpty));
  });

  test('deleting against a client with no memos does not throw', () async {
    final repo = await _repoWith(<String, Object>{});

    await expectLater(repo.delete('m1', 'memo-1'), completes);
  });

  test('fetch returns the stored memos newest first', () async {
    final repo = await _repoWith(<String, Object>{
      'trainer_memos:m1': jsonEncode(<Map<String, Object?>>[
        _memoJson(
          id: 'memo-old',
          body: '지난주 무릎 통증',
          createdAt: '2026-08-10T09:00:00.000Z',
        ),
        _memoJson(
          id: 'memo-new',
          body: '오늘 나트륨 초과',
          createdAt: '2026-08-16T09:00:00.000Z',
        ),
      ]),
    });

    final memos = await repo.fetch('m1');

    expect(memos.map((memo) => memo.id), <String>['memo-new', 'memo-old']);
  });

  test('a memo written to an empty store is read back', () async {
    final repo = await _repoWith(<String, Object>{});

    await repo.create('m1', body: '무릎 상태 확인');
    final memos = await repo.fetch('m1');

    expect(memos.single.body, '무릎 상태 확인');
    expect(memos.single.source, TrainerMemoSource.trainer);
  });

  test('saving the same chat insight twice keeps one memo', () async {
    final repo = await _repoWith(<String, Object>{});

    final first = await repo.create(
      'm1',
      body: '무릎이 아파요',
      source: TrainerMemoSource.chatInsight,
      insightId: 'msg-3:discomfort',
      insightKind: 'discomfort',
    );
    final second = await repo.create(
      'm1',
      body: '무릎이 아파요',
      source: TrainerMemoSource.chatInsight,
      insightId: 'msg-3:discomfort',
      insightKind: 'discomfort',
    );

    expect(second.id, first.id);
    await expectLater(repo.fetch('m1'), completion(hasLength(1)));
  });

  test('a memo can be edited and removed', () async {
    final repo = await _repoWith(<String, Object>{});
    final memo = await repo.create('m1', body: '초안');

    final updated = await repo.update('m1', memo.id, '수정한 메모');
    expect(updated.body, '수정한 메모');
    await expectLater(repo.fetch('m1'), completion(hasLength(1)));

    await repo.delete('m1', memo.id);
    await expectLater(repo.fetch('m1'), completion(isEmpty));
  });

  test('memos are kept per client', () async {
    final repo = await _repoWith(<String, Object>{});

    await repo.create('m1', body: 'm1 메모');

    await expectLater(repo.fetch('m2'), completion(isEmpty));
  });

  test('the demo keeps the category the server would (#2622)', () async {
    final repo = await _repoWith(<String, Object>{});
    final manual = await repo.create(
      'm1',
      body: '야식 줄이기',
      category: TrainerMemoCategory.diet,
    );
    final exercise = await repo.create(
      'm1',
      body: '걷기 꾸준함',
      source: TrainerMemoSource.exerciseMemo,
      ref: const TrainerMemoRef(
        kind: TrainerMemoRefKind.memberLog,
        day: '2026-09-28',
      ),
    );
    expect(manual.category, TrainerMemoCategory.diet);
    // 운동 기록 메모는 언제나 운동이다 — 서버와 같은 규칙.
    expect(exercise.category, TrainerMemoCategory.exercise);

    final changed = await repo.update(
      'm1',
      manual.id,
      manual.body,
      category: TrainerMemoCategory.life,
    );
    expect(changed.category, TrainerMemoCategory.life);
    // 다시 읽어도 남아 있다.
    final stored = (await repo.fetch(
      'm1',
    )).firstWhere((m) => m.id == manual.id);
    expect(stored.category, TrainerMemoCategory.life);

    // 출처가 분류를 정한 메모는 바꿀 수 없다(실서버 400 과 같다).
    expect(
      repo.update(
        'm1',
        exercise.id,
        exercise.body,
        category: TrainerMemoCategory.diet,
      ),
      throwsA(isA<ValidationError>()),
    );
  });
}
