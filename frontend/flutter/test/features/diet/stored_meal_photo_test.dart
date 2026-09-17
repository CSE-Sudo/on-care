// 저장된 끼니 사진 썸네일 (#699).
//
// 실서버에서는 회원이 올린 사진이 여기로 온다. 사진 경로는 인증이 걸려 있어
// 앱의 Dio 로 읽어야 하고, 못 읽는 경우(사진 없음·실패)에는 기존 썸네일이
// 그대로 보여야 한다 — 사진이 없다고 카드가 비면 안 된다.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/presentation/widgets/stored_meal_photo.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

class _MockDio extends Mock implements Dio {}

const String _path = '/diet/photos/dietpic-1';
const String _fallbackText = '🍚';

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

Future<void> _pump(WidgetTester tester, Dio dio) async {
  final container = ProviderContainer(
    overrides: <Override>[dioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        // 사진의 대체 텍스트를 로케일에서 읽는다(#1942).
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: StoredMealPhoto(
            path: _path,
            width: 52,
            height: 52,
            fallback: Text(_fallbackText),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
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

  Response<List<int>> ok(List<int> body) => Response<List<int>>(
    requestOptions: RequestOptions(path: _path),
    statusCode: 200,
    data: body,
  );

  group('DietEntry', () {
    test('실서버 응답의 사진 경로를 읽는다', () {
      final DietEntry entry = DietEntry.fromJson(<String, Object?>{
        'id': 'diet-1',
        'meal_type': 'lunch',
        'time_label': '12:30',
        'foods': <Object?>[],
        'total_calories': 620,
        'photo_url': _path,
      });

      expect(entry.photoUrl, _path);
    });

    test('사진이 없는 기록은 null 이다 — 사진 저장 이전 기록이 그렇다', () {
      final DietEntry entry = DietEntry.fromJson(<String, Object?>{
        'id': 'diet-2',
        'meal_type': 'dinner',
        'time_label': '19:00',
        'foods': <Object?>[],
        'total_calories': 500,
      });

      expect(entry.photoUrl, isNull);
    });
  });

  group('StoredMealPhoto', () {
    testWidgets('사진이 오면 대체 썸네일 대신 사진을 그린다', (tester) async {
      stub(() => ok(_pngBytes));

      await _pump(tester, dio);

      expect(find.byType(Image), findsOneWidget);
      expect(find.text(_fallbackText), findsNothing);
    });

    testWidgets('사진을 못 읽으면 기존 썸네일로 돌아간다', (tester) async {
      stub(
        () => DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );

      await _pump(tester, dio);

      expect(find.text(_fallbackText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('로딩 중에도 카드는 대체 썸네일로 채워져 있다', (tester) async {
      when(
        () => dio.get<List<int>>(_path, options: any(named: 'options')),
      ).thenAnswer(
        (_) => Future<Response<List<int>>>.delayed(
          const Duration(seconds: 1),
          () => ok(_pngBytes),
        ),
      );

      final container = ProviderContainer(
        overrides: <Override>[dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: StoredMealPhoto(
                path: _path,
                width: 52,
                height: 52,
                fallback: Text(_fallbackText),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(_fallbackText), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
