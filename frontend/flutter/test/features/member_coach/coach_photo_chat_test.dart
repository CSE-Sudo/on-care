/// 트레이너 채팅에서 사진 보내기 — 입력줄 버튼·고르는 길·보내는 중·실패·말풍선.
/// (#1665)
///
/// 사진을 여는 길은 식단 추가와 같다. 네이티브는 보관함·카메라를 시트에서
/// 고르고, 웹은 브라우저 메뉴가 그 둘을 묻기 때문에 바로 보관함 입력을 연다
/// (#1433). 보내는 동안과 실패는 대화 끝의 내 말풍선이 보여 준다.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/domain/repositories/meal_photo_picker.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/coach_photo_send_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_image_attachment.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_photo_picker.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _demo = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost',
  useMockApi: true,
);

/// 1×1 투명 PNG — 실제로 그려지는 사진.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

/// 어느 갈래로 열었는지 적어 두고, 정해 둔 결과를 돌려주는 선택기.
class _FakePicker implements MealPhotoPicker {
  _FakePicker({this.result, this.failure});

  final MealPhoto? result;
  final MealPhotoFailure? failure;
  final List<MealPhotoSource> sources = <MealPhotoSource>[];

  @override
  Future<MealPhoto?> pick(MealPhotoSource source) async {
    sources.add(source);
    if (failure case final MealPhotoFailure f?) throw MealPhotoException(f);
    return result;
  }
}

/// 사진 전송을 붙잡아 두거나 실패시키는 데모 저장소.
class _PhotoRepository extends MockMemberCoachRepository {
  _PhotoRepository({this.failures = 0});

  int failures;
  Completer<void>? gate;
  final List<String> requestIds = <String>[];

  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) async {
    requestIds.add(clientRequestId);
    final Completer<void>? wait = gate;
    if (wait != null) await wait.future;
    if (failures > 0) {
      failures -= 1;
      throw const NetworkError();
    }
    return super.sendPhoto(
      bytes,
      fileName: fileName,
      mimeType: mimeType,
      clientRequestId: clientRequestId,
      text: text,
    );
  }
}

Future<AppLocalizations> _pumpChat(
  WidgetTester tester, {
  required _FakePicker picker,
  _PhotoRepository? coach,
  MealPhotoChoiceLayout layout = MealPhotoChoiceLayout.separate,
  Locale locale = const Locale('ko'),
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(_demo),
        memberCoachRepositoryProvider.overrideWithValue(
          coach ?? _PhotoRepository(),
        ),
        mealPhotoPickerProvider.overrideWithValue(picker),
        mealPhotoChoiceLayoutProvider.overrideWithValue(layout),
        coachPhotoRequestIdProvider.overrideWithValue(() => 'photo-1'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrainerChatPage(trainerName: '김트레이너'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(TrainerChatPage)));
}

/// 알림이 사라질 때까지 흘려보낸다 — 남은 타이머가 있으면 테스트가 실패한다.
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

Finder get _sending =>
    find.byKey(const ValueKey<String>('coach-pending-photo-sending'));
Finder get _failed =>
    find.byKey(const ValueKey<String>('coach-pending-photo-failed'));

void main() {
  group('입력줄 버튼', () {
    testWidgets('입력줄에 사진 보내기 버튼이 있다', (tester) async {
      final AppLocalizations l = await _pumpChat(tester, picker: _FakePicker());

      final Finder attach = find.byTooltip(l.coachPhotoAttach);
      expect(attach, findsOneWidget);
      // 입력줄 안에 있다 — 대화 위에 떠 있는 버튼이 아니다.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('member-chat-input')),
          matching: attach,
        ),
        findsOneWidget,
      );
      // 보내기와 같은 높이 — 입력줄 버튼들의 한 변이 어긋나면 줄이 뒤뚱거린다.
      expect(
        tester.getSize(attach).height,
        tester.getSize(find.byTooltip(l.a11ySendMessage)).height,
      );
    });

    testWidgets('영어 화면에서는 버튼 이름도 영어다', (tester) async {
      await _pumpChat(
        tester,
        picker: _FakePicker(),
        locale: const Locale('en'),
      );

      expect(find.byTooltip('Send a photo'), findsOneWidget);
    });
  });

  group('고르는 길', () {
    testWidgets('네이티브는 보관함과 카메라를 시트에서 고른다', (tester) async {
      final _FakePicker picker = _FakePicker();
      final AppLocalizations l = await _pumpChat(tester, picker: picker);

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();

      expect(find.byKey(CoachPhotoSourceSheet.sheetKey), findsOneWidget);
      expect(find.text(l.coachPhotoSheetSubtitle), findsOneWidget);
      expect(find.text(l.dietPickPhoto), findsOneWidget);
      expect(find.text(l.dietTakePhoto), findsOneWidget);
      // 시트를 연 것만으로는 선택기를 열지 않는다.
      expect(picker.sources, isEmpty);
    });

    testWidgets('카메라를 고르면 카메라로 연다', (tester) async {
      final _FakePicker picker = _FakePicker();
      final AppLocalizations l = await _pumpChat(tester, picker: picker);

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CoachPhotoSourceSheet.cameraKey));
      await tester.pumpAndSettle();

      expect(picker.sources, <MealPhotoSource>[MealPhotoSource.camera]);
      expect(find.byKey(CoachPhotoSourceSheet.sheetKey), findsNothing);
    });

    testWidgets('웹은 시트 없이 바로 보관함 입력을 연다(#1433)', (tester) async {
      final _FakePicker picker = _FakePicker();
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: picker,
        layout: MealPhotoChoiceLayout.systemMenu,
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();

      expect(find.byKey(CoachPhotoSourceSheet.sheetKey), findsNothing);
      expect(picker.sources, <MealPhotoSource>[MealPhotoSource.gallery]);
    });

    testWidgets('고르지 않고 닫으면 아무것도 보내지 않는다', (tester) async {
      final _PhotoRepository coach = _PhotoRepository();
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(),
        coach: coach,
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CoachPhotoSourceSheet.galleryKey));
      await tester.pumpAndSettle();

      expect(coach.requestIds, isEmpty);
      expect(_sending, findsNothing);
    });

    testWidgets('권한이 없으면 까닭을 알리고 보내지 않는다', (tester) async {
      final _PhotoRepository coach = _PhotoRepository();
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(failure: MealPhotoFailure.photoPermissionDenied),
        coach: coach,
        layout: MealPhotoChoiceLayout.systemMenu,
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l.coachPhotoPermissionDenied), findsOneWidget);
      expect(coach.requestIds, isEmpty);
      await _drainToasts(tester);
    });

    testWidgets('서버 한도(6MB)보다 큰 사진은 올리기 전에 거른다', (tester) async {
      final Uint8List big = Uint8List(CoachPhotoSendController.maxBytes + 1)
        ..setRange(0, _png.length, _png);
      final _PhotoRepository coach = _PhotoRepository();
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(result: MealPhoto.fromBytes(big)),
        coach: coach,
        layout: MealPhotoChoiceLayout.systemMenu,
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l.dietPhotoTooLarge), findsOneWidget);
      expect(coach.requestIds, isEmpty);
      await _drainToasts(tester);
    });

    test('실패 까닭마다 회원에게 할 말이 있다', () async {
      final AppLocalizations l = await AppLocalizations.delegate.load(
        const Locale('ko'),
      );
      for (final MealPhotoFailure f in MealPhotoFailure.values) {
        expect(coachPhotoFailureMessage(l, f), isNotEmpty, reason: f.name);
      }
      // 식단 문구의 "음식 사진"을 쓰지 않는다 — 자세·인바디 사진도 보낸다.
      expect(
        coachPhotoFailureMessage(l, MealPhotoFailure.cameraPermissionDenied),
        isNot(contains('음식')),
      );
    });
  });

  group('보내기', () {
    testWidgets('고른 사진이 내 말풍선으로 대화에 들어간다', (tester) async {
      final _PhotoRepository coach = _PhotoRepository();
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(result: MealPhoto.fromBytes(_png)),
        coach: coach,
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CoachPhotoSourceSheet.galleryKey));
      await tester.pumpAndSettle();

      expect(coach.requestIds, hasLength(1));
      final List<CoachMessage> chat = await coach.fetchChat();
      final CoachMessage sent = chat.last;
      expect(sent.fromMe, isTrue);
      final Finder image = find.byKey(
        ValueKey<String>('coach-image-${sent.attachment!.fileId}'),
      );
      expect(image, findsOneWidget);
      // 내 말풍선 줄에 있다.
      expect(
        find.descendant(
          of: find.byKey(ValueKey<String>('coach-message-${sent.id}')),
          matching: image,
        ),
        findsOneWidget,
      );
      // 내 사진은 내 사진이라고 읽힌다.
      expect(tester.widget<Image>(image).semanticLabel, l.a11yMyPhoto);
      expect(_sending, findsNothing);
      expect(_failed, findsNothing);
    });

    testWidgets('보내는 동안 말풍선 아래에 보내는 중이라 적는다', (tester) async {
      final _PhotoRepository coach = _PhotoRepository()
        ..gate = Completer<void>();
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(result: MealPhoto.fromBytes(_png)),
        coach: coach,
        layout: MealPhotoChoiceLayout.systemMenu,
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pump();
      await tester.pump();

      expect(_sending, findsOneWidget);
      expect(find.text(l.coachPhotoSending), findsOneWidget);
      // 올리는 동안에도 고른 사진이 보인다 — 서버에 없으니 가진 바이트로 그린다.
      expect(
        find.byKey(const ValueKey<String>('coach-image-photo-1')),
        findsOneWidget,
      );

      coach.gate!.complete();
      await tester.pumpAndSettle();

      expect(_sending, findsNothing);
      final CoachMessage sent = (await coach.fetchChat()).last;
      expect(
        find.byKey(ValueKey<String>('coach-image-${sent.attachment!.fileId}')),
        findsOneWidget,
      );
    });

    testWidgets('실패하면 다시 보내기로 같은 사진을 한 번만 보낸다', (tester) async {
      final _PhotoRepository coach = _PhotoRepository(failures: 1);
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(result: MealPhoto.fromBytes(_png)),
        coach: coach,
        layout: MealPhotoChoiceLayout.systemMenu,
      );
      final int before = (await coach.fetchChat()).length;

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();

      expect(_failed, findsOneWidget);
      expect(find.text(l.coachPhotoSendFailed), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('coach-pending-photo-retry')),
      );
      await tester.pumpAndSettle();

      expect(_failed, findsNothing);
      expect(coach.requestIds, hasLength(2));
      expect(coach.requestIds.toSet(), hasLength(1));
      expect(await coach.fetchChat(), hasLength(before + 1));
    });

    testWidgets('실패한 사진을 지우면 대화에서 사라지고 보내지 않는다', (tester) async {
      final _PhotoRepository coach = _PhotoRepository(failures: 1);
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(result: MealPhoto.fromBytes(_png)),
        coach: coach,
        layout: MealPhotoChoiceLayout.systemMenu,
      );
      final int before = (await coach.fetchChat()).length;

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('coach-pending-photo-discard')),
      );
      await tester.pumpAndSettle();

      expect(_failed, findsNothing);
      expect(coach.requestIds, hasLength(1));
      expect(await coach.fetchChat(), hasLength(before));
    });

    testWidgets('영어 화면의 실패 안내와 버튼', (tester) async {
      final AppLocalizations l = await _pumpChat(
        tester,
        picker: _FakePicker(result: MealPhoto.fromBytes(_png)),
        coach: _PhotoRepository(failures: 1),
        layout: MealPhotoChoiceLayout.systemMenu,
        locale: const Locale('en'),
      );

      await tester.tap(find.byTooltip(l.coachPhotoAttach));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't send the photo"), findsOneWidget);
      expect(find.text('Send again'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    });
  });

  group('말풍선', () {
    Future<void> pumpBubble(
      WidgetTester tester,
      CoachAttachment attachment, {
      bool mine = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            // 받아 오면 안 되는 자리 — 불리면 사진 대신 실패 자리가 남는다.
            coachImageProvider(
              attachment.downloadPath,
            ).overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CoachImageAttachment(attachment: attachment, mine: mine),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('가진 바이트가 있으면 받아 오지 않고 그린다', (tester) async {
      await pumpBubble(
        tester,
        CoachAttachment(
          kind: CoachAttachmentKind.image,
          fileName: 'photo.png',
          fileId: 'local-1',
          fileSize: _png.length,
          downloadPath: '/chat/attachments/local-1',
          localBytes: _png,
        ),
        mine: true,
      );

      final Finder image = find.byKey(
        const ValueKey<String>('coach-image-local-1'),
      );
      expect(image, findsOneWidget);
      expect(tester.widget<Image>(image).semanticLabel, '내가 보낸 사진');
      expect(find.text('사진을 불러오지 못했어요'), findsNothing);
    });

    testWidgets('트레이너 사진은 지금처럼 받아 와서 그린다', (tester) async {
      await pumpBubble(
        tester,
        const CoachAttachment(
          kind: CoachAttachmentKind.image,
          fileName: 'pose.png',
          fileId: 'file-1',
          fileSize: 10,
          downloadPath: '/chat/attachments/file-1',
        ),
      );

      // 받아 온 것이 없으니 실패 자리가 남는다 — 가진 바이트를 쓰지 않았다는 뜻.
      expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
    });
  });
}
