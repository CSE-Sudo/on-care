import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/features/clients/data/dtos/chat_dtos.dart';
import 'package:oncare_trainer/features/clients/presentation/widgets/chat_image_attachment.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

/// 1×1 투명 PNG. 파일을 읽어 오지 않고 여기서 만든다.
final Uint8List _png = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, //
  0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1,
  13, 10, 45, 180,
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

const ChatAttachment _image = ChatAttachment(
  kind: ChatAttachmentKind.image,
  fileName: 'pose.png',
  fileId: 'file-1',
  fileSize: 1024,
  downloadPath: '/chat/attachments/file-1',
);

Future<void> _pump(WidgetTester tester, {Uint8List? bytes}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        chatImageProvider(
          _image.downloadPath,
        ).overrideWith((ref) async => bytes),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ChatImageAttachment(attachment: _image)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _message(Map<String, Object?>? attachment) =>
    <String, Object?>{
      'id': 'chat-1',
      'sender': 'trainer',
      'body': '이 자세를 참고해 주세요',
      'time_label': '18:10',
      'created_at': '2026-08-19T18:10:00Z',
      'attachment': attachment,
    };

/// 사진은 대화의 일부다 — 열어야만 보이는 파일이 아니라 말풍선 안에 그린다.
/// (#921)
void main() {
  group('DTO', () {
    test('이미지 첨부를 읽는다', () {
      final ClientChatMessage parsed = chatMessageFromJson(
        _message(<String, Object?>{
          'type': 'image',
          'file_name': 'pose.png',
          'file_id': 'file-1',
          'file_size': 2048,
          'download_path': '/chat/attachments/file-1',
        }),
      );

      expect(parsed.attachment!.isImage, isTrue);
    });

    test('PDF 첨부는 그대로 읽힌다', () {
      final ClientChatMessage parsed = chatMessageFromJson(
        _message(<String, Object?>{
          'type': 'pdf',
          'file_name': 'report.pdf',
          'file_id': 'file-2',
          'file_size': 2048,
          'download_path': '/chat/attachments/file-2',
        }),
      );

      expect(parsed.attachment!.kind, ChatAttachmentKind.pdf);
    });

    test('모르는 종류는 조용히 지나치지 않는다', () {
      expect(
        () => chatMessageFromJson(
          _message(<String, Object?>{
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

    test('첨부가 없는 메시지는 지금과 같다', () {
      expect(chatMessageFromJson(_message(null)).attachment, isNull);
    });
  });

  group('카드', () {
    testWidgets('보낸 사진을 대화 안에 그린다', (tester) async {
      await _pump(tester, bytes: _png);

      expect(
        find.byKey(const ValueKey<String>('chat-image-file-1')),
        findsOneWidget,
      );
    });

    testWidgets('사진을 못 가져와도 대화가 깨지지 않는다', (tester) async {
      await _pump(tester);

      expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
    });
  });
}
