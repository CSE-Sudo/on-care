/// 분석 결과 시트를 어떻게 닫든, 기록이 남아 있으면 저장 성공이다. (#2627)
///
/// 사진 분석 요청이 서버에 기록을 남기고 포인트까지 적립한다. 그런데 시트는
/// `저장` 으로 닫힐 때만 저장으로 보고, 아래 버튼·끌어내려 닫기는 실패로
/// 돌려줬다 — 하단 `+` 로 시작한 흐름이 식단 탭으로 옮겨 가지 않았다.
/// `다른 사진 고르기` 는 새 흐름의 결과를 버렸다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';
import '../../helpers/fixed_clock.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async =>
      MealPhoto.fromBytes(_jpegBytes)!;
}

AppError _httpError(int status) => AppError.fromDio(
  DioException(
    requestOptions: RequestOptions(path: '/diet/analyze'),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: '/diet/analyze'),
      statusCode: status,
    ),
  ),
);

/// 앞의 [failures] 번은 [status] 로 실패하고, 그 뒤로는 대역대로 저장한다.
class _FailThenSaveRepository extends FakeDietRepository {
  _FailThenSaveRepository({required this.failures, required this.status});

  final int failures;
  final int status;
  int attempts = 0;

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
    String? date,
  }) async {
    attempts += 1;
    if (attempts <= failures) throw _httpError(status);
    return super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: idempotencyKey,
    );
  }
}

/// 흐름이 끝난 결과. 테스트마다 새로 채운다.
final List<bool> _results = <bool>[];

Future<void> _pumpApp(WidgetTester tester, FakeDietRepository repo) async {
  _results.clear();
  useFixedKstDate(DateTime(2026, 8, 20, 9));
  await tester.binding.setSurfaceSize(const Size(500, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
        dietRepositoryProvider.overrideWithValue(repo),
        sessionFeatureResetOverride(),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    _results.add(await showDietAddSheet(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `open` → `사진 찍기` → 분석이 끝날 때까지.
Future<void> _analyze(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('사진 찍기'));
  await tester.pumpAndSettle();
}

/// 시트를 끌어내려 닫는 것과 같다 — 값 없이 닫힌다.
Future<void> _dismissSheet(WidgetTester tester, Finder inside) async {
  Navigator.of(tester.element(inside)).pop();
  await tester.pumpAndSettle();
}

Future<void> _tapFooter(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('DietResultOutcome', () {
    test('값 없이 닫히면 분석 성공 여부를 돌려준다', () {
      final DietResultOutcome outcome = DietResultOutcome();
      expect(outcome.resolve(null), isFalse);
      outcome.saved = true;
      expect(outcome.resolve(null), isTrue);
    });

    test('명시적인 true/false 는 그대로 둔다', () {
      final DietResultOutcome outcome = DietResultOutcome()..saved = true;
      // 결과 시트에서 기록을 지우면 false 로 닫힌다.
      expect(outcome.resolve(false), isFalse);
      outcome.saved = false;
      expect(outcome.resolve(true), isTrue);
    });

    test('bool 이 아닌 값은 분석 성공 여부를 따른다', () {
      final DietResultOutcome outcome = DietResultOutcome()..saved = true;
      expect(outcome.resolve('something'), isTrue);
    });
  });

  group('분석이 성공한 뒤', () {
    testWidgets('`저장` 은 알림과 함께 저장 성공으로 닫힌다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _analyze(tester);

      await _tapFooter(tester, '저장');

      expect(_results, <bool>[true]);
      expect(find.text('식단을 저장했어요'), findsOneWidget);
    });

    testWidgets('`닫기` 도 저장 성공으로 닫힌다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _analyze(tester);

      await _tapFooter(tester, '닫기');

      expect(find.byKey(const Key('diet-result-recognized')), findsNothing);
      expect(_results, <bool>[true]);
    });

    testWidgets('끌어내려 닫아도 저장 성공이다', (WidgetTester tester) async {
      await _pumpApp(tester, FakeDietRepository());
      await _analyze(tester);

      await _dismissSheet(
        tester,
        find.byKey(const Key('diet-result-recognized')),
      );

      expect(find.byKey(const Key('diet-result-recognized')), findsNothing);
      expect(_results, <bool>[true]);
    });

    testWidgets('영어 화면에서는 `Close` 다', (WidgetTester tester) async {
      _results.clear();
      useFixedKstDate(DateTime(2026, 8, 20, 9));
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
            dietRepositoryProvider.overrideWithValue(FakeDietRepository()),
            sessionFeatureResetOverride(),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (BuildContext context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async =>
                        _results.add(await showDietAddSheet(context)),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final AppLocalizations l = AppLocalizations.of(
        tester.element(find.byKey(const Key('dietAddSheet'))),
      );
      await tester.tap(find.text(l.dietTakePhoto));
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      await _tapFooter(tester, 'Close');
      expect(_results, <bool>[true]);
    });
  });

  group('분석이 실패하면', () {
    testWidgets('닫아도 저장 성공이 아니다', (WidgetTester tester) async {
      // 501 은 다시 시도할 수 없어 실패 버튼이 `닫기` 다.
      await _pumpApp(
        tester,
        _FailThenSaveRepository(failures: 1 << 20, status: 501),
      );
      await _analyze(tester);
      expect(
        find.byKey(const Key('dietAnalysisFailureAction')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
      await tester.pumpAndSettle();

      expect(_results, <bool>[false]);
    });

    testWidgets('끌어내려 닫아도 저장 성공이 아니다', (WidgetTester tester) async {
      await _pumpApp(
        tester,
        _FailThenSaveRepository(failures: 1 << 20, status: 502),
      );
      await _analyze(tester);

      await _dismissSheet(
        tester,
        find.byKey(const Key('dietAnalysisFailureAction')),
      );

      expect(_results, <bool>[false]);
    });

    testWidgets('다시 시도해 성공한 뒤 닫으면 저장 성공이다', (WidgetTester tester) async {
      final _FailThenSaveRepository repo = _FailThenSaveRepository(
        failures: 1,
        status: 502,
      );
      await _pumpApp(tester, repo);
      await _analyze(tester);

      await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
      await tester.pumpAndSettle();
      expect(repo.attempts, 2);

      await _tapFooter(tester, '닫기');
      expect(_results, <bool>[true]);
    });
  });

  group('`다른 사진 고르기`', () {
    testWidgets('새 사진으로 저장하면 처음 흐름도 저장 성공으로 끝난다', (WidgetTester tester) async {
      // 415 는 사진 문제라 버튼이 `다른 사진 고르기` 다.
      final _FailThenSaveRepository repo = _FailThenSaveRepository(
        failures: 1,
        status: 415,
      );
      await _pumpApp(tester, repo);
      await _analyze(tester);
      expect(_results, isEmpty);

      await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
      await tester.pumpAndSettle();
      // 사진 선택 시트가 다시 열렸고, 처음 흐름은 아직 끝나지 않았다.
      expect(find.byKey(const Key('dietAddSheet')), findsOneWidget);
      expect(_results, isEmpty);

      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();
      await _tapFooter(tester, '닫기');

      expect(repo.attempts, 2);
      // 흐름은 하나다 — 결과도 하나, 새 흐름의 결과다.
      expect(_results, <bool>[true]);
    });

    testWidgets('다시 연 사진 선택을 닫으면 저장 성공이 아니다', (WidgetTester tester) async {
      await _pumpApp(tester, _FailThenSaveRepository(failures: 1, status: 415));
      await _analyze(tester);
      await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10)); // 스크림
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dietAddSheet')), findsNothing);
      expect(_results, <bool>[false]);
    });
  });
}
