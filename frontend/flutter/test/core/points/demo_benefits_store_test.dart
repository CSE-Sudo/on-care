/// 데모 혜택 장부의 시드와 새로고침 유지(#2664).
library;

import 'dart:io';

import 'package:demo_fixture/demo_fixture.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_benefits_seed.dart';
import 'package:oncare/core/points/demo_benefits_store.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_emote_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/core/points/demo_weekly_challenge.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/core/storage/seed_data.dart';

/// 수요일 오후 — 지난주 월요일은 9월 21일, 2주 전 월요일은 9월 14일이다.
final DateTime _now = DateTime(2026, 9, 30, 15);

DateTime _clock() => _now;

/// 시드를 되살린 장부 한 벌. 앱의 프로바이더와 같이 원장 하나를 함께 쓴다.
class _Books {
  _Books(Map<String, Map<String, Object?>> seed) {
    ledger.restore(seed['points']!);
    coupons.restore(seed['coupons']!);
    challenges.restore(seed['challenges']!);
    shields.restore(seed['shields']!);
    emotes.restore(seed['emotes']!);
  }

  final DemoPointsLedger ledger = DemoPointsLedger(now: _clock);
  late final DemoStreakShieldBook shields = DemoStreakShieldBook(
    ledger: ledger,
    now: _clock,
  );
  late final DemoCouponBook coupons = DemoCouponBook(
    ledger: ledger,
    now: _clock,
    shields: shields,
  );
  late final DemoWeeklyChallenge challenges = DemoWeeklyChallenge(
    ledger: ledger,
    now: _clock,
  );
  late final DemoEmoteBook emotes = DemoEmoteBook(ledger: ledger, now: _clock);
}

/// 저장소는 쓰기를 기다리지 않는다 — 다음 읽기 전에 한 박자 쉰다.
Future<void> _settleWrites() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// 포인트 내역 전 페이지의 사유.
Set<String> _historyReasons(DemoPointsLedger ledger) {
  final Set<String> reasons = <String>{};
  String? before;
  do {
    final Map<String, Object?> page = ledger.historyJson(before: before);
    for (final Object? row in page['items']! as List<Object?>) {
      reasons.add((row! as Map<String, Object?>)['reason']! as String);
    }
    before = page['next_before'] as String?;
  } while (before != null);
  return reasons;
}

void main() {
  late Map<String, Map<String, Object?>> seed;

  setUp(() async {
    seed = await buildDemoBenefitsSeed(_now);
  });

  group('시드', () {
    test('포인트 내역이 적립과 사용을 함께 싣고, 잔액은 시작 잔액이다', () {
      final _Books books = _Books(seed);

      expect(books.ledger.balance, kDemoOpeningPoints);
      expect(
        _historyReasons(books.ledger),
        containsAll(<String>[
          'diet_entry',
          'exercise_manual',
          'routine_complete',
          'coupon_locker_month',
          'streak_shield',
          'challenge_stake',
          'weekly_report',
          'emote_unlock',
        ]),
      );
      // 오늘 적립은 시드하지 않는다 — 데모에서 기록하면 하루 한도가 그대로 남아 있다.
      final Map<String, Object?> latest = books.ledger.historyJson();
      expect(
        (latest['items']! as List<Object?>).any(
          (Object? row) =>
              (row! as Map<String, Object?>)['kst_date'] == '2026-09-30',
        ),
        isFalse,
      );
    });

    test('쿠폰은 쓸 수 있는 락커 한 장과 지난달에 쓴 락커 한 장이다', () {
      final List<Map<String, Object?>> coupons = _Books(
        seed,
      ).coupons.couponsJson();

      expect(coupons.map((Map<String, Object?> c) => c['status']), <String>[
        'issued',
        'used',
      ]);
      expect(
        coupons.map((Map<String, Object?> c) => c['item']).toSet(),
        <String>{kDemoLockerMonth.id},
      );
      expect(coupons.first['issued_on'], '2026-09-27');
    });

    test('PT 재등록은 비워 둬 데모에서 바로 교환해 볼 수 있다', () {
      final _Books books = _Books(seed);

      expect(books.coupons.exchange(kDemoPtRenewal.id).statusCode, 201);
    });

    test('받은 주간 리포트는 2주 전 한 주이고, 지난주는 아직 받지 않았다', () {
      final _Books books = _Books(seed);
      final Map<String, Object?> list = books.coupons.reports.listJson();

      expect(
        (list['reports']! as List<Object?>).map(
          (Object? r) => (r! as Map<String, Object?>)['week_start'],
        ),
        <String>['2026-09-14'],
      );
      expect(list['next_week_start'], '2026-09-21');
      expect(books.coupons.reports.targetOwned, isFalse);
    });

    test('보호권 두 장과 이모티콘 둘을 들고 있다', () {
      final _Books books = _Books(seed);

      expect(books.shields.held, 2);
      expect(books.emotes.unlocked.keys.toSet(), <String>{
        'oni_owoon',
        'oni_thanks',
      });
    });

    test('지난주 챌린지는 첫 조회에서 판정돼 결과 알림과 보상이 생긴다', () async {
      final _Books books = _Books(seed);
      final List<Map<String, Object?>> before = await books.challenges
          .historyJson(daysOf: (_) async => <DateTime>{});
      expect(before.single['status'], 'active');
      expect(before.single['week_start'], '2026-09-21');

      final List<DemoChallengeNotice> notices = await books.challenges
          .settleDue(
            (_) async => <DateTime>{
              DateTime(2026, 9, 21),
              DateTime(2026, 9, 23),
              DateTime(2026, 9, 26),
            },
          );

      expect(notices, hasLength(1));
      expect(books.ledger.balance, kDemoOpeningPoints + 200);
    });

    test('되살린 쿠폰도 헬스장 연결이 끊기면 포인트를 돌려준다', () {
      final _Books books = _Books(seed);

      books.coupons.endGymLink();

      expect(books.ledger.balance, kDemoOpeningPoints + kDemoLockerMonth.cost);
      expect(books.coupons.couponsJson().first['status'], 'cancelled');
    });
  });

  group('저장소', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('저장분이 없으면 시드를 깔아 쓰고, 바뀐 장부는 다시 열어도 남는다', () async {
      final DemoBenefitsStore first = await DemoBenefitsStore.open(
        db,
        seed: () async => seed,
      );
      await _settleWrites();
      expect(await db.readValue(kDemoBenefitsKey), isNotNull);

      final DemoPointsLedger ledger = DemoPointsLedger(now: _clock);
      first.attach('points', ledger);
      expect(ledger.balance, kDemoOpeningPoints);
      expect(ledger.spend('ai-chat-demo-1', 50, reason: 'ai_chat'), isTrue);
      await _settleWrites();

      // 새로고침 — 저장분이 있으니 시드를 다시 부르지 않는다.
      final DemoBenefitsStore reopened = await DemoBenefitsStore.open(
        db,
        seed: () async => fail('저장분이 있으면 시드하지 않는다'),
      );
      final DemoPointsLedger restored = DemoPointsLedger(now: _clock);
      reopened.attach('points', restored);

      expect(restored.balance, kDemoOpeningPoints - 50);
      expect(restored.historyJson()['items'], ledger.historyJson()['items']);
    });

    test('메모리 저장소는 아무것도 되살리지 않는다', () {
      final DemoPointsLedger ledger = DemoPointsLedger(now: _clock);
      DemoBenefitsStore.memory().attach('points', ledger);

      expect(ledger.historyJson()['items'], isEmpty);
    });

    test('시드 플래그의 첫 부팅은 혜택 장부를 지우고, 날짜만 바뀐 부팅은 남긴다', () async {
      final DemoFixture fixture = DemoFixture.parse(
        File(
          '../../shared/demo_fixture/assets/kim_minsu.json',
        ).readAsStringSync(),
      );
      await db.putValue(kDemoBenefitsKey, '{}');
      await seedIfEmpty(db, fixture: fixture);
      expect(await db.readValue(kDemoBenefitsKey), isNull);

      await db.putValue(kDemoBenefitsKey, '{}');
      await db.putValue('seeded_v23', '2020-01-01');
      await seedIfEmpty(db, fixture: fixture);
      expect(await db.readValue(kDemoBenefitsKey), '{}');

      // v22 를 거친 설치가 v23(#2694)으로 넘어올 때도 장부는 남는다.
      await db.deleteValue('seeded_v23');
      await db.putValue('seeded_v22', '2020-01-01');
      await seedIfEmpty(db, fixture: fixture);
      expect(await db.readValue(kDemoBenefitsKey), '{}');
      expect(await db.readValue('seeded_v22'), isNull);

      // v21 을 거친 설치가 넘어올 때도 장부는 남는다(#2662).
      await db.deleteValue('seeded_v23');
      await db.putValue('seeded_v21', '2020-01-01');
      await seedIfEmpty(db, fixture: fixture);
      expect(await db.readValue(kDemoBenefitsKey), '{}');
      expect(await db.readValue('seeded_v21'), isNull);

      // v20 을 거친 설치가 넘어올 때도 장부는 남는다(#2660).
      await db.deleteValue('seeded_v23');
      await db.putValue('seeded_v20', '2020-01-01');
      await seedIfEmpty(db, fixture: fixture);
      expect(await db.readValue(kDemoBenefitsKey), '{}');
      expect(await db.readValue('seeded_v20'), isNull);
    });
  });
}
