import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_shell.dart';
import 'package:oncare_trainer/features/auth/domain/entities/session_state.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// The router's `errorBuilder` target: a URL that matches no screen.
///
/// go_router's built-in error page is an English one-liner with no way
/// out. This one keeps the console around it instead (#2294):
///
/// - in the app (demo or authenticated) → rendered inside
///   [AppShellFrame], so the sidebar is still there and nothing is
///   selected — no destination claims a page that does not exist — and the
///   primary action goes to the 대시보드;
/// - signed-out → the sign-in screen's [AppAuthLayout], with the primary
///   action going to sign-in. The auth gate normally sends a signed-out
///   visitor to sign-in before this page can build; this branch covers
///   the frame where the session has dropped but the gate has not re-run.
///
/// The URL is left as it is, so the address bar still shows what was
/// asked for.
class NotFoundPage extends ConsumerWidget {
  /// Creates the 404 page.
  const NotFoundPage({super.key});

  /// Key on the page body, for tests and for finding the page in a tree.
  static const Key bodyKey = ValueKey<String>('not-found-page');

  /// Key on the primary action button.
  static const Key actionKey = ValueKey<String>('not-found-action');

  /// Whether [status] puts the trainer inside the console.
  static bool isInApp(SessionStatus status) =>
      status == SessionStatus.demo || status == SessionStatus.authenticated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool inApp = isInApp(ref.watch(sessionControllerProvider).status);
    const IconData icon = Icons.link_off_rounded;

    if (!inApp) {
      return AppAuthLayout(
        key: bodyKey,
        logo: const AppIcon(
          icon,
          size: OnCareSize.iconEmptyState,
          color: OnCareColors.textTertiary,
        ),
        title: l.notFoundTitle,
        subtitle: l.notFoundMessage,
        child: AppButton(
          key: actionKey,
          label: l.notFoundGoSignIn,
          onPressed: () => context.go(AppRoutes.signIn),
          size: OnCareButtonSize.large,
          fullWidth: true,
        ),
      );
    }

    return AppShellFrame(
      currentIndex: -1,
      onSelect: (index) => context.go(AppShell.branchRoot(index)),
      onHome: () => context.go(AppRoutes.dashboard),
      body: Center(
        key: bodyKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OnCareSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppEmptyState(
                icon: icon,
                title: l.notFoundTitle,
                message: l.notFoundMessage,
                placement: AppStatePlacement.card,
              ),
              const SizedBox(height: OnCareSpacing.s16),
              AppButton(
                key: actionKey,
                label: l.notFoundGoDashboard,
                onPressed: () => context.go(AppRoutes.dashboard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
