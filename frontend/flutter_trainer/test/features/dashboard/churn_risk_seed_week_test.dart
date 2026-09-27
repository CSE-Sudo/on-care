import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/fixed_clock.dart';

// 데모 시드도 서버 `_daily_week` 와 같은 월→일 고정 창(미래 요일 0)을 준다.
// 요일마다 시드를 새로 깔고, 그 로스터에서 이탈 위험 규칙이 미래 0 을
// 끊김으로 읽지 않는지 확인한다(#2282).

const List<String> _dayNames = <String>['월', '화', '수', '목', '금', '토', '일'];

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<TrainerClient>> seededRoster(DateTime now) async {
    useFixedKstDate(now);
    await seedIfEmpty(db, clock: now);
    return DriftClientRepository(db).watchClients().first;
  }

  for (var i = 0; i < 7; i++) {
    final now = DateTime(2026, 8, 17 + i, 10);
    final day = _dayNames[i];
    final elapsed = i + 1;

    test('$day: 시드 식단·이행률 계열은 월→일 7칸이고 미래 요일은 0 이다', () async {
      final roster = await seededRoster(now);
      expect(roster, isNotEmpty);
      for (final c in roster) {
        for (final (name, series) in <(String, List<num>)>[
          ('칼로리', c.caloriesWeek),
          ('나트륨', c.sodiumWeek),
          ('이행률', c.weekCompletion),
        ]) {
          if (series.isEmpty) continue;
          expect(series, hasLength(7), reason: '${c.name} $name');
          expect(
            series.skip(elapsed),
            everyElement(0),
            reason: '${c.name} $name 미래 요일',
          );
        }
      }
    });

    test('$day: 시드 로스터의 식단 끊김은 지난 날의 모양과 일치한다', () async {
      final roster = await seededRoster(now);
      for (final c in roster) {
        final stopped = computeChurnSignals(
          c,
          recentSessions: const <ScheduleSession>[],
          unreadCount: 0,
          now: now,
        ).contains(ChurnSignal.dietStopped);

        if (elapsed <= dietStopRecentDays) {
          expect(stopped, isFalse, reason: '$day 에는 판단하지 않는다: ${c.name}');
          continue;
        }
        if (c.caloriesWeek.length != 7 || c.sodiumWeek.length != 7) {
          expect(stopped, isFalse, reason: c.name);
          continue;
        }
        final earlier = elapsed - dietStopRecentDays;
        bool anyIn(int from, int to) {
          for (var d = from; d < to; d++) {
            if (c.caloriesWeek[d] > 0 || c.sodiumWeek[d] > 0) return true;
          }
          return false;
        }

        expect(
          stopped,
          anyIn(0, earlier) && !anyIn(earlier, elapsed),
          reason: '$day ${c.name}',
        );
        // 최근 지난 날에 기록이 있는 회원은 어떤 요일에도 끊김이 아니다.
        if (anyIn(earlier, elapsed)) {
          expect(stopped, isFalse, reason: '$day ${c.name}');
        }
      }
    });
  }
}
