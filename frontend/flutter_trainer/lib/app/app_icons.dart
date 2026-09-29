import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너웹 아이콘 목록(#2466) — 트레이너웹 화면이 쓰는 아이콘은 모두 여기서 고른다.
///
/// 회원앱 목록(`frontend/flutter/lib/app/app_icons.dart`, #1803)과 같은 한 세트
/// (Material Symbols Rounded)에서만 고르고, 모양은 [oncare] 가 정한다: 채움(FILL 1)·
/// 굵기 400·등급 0, 광학 크기는 그리는 크기(20~48)를 따른다. 그리는 쪽은 `Icon`
/// 대신 [AppIcon] 을 써야 이 모양이 실린다.
///
/// 이름은 모양이 아니라 화면에서의 뜻으로 짓는다. 회원앱에 같은 뜻이 있으면 같은
/// 모양을 쓴다(삭제·채팅·경고·메모 …). 외곽선 글리프(`*_outline`·`*_border` …)는
/// 두지 않는다 — 켜짐·꺼짐 같은 상태는 모양이 아니라 색·배경으로 가른다.
/// 화면 코드에서 `Icons.*`·`Symbols.*`·`Icon(` 을 직접 쓰면 UI 가드
/// (`tool/ui_guard`)가 막는다.
class AppIcons {
  AppIcons._();

  // --- 사이드바 ---
  static const IconData dashboard = Symbols.space_dashboard_rounded;

  /// 회원 여러 명 — 사이드바 `회원`·대시보드와 MY 의 `내 회원 수`·빈 목록이
  /// 모두 이 모양이다. 예전에는 같은 숫자가 화면마다 다른 사람 그림이었다.
  static const IconData clients = Symbols.group_rounded;

  /// 코칭 — 회원 상세의 `프로그램` 버튼과 같은 운동 계획서(#2330). 반짝이(✦)는
  /// [ai] 표시라 메뉴가 AI 기능처럼 읽힌다. 검색 빠른 이동도 이 모양이다.
  static const IconData coaching = Symbols.assignment_rounded;

  /// 리포트 — 회원 상세의 `리포트` 버튼·검색 빠른 이동과 같은 그림(#2330).
  static const IconData reports = Symbols.analytics_rounded;

  /// 상담 요청함.
  static const IconData consultation = Symbols.mark_email_unread_rounded;
  static const IconData notifications = Symbols.notifications_rounded;
  static const IconData menu = Symbols.menu_rounded;
  static const IconData settings = Symbols.settings_rounded;

  /// 사이드바 로고를 못 읽었을 때 대신 서는 그림.
  static const IconData favorite = Symbols.favorite_rounded;

  // --- 운동·식단 ---
  static const IconData diet = Symbols.restaurant_rounded;
  static const IconData exercise = Symbols.fitness_center_rounded;

  /// 운동 유형 `근력` — 회원앱처럼 [exercise] 와 같은 덤벨이다.
  static const IconData strength = exercise;

  /// 운동 유형 `유산소` — 회원앱 running 과 같은 달리는 사람. 이 모양은 유산소만
  /// 뜻한다([personalRoutine] 참고).
  static const IconData running = Symbols.directions_run_rounded;
  static const IconData flexibility = Symbols.self_improvement_rounded;
  static const IconData calories = Symbols.local_fire_department_rounded;

  /// 연속 기록 — 불꽃은 [calories] 가 쓰므로 기세 쪽 기호로 가른다.
  static const IconData streak = Symbols.bolt_rounded;

  /// 개인 루틴(PT 와 함께 가는 개인운동, #2223). 예전에는 [running] 과 같은 달리는
  /// 사람이라 유산소 기호와 구별되지 않았다 — 개인운동은 유산소만이 아니다.
  /// 회원앱이 트레이너가 보낸 루틴에 쓰는 목록 모양(routine)을 그대로 쓴다.
  static const IconData personalRoutine = Symbols.list_alt_rounded;

  /// 프로그램 템플릿.
  static const IconData template = Symbols.dashboard_customize_rounded;

  /// 템플릿으로 저장 — 저장 전(더하기)과 저장 뒤(체크)를 모양으로도 가른다.
  /// 예전에는 빈 북마크와 채운 북마크였다.
  static const IconData saveTemplate = Symbols.bookmark_add_rounded;
  static const IconData templateSaved = Symbols.bookmark_added_rounded;

  /// AI 가 읽은 자료·검토 끝내기.
  static const IconData review = Symbols.fact_check_rounded;

  /// 개인운동을 편집기(템플릿)에 넣기.
  static const IconData applyToTemplate = Symbols.playlist_add_check_rounded;

  /// 운동·세션 끌어 옮기기 손잡이.
  static const IconData dragHandle = Symbols.drag_indicator_rounded;

  /// 세션 순서 올리기·내리기. 펼침 화살표([expandMore])와 뜻이 달라 모양도 가른다.
  static const IconData moveUp = Symbols.arrow_upward_rounded;
  static const IconData moveDown = Symbols.arrow_downward_rounded;

  /// 운동을 다른 세션으로 옮기기.
  static const IconData moveToSession = Symbols.drive_file_move_rounded;

  /// 휴면 회원 표시.
  static const IconData dormant = Symbols.bedtime_rounded;
  static const IconData goal = Symbols.flag_rounded;

  /// AI 가 만든 값·AI 동작 표시(회원앱 ai 와 같다).
  static const IconData ai = Symbols.auto_awesome_rounded;

  // --- 사람·계정 ---
  static const IconData person = Symbols.person_rounded;

  /// 초대 거절·노쇼·이탈 위험.
  static const IconData personOff = Symbols.person_off_rounded;

  /// 회원이 연결을 끊고 나감.
  static const IconData memberLeft = Symbols.person_remove_rounded;

  /// 초대 수락.
  static const IconData inviteAccepted = Symbols.how_to_reg_rounded;
  static const IconData addClient = Symbols.person_add_rounded;

  /// 회원을 먼저 고르라는 빈 화면.
  static const IconData selectClient = Symbols.person_search_rounded;

  /// 트레이너가 직접 배정한 것·이름.
  static const IconData badge = Symbols.badge_rounded;
  static const IconData certificate = Symbols.workspace_premium_rounded;

  /// 헬스장 연결 확인.
  static const IconData verified = Symbols.verified_rounded;
  static const IconData mail = Symbols.mail_rounded;
  static const IconData lock = Symbols.lock_rounded;

  /// 비밀번호 바꾸기.
  static const IconData password = Symbols.key_rounded;
  static const IconData visibility = Symbols.visibility_rounded;
  static const IconData visibilityOff = Symbols.visibility_off_rounded;
  static const IconData logout = Symbols.logout_rounded;

  /// 끊긴 링크 — 없는 주소 화면.
  static const IconData disconnect = Symbols.link_off_rounded;

  /// 가입 초대 코드 — 회원앱 쿠폰과 같은 표 한 장.
  static const IconData inviteCode = Symbols.confirmation_number_rounded;

  // --- 알림·소통 ---
  /// 채팅·메시지 — 회원앱 chat 과 같은 채운 말풍선. 사이드바 `메시지`·빠른 이동·
  /// 빈 대화·문의 채팅이 모두 이 모양이다.
  static const IconData chat = Symbols.chat_bubble_rounded;

  /// 답장이 필요한 메시지 수.
  static const IconData unreadMessages = Symbols.mark_chat_unread_rounded;
  static const IconData help = Symbols.help_rounded;
  static const IconData privacy = Symbols.privacy_tip_rounded;
  static const IconData document = Symbols.description_rounded;

  /// 메모 — 회원앱 note 와 같은 모양 하나. 메모가 있을 때(수정)와 없을 때(추가)도
  /// 같은 모양이고 글씨로 가른다.
  static const IconData note = Symbols.note_alt_rounded;

  /// 글을 직접 쓰기 시작하는 동작(직접 만들기·처음부터 쓰기·초안으로 쓰기).
  /// 메모([note])와 다른 뜻이다.
  static const IconData write = Symbols.edit_note_rounded;
  static const IconData language = Symbols.language_rounded;

  /// 고객 지원.
  static const IconData support = Symbols.support_agent_rounded;

  // --- 날짜·시간 ---
  /// 날짜·달력·오늘로 이동·요일별 표. 일정 계열은 이것과 [eventAvailable]·
  /// [eventBusy]·[editSchedule] 넷만 쓴다.
  static const IconData calendar = Symbols.calendar_today_rounded;
  static const IconData clock = Symbols.schedule_rounded;

  /// 예약 가능 시간·확정된 예약.
  static const IconData eventAvailable = Symbols.event_available_rounded;

  /// 취소·끝난 약속.
  static const IconData eventBusy = Symbols.event_busy_rounded;

  /// 일정(날짜·시각) 고치기.
  static const IconData editSchedule = Symbols.edit_calendar_rounded;
  static const IconData history = Symbols.history_rounded;

  /// 리포트 인쇄(#2451).
  static const IconData print = Symbols.print_rounded;

  /// 보낸 기록이 없을 때.
  static const IconData sent = Symbols.outbox_rounded;
  static const IconData keyboard = Symbols.keyboard_rounded;

  // --- 분석 ---
  /// 식단 분석 카드.
  static const IconData insights = Symbols.insights_rounded;

  /// 대시보드 활동 피드백 — 규칙으로 고른 코칭 제안이라 [ai] 반짝이를 달지
  /// 않는다(#2468).
  static const IconData activityFeedback = Symbols.tips_and_updates_rounded;

  /// 할 일 진행률.
  static const IconData progress = Symbols.stacked_bar_chart_rounded;

  /// 건강 주의 회원 수.
  static const IconData attention = Symbols.report_rounded;

  // --- 이동·펼침 ---
  static const IconData back = Symbols.chevron_left_rounded;
  static const IconData chevronLeft = Symbols.chevron_left_rounded;
  static const IconData chevronRight = Symbols.chevron_right_rounded;

  /// 펼치기·접기 — 회원앱 expandMore 와 같은 꺾쇠 한 계열만 쓴다. 선택 버튼의
  /// 펼침 표시도 이것이다.
  static const IconData expandMore = Symbols.keyboard_arrow_down_rounded;
  static const IconData expandLess = Symbols.keyboard_arrow_up_rounded;

  /// 날짜 선택창 머리의 삼각형 — 달 보기 열기(▾)·닫기(▴). 공용 날짜 선택창만 쓴다.
  static const IconData calendarExpand = Symbols.arrow_drop_down_rounded;
  static const IconData calendarCollapse = Symbols.arrow_drop_up_rounded;

  /// 더 보기 메뉴 — 가로 점 셋 하나만 쓴다.
  static const IconData more = Symbols.more_horiz_rounded;
  static const IconData external = Symbols.open_in_new_rounded;
  static const IconData forward = Symbols.arrow_forward_rounded;

  /// 검색 결과에서 Enter 로 여는 표시.
  static const IconData enter = Symbols.subdirectory_arrow_left_rounded;
  static const IconData close = Symbols.close_rounded;

  // --- 동작 ---
  static const IconData add = Symbols.add_rounded;

  /// 목록 행 끝의 `불러오기` 표시.
  static const IconData addCircle = Symbols.add_circle_rounded;
  static const IconData remove = Symbols.remove_rounded;
  static const IconData edit = Symbols.edit_rounded;

  /// 삭제 — 회원앱 delete 와 같은 채운 휴지통. 목록에서 빼기도 이것이다.
  static const IconData delete = Symbols.delete_rounded;
  static const IconData check = Symbols.check_rounded;

  /// 모두 읽음.
  static const IconData markAllRead = Symbols.done_all_rounded;
  static const IconData search = Symbols.search_rounded;
  static const IconData send = Symbols.send_rounded;
  static const IconData refresh = Symbols.refresh_rounded;
  static const IconData undo = Symbols.undo_rounded;
  static const IconData redo = Symbols.redo_rounded;
  static const IconData save = Symbols.save_rounded;
  static const IconData zoomIn = Symbols.zoom_in_rounded;
  static const IconData zoomOut = Symbols.zoom_out_rounded;
  static const IconData emote = Symbols.sentiment_satisfied_rounded;

  // --- 상태 ---
  static const IconData info = Symbols.info_rounded;
  static const IconData checkCircle = Symbols.check_circle_rounded;
  static const IconData warning = Symbols.warning_rounded;
  static const IconData error = Symbols.error_rounded;
  static const IconData empty = Symbols.inbox_rounded;
  static const IconData offline = Symbols.cloud_off_rounded;
  static const IconData star = Symbols.star_rounded;

  // --- 사진·파일 ---
  static const IconData image = Symbols.image_rounded;
  static const IconData imageUnavailable = Symbols.image_not_supported_rounded;
  static const IconData attachImage = Symbols.add_photo_alternate_rounded;
  static const IconData file = Symbols.picture_as_pdf_rounded;

  /// 트레이너웹 테마에 넣는 아이콘 묶음 — 공용 컴포넌트(뒤로·닫기·꺾쇠·빈 화면·
  /// 배너·토스트 …)도 트레이너웹에서는 이 목록으로 그린다. 모양 규칙은 회원앱
  /// 묶음과 같다.
  static const OnCareIconSet oncare = OnCareIconSet(
    name: 'trainer',
    back: back,
    close: close,
    previous: chevronLeft,
    next: chevronRight,
    disclosure: chevronRight,
    dropdown: expandMore,
    calendarExpand: calendarExpand,
    calendarCollapse: calendarCollapse,
    search: search,
    add: add,
    remove: remove,
    check: check,
    info: info,
    success: checkCircle,
    caution: warning,
    error: error,
    empty: empty,
    offline: offline,
    image: image,
    attachImage: attachImage,
    send: send,
    emote: emote,
    file: file,
    reward: star,
    mail: mail,
    lock: lock,
    visibility: visibility,
    visibilityOff: visibilityOff,
    timeInput: keyboard,
    timeDial: clock,
    fill: 1,
    weight: 400,
    grade: 0,
    minOpticalSize: 20,
    maxOpticalSize: 48,
  );
}
