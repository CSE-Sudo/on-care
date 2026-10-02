import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_program_draft_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_draft_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

class _MockPrefs extends Mock implements SharedPreferences {}

const String _base = '/trainer/programs';

Response<T> _ok<T>(T data) => Response<T>(
  requestOptions: RequestOptions(path: _base),
  statusCode: 200,
  data: data,
);

Map<String, Object?> _summaryJson({String id = 'pgm-1', String? memberId}) =>
    <String, Object?>{
      'id': id,
      'name': '작성 중',
      'goal': '',
      'period': '',
      'session_count': 1,
      'exercise_count': 0,
      'updated_at': '2026-10-02T09:00:00Z',
      'member_id': memberId,
    };

Map<String, Object?> _payload({String name = '작성 중', String? memberId}) =>
    <String, Object?>{
      'name': name,
      'goal': '',
      'period': '',
      'memo': '',
      'sessions': const <Object?>[],
      'workspace': <String, Object?>{'version': 1, 'phase': 'wizard'},
      'member_id': ?memberId,
    };

/// 프로그램 초안 저장소의 회원별 자동 보관 계약 (#2873).
///
/// 코칭 화면은 회원마다 초안 하나를 자동 보관하고 회원으로 찾는다. 실 API 는
/// 목록을 `member_id` 로 거르고, 데모(브라우저 저장소)는 같은 일을 스스로 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DioTrainerProgramDraftRepository', () {
    late _MockDio dio;
    late DioTrainerProgramDraftRepository repo;

    setUp(() {
      dio = _MockDio();
      repo = DioTrainerProgramDraftRepository(dio);
    });

    test('회원을 주면 목록을 member_id 로 거른다', () async {
      when(
        () => dio.get<List<dynamic>>(
          _base,
          queryParameters: <String, Object?>{'member_id': 'member-1'},
        ),
      ).thenAnswer(
        (_) async =>
            _ok<List<dynamic>>(<dynamic>[_summaryJson(memberId: 'member-1')]),
      );

      final drafts = await repo.list(memberId: 'member-1');

      expect(drafts.single.memberId, 'member-1');
      verifyNever(() => dio.get<List<dynamic>>(_base));
    });

    test('회원을 주지 않으면 지금처럼 거르지 않는다', () async {
      when(
        () => dio.get<List<dynamic>>(_base),
      ).thenAnswer((_) async => _ok<List<dynamic>>(<dynamic>[_summaryJson()]));

      final drafts = await repo.list();

      expect(drafts.single.memberId, isNull);
    });

    test('상세의 회원과 작성 상태를 읽는다', () async {
      when(() => dio.get<Map<String, Object?>>('$_base/pgm-1')).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'pgm-1',
          'name': '작성 중',
          'goal': '',
          'period': '',
          'memo': '',
          'sessions': const <Object?>[],
          'created_at': '2026-10-02T09:00:00Z',
          'updated_at': '2026-10-02T09:00:00Z',
          'member_id': 'member-1',
          'workspace': <String, Object?>{'version': 1, 'phase': 'editor'},
        }),
      );

      final draft = await repo.read('pgm-1');

      expect(draft.memberId, 'member-1');
      expect(draft.workspace['phase'], 'editor');
      // 다시 싣는 모양에도 그대로 남는다.
      expect(draft.toJson()['member_id'], 'member-1');
    });

    test('회원 없는 예전 초안은 빈 작성 상태로 읽는다', () async {
      when(() => dio.get<Map<String, Object?>>('$_base/pgm-1')).thenAnswer(
        (_) async => _ok<Map<String, Object?>>(<String, Object?>{
          'id': 'pgm-1',
          'name': '예전 초안',
          'goal': '',
          'period': '',
          'memo': '',
          'sessions': const <Object?>[],
          'created_at': '2026-10-02T09:00:00Z',
          'updated_at': '2026-10-02T09:00:00Z',
        }),
      );

      final draft = await repo.read('pgm-1');

      expect(draft.memberId, isNull);
      expect(draft.workspace, isEmpty);
    });
  });

  group('LocalTrainerProgramDraftRepository (데모)', () {
    late LocalTrainerProgramDraftRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      repo = LocalTrainerProgramDraftRepository(
        await SharedPreferences.getInstance(),
      );
    });

    test('회원으로 거르고, 회원 없는 초안은 섞이지 않는다', () async {
      final mine = await repo.create(_payload(memberId: 'member-1'));
      await repo.create(_payload(memberId: 'member-2'));
      await repo.create(_payload(name: '일반 초안'));

      final drafts = await repo.list(memberId: 'member-1');

      expect(drafts.map((d) => d.id), <String>[mine.id]);
      expect(drafts.single.memberId, 'member-1');
      expect(await repo.list(), hasLength(3));
    });

    test('같은 순간에 만들어도 id 가 겹치지 않는다', () async {
      final a = await repo.create(_payload(memberId: 'member-1'));
      final b = await repo.create(_payload(memberId: 'member-2'));

      expect(a.id, isNot(b.id));
    });

    test('수정은 작성 상태를 바꾸고 회원은 그대로 둔다', () async {
      final created = await repo.create(_payload(memberId: 'member-1'));

      await repo.update(created.id, <String, Object?>{
        ..._payload(name: '고친 이름'),
        'workspace': <String, Object?>{'version': 1, 'phase': 'editor'},
        // 수정 본문에 회원이 실려도 바꾸지 않는다 — 서버와 같다.
        'member_id': 'member-2',
      });

      final stored = await repo.read(created.id);
      expect(stored.name, '고친 이름');
      expect(stored.memberId, 'member-1');
      expect(stored.workspace['phase'], 'editor');
    });
  });

  group('LocalTrainerProgramDraftRepository — 브라우저 저장소를 못 쓸 때', () {
    late _MockPrefs prefs;
    late LocalTrainerProgramDraftRepository repo;

    setUp(() {
      prefs = _MockPrefs();
      repo = LocalTrainerProgramDraftRepository(prefs);
    });

    test('읽기가 던지면 빈 목록이다', () async {
      when(() => prefs.getString(any())).thenThrow(Exception('blocked'));

      expect(await repo.list(memberId: 'member-1'), isEmpty);
    });

    test('쓰기가 던지거나 거절되면 StateError 하나로 올라온다', () async {
      when(() => prefs.getString(any())).thenReturn(null);
      when(
        () => prefs.setString(any(), any()),
      ).thenThrow(Exception('quota exceeded'));
      await expectLater(
        repo.create(_payload(memberId: 'member-1')),
        throwsStateError,
      );

      when(() => prefs.setString(any(), any())).thenAnswer((_) async => false);
      await expectLater(
        repo.create(_payload(memberId: 'member-1')),
        throwsStateError,
      );
    });
  });
}
