import 'package:oncare_trainer/core/utils/date_format.dart';

/// Centralised route paths for the trainer app. Anything that needs to
/// navigate imports this rather than another feature module
/// (STRUCTURE.md §4).
///
/// URLs are **path-based** (`/clients/<id>/diet`) rather than
/// query-based: the sidebar console is deep-linked constantly (a KPI
/// card jumps to a filtered list, a schedule row jumps to a chat), and
/// paths keep back/forward, refresh and link-sharing honest.
class AppRoutes {
  AppRoutes._();

  /// Trainer login screen (email/password + demo bypass).
  static const String signIn = '/auth/sign-in';

  /// Trainer 회원가입 screen (name/email/password).
  static const String signUp = '/auth/sign-up';

  // --- Main navigation (StatefulShellRoute branches) ---

  /// 대시보드 — the console's home; what needs doing today.
  static const String dashboard = '/dashboard';

  /// 고객 — roster list, with the detail panel as a child path.
  static const String clients = '/clients';

  /// 스케줄 — day / week calendar.
  static const String schedule = '/schedule';

  /// 메시지 — roster-backed two-pane conversation workspace.
  static const String messages = '/messages';

  /// AI 코칭 — routine generation, templates, send history.
  static const String coaching = '/coaching';

  /// 리포트 — client weekly reports + trainer operating metrics.
  static const String reports = '/reports';

  /// 내 정보 / 설정 — reached from the sidebar footer, not the nav list.
  static const String my = '/my';

  /// 약관 · 개인정보 처리방침 — 로그인 없이도 열리는 문서 화면. (#968)
  ///
  /// 셸 밖의 최상위 라우트다. 내 정보에서만 열 수 있게 `/my` 아래에 두면
  /// 가입 화면에서는 걸 수 없다 — 동의할 문서를 동의하기 전에 읽지 못하는
  /// 셈이 된다. 인증 게이트도 이 경로만 통과시킨다([sessionRedirect]).
  static const String legal = '/legal';

  /// 이용약관 문서의 URL 세그먼트.
  static const String legalTerms = 'terms';

  /// 개인정보 처리방침 문서의 URL 세그먼트.
  static const String legalPrivacy = 'privacy';

  /// The documents [legal] can render, as URL segments.
  static const List<String> legalDocuments = <String>[legalTerms, legalPrivacy];

  /// Route pattern for a legal document.
  static const String legalDocumentPattern = ':document';

  /// Builds `/legal/<document>`. An unknown document falls back to the
  /// 이용약관 rather than resolving to nothing.
  static String legalDocument(String document) {
    final safe = legalDocuments.contains(document)
        ? document
        : legalDocuments.first;
    return '$legal/$safe';
  }

  /// Is [path] one of the documents that must open without a session?
  static bool isLegalPath(String path) =>
      path == legal || path.startsWith('$legal/');

  /// 스케줄 하위의 상담 요청 인박스. (#467, #1228)
  static const String consultationsSegment = 'consultations';
  static const String consultations = '$schedule/$consultationsSegment';

  /// 이전 독립 탭 주소. 기존 링크는 새 스케줄 하위 주소로 리다이렉트한다.
  static const String legacyConsultations = '/consultations';

  /// 대시보드에서 열었음을 남겨 돌아가기 동선을 복원한다.
  static String consultationsFromDashboard() => Uri(
    path: consultations,
    queryParameters: const <String, String>{'from': 'dashboard'},
  ).toString();

  /// 알림함 — 놓친 변화를 나중에 확인하는 자리. (#503)
  ///
  /// 상담 요청과 같은 이유로 nav 행은 실 API 빌드에서만 보인다(데모에는 알림을
  /// 만드는 회원 백엔드가 없다). 라우트 자체는 항상 등록해 딥링크가 살아 있다.
  static const String notifications = '/notifications';

  // --- Client detail ---

  /// Every addressable sub-section of a client's detail panel.
  ///
  /// 개요 became the always-visible detail header (alerts + today's
  /// numbers are needed on every tab, not just one), and 루틴 folded into
  /// 운동 — a prescription and its execution are one story, and splitting
  /// them meant the trainer could never see "I assigned this, did they do
  /// it?" on a single screen.
  ///
  /// [clientChatSection] is in this list but NOT in [clientTabSections]:
  /// it's opened from the header's message button rather than a tab, and
  /// it stays a real URL so the 대시보드 답장 대기 card and the 스케줄
  /// 채팅 chip can still deep-link straight into a thread.
  static const List<String> clientSections = <String>[
    'chat',
    'diet',
    'workout',
  ];

  /// The sections rendered as tabs, in tab order. Chat is deliberately
  /// absent — see [clientChatSection].
  static const List<String> clientTabSections = <String>['diet', 'workout'];

  /// The chat thread's section key — the header message button's target.
  ///
  /// Chat is an action ("say something to this person"), not a view of
  /// their data like 식단/운동, so it reads as a button the way it does on
  /// a social profile rather than a peer of the content tabs.
  static const String clientChatSection = 'chat';

  /// The section shown when a client is opened without one.
  ///
  /// A content tab, not the chat: opening the thread marks it read, so
  /// landing there by default cleared the 답장 대기 badge before the
  /// trainer had chosen to deal with it.
  static const String defaultClientSection = 'diet';

  /// Route pattern for the client detail panel.
  static const String clientDetailPattern = ':id/:section';

  /// Route pattern for a client opened without a section (redirects).
  static const String clientBarePattern = ':id';

  /// Builds `/clients/<id>/<section>`. Ids are percent-encoded — a
  /// backend member id is not guaranteed to be URL-safe.
  ///
  /// [filter] carries the roster preset (`f`) into the detail URL. Dropping
  /// it is what made the 대시보드 '주의 고객' 카드 → 목록 → 고객 순서에서
  /// 필터가 사라지게 했다: 상세는 별개 라우트라 쿼리를 물려주지 않으면 그
  /// 자리에서 전체 로스터로 돌아간다(#816).
  static String clientDetail(String id, {String? section, String? filter}) {
    final safeSection = clientSections.contains(section)
        ? section!
        : defaultClientSection;
    final path = '$clients/${Uri.encodeComponent(id)}/$safeSection';
    // 빈 맵을 넘기면 `?` 만 붙은 주소가 나온다 — 필터가 없을 때는 쿼리 자체를
    // 만들지 않는다.
    if (filter == null) return path;
    return Uri(
      path: path,
      queryParameters: <String, String>{'f': filter},
    ).toString();
  }

  /// Builds the 고객 list filtered to a preset. Used by the dashboard
  /// KPI cards (`unread` = 답장 필요, `attention` = 주의 고객).
  static String clientsFiltered(String filter) => Uri(
    path: clients,
    queryParameters: <String, String>{'f': filter},
  ).toString();

  /// Builds the standalone 메시지 workspace with an optional selected client
  /// and conversation filter (`all` | `unread` | `attention`).
  static String messagesFor(String? clientId, {String? filter}) => Uri(
    path: messages,
    queryParameters: <String, String>{'client': ?clientId, 'f': ?filter},
  ).toString();

  /// Builds the AI 코칭 workspace with [clientId] preselected.
  static String coachingFor(String clientId) => Uri(
    path: coaching,
    queryParameters: <String, String>{'client': clientId},
  ).toString();

  /// Builds the 리포트 tab focused on [clientId].
  ///
  /// [weekStart] 를 주면 그 주가 선택된 채로 열린다. 채팅의 리포트 카드가
  /// 가리키는 주와 리포트 화면이 보여 주는 주가 어긋나면, 트레이너는 카드를
  /// 누르고도 어느 주였는지 다시 찾아야 한다(#1421).
  ///
  /// [clientId] 가 null 이면 작업대(회원을 고르기 전 목록)다. 주를 옮긴
  /// 작업대도 새로고침·뒤로 가기에서 그 주로 돌아와야 해서 주만 싣는다(#2289).
  static String reportFor(String? clientId, {DateTime? weekStart}) {
    final Map<String, String> query = <String, String>{
      'client': ?clientId,
      if (weekStart != null) 'week': ymd(weekStart),
    };
    return Uri(
      path: reports,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// [clientId] 회원의 지난 리포트 화면(#2394).
  ///
  /// `history` 로 싣는다 — `client` 는 편집기라, 같은 값에 두 뜻을 얹지 않는다.
  /// [weekStart] 는 작업대에서 보고 있던 주다. 지난 리포트에서 `회원 목록` 으로
  /// 돌아가면 그 주 작업대로 선다.
  static String reportHistoryFor(String clientId, {DateTime? weekStart}) {
    return Uri(
      path: reports,
      queryParameters: <String, String>{
        'history': clientId,
        if (weekStart != null) 'week': ymd(weekStart),
      },
    ).toString();
  }

  /// 리포트 URL 의 `week` 값을 날짜로 읽는다.
  ///
  /// `yyyy-MM-dd` 만 받는다. 형식이 깨졌거나 달력에 없는 날(`2026-02-30`)은
  /// null — 다음 달로 넘겨 엉뚱한 주를 여는 것보다 이번 주로 여는 편이
  /// 낫다(#2289).
  static DateTime? parseReportWeek(String? raw) {
    if (raw == null) return null;
    final RegExpMatch? m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final int year = int.parse(m.group(1)!);
    final int month = int.parse(m.group(2)!);
    final int day = int.parse(m.group(3)!);
    final DateTime date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  /// Builds the 스케줄 tab on a given date.
  ///
  /// 보기가 주간 시간표 하나뿐이라 `v=` 는 없다(#988). 날짜만 실어 보낸다.
  static String scheduleAt({String? date, String? sessionId}) {
    // [clientDetail] 과 같은 이유로 빈 맵을 넘기지 않는다 — `Uri` 는 빈 쿼리와
    // 쿼리 없음을 구분해, 빈 맵에는 `?` 만 붙은 `/schedule?` 를 돌려준다.
    if (date == null && sessionId == null) return schedule;
    return Uri(
      path: schedule,
      queryParameters: <String, String>{'d': ?date, 'session': ?sessionId},
    ).toString();
  }

  /// 후속 관리 할 일이 열어야 할 화면. (#869)
  ///
  /// 새 deep-link 체계를 만들지 않고 **이미 있는 route 를 고른다** — 할 일은
  /// "이 고객의 무엇을 다시 볼 것인가"라서, 그 무엇은 이미 화면을 갖고 있다.
  ///
  /// [contextWire] 는 서버 계약값(`context_type`)이다. 도메인 타입 대신 문자열을
  /// 받아 라우트 표가 특정 feature 의 enum 에 매이지 않게 둔다. 모르는 값은 고객
  /// 상세로 보낸다 — 갈 곳이 없다고 아무 데도 가지 않는 것보다, 그 고객 화면까지
  /// 데려다주는 편이 낫다.
  static String followUpTarget(String clientId, String contextWire) =>
      switch (contextWire) {
        'message' => messagesFor(clientId),
        'program' => coachingFor(clientId),
        'schedule' => scheduleAt(),
        'diet' => clientDetail(clientId, section: 'diet'),
        'exercise' => clientDetail(clientId, section: 'workout'),
        _ => clientDetail(clientId),
      };

  /// Builds the 내 정보 page on a given [tab] (`profile` | `settings`).
  static String mySection(String tab) =>
      Uri(path: my, queryParameters: <String, String>{'t': tab}).toString();

  // --- Deep-link resume (#701) ---

  /// Query key that parks a destination on the sign-in URL while the
  /// session is being restored (or logged into).
  static const String resumeParam = 'from';

  /// The path every in-app location hangs off. Used to recognise a
  /// destination worth coming back to after the session resolves.
  static const List<String> _appRoots = <String>[
    dashboard,
    clients,
    schedule,
    messages,
    coaching,
    reports,
    my,
    legacyConsultations,
    notifications,
  ];

  /// Is [location] an in-app destination the app may return to?
  ///
  /// Deliberately strict: the value travels through a URL the user (or a
  /// shared link) controls, so anything with a scheme or an authority is
  /// rejected — `?from=https://elsewhere` must never become a redirect.
  /// Unknown paths are rejected too, so a stale link resumes onto the
  /// 대시보드 rather than the router's error screen.
  static bool isRestorable(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return false;
    final path = uri.path;
    return _appRoots.any((root) => path == root || path.startsWith('$root/'));
  }

  /// The sign-in URL, carrying [location] so the app can resume there
  /// once the session is known. A location that isn't restorable is
  /// simply dropped — sign-in still works, it just lands on the 대시보드.
  static String signInResuming(String location) => isRestorable(location)
      ? Uri(
          path: signIn,
          queryParameters: <String, String>{resumeParam: location},
        ).toString()
      : signIn;

  /// The parked destination on an auth URL, or null when there is none
  /// (or it failed [isRestorable]).
  static String? resumeTarget(String location) {
    final from = Uri.tryParse(location)?.queryParameters[resumeParam];
    if (from == null || !isRestorable(from)) return null;
    return from;
  }
}
