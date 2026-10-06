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

  /// 가입 동의(#2819) — 동의가 남은 계정이 로그인하면 다른 화면보다 먼저 온다.
  static const String consent = '/auth/consent';

  /// 비밀번호 재설정(#2824). 로그인 화면과 재설정 메일의 링크(`?token=…`)가
  /// 연다. 세션 상태와 상관없이 열린다 — 링크를 어느 상태에서 열어도 코드를
  /// 잃지 않는다.
  static const String passwordReset = '/auth/password-reset';

  /// 아이디(가입 이메일) 찾기. 로그인 화면이 연다. 가입 화면처럼 로그아웃
  /// 상태에서만 머문다 — 로그인한 채 열면 대시보드로 간다. 찾기는 아직 준비 중이다.
  static const String findEmail = '/auth/find-email';

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

  /// 스케줄을 열면서 그 위에 상담 요청함 **창**을 띄우라는 쿼리. (#2717)
  static const String inboxParam = 'inbox';

  /// 상담 요청함 — 스케줄 위에 뜨는 창이다. 페이지가 따로 없다(#2717).
  ///
  /// 알림처럼 상담함으로 보내야 하는 길은 이 주소로 스케줄에 가고, 스케줄이
  /// 창을 연 뒤 쿼리를 지운다 — 스케줄·대시보드 버튼이 여는 창과 같은 창이다.
  static const String consultations = '$schedule?$inboxParam=1';

  /// 예전 상담함 주소들 — 독립 탭(`/consultations`)과 스케줄 하위 페이지
  /// (`/schedule/consultations`). 남은 링크는 [consultations] 로 보낸다.
  static const String legacyConsultations = '/consultations';
  static const String legacyScheduleConsultations = '$schedule/consultations';

  /// 신고·계정 관리 — 운영자 계정에만 보이는 운영 화면 (#3008).
  ///
  /// 운영자가 아니면 주소로 열어도 찾을 수 없음 안내만 그린다.
  static const String adminReports = '/admin/reports';

  /// 알림함 — 놓친 변화를 나중에 확인하는 자리. (#503)
  ///
  /// 들어오는 길은 화면 머리의 알림 종이다(#2628). 사이드바 탭이 아니다.
  static const String notifications = '/notifications';

  /// 알림 화면 — [from] 은 종을 누른 화면이다. 알림 화면의 뒤로 가기가 그리로
  /// 돌아간다(#2628). 셸의 갈래를 옮겨 오므로 되돌아갈 이력이 남지 않는다.
  static String notificationsFrom(String? from) =>
      from == null || from.isEmpty || from.startsWith(notifications)
      ? notifications
      : Uri(
          path: notifications,
          queryParameters: <String, String>{'from': from},
        ).toString();

  /// 알림 화면 뒤로 가기가 갈 곳. 콘솔 안의 주소만 받는다 — 밖으로 나가는
  /// 주소나 알림 화면 자신이면 대시보드다.
  static String notificationsBackTarget(String? from) =>
      from != null &&
          from.startsWith('/') &&
          !from.startsWith('//') &&
          !from.startsWith(notifications)
      ? from
      : dashboard;

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
  ///
  /// [openHealthNotes] 는 들어가자마자 신체·목표 창의 `건강 목표` 탭을 연다 —
  /// 주의사항 알림에서 온 길이다(#2619).
  ///
  /// [openFeedback] 은 메모 창의 `피드백` 탭을 연다 — 회원 주간 피드백 알림에서
  /// 온 길이다(#3026). 둘 다 주면 [openHealthNotes] 가 이긴다(한 번에 창 하나).
  static String clientDetail(
    String id, {
    String? section,
    String? filter,
    bool openHealthNotes = false,
    bool openFeedback = false,
  }) {
    final safeSection = clientSections.contains(section)
        ? section!
        : defaultClientSection;
    final path = '$clients/${Uri.encodeComponent(id)}/$safeSection';
    // 빈 맵을 넘기면 `?` 만 붙은 주소가 나온다 — 필터가 없을 때는 쿼리 자체를
    // 만들지 않는다.
    if (filter == null && !openHealthNotes && !openFeedback) return path;
    return Uri(
      path: path,
      queryParameters: <String, String>{
        'f': ?filter,
        if (openHealthNotes)
          clientOpenParam: clientOpenHealthNotes
        else if (openFeedback)
          clientOpenParam: clientOpenFeedback,
      },
    ).toString();
  }

  /// [clientDetail] 이 창을 열라고 알리는 쿼리 이름과 값.
  static const String clientOpenParam = 'open';
  static const String clientOpenHealthNotes = 'health-notes';
  static const String clientOpenFeedback = 'feedback';

  /// Builds the 고객 list filtered to a preset. Used by the dashboard
  /// KPI cards (`unread` = 답장 필요, `attention` = 주의 고객).
  static String clientsFiltered(String filter) => Uri(
    path: clients,
    queryParameters: <String, String>{'f': filter},
  ).toString();

  /// 회원 목록 — [filter] 가 있으면 그 필터를 건 목록, 없으면 전체 목록. (#2893)
  ///
  /// 상세를 닫을 때 돌아갈 자리다. 예전에는 닫기가 늘 [clients] 로 가, '주의
  /// 회원' 처럼 걸러 둔 목록에서 한 명을 닫을 때마다 필터가 풀렸다 — 메시지
  /// 탭([messagesFor])은 같은 상황에서 필터를 지킨다.
  static String clientsWith(String? filter) =>
      filter == null ? clients : clientsFiltered(filter);

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

  /// [clientId] 회원의 코칭 탭을 **그 PT 에 개인운동 붙이기**로 연다. (#2280)
  ///
  /// 일정 상세의 `개인운동 없음` 에서 온다. 개인운동은 AI 제안을 받아 짜는
  /// 것이라 코칭 탭의 개인운동 단계에서 짜고, 붙이면 [date] 의 그 일정
  /// ([sessionId])으로 돌아간다.
  ///
  /// [requestId] 는 누를 때마다 새로 만든다. 같은 PT 를 다시 누르면 주소가
  /// 같아, 한 번 닫은 흐름으로 읽혀 다시 열리지 않았다.
  static String coachingAttach(
    String clientId, {
    required String sessionId,
    required String date,
    required String requestId,
  }) => Uri(
    path: coaching,
    queryParameters: <String, String>{
      'client': clientId,
      'attach': sessionId,
      'd': date,
      'r': requestId,
    },
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
