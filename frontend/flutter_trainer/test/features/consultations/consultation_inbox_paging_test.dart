/// 상담함 `더 보기` 뒤 새 요청이 와도 요청이 사라지지 않는다. (#3249)
///
/// 폴링은 첫 쪽만 다시 읽는다. 이어 받은 뒤 새 요청이 들어오면 꽉 찬 첫 쪽의
/// 마지막 요청이 밀려나, 첫 쪽에도 이어 받은 목록에도 없게 되어 한 건이 사라졌다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';

/// 번호가 클수록 새 요청이다. id 도 같은 순서로 정렬되게 0 을 채운다.
ConsultationRequest _request(int n) => ConsultationRequest(
  id: 'r${n.toString().padLeft(3, '0')}',
  memberId: 'm$n',
  memberName: '회원 $n',
  goalCode: 'weight_loss',
  purposeCode: 'chronic',
  preferredDate: DateTime(2026, 10, 10),
  preferredTimeCode: 'flexible',
  status: 'pending',
  createdAt: DateTime.utc(2026, 10).add(Duration(minutes: n)),
);

/// [from] 부터 [to] 까지(둘 다 포함) 최신순.
List<ConsultationRequest> _range(int from, int to) => <ConsultationRequest>[
  for (int n = from; n >= to; n--) _request(n),
];

class _FakeRepository implements ConsultationRepository {
  // tearDown 이 닫는다.
  // ignore: close_sinks
  final StreamController<List<ConsultationRequest>> firstPage =
      StreamController<List<ConsultationRequest>>.broadcast();
  List<ConsultationRequest> older = const <ConsultationRequest>[];

  @override
  Stream<List<ConsultationRequest>> watch({
    String status = 'pending',
    int limit = consultationPageSize,
  }) => firstPage.stream;

  @override
  Future<List<ConsultationRequest>> fetch({
    String status = 'pending',
    int limit = consultationPageSize,
    DateTime? before,
    String? beforeId,
  }) async => older;

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

List<String> _ids(ConsultationInboxController c) => <String>[
  for (final ConsultationRequest r in c.state.requests.requireValue) r.id,
];

void main() {
  late _FakeRepository repo;
  late ConsultationInboxController controller;

  setUp(() async {
    repo = _FakeRepository();
    controller = ConsultationInboxController(repo, 'pending');
    // 첫 쪽 50건(100~51)을 받고, `더 보기` 로 50건(50~1)을 이어 받는다.
    repo.firstPage.add(_range(100, 51));
    await _flush();
    repo.older = _range(50, 1);
    await controller.loadMore();
  });

  tearDown(() async {
    controller.dispose();
    await repo.firstPage.close();
  });

  test('새 요청이 와도 첫 쪽에서 밀려난 요청이 남는다', () async {
    expect(_ids(controller), hasLength(100));

    // 새 요청(101)이 들어와 첫 쪽이 101~52 가 됐다 — 51 이 밀려났다.
    repo.firstPage.add(_range(101, 52));
    await _flush();

    final List<String> ids = _ids(controller);
    expect(ids, hasLength(101));
    expect(ids.where((String id) => id == 'r051'), hasLength(1));
    expect(ids.first, 'r101');
    // 순서도 그대로다 — 52 다음이 51, 그다음이 이어 받은 50.
    expect(ids.indexOf('r051'), ids.indexOf('r052') + 1);
    expect(ids.indexOf('r050'), ids.indexOf('r051') + 1);
  });

  test('처리돼 갈래를 떠난 요청은 되살리지 않는다', () async {
    // 60 을 수락했다 — 대기 첫 쪽은 100~61, 59~50 이다(50 이 올라왔다).
    repo.firstPage.add(<ConsultationRequest>[
      ..._range(100, 61),
      ..._range(59, 50),
    ]);
    await _flush();

    final List<String> ids = _ids(controller);
    expect(ids, isNot(contains('r060')));
    expect(ids, hasLength(99));
    expect(ids.where((String id) => id == 'r050'), hasLength(1));
  });
}
