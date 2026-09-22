import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';

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

/// Plays back one picker outcome: a photo, a cancel (null), or a failure.
class _FakeMealPhotoPicker implements MealPhotoPicker {
  _FakeMealPhotoPicker({this.photo, this.failure});

  final MealPhoto? photo;
  final MealPhotoFailure? failure;
  MealPhotoSource? requestedSource;
  int calls = 0;

  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async {
    calls += 1;
    requestedSource = source;
    if (failure != null) throw MealPhotoException(failure!);
    return photo;
  }
}

/// Picker whose completion the test controls, so the sheet can be dismissed
/// while the OS picker is still "open".
class _PendingMealPhotoPicker implements MealPhotoPicker {
  final Completer<MealPhoto?> completer = Completer<MealPhoto?>();

  @override
  Future<MealPhoto?> pick(MealPhotoSource source) => completer.future;
}

class _RecordingDietRepository extends FakeDietRepository {
  MealPhoto? uploaded;

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) {
    uploaded = photo;
    return super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: idempotencyKey,
    );
  }
}

Future<void> _pumpAddSheet(
  WidgetTester tester, {
  required MealPhotoPicker picker,
  required _RecordingDietRepository repository,
  MealPhotoChoiceLayout layout = MealPhotoChoiceLayout.separate,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        mealPhotoPickerProvider.overrideWithValue(picker),
        mealPhotoChoiceLayoutProvider.overrideWithValue(layout),
        dietRepositoryProvider.overrideWithValue(repository),
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
}

void main() {
  testWidgets('카메라로 촬영한 사진은 형식에 맞는 MIME 으로 분석 요청된다', (
    WidgetTester tester,
  ) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
      photo: MealPhoto.fromBytes(_jpegBytes)!,
    );
    final _RecordingDietRepository repository = _RecordingDietRepository();
    await _pumpAddSheet(tester, picker: picker, repository: repository);

    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();

    expect(picker.requestedSource, MealPhotoSource.camera);
    expect(repository.uploaded?.filename, 'meal.jpg');
    expect(repository.uploaded?.mimeType, 'image/jpeg');
    expect(find.text('분석 완료!'), findsOneWidget);
  });

  testWidgets('보관함에서 고른 PNG 는 png 확장자·MIME 으로 올라간다', (
    WidgetTester tester,
  ) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
      photo: MealPhoto.fromBytes(
        Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]),
      )!,
    );
    final _RecordingDietRepository repository = _RecordingDietRepository();
    await _pumpAddSheet(tester, picker: picker, repository: repository);

    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();

    expect(picker.requestedSource, MealPhotoSource.gallery);
    expect(repository.uploaded?.filename, 'meal.png');
    expect(repository.uploaded?.mimeType, 'image/png');
  });

  testWidgets('웹은 사진 추가 한 갈래만 두고 촬영을 앱에서 따로 내놓지 않는다(#1433)', (
    WidgetTester tester,
  ) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
      photo: MealPhoto.fromBytes(_jpegBytes)!,
    );
    final _RecordingDietRepository repository = _RecordingDietRepository();
    await _pumpAddSheet(
      tester,
      picker: picker,
      repository: repository,
      layout: MealPhotoChoiceLayout.systemMenu,
    );

    // 브라우저 시스템 메뉴가 보관함·촬영·파일을 묻는다 — 앱에 촬영이 또 있으면 겹친다.
    expect(find.text('사진 찍기'), findsNothing);
    expect(find.text('사진 선택'), findsNothing);

    await tester.tap(find.text('사진 추가'));
    await tester.pumpAndSettle();

    expect(picker.requestedSource, MealPhotoSource.gallery);
    expect(repository.uploaded?.mimeType, 'image/jpeg');
    expect(
      MealPhotoChoiceLayout.forPlatform(isWeb: true),
      MealPhotoChoiceLayout.systemMenu,
    );
    expect(
      MealPhotoChoiceLayout.forPlatform(isWeb: false),
      MealPhotoChoiceLayout.separate,
    );
  });

  testWidgets('촬영을 취소하면 오류 없이 추가 시트에 머무른다', (WidgetTester tester) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker();
    final _RecordingDietRepository repository = _RecordingDietRepository();
    await _pumpAddSheet(tester, picker: picker, repository: repository);

    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();

    expect(repository.uploaded, isNull);
    // 취소는 오류가 아니므로 안내를 띄우지 않는다.
    expect(find.byKey(const Key('dietPhotoFailureNotice')), findsNothing);
    // 시트가 닫히지 않아 바로 다시 시도할 수 있다.
    expect(find.byKey(const Key('dietAddSheet')), findsOneWidget);
  });

  testWidgets('일반 권한 거부는 재시도를 안내하고 설정 링크를 표시하지 않는다', (
    WidgetTester tester,
  ) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
      failure: MealPhotoFailure.cameraPermissionDenied,
    );
    final _RecordingDietRepository repository = _RecordingDietRepository();
    await _pumpAddSheet(tester, picker: picker, repository: repository);

    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 시트에 가려지지 않도록 안내를 시트 안에 그린다.
    expect(find.byKey(const Key('dietPhotoFailureNotice')), findsOneWidget);
    expect(find.textContaining('카메라 권한이 필요해요'), findsOneWidget);
    expect(find.text('설정 열기'), findsNothing);
    expect(repository.uploaded, isNull);
    expect(find.byKey(const Key('dietAddSheet')), findsOneWidget);

    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    expect(picker.calls, 2);
  });

  testWidgets('iOS 영구 거부는 설정 안내와 설정 링크를 표시한다', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
        failure: MealPhotoFailure.cameraPermissionPermanentlyDenied,
      );
      final _RecordingDietRepository repository = _RecordingDietRepository();
      await _pumpAddSheet(tester, picker: picker, repository: repository);

      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();

      expect(find.textContaining('설정에서 카메라를 켜면'), findsOneWidget);
      expect(find.text('설정 열기'), findsOneWidget);
      expect(find.byKey(const Key('dietAddSheet')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('restricted는 정책 안내만 표시하고 설정 링크를 표시하지 않는다', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
        failure: MealPhotoFailure.photoPermissionRestricted,
      );
      final _RecordingDietRepository repository = _RecordingDietRepository();
      await _pumpAddSheet(tester, picker: picker, repository: repository);

      await tester.tap(find.text('사진 선택'));
      await tester.pumpAndSettle();

      expect(find.textContaining('기기 설정이나 관리 정책'), findsOneWidget);
      expect(find.text('설정 열기'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('서버가 받지 않는 형식은 형식 안내 메시지를 보여준다', (WidgetTester tester) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
      failure: MealPhotoFailure.unsupportedFormat,
    );
    final _RecordingDietRepository repository = _RecordingDietRepository();
    await _pumpAddSheet(tester, picker: picker, repository: repository);

    await tester.tap(find.text('사진 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('지원하지 않는 사진 형식'), findsOneWidget);
    expect(repository.uploaded, isNull);
  });

  testWidgets('사진 선택 중 시트를 닫으면 아래 화면을 대신 pop 하지 않는다', (
    WidgetTester tester,
  ) async {
    final _PendingMealPhotoPicker picker = _PendingMealPhotoPicker();
    final _RecordingDietRepository repository = _RecordingDietRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mealPhotoPickerProvider.overrideWithValue(picker),
          dietRepositoryProvider.overrideWithValue(repository),
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext inner) => Scaffold(
                        body: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text('식단 화면'),
                              ElevatedButton(
                                onPressed: () => showDietAddSheet(inner),
                                child: const Text('open'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 촬영을 시작한다 — 픽커는 완료되지 않고 대기 상태로 남는다.
    await tester.tap(find.text('사진 찍기'));
    await tester.pump();

    // OS 픽커가 떠 있는 동안 사용자가 시트를 닫는다 — 닫기 X 가 없으므로
    // 바깥을 눌러 닫는다(#2151).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dietAddSheet')), findsNothing);

    // 그 뒤에 픽커가 사진을 들고 돌아온다.
    picker.completer.complete(MealPhoto.fromBytes(_jpegBytes));
    await tester.pumpAndSettle();

    // 시트가 이미 닫혔으므로 pop 대상이 없다 — 아래 식단 화면이 그대로 있어야 한다.
    expect(find.text('식단 화면'), findsOneWidget);
    expect(find.text('go'), findsNothing);
    expect(repository.uploaded, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('분석 API 가 실패해도 같은 사진으로 다시 시도할 수 있다', (WidgetTester tester) async {
    final _FakeMealPhotoPicker picker = _FakeMealPhotoPicker(
      photo: MealPhoto.fromBytes(_jpegBytes)!,
    );
    final _FailingOnceDietRepository repository = _FailingOnceDietRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mealPhotoPickerProvider.overrideWithValue(picker),
          dietRepositoryProvider.overrideWithValue(repository),
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

    expect(find.text('분석 실패'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('분석 완료!'), findsOneWidget);
  });
}

class _FailingOnceDietRepository extends FakeDietRepository {
  int calls = 0;

  @override
  Future<DietAnalysisResult> analyze({
    required MealPhoto photo,
    required String mealType,
    String? idempotencyKey,
  }) {
    calls += 1;
    if (calls == 1) throw StateError('network down');
    return super.analyze(
      photo: photo,
      mealType: mealType,
      idempotencyKey: idempotencyKey,
    );
  }
}
