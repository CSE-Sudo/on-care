/// 브라우저 알림과 탭 아이콘 표시(#3285).
///
/// 콘솔 탭이 열려 있으면 다른 탭·다른 프로그램을 쓰는 중에도 새 알림을 화면
/// 구석에 띄우고, 탭 아이콘에 빨간 점을 찍는다. 서버 키가 필요 없는 Notification
/// API 라 **탭이 열려 있을 때만** 동작한다 — 탭을 닫아도 오는 웹 푸시는 #3286.
///
/// 웹은 [createBrowserAlerts] 가 브라우저 구현을, 웹이 아닌 곳(테스트 등)은
/// 아무것도 하지 않는 구현을 돌려준다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/desktop_alerts/data/browser_alerts_platform.dart';

/// 이 브라우저의 알림 권한.
enum BrowserAlertPermission {
  /// 허용됨.
  granted,

  /// 아직 묻지 않음 — 켜면 브라우저가 묻는다.
  notAsked,

  /// 차단됨 — 사이트가 다시 물을 수 없다. 주소창의 사이트 설정에서만 풀린다.
  denied,

  /// 이 브라우저에서는 쓸 수 없다. iPad Safari 는 탭에서 알림 기능 자체가 없고,
  /// 안드로이드 Chrome 은 페이지가 직접 띄우는 알림을 막는다(#3286 의 웹 푸시 몫).
  unsupported,
}

/// 브라우저 알림 한 건.
typedef BrowserAlert = ({String title, String body, String tag});

/// 브라우저의 알림·포커스·탭 아이콘.
abstract interface class BrowserAlerts {
  /// 지금 권한. 사용자가 주소창에서 바꿀 수 있어 매번 새로 읽는다.
  BrowserAlertPermission get permission;

  /// 권한을 묻는다. 이미 정해졌으면 묻지 않고 그 값을 돌려준다.
  Future<BrowserAlertPermission> requestPermission();

  /// 화면 구석에 알림을 띄운다. 같은 [BrowserAlert.tag] 는 앞의 알림을 바꿔
  /// 끼운다 — 탭이 둘 열려 있어도 한 번만 보인다. 누르면 이 탭을 앞으로
  /// 가져온 뒤 [onClick] 을 부른다.
  void show(BrowserAlert alert, {required void Function() onClick});

  /// 트레이너가 지금 이 탭을 보고 있는가 — 보이고, 창에 포커스가 있다.
  /// 보고 있으면 머리의 알림 종이 알리므로 화면 구석 알림은 띄우지 않는다.
  bool get pageFocused;

  /// 탭 아이콘에 빨간 점을 찍거나(참) 원래 아이콘으로 되돌린다.
  void setIconDot({required bool on});
}

/// 아무것도 하지 않는 구현 — 웹이 아닌 빌드와 테스트.
class NoBrowserAlerts implements BrowserAlerts {
  const NoBrowserAlerts();

  @override
  BrowserAlertPermission get permission => BrowserAlertPermission.unsupported;

  @override
  Future<BrowserAlertPermission> requestPermission() async => permission;

  @override
  void show(BrowserAlert alert, {required void Function() onClick}) {}

  @override
  bool get pageFocused => true;

  @override
  void setIconDot({required bool on}) {}
}

/// 이 브라우저의 알림 기능.
final browserAlertsProvider = Provider<BrowserAlerts>(
  (ref) => createBrowserAlerts(),
  name: 'browserAlerts',
);
