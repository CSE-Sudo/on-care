import 'package:oncare_trainer/features/desktop_alerts/data/browser_alerts.dart';

/// 웹이 아닌 빌드(테스트 포함): 브라우저 알림이 없다.
BrowserAlerts createBrowserAlerts() => const NoBrowserAlerts();
