import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/features/exercise/domain/repositories/gym_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 헬스장·트레이너 연결을 끊는 하나의 흐름 — 확인 창을 띄우고, 승인되면
/// 끊은 뒤 연결 상태를 새로 읽는다.
///
/// MY 탭 카드와 상세 화면이 같은 것을 지운다. 두 화면이 각자 확인 창을 만들면
/// 한쪽만 "트레이너도 함께 사라진다" 를 알리는 식으로 갈린다. (#1057)
///
/// 승인 없이 닫혔거나 해제 요청이 실패했으면 `false` 를 돌려준다 — 호출부가
/// 화면을 닫을지 정한다.
///
/// 요청이 실패하면(네트워크 끊김·서버 오류) 실패 안내를 띄우고 화면은 그대로
/// 둔다. 예전에는 예외가 그대로 빠져나가 창만 닫히고 아무 말이 없어, 회원은
/// 해제가 됐는지 알 수 없었다(#2857). 서버가 '연결이 없다(404)' 고 답하면 이미
/// 해제된 것이라 성공과 같이 다룬다.
Future<bool> confirmDisconnect(
  BuildContext context,
  WidgetRef ref, {
  required String message,
  required Future<void> Function(GymRepository repo) disconnect,
}) async {
  final AppLocalizations l = AppLocalizations.of(context);
  final AppToastHost toast = AppToastHost.of(context);
  final bool ok = await showAppConfirmDialog(
    context: context,
    title: l.myConnectionDeleteTitle,
    message: message,
    confirmLabel: l.myDelete,
    cancelLabel: l.myCancel,
    destructive: true,
  );
  if (!ok) return false;
  try {
    await disconnect(ref.read(gymRepositoryProvider));
  } on Object catch (error) {
    if (!isAlreadyDisconnected(error)) {
      toast.show(l.myConnectionDeleteFailed, type: AppToastType.error);
      return false;
    }
  }
  // 해제를 기다리는 동안 화면을 벗어났다면 ref 가 이미 폐기됐을 수 있다.
  if (!context.mounted) return true;
  // 헬스장 해제는 트레이너까지 끊으므로 두 provider 를 함께 새로 읽는다.
  ref.invalidate(myGymProvider);
  ref.invalidate(myTrainerProvider);
  // 담당 코치도 더는 내 코치가 아니다(#1865). 다시 읽지 않으면 헤더의 대화
  // 버튼이 여전히 트레이너 채팅으로 가고, AI 챗봇 입구로 바뀌지 않는다(#1840).
  // 그 코치에 딸린 화면(배정 운동·PT 일정·대화·미읽음)도 함께 비워야 한다.
  ref
    ..invalidate(memberCoachProvider)
    ..invalidate(coachRoutinesProvider)
    ..invalidate(coachSessionsProvider)
    ..invalidate(coachChatProvider)
    ..invalidate(coachUnreadProvider)
    // 담당이 없는 회원에게만 담당 요청이 온다. 데모는 요청을 앱을 켤 때 한 번만
    // 받아서, 다시 읽지 않으면 끊은 뒤 온 요청 창이 뜨지 않는다(#2659).
    ..invalidate(coachInvitesProvider);
  return true;
}

/// 해제 요청의 실패가 '이미 연결이 없다' 는 뜻인가. (#2857)
///
/// 서버의 해제는 멱등이라 연결이 없어도 204 를 주지만, 예전 서버나 경로가
/// 404 로 답해도 끊으려던 상태는 이미 이뤄진 것이다 — 실패 안내 대신 연결
/// 상태를 새로 읽고 화면을 닫는다.
@visibleForTesting
bool isAlreadyDisconnected(Object error) =>
    error is DioException && error.response?.statusCode == 404;

/// 확인 창 문구를 정하려고 지금 연결을 읽는다. 읽기가 실패하면 `null` 이다.
/// (#2857)
///
/// 예전에는 이 조회가 실패하면 예외가 빠져나가 확인 창조차 뜨지 않았고, 해제
/// 버튼이 먹통처럼 보였다. 실패하면 '함께 해제' 안내만 빼고 확인 창은 띄운다.
Future<T?> readConnectionForConfirm<T>(Future<T?> lookup) async {
  try {
    return await lookup;
  } on Object {
    return null;
  }
}

/// 상세 화면 하단의 연결 삭제 버튼.
///
/// 목록 카드에서 삭제를 상세로 옮겼으므로(#1057), 상세에도 지울 자리가 있어야
/// 한다. 그러지 않으면 연결을 끊을 방법이 화면에서 사라진다.
class DisconnectButton extends StatelessWidget {
  const DisconnectButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 확인창을 여는 위험 동작이라 빨간 글자 버튼이다(#1690).
    return AppButton(
      key: const Key('connection-disconnect-button'),
      label: label,
      onPressed: onTap,
      variant: AppButtonVariant.destructiveText,
      leadingIcon: AppIcons.disconnect,
      fullWidth: true,
    );
  }
}
