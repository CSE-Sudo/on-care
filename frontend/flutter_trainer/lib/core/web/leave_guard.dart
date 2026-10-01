/// 브라우저를 새로 고치거나 탭을 닫을 때 "나가시겠어요?" 를 묻게 한다. (#2264)
///
/// 앱 안의 이동(뒤로·메뉴)은 화면이 직접 묻는다. 새로 고침·탭 닫기·주소 입력은
/// 앱 밖의 일이라 브라우저의 `beforeunload` 로만 막을 수 있다 — 브라우저가 자기
/// 문구로 확인창을 띄우고, 사이트는 문구를 정할 수 없다.
///
/// `setLeaveGuard(owner, shouldBlock)` — [shouldBlock] 을 주면 떠나려는 그
/// 순간에 물어본다(입력 칸이 바뀔 때마다 등록을 다시 하지 않아도 된다). `null`
/// 이면 그 [owner] 의 지킴만 푼다. 여러 화면이 함께 지킬 수 있고, 하나라도 막으려
/// 하면 막는다(#2873, [LeaveGuardRegistry]). 웹이 아닌 곳(테스트 등)에서는
/// 목록만 들고 브라우저에는 아무 일도 하지 않는다.
library;

export 'leave_guard_registry.dart' show LeaveGuardRegistry, leaveGuards;
export 'leave_guard_stub.dart'
    if (dart.library.js_interop) 'leave_guard_web.dart';
