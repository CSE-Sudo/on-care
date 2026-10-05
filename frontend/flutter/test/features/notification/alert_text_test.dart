import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/demo/demo_alert_keys.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/features/notification/presentation/alert_text.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

import '../../helpers/demo_notifications.dart';

/// 알림 문구·상대 시각의 로케일 처리(#1812).
void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  // 데모 알림함이 실제로 받는 목록 — drift 시드를 로컬 인터셉터로 읽은 것(#2660).
  late List<AlertItem> demoAlerts;
  setUpAll(() async {
    demoAlerts = await fetchDemoAlerts();
  });

  const AlertItem serverAlert = AlertItem(
    id: 'n1',
    title: '서버 제목',
    body: '서버 본문',
    timeAgo: '3분 전',
    category: AlertCategory.reminder,
  );

  group('제목·본문', () {
    test('데모 알림은 키로 로케일 문장을 고른다', () {
      final AlertItem feedback = demoAlerts.firstWhere(
        (AlertItem a) => a.messageKey == kDemoAlertTrainerFeedback,
      );
      expect(alertText(en, feedback).title, en.demoAlertTrainerFeedbackTitle);
      expect(alertText(en, feedback).body, en.demoAlertTrainerFeedbackBody);
      expect(alertText(ko, feedback).title, '트레이너 피드백이 도착했어요');
    });

    test('서버 알림과 모르는 키는 받은 문자열을 그대로 쓴다', () {
      expect(alertText(en, serverAlert).title, '서버 제목');
      const AlertItem unknown = AlertItem(
        id: 'x',
        title: '원문',
        body: '원문 본문',
        timeAgo: '방금',
        category: AlertCategory.system,
        messageKey: 'not_a_key',
      );
      expect(alertText(en, unknown), (title: '원문', body: '원문 본문'));
    });

    // 한국어 원문(`title`·`body`)은 키를 모르는 곳이 보는 값이다. ARB 의 한국어와
    // 한 글자라도 다르면 경로에 따라 다른 문장이 보인다.
    test('모든 데모 알림은 키가 있고 한국어 원문이 ARB 와 같다', () {
      for (final AlertItem a in demoAlerts) {
        expect(a.messageKey, isNotNull, reason: a.id);
        expect(alertText(ko, a), (title: a.title, body: a.body), reason: a.id);
        expect(alertTimeAgo(ko, a), a.timeAgo, reason: a.id);
        expect(alertText(en, a).title, isNot(a.title), reason: a.id);
        // 인터셉터가 셈한 한국어 시각도 영어 화면에서는 영어로 옮긴다.
        expect(alertTimeAgo(en, a), isNot(a.timeAgo), reason: a.id);
      }
    });

    test('로컬 시드 알림 id 마다 데모 목록에 같은 키가 있다', () {
      final Set<String> demoKeys = <String>{
        for (final AlertItem a in demoAlerts) a.messageKey!,
      };
      expect(kDemoAlertKeyBySeedId.values.toSet(), demoKeys);
      expect(kDemoAlertKeyBySeedId, hasLength(demoAlerts.length));
    });
  });

  group('상대 시각', () {
    test('서버·인터셉터의 한국어 time_ago 를 로케일 문장으로 옮긴다', () {
      final Map<String, String> cases = <String, String>{
        '방금': 'Just now',
        '방금 전': 'Just now',
        '10분 전': '10m ago',
        '1시간 전': '1h ago',
        '어제': 'Yesterday',
        '1일 전': '1d ago',
        '12일 전': '12d ago',
      };
      cases.forEach((String raw, String want) {
        expect(localizeTimeAgo(en, raw), want, reason: raw);
      });
      expect(alertTimeAgo(en, serverAlert), '3m ago');
      expect(alertTimeAgo(ko, serverAlert), '3분 전');
    });

    // 서버가 데모 계정 알림에 주는 영어 "어제"(#2691).
    test('서버의 영어 yesterday 도 옮긴다', () {
      expect(localizeTimeAgo(en, 'yesterday'), 'Yesterday');
      expect(localizeTimeAgo(ko, 'yesterday'), '어제');
    });

    test('모르는 모양은 받은 그대로 둔다', () {
      expect(localizeTimeAgo(en, '2026-09-15'), '2026-09-15');
      expect(localizeTimeAgo(en, ''), '');
    });
  });
}
