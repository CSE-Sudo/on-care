import 'dart:typed_data';

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
    this.routineDelivery,
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

  /// 루틴 전송 안내라면 무엇을 보냈나(#2672). 일반 대화는 null 이다.
  ///
  /// 리포트 안내([reportWeekStart])처럼 말풍선이 아니라 대화 가운데 카드로
  /// 그린다. 본문은 카드를 못 그리는 자리(고객 목록의 마지막 메시지)가 읽는다.
  final RoutineDeliveryNotice? routineDelivery;

  /// Whether this message was sent by the trainer.
  bool get fromTrainer => sender == ChatSender.trainer;
}

/// 채팅 가운데 루틴 전송 안내 — 한 번의 전송에 무엇이 갔나. (#2672)
class RoutineDeliveryNotice {
  /// Creates the notice.
  const RoutineDeliveryNotice({
    required this.kind,
    this.programNames = const <String>[],
    this.routineNames = const <String>[],
  });

  /// JSON(서버 `RoutineDeliveryCardOut`, 데모 표시 행) → 안내. 모양이 다르면
  /// null — 안내 카드 하나 때문에 대화가 뜨지 않는 편보다 일반 메시지로 둔다.
  static RoutineDeliveryNotice? fromJson(Object? value) {
    if (value is! Map) return null;
    final Object? kind = value['kind'];
    if (kind is! String || kind.isEmpty) return null;
    List<String> names(Object? raw) => <String>[
      if (raw is List)
        for (final Object? name in raw)
          if (name is String && name.isNotEmpty) name,
    ];
    return RoutineDeliveryNotice(
      kind: kind,
      programNames: names(value['program_names']),
      routineNames: names(value['routine_names']),
    );
  }

  /// `pt_with_routine` · `routine_only` · `cancelled_routine_only` · `routine`
  /// · `program`.
  final String kind;

  /// 함께 간 PT 프로그램의 운동 이름.
  final List<String> programNames;

  /// 함께 간 개인운동 이름.
  final List<String> routineNames;

  /// 저장용 JSON — 서버와 같은 키다.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'program_names': programNames,
    'routine_names': routineNames,
  };
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
    this.localBytes,
  });

  final ChatAttachmentKind kind;
  final String fileName;
  final String fileId;
  final int fileSize;
  final String downloadPath;

  /// 데모 대화의 사진·PDF 바이트. (#2493, #2669)
  ///
  /// 데모에는 [downloadPath] 로 내려받을 서버가 없다. 값이 있으면 화면은 받아
  /// 오지 않고 이 바이트를 그대로 그리거나 연다 — 회원앱
  /// `CoachAttachment.localBytes` 와 같은 자리다.
  final Uint8List? localBytes;

  bool get isImage => kind == ChatAttachmentKind.image;
}
