/// 데모 대화에서 **트레이너가 보낸** 첨부. (#2663)
///
/// 실서버 대화에는 트레이너가 올린 운동 안내 PDF·예시 사진이 섞여 있다. 데모
/// 시드에 그런 메시지가 없으면 회원 앱의 PDF 카드와 사진 말풍선, 그리고 그
/// 파일을 내려받는 흐름(`GET /chat/attachments/{id}`)이 데모에서 한 번도 보이지
/// 않는다.
///
/// 시드 메시지는 실서버 첨부처럼 내려받을 경로만 들고 있고, 바이트는 로컬 목업
/// API 가 앱 번들에서 꺼내 준다 — 실서버와 같은 길로 받아 와야 받는 쪽 코드가
/// 데모에서도 돈다. 트레이너 웹 데모의 김민수 대화도 같은 파일을 같은 자리에
/// 둔다(`frontend/flutter_trainer/lib/core/storage/seed_clients.dart`).
library;

import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

/// 번들에 든 첨부 파일 한 건.
class DemoCoachFile {
  const DemoCoachFile({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.asset,
    required this.fileSize,
  });

  /// 첨부 id — 내려받는 경로의 끝이다.
  final String id;
  final CoachAttachmentKind kind;

  /// 대화에 보이는 파일 이름.
  final String fileName;

  /// 앱 번들 경로.
  final String asset;

  /// 바이트 수. 실서버는 첨부와 함께 크기를 내려 주고 PDF 카드가 그 값을
  /// 적는다. 번들 파일의 크기와 같아야 한다(시험이 지킨다).
  final int fileSize;

  String get downloadPath => '/chat/attachments/$id';

  CoachAttachment toAttachment() => CoachAttachment(
    kind: kind,
    fileName: fileName,
    fileId: id,
    fileSize: fileSize,
    downloadPath: downloadPath,
  );
}

/// 화·목 15분 프로그램 안내 — 트레이너가 짧은 프로그램으로 바꾼 날 보낸다.
const DemoCoachFile kDemoCoachProgramPdf = DemoCoachFile(
  id: 'demo-coach-file-program',
  kind: CoachAttachmentKind.pdf,
  fileName: 'tue-thu-15min-program.pdf',
  asset: 'assets/demo/coach-program-tue-thu.pdf',
  fileSize: 171338,
);

/// 국물을 덜어 둔 한 끼 예시 사진 — 나트륨 이야기를 하던 날 보낸다.
const DemoCoachFile kDemoCoachSoupPhoto = DemoCoachFile(
  id: 'demo-coach-file-soup',
  kind: CoachAttachmentKind.image,
  fileName: 'soup-example.jpeg',
  asset: 'assets/demo/images/diet-doenjang-rice.jpeg',
  fileSize: 114516,
);

/// 데모 대화에 든 트레이너 첨부 전부.
const List<DemoCoachFile> kDemoCoachFiles = <DemoCoachFile>[
  kDemoCoachProgramPdf,
  kDemoCoachSoupPhoto,
];

/// [id] 의 첨부. 데모가 든 것이 아니면 null.
DemoCoachFile? demoCoachFileById(String id) {
  for (final DemoCoachFile file in kDemoCoachFiles) {
    if (file.id == id) return file;
  }
  return null;
}
