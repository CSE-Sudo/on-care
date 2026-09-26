/// Centralised route paths. Anything that needs to navigate imports
/// this rather than another feature module — see STRUCTURE.md §4.
class AppRoutes {
  AppRoutes._();

  // Main tabs (StatefulShellRoute branches)
  static const String dashboard = '/dashboard';
  static const String diet = '/diet';
  static const String exercise = '/exercise';
  static const String myHealth = '/my-health';

  // Modal-ish routes (pushed from any tab)
  static const String aiCoach = '/ai-coach';
  static const String notification = '/notification';
  static const String dietEntryDetail = '/diet/entries/:entryId';
  static const String myPoints = '/my-health/points';

  /// 포인트 내역 — 적립·사용·회수·반환(#2146).
  static const String myPointsHistory = '/my-health/points/history';

  /// 내 혜택 — 보유 쿠폰(이후 보호권·챌린지)을 모은다(#1787).
  static const String myBenefits = '/my-health/benefits';
  static const String myCouponDetail = '/my-health/benefits/coupons/:couponId';

  /// 트레이너 리포트 — 받은 리포트 목록과 내가 보낸 주간 피드백(#2232).
  ///
  /// 담당 트레이너가 있는 회원만 들어간다. MY 탭이 담당이 없을 때 입구 자체를
  /// 세우지 않는다 — 받는 사람이 없는 리포트·피드백은 아무 데도 닿지 않는다.
  static const String myCoachReports = '/my-health/coach-reports';
  static const String mySettings = '/my-health/settings/:section';
  static const String gyms = '/gyms';
  static const String gymDetail = '/gyms/:gymId';
  /// 트레이너 **상세**. 목록 화면은 없다 — 트레이너는 헬스장을 거쳐 만난다
  /// (헬스장 찾기 카드 → 헬스장 상세 → 트레이너 상세). #1885
  static const String trainerDetail = '/trainers/:trainerId';
  static const String consultationRequest = '/consultations/request';
  static const String consultationComplete = '/consultations/complete';

  /// 내 상담 요청 전체 내역 화면(#948). 운동 탭 요약 카드는 요청 1건만
  /// 보여주고, 여기서 전체(진행 중 + 지난 요청)를 본다.
  static const String consultationHistory = '/consultations';
  static const String exerciseGym = '/exercise?tab=gym';

  static String gymDetailPath(String gymId) =>
      '$gyms/${Uri.encodeComponent(gymId)}';

  static String trainerDetailPath(String trainerId) =>
      '/trainers/${Uri.encodeComponent(trainerId)}';

  static String dietEntryDetailPath(String entryId) =>
      '$diet/entries/${Uri.encodeComponent(entryId)}';

  static String myCouponDetailPath(String couponId) =>
      '$myBenefits/coupons/${Uri.encodeComponent(couponId)}';

  static String mySettingsPath(String section) =>
      '/my-health/settings/${Uri.encodeComponent(section)}';

  /// 상담 요청은 트레이너 한 사람 앞으로만 간다 — [trainerId] 는 필수다.
  /// [gymId] 는 요청 화면이 그 트레이너의 헬스장을 함께 보여 주는 데 쓴다.
  static String consultationRequestPath({
    required String gymId,
    required String trainerId,
  }) {
    return Uri(
      path: consultationRequest,
      queryParameters: <String, String>{'gymId': gymId, 'trainerId': trainerId},
    ).toString();
  }

  // Auth
  /// 저장된 세션을 되살리는 동안 머무는 시작 화면(#1944). 복구가 끝나면
  /// 라우터가 홈이나 로그인으로 옮긴다.
  static const String splash = '/auth/splash';
  static const String signIn = '/auth/sign-in';
  static const String signUp = '/auth/sign-up';

  // First-run onboarding (shown right after sign-up)
  static const String onboarding = '/onboarding';


  /// 포인트 안내의 `시작하기` 뒤에 보는 사용 가이드(#1857) — 예시 자료로 채운
  /// 화면 위에서 주요 기능을 하나씩 밝게 짚는다.
  static const String guideTour = '/onboarding/guide';

  // Dev-only routes (registered only in non-prod builds).
  static const String uiCatalog = '/dev/ui-catalog';
}
