/// 데모 회원의 지난 리포트 이력. (#2399)
///
/// 데모 전송 기록이 이번 주에만 붙어, 지난 주로 가면 열다섯 명이 전부
/// 미전송으로 섰다. 이 파일이 지키는 것:
///  * 오래된 회원은 이번 주 포함 열네 주(지난 주만 열세 주) 이력이 있다.
///  * 신규·적응 중 회원은 붙은 주보다 앞선 이력이 없다.
///  * 지난 주 기록도 본문을 비워 둔다 — 화면이 그 주 수치로 초안을 만든다(#2423).
///  * 같은 회원·같은 주·같은 오늘이면 언제 만들어도 같은 이력이다.
///  * 보낸 시각은 그 주 주말부터 다음 주 초 사이이고, 오늘을 넘지 않는다.
///  * 데모 저장소가 지난 주 이력을 돌려주고, 실행 중에 보낸 것이 이긴다.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/demo_language.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/fixed_clock.dart';

/// 목요일 낮 — 이번 주는 2026-08-17(월)에 시작한다.
final DateTime _today = DateTime(2026, 8, 20, 13);
final DateTime _thisMonday = DateTime(2026, 8, 17);
final DateTime _lastMonday = DateTime(2026, 8, 10);

/// 데모 로스터.
final List<String> _ids = <String>[
  for (int i = 1; i <= 15; i++) 'seed-client-$i',
];

/// 신규·적응 중 회원.
const Set<String> _newcomers = <String>{'seed-client-7', 'seed-client-15'};

List<DemoReportWeek> _history(String id, {DateTime? today}) =>
    demoReportHistoryFor(clientId: id, today: today ?? _today);

List<DemoReportMember> get _roster => <DemoReportMember>[
  for (final String id in _ids) (id: id),
];

LocalReportRepository _local(AppDatabase db) => LocalReportRepository(
  DriftScheduleRepository(db),
  DriftChatRepository(db),
  db,
);

void main() {
  group('demoReportHistoryFor — 주 수와 가입 시점', () {
    test('오래된 회원은 이번 주 포함 열네 주, 지난 주만 열세 주 이상이다', () {
      for (final String id in _ids) {
        if (_newcomers.contains(id)) continue;
        final List<DemoReportWeek> weeks = _history(id);
        expect(weeks, hasLength(demoReportHistoryWeeks), reason: id);
        expect(
          weeks.where((w) => w.weekStart.isBefore(_thisMonday)).length,
          greaterThanOrEqualTo(13),
          reason: '$id 의 지난 주 이력이 석 달에 못 미친다',
        );
      }
    });

    test('최신 주부터 한 주씩 거슬러 간다', () {
      final List<DemoReportWeek> weeks = _history('seed-client-1');
      expect(weeks.first.weekStart, _thisMonday);
      for (int i = 1; i < weeks.length; i++) {
        expect(
          weeks[i].weekStart,
          DateTime(
            _thisMonday.year,
            _thisMonday.month,
            _thisMonday.day - 7 * i,
          ),
        );
        expect(weeks[i].weekStart.weekday, DateTime.monday);
      }
    });

    test('이번 주에 붙은 신규 회원은 이번 주 한 줄뿐이고 아직 보내지 않았다', () {
      final List<DemoReportWeek> weeks = _history('seed-client-7');
      expect(weeks, hasLength(1));
      expect(weeks.single.weekStart, _thisMonday);
      expect(weeks.single.sent, isFalse);
    });

    test('지난 주에 붙은 회원은 지난 주부터이고, 첫 주 리포트는 나갔다', () {
      final List<DemoReportWeek> weeks = _history('seed-client-15');
      expect(weeks.map((w) => w.weekStart), <DateTime>[
        _thisMonday,
        _lastMonday,
      ]);
      expect(weeks.last.sent, isTrue);
    });

    test('가입 주보다 앞선 주에는 어느 신규 회원도 기록이 없다', () {
      for (int back = 1; back < demoReportHistoryWeeks; back++) {
        final DateTime week = DateTime(2026, 8, 17 - 7 * back);
        final Set<String> sent = <String>{
          for (final ReportSendRecord r in demoSentReportsForWeek(
            roster: _roster,
            weekStart: week,
            today: _today,
          ))
            r.clientId,
        };
        expect(sent, isNot(contains('seed-client-7')), reason: '$week');
        if (back > 1) {
          expect(sent, isNot(contains('seed-client-15')), reason: '$week');
        }
      }
    });

    test('데모 로스터가 아닌 회원은 이력이 없다', () {
      expect(
        demoReportHistoryFor(clientId: 'user-7d4e9a2c5f18', today: _today),
        isEmpty,
      );
      expect(
        demoSentReportsForWeek(
          roster: <DemoReportMember>[(id: 'c1')],
          weekStart: _lastMonday,
          today: _today,
        ),
        isEmpty,
      );
    });
  });

  group('demoReportHistoryFor — 이번 주', () {
    test('이번 주 줄은 작업대 데모 명단과 같다', () {
      for (final String id in _ids) {
        final DemoReportWeek current = _history(id).first;
        final bool listed = demoSentReports.any((d) => d.clientId == id);
        expect(current.sent, listed, reason: id);
        if (listed) {
          // 작업대가 얹는 기록과 한 치도 다르지 않다.
          final ReportSendRecord shown = sendRecordFor(
            withDemoSends(
              const <String, ReportSendRecord>{},
              <String>{id},
              _thisMonday,
              today: _today,
            ),
            id,
            _thisMonday,
          )!;
          expect(current.record!.sentAt, shown.sentAt);
          expect(current.record!.read, shown.read);
          expect(current.record!.message, isEmpty);
        }
      }
    });

    test('지난 주 목록은 이번 주를 돌려주지 않는다 — 이번 주는 작업대 몫이다', () {
      expect(
        demoSentReportsForWeek(
          roster: _roster,
          weekStart: _thisMonday,
          today: _today,
        ),
        isEmpty,
      );
      expect(
        demoSentReportsForWeek(
          roster: _roster,
          weekStart: DateTime(2026, 8, 24),
          today: _today,
        ),
        isEmpty,
      );
    });

    test('이력 창보다 오래된 주는 비어 있다', () {
      expect(
        demoSentReportsForWeek(
          roster: _roster,
          weekStart: DateTime(2026, 8, 17 - 7 * demoReportHistoryWeeks),
          today: _today,
        ),
        isEmpty,
      );
    });
  });

  group('demoReportHistoryFor — 전송 시각·열람', () {
    test('지난 주 리포트는 그 주 토요일부터 다음 주 화요일 사이에 나갔다', () {
      for (final String id in _ids) {
        for (final DemoReportWeek w in _history(id).skip(1)) {
          final ReportSendRecord? r = w.record;
          if (r == null) continue;
          expect(r.weekStart, w.weekStart);
          final DateTime from = DateTime(
            w.weekStart.year,
            w.weekStart.month,
            w.weekStart.day + 5,
          );
          final DateTime to = DateTime(
            w.weekStart.year,
            w.weekStart.month,
            w.weekStart.day + 9,
          );
          expect(r.sentAt.isBefore(from), isFalse, reason: '$id ${r.sentAt}');
          expect(r.sentAt.isBefore(to), isTrue, reason: '$id ${r.sentAt}');
          expect(r.sentAt.isAfter(_today), isFalse, reason: '$id ${r.sentAt}');
        }
      }
    });

    test('월요일 아침에 열어도 지난 주 기록이 아직 오지 않은 시각에 서지 않는다', () {
      final DateTime mondayMorning = DateTime(2026, 8, 17, 7);
      for (final String id in _ids) {
        for (final DemoReportWeek w in _history(
          id,
          today: mondayMorning,
        ).skip(1)) {
          final ReportSendRecord? r = w.record;
          if (r == null) continue;
          expect(r.sentAt.isAfter(mondayMorning), isFalse, reason: id);
        }
      }
    });

    test('일부 주는 미전송·안 읽음으로 남는다', () {
      final List<DemoReportWeek> past = <DemoReportWeek>[
        for (final String id in _ids) ..._history(id).skip(1),
      ];
      expect(past.where((w) => !w.sent), isNotEmpty);
      expect(past.where((w) => w.sent && !w.record!.read), isNotEmpty);
      // 대부분은 나가고 읽혔다 — 석 달을 굴려 온 트레이너의 작업대다.
      expect(
        past.where((w) => w.sent && w.record!.read).length,
        greaterThan(past.length ~/ 2),
      );
    });

    test('완벽한 대조군 최우진은 빠짐없이 나가고 전부 읽었다', () {
      for (final DemoReportWeek w in _history('seed-client-5').skip(1)) {
        expect(w.sent, isTrue, reason: '${w.weekStart}');
        expect(w.record!.read, isTrue, reason: '${w.weekStart}');
      }
    });

    test('휴면 박성호는 최근 다섯 주에 보낸 리포트를 하나도 읽지 않았다', () {
      final List<DemoReportWeek> weeks = _history('seed-client-3');
      for (final DemoReportWeek w in weeks.skip(1).take(5)) {
        if (!w.sent) continue;
        expect(w.record!.read, isFalse, reason: '${w.weekStart}');
      }
    });

    test('급성 악화 오세라는 최근 두 주를 읽지 않았다', () {
      for (final DemoReportWeek w in _history(
        'seed-client-8',
      ).skip(1).take(2)) {
        if (!w.sent) continue;
        expect(w.record!.read, isFalse, reason: '${w.weekStart}');
      }
    });
  });

  group('demoReportHistoryFor — 결정성', () {
    test('같은 입력이면 같은 이력이다', () {
      for (final String id in _ids) {
        final List<DemoReportWeek> a = _history(id);
        final List<DemoReportWeek> b = _history(id);
        expect(a.length, b.length);
        for (int i = 0; i < a.length; i++) {
          expect(a[i].weekStart, b[i].weekStart);
          expect(a[i].record?.sentAt, b[i].record?.sentAt);
          expect(a[i].record?.read, b[i].record?.read);
          expect(a[i].record?.message, b[i].record?.message);
        }
      }
    });

    test('같은 주의 기록은 오늘이 같은 주 안에서 바뀌어도 그대로다', () {
      final List<DemoReportWeek> thursday = _history('seed-client-2');
      final List<DemoReportWeek> saturday = _history(
        'seed-client-2',
        today: DateTime(2026, 8, 22, 15),
      );
      for (int i = 1; i < thursday.length; i++) {
        expect(saturday[i].record?.sentAt, thursday[i].record?.sentAt);
        expect(saturday[i].record?.message, thursday[i].record?.message);
      }
    });

    test('회원별 보낸 시각이 한 시각으로 몰리지 않는다', () {
      final Set<DateTime> times = <DateTime>{
        for (final ReportSendRecord r in demoSentReportsForWeek(
          roster: _roster,
          weekStart: DateTime(2026, 7, 27),
          today: _today,
        ))
          r.sentAt,
      };
      expect(times.length, greaterThan(3));
    });
  });

  group('지난 주 본문 — 그 주 수치로 만든 초안 (#2423)', () {
    test('모든 회원의 모든 지난 주 기록은 본문을 비워 둔다', () {
      // 목표에 맞춘 고정 문장을 깔아 두면, 칼로리를 매일 넘긴 주에도 "잘하고
      // 계세요" 가 남는다. 비워 두면 화면이 그 주 수치로 초안을 만든다.
      int sent = 0;
      for (final String id in _ids) {
        for (final DemoReportWeek w in _history(id).skip(1)) {
          if (!w.sent) continue;
          sent++;
          expect(w.record!.message, isEmpty, reason: '$id ${w.weekStart}');
        }
      }
      expect(sent, greaterThan(_ids.length), reason: '지난 주 기록이 있어야 한다');
    });

    test('작업대가 읽는 지난 주 기록도 본문이 비어 있다', () {
      final List<ReportSendRecord> records = demoSentReportsForWeek(
        roster: _roster,
        weekStart: _lastMonday,
        today: _today,
      );
      expect(records, isNotEmpty);
      expect(records.where((r) => r.message.isNotEmpty), isEmpty);
    });

    test('이번 주 기록과 같은 규칙이다', () {
      for (final String id in _ids) {
        final DemoReportWeek current = _history(id).first;
        if (current.sent) expect(current.record!.message, isEmpty);
      }
    });
  });

  group('LocalReportRepository.sentReports — 지난 주 데모 이력', () {
    late AppDatabase db;

    setUp(() {
      useFixedKstDate(_today);
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    test('지난 주로 물으면 데모 로스터의 그 주 이력이 선다', () async {
      await seedIfEmpty(db, clock: _today);

      final List<ReportSendRecord> records = await _local(
        db,
      ).sentReports(weekStart: _lastMonday);
      final List<ReportSendRecord> expected = demoSentReportsForWeek(
        roster: _roster,
        weekStart: _lastMonday,
        today: _today,
      );

      expect(records, isNotEmpty);
      expect(
        records.map((r) => r.clientId).toSet(),
        expected.map((r) => r.clientId).toSet(),
      );
      for (final ReportSendRecord r in records) {
        expect(r.weekStart, _lastMonday);
        // 본문은 비어 있다 — 화면이 그 주 수치로 초안을 만든다(#2423).
        expect(r.message, isEmpty);
      }
    });

    test('석 달 전 주까지 거슬러 가도 이력이 있다', () async {
      await seedIfEmpty(db, clock: _today);
      final DateTime oldest = DateTime(2026, 8, 17 - 7 * 13);

      expect(await _local(db).sentReports(weekStart: oldest), isNotEmpty);
    });

    test('이번 주에는 데모 이력을 돌려주지 않는다 — 작업대가 따로 얹는다', () async {
      await seedIfEmpty(db, clock: _today);

      expect(await _local(db).sentReports(weekStart: _thisMonday), isEmpty);
    });

    test('실행 중에 지난 주로 보낸 것이 데모 이력을 이긴다', () async {
      await seedIfEmpty(db, clock: _today);
      await _local(db).sendPdf(
        clientId: 'seed-client-5',
        weekStart: _lastMonday,
        bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
        fileName: 'weekly.pdf',
        message: '다시 보낸 지난 주 리포트',
      );

      final List<ReportSendRecord> mine = <ReportSendRecord>[
        for (final ReportSendRecord r in await _local(
          db,
        ).sentReports(weekStart: _lastMonday))
          if (r.clientId == 'seed-client-5') r,
      ];
      expect(mine, hasLength(1));
      expect(mine.single.message, '다시 보낸 지난 주 리포트');
      expect(mine.single.sentAt, _today);
    });

    test('영어 데모도 본문을 비워 두어 화면 언어로 초안이 선다', () async {
      await seedIfEmpty(db, clock: _today, language: DemoLanguage.en);

      final List<ReportSendRecord> records = await _local(
        db,
      ).sentReports(weekStart: _lastMonday);

      expect(records, isNotEmpty);
      expect(records.where((r) => r.message.isNotEmpty), isEmpty);
    });

    test('같은 DB 로 다시 물어도(새로고침) 같은 이력이다', () async {
      await seedIfEmpty(db, clock: _today);

      final List<ReportSendRecord> first = await _local(
        db,
      ).sentReports(weekStart: _lastMonday);
      final List<ReportSendRecord> again = await _local(
        db,
      ).sentReports(weekStart: _lastMonday);

      String key(ReportSendRecord r) =>
          '${r.clientId}|${r.sentAt}|${r.message}';
      expect(again.map(key).toList(), first.map(key).toList());
    });

    test('시드 대화의 리포트 안내 주에도 데모 이력만 선다', () async {
      await seedIfEmpty(db, clock: _today);
      final List<AppKeyValue> seeded = await (db.select(
        db.appKeyValues,
      )..where((t) => t.key.like('report_msg_seed-%'))).get();
      expect(seeded, isNotEmpty);

      for (final AppKeyValue marker in seeded) {
        final DateTime week = DateTime.parse(marker.value);
        final List<ReportSendRecord> records = await _local(
          db,
        ).sentReports(weekStart: week);
        final List<String> got = <String>[
          for (final ReportSendRecord r in records)
            '${r.clientId}|${ymd(r.weekStart)}|${r.message}',
        ]..sort();
        final List<String> want = <String>[
          for (final ReportSendRecord r in demoSentReportsForWeek(
            roster: _roster,
            weekStart: weekStartOf(week),
            today: _today,
          ))
            '${r.clientId}|${ymd(r.weekStart)}|${r.message}',
        ]..sort();
        expect(got, want);
      }
    });
  });
}
