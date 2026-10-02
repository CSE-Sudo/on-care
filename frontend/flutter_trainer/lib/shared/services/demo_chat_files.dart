import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:oncare_trainer/shared/models/client_chat_message.dart';
import 'package:pdf/widgets.dart' as pw;

/// 데모 대화에서 **회원이 보낸** 첨부(#2669).
///
/// 실서버 대화에는 회원이 올린 식단 사진·병원 서류가 섞여 있다. 데모 시드에
/// 그런 메시지가 없으면 트레이너 웹의 사진 말풍선과 PDF 카드가 데모에서 한
/// 번도 보이지 않는다. 시드는 메시지 id 에 이 표시([demoChatFileKeyPrefix])를
/// 남기고, 대화를 읽을 때 바이트를 만든다 — 사진은 앱 번들의 식단 사진을,
/// PDF 는 그 자리에서 그린 한 쪽짜리 문서를 쓴다. 바이트를 로컬 DB 에 넣지
/// 않으므로 시드가 무거워지지 않는다.
const String demoChatFileKeyPrefix = 'chat_file_';

/// 루틴 전송 안내(#2672) 표시 행의 머리. 메시지 id 뒤에 붙고, 값은 안내 JSON
/// (`RoutineDeliveryNotice.toJson`) 이다. 데모 대화 표에 칸을 늘리지 않고 리포트
/// 안내(`report_msg_`)처럼 키-값 표에 둔다.
const String demoRoutineDeliveryKeyPrefix = 'routine_msg_';

/// 시드가 남기는 첨부 표시 한 건.
///
/// [asset] 은 사진일 때 앱 번들 경로다. PDF 는 [lines] 를 한 줄씩 적은 한 쪽
/// 문서로 만든다. 문서 글은 PDF 기본 서체(라틴 문자)만 쓴다 — 한글 서체를 PDF
/// 에 싣는 일은 리포트 PDF 의 몫이고, 병원 소견서 같은 서류는 영문인 경우가
/// 흔하다.
String encodeDemoChatFile({
  required ChatAttachmentKind kind,
  required String name,
  String? asset,
  List<String> lines = const <String>[],
}) => jsonEncode(<String, Object?>{
  'kind': kind.name,
  'name': name,
  'asset': ?asset,
  if (lines.isNotEmpty) 'lines': lines,
});

/// [stored] 표시를 첨부로 푼다. 읽지 못하면 null — 말풍선의 글은 그대로 남는다.
Future<ChatAttachment?> decodeDemoChatFile(
  String messageId,
  String stored,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final ChatAttachmentKind? kind = ChatAttachmentKind.parse(decoded['kind']);
  final Object? name = decoded['name'];
  if (kind == null || name is! String) return null;
  final Uint8List bytes;
  try {
    bytes = switch (kind) {
      ChatAttachmentKind.image => await _asset(decoded['asset']),
      // 번들에 든 PDF 가 있으면 그것을, 없으면 적힌 줄로 한 쪽을 그린다(#2663).
      ChatAttachmentKind.pdf =>
        decoded['asset'] is String
            ? await _asset(decoded['asset'])
            : await _pdf(decoded['lines']),
    };
  } on Object {
    return null;
  }
  final String fileId = 'demo-file-$messageId';
  return ChatAttachment(
    kind: kind,
    fileName: name,
    fileId: fileId,
    fileSize: bytes.length,
    downloadPath: '/chat/attachments/$fileId',
    localBytes: bytes,
  );
}

Future<Uint8List> _asset(Object? path) async {
  if (path is! String) throw const FormatException('asset');
  final ByteData data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Uint8List> _pdf(Object? lines) async {
  final List<String> text = lines is List
      ? lines.whereType<String>().toList(growable: false)
      : const <String>[];
  final pw.Document doc = pw.Document();
  doc.addPage(
    pw.Page(
      // 제목·문단은 pdf 기본 서식(Header·Paragraph)에 맡긴다 — 앱 화면이 아니라
      // 서류 모양이라 앱 토큰을 쓸 자리가 아니다.
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          if (text.isNotEmpty) pw.Header(text: text.first),
          for (final String line in text.skip(1)) pw.Paragraph(text: line),
        ],
      ),
    ),
  );
  return doc.save();
}
