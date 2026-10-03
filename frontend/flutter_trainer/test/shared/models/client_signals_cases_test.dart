import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_signal_rules.dart';
import '../../helpers/shared_rule_vectors.dart';

/// PT 관리 신호가 서버 판정과 같은 규칙인가(#2906).
///
/// 원본은 서버 스크립트(`backend/scripts/gen_client_signals_cases.py`)가 만든
/// `shared/oncare_rules/vectors/client_signals_cases.json` 이다. 먼저 테스트의
/// 판정([decideClientSignals])이 서버 사례와 같은지 보고, 그 판정으로 데모
/// 시드(`seed_clients.dart`)의 신호가 **규칙에서 나올 수 있는 값**인지 본다 —
/// 서버 규칙(문턱·순서·기록 끊김이 가리는 신호·단백질 중심 목표)이 바뀌면 옛
/// 규칙으로 적힌 시드 배지가 여기서 깨진다.
void main() {
  final Map<String, Object?> file = loadSharedRuleVectors(
    'client_signals_cases',
  );
  final Map<String, Object?> thresholds =
      file['thresholds']! as Map<String, Object?>;

  test('앱의 신호 순서가 서버의 급한 순과 같다', () {
    expect(<String>[
      for (final ClientSignalKind k in ClientSignalKind.values)
        if (k != ClientSignalKind.unanswered) k.wire,
    ], thresholds['signal_order']);
  });

  group('판정 — 서버 사례와 같다', () {
    for (final Map<String, Object?> c in vectorRows(file, 'cases')) {
      test(c['name']! as String, () {
        final List<ClientSignal> got = decideClientSignals(
          ClientSignalFacts.fromJson(c['facts']! as Map<String, Object?>),
          thresholds,
        );
        expect(got.map((ClientSignal s) => s.toJson()).toList(), c['expected']);
      });
    }
  });

  group('데모 시드의 신호가 규칙에서 나올 수 있는 값이다', () {
    late List<TrainerClient> clients;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
      // 목요일 — 운동 목표를 보는 요일이다.
      await seedIfEmpty(db, clock: DateTime(2026, 9, 24, 21));
      clients = await DriftClientRepository(db).watchClients().first;
      await db.close();
    });

    test('시드가 회원을 싣는다', () => expect(clients, isNotEmpty));

    test('휴면 회원은 서버처럼 신호가 없다', () {
      for (final TrainerClient c in clients.where((c) => !c.active)) {
        expect(c.signals, isEmpty, reason: c.name);
      }
    });

    test('신호마다 그 값을 낳는 사실로 다시 판정하면 같은 신호다', () {
      const int target = 2000;
      const double proteinTarget = 100;
      for (final TrainerClient c in clients.where((c) => c.active)) {
        ClientSignal? of(ClientSignalKind kind) {
          for (final ClientSignal s in c.signals) {
            if (s.kind == kind) return s;
          }
          return null;
        }

        final ClientSignal? calorie = of(ClientSignalKind.calorieOff);
        final ClientSignal? protein = of(ClientSignalKind.proteinLow);
        final int kcal = calorie == null
            ? target
            : target +
                  (calorie.over! ? 1 : -1) * target * calorie.percent! ~/ 100;
        final double grams = protein == null
            ? proteinTarget
            : proteinTarget * protein.percent! / 100;
        final ClientSignalFacts facts = ClientSignalFacts(
          discomfort: of(ClientSignalKind.discomfort) != null,
          linkAgeDays: 30,
          recordGapDays: of(ClientSignalKind.recordGap)?.days ?? 0,
          noShowCount: of(ClientSignalKind.noShow)?.count ?? 0,
          routineMissedDays: of(ClientSignalKind.routineMissed)?.days ?? 0,
          weekday: 3,
          exerciseGoalPercent:
              of(ClientSignalKind.exerciseGoalLow)?.percent ?? 100,
          recentDiet: <(int, double)>[(kcal, grams), (kcal, grams)],
          calorieTarget: target,
          proteinTarget: proteinTarget,
          // 단백질 부족은 근력 향상·체중 감량 회원에게만 나온다 — 시드의 목표로 본다.
          focus: c.goal.split('·').map((String g) => g.trim()).toSet(),
        );
        expect(
          decideClientSignals(
            facts,
            thresholds,
          ).map((ClientSignal s) => s.toJson()).toList(),
          c.signals.map((ClientSignal s) => s.toJson()).toList(),
          reason: c.name,
        );
      }
    });
  });
}
