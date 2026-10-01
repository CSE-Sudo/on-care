/// 데모 리포트의 PT 횟수가 스케줄 탭과 같은 자료에서 나오는지. (#2452)
///
/// 리포트는 따로 센 숫자를 들고 있지 않다 — 그 주 스케줄 행을 그대로 센다
/// (`buildWeeklyReport`). 그래서 시드가 수업을 심지 않으면 리포트가 0회로
/// 서고, 시드가 심으면 스케줄 탭에 보이는 수업 수와 리포트 숫자가 같아야 한다.
/// 이 파일은 그 두 쪽을 데모 회원 전원·이력 창의 모든 주에서 맞춰 본다.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  late AppDatabase db;
  late List<TrainerClient> clients;

  setUp(() async {
    useFixedKstDate(kMidWeekKst);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db, clock: kMidWeekKst);
    clients = (await DriftClientRepository(db).watchClients().first)
        .where((c) => c.id.startsWith('seed-client-'))
        .toList();
  });

  tearDown(() => db.close());

  DateTime weekAgo(int back) {
    final DateTime monday = weekStartOf(kMidWeekKst);
    return DateTime(monday.year, monday.month, monday.day - 7 * back);
  }

  /// 스케줄 탭의 주간 시간표가 읽는 경로 — 그 주 범위에서 이 회원 행만 센다.
  Future<List<ScheduleSession>> scheduleWeek(String clientId, int back) async {
    final DateTime start = weekAgo(back);
    final DateTime end = DateTime(start.year, start.month, start.day + 6);
    final List<ScheduleSession> range = await DriftScheduleRepository(
      db,
    ).watchRange(ymd(start), ymd(end)).first;
    return range.where((s) => s.clientId == clientId && !s.isGap).toList();
  }

  bool joinedBy(String clientId, int back) =>
      back <= (demoMemberJoinedWeeksAgo[clientId] ?? demoReportHistoryWeeks);

  test('데모 로스터가 열다섯 명 전원이다', () {
    expect(clients, hasLength(15));
  });

  test('buildWeeklyReport — 데모 회원의 이번 주 PT 는 0회가 아니다', () async {
    final DriftScheduleRepository schedule = DriftScheduleRepository(db);
    for (final TrainerClient client in clients) {
      final List<ScheduleSession> sessions = await schedule
          .watchClientSessions((id: client.id, name: client.name))
          .first;
      final WeeklyReport report = buildWeeklyReport(
        client: client,
        sessions: sessions,
        weekStart: weekAgo(0),
        today: kMidWeekKst,
      );
      expect(report.sessionsBooked, greaterThanOrEqualTo(1), reason: client.id);
      expect(report.sessionsBooked, lessThanOrEqualTo(2), reason: client.id);
    }
  });

  test('buildWeeklyReport — 회원이 붙은 뒤의 지난 주들도 PT 가 1~2회이고 모두 진행됐다', () async {
    final DriftScheduleRepository schedule = DriftScheduleRepository(db);
    for (final TrainerClient client in clients) {
      // 김민수의 수업 날은 공유 픽스처가 정한다 — 비워 둔 날이 겹친 주는 0회다.
      // 그의 수업 날은 주간 PT 시드 시험이 픽스처와 맞춰 본다(#2694).
      if (client.id == 'seed-client-1') continue;
      final List<ScheduleSession> sessions = await schedule
          .watchClientSessions((id: client.id, name: client.name))
          .first;
      for (int back = 1; back < demoReportHistoryWeeks; back++) {
        final WeeklyReport report = buildWeeklyReport(
          client: client,
          sessions: sessions,
          weekStart: weekAgo(back),
          today: kMidWeekKst,
        );
        if (!joinedBy(client.id, back)) {
          expect(report.sessionsBooked, 0, reason: '${client.id} · $back주 전');
          continue;
        }
        expect(
          report.sessionsBooked,
          inInclusiveRange(1, 2),
          reason: '${client.id} · $back주 전',
        );
        // 3주 전의 배준혁(9) 노쇼·강서연(6) 회원 취소 한 건씩은 진행되지
        // 않은 수업이다(#2669). 나머지 지난 주 수업은 모두 끝난 수업이다.
        final bool missedOne =
            back == seedPastMissWeeksAgo &&
            (client.id == 'seed-client-9' || client.id == 'seed-client-6');
        expect(
          report.sessionsDone,
          report.sessionsBooked - (missedOne ? 1 : 0),
          reason: '지난 주 수업은 끝난 수업이다 — ${client.id} · $back주 전',
        );
        if (!missedOne) expect(report.attendanceRate, 100);
      }
    }
  });

  test('리포트 저장소의 PT 횟수가 스케줄 탭의 그 주 수업 수와 같다', () async {
    final LocalReportRepository reports = LocalReportRepository(
      DriftScheduleRepository(db),
      DriftChatRepository(db),
      db,
    );
    for (final TrainerClient client in clients) {
      for (final int back in <int>[0, 1, 2, 6, demoReportHistoryWeeks - 1]) {
        final WeeklyReport report = await reports
            .watch(client: client, weekStart: weekAgo(back))
            .first;
        final List<ScheduleSession> inSchedule = await scheduleWeek(
          client.id,
          back,
        );
        expect(
          report.sessionsBooked,
          inSchedule.length,
          reason: '${client.id} · $back주 전',
        );
        expect(
          report.sessionsDone,
          inSchedule.where((s) => s.isDone).length,
          reason: '${client.id} · $back주 전',
        );
      }
    }
  });

  test('스케줄에서 수업을 지우면 리포트 숫자도 따라 줄어든다 — 따로 센 값이 없다', () async {
    final TrainerClient client = clients.firstWhere(
      (c) => c.id == 'seed-client-5',
    );
    final LocalReportRepository reports = LocalReportRepository(
      DriftScheduleRepository(db),
      DriftChatRepository(db),
      db,
    );
    final int before = (await reports
        .watch(client: client, weekStart: weekAgo(1))
        .first).sessionsBooked;

    final List<ScheduleSession> lastWeek = await scheduleWeek(client.id, 1);
    await (db.delete(
      db.trainerScheduleEntries,
    )..where((t) => t.id.equals(lastWeek.first.id))).go();

    final int after = (await reports
        .watch(client: client, weekStart: weekAgo(1))
        .first).sessionsBooked;
    expect(after, before - 1);
  });

  test('지난 주 스케줄에 그때 붙어 있던 회원 전원의 수업이 있다', () async {
    final DateTime start = weekAgo(1);
    final DateTime end = DateTime(start.year, start.month, start.day + 6);
    final List<ScheduleSession> range = await DriftScheduleRepository(
      db,
    ).watchRange(ymd(start), ymd(end)).first;
    final Set<String?> trained = range
        .where((s) => !s.isGap)
        .map((s) => s.clientId)
        .toSet();
    for (final TrainerClient client in clients) {
      if (!joinedBy(client.id, 1)) continue;
      expect(trained, contains(client.id));
    }
  });
}
