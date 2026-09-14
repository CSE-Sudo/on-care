import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/app/session_feature_reset.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/fake_diet_repository.dart';

final Uint8List _jpegBytes = Uint8List.fromList(<int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
]);

MealPhoto get _photo => MealPhoto.fromBytes(_jpegBytes)!;

class _FixedPicker implements MealPhotoPicker {
  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async => _photo;
}

/// Fails every analyze with the given HTTP status, counting attempts so a
/// test can prove whether the button actually re-sent the request.
class _FailingDietRepository extends FakeDietRepository {
  _FailingDietRepository(this.statusCode);

  final int statusCode;
  int attempts = 0;

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) async {
    attempts += 1;
    throw AppError.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/diet/analyze'),
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: RequestOptions(path: '/diet/analyze'),
          statusCode: statusCode,
        ),
      ),
    );
  }
}

Future<ProviderContainer> _openResultSheet(
  WidgetTester tester,
  _FailingDietRepository repository,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      mealPhotoPickerProvider.overrideWithValue(_FixedPicker()),
      dietRepositoryProvider.overrideWithValue(repository),
      // signOut() 이 각 기능의 상태를 초기화한다. 실제 구현은 drift 등 플랫폼
      // 의존이 있어 위젯 테스트에서는 표준 오버라이드를 쓴다(widget_test 와 동일).
      sessionFeatureResetOverride(),
    ],
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
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDietAddSheet(context),
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
  await tester.tap(find.text('사진 찍기'));
  await tester.pumpAndSettle();
  return container;
}

String _actionLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('dietAnalysisFailureAction')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  setUp(() {
    // signOut() 은 보안 저장소를 await 한다. 플랫폼 채널이 없는 위젯 테스트에서는
    // 그대로 멈추므로, session_controller_test 와 같은 방식으로 목을 깐다.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('415 는 형식 문제를 알리고 재시도 대신 다른 사진을 유도한다', (
    WidgetTester tester,
  ) async {
    final _FailingDietRepository repo = _FailingDietRepository(415);
    await _openResultSheet(tester, repo);

    expect(find.textContaining('이 사진 형식은 분석할 수 없어요'), findsOneWidget);
    expect(_actionLabel(tester), '다른 사진 고르기');
    expect(repo.attempts, 1);

    // 같은 사진 재전송이 아니라 사진 선택 시트로 돌아간다.
    await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
    await tester.pumpAndSettle();
    expect(repo.attempts, 1, reason: '같은 사진을 다시 보내면 또 415 다');
    expect(find.byKey(const Key('dietAddSheet')), findsOneWidget);
  });

  testWidgets('400 도 사진 문제이므로 다시 고르기로 유도한다', (WidgetTester tester) async {
    final _FailingDietRepository repo = _FailingDietRepository(400);
    await _openResultSheet(tester, repo);

    expect(find.textContaining('사진을 읽지 못했어요'), findsOneWidget);
    expect(_actionLabel(tester), '다른 사진 고르기');
  });

  testWidgets('401 은 재시도가 아니라 로그인 화면으로 데려간다', (WidgetTester tester) async {
    final _FailingDietRepository repo = _FailingDietRepository(401);
    final ProviderContainer container = await _openResultSheet(tester, repo);

    expect(find.textContaining('로그인이 만료됐어요'), findsOneWidget);
    expect(_actionLabel(tester), '다시 로그인');

    await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
    await tester.pumpAndSettle();

    // 죽은 토큰을 지우는 것이 핵심이다 — 세션이 authenticated 로 남아 있으면
    // 라우터 가드가 로그인 화면에서 도로 튕겨낸다(app_router.dart sessionRedirect).
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(repo.attempts, 1, reason: '같은 토큰으로 다시 보내도 또 401 이다');
  });

  testWidgets('501 은 분석 기능 부재를 알린다', (WidgetTester tester) async {
    final _FailingDietRepository repo = _FailingDietRepository(501);
    await _openResultSheet(tester, repo);

    expect(find.textContaining('사진 분석을 사용할 수 없어요'), findsOneWidget);
    expect(_actionLabel(tester), '닫기');
  });

  testWidgets('502 는 일시 실패이므로 같은 사진으로 재시도를 제공한다', (WidgetTester tester) async {
    final _FailingDietRepository repo = _FailingDietRepository(502);
    await _openResultSheet(tester, repo);

    expect(find.textContaining('잠시 후 다시 시도'), findsOneWidget);
    expect(_actionLabel(tester), '다시 시도');

    await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
    await tester.pumpAndSettle();
    expect(repo.attempts, 2, reason: '재시도는 실제로 다시 전송해야 한다');
  });

  testWidgets('500 등 기타 서버 오류도 재시도 가능하게 둔다', (WidgetTester tester) async {
    final _FailingDietRepository repo = _FailingDietRepository(500);
    await _openResultSheet(tester, repo);

    expect(_actionLabel(tester), '다시 시도');
    await tester.tap(find.byKey(const Key('dietAnalysisFailureAction')));
    await tester.pumpAndSettle();
    expect(repo.attempts, 2);
  });
}
