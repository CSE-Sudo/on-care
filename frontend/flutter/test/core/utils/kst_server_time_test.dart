/// 서버 시각을 KST 하나로 읽는다 — 기기 시간대와 섞지 않는다. (#2876)
///
/// 회원 앱은 "오늘" 을 `nowKst()` 로 계산한다. 서버가 준 시각(UTC 순간)을
/// `toLocal()` 로 바꾸면 **기기 시간대**의 벽시계가 되어, KST 가 아닌 기기에서
/// 같은 화면 안에 두 기준이 섞인다. 여기서는 엔티티 파싱·되돌려 보내는 커서·
/// 날짜 판정이 모두 KST 벽시계 하나로 맞는지를 본다.
///
/// Dart 에는 테스트 안에서 기기 시간대를 바꿀 수단이 없다. 대신 **기기 시간대를
/// 거치지 않는 값**만 기대한다 — 기대값은 KST 벽시계를 필드로 적은 로컬
/// `DateTime` 이고, 그 필드는 어느 기기에서 돌려도 같아야 한다. CI(UTC)와
/// 개발 기기(KST) 어디서든 같은 결과가 나와야 통과한다.
library;

import 'dart:io' show Directory, File, FileSystemEntity;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_message.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/my_reservation.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/presentation/utils/next_pt.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare_core/clock.dart';

/// 필드만 꺼낸다 — `==` 는 isUtc 까지 보므로 벽시계 비교는 필드로 한다.
List<int> _wall(DateTime t) => <int>[t.year, t.month, t.day, t.hour, t.minute];

void main() {
  group('kstWallToUtc', () {
    test('KST 07:00 벽시계는 전날 22:00Z 다', () {
      final DateTime utc = kstWallToUtc(DateTime(2026, 8, 17, 7));

      expect(utc.isUtc, isTrue);
      expect(utc, DateTime.utc(2026, 8, 16, 22));
    });

    test('이미 UTC 순간이면 그대로 돌려준다', () {
      final DateTime at = DateTime.utc(2026, 8, 16, 22);

      expect(kstWallToUtc(at), same(at));
    });

    test('toKst 의 역이다', () {
      final DateTime at = DateTime.utc(2026, 3, 2, 1, 30, 15);

      expect(kstWallToUtc(toKst(at)), at);
    });

    test('연말 자정 직후 벽시계도 전해로 넘긴다', () {
      expect(
        kstWallToUtc(DateTime(2027, 1, 1, 3)),
        DateTime.utc(2026, 12, 31, 18),
      );
    });
  });

  group('kstDateOf · isSameKstDay', () {
    test('UTC 23:30 은 KST 로 다음 날이다', () {
      expect(
        kstDateOf(DateTime.utc(2026, 8, 16, 23, 30)),
        DateTime(2026, 8, 17),
      );
    });

    test('날짜만 남기고 시각은 0시로 자른다', () {
      final DateTime d = kstDateOf(DateTime.utc(2026, 8, 17, 5, 45));

      expect(_wall(d), <int>[2026, 8, 17, 0, 0]);
    });

    test('KST 00:30 과 08:30 은 같은 날이다 — UTC 로는 다른 날이어도', () {
      // 15:30Z = KST 8/17 00:30, 23:30Z = KST 8/17 08:30
      expect(
        isSameKstDay(
          DateTime.utc(2026, 8, 16, 15, 30),
          DateTime.utc(2026, 8, 16, 23, 30),
        ),
        isTrue,
      );
    });

    test('KST 23:00 과 다음 날 08:30 은 다른 날이다 — UTC 로는 같은 날이어도', () {
      // 14:00Z = KST 8/16 23:00, 23:30Z = KST 8/17 08:30
      expect(
        isSameKstDay(
          DateTime.utc(2026, 8, 16, 14),
          DateTime.utc(2026, 8, 16, 23, 30),
        ),
        isFalse,
      );
    });

    test('UTC 순간과 KST 벽시계를 섞어도 같은 기준으로 견준다', () {
      expect(
        isSameKstDay(DateTime.utc(2026, 8, 16, 23), DateTime(2026, 8, 17, 21)),
        isTrue,
      );
    });
  });

  group('엔티티 파싱 — KST 00~09시 경계', () {
    test('예약 가능 자리 시각은 KST 벽시계다', () {
      final TrainerSlot slot = trainerSlotFromJson(<String, Object?>{
        'id': 's1',
        'trainer_id': 't1',
        'starts_at': '2026-08-16T22:00:00+00:00',
        'remaining': 1,
      });

      expect(slot.startsAt.isUtc, isFalse);
      expect(_wall(slot.startsAt), <int>[2026, 8, 17, 7, 0]);
    });

    test('+09:00 으로 온 자리 시각도 같은 값이다', () {
      final TrainerSlot slot = trainerSlotFromJson(<String, Object?>{
        'id': 's1',
        'trainer_id': 't1',
        'starts_at': '2026-08-17T07:00:00+09:00',
        'remaining': 1,
      });

      expect(_wall(slot.startsAt), <int>[2026, 8, 17, 7, 0]);
    });

    test('내 예약 시각은 KST 벽시계다', () {
      final MyReservation r = MyReservation.fromJson(<String, Object?>{
        'id': 'r1',
        'slot_id': 's1',
        'trainer_id': 't1',
        'starts_at': '2026-08-16T23:30:00Z',
        'cancellable': true,
      });

      expect(_wall(r.startsAt), <int>[2026, 8, 17, 8, 30]);
    });

    test('상담 요청의 자리 시각은 KST 벽시계다', () {
      final ConsultationRequest c = consultationFromJson(<String, Object?>{
        'id': 'c1',
        'trainer_id': 't1',
        'trainer_name': '김트레이너',
        'exercise_goal': 'weight_loss',
        'preferred_date': '2026-08-17',
        'preferred_time_slot': '07:00',
        'slot_starts_at': '2026-08-16T22:00:00Z',
        'status': 'pending',
        'created_at': '2026-08-10T01:00:00Z',
      });

      expect(_wall(c.slotStartsAt!), <int>[2026, 8, 17, 7, 0]);
      // 희망 날짜와 같은 날로 읽힌다 — 두 값이 같은 기준이다.
      expect(kstDateOf(c.slotStartsAt!), c.preferredDate);
    });

    test('상담 요청에 자리 시각이 없으면 비어 있다', () {
      final ConsultationRequest c = consultationFromJson(<String, Object?>{
        'id': 'c1',
        'exercise_goal': 'weight_loss',
        'preferred_date': '2026-08-17',
        'status': 'pending',
      });

      expect(c.slotStartsAt, isNull);
    });

    test('AI 코치 대화 시각은 KST 벽시계다', () {
      final ChatMessage m = ChatMessage.fromStored(<String, Object?>{
        'role': 'coach',
        'content': '좋아요',
        'created_at': '2026-08-16T23:05:00Z',
      });

      expect(_wall(m.at!), <int>[2026, 8, 17, 8, 5]);
    });

    test('AI 코치 대화에 시각이 없으면 비어 있다', () {
      final ChatMessage m = ChatMessage.fromStored(<String, Object?>{
        'role': 'user',
        'content': '안녕',
      });

      expect(m.at, isNull);
    });

    test('감지 기록 시각은 KST 벽시계다', () {
      final ChatInsightRecord? r = ChatInsightRecord.fromJson(<String, Object?>{
        'message_id': 'm1',
        'created_at': '2026-09-14T16:00:00Z',
        'kind': 'discomfort',
        'body_part': '허리',
        'text': '허리가 뻐근해요',
      });

      expect(_wall(r!.createdAt), <int>[2026, 9, 15, 1, 0]);
    });

    test('집중 영역 변경 시각은 KST 벽시계다', () {
      final UserProfile p = UserProfile.fromJson(<String, Object?>{
        'id': 'u1',
        'focus_changed_by': 'trainer',
        'focus_changed_at': '2026-09-15T20:00:00Z',
      });

      expect(_wall(p.focusChangedAt!), <int>[2026, 9, 16, 5, 0]);
    });
  });

  group('nextPtAt — 세션과 예약을 같은 기준으로', () {
    CoachSession session(DateTime date, String time) => CoachSession(
      id: 'ses-$time',
      date: date,
      time: time,
      type: '1:1 PT',
      durationMinutes: 50,
      status: '예정',
    );

    MyReservation reservation(String startsAt) =>
        MyReservation.fromJson(<String, Object?>{
          'id': 'r-$startsAt',
          'slot_id': 's',
          'trainer_id': 't',
          'starts_at': startsAt,
          'cancellable': true,
        });

    test('KST 오전 예약이 같은 날 저녁 세션보다 앞선다', () {
      // 예약: 22:00Z = KST 8/21 07:00, 세션: KST 8/21 19:00
      final DateTime? next = nextPtAt(
        sessions: <CoachSession>[session(DateTime(2026, 8, 21), '19:00')],
        reservations: <MyReservation>[reservation('2026-08-20T22:00:00Z')],
        now: DateTime(2026, 8, 20, 14),
      );

      expect(_wall(next!), <int>[2026, 8, 21, 7, 0]);
    });

    test('KST 저녁 세션이 다음 날 오전 예약보다 앞선다', () {
      // 세션: KST 8/20 19:00, 예약: 01:00Z = KST 8/21 10:00
      final DateTime? next = nextPtAt(
        sessions: <CoachSession>[session(DateTime(2026, 8, 20), '19:00')],
        reservations: <MyReservation>[reservation('2026-08-21T01:00:00Z')],
        now: DateTime(2026, 8, 20, 14),
      );

      expect(_wall(next!), <int>[2026, 8, 20, 19, 0]);
    });

    test('9시간 차이 안쪽의 두 일정도 KST 순서대로 고른다', () {
      // 세션: KST 8/21 09:00, 예약: 23:30Z = KST 8/21 08:30 — 예약이 먼저다.
      // 기기 시간대로 읽으면(UTC 기기) 예약이 8/20 23:30 으로 보여 순서는 같지만
      // 날짜가 하루 어긋난다. 값까지 KST 로 맞는지 본다.
      final DateTime? next = nextPtAt(
        sessions: <CoachSession>[session(DateTime(2026, 8, 21), '09:00')],
        reservations: <MyReservation>[reservation('2026-08-20T23:30:00Z')],
        now: DateTime(2026, 8, 20, 14),
      );

      expect(_wall(next!), <int>[2026, 8, 21, 8, 30]);
    });
  });

  test('lib 에 서버 시각을 기기 시간대로 바꾸는 toLocal() 이 없다', () {
    final List<String> leftovers = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String path = entity.path.replaceAll(r'\', '/');
      if (path.contains('/gen/')) continue;
      final List<String> lines = entity.readAsStringSync().split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (!line.contains('.toLocal()')) continue;
        if (line.trimLeft().startsWith('//')) continue;
        leftovers.add('$path:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      leftovers,
      isEmpty,
      reason:
          '서버 시각을 기기 시간대로 바꾸는 곳이 남았어요. toKst() 를 쓰세요:\n'
          '${leftovers.join('\n')}',
    );
  });
}
