import 'package:oncare_trainer/shared/models/trainer_profile.dart';

/// Lifecycle of the trainer session.
///
/// Designed fresh for the trainer app (the user app's auth logic is not
/// reused — it has no notion of a trainer account). Mirrors the same
/// four-state shape so the two On-Care apps stay conceptually aligned.
enum SessionStatus {
  /// Session not yet resolved (during the initial restore).
  unknown,

  /// No session — the login screen is shown.
  signedOut,

  /// Skipped login — browsing with mock data, no token.
  demo,

  /// Logged in with a (mock) token and a trainer profile attached.
  authenticated,
}

/// Immutable snapshot of the current session.
class SessionState {
  /// Creates a session snapshot. [profile] is non-null only when
  /// [status] is [SessionStatus.authenticated].
  const SessionState({
    this.status = SessionStatus.unknown,
    this.profile,
    this.consentRequired = false,
  });

  /// Current lifecycle state.
  final SessionStatus status;

  /// The signed-in trainer's profile, or `null` when not authenticated.
  final TrainerProfile? profile;

  /// 로그인은 됐지만 가입 동의가 남았다 — 라우터가 다른 화면보다 먼저 동의
  /// 화면을 띄운다. (#2819) 데모에는 계정이 없어 언제나 거짓이다.
  final bool consentRequired;
}
