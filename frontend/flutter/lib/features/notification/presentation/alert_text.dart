import 'package:demo_fixture/demo_fixture.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 알림 한 줄에 보일 제목·본문. (#1812)
///
/// 데모 알림은 [AlertItem.messageKey] 로 ARB 의 ko·en 문장을 고른다. 서버가 만든
/// 알림은 번역본이 없으므로 받은 문자열을 그대로 쓴다. 모르는 키도 문자열로
/// 돌아간다 — 빈 줄보다 한국어 한 줄이 낫다.
({String title, String body}) alertText(AppLocalizations l, AlertItem item) {
  final (String, String)? demo = switch (item.messageKey) {
    kDemoAlertSodium => (l.demoAlertSodiumTitle, l.demoAlertSodiumBody),
    kDemoAlertDinner => (l.demoAlertDinnerTitle, l.demoAlertDinnerBody),
    kDemoAlertRoutine => (
      l.demoAlertRoutineTitle,
      l.demoAlertRoutineBody(kDemoTrainerName),
    ),
    kDemoAlertReport => (
      l.demoAlertReportTitle,
      l.demoAlertReportBody(kDemoTrainerName),
    ),
    kDemoAlertPtDone => (
      l.demoAlertPtDoneTitle,
      l.demoAlertPtDoneBody(kDemoTrainerName),
    ),
    kDemoAlertTrainerFeedback => (
      l.demoAlertTrainerFeedbackTitle,
      l.demoAlertTrainerFeedbackBody,
    ),
    kDemoAlertWeeklyGoal => (
      l.demoAlertWeeklyGoalTitle,
      l.demoAlertWeeklyGoalBody,
    ),
    kDemoAlertMealStreak => (
      l.demoAlertMealStreakTitle,
      l.demoAlertMealStreakBody,
    ),
    kDemoAlertMaintenance => (
      l.demoAlertMaintenanceTitle,
      l.demoAlertMaintenanceBody,
    ),
    _ => null,
  };
  if (demo == null) return (title: item.title, body: item.body);
  return (title: demo.$1, body: demo.$2);
}

/// 알림의 상대 시각("10분 전" / "10m ago"). (#1812)
///
///  * 데모 알림은 [AlertItem.age] 로 로케일에 맞게 쓴다.
///  * 서버·로컬 알림은 이미 셈해 온 한국어 `time_ago` 를 로케일 문장으로 옮긴다.
///
/// 서버 알림을 `created_at` 으로 다시 셈하지 않는 이유: 서버는 오프셋 없는 시각을
/// UTC 로, 로컬 목 모드는 서울 벽시계로 저장한다. 앱이 둘을 구분할 수 없어
/// 한쪽이 9시간 어긋난다(#850). 시각은 보낸 쪽이 이미 맞게 셈했다.
String alertTimeAgo(AppLocalizations l, AlertItem item) {
  final Duration? age = item.age;
  if (age != null) return formatAlertAge(l, age);
  return localizeTimeAgo(l, item.timeAgo);
}

/// 경과 시간 → 상대 시각. 구간은 로컬 인터셉터가 한국어로 셈하는 규칙과 같다
/// (1분·1시간·하루·이틀).
String formatAlertAge(AppLocalizations l, Duration age) {
  if (age.inMinutes < 1) return l.alertTimeJustNow;
  if (age.inMinutes < 60) return l.alertTimeMinutesAgo(age.inMinutes);
  if (age.inHours < 24) return l.alertTimeHoursAgo(age.inHours);
  if (age.inDays == 1) return l.alertTimeYesterday;
  return l.alertTimeDaysAgo(age.inDays);
}

final RegExp _koreanAgo = RegExp(r'^(\d+)\s*(분|시간|일)\s*전$');

/// 서버·로컬 인터셉터가 만든 한국어 상대 시각 → 로케일 문장.
///
/// 두 곳이 쓰는 모양(`방금`·`방금 전`·`N분 전`·`N시간 전`·`어제`·`N일 전`)만
/// 옮기고, 모르는 모양은 받은 그대로 둔다 — 틀리게 옮기느니 원문이 낫다.
String localizeTimeAgo(AppLocalizations l, String raw) {
  final String text = raw.trim();
  if (text == '방금' || text == '방금 전') return l.alertTimeJustNow;
  if (text == '어제') return l.alertTimeYesterday;
  final RegExpMatch? match = _koreanAgo.firstMatch(text);
  if (match == null) return raw;
  final int n = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    '분' => l.alertTimeMinutesAgo(n),
    '시간' => l.alertTimeHoursAgo(n),
    _ => l.alertTimeDaysAgo(n),
  };
}
