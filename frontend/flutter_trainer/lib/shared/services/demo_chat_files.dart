import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

/// 데모 대화에서 **회원이 보낸** 첨부(#2669).
///
/// 실서버 대화에는 회원이 올린 식단 사진·병원 서류가 섞여 있다. 데모 시드에
/// 그런 메시지가 없으면 트레이너 웹의 사진 말풍선과 PDF 카드가 데모에서 한
/// 번도 보이지 않는다. 시드는 메시지 id 에 이 표시([demoChatFileKeyPrefix])를
/// 남기고, 대화를 읽을 때 앱 번들에서 바이트를 읽는다 — 사진은 식단 사진을,
/// PDF 는 미리 만들어 둔 한 쪽짜리 문서를 쓴다. 바이트를 로컬 DB 에 넣지
/// 않으므로 시드가 무거워지지 않는다.
const String demoChatFileKeyPrefix = 'chat_file_';

/// 루틴 전송 안내(#2672) 표시 행의 머리. 메시지 id 뒤에 붙고, 값은 안내 JSON
/// (`RoutineDeliveryNotice.toJson`) 이다. 데모 대화 표에 칸을 늘리지 않고 리포트
/// 안내(`report_msg_`)처럼 키-값 표에 둔다.
const String demoRoutineDeliveryKeyPrefix = 'routine_msg_';

/// 시드가 남기는 첨부 표시 한 건.
///
/// [asset] 은 앱 번들 경로다. 사진도 PDF 도 번들에 든 파일을 그대로 쓴다.
///
/// PDF 를 실행 중에 그리지 않는 이유(#3416): 문서가 한글인데 pdf 패키지는
/// TrueType 글꼴만 실을 수 있고, 앱이 싣는 Pretendard 는 CFF(OTF)다. 전에는
/// 적힌 줄을 PDF 기본 서체로 그려서 소견서가 영문일 수밖에 없었다.
String encodeDemoChatFile({
  required ChatAttachmentKind kind,
  required String name,
  required String asset,
}) => jsonEncode(<String, Object?>{
  'kind': kind.name,
  'name': name,
  'asset': asset,
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
    // 경로가 없는 옛 표시(줄로 그리던 PDF)는 풀지 않는다 — 시드 키가 올라
    // 다시 시드되면 사라진다.
    bytes = await _asset(decoded['asset']);
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
