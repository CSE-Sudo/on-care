/// Who sent a chat message.
enum ChatSender {
  /// The trainer (right-aligned bubble).
  trainer,

  /// The client (left-aligned bubble).
  client,
}

/// A single chat message in a client thread. Decoded from the drift
/// `ClientChatMessages` row.
class ClientChatMessage {
  /// Creates a chat message.
  const ClientChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timeLabel,
    required this.createdAt,
    this.attachment,
    this.reportWeekStart,
    this.emoteId,
  });

  /// Row id (`seed-chat-…` for seeds, `chat-…` for runtime replies).
  final String id;

  /// Who sent it.
  final ChatSender sender;

  /// Message text.
  final String body;

  /// Display time label (e.g. 18:10).
  final String timeLabel;

  /// Ordering key.
  final DateTime createdAt;
  final ChatAttachment? attachment;

  /// null이면 그냥 채팅, 값이 있으면 리포트 PDF 전송 안내다 — 그 주의
  /// 월요일. (#1378) 데모/드리프트는 첨부를 저장하지 못해 [attachment] 대신
  /// 이 값으로 안내 말풍선을 구분한다.
  final DateTime? reportWeekStart;

  /// 회원이 보낸 이모티콘이면 그 id. (#2020)
  ///
  /// 트레이너는 이용권 없이도 받은 이모티콘을 본다 — 지난 대화는 기록이다.
  /// 본문(`body`)은 이모티콘을 그리지 못하는 자리(로스터의 마지막 메시지)가
  /// 읽는 글이라 함께 온다.
  final String? emoteId;

  /// Whether this message was sent by the trainer.
  bool get fromTrainer => sender == ChatSender.trainer;
}

/// 첨부의 종류. 화면이 그릴 방법을 이 값으로 정한다.
///
/// 주간 리포트 PDF(#778)로 시작해 코칭 사진(#921)이 더해졌다. **둘뿐이다** —
/// 임의 파일 공유는 이 대화의 목적이 아니고, 그릴 수 없는 형식이 오면 화면에는
/// 아이콘 하나만 남는다.
enum ChatAttachmentKind {
  /// 내려받는다.
  pdf,

  /// 대화 안에서 그린다.
  image;

  static ChatAttachmentKind? parse(Object? value) => switch (value) {
    'pdf' => ChatAttachmentKind.pdf,
    'image' => ChatAttachmentKind.image,
    _ => null,
  };
}

/// 채팅 메시지에 딸린 파일.
class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.fileName,
    required this.fileId,
    required this.fileSize,
    required this.downloadPath,
  });

  final ChatAttachmentKind kind;
  final String fileName;
  final String fileId;
  final int fileSize;
  final String downloadPath;

  bool get isImage => kind == ChatAttachmentKind.image;
}
