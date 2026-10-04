import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_text.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

/// 서버가 영어 요청에 주는 상대 시각도 앱의 로케일 문장으로 옮긴다(#2302).
///
/// 앱은 Accept-Language 를 보내므로 영어 화면이면 서버가 `5 min ago` 처럼 영어로
/// 셈해 준다. 데모 알림과 같은 모양(`5m ago`)으로 맞춰 보여 준다.
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  test('서버의 영어 모양을 영어 로케일 문장으로 옮긴다', () {
    const Map<String, String> cases = <String, String>{
      'just now': 'Just now',
      '1 min ago': '1m ago',
      '5 min ago': '5m ago',
      '59 min ago': '59m ago',
      '1 hour ago': '1h ago',
      '3 hours ago': '3h ago',
      '1 day ago': '1d ago',
      '2 days ago': '2d ago',
      '  2 days ago ': '2d ago',
    };
    cases.forEach((String raw, String want) {
      expect(localizeTimeAgo(en, raw), want, reason: raw);
    });
  });

  test('한국어 로케일에서도 같은 값으로 옮긴다', () {
    expect(localizeTimeAgo(ko, 'just now'), '방금');
    expect(localizeTimeAgo(ko, '5 min ago'), '5분 전');
    expect(localizeTimeAgo(ko, '3 hours ago'), '3시간 전');
    expect(localizeTimeAgo(ko, '2 days ago'), '2일 전');
  });

  test('한국어 모양은 예전처럼 옮긴다', () {
    expect(localizeTimeAgo(en, '방금 전'), 'Just now');
    expect(localizeTimeAgo(en, '5분 전'), '5m ago');
    expect(localizeTimeAgo(ko, '5분 전'), '5분 전');
  });

  test('비슷하지만 다른 영어 모양은 받은 그대로 둔다', () {
    for (final String raw in <String>[
      '5 minutes ago',
      'a day ago',
      'in 5 min',
      '5 min',
      'Just Now!',
    ]) {
      expect(localizeTimeAgo(en, raw), raw, reason: raw);
    }
  });

  test('서버 알림 한 건의 상대 시각', () {
    const AlertItem item = AlertItem(
      id: 'n1',
      title: 'Appointment cancelled',
      body: '2026-10-01 09:00 · Consultation',
      timeAgo: '3 hours ago',
      category: AlertCategory.reminder,
    );
    expect(alertTimeAgo(en, item), '3h ago');
  });
}
