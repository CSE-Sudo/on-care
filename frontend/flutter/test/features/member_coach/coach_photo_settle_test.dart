/// 보낸 사진이 대화에 들어오면 대기 목록에서 빠진다. (#2880)
///
/// 업로드가 끝난 사진도 `sent` 로 상태에 남아, 화면을 오래 열어 두고 여러 장을
/// 보내면 원본 바이트가 계속 메모리에 쌓였다.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/errors/app_error.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/member_coach/data/repositories/mock_member_coach_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/coach_photo_send_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

/// PNG 서명 뒤에 아무 바이트. 형식 판정은 앞 8바이트만 본다.
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  1, 2, 3, 4,
]);

/// KST 고정 시각.
final DateTime _at = DateTime(2026, 9, 28, 9, 30);

CoachMessage _message(String id) => CoachMessage(
  id: id,
  sender: CoachSender.me,
  body: '',
  timeLabel: '09:30',
  createdAt: _at,
);

/// 보낼 때마다 `server-<n>` 메시지를 돌려주고, [failNext] 면 한 번 실패한다.
class _Repository extends MockMemberCoachRepository {
  int sent = 0;
  bool failNext = false;

  @override
  Future<CoachMessage> sendPhoto(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required String clientRequestId,
    String text = '',
  }) async {
    if (failNext) {
      failNext = false;
      throw const NetworkError();
    }
    sent++;
    return _message('server-$sent');
  }
}

ProviderContainer _container(_Repository repo) {
  int n = 0;
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      memberCoachRepositoryProvider.overrideWithValue(repo),
      coachPhotoRequestIdProvider.overrideWithValue(() => 'photo-${++n}'),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

MealPhoto get _photo => MealPhoto.fromBytes(_png)!;

void main() {
  test('대화에 같은 id 메시지가 들어오면 보낸 사진을 뺀다', () async {
    final ProviderContainer c = _container(_Repository());
    final CoachPhotoSendController controller = c.read(
      coachPhotoSendProvider.notifier,
    );

    expect(await controller.send(_photo), isTrue);
    expect(
      c.read(coachPhotoSendProvider).single.status,
      CoachPhotoSendStatus.sent,
    );

    controller.settle(<CoachMessage>[_message('server-1')]);

    expect(c.read(coachPhotoSendProvider), isEmpty);
  });

  test('대화에 아직 없으면 보낸 사진을 남겨 그 메시지로 그린다', () async {
    final ProviderContainer c = _container(_Repository());
    final CoachPhotoSendController controller = c.read(
      coachPhotoSendProvider.notifier,
    );

    await controller.send(_photo);
    controller.settle(<CoachMessage>[_message('other')]);

    final PendingCoachPhoto left = c.read(coachPhotoSendProvider).single;
    expect(left.message?.id, 'server-1');
  });

  test('실패한 사진은 대화와 상관없이 남아 다시 보낼 수 있다', () async {
    final _Repository repo = _Repository()..failNext = true;
    final ProviderContainer c = _container(repo);
    final CoachPhotoSendController controller = c.read(
      coachPhotoSendProvider.notifier,
    );

    expect(await controller.send(_photo), isFalse);
    controller.settle(<CoachMessage>[_message('server-1')]);

    expect(
      c.read(coachPhotoSendProvider).single.status,
      CoachPhotoSendStatus.failed,
    );
  });

  test('여러 장 중 대화에 들어온 것만 뺀다', () async {
    final ProviderContainer c = _container(_Repository());
    final CoachPhotoSendController controller = c.read(
      coachPhotoSendProvider.notifier,
    );

    await controller.send(_photo);
    await controller.send(_photo);
    controller.settle(<CoachMessage>[_message('server-1')]);

    final List<PendingCoachPhoto> left = c.read(coachPhotoSendProvider);
    expect(left.single.message?.id, 'server-2');
  });

  test('뺄 것이 없으면 상태를 바꾸지 않는다', () async {
    final ProviderContainer c = _container(_Repository());
    final CoachPhotoSendController controller = c.read(
      coachPhotoSendProvider.notifier,
    );
    await controller.send(_photo);
    final List<PendingCoachPhoto> before = c.read(coachPhotoSendProvider);

    controller.settle(const <CoachMessage>[]);

    expect(identical(c.read(coachPhotoSendProvider), before), isTrue);
  });
}
