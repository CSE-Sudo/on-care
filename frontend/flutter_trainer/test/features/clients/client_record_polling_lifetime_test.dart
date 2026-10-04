/// 회원 식단·운동 기록 폴링의 수명 — 화면이 보는 동안만 돈다. (#3103)
///
/// 전에는 두 provider 를 계정 동안 붙잡아 두어, 회원 상세에서 식단·운동 탭을
/// 한 번 열면 다른 화면으로 가도 로그아웃할 때까지 그 회원의 기록을 30초마다
/// 다시 받았다. 담당 회원을 한 번씩 훑으면 회원 수에 비례해 요청이 쌓였다.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare_trainer/features/clients/data/repositories/dio_client_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

class _MockDio extends Mock implements Dio {}

const String _clientId = 'c1';
const String _dietPath = '/trainer/clients/$_clientId/diet';
const String _historyPath = '/trainer/clients/$_clientId/history';
const Duration _interval = Duration(seconds: 30);

Response<List<dynamic>> _ok(String path) => Response<List<dynamic>>(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: <dynamic>[],
);

void main() {
  late _MockDio dio;
  late Map<String, int> calls;
  late ProviderContainer container;

  setUp(() {
    dio = _MockDio();
    calls = <String, int>{};
    when(
      () => dio.get<List<dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((Invocation invocation) async {
      final String path = invocation.positionalArguments.first as String;
      calls[path] = (calls[path] ?? 0) + 1;
      return _ok(path);
    });
    container = ProviderContainer(
      overrides: <Override>[
        clientRepositoryProvider.overrideWithValue(DioClientRepository(dio)),
      ],
    );
  });

  Future<void> disposeContainer(WidgetTester tester) async {
    container.dispose();
    await tester.pump(Duration.zero);
  }

  for (final (String name, ProviderBase<Object?> provider, String path)
      in <(String, ProviderBase<Object?>, String)>[
        ('식단', clientDietProvider(_clientId), _dietPath),
        ('운동', clientHistoryProvider(_clientId), _historyPath),
      ]) {
    testWidgets('$name — 보는 동안에는 30초마다 다시 읽는다', (tester) async {
      final ProviderSubscription<Object?> sub = container.listen(
        provider,
        (_, _) {},
      );
      await tester.pump(Duration.zero);
      expect(calls[path], 1);

      await tester.pump(_interval);
      await tester.pump(Duration.zero);
      expect(calls[path], 2);

      sub.close();
      await tester.pump(Duration.zero);
      await disposeContainer(tester);
    });

    testWidgets('$name — 화면을 떠나면 폴링이 멈추고 provider 도 버려진다', (tester) async {
      final ProviderSubscription<Object?> sub = container.listen(
        provider,
        (_, _) {},
      );
      await tester.pump(Duration.zero);
      expect(calls[path], 1);

      sub.close();
      await tester.pump(Duration.zero);
      expect(container.exists(provider), isFalse);

      // 몇 주기가 지나도 더 부르지 않는다.
      await tester.pump(_interval * 3);
      expect(calls[path], 1);
      await disposeContainer(tester);
    });

    testWidgets('$name — 다시 열면 새로 읽고 폴링을 다시 시작한다', (tester) async {
      ProviderSubscription<Object?> sub = container.listen(provider, (_, _) {});
      await tester.pump(Duration.zero);
      sub.close();
      await tester.pump(Duration.zero);
      await tester.pump(_interval * 2);
      expect(calls[path], 1);

      sub = container.listen(provider, (_, _) {});
      await tester.pump(Duration.zero);
      expect(calls[path], 2);

      await tester.pump(_interval);
      await tester.pump(Duration.zero);
      expect(calls[path], 3);

      sub.close();
      await tester.pump(Duration.zero);
      await disposeContainer(tester);
    });
  }
}
