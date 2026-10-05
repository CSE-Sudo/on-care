/// 알림 문장을 화면 언어로 조립한다(#2302).
///
/// 한국어 기대값은 서버가 틀 이전에 저장하던 문장 그대로다
/// (`backend/tests/test_notification_templates.py` 의 `LEGACY_KO`). 영어 기대값은
/// 서버의 영어 조립과 같다 — 트레이너 웹이 조립하든 서버가 조립하든 같은 문장이
/// 보여야 한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/features/notifications/domain/entities/trainer_notification.dart';
import 'package:oncare_trainer/features/notifications/presentation/trainer_notification_text.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_en.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

final AppLocalizations _ko = AppLocalizationsKo();
final AppLocalizations _en = AppLocalizationsEn();

/// 서버가 저장해 둔 문장. 조립에 실패하면 이 문장이 그대로 보여야 한다.
const String _storedTitle = '저장된 제목';
const String _storedBody = '저장된 본문';

const String _starts = '2026-10-01T09:05:00+09:00';

TrainerNotification _n(
  String? template,
  Map<String, Object?> args, {
  String title = _storedTitle,
  String body = _storedBody,
}) => TrainerNotification(
  id: 'noti-1',
  title: title,
  body: body,
  kind: TrainerNotificationKind.other,
  read: false,
  createdAt: DateTime.utc(2026, 10, 2),
  timeAgo: '',
  template: template,
  args: args,
);

TrainerNotificationText _text(AppLocalizations l, TrainerNotification n) =>
    trainerNotificationText(l, n);

/// (틀, 인자, 한국어 제목, 한국어 본문, 영어 제목, 영어 본문).
/// 메시지 알림의 본문은 회원이 쓴 문장이라 저장된 본문이 그대로 나온다.
const List<(String, Map<String, Object?>, String, String, String, String)>
_cases = <(String, Map<String, Object?>, String, String, String, String)>[
  (
    'trainer_health_goal',
    <String, Object?>{
      'member_name': '지수',
      'focus': <String>['근력 향상', '재활'],
    },
    '회원 건강 목표 변경',
    '지수 회원이 건강 목표를 바꿨어요: 근력 향상 · 재활',
    'Member goals changed',
    '지수 changed their health goals: Build strength · Rehab',
  ),
  (
    'trainer_health_goal',
    <String, Object?>{'member_name': '지수', 'focus': <String>[]},
    '회원 건강 목표 변경',
    '지수 회원이 건강 목표를 바꿨어요: 목표 없음',
    'Member goals changed',
    '지수 changed their health goals: none',
  ),
  (
    'trainer_health_notes',
    <String, Object?>{'member_name': '지수', 'with_focus': false},
    '회원 주의사항 변경',
    '지수 회원이 건강상태·주의사항을 바꿨어요',
    'Member health notes changed',
    '지수 updated their health notes',
  ),
  (
    'trainer_health_notes',
    <String, Object?>{'member_name': '지수', 'with_focus': true},
    '회원 주의사항 변경',
    '지수 회원이 건강 목표와 건강상태·주의사항을 바꿨어요',
    'Member health notes changed',
    '지수 updated their health goals and health notes',
  ),
  (
    'trainer_health_goal',
    <String, Object?>{
      'member_name': 'Alex',
      'focus': <String>['체중 감량', '체력 강화', '자세 교정', '식습관 개선', '운동 습관', '혈압 관리'],
    },
    '회원 건강 목표 변경',
    'Alex 회원이 건강 목표를 바꿨어요: 체중 감량 · 체력 강화 · 자세 교정 · 식습관 개선 · 운동 습관 · 혈압 관리',
    'Member goals changed',
    'Alex changed their health goals: Weight loss · Improve fitness · '
        'Posture correction · Better eating habits · Exercise habit · '
        'Blood pressure care',
  ),
  (
    'trainer_member_renamed',
    <String, Object?>{'old_name': '김지수', 'new_name': '김지수B'},
    '회원 이름 변경',
    '김지수 회원이 이름을 바꿨어요: 김지수B',
    'Member renamed',
    '김지수 changed their name to 김지수B.',
  ),
  (
    'trainer_member_withdrawn',
    <String, Object?>{'member_name': '지수'},
    '회원 탈퇴',
    '지수 회원이 탈퇴했어요.',
    'Member account deleted',
    '지수 deleted their account.',
  ),
  (
    'trainer_member_disconnected',
    <String, Object?>{'member_name': '지수'},
    '담당 연결 해제',
    '지수 회원이 담당 연결을 끊었어요.',
    'Client disconnected',
    '지수 ended their connection with you.',
  ),
  (
    'trainer_consult_requested',
    <String, Object?>{'member_name': '지수', 'preferred_date': '2026-10-01'},
    '새 상담 요청이 도착했어요',
    '지수 회원 · 10월 1일',
    'New consultation request',
    '지수 · 10/1',
  ),
  (
    'trainer_consult_cancelled',
    <String, Object?>{'member_name': '지수', 'preferred_date': '2026-10-01'},
    '상담 요청이 취소됐어요',
    '지수 회원 · 10월 1일',
    'Consultation request cancelled',
    '지수 · 10/1',
  ),
  (
    'trainer_consult_withdrawn',
    <String, Object?>{'member_name': '지수', 'preferred_date': '2026-10-01'},
    '회원 탈퇴로 상담 요청이 취소됐어요',
    '지수 회원 · 10월 1일',
    'Consultation request cancelled: member account deleted',
    '지수 · 10/1',
  ),
  (
    'trainer_invite_accepted',
    <String, Object?>{'member_name': '지수'},
    '담당 요청이 수락되었어요',
    '지수 회원이 담당으로 연결되었어요.',
    'Coaching request accepted',
    '지수 is now your client.',
  ),
  (
    'trainer_invite_rejected',
    <String, Object?>{'member_name': '지수'},
    '담당 요청이 거절되었어요',
    '지수 회원이 담당 요청을 거절했어요.',
    'Coaching request declined',
    '지수 declined your coaching request.',
  ),
  (
    'trainer_reservation_booked',
    <String, Object?>{'member_name': '지수', 'starts_at': _starts},
    '새 예약이 들어왔어요',
    '지수 회원 · 10월 1일 09:05',
    'New booking',
    '지수 · 10/1 09:05',
  ),
  (
    'trainer_reservation_cancelled',
    <String, Object?>{'member_name': '지수', 'starts_at': _starts},
    '예약이 취소되었습니다',
    '지수 회원 · 10월 1일 09:05',
    'Booking cancelled',
    '지수 · 10/1 09:05',
  ),
  (
    'trainer_reservation_cancelled',
    <String, Object?>{'member_name': '지수', 'starts_at': null},
    '예약이 취소되었습니다',
    '지수 회원',
    'Booking cancelled',
    '지수',
  ),
  (
    'trainer_reservation_cancelled',
    <String, Object?>{'member_name': '지수'},
    '예약이 취소되었습니다',
    '지수 회원',
    'Booking cancelled',
    '지수',
  ),
  (
    'trainer_member_message',
    <String, Object?>{'member_name': '지수'},
    '지수 회원의 메시지',
    _storedBody,
    'Message from 지수',
    _storedBody,
  ),
  // 글 없이 사진만 보냈으면 본문을 화면 언어로 적는다(#1665).
  (
    'trainer_member_message',
    <String, Object?>{'member_name': '지수', 'photo_only': true},
    '지수 회원의 메시지',
    '사진을 보냈어요',
    'Message from 지수',
    'Sent a photo',
  ),
  // 회원 주간 피드백(#3026). 서버 `LEGACY_KO`·`ENGLISH` 와 같은 문장이다.
  (
    'trainer_member_weekly_feedback',
    <String, Object?>{
      'member_name': '지수',
      'condition': 'good',
      'intensity': 'right',
      'pain': false,
      'revised': false,
    },
    '지수 회원이 주간 피드백을 보냈어요',
    '컨디션 좋았어요 · 운동 강도 적당했어요',
    '지수 sent their weekly feedback',
    'Condition: Good · Intensity: About right',
  ),
  // 통증은 수정보다 먼저 보인다 — 다음 PT 를 바꿔야 할 수 있는 답이다.
  (
    'trainer_member_weekly_feedback',
    <String, Object?>{
      'member_name': '지수',
      'condition': 'tired',
      'intensity': 'too_hard',
      'pain': true,
      'revised': true,
    },
    '지수 회원이 통증을 알렸어요',
    '컨디션 지쳤어요 · 운동 강도 너무 힘들었어요 · 통증 있음',
    '지수 reported pain',
    'Condition: Worn out · Intensity: Too hard · Pain reported',
  ),
  (
    'trainer_member_weekly_feedback',
    <String, Object?>{
      'member_name': '지수',
      'condition': 'great',
      'intensity': 'too_easy',
      'pain': false,
      'revised': true,
    },
    '지수 회원이 주간 피드백을 수정했어요',
    '컨디션 아주 좋았어요 · 운동 강도 너무 쉬웠어요',
    '지수 updated their weekly feedback',
    'Condition: Great · Intensity: Too easy',
  ),
];

/// 서버가 아는 트레이너 틀 전부. 백엔드 테스트가 이 코드들이 조립 파일에 있는지
/// 확인하고, 여기서는 각 코드가 실제로 조립되는지 확인한다.
const Set<String> _trainerTemplates = <String>{
  'trainer_health_goal',
  'trainer_health_notes',
  'trainer_member_renamed',
  'trainer_member_withdrawn',
  'trainer_member_disconnected',
  'trainer_consult_requested',
  'trainer_consult_cancelled',
  'trainer_consult_withdrawn',
  'trainer_invite_accepted',
  'trainer_invite_rejected',
  'trainer_reservation_booked',
  'trainer_reservation_cancelled',
  'trainer_member_message',
  'trainer_member_weekly_feedback',
};

final RegExp _hangul = RegExp('[가-힣]');

void main() {
  group('한국어는 옛 문장과 같다', () {
    for (final (
          String template,
          Map<String, Object?> args,
          String koTitle,
          String koBody,
          _,
          _,
        )
        in _cases) {
      test('$template $args', () {
        final TrainerNotificationText text = _text(_ko, _n(template, args));
        expect(text.title, koTitle);
        expect(text.body, koBody);
      });
    }
  });

  group('영어로 조립한다', () {
    for (final (
          String template,
          Map<String, Object?> args,
          _,
          _,
          String enTitle,
          String enBody,
        )
        in _cases) {
      test('$template $args', () {
        final TrainerNotificationText text = _text(_en, _n(template, args));
        expect(text.title, enTitle);
        expect(text.body, enBody);
      });
    }
  });

  test('영어 조립은 이름·날짜 말고는 한글을 남기지 않는다', () {
    for (final String template in _trainerTemplates) {
      final TrainerNotificationText text = _text(
        _en,
        _n(template, <String, Object?>{
          'member_name': 'Alex',
          'old_name': 'Alex',
          'new_name': 'Alexandra',
          'focus': <String>['근력 향상', '혈압 관리'],
          'preferred_date': '2026-10-01',
          'starts_at': _starts,
          'condition': 'bad',
          'intensity': 'hard',
          'pain': true,
        }, body: 'See you'),
      );
      expect(text.title, isNot(matches(_hangul)), reason: template);
      expect(text.body, isNot(matches(_hangul)), reason: template);
      // 조립에 성공했다 — 저장된 한국어 제목으로 돌아가지 않았다.
      expect(text.title, isNot(_storedTitle), reason: template);
    }
  });

  test('모든 트레이너 틀이 조립된다', () {
    final Set<String> covered = <String>{
      for (final (String template, _, _, _, _, _) in _cases) template,
    };
    expect(covered, _trainerTemplates);
  });

  group('저장된 문장으로 돌아간다', () {
    void expectStored(TrainerNotification n) {
      for (final AppLocalizations l in <AppLocalizations>[_ko, _en]) {
        final TrainerNotificationText text = _text(l, n);
        expect(text.title, n.title);
        expect(text.body, n.body);
      }
    }

    test('틀이 없는 옛 알림', () {
      expectStored(_n(null, const <String, Object?>{}));
    });

    test('모르는 틀', () {
      expectStored(
        _n('trainer_from_the_future', <String, Object?>{'member_name': '지수'}),
      );
      // 회원이 받는 틀은 트레이너 웹이 조립하지 않는다.
      expectStored(
        _n('member_coach_message', <String, Object?>{'trainer_name': '박코치'}),
      );
    });

    test('인자가 없다', () {
      for (final String template in _trainerTemplates) {
        expectStored(_n(template, const <String, Object?>{}));
      }
    });

    test('이름이 비었다 — 이름 없는 경우의 한국어가 종류마다 달라서', () {
      for (final String template in _trainerTemplates) {
        expectStored(
          _n(template, <String, Object?>{
            'member_name': '',
            'old_name': '',
            'new_name': '지수',
            'focus': <String>[],
            'preferred_date': '2026-10-01',
            'starts_at': _starts,
          }),
        );
      }
    });

    test('이름 앞뒤에 공백이 있다', () {
      expectStored(
        _n('trainer_member_withdrawn', <String, Object?>{'member_name': ' 지수'}),
      );
      expectStored(
        _n('trainer_member_renamed', <String, Object?>{
          'old_name': '지수',
          'new_name': '지수 ',
        }),
      );
    });

    test('인자 모양이 다르다', () {
      expectStored(
        _n('trainer_member_withdrawn', <String, Object?>{'member_name': 42}),
      );
      expectStored(
        _n('trainer_health_goal', <String, Object?>{
          'member_name': '지수',
          'focus': '근력 향상',
        }),
      );
      expectStored(
        _n('trainer_health_goal', <String, Object?>{
          'member_name': '지수',
          'focus': <Object?>['근력 향상', 3],
        }),
      );
      expectStored(
        _n('trainer_consult_requested', <String, Object?>{
          'member_name': '지수',
          'preferred_date': 20261001,
        }),
      );
      expectStored(
        _n('trainer_consult_requested', <String, Object?>{
          'member_name': '지수',
          'preferred_date': '',
        }),
      );
    });

    test('예약 시각을 읽을 수 없다', () {
      for (final Object? starts in <Object?>['내일', '', 12, '10/1 09:05']) {
        expectStored(
          _n('trainer_reservation_booked', <String, Object?>{
            'member_name': '지수',
            'starts_at': starts,
          }),
        );
      }
      expectStored(
        _n('trainer_reservation_cancelled', <String, Object?>{
          'member_name': '지수',
          'starts_at': 'not-a-date',
        }),
      );
    });
  });

  test('모르는 건강 목표 값(옛 질환명)은 받은 그대로 적는다', () {
    final TrainerNotificationText text = _text(
      _en,
      _n('trainer_health_goal', <String, Object?>{
        'member_name': 'Alex',
        'focus': <String>['고혈압', '재활'],
      }),
    );
    expect(text.body, 'Alex changed their health goals: 고혈압 · Rehab');
  });

  test('예약 시각은 적힌 서울 시각을 그대로 읽는다(시간대를 옮기지 않는다)', () {
    final TrainerNotificationText text = _text(
      _en,
      _n('trainer_reservation_booked', <String, Object?>{
        'member_name': 'Alex',
        'starts_at': '2026-12-31T23:30:00+09:00',
      }),
    );
    expect(text.body, 'Alex · 12/31 23:30');
  });

  test('사진 전용 표시가 거짓이면 회원이 쓴 글을 그대로 둔다', () {
    final TrainerNotificationText text = _text(
      _en,
      _n('trainer_member_message', <String, Object?>{
        'member_name': 'Alex',
        'photo_only': false,
      }, body: '사진과 함께 보내요'),
    );
    expect(text.body, '사진과 함께 보내요');
  });

  test('메시지 본문이 비었으면 비어 있는 그대로다', () {
    final TrainerNotificationText text = _text(
      _en,
      _n('trainer_member_message', <String, Object?>{
        'member_name': 'Alex',
      }, body: ''),
    );
    expect(text.title, 'Message from Alex');
    expect(text.body, isEmpty);
  });

  group('TrainerNotification.fromJson 의 틀', () {
    Map<String, Object?> json([Map<String, Object?> extra = const {}]) =>
        <String, Object?>{
          'id': 'n1',
          'title': '회원 탈퇴',
          'body': '지수 회원이 탈퇴했어요.',
          'category': 'member_left',
          'read': false,
          'created_at': '2026-10-01T00:00:00Z',
          'time_ago': '방금 전',
          ...extra,
        };

    test('틀과 인자를 읽는다', () {
      final TrainerNotification n = TrainerNotification.fromJson(
        json(<String, Object?>{
          'template': 'trainer_member_withdrawn',
          'args': <String, Object?>{'member_name': '지수'},
        }),
      );
      expect(n.template, 'trainer_member_withdrawn');
      expect(n.args, <String, Object?>{'member_name': '지수'});
      expect(_text(_en, n).body, '지수 deleted their account.');
    });

    test('틀이 없는 옛 응답은 저장된 문장을 쓴다', () {
      final TrainerNotification n = TrainerNotification.fromJson(json());
      expect(n.template, isNull);
      expect(n.args, isEmpty);
      expect(_text(_en, n).title, '회원 탈퇴');
    });

    test('null·빈 문자열·다른 모양은 없는 것으로 읽는다', () {
      for (final Object? template in <Object?>[null, '', 7]) {
        final TrainerNotification n = TrainerNotification.fromJson(
          json(<String, Object?>{'template': template, 'args': null}),
        );
        expect(n.template, isNull);
        expect(n.args, isEmpty);
      }
      final TrainerNotification n = TrainerNotification.fromJson(
        json(<String, Object?>{
          'template': 'trainer_member_withdrawn',
          'args': <Object?>['지수'],
        }),
      );
      expect(n.template, 'trainer_member_withdrawn');
      expect(n.args, isEmpty);
      // 인자가 없어 조립하지 못하고 저장된 문장으로 돌아간다.
      expect(_text(_en, n).body, '지수 회원이 탈퇴했어요.');
    });

    test('인자는 바꿀 수 없다', () {
      final TrainerNotification n = TrainerNotification.fromJson(
        json(<String, Object?>{
          'template': 'trainer_member_withdrawn',
          'args': <String, Object?>{'member_name': '지수'},
        }),
      );
      expect(() => n.args['member_name'] = 'x', throwsUnsupportedError);
    });
  });

  group('회원 주간 피드백 (#3026)', () {
    test('모르는 답이면 저장된 문장으로 돌아간다', () {
      for (final Map<String, Object?> args in <Map<String, Object?>>[
        <String, Object?>{
          'member_name': '지수',
          'condition': 'sleepy',
          'intensity': 'right',
        },
        <String, Object?>{
          'member_name': '지수',
          'condition': 'good',
          'intensity': 'max',
        },
        <String, Object?>{'member_name': '지수'},
        <String, Object?>{
          'member_name': '지수',
          'condition': 3,
          'intensity': true,
        },
        <String, Object?>{'condition': 'good', 'intensity': 'right'},
      ]) {
        for (final AppLocalizations l in <AppLocalizations>[_ko, _en]) {
          final TrainerNotificationText text = _text(
            l,
            _n('trainer_member_weekly_feedback', args),
          );
          expect(text.title, _storedTitle, reason: '$args');
          expect(text.body, _storedBody, reason: '$args');
        }
      }
    });

    test('아픈 곳 글은 인자에 있어도 싣지 않는다', () {
      final TrainerNotificationText text = _text(
        _ko,
        _n('trainer_member_weekly_feedback', <String, Object?>{
          'member_name': '지수',
          'condition': 'ok',
          'intensity': 'hard',
          'pain': true,
          'pain_area': '왼쪽 어깨',
        }),
      );
      expect(text.title, isNot(contains('어깨')));
      expect(text.body, isNot(contains('어깨')));
    });

    test('같은 답 이름은 리포트 화면의 회원 피드백 칸과 같다', () {
      final TrainerNotificationText text = _text(
        _ko,
        _n('trainer_member_weekly_feedback', <String, Object?>{
          'member_name': '지수',
          'condition': 'bad',
          'intensity': 'too_easy',
        }),
      );
      expect(text.body, contains(_ko.reportsMemberFeedbackConditionBad));
      expect(text.body, contains(_ko.reportsMemberFeedbackIntensityTooEasy));
    });
  });
}
