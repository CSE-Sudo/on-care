import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원앱 아이콘 목록(#1803) — 회원앱 화면이 쓰는 아이콘은 모두 여기서 고른다.
///
/// 한 세트(Material Symbols Rounded)에서만 고르고, 모양은 [oncare] 가 정한다:
/// 채움(FILL 1)·굵기 400·등급 0, 광학 크기는 그리는 크기(20~48)를 따른다. 운동
/// 아이콘([exercise])만 굵기 300 으로 얇다. 그리는 쪽은 `Icon` 대신 [AppIcon] 을
/// 써야 이 모양이 실린다.
///
/// 이름은 모양이 아니라 화면에서의 뜻으로 짓는다. 같은 모양을 뜻에 따라 다른
/// 이름으로 부를 수 있다([gym] 은 [exercise] 와 같은 모양). 화면 코드에서
/// `Icons.*`·`Symbols.*`·`Icon(` 을 직접 쓰면 UI 가드(`tool/ui_guard`)가 막는다.
class AppIcons {
  AppIcons._();

  // --- 하단 탭 ---
  static const IconData home = Symbols.home_rounded;
  static const IconData diet = Symbols.restaurant_rounded;

  /// 운동 — 이 목록에서 유일하게 굵기 300 이다([oncare] 의 예외).
  static const IconData exercise = Symbols.exercise_rounded;
  static const IconData my = Symbols.person_rounded;

  // --- 운동 ---
  /// 헬스장·소속. 운동 아이콘과 같은 모양이라 굵기도 같다.
  static const IconData gym = exercise;

  /// 운동 유형 `근력`. 운동 그래프 링 12시에 **작게(≈14px)** 얹히는 자리라,
  /// 획이 겹친 [exercise](덤벨 두 개)를 채우면 틈이 사라져 덩어리로 뭉친다.
  /// 획이 단순한 덤벨 한 개로 둔다 — #1803 전 회원앱과 지금 트레이너웹이 같은
  /// 링에서 쓰는 그림이다. (#1866)
  static const IconData strength = Symbols.fitness_center_rounded;
  static const IconData running = Symbols.directions_run_rounded;
  static const IconData flexibility = Symbols.self_improvement_rounded;
  static const IconData calories = Symbols.local_fire_department_rounded;
  static const IconData streak = Symbols.bolt_rounded;
  static const IconData routine = Symbols.list_alt_rounded;
  static const IconData timer = Symbols.timer_rounded;
  static const IconData exerciseLog = Symbols.event_note_rounded;

  // --- 사람·계정 ---
  static const IconData person = Symbols.person_rounded;
  static const IconData personOff = Symbols.person_off_rounded;
  static const IconData badge = Symbols.badge_rounded;
  static const IconData certificate = Symbols.workspace_premium_rounded;
  static const IconData mail = Symbols.mail_rounded;
  static const IconData phone = Symbols.call_rounded;
  static const IconData lock = Symbols.lock_rounded;
  static const IconData unlock = Symbols.lock_open_rounded;
  static const IconData visibility = Symbols.visibility_rounded;
  static const IconData visibilityOff = Symbols.visibility_off_rounded;
  static const IconData logout = Symbols.logout_rounded;
  static const IconData disconnect = Symbols.link_off_rounded;

  // --- 알림·소통 ---
  static const IconData notifications = Symbols.notifications_rounded;
  static const IconData notificationsOff = Symbols.notifications_off_rounded;

  /// 알림 갈래 — 건강 확인·달성.
  static const IconData healthCheck = Symbols.monitor_heart_rounded;
  static const IconData achievement = Symbols.emoji_events_rounded;
  static const IconData chat = Symbols.chat_bubble_rounded;
  static const IconData help = Symbols.help_rounded;
  static const IconData privacy = Symbols.privacy_tip_rounded;
  static const IconData document = Symbols.description_rounded;
  static const IconData note = Symbols.note_alt_rounded;
  static const IconData guide = Symbols.menu_book_rounded;
  static const IconData request = Symbols.assignment_rounded;
  static const IconData ai = Symbols.auto_awesome_rounded;

  /// AI 챗봇으로 들어가는 자리 — 말풍선 안에 별. (#1900)
  ///
  /// [ai](반짝이)와 나눠 둔다. 반짝이는 "이 값은 AI 가 만들었다" 는 표시이고,
  /// 이것은 "여기서 AI 와 이야기한다" 는 입구다. 옆자리의 트레이너 채팅([chat])과
  /// 같은 말풍선 계열이라, 담당이 있고 없고에 따라 바뀌는 한 자리로 읽힌다.
  static const IconData aiChat = Symbols.assistant_rounded;

  // --- 날짜·시간·장소 ---
  static const IconData calendar = Symbols.calendar_today_rounded;
  static const IconData clock = Symbols.schedule_rounded;
  static const IconData eventAvailable = Symbols.event_available_rounded;
  static const IconData eventBusy = Symbols.event_busy_rounded;
  static const IconData location = Symbols.location_on_rounded;
  static const IconData keyboard = Symbols.keyboard_rounded;

  // --- 보상·목표 ---
  static const IconData star = Symbols.star_rounded;
  static const IconData points = Symbols.stars_rounded;
  static const IconData savings = Symbols.savings_rounded;
  static const IconData goal = Symbols.flag_rounded;
  static const IconData favorite = Symbols.favorite_rounded;
  static const IconData sync = Symbols.sync_rounded;

  // --- 이동·펼침 ---
  static const IconData back = Symbols.chevron_left_rounded;
  static const IconData chevronLeft = Symbols.chevron_left_rounded;
  static const IconData chevronRight = Symbols.chevron_right_rounded;
  static const IconData expandMore = Symbols.keyboard_arrow_down_rounded;
  static const IconData expandLess = Symbols.keyboard_arrow_up_rounded;

  /// 날짜 선택창 머리의 삼각형 — 달 보기 열기(▾)·닫기(▴).
  static const IconData calendarExpand = Symbols.arrow_drop_down_rounded;
  static const IconData calendarCollapse = Symbols.arrow_drop_up_rounded;
  static const IconData external = Symbols.open_in_new_rounded;
  static const IconData close = Symbols.close_rounded;

  // --- 동작 ---
  static const IconData add = Symbols.add_rounded;
  static const IconData remove = Symbols.remove_rounded;
  static const IconData edit = Symbols.edit_rounded;
  static const IconData delete = Symbols.delete_rounded;
  static const IconData check = Symbols.check_rounded;
  static const IconData search = Symbols.search_rounded;
  static const IconData send = Symbols.arrow_upward_rounded;

  // --- 상태 ---
  static const IconData info = Symbols.info_rounded;
  static const IconData checkCircle = Symbols.check_circle_rounded;
  static const IconData warning = Symbols.warning_rounded;
  static const IconData error = Symbols.error_rounded;
  static const IconData empty = Symbols.inbox_rounded;
  static const IconData offline = Symbols.cloud_off_rounded;
  static const IconData searchOff = Symbols.search_off_rounded;

  // --- 사진·파일 ---
  static const IconData image = Symbols.image_rounded;
  static const IconData imageUnavailable = Symbols.image_not_supported_rounded;
  static const IconData camera = Symbols.photo_camera_rounded;
  static const IconData attachImage = Symbols.add_photo_alternate_rounded;
  static const IconData file = Symbols.picture_as_pdf_rounded;

  /// 회원앱 테마에 넣는 아이콘 묶음 — 공용 컴포넌트(뒤로·닫기·꺾쇠·빈 화면·배너·
  /// 토스트 …)도 회원앱에서는 이 목록으로 그린다.
  static const OnCareIconSet oncare = OnCareIconSet(
    name: 'member',
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
    file: file,
    reward: star,
    timeInput: keyboard,
    timeDial: clock,
    fill: 1,
    weight: 400,
    grade: 0,
    minOpticalSize: 20,
    maxOpticalSize: 48,
    weightOverrides: <OnCareIconWeight>[OnCareIconWeight(exercise, 300)],
  );
}
