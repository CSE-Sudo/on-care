/// 데모의 노쇼 신호는 시드에 박힌 값이 아니라 일정 기록에서 센다. (#3304)
///
/// 실서버(`client_signals.py`)와 같은 규칙 — 최근 30일(오늘 포함) 노쇼·회원
/// 사정 취소가 2건 이상이면 신호다. 예전에는 시드 신호를 그대로 읽어, 스케줄에서
/// 노쇼·취소를 남겨도 대시보드 이탈 위험이 바뀌지 않았다.
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_core/clock.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

void main() {
  group('withDemoNoShowSignal', () {
    const ClientSignal gap = ClientSignal(ClientSignalKind.recordGap, days: 4);
    const ClientSignal seeded = ClientSignal(ClientSignalKind.noShow, count: 5);

    test('횟수를 모르면 저장된 신호 그대로다', () {
      expect(
        withDemoNoShowSignal(<ClientSignal>[seeded, gap], null),
        <ClientSignal>[seeded, gap],
      );
    });

    test('2건 미만이면 노쇼 신호를 뺀다', () {
      final List<ClientSignal> out = withDemoNoShowSignal(<ClientSignal>[
        seeded,
        gap,
      ], 1);
      expect(out.map((s) => s.kind), <ClientSignalKind>[
        ClientSignalKind.recordGap,
      ]);
    });

    test('2건 이상이면 센 횟수로 놓고, 급한 순서를 지킨다', () {
      final List<ClientSignal> out = withDemoNoShowSignal(<ClientSignal>[
        gap,
      ], 2);
      expect(out.map((s) => s.kind), <ClientSignalKind>[
        ClientSignalKind.recordGap,
        ClientSignalKind.noShow,
      ]);
      expect(out.last.count, 2);
    });
  });

  group('데모 로스터', () {
    late AppDatabase db;
    late DriftClientRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedIfEmpty(db, clock: nowKst());
      repo = DriftClientRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    ClientSignal? noShowOf(List<TrainerClient> roster, String name) {
      final TrainerClient client = roster.firstWhere((c) => c.name == name);
      for (final ClientSignal s in client.signals) {
        if (s.kind == ClientSignalKind.noShow) return s;
      }
      return null;
    }

    test('시드 일정만으로 배준혁은 노쇼 2건, 강서연은 1건이라 신호가 없다', () async {
      final List<TrainerClient> roster = await repo.watchClients().first;
      expect(noShowOf(roster, seedSameDayCancelClient)?.count, 2);
      expect(noShowOf(roster, '강서연'), isNull);
    });

    test('오늘 PT 를 회원 사정으로 취소하면 로스터가 다시 센다', () async {
      final String today = ymd(nowKst());
      await db
          .into(db.trainerScheduleEntries)
          .insert(
            TrainerScheduleEntriesCompanion.insert(
              id: 'test-cancel-today',
              date: today,
              time: '07:00',
              clientId: const Value('seed-client-6'),
              clientName: const Value('강서연'),
              type: const Value(SessionType.personalTraining),
              status: ScheduleStatus.cancelled,
              cancellationSource: const Value(CancellationSource.member),
            ),
          );

      final List<TrainerClient> roster = await repo.watchClients().first;
      expect(noShowOf(roster, '강서연')?.count, 2);
    });

    test('내일 PT 도 오늘 회원 사정으로 취소하면 바로 센다 (#3306)', () async {
      final DateTime now = nowKst();
      await db
          .into(db.trainerScheduleEntries)
          .insert(
            TrainerScheduleEntriesCompanion.insert(
              id: 'test-cancel-ahead',
              date: ymd(DateTime(now.year, now.month, now.day + 3)),
              time: '07:00',
              clientId: const Value('seed-client-6'),
              clientName: const Value('강서연'),
              type: const Value(SessionType.personalTraining),
              status: ScheduleStatus.cancelled,
              cancelledAt: Value(now),
              cancellationSource: const Value(CancellationSource.member),
            ),
          );

      final List<TrainerClient> roster = await repo.watchClients().first;
      expect(noShowOf(roster, '강서연')?.count, 2);
    });

    test('트레이너 사정 취소와 취소 시각 없는 앞으로의 일정은 세지 않는다', () async {
      final DateTime now = nowKst();
      await db.batch(
        (Batch b) => b.insertAll(
          db.trainerScheduleEntries,
          <TrainerScheduleEntriesCompanion>[
            TrainerScheduleEntriesCompanion.insert(
              id: 'test-trainer-cancel',
              date: ymd(now),
              time: '07:00',
              clientId: const Value('seed-client-6'),
              clientName: const Value('강서연'),
              type: const Value(SessionType.personalTraining),
              status: ScheduleStatus.cancelled,
              cancellationSource: const Value(CancellationSource.trainer),
            ),
            TrainerScheduleEntriesCompanion.insert(
              id: 'test-tomorrow-cancel',
              date: ymd(DateTime(now.year, now.month, now.day + 1)),
              time: '07:00',
              clientId: const Value('seed-client-6'),
              clientName: const Value('강서연'),
              type: const Value(SessionType.personalTraining),
              status: ScheduleStatus.cancelled,
              cancellationSource: const Value(CancellationSource.member),
            ),
          ],
        ),
      );

      final List<TrainerClient> roster = await repo.watchClients().first;
      expect(noShowOf(roster, '강서연'), isNull);
    });
  });
}
