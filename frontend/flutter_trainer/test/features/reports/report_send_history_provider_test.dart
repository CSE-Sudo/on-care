/// 리포트 전송 이력 — 저장소와 provider 층. (#2288)
///
/// 예전 전송 기록은 앱 메모리의 `StateNotifier` 하나라, 새로고침하면 보낸 회원이
/// 미전송으로 돌아가 같은 리포트를 다시 보낼 수 있었다. 이 파일이 지키는 것:
///  * 데모 저장소는 로컬 채팅의 리포트 전송 표시에서 이력을 읽는다 — 같은 DB
///    위에 저장소를 새로 만들어도(=새로고침) 보낸 회원이 남는다.
///  * 시드 대화의 리포트 안내는 이력으로 세지 않는다(데모 명단은 따로 있다).
///  * [reportSendHistoryProvider] 는 저장소의 기록을 `회원|주` 열쇠로 모은다.
///  * [mergeSendLogs] 는 서버 기록 위에 방금 보낸 것을 얹되, 더 늦은 것을 남긴다.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show StringExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/report_summary.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/chat_repository.dart';

import '../../helpers/fixed_clock.dart';

LocalReportRepository _local(AppDatabase db) => LocalReportRepository(
  DriftScheduleRepository(db),
  DriftChatRepository(db),
  db,
);

final Uint8List _pdf = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);

ReportSendRecord _record(
  String clientId, {
  DateTime? sentAt,
  String message = '리포트',
  bool read = true,
  int sendCount = 1,
  DateTime? week,
}) => ReportSendRecord(
  clientId: clientId,
  weekStart: week ?? DateTime(2026, 8, 17),
  sentAt: sentAt ?? DateTime(2026, 8, 18, 9),
  message: message,
  read: read,
  sendCount: sendCount,
);

/// 기록을 정해 둔 저장소. 몇 번 물었는지 센다.
class _FakeHistoryRepository implements ReportRepository {
  _FakeHistoryRepository(this.records, {this.fail = false});

  final List<ReportSendRecord> records;
  final bool fail;
  final List<DateTime> asked = <DateTime>[];

  @override
  Future<List<ReportSendRecord>> sentReports({
    required DateTime weekStart,
  }) async {
    asked.add(weekStart);
    if (fail) throw StateError('history failed');
    return records;
  }

  @override
  Stream<WeeklyReport> watch({
    required TrainerClient client,
    required DateTime weekStart,
  }) => const Stream<WeeklyReport>.empty();

  @override
  Future<ReportSummary> summary({
    required TrainerClient client,
    required DateTime weekStart,
    required AppLocalizations l,
  }) => throw UnimplementedError();

  @override
  Future<void> send({
    required String clientId,
    required DateTime weekStart,
    required String message,
  }) async {}

  @override
  Future<void> sendPdf({
    required String clientId,
    required DateTime weekStart,
    required Uint8List bytes,
    required String fileName,
    required String message,
  }) async {}

  @override
  Future<ReportFeedbackDraft> feedbackDraft({
    required TrainerClient client,
    required DateTime weekStart,
  }) async => const ReportFeedbackDraft.none();

  @override
  Future<ReportFeedbackDraft> saveFeedbackDraft({
    required String clientId,
    required DateTime weekStart,
    required String body,
  }) async => ReportFeedbackDraft(body: body, saved: true);
}

void main() {
  group('LocalReportRepository.sentReports', () {
    late AppDatabase db;
    final DateTime week = DateTime(2026, 8, 17);

    setUp(() {
      useFixedKstDate(DateTime(2026, 8, 19, 14));
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() => db.close());

    test('보낸 적이 없으면 빈 목록이다', () async {
      expect(await _local(db).sentReports(weekStart: week), isEmpty);
    });

    test('PDF 로 보낸 리포트가 그 주 이력에 선다', () async {
      await _local(db).sendPdf(
        clientId: 'c1',
        weekStart: week,
        bytes: _pdf,
        fileName: 'weekly.pdf',
        message: '이번 주 잘했어요',
      );

      final ReportSendRecord r = (await _local(
        db,
      ).sentReports(weekStart: week)).single;
      expect(r.clientId, 'c1');
      expect(r.weekStart, week);
      expect(r.message, '이번 주 잘했어요');
      expect(r.sendCount, 1);
      expect(r.sentAt, DateTime(2026, 8, 19, 14));
    });

    test('저장소를 새로 만들어도(새로고침) 보낸 기록이 남는다', () async {
      await _local(db).sendPdf(
        clientId: 'c1',
        weekStart: week,
        bytes: _pdf,
        fileName: 'weekly.pdf',
        message: '보냄',
      );

      // 같은 DB 위의 새 저장소 — 앱을 다시 연 것과 같다.
      final LocalReportRepository reopened = _local(db);
      expect(
        (await reopened.sentReports(weekStart: week)).map((r) => r.clientId),
        <String>['c1'],
      );
    });

    test('주 중간 날짜로 물어도 그 주 월요일 기록을 찾는다', () async {
      await _local(db).sendPdf(
        clientId: 'c1',
        weekStart: week,
        bytes: _pdf,
        fileName: 'weekly.pdf',
        message: '보냄',
      );

      expect(
        await _local(db).sentReports(weekStart: DateTime(2026, 8, 20)),
        hasLength(1),
      );
    });

    test('다시 보내면 가장 최근 글 하나로 접고 횟수를 센다', () async {
      await _local(db).sendPdf(
        clientId: 'c1',
        weekStart: week,
        bytes: _pdf,
        fileName: 'weekly.pdf',
        message: '처음',
      );
      useFixedKstDate(DateTime(2026, 8, 19, 18));
      await _local(db).sendPdf(
        clientId: 'c1',
        weekStart: week,
        bytes: _pdf,
        fileName: 'weekly.pdf',
        message: '다시',
      );

      final ReportSendRecord r = (await _local(
        db,
      ).sentReports(weekStart: week)).single;
      expect(r.message, '다시');
      expect(r.sendCount, 2);
      expect(r.sentAt, DateTime(2026, 8, 19, 18));
    });

    test('다른 주·일반 대화·표시 없는 본문은 이력이 아니다', () async {
      await _local(db).sendPdf(
        clientId: 'c1',
        weekStart: DateTime(2026, 8, 10),
        bytes: _pdf,
        fileName: 'weekly.pdf',
        message: '지난 주 리포트',
      );
      await DriftChatRepository(
        db,
      ).sendTrainerMessage(clientId: 'c2', text: '일반 대화');
      // 본문만 보내는 길(send)은 채팅에 리포트 표시를 남기지 않는다.
      await _local(db).send(clientId: 'c3', weekStart: week, message: '본문만');

      expect(await _local(db).sentReports(weekStart: week), isEmpty);
    });

    test('회원마다 한 줄씩 선다', () async {
      for (final String id in <String>['c1', 'c2']) {
        await _local(db).sendPdf(
          clientId: id,
          weekStart: week,
          bytes: _pdf,
          fileName: 'weekly.pdf',
          message: '$id 리포트',
        );
      }

      final List<ReportSendRecord> records = await _local(
        db,
      ).sentReports(weekStart: week);
      expect(records.map((r) => r.clientId).toSet(), <String>{'c1', 'c2'});
    });

    test('시드 대화의 리포트 안내는 이력으로 세지 않는다', () async {
      await seedIfEmpty(db, clock: DateTime(2026, 8, 19, 14));
      final List<AppKeyValue> seeded = await (db.select(
        db.appKeyValues,
      )..where((t) => t.key.like('report_msg_seed-%'))).get();
      expect(seeded, isNotEmpty, reason: '시드에 리포트 안내가 있어야 이 테스트가 뜻이 있다');

      for (final AppKeyValue marker in seeded) {
        final List<ReportSendRecord> records = await _local(
          db,
        ).sentReports(weekStart: DateTime.parse(marker.value));
        expect(records, isEmpty);
      }
    });
  });

  group('reportSendHistoryProvider', () {
    test('저장소의 기록을 회원|주 열쇠로 모은다', () async {
      final _FakeHistoryRepository repo = _FakeHistoryRepository(
        <ReportSendRecord>[_record('a'), _record('b')],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[reportRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final Map<String, ReportSendRecord> history = await container.read(
        reportSendHistoryProvider(DateTime(2026, 8, 17)).future,
      );

      expect(history.keys.toSet(), <String>{'a|2026-08-17', 'b|2026-08-17'});
      expect(repo.asked, <DateTime>[DateTime(2026, 8, 17)]);
    });

    test('주 중간 날짜로 열어도 월요일로 묻는다', () async {
      final _FakeHistoryRepository repo = _FakeHistoryRepository(
        const <ReportSendRecord>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[reportRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(
        reportSendHistoryProvider(DateTime(2026, 8, 20)).future,
      );

      expect(repo.asked, <DateTime>[DateTime(2026, 8, 17)]);
    });

    test('새 컨테이너(새로고침)에서도 서버 기록으로 다시 선다', () async {
      final _FakeHistoryRepository server = _FakeHistoryRepository(
        <ReportSendRecord>[_record('a', message: '보낸 글')],
      );
      for (var i = 0; i < 2; i++) {
        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[
            reportRepositoryProvider.overrideWithValue(server),
          ],
        );
        final Map<String, ReportSendRecord> history = await container.read(
          reportSendHistoryProvider(DateTime(2026, 8, 17)).future,
        );
        // 세션 기록은 새 컨테이너마다 비어 있다 — 그래도 이력은 남는다.
        expect(container.read(reportSendLogProvider), isEmpty);
        expect(
          sendRecordFor(history, 'a', DateTime(2026, 8, 17))?.message,
          '보낸 글',
        );
        container.dispose();
      }
    });

    test('무효화하면 다시 묻는다', () async {
      final _FakeHistoryRepository repo = _FakeHistoryRepository(
        const <ReportSendRecord>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[reportRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final DateTime week = DateTime(2026, 8, 17);
      final ProviderSubscription<AsyncValue<Map<String, ReportSendRecord>>>
      sub = container.listen(reportSendHistoryProvider(week), (_, _) {});
      addTearDown(sub.close);
      await container.read(reportSendHistoryProvider(week).future);

      container.invalidate(reportSendHistoryProvider(week));
      await container.read(reportSendHistoryProvider(week).future);

      expect(repo.asked, hasLength(2));
    });

    test('저장소가 실패하면 오류 상태다 — 빈 이력으로 삼키지 않는다', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          reportRepositoryProvider.overrideWithValue(
            _FakeHistoryRepository(const <ReportSendRecord>[], fail: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final DateTime week = DateTime(2026, 8, 17);
      final ProviderSubscription<AsyncValue<Map<String, ReportSendRecord>>>
      sub = container.listen(reportSendHistoryProvider(week), (_, _) {});
      addTearDown(sub.close);

      await expectLater(
        container.read(reportSendHistoryProvider(week).future),
        throwsA(isA<StateError>()),
      );
      expect(container.read(reportSendHistoryProvider(week)).hasError, isTrue);
    });

    test('계정이 바뀌면 새 계정의 저장소로 다시 묻는다', () async {
      final _FakeHistoryRepository a = _FakeHistoryRepository(
        <ReportSendRecord>[_record('a')],
      );
      final _FakeHistoryRepository b = _FakeHistoryRepository(
        const <ReportSendRecord>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          reportRepositoryProvider.overrideWith(
            (ref) => ref.watch(accountScopeProvider) == 0 ? a : b,
          ),
        ],
      );
      addTearDown(container.dispose);
      final DateTime week = DateTime(2026, 8, 17);
      final ProviderSubscription<AsyncValue<Map<String, ReportSendRecord>>>
      sub = container.listen(reportSendHistoryProvider(week), (_, _) {});
      addTearDown(sub.close);
      expect(
        await container.read(reportSendHistoryProvider(week).future),
        hasLength(1),
      );

      container.read(accountScopeProvider.notifier).state++;

      expect(
        await container.read(reportSendHistoryProvider(week).future),
        isEmpty,
      );
    });

    test('데모 저장소 위에서도 보낸 것이 새 컨테이너에 남는다', () async {
      useFixedKstDate(DateTime(2026, 8, 19, 14));
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final DateTime week = DateTime(2026, 8, 17);

      final ProviderContainer first = ProviderContainer(
        overrides: <Override>[
          reportRepositoryProvider.overrideWithValue(_local(db)),
        ],
      );
      await first
          .read(reportRepositoryProvider)
          .sendPdf(
            clientId: 'c1',
            weekStart: week,
            bytes: _pdf,
            fileName: 'weekly.pdf',
            message: '보냄',
          );
      first.dispose();

      final ProviderContainer second = ProviderContainer(
        overrides: <Override>[
          reportRepositoryProvider.overrideWithValue(_local(db)),
        ],
      );
      addTearDown(second.dispose);
      final Map<String, ReportSendRecord> history = await second.read(
        reportSendHistoryProvider(week).future,
      );

      expect(sentClientsIn(history, week), <String>{'c1'});
    });
  });

  group('mergeSendLogs', () {
    test('한쪽에만 있는 기록은 그대로 모인다', () {
      final Map<String, ReportSendRecord> merged = mergeSendLogs(
        <String, ReportSendRecord>{'a|2026-08-17': _record('a')},
        <String, ReportSendRecord>{'b|2026-08-17': _record('b')},
      );

      expect(merged.keys.toSet(), <String>{'a|2026-08-17', 'b|2026-08-17'});
    });

    test('방금 다시 보낸 글이 서버의 옛 글보다 앞선다', () {
      final Map<String, ReportSendRecord> merged = mergeSendLogs(
        <String, ReportSendRecord>{
          'a|2026-08-17': _record(
            'a',
            message: '옛 글',
            sentAt: DateTime(2026, 8, 18, 9),
            sendCount: 2,
          ),
        },
        <String, ReportSendRecord>{
          'a|2026-08-17': _record(
            'a',
            message: '새 글',
            sentAt: DateTime(2026, 8, 19, 9),
          ),
        },
      );

      final ReportSendRecord r = merged['a|2026-08-17']!;
      expect(r.message, '새 글');
      expect(r.sentAt, DateTime(2026, 8, 19, 9));
      // 횟수는 줄지 않는다.
      expect(r.sendCount, 2);
    });

    test('서버 기록이 더 늦으면 서버 것이 남는다', () {
      final ReportSendRecord server = _record(
        'a',
        message: '다른 탭에서 보낸 글',
        sentAt: DateTime(2026, 8, 19, 20),
        read: false,
      );
      final Map<String, ReportSendRecord> merged = mergeSendLogs(
        <String, ReportSendRecord>{'a|2026-08-17': server},
        <String, ReportSendRecord>{
          'a|2026-08-17': _record('a', sentAt: DateTime(2026, 8, 19, 9)),
        },
      );

      expect(merged['a|2026-08-17'], same(server));
    });

    test('둘 다 비어 있으면 빈 기록이다', () {
      expect(
        mergeSendLogs(
          const <String, ReportSendRecord>{},
          const <String, ReportSendRecord>{},
        ),
        isEmpty,
      );
    });

    test('원본을 고치지 않는다', () {
      final Map<String, ReportSendRecord> server = <String, ReportSendRecord>{
        'a|2026-08-17': _record('a'),
      };
      mergeSendLogs(server, <String, ReportSendRecord>{
        'b|2026-08-17': _record('b'),
      });

      expect(server.keys, <String>['a|2026-08-17']);
    });
  });

  group('sendLogKey', () {
    test('주의 어느 날이든 그 주 월요일 열쇠다', () {
      expect(sendLogKey('a', DateTime(2026, 8, 17)), 'a|2026-08-17');
      expect(sendLogKey('a', DateTime(2026, 8, 23, 23, 59)), 'a|2026-08-17');
      expect(
        sendLogKey('a', DateTime(2026, 8, 24)),
        'a|${ymd(DateTime(2026, 8, 24))}',
      );
    });

    test('세션 기록도 같은 열쇠로 적힌다', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(reportSendLogProvider.notifier)
          .record(
            clientId: 'a',
            weekStart: DateTime(2026, 8, 19),
            message: '보냄',
          );

      expect(container.read(reportSendLogProvider).keys, <String>[
        'a|2026-08-17',
      ]);
    });
  });
}
