/// 회원별 지난 리포트 — 도메인 층. (#2394)
///
/// 이 파일이 지키는 것:
///  * 목록 줄의 첫 줄([reportFeedbackPreview])은 서버 `feedback_preview` 와
///    같은 규칙이다 — 비어 있지 않은 첫 줄, 80자 넘으면 잘라 `…`.
///  * [mergeMemberHistory] 는 같은 주에서 세션 기록이 이기고, 다른 회원 기록은
///    끼우지 않고, 최신 주부터 세우고, 아직 안 불러온 쪽의 주는 얹지 않는다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/report_send_record.dart';

MemberReportHistoryItem _item(
  DateTime week, {
  String preview = '서버 첫 줄',
  bool read = true,
  int sendCount = 1,
  String? messageId = 'm-1',
  bool hasPdf = true,
}) => MemberReportHistoryItem(
  weekStart: week,
  sentAt: DateTime(week.year, week.month, week.day + 6, 20),
  read: read,
  sendCount: sendCount,
  feedbackPreview: preview,
  messageId: messageId,
  hasPdf: hasPdf,
);

ReportSendRecord _record(
  DateTime week, {
  String clientId = 'c1',
  String message = '방금 보낸 글',
  int sendCount = 1,
  bool read = true,
}) => ReportSendRecord(
  clientId: clientId,
  weekStart: week,
  sentAt: DateTime(week.year, week.month, week.day + 2, 9),
  message: message,
  read: read,
  sendCount: sendCount,
);

String _key(String clientId, DateTime week) =>
    '$clientId|${week.toIso8601String()}';

void main() {
  final DateTime w1 = DateTime(2026, 8, 17);
  final DateTime w2 = DateTime(2026, 8, 10);
  final DateTime w3 = DateTime(2026, 8, 3);

  group('reportFeedbackPreview', () {
    test('비어 있지 않은 첫 줄을 앞뒤 공백 없이 돌려준다', () {
      expect(reportFeedbackPreview('\n  \n  첫 줄  \n둘째 줄'), '첫 줄');
    });

    test('한 줄이면 그대로다', () {
      expect(reportFeedbackPreview('이번 주도 수고 많으셨어요.'), '이번 주도 수고 많으셨어요.');
    });

    test('빈 본문은 빈 문자열이다', () {
      expect(reportFeedbackPreview(''), '');
      expect(reportFeedbackPreview('  \n \n'), '');
    });

    test('80자를 넘으면 80자에서 잘라 말줄임표를 붙인다', () {
      final String long = '가' * 81;
      final String preview = reportFeedbackPreview(long);
      expect(preview, '${'가' * 80}…');
    });

    test('딱 80자는 자르지 않는다', () {
      final String exact = 'a' * 80;
      expect(reportFeedbackPreview(exact), exact);
    });

    test('길이는 글자 단위로 센다 — 이모지를 반으로 가르지 않는다', () {
      final String emoji = '🙂' * 81;
      final String preview = reportFeedbackPreview(emoji);
      expect(preview.runes.length, 81); // 80자 + …
      expect(preview.endsWith('🙂…'), isTrue);
    });

    test('길이 한도를 바꿀 수 있다', () {
      expect(reportFeedbackPreview('abcdef', maxLength: 3), 'abc…');
    });
  });

  group('MemberReportHistoryItem.fromRecord', () {
    test('기록의 주를 월요일로 맞추고 본문 첫 줄을 싣는다', () {
      final ReportSendRecord record = ReportSendRecord(
        clientId: 'c1',
        weekStart: DateTime(2026, 8, 20), // 목요일
        sentAt: DateTime(2026, 8, 21, 9),
        message: '첫 줄\n\n다음 주 목표\n· 걷기',
        read: false,
        sendCount: 3,
      );
      final MemberReportHistoryItem item = MemberReportHistoryItem.fromRecord(
        record,
      );
      expect(item.weekStart, w1);
      expect(item.sentAt, DateTime(2026, 8, 21, 9));
      expect(item.read, isFalse);
      expect(item.sendCount, 3);
      expect(item.feedbackPreview, '첫 줄');
      expect(item.messageId, isNull);
      expect(item.hasPdf, isFalse);
    });

    test('본문이 빈 기록은 빈 첫 줄이다 — 화면이 그 주 수치로 채운다', () {
      final MemberReportHistoryItem item = MemberReportHistoryItem.fromRecord(
        _record(w1, message: ''),
      );
      expect(item.feedbackPreview, isEmpty);
    });
  });

  group('MemberReportHistoryPage', () {
    test('다음 쪽 커서가 있으면 더 불러올 쪽이 있다', () {
      expect(
        MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
          nextBefore: w1,
        ).hasMore,
        isTrue,
      );
      expect(
        MemberReportHistoryPage(
          items: <MemberReportHistoryItem>[_item(w1)],
        ).hasMore,
        isFalse,
      );
    });

    test('빈 쪽은 줄도 커서도 없다', () {
      const MemberReportHistoryPage empty = MemberReportHistoryPage.empty();
      expect(empty.items, isEmpty);
      expect(empty.hasMore, isFalse);
    });
  });

  group('mergeMemberHistory', () {
    test('세션 기록이 없으면 받은 줄을 최신 주부터 그대로 둔다', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w3), _item(w1), _item(w2)],
        session: const <String, ReportSendRecord>{},
        clientId: 'c1',
      );
      expect(merged.map((i) => i.weekStart), <DateTime>[w1, w2, w3]);
    });

    test('서버에 아직 없는 주를 방금 보냈으면 맨 위에 선다', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w2), _item(w3)],
        session: <String, ReportSendRecord>{_key('c1', w1): _record(w1)},
        clientId: 'c1',
      );
      expect(merged.map((i) => i.weekStart), <DateTime>[w1, w2, w3]);
      expect(merged.first.feedbackPreview, '방금 보낸 글');
    });

    test('같은 주는 세션 기록이 이긴다 — 첫 줄·시각은 방금 보낸 것', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w1, preview: '옛 글')],
        session: <String, ReportSendRecord>{
          _key('c1', w1): _record(w1, message: '다시 쓴 글'),
        },
        clientId: 'c1',
      );
      final MemberReportHistoryItem only = merged.single;
      expect(only.feedbackPreview, '다시 쓴 글');
      expect(only.sentAt, DateTime(2026, 8, 19, 9));
    });

    test('같은 주를 덮을 때 방금 보낸 것은 안 읽음이고 횟수는 큰 쪽을 지킨다', () {
      final MemberReportHistoryItem only = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w1, sendCount: 3)],
        session: <String, ReportSendRecord>{_key('c1', w1): _record(w1)},
        clientId: 'c1',
      ).single;
      expect(only.read, isFalse);
      expect(only.sendCount, 3);
    });

    test('같은 주를 덮어도 서버의 메시지 id·PDF 여부는 남는다', () {
      final MemberReportHistoryItem only = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w1, messageId: 'server-msg')],
        session: <String, ReportSendRecord>{_key('c1', w1): _record(w1)},
        clientId: 'c1',
      ).single;
      expect(only.messageId, 'server-msg');
      expect(only.hasPdf, isTrue);
    });

    test('다른 회원에게 보낸 세션 기록은 끼우지 않는다', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w2)],
        session: <String, ReportSendRecord>{
          _key('c2', w1): _record(w1, clientId: 'c2'),
        },
        clientId: 'c1',
      );
      expect(merged.map((i) => i.weekStart), <DateTime>[w2]);
    });

    test('아직 불러오지 않은 쪽의 주는 얹지 않는다', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w1), _item(w2)],
        session: <String, ReportSendRecord>{_key('c1', w3): _record(w3)},
        clientId: 'c1',
        oldestLoaded: w2,
      );
      expect(merged.map((i) => i.weekStart), <DateTime>[w1, w2]);
    });

    test('불러온 가장 오래된 주 자체는 덮는다', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[
          _item(w1),
          _item(w2, preview: '옛'),
        ],
        session: <String, ReportSendRecord>{
          _key('c1', w2): _record(w2, message: '새'),
        },
        clientId: 'c1',
        oldestLoaded: w2,
      );
      expect(merged.last.feedbackPreview, '새');
    });

    test('주 중간 날짜로 적힌 세션 기록도 그 주 월요일에 붙는다', () {
      final List<MemberReportHistoryItem> merged = mergeMemberHistory(
        fetched: <MemberReportHistoryItem>[_item(w1, preview: '옛')],
        session: <String, ReportSendRecord>{
          _key('c1', w1): _record(DateTime(2026, 8, 20), message: '새'),
        },
        clientId: 'c1',
      );
      expect(merged.single.weekStart, w1);
      expect(merged.single.feedbackPreview, '새');
    });
  });
}
