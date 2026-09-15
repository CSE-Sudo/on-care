import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/main_shell.dart';
import 'package:oncare/app/router/nav_logger_observer.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/logging/app_logger.dart';
import 'package:oncare/features/account/presentation/pages/onboarding_page.dart';
import 'package:oncare/features/account/presentation/pages/points_guide_page.dart';
import 'package:oncare/features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/auth/presentation/pages/sign_in_page.dart';
import 'package:oncare/features/auth/presentation/pages/sign_up_page.dart';
import 'package:oncare/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:oncare/features/diet/presentation/pages/diet_record_page.dart';
import 'package:oncare/features/diet/presentation/widgets/diet_flows.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_complete_page.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_history_page.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_request_page.dart';
import 'package:oncare/features/exercise/presentation/pages/exercise_page.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_detail_page.dart';
import 'package:oncare/features/exercise/presentation/pages/gym_list_page.dart';
import 'package:oncare/features/exercise/presentation/pages/trainer_detail_page.dart';
import 'package:oncare/features/exercise/presentation/pages/trainer_list_page.dart';
import 'package:oncare/features/my_health/presentation/pages/my_health_page.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/features/notification/presentation/pages/notification_page.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// Pure auth-guard policy for the router's `redirect`. Kept free of
/// `BuildContext`/`GoRouterState` so it can be unit-tested directly.
///
/// - signed-out (or still restoring the session) → forced onto the
///   sign-in screen;
/// - already in the app (demo or authenticated) → kept off the sign-in
///   screen (bounced to the dashboard).
///
/// Returning `null` means "no redirect — stay put".
String? sessionRedirect(SessionStatus status, String location) {
  final onAuthRoute =
      location == AppRoutes.signIn || location == AppRoutes.signUp;
  switch (status) {
    case SessionStatus.unknown:
    case SessionStatus.signedOut:
      return onAuthRoute ? null : AppRoutes.signIn;
    case SessionStatus.demo:
    case SessionStatus.authenticated:
      return onAuthRoute ? AppRoutes.dashboard : null;
  }
}

/// Single source of truth for the app's routing tree. The `config`
/// is read once at build time — dev-only routes (UI catalog) are
/// excluded from prod builds.
///
/// When [readStatus] is supplied the router enforces [sessionRedirect];
/// [refresh] should fire whenever the session changes so the guard is
/// re-evaluated without rebuilding the router (which drops nav state).
GoRouter buildAppRouter({
  required AppConfig config,
  NavigatorObserver? observer,
  SessionStatus Function()? readStatus,
  Listenable? refresh,
}) {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return GoRouter(
    initialLocation: AppRoutes.signIn,
    debugLogDiagnostics: !config.isProd,
    observers: observer == null
        ? const <NavigatorObserver>[]
        : <NavigatorObserver>[observer],
    refreshListenable: refresh,
    redirect: readStatus == null
        ? null
        : (context, state) =>
              sessionRedirect(readStatus(), state.matchedLocation),
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.diet,
                builder: (context, state) => const DietRecordPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.exercise,
                builder: (context, state) => ExercisePage(
                  initialSubTab: state.uri.queryParameters['tab'] == 'gym'
                      ? 1
                      : 0,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.myHealth,
                builder: (context, state) => const MyHealthPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.aiCoach,
        builder: (context, state) => const AICoachPage(),
      ),
      GoRoute(
        path: AppRoutes.notification,
        builder: (context, state) => const NotificationPage(),
      ),
      GoRoute(
        path: AppRoutes.dietEntryDetail,
        builder: (context, state) => DietMealDetailPage(
          entryId: state.pathParameters['entryId'] ?? '',
          initialMeal: state.extra is DietMeal
              ? state.extra! as DietMeal
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.myPoints,
        builder: (context, state) => PointsBenefitsPage(
          points: state.extra is int ? state.extra! as int : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.mySettings,
        builder: (context, state) => switch (state.pathParameters['section']) {
          'profile' => const ProfileSettingsPage(),
          'goals' => const HealthGoalsPage(),
          'notifications' => const NotificationSettingsPage(),
          'terms' => const LegalDocumentPage(document: 'terms'),
          'privacy' => const LegalDocumentPage(document: 'privacy'),
          _ => const SupportPage(),
        },
      ),
      GoRoute(
        path: AppRoutes.gyms,
        builder: (context, state) => const GymListPage(),
      ),
      GoRoute(
        path: AppRoutes.gymDetail,
        builder: (context, state) =>
            GymDetailPage(gymId: state.pathParameters['gymId'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.trainers,
        builder: (context, state) => const TrainerListPage(),
      ),
      GoRoute(
        path: AppRoutes.trainerDetail,
        builder: (context, state) => TrainerDetailPage(
          trainerId: state.pathParameters['trainerId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.consultationRequest,
        // 폐지된 헬스장 대상 링크(`?targetType=gym`)는 trainerId 가 없어 화면이
        // "대상을 찾을 수 없음"으로 떨어진다 — 옛 딥링크가 죽지 않고 안내된다.
        builder: (context, state) => ConsultationRequestPage(
          gymId: state.uri.queryParameters['gymId'] ?? '',
          trainerId: state.uri.queryParameters['trainerId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.consultationComplete,
        builder: (context, state) => ConsultationCompletePage(
          request: state.extra is ConsultationRequest
              ? state.extra! as ConsultationRequest
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.consultationHistory,
        builder: (context, state) => const ConsultationHistoryPage(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.pointsGuide,
        builder: (context, state) => const PointsGuidePage(),
      ),
      if (!config.isProd)
        GoRoute(
          path: AppRoutes.uiCatalog,
          builder: (context, state) => const OnCareTokenCatalog(),
        ),
    ],
  );
}

/// Riverpod-managed router. Rebuilds if AppConfig is ever swapped.
final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  final observer = config.isProd
      ? null
      : NavLoggerObserver(ref.watch(appLoggerProvider));
  // Bridge session changes into a Listenable so the router re-evaluates its
  // login guard without rebuilding — a rebuild would drop the navigation
  // stack. The status itself is read lazily inside `redirect`.
  final refresh = ValueNotifier<int>(0);
  ref.listen<SessionState>(
    sessionControllerProvider,
    (_, _) => refresh.value++,
  );
  ref.onDispose(refresh.dispose);
  return buildAppRouter(
    config: config,
    observer: observer,
    readStatus: () => ref.read(sessionControllerProvider).status,
    refresh: refresh,
  );
});
