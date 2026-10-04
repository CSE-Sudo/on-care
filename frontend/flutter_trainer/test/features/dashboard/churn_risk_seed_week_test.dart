import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/core/storage/seed_data.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/fixed_clock.dart';

// 데모 시드도 서버 `_daily_week` 와 같은 월→일 고정 창(미래 요일 0)을 준다.
// 요일마다 시드를 새로 깔고 그 모양을 확인한다(#2282). 예전에는 이 계열로
// 앱이 이탈 위험(식단 끊김)을 셌지만, 이제 이탈 위험은 서버 PT 관리 신호로
// 판정한다(#2364) — 계열 모양은 리포트·차트가 여전히 기댄다.

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

    test('$day: 시드 식단·이행률 계열은 월→일 7칸이고 미래 요일은 비어 있다', () async {
      final roster = await seededRoster(now);
      expect(roster, isNotEmpty);
      for (final c in roster) {
        for (final (name, series) in <(String, List<num>)>[
          ('칼로리', c.caloriesWeek),
          ('나트륨', c.sodiumWeek),
        ]) {
          if (series.isEmpty) continue;
          expect(series, hasLength(7), reason: '${c.name} $name');
          expect(
            series.skip(elapsed),
            everyElement(0),
            reason: '${c.name} $name 미래 요일',
          );
        }
        // 이행률은 아직 오지 않은 날이 null 이다(#2513) — 0 은 "걸렸는데 안 함".
        if (c.weekCompletion.isNotEmpty) {
          expect(c.weekCompletion, hasLength(7), reason: '${c.name} 이행률');
          expect(
            c.weekCompletion.skip(elapsed),
            everyElement(isNull),
            reason: '${c.name} 이행률 미래 요일',
          );
        }
      }
    });
  }
}
