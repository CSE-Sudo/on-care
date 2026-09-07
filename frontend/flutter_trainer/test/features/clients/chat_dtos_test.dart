import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/clients/data/dtos/chat_dtos.dart';
import 'package:oncare_trainer/shared/models/client_chat_message.dart';

void main() {
  group('chatMessageFromJson', () {
    test('maps a trainer message', () {
      final m = chatMessageFromJson(<String, Object?>{
        'id': 'c1',
        'sender': 'trainer',
        'body': '오늘 컨디션 어때요?',
        'time_label': '18:10',
        'created_at': '2026-07-30T18:10:00',
      });
      expect(m.id, 'c1');
      expect(m.sender, ChatSender.trainer);
      expect(m.fromTrainer, isTrue);
      expect(m.timeLabel, '18:10');
      expect(m.createdAt, DateTime.parse('2026-07-30T18:10:00'));
      expect(m.attachment, isNull);
    });

    test('maps an optional PDF attachment', () {
      final m = chatMessageFromJson(<String, Object?>{
        'id': 'pdf-1',
        'sender': 'trainer',
        'body': '이번 주 리포트입니다.',
        'time_label': '18:10',
        'created_at': '2026-07-30T18:10:00',
        'attachment': <String, Object?>{
          'type': 'pdf',
          'file_name': '김회원_주간리포트.pdf',
          'file_id': 'abc123',
          'file_size': 2048,
          'download_path': '/chat/attachments/abc123',
        },
      });
      expect(m.attachment?.fileName, '김회원_주간리포트.pdf');
      expect(m.attachment?.fileSize, 2048);
    });

    test('리포트 안내는 그 주 월요일을 싣고 오고, 날짜가 아니면 일반 메시지다 (#1600)', () {
      Map<String, Object?> message(Object? week) => <String, Object?>{
        'id': 'report-1',
        'sender': 'trainer',
        'body': '이번 주 리포트입니다.',
        'time_label': '18:10',
        'created_at': '2026-08-24T18:10:00Z',
        'report_week_start': ?week,
      };
      expect(
        chatMessageFromJson(message('2026-08-17')).reportWeekStart,
        DateTime(2026, 8, 17),
      );
      // 파일명이나 본문으로 추측하지 않는다. 그리고 안내 상자 하나 때문에
      // 대화 전체가 뜨지 않는 편보다, 일반 대화로 그리는 편이 낫다.
      expect(chatMessageFromJson(message(null)).reportWeekStart, isNull);
      expect(chatMessageFromJson(message('지난주')).reportWeekStart, isNull);
    });

    test('maps the client sender', () {
      final m = chatMessageFromJson(<String, Object?>{
        'id': 'c2',
        'sender': 'client',
        'body': '좋아요!',
        'time_label': '18:12',
        'created_at': '2026-07-30T18:12:00',
      });
      expect(m.sender, ChatSender.client);
      expect(m.fromTrainer, isFalse);
    });

    test('rejects malformed sender and created_at values', () {
      Map<String, Object?> message({
        Object? sender = 'client',
        Object? createdAt = '2026-07-30T18:12:00',
      }) => <String, Object?>{
        'id': 'c3',
        'sender': sender,
        'body': 'x',
        'time_label': '',
        'created_at': createdAt,
      };

      expect(
        () => chatMessageFromJson(message(sender: 'me')),
        throwsFormatException,
      );
      expect(
        () => chatMessageFromJson(message(createdAt: 'not-a-date')),
        throwsFormatException,
      );
    });
  });
}
