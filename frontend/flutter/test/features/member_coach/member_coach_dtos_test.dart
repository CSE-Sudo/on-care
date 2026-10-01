import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/member_coach/data/dtos/member_coach_dtos.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';

void main() {
  test('memberCoachFromJson maps the coach summary (nested gym)', () {
    final c = memberCoachFromJson(<String, Object?>{
      'trainer_id': 't1',
      'name': '김트레이너',
      'specialty': '퍼스널 트레이너',
      'career': '7년',
      'intro': '안녕하세요',
      'gym': <String, Object?>{'name': '온케어짐 신촌점'},
      'goal': '혈압 관리',
    });
    expect(c.trainerId, 't1');
    expect(c.name, '김트레이너');
    expect(c.gymName, '온케어짐 신촌점');
    expect(c.goal, '혈압 관리');
  });

  test('coachRoutineFromJson maps a received routine (double minutes ok)', () {
    final r = coachRoutineFromJson(<String, Object?>{
      'id': 'r1',
      'name': '저강도 유산소',
      'minutes': 20.0,
      'type': '유산소',
      'reason': '혈압 안정',
      'source': 'ai',
      'intensity': 'light',
      'completed': true,
      'completed_at': '2026-08-13T10:00:00Z',
      'completed_minutes': 25,
      'completed_intensity': 'high',
      // 개인 운동 피드백은 회원(#1825)·트레이너(#2517) 모두 없앴다 — 옛
      // 서버가 보내도 읽지 않는다.
      'member_note': '힘들었어요',
      'trainer_feedback': '잘했어요',
    });
    expect(r.minutes, 20);
    expect(r.source, 'ai');
    expect(r.completed, isTrue);
    expect(r.completedAt, DateTime.utc(2026, 8, 13, 10));
    expect(r.completedMinutes, 25);
    expect(r.completedIntensity, 'high');
    // 권장 강도와 회원이 고른 강도는 서로 다른 칸이다(#2160) — 하나로 뭉치면
    // 권장대로 했는지 알 수 없다.
    expect(r.intensity, 'light');
  });

  test(
    'coachRoutineFromJson defaults a missing intensity to moderate (#2160)',
    () {
      // 이 키가 없던 옛 응답. 서버 기본값과 같은 값으로 읽어야 줄이 비지 않는다.
      final r = coachRoutineFromJson(<String, Object?>{
        'id': 'r-old',
        'name': '실내 자전거',
        'minutes': 20,
        'type': '유산소',
        'reason': '',
        'source': 'trainer',
      });
      expect(r.intensity, 'moderate');
    },
  );

  test('coachSessionFromJson keeps non-strength program duration (#2126)', () {
    final CoachSession session = coachSessionFromJson(<String, Object?>{
      'id': 'session-1',
      'date': '2026-09-21',
      'time': '18:00',
      'type': '1:1 PT',
      'duration_minutes': 50,
      'status': '완료',
      'note': '',
      'program': <Object?>[
        <String, Object?>{
          'name': '마무리 러닝머신',
          'sets': null,
          'reps': null,
          'weight': null,
          'duration': '10분',
        },
      ],
    });

    expect(session.program.single.duration, 10);
    // `duration_seconds` 를 모르는 옛 응답은 분에서 되짚는다(#2221).
    expect(session.program.single.durationSeconds, 600);
  });

  test('coachSessionFromJson reads session_number (#2697)', () {
    CoachSession parse(Object? number) =>
        coachSessionFromJson(<String, Object?>{
          'id': 'session-number',
          'date': '2026-09-21',
          'time': '18:00',
          'type': '1:1 PT',
          'duration_minutes': 50,
          'status': '완료',
          'note': '',
          'program': const <Object?>[],
          'session_number': number,
        });

    expect(parse(12).sessionNumber, 12);
    // 예정·상담과 옛 서버는 싣지 않는다 — 칩을 세우지 않는다.
    expect(parse(null).sessionNumber, isNull);
    expect(parse(0).sessionNumber, isNull);
  });

  group('duration_seconds (#2221)', () {
    test('coachSessionFromJson reads program seconds', () {
      final CoachSession session = coachSessionFromJson(<String, Object?>{
        'id': 'session-2',
        'date': '2026-09-28',
        'time': '18:00',
        'type': '1:1 PT',
        'duration_minutes': 50,
        'status': '완료',
        'note': '',
        'program': <Object?>[
          <String, Object?>{
            'name': '플랭크',
            'sets': null,
            'reps': null,
            'weight': null,
            // 서버가 초에서 반올림한 분 — 0 초과면 최소 1.
            'duration': 1,
            'duration_seconds': 45,
          },
          <String, Object?>{
            'name': '스쿼트',
            'sets': 4,
            'reps': 12,
            'weight': 40,
            'duration': null,
            'duration_seconds': null,
          },
        ],
      });

      expect(session.program.first.duration, 1);
      expect(session.program.first.durationSeconds, 45);
      // 근력은 세트로 잰다 — 초가 없다.
      expect(session.program.last.durationSeconds, isNull);
    });

    test(
      'coachRoutineFromJson reads routine, completion and exercise seconds',
      () {
        final CoachRoutine r = coachRoutineFromJson(<String, Object?>{
          'id': 'r-seconds',
          'name': '유산소 세션',
          'minutes': 90,
          'duration_seconds': 5400,
          'type': '유산소',
          'reason': '',
          'source': 'trainer',
          'completed': true,
          'completed_minutes': 1,
          'completed_duration_seconds': 45,
          'exercises': <Object?>[
            <String, Object?>{
              'name': '버피',
              'duration': 1,
              'duration_seconds': 45,
              'memo': '',
            },
            <String, Object?>{
              'name': '레그프레스',
              'sets': 4,
              'reps': 12,
              'weight': 60,
              'duration': null,
              'duration_seconds': null,
              'memo': '',
            },
          ],
        });

        expect(r.minutes, 90);
        expect(r.durationSeconds, 5400);
        expect(r.completedMinutes, 1);
        expect(r.completedDurationSeconds, 45);
        expect(r.exercises.first.duration, 1);
        expect(r.exercises.first.durationSeconds, 45);
        expect(r.exercises.last.durationSeconds, isNull);
      },
    );

    test('legacy minute-only JSON still reads (duration × 60)', () {
      final CoachRoutine r = coachRoutineFromJson(<String, Object?>{
        'id': 'r-legacy',
        'name': '실내 자전거',
        'minutes': 20,
        'type': '유산소',
        'reason': '',
        'source': 'trainer',
        'completed': true,
        'completed_minutes': 25,
        'exercises': <Object?>[
          <String, Object?>{'name': '실내 자전거', 'duration': 20, 'memo': ''},
        ],
      });

      expect(r.minutes, 20);
      // 루틴 단위의 초는 비워 둔다 — 화면이 [minutes] 로 떨어진다.
      expect(r.durationSeconds, isNull);
      expect(r.completedMinutes, 25);
      expect(r.completedDurationSeconds, isNull);
      expect(r.exercises.single.duration, 20);
      expect(r.exercises.single.durationSeconds, 1200);
    });

    test('copyWith keeps the assigned seconds and adds completion seconds', () {
      const CoachRoutine routine = CoachRoutine(
        id: 'r-45s',
        name: '버피',
        minutes: 1,
        durationSeconds: 45,
        type: '유산소',
        reason: '',
        source: 'trainer',
      );

      final CoachRoutine done = routine.copyWith(
        completed: true,
        completedMinutes: 1,
        completedDurationSeconds: 45,
      );
      expect(done.durationSeconds, 45);
      expect(done.completedDurationSeconds, 45);
      // 완료와 상관없는 복사에도 초가 따라간다.
      expect(
        done.copyWith(completedIntensity: 'high').completedDurationSeconds,
        45,
      );
    });
  });

  group('coachMessageFromJson (member viewpoint)', () {
    test('maps a coach (trainer) message', () {
      final m = coachMessageFromJson(<String, Object?>{
        'id': 'm1',
        'sender': 'trainer',
        'body': '안녕하세요',
        'time_label': '13:20',
        'created_at': '2026-08-07T13:20:00Z',
      });
      expect(m.sender, CoachSender.trainer);
      expect(m.fromMe, isFalse);
      expect(m.createdAt, DateTime.utc(2026, 8, 7, 13, 20));
      expect(m.attachment, isNull);
    });

    test('maps a PDF attachment', () {
      final m = coachMessageFromJson(<String, Object?>{
        'id': 'm-pdf',
        'sender': 'trainer',
        'body': '이번 주 리포트입니다.',
        'time_label': '13:20',
        'created_at': '2026-08-07T13:20:00Z',
        'attachment': <String, Object?>{
          'type': 'pdf',
          'file_name': '이지수_주간리포트.pdf',
          'file_id': 'file123',
          'file_size': 4096,
          'download_path': '/chat/attachments/file123',
        },
      });
      expect(m.attachment?.fileName, '이지수_주간리포트.pdf');
      expect(m.attachment?.fileSize, 4096);
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
        coachMessageFromJson(message('2026-08-17')).reportWeekStart,
        DateTime(2026, 8, 17),
      );
      // 파일명이나 본문으로 추측하지 않는다. 그리고 안내 상자 하나 때문에
      // 대화 전체가 뜨지 않는 편보다, 일반 대화로 그리는 편이 낫다.
      expect(coachMessageFromJson(message(null)).reportWeekStart, isNull);
      expect(coachMessageFromJson(message('지난주')).reportWeekStart, isNull);
    });

    test('maps my own message', () {
      final m = coachMessageFromJson(<String, Object?>{
        'id': 'm2',
        'sender': 'me',
        'body': '좋아요',
        'time_label': '13:21',
        'created_at': '2026-08-07T13:21:00Z',
      });
      expect(m.sender, CoachSender.me);
      expect(m.fromMe, isTrue);
    });

    test('rejects an unknown sender', () {
      expect(
        () => coachMessageFromJson(<String, Object?>{
          'id': 'm3',
          'sender': 'client',
          'body': '잘못된 발신자',
          'time_label': '13:22',
          'created_at': '2026-08-07T13:22:00Z',
        }),
        throwsFormatException,
      );
    });

    test('rejects an invalid created_at value', () {
      expect(
        () => coachMessageFromJson(<String, Object?>{
          'id': 'm4',
          'sender': 'trainer',
          'body': '잘못된 시간',
          'time_label': '13:23',
          'created_at': 'not-a-date',
        }),
        throwsFormatException,
      );
    });
  });

  test('coachRoutineFromJson maps a program session (#709)', () {
    final r = coachRoutineFromJson(<String, Object?>{
      'id': 'r-session-1',
      'name': '세션 A · 하체',
      'minutes': 30,
      'type': '근력',
      'reason': '레그프레스, 스쿼트',
      'source': 'trainer',
      'program_name': '주 2회 분할',
      'session_name': '세션 A · 하체',
      'session_order': 2,
      'exercises': <Object?>[
        <String, Object?>{
          'name': '레그프레스',
          'sets': '4',
          'reps': '12회',
          'weight': '60kg',
          'duration': '',
          'rest': '90',
          'memo': '',
        },
      ],
    });

    expect(r.programName, '주 2회 분할');
    expect(r.sessionName, '세션 A · 하체');
    // 0 을 그대로 두면 매퍼가 항상 기본값을 돌려줘도 통과한다.
    expect(r.sessionOrder, 2);
    expect(r.isProgramSession, isTrue);
    expect(r.exercises.single.name, '레그프레스');
    // 값은 수로 든다(#1904). 여기 픽스처는 단위가 섞인 **옛** 응답이라, 숫자만
    // 떼어 읽는지까지 함께 본다 — 예전 응답 한 줄 때문에 세션 구성이 통째로
    // 비면 안 된다.
    expect(r.exercises.single.sets, 4);
    expect(r.exercises.single.reps, 12);
    expect(r.exercises.single.weight, 60);
    expect(r.exercises.single.duration, isNull);
    expect(r.exercises.single.rest, 90);
  });

  test('coachRoutineFromJson reads numeric exercise values as they come', () {
    // 지금 서버(`ProgramDraftExercise`)가 내려보내는 모양 — 전부 수다.
    final r = coachRoutineFromJson(<String, Object?>{
      'id': 'r-num',
      'name': '하체',
      'minutes': 40,
      'type': '근력',
      'reason': '',
      'source': 'trainer',
      'exercises': <Object?>[
        <String, Object?>{
          'name': '레그프레스',
          'sets': 4,
          'reps': 12,
          'weight': 62.5,
          'duration': null,
          'memo': '',
        },
      ],
    });

    expect(r.exercises.single.sets, 4);
    expect(r.exercises.single.reps, 12);
    expect(r.exercises.single.weight, 62.5);
    expect(r.exercises.single.duration, isNull);
    // 지금 계약에 없는 칸은 비어 온다.
    expect(r.exercises.single.rest, isNull);
  });

  test('coachRoutineFromJson keeps working without the session keys', () {
    // 세션 필드가 없던 예전 응답 — 단일 배정으로 읽힌다.
    final r = coachRoutineFromJson(<String, Object?>{
      'id': 'r1',
      'name': '저강도 유산소',
      'minutes': 20,
      'type': '유산소',
      'reason': '혈압 안정',
      'source': 'ai',
    });
    expect(r.programName, '');
    expect(r.sessionName, '');
    expect(r.isProgramSession, isFalse);
    expect(r.exercises, isEmpty);
  });

  test('copyWith keeps the program session data (#709)', () {
    const routine = CoachRoutine(
      id: 'r-session-1',
      name: '세션 A · 하체',
      minutes: 30,
      type: '근력',
      reason: '레그프레스',
      source: 'trainer',
      programName: '주 2회 분할',
      sessionName: '세션 A · 하체',
      sessionOrder: 1,
      exercises: <CoachRoutineExercise>[CoachRoutineExercise(name: '레그프레스')],
    );

    // 완료만 표시했는데 프로그램 제목과 운동 구성이 사라지면 안 된다.
    final completed = routine.copyWith(completed: true);
    expect(completed.completed, isTrue);
    expect(completed.programName, '주 2회 분할');
    expect(completed.sessionName, '세션 A · 하체');
    expect(completed.sessionOrder, 1);
    expect(completed.exercises.single.name, '레그프레스');
  });
}
