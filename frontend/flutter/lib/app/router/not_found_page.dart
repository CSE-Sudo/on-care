import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 라우터 `errorBuilder` 의 화면 — 어떤 화면과도 맞지 않는 주소다. (#2633)
///
/// go_router 기본 오류 화면은 영어 한 줄에 나갈 길이 없다. 회원 앱의 원래
/// 모양대로 흰 바탕 가운데에 빈 화면 안내를 두고, 한 번에 돌아갈 곳을 준다.
///
/// - 앱 안(데모·로그인) → `홈으로`, 대시보드로 간다.
/// - 로그인 전 → `로그인하러 가기`. 보통은 라우터 가드가 먼저 로그인 화면으로
///   보내 이 분기를 볼 일이 없다. 세션이 막 끝났는데 가드가 아직 다시 돌지
///   않은 한 프레임을 위한 것이다(트레이너 웹 #2294 와 같은 이유).
///
/// 주소는 그대로 둔다 — 무엇을 열려 했는지 주소창에 남는다.
class NotFoundPage extends ConsumerWidget {
  /// 404 화면.
  const NotFoundPage({super.key});

  /// 화면 본문의 Key — 테스트와 트리 탐색용.
  static const Key bodyKey = ValueKey<String>('not-found-page');

  /// 돌아가기 버튼의 Key.
  static const Key actionKey = ValueKey<String>('not-found-action');

  /// [status] 가 회원을 앱 안에 두는가.
  static bool isInApp(SessionStatus status) =>
      status == SessionStatus.demo || status == SessionStatus.authenticated;

  /// 버튼이 보낼 곳 — 앱 안이면 홈, 아니면 로그인 화면.
  static String homeFor(SessionStatus status) =>
      isInApp(status) ? AppRoutes.dashboard : AppRoutes.signIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final SessionStatus status = ref.watch(sessionControllerProvider).status;
    final bool inApp = isInApp(status);
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      body: SafeArea(
        child: Center(
          key: bodyKey,
          // 좁은 화면에서 글자를 키워도 잘리지 않게 스크롤을 둔다. 여백은 빈 화면
          // 안내(`AppStatePlacement.page`)가 스스로 두른다.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: OnCareLayout.mobileContentMaxWidth,
              ),
              child: AppEmptyState(
                icon: AppIcons.disconnect,
                title: l.notFoundTitle,
                message: l.notFoundMessage,
                actionLabel: inApp ? l.notFoundGoHome : l.notFoundGoSignIn,
                actionKey: actionKey,
                onAction: () => context.go(homeFor(status)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
