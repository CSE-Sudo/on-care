/// 회원별 지난 리포트 — 데모 저장소. (#2394)
///
/// 데모 저장소는 데모 회원의 지난 리포트 이력([demoReportHistoryFor])에 실행
/// 중 보낸 것을 얹어 돌려준다. 이 파일이 지키는 것:
///  * 데모 회원은 이력의 **보낸 주**만, 최신 주부터 선다(안 보낸 주는 빠진다 —
///    서버와 같은 모양).
///  * 데모 기록은 본문이 비어 있어, 첫 줄은 화면이 그 주 수치로 채운다(#2423).
///  * 쪽 단위로 나뉘고, `before` 로 다음 쪽을 읽는다.
///  * 실행 중에 보낸 리포트가 그 주 데모 기록을 이긴다.
///  * 데모 로스터가 아닌 회원은 실행 중 보낸 것만 선다.
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/reports/data/demo_report_history.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/fixed_clock.dart';

LocalReportRepository _local(AppDatabase db) => LocalReportRepository(
  DriftScheduleRepository(db),
  DriftChatRepository(db),
  db,
);

final Uint8List _pdf = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);

/// 최우진 — 매주 빠짐없이 받는 대조군이라 이력 창 전체가 전송 주다.
const String _steady = 'seed-client-5';

void main() {
  late AppDatabase db;

  setUp(() async {
    useFixedKstDate(kMidWeekKst);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedIfEmpty(db, clock: kMidWeekKst);
  });

  tearDown(() => db.close());

  Future<List<MemberReportHistoryItem>> readAll(String id) async {
    final List<MemberReportHistoryItem> all = <MemberReportHistoryItem>[];
    DateTime? before;
    do {
      final MemberReportHistoryPage page = await _local(
        db,
      ).memberReportHistory(clientId: id, before: before);
      all.addAll(page.items);
      before = page.nextBefore;
    } while (before != null);
    return all;
  }

  test('데모 회원은 데모 이력의 보낸 주만 최신 주부터 선다', () async {
    const String id = 'seed-client-9'; // 트레이너도 자주 건너뛰는 회원
    final List<DemoReportWeek> demo = demoReportHistoryFor(
      clientId: id,
      today: kMidWeekKst,
    );
    final List<MemberReportHistoryItem> all = await readAll(id);

    expect(all.map((i) => i.weekStart).toList(), <DateTime>[
      for (final DemoReportWeek w in demo)
        if (w.sent) w.weekStart,
    ]);
    // 건너뛴 주가 있어야 이 테스트가 `안 보낸 주는 빠진다` 를 잰다.
    expect(demo.any((w) => !w.sent), isTrue);
  });

  test('줄의 시각·열람이 데모 기록과 같고, PDF 로 나간 것으로 선다 (#2669)', () async {
    final List<DemoReportWeek> demo = demoReportHistoryFor(
      clientId: _steady,
      today: kMidWeekKst,
    );
    final List<MemberReportHistoryItem> all = await readAll(_steady);
    for (int i = 0; i < demo.length; i++) {
      expect(all[i].sentAt, demo[i].record!.sentAt);
      expect(all[i].read, demo[i].record!.read);
      // 공유 메뉴의 기본 전송이 PDF 라, 데모의 보낸 리포트는 PDF 표시를 단다.
      expect(all[i].hasPdf, isTrue);
    }
  });

  test('데모 기록은 본문을 저장하지 않고, 목록은 그 주 초안의 인사말 줄을 첫 줄로 '
      '싣는다 (#2423, #2669)', () async {
    // 목표별 고정 문장을 두지 않는다 — 첫 줄은 그 주 수치로 만든 초안에서 온다.
    for (final DemoReportWeek w in demoReportHistoryFor(
      clientId: _steady,
      today: kMidWeekKst,
    )) {
      expect(w.record!.message, isEmpty, reason: '${w.weekStart}');
    }
    final List<MemberReportHistoryItem> all = await readAll(_steady);
    expect(all.length, greaterThan(1));
    for (final MemberReportHistoryItem item in all) {
      expect(item.feedbackPreview, isNotEmpty, reason: '${item.weekStart}');
      expect(item.feedbackPreview, contains('님,'), reason: '${item.weekStart}');
    }
  });

  test('이번 주 데모 기록도 첫 줄이 그 주 초안에서 온다', () async {
    final MemberReportHistoryItem thisWeek = (await readAll(_steady)).first;
    expect(thisWeek.weekStart, weekStartOf(kMidWeekKst));
    expect(thisWeek.feedbackPreview, isNotEmpty);
  });

  test('한 쪽은 기본 쪽 크기이고 다음 쪽 커서는 그 쪽 마지막 주다', () async {
    final MemberReportHistoryPage first = await _local(
      db,
    ).memberReportHistory(clientId: _steady);
    expect(first.items, hasLength(memberReportHistoryPageSize));
    expect(first.nextBefore, first.items.last.weekStart);

    final MemberReportHistoryPage second = await _local(
      db,
    ).memberReportHistory(clientId: _steady, before: first.nextBefore);
    expect(
      second.items,
      hasLength(demoReportHistoryWeeks - memberReportHistoryPageSize),
    );
    expect(second.hasMore, isFalse);
    expect(
      second.items.first.weekStart.isBefore(first.items.last.weekStart),
      isTrue,
    );
  });

  test('before 는 그 주를 빼고 주 중간 날짜도 월요일로 접는다', () async {
    final MemberReportHistoryPage page = await _local(db).memberReportHistory(
      clientId: _steady,
      before: DateTime(2026, 8, 13), // 8/10 주의 목요일
      limit: 1,
    );
    expect(page.items.single.weekStart, DateTime(2026, 8, 3));
  });

  test('쪽 크기를 줄이면 그만큼씩 나뉜다', () async {
    final MemberReportHistoryPage page = await _local(
      db,
    ).memberReportHistory(clientId: _steady, limit: 3);
    expect(page.items, hasLength(3));
    expect(page.hasMore, isTrue);
  });

  test('실행 중에 보낸 리포트가 그 주 데모 기록을 이긴다', () async {
    final DateTime thisWeek = weekStartOf(kMidWeekKst);
    int hour = 13;
    for (final String message in <String>['첫 전송', '다시 보낸 글\n· 목표']) {
      // 전송마다 시각이 달라야 채팅 메시지가 따로 남는다.
      useFixedKstDate(DateTime(2026, 8, 20, hour++));
      await _local(db).sendPdf(
        clientId: _steady,
        weekStart: thisWeek,
        bytes: _pdf,
        fileName: 'r.pdf',
        message: message,
      );
    }

    final MemberReportHistoryItem top = (await _local(
      db,
    ).memberReportHistory(clientId: _steady)).items.first;
    expect(top.weekStart, thisWeek);
    expect(top.feedbackPreview, '다시 보낸 글');
    expect(top.sendCount, 2);
  });

  test('다른 회원에게 보낸 것은 이 회원 이력에 서지 않는다', () async {
    await _local(db).sendPdf(
      clientId: 'seed-client-7',
      weekStart: weekStartOf(kMidWeekKst),
      bytes: _pdf,
      fileName: 'r.pdf',
      message: '임도현 첫 리포트',
    );
    final List<MemberReportHistoryItem> all = await readAll(_steady);
    expect(all.map((i) => i.feedbackPreview), isNot(contains('임도현 첫 리포트')));
  });

  test('데모 로스터가 아닌 회원은 실행 중 보낸 것만 선다', () async {
    expect(
      (await _local(db).memberReportHistory(clientId: 'user-42')).items,
      isEmpty,
    );

    await _local(db).sendPdf(
      clientId: 'user-42',
      weekStart: DateTime(2026, 8, 10),
      bytes: _pdf,
      fileName: 'r.pdf',
      message: '지난 주 리포트',
    );

    final MemberReportHistoryPage page = await _local(
      db,
    ).memberReportHistory(clientId: 'user-42');
    expect(page.items.single.weekStart, DateTime(2026, 8, 10));
    expect(page.items.single.feedbackPreview, '지난 주 리포트');
    expect(page.hasMore, isFalse);
  });

  test('이번 주에 붙은 신규 회원은 이번 주 전까지 이력이 없다', () async {
    // 임도현 — 이번 주에 붙었고 이번 주 리포트도 아직이다.
    expect(
      (await _local(db).memberReportHistory(clientId: 'seed-client-7')).items,
      isEmpty,
    );
  });
}
