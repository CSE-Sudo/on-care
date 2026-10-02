import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/storage/prefs_provider.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_trainer_memo_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/trainer_memo.dart';
import 'package:oncare_trainer/shared/services/trainer_memo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/trainer/clients/m1/memos';

Map<String, Object?> _memoJson({
  String id = 'memo-1',
  String body = '무릎 통증 경과 관찰',
  String source = 'trainer',
  String? insightId,
  String insightKind = '',
  String createdAt = '2026-08-14T09:00:00Z',
}) => <String, Object?>{
  'id': id,
  'body': body,
  'source': source,
  'insight_id': insightId,
  'insight_kind': insightKind,
  'created_at': createdAt,
  'updated_at': createdAt,
};

Response<T> _ok<T>(T data) => Response<T>(
  requestOptions: RequestOptions(path: _path),
  statusCode: 200,
  data: data,
);

DioException _httpError(int status) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
  ),
);

ProviderContainer _containerFor({
  required bool useMockApi,
  List<Override> extraOverrides = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: Environment.dev,
          apiBaseUrl: 'http://localhost/v1',
          useMockApi: useMockApi,
        ),
      ),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDio dio;
  late DioTrainerMemoRepository repo;

  setUp(() {
    dio = _MockDio();
    repo = DioTrainerMemoRepository(dio);
  });

  test('fetch parses the memo list', () async {
    when(() => dio.get<List<dynamic>>(_path)).thenAnswer(
      (_) async => _ok<List<dynamic>>(<dynamic>[
        _memoJson(),
        _memoJson(
          id: 'memo-2',
          body: '무릎이 아파요',
          source: 'chat_insight',
          insightId: 'msg-3:discomfort',
          insightKind: 'discomfort',
        ),
      ]),
    );

    final memos = await repo.fetch('m1');
    expect(memos.map((m) => m.id), <String>['memo-1', 'memo-2']);
    expect(memos.first.source, TrainerMemoSource.trainer);
    expect(memos.first.insightId, isNull);
    expect(memos.last.source, TrainerMemoSource.chatInsight);
    expect(memos.last.insightId, 'msg-3:discomfort');
    expect(memos.last.insightKind, 'discomfort');
  });

  test('a client this trainer is not assigned to surfaces a typed error', () {
    when(() => dio.get<List<dynamic>>(_path)).thenThrow(_httpError(404));
    expect(repo.fetch('m1'), throwsA(isA<AppError>()));
  });

  test('create sends the chat-insight de-duplication key', () async {
    Map<String, Object?>? sent;
    when(
      () => dio.post<Map<String, Object?>>(_path, data: any(named: 'data')),
    ).thenAnswer((invocation) async {
      sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
          .cast<String, Object?>();
      return _ok<Map<String, Object?>>(
        _memoJson(
          id: 'memo-9',
          body: '무릎이 아파요',
          source: 'chat_insight',
          insightId: 'msg-3:discomfort',
          insightKind: 'discomfort',
        ),
      );
    });

    final memo = await repo.create(
      'm1',
      body: '무릎이 아파요',
      source: TrainerMemoSource.chatInsight,
      insightId: 'msg-3:discomfort',
      insightKind: 'discomfort',
    );

    expect(sent!['source'], 'chat_insight');
    expect(sent!['insight_id'], 'msg-3:discomfort');
    expect(sent!['insight_kind'], 'discomfort');
    expect(memo.id, 'memo-9');
  });

  test('a hand-written memo carries no insight key', () async {
    Map<String, Object?>? sent;
    when(
      () => dio.post<Map<String, Object?>>(_path, data: any(named: 'data')),
    ).thenAnswer((invocation) async {
      sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
          .cast<String, Object?>();
      return _ok<Map<String, Object?>>(_memoJson());
    });

    await repo.create('m1', body: '직접 작성');
    expect(sent!.containsKey('insight_id'), isFalse);
    expect(sent!.containsKey('insight_kind'), isFalse);
    expect(sent!['source'], 'trainer');
  });

  test('update rewrites only the body', () async {
    Map<String, Object?>? sent;
    when(
      () => dio.put<Map<String, Object?>>(
        '$_path/memo-1',
        data: any(named: 'data'),
      ),
    ).thenAnswer((invocation) async {
      sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
          .cast<String, Object?>();
      return _ok<Map<String, Object?>>(_memoJson(body: '고친 내용'));
    });

    final memo = await repo.update('m1', 'memo-1', '고친 내용');
    expect(sent, <String, Object?>{'body': '고친 내용'});
    expect(memo.body, '고친 내용');
  });

  test('delete failures surface as a typed error', () async {
    when(
      () => dio.delete<Map<String, Object?>>('$_path/memo-1'),
    ).thenThrow(_httpError(404));
    expect(repo.delete('m1', 'memo-1'), throwsA(isA<AppError>()));
  });

  test('resolves the local repository when USE_MOCK_API=true', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = _containerFor(
      useMockApi: true,
      extraOverrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    expect(
      container.read(trainerMemoRepositoryProvider),
      isA<LocalTrainerMemoRepository>(),
    );
  });

  test('resolves the Dio repository when USE_MOCK_API=false', () {
    final container = _containerFor(
      useMockApi: false,
      extraOverrides: <Override>[dioProvider.overrideWithValue(dio)],
    );
    expect(
      container.read(trainerMemoRepositoryProvider),
      isA<DioTrainerMemoRepository>(),
    );
  });

  test('in real-API mode a memo survives a fresh provider container — the '
      'trainer sees it again after a re-login or in another browser', () async {
    // The mock Dio stands in for the server: whatever POST stored is what a
    // later GET returns, no matter which container asks.
    final stored = <Map<String, Object?>>[];
    when(
      () => dio.post<Map<String, Object?>>(_path, data: any(named: 'data')),
    ).thenAnswer((invocation) async {
      final data = (invocation.namedArguments[#data] as Map<Object?, Object?>)
          .cast<String, Object?>();
      final memo = _memoJson(
        id: 'memo-${stored.length + 1}',
        body: data['body']! as String,
      );
      stored.add(memo);
      return _ok<Map<String, Object?>>(memo);
    });
    when(
      () => dio.get<List<dynamic>>(_path),
    ).thenAnswer((_) async => _ok<List<dynamic>>(List<dynamic>.from(stored)));

    final first = _containerFor(
      useMockApi: false,
      extraOverrides: <Override>[dioProvider.overrideWithValue(dio)],
    );
    await first
        .read(trainerMemoRepositoryProvider)
        .create('m1', body: '재로그인 후에도 남아야 하는 메모');
    first.dispose();

    // A brand-new container: new repository instance, no carried state.
    final second = _containerFor(
      useMockApi: false,
      extraOverrides: <Override>[dioProvider.overrideWithValue(dio)],
    );
    // autoDispose provider 는 리스너가 없으면 future 가 끝나기 전에 폐기될 수
    // 있다 — 읽는 동안 구독을 잡아 둔다.
    final sub = second.listen(trainerMemosProvider('m1'), (_, _) {});
    addTearDown(sub.close);
    final memos = await second.read(trainerMemosProvider('m1').future);
    expect(memos, hasLength(1));
    expect(memos.single.body, '재로그인 후에도 남아야 하는 메모');
  });

  test(
    'a picked category goes out with the memo and comes back (#2622)',
    () async {
      Map<String, Object?>? sent;
      when(
        () => dio.post<Map<String, Object?>>(_path, data: any(named: 'data')),
      ).thenAnswer((invocation) async {
        sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
            .cast<String, Object?>();
        return _ok<Map<String, Object?>>(<String, Object?>{
          ..._memoJson(body: '허리 디스크 이력'),
          'category': 'pain',
        });
      });

      final memo = await repo.create(
        'm1',
        body: '허리 디스크 이력',
        category: TrainerMemoCategory.pain,
      );
      expect(sent!['category'], 'pain');
      expect(memo.category, TrainerMemoCategory.pain);

      // 고르지 않은 메모는 분류 칸을 싣지 않는다.
      await repo.create('m1', body: '분류 없음');
      expect(sent!.containsKey('category'), isFalse);
    },
  );

  test('update sends a category only when one is given (#2622)', () async {
    Map<String, Object?>? sent;
    when(
      () => dio.put<Map<String, Object?>>(
        '$_path/memo-1',
        data: any(named: 'data'),
      ),
    ).thenAnswer((invocation) async {
      sent = (invocation.namedArguments[#data] as Map<Object?, Object?>)
          .cast<String, Object?>();
      return _ok<Map<String, Object?>>(_memoJson());
    });

    await repo.update('m1', 'memo-1', '본문', category: TrainerMemoCategory.none);
    // 빈 문자열은 분류를 지운다 — `직접 작성` 으로 돌아간다.
    expect(sent, <String, Object?>{'body': '본문', 'category': ''});
  });

  test('an unknown category reads as none instead of failing the list', () {
    final memo = TrainerMemo.fromJson(<String, Object?>{
      ..._memoJson(),
      'category': 'sleep',
    });
    expect(memo.category, TrainerMemoCategory.none);
  });
}
