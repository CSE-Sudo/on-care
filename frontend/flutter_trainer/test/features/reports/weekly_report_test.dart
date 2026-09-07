import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

import '../../helpers/client_factory.dart';

/// 문구 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();

ScheduleSession session({
  required String date,
  String status = '예정',
  String clientName = '테스트회원',
  List<ProgramItem> program = const <ProgramItem>[],
}) {
  return ScheduleSession(
    id: 'sess-$date-$status',
    date: date,
    time: '10:00',
    clientName: clientName,
    type: '1:1 PT',
    durationMinutes: 60,
    status: status,
    note: '',
    program: program,
  );
}

void main() {
  // A fixed Wednesday so the week boundaries are unambiguous.
  final wednesday = DateTime(2026, 8, 5);
  final monday = DateTime(2026, 8, 3);
  final sunday = DateTime(2026, 8, 9);

  group('weekStartOf', () {
    test('resolves any day to its Monday', () {
      expect(weekStartOf(wednesday), monday);
      expect(weekStartOf(monday), monday);
      expect(weekStartOf(sunday), monday);
    });

    test('strips the time so two moments on one day agree', () {
      expect(
        weekStartOf(DateTime(2026, 8, 5, 23, 59)),
        weekStartOf(DateTime(2026, 8, 5, 0, 1)),
      );
    });
  });

  group('buildWeeklyReport', () {
    test('counts only the sessions inside the reported week', () {
      final report = buildWeeklyReport(
        client: makeClient(),
        sessions: <ScheduleSession>[
          session(date: ymd(monday), status: '완료'),
          session(date: ymd(sunday)),
          // Last Sunday and next Monday are outside the window.
          session(date: ymd(monday.subtract(const Duration(days: 1)))),
          session(date: ymd(sunday.add(const Duration(days: 1)))),
        ],
        weekStart: wednesday,
        // Every call here pins `today`. Left to DateTime.now() the report
        // silently switches to "past week" mode once the clock leaves
        // 8/3–8/9, which drops completionAvg/sodium and flips isGoodWeek.
        // That is what broke the suite on 2026-08-10 (#551).
        today: wednesday,
      );

      expect(report.sessionsBooked, 2);
      expect(report.sessionsDone, 1);
      expect(report.attendanceRate, 50);
    });

    test('gap slots are not sessions', () {
      final report = buildWeeklyReport(
        client: makeClient(),
        sessions: <ScheduleSession>[session(date: ymd(monday), status: '공백')],
        weekStart: wednesday,
        today: wednesday,
      );

      expect(report.sessionsBooked, 0);
      // Nothing booked — a rate would be a divide-by-zero fiction.
      expect(report.attendanceRate, isNull);
    });

    test('completion averages only the recorded days', () {
      final report = buildWeeklyReport(
        client: makeClient(weekCompletion: const <int>[80, 60, 0, 0, 0, 0, 0]),
        sessions: const <ScheduleSession>[],
        weekStart: wednesday,
        today: wednesday,
      );

      expect(report.completionAvg, 70);
    });

    test('a client with no logged days reports null, not 0%', () {
      final report = buildWeeklyReport(
        client: makeClient(weekCompletion: const <int>[0, 0, 0, 0, 0, 0, 0]),
        sessions: const <ScheduleSession>[],
        weekStart: wednesday,
        today: wednesday,
      );

      expect(report.completionAvg, isNull);
    });

    test('a PAST week does not borrow this week\'s roster aggregates', () {
      // weekCompletion/sodiumWeek carry no week of their own — they are
      // whatever the roster last computed. Attaching them to an earlier
      // week would report this week's numbers under last week's dates,
      // and the trainer can SEND that to the member.
      final lastWeek = monday.subtract(const Duration(days: 7));
      final report = buildWeeklyReport(
        client: makeClient(
          weekCompletion: const <int>[80, 80, 80, 80, 80, 80, 80],
          sodiumWeek: const <int>[2500, 2500, 1000, 1000, 1000, 1000, 1000],
        ),
        sessions: const <ScheduleSession>[],
        weekStart: lastWeek,
        today: wednesday,
      );

      expect(report.completionAvg, isNull);
      expect(report.sodiumOverDays, isNull);
      expect(report.sodiumAvg, isNull);
      // Unknown is not good — praise has to be earned by data we have.
      expect(report.isGoodWeek, isFalse);
    });

    test('the CURRENT week still uses them', () {
      final report = buildWeeklyReport(
        client: makeClient(
          weekCompletion: const <int>[80, 80, 80, 80, 80, 80, 80],
        ),
        sessions: const <ScheduleSession>[],
        weekStart: wednesday,
        today: wednesday,
      );

      expect(report.completionAvg, 80);
      expect(report.sodiumOverDays, isNotNull);
    });

    test('a past week\'s message omits the figures it cannot know', () {
      final report = buildWeeklyReport(
        client: makeClient(),
        sessions: const <ScheduleSession>[],
        weekStart: monday.subtract(const Duration(days: 7)),
        today: wednesday,
      );

      final message = reportMessage(_ko, report);
      expect(message, isNot(contains('이행률')));
      expect(message, isNot(contains('나트륨')));
    });

    test('carries the sodium figures from the client', () {
      final report = buildWeeklyReport(
        client: makeClient(
          sodiumWeek: const <int>[2500, 2400, 1000, 1000, 1000, 1000, 1000],
        ),
        sessions: const <ScheduleSession>[],
        weekStart: wednesday,
        today: wednesday,
      );

      expect(report.sodiumOverDays, 2);
      expect(report.sodiumAvg, 1414);
    });

    test('isGoodWeek needs both adherence and diet to hold up', () {
      WeeklyReport reportFor({required int completion, required int overDays}) {
        return buildWeeklyReport(
          client: makeClient(
            weekCompletion: List<int>.filled(7, completion),
            sodiumWeek: <int>[
              for (var i = 0; i < 7; i++) i < overDays ? 2500 : 1000,
            ],
          ),
          sessions: const <ScheduleSession>[],
          weekStart: wednesday,
          today: wednesday,
        );
      }

      expect(reportFor(completion: 80, overDays: 1).isGoodWeek, isTrue);
      expect(reportFor(completion: 50, overDays: 1).isGoodWeek, isFalse);
      expect(reportFor(completion: 80, overDays: 4).isGoodWeek, isFalse);
    });
  });

  group('reportMessage', () {
    test('reads as a trainer message, ending with encouragement', () {
      final report = buildWeeklyReport(
        client: makeClient(name: '김민수'),
        sessions: <ScheduleSession>[session(date: ymd(monday), status: '완료')],
        weekStart: wednesday,
        today: wednesday,
      );

      final message = reportMessage(_ko, report);
      // 회원이 그대로 받는 편지다 — 첫 줄에 무슨 메시지인지, 본문은 문단으로,
      // 마지막은 다음 주 이야기로 끝난다(#755).
      expect(message, startsWith('김민수님,'));
      expect(message, contains('주간 리포트'));
      // PT 진행 횟수는 적지 않는다 — 회원에게 보낼 글은 그 주에 무엇을 했고
      // 무엇을 챙길지를 말하는 자리다(#1177).
      expect(message, isNot(contains('PT 세션')));
      // 지난 주 리포트에도 그대로 나가는 문장이라 `이번 주` 로 시작하지
      // 않는다 — 어느 주인지는 첫 줄의 날짜 범위가 말한다(#1177).
      expect(message, contains('정말 잘하셨어요'));
      expect(message, contains('\n\n'), reason: '한 덩어리가 아니라 문단으로 나뉘어야 한다');
    });

    test('건너뛴 운동은 분량을 떼고 한 번만 적는다 (#1177)', () {
      // 같은 스트레칭을 요일마다 건너뛰면 예전에는 `하체 스트레칭 10분,
      // 하체 스트레칭 5분, …` 이 되어 서로 다른 운동 셋을 빠뜨린 것처럼 읽혔다.
      final report = WeeklyReport(
        client: makeClient(name: '김민수'),
        weekStart: monday,
        sessionsBooked: 0,
        sessionsDone: 0,
        completionAvg: 80,
        sodiumOverDays: 0,
        sodiumAvg: 1500,
        isCurrentWeek: true,
        weekCompletion: const <int>[80, 80, 80, 80, 80, 80, 80],
        days: const <ReportDay>[
          ReportDay(completion: 80, exercises: <String>['하체 스트레칭 10분✗']),
          ReportDay(completion: 80, exercises: <String>['하체 스트레칭 5분✗']),
          ReportDay(completion: 80, exercises: <String>['벤치프레스 40kg · 4세트✗']),
        ],
      );

      final message = reportMessage(_ko, report);
      expect(message, contains('다만 하체 스트레칭, 벤치프레스는 건너뛰셨더라고요'));
      expect(message, isNot(contains('10분')));
    });

    test('수치는 화면과 같은 서식으로, 목표는 상수에서 적는다 (#1177)', () {
      final report = WeeklyReport(
        client: makeClient(name: '김민수'),
        weekStart: monday,
        sessionsBooked: 0,
        sessionsDone: 0,
        completionAvg: 81,
        sodiumOverDays: 3,
        sodiumAvg: 1916,
        isCurrentWeek: true,
        caloriesWeek: const <int>[1531, 1531, 1531, 1531, 1531, 1531, 1531],
      );

      final message = reportMessage(_ko, report);
      // 그래프가 `1,916mg` 이라고 적는 값을 문장만 `1916mg` 이라고 쓰면 회원은
      // 다른 값으로 읽는다.
      expect(message, contains('1,916mg'));
      expect(message, contains('1,531kcal'));
      // 평균이 목표 안이어도 넘긴 **날**이 있었다는 사실을 뒤섞지 않는다.
      expect(message, contains('목표(2,000mg)를 넘긴 날이 3일'));
    });

    test('omits figures the client has no data for', () {
      final report = buildWeeklyReport(
        client: makeClient(
          weekCompletion: const <int>[],
          sodiumWeek: const <int>[],
        ),
        sessions: const <ScheduleSession>[],
        weekStart: wednesday,
        today: wednesday,
      );

      final message = reportMessage(_ko, report);
      expect(message, isNot(contains('이행률')));
      expect(message, isNot(contains('나트륨')));
    });
  });

  group('buildTrainerWeekStats', () {
    test('summarises the trainer’s own week across all clients', () {
      final stats = buildTrainerWeekStats(
        sessions: <ScheduleSession>[
          session(date: ymd(monday), status: '완료'),
          session(
            date: ymd(wednesday),
            program: const <ProgramItem>[
              ProgramItem(name: '스쿼트', sets: 3, weight: 60),
            ],
          ),
          session(date: ymd(sunday), status: '공백'),
        ],
        clients: const <TrainerClient>[],
      );

      expect(stats.sessionsBooked, 2);
      expect(stats.sessionsDone, 1);
      expect(stats.programsSent, 1);
      expect(stats.completionRate, 50);
    });

    test('an empty week has no completion rate rather than 0%', () {
      final stats = buildTrainerWeekStats(
        sessions: const <ScheduleSession>[],
        clients: const <TrainerClient>[],
      );

      expect(stats.completionRate, isNull);
    });
  });
}
