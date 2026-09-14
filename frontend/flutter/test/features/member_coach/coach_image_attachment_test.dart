import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/app/app_theme.dart';
import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_image_attachment.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 1×1 투명 PNG. 파일을 읽어 오지 않고 여기서 만든다.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

const CoachAttachment _image = CoachAttachment(
  kind: CoachAttachmentKind.image,
  fileName: 'pose.png',
  fileId: 'file-1',
  fileSize: 1024,
  downloadPath: '/chat/attachments/file-1',
);

Future<void> _pump(WidgetTester tester, {Uint8List? bytes}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        coachImageProvider(
          _image.downloadPath,
        ).overrideWith((ref) async => bytes),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CoachImageAttachment(attachment: _image)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 트레이너가 보낸 사진은 대화 안에서 보여야 한다. 열어야만 보이는 파일이면
/// 자세를 확인할 때마다 파일을 여는 일이 되고, 그건 채팅에 사진을 붙이는 이유
/// 자체를 없앤다. (#921)
void main() {
  group('DTO', () {
    Map<String, Object?> message(Map<String, Object?>? attachment) =>
        <String, Object?>{
          'id': 'chat-1',
          'sender': 'trainer',
          'body': '이 자세를 참고해 주세요',
          'time_label': '18:10',
          'created_at': '2026-08-19T18:10:00Z',
          'attachment': attachment,
        };

    test('이미지 첨부를 읽는다', () {
      final CoachMessage parsed = coachMessageFromJson(
        message(<String, Object?>{
          'type': 'image',
          'file_name': 'pose.png',
          'file_id': 'file-1',
          'file_size': 2048,
          'download_path': '/chat/attachments/file-1',
        }),
      );

      expect(parsed.attachment!.isImage, isTrue);
      expect(parsed.attachment!.fileName, 'pose.png');
    });

    test('PDF 첨부는 그대로 읽힌다', () {
      final CoachMessage parsed = coachMessageFromJson(
        message(<String, Object?>{
          'type': 'pdf',
          'file_name': 'report.pdf',
          'file_id': 'file-2',
          'file_size': 2048,
          'download_path': '/chat/attachments/file-2',
        }),
      );

      expect(parsed.attachment!.kind, CoachAttachmentKind.pdf);
      expect(parsed.attachment!.isImage, isFalse);
    });

    test('모르는 종류는 조용히 지나치지 않는다', () {
      expect(
        () => coachMessageFromJson(
          message(<String, Object?>{
            'type': 'zip',
            'file_name': 'x.zip',
            'file_id': 'file-3',
            'file_size': 1,
            'download_path': '/chat/attachments/file-3',
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('카드', () {
    testWidgets('받은 사진을 대화 안에 그린다', (tester) async {
      await _pump(tester, bytes: _png);

      expect(
        find.byKey(const ValueKey<String>('coach-image-file-1')),
        findsOneWidget,
      );
    });

    testWidgets('사진을 못 가져와도 대화가 깨지지 않는다', (tester) async {
      await _pump(tester);

      expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
    });
  });
}
