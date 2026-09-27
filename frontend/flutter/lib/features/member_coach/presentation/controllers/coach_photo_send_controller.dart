import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/utils/request_id.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

/// 회원이 트레이너에게 보내는 사진 한 장의 전송 상태. (#1665)
enum CoachPhotoSendStatus {
  /// 올리는 중.
  sending,

  /// 보내지 못했다 — 다시 보내거나 지울 수 있다.
  failed,

  /// 서버가 받았다. 대화를 다시 받아 올 때까지 서버가 준 메시지로 그린다.
  sent,
}

/// 아직 대화에 들어가지 않은, 내가 보내는 사진. (#1665)
///
/// 서버가 받기 전까지 이 사진은 스레드에 없다. 그 사이 화면에서 사라지면 회원은
/// 보냈는지 모른 채 같은 사진을 또 고른다 — 그래서 올리는 동안과 실패했을 때
/// 모두 대화 끝에 내 말풍선으로 남긴다.
class PendingCoachPhoto {
  const PendingCoachPhoto({
    required this.requestId,
    required this.photo,
    this.status = CoachPhotoSendStatus.sending,
    this.message,
  });

  /// 이 사진의 멱등키. **다시 보내기에서 그대로 쓴다** — 서버는 받았는데 응답만
  /// 끊긴 경우, 새 키로 보내면 같은 사진이 대화에 두 장 쌓인다.
  final String requestId;

  final MealPhoto photo;
  final CoachPhotoSendStatus status;

  /// 서버가 받아 만든 메시지. [CoachPhotoSendStatus.sent] 일 때만 있다.
  ///
  /// 받자마자 대기 말풍선을 치우면, 대화를 다시 받아 오는 사이 사진이 잠깐
  /// 사라졌다 나타난다. 그래서 대화가 그 id 를 가질 때까지 이 메시지로 그린다
  /// (화면이 id 로 겹침을 거른다).
  final CoachMessage? message;

  /// 서버에 적힐 파일 이름. 형식은 바이트에서 읽은 것이라 내용과 어긋나지 않는다.
  String get fileName => 'photo.${photo.format.extension}';

  /// 말풍선이 그릴 첨부 — 올리는 중에는 서버에 파일이 없어 고른 바이트를 그린다.
  CoachAttachment get attachment => CoachAttachment(
    kind: CoachAttachmentKind.image,
    fileName: fileName,
    fileId: requestId,
    fileSize: photo.bytes.length,
    downloadPath: '',
    localBytes: photo.bytes,
  );

  PendingCoachPhoto copyWith({
    CoachPhotoSendStatus? status,
    CoachMessage? message,
  }) => PendingCoachPhoto(
    requestId: requestId,
    photo: photo,
    status: status ?? this.status,
    message: message ?? this.message,
  );
}

/// 사진 멱등키를 만든다. 테스트가 정해진 키로 바꿔 끼운다.
final coachPhotoRequestIdProvider = Provider<String Function()>(
  (ref) => newClientRequestId,
  name: 'coachPhotoRequestId',
);

/// 트레이너 채팅에서 보내는 사진들의 전송 상태. (#1665)
///
/// 화면을 닫아도 버리지 않는다 — 실패한 사진이 채팅을 다시 열었을 때도 남아
/// 있어야 다시 보낼 수 있다. 담당이 바뀌면(저장소가 새로 서면) 비운다.
class CoachPhotoSendController extends Notifier<List<PendingCoachPhoto>> {
  /// 서버가 받는 사진 한 장의 최대 크기(`max_chat_image_bytes`, 6MB).
  ///
  /// 넘으면 올려 봐야 413 이다. 고른 자리에서 막아 기다림 없이 알려 준다.
  static const int maxBytes = 6 * 1024 * 1024;

  @override
  List<PendingCoachPhoto> build() {
    ref.watch(memberCoachRepositoryProvider);
    return const <PendingCoachPhoto>[];
  }

  /// [photo] 를 보낸다. 서버가 받았으면 true.
  Future<bool> send(MealPhoto photo) {
    final PendingCoachPhoto pending = PendingCoachPhoto(
      requestId: ref.read(coachPhotoRequestIdProvider)(),
      photo: photo,
    );
    state = <PendingCoachPhoto>[...state, pending];
    return _upload(pending);
  }

  /// 실패한 사진을 **같은 멱등키로** 다시 보낸다.
  Future<bool> retry(String requestId) {
    final PendingCoachPhoto? pending = _find(requestId);
    if (pending == null || pending.status != CoachPhotoSendStatus.failed) {
      return Future<bool>.value(false);
    }
    _replace(pending.copyWith(status: CoachPhotoSendStatus.sending));
    return _upload(pending);
  }

  /// 사진을 목록에서 뺀다. 실패한 사진이면 트레이너에게는 아무것도 가지 않는다.
  void discard(String requestId) {
    state = <PendingCoachPhoto>[
      for (final PendingCoachPhoto p in state)
        if (p.requestId != requestId) p,
    ];
  }

  Future<bool> _upload(PendingCoachPhoto pending) async {
    final MemberCoachRepository repository = ref.read(
      memberCoachRepositoryProvider,
    );
    final CoachMessage message;
    try {
      message = await repository.sendPhoto(
        pending.photo.bytes,
        fileName: pending.fileName,
        mimeType: pending.photo.mimeType,
        clientRequestId: pending.requestId,
      );
    } on Object {
      // 그새 지웠으면 되살리지 않는다.
      final PendingCoachPhoto? current = _find(pending.requestId);
      if (current != null) {
        _replace(current.copyWith(status: CoachPhotoSendStatus.failed));
      }
      return false;
    }
    // 이제 스레드에 있다 — 내 말풍선은 서버가 준 메시지가 대신한다.
    final PendingCoachPhoto? current = _find(pending.requestId);
    if (current != null) {
      _replace(
        current.copyWith(status: CoachPhotoSendStatus.sent, message: message),
      );
    }
    ref.invalidate(coachChatProvider);
    return true;
  }

  PendingCoachPhoto? _find(String requestId) {
    for (final PendingCoachPhoto p in state) {
      if (p.requestId == requestId) return p;
    }
    return null;
  }

  void _replace(PendingCoachPhoto next) {
    state = <PendingCoachPhoto>[
      for (final PendingCoachPhoto p in state)
        if (p.requestId == next.requestId) next else p,
    ];
  }
}

final coachPhotoSendProvider =
    NotifierProvider<CoachPhotoSendController, List<PendingCoachPhoto>>(
      CoachPhotoSendController.new,
      name: 'coachPhotoSend',
    );
