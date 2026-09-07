// 회원 끼니 사진 썸네일 (#699).
//
// 사진은 인증이 걸린 경로에서 온다 — 앱의 Dio 를 통해야 토큰이 붙는다. 그리고
// 사진을 못 가져오는 경우가 흔하다(사진 저장 이전 기록, 권한, 네트워크). 그때
// 카드가 깨지지 않고 사진 자리만 비는지가 이 스위트의 관심사다.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/client_meal_photo.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/trainer/clients/m1/diet/photos/dietpic-1';

/// 1x1 PNG — 디코딩되는 최소 이미지.
final Uint8List _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Response<List<int>> _bytes(List<int> body) => Response<List<int>>(
  requestOptions: RequestOptions(path: _path),
  statusCode: 200,
  data: body,
);

Future<ProviderContainer> _pump(WidgetTester tester, Dio dio) async {
  final container = ProviderContainer(
    overrides: <Override>[dioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: ClientMealPhoto(path: _path)),
      ),
    ),
  );
  // 한 번은 로딩 자리, 그다음 결과.
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
    registerFallbackValue(Options());
  });

  void stub(Object Function() answer) {
    when(
      () => dio.get<List<int>>(_path, options: any(named: 'options')),
    ).thenAnswer((_) async {
      final Object result = answer();
      if (result is DioException) throw result;
      return result as Response<List<int>>;
    });
  }

  testWidgets('그려진 사진은 회원이 올린 바이트 그대로다', (tester) async {
    stub(() => _bytes(_pngBytes));

    final container = await _pump(tester, dio);

    expect(find.byType(Image), findsOneWidget);
    expect(
      await container.read(clientMealPhotoProvider(_path).future),
      _pngBytes,
    );
  });

  testWidgets('사진 요청이 실패하면 자리만 비고 카드는 남는다', (tester) async {
    // 담당이 아니거나 사진이 지워진 경우가 여기로 온다(서버는 404 로 답한다).
    stub(
      () => DioException(
        requestOptions: RequestOptions(path: _path),
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: RequestOptions(path: _path),
          statusCode: 404,
        ),
      ),
    );

    await _pump(tester, dio);

    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('빈 응답도 사진 없음으로 다룬다', (tester) async {
    stub(() => _bytes(<int>[]));

    await _pump(tester, dio);

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('사진은 앱의 Dio 로만 읽는다 — 토큰이 붙는 경로다', (tester) async {
    stub(() => _bytes(_pngBytes));

    await _pump(tester, dio);

    final Options options =
        verify(
              () => dio.get<List<int>>(
                _path,
                options: captureAny(named: 'options'),
              ),
            ).captured.single
            as Options;
    expect(options.responseType, ResponseType.bytes);
  });
}
