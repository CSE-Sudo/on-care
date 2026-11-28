import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/my_health/data/repositories/demo_trainer_sync_repository.dart';
import 'package:oncare/features/my_health/data/repositories/trainer_sync_repository.dart';

/// 데모의 동기화 코드 저장소는 발급·취소를 실서비스와 같은 경로로 보내고, 코드를
/// 입력해 줄 트레이너만 대신한다. (#3342)
///
/// 데모에는 웹에 코드를 넣어 줄 트레이너가 없어, 이 장치가 없으면 연결 코드
/// 시트의 `연결됐어요` 가 데모에서만 보이지 않는다.
class _PairingCodeApi extends Interceptor {
  final List<String> calls = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add('${options.method} ${options.path}');
    handler.resolve(
      Response<Object?>(
        requestOptions: options,
        statusCode: options.method == 'DELETE' ? 204 : 200,
        data: options.method == 'DELETE'
            ? null
            : <String, Object?>{'code': '567812', 'expires_in_seconds': 300},
      ),
    );
  }
}

/// 테스트는 실제 시간을 기다린다 — 입력까지의 시간을 짧게 준다.
const Duration _delay = Duration(milliseconds: 60);

void main() {
  late _PairingCodeApi api;
  late Dio dio;
  late int entered;
  late DemoTrainerSyncRepository repository;

  setUp(() {
    api = _PairingCodeApi();
    dio = Dio()..interceptors.add(api);
    entered = 0;
    repository = DemoTrainerSyncRepository(
      dio,
      onCodeEntered: () => entered += 1,
      entryDelay: _delay,
    );
    addTearDown(repository.dispose);
  });

  test('데모의 입력 시간은 코드를 받아 적을 만큼이다', () {
    expect(
      demoPairingEntryDelay,
      greaterThanOrEqualTo(const Duration(seconds: 3)),
    );
    expect(demoPairingEntryDelay, lessThan(const Duration(minutes: 1)));
  });

  test('발급하고 잠시 지나면 트레이너가 코드를 입력한 것으로 친다', () async {
    final PairingCode issued = await repository.issue();

    expect(issued.code, '567812');
    expect(api.calls, <String>['POST /users/me/pairing-code']);
    // 받아 적는 사이에는 아직 연결되지 않는다.
    expect(entered, 0);

    await Future<void>.delayed(_delay * 2);
    expect(entered, 1);

    // 한 번 입력하면 끝이다.
    await Future<void>.delayed(_delay * 2);
    expect(entered, 1);
  });

  test('시트를 닫아 코드를 버리면 입력도 없던 일이 된다', () async {
    await repository.issue();
    await repository.revoke();

    await Future<void>.delayed(_delay * 2);

    expect(entered, 0);
    expect(api.calls, <String>[
      'POST /users/me/pairing-code',
      'DELETE /users/me/pairing-code',
    ]);
  });

  test('새 코드를 받으면 입력은 한 번만 일어난다', () async {
    await repository.issue();
    await repository.issue();

    await Future<void>.delayed(_delay * 3);

    expect(entered, 1);
  });

  test('provider 가 사라지면 남은 입력을 정리한다', () async {
    await repository.issue();
    repository.dispose();

    await Future<void>.delayed(_delay * 2);

    expect(entered, 0);
  });
}
