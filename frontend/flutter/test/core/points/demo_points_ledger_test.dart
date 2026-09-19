/// 목업 포인트 원장 — 백엔드 `points_service` 와 같은 규칙. (#1786)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/points/points_award.dart';

void main() {
  late DateTime now;
  late DemoPointsLedger ledger;

  setUp(() {
    now = DateTime(2026, 9, 15, 9);
    // 시작 잔액을 못 박아 둔다 — 아래 규칙 테스트는 데모 시작 잔액과 상관없다.
    ledger = DemoPointsLedger(openingBalance: 1240, now: () => now);
  });

  test('데모 시작 잔액은 25,000P 다', () {
    expect(DemoPointsLedger().balance, kDemoOpeningPoints);
    expect(kDemoOpeningPoints, 25000);
  });

  test('식단은 +50P, 하루 3회까지', () {
    final List<int> awarded = <int>[
      for (int i = 0; i < 4; i++)
        ledger.award(PointsRule.dietEntry, 'diet-$i').awarded,
    ];
    expect(awarded, <int>[50, 50, 50, 0]);
    expect(ledger.balance, 1240 + 150);
  });

  test('운동 직접 추가는 +20P 하루 3회, 추천·배정 운동 완료는 +50P 하루 1회', () {
    expect(
      <int>[
        for (int i = 0; i < 4; i++)
          ledger.award(PointsRule.exerciseManual, 'ex-$i').awarded,
      ],
      <int>[20, 20, 20, 0],
    );
    expect(ledger.award(PointsRule.routineComplete, 'routine-1').awarded, 50);
    expect(ledger.award(PointsRule.routineComplete, 'routine-2').awarded, 0);
    // 규칙마다 한도를 따로 센다 — 운동 한도를 채워도 식단은 받는다.
    expect(ledger.award(PointsRule.dietEntry, 'diet-1').awarded, 50);
  });

  test('한도는 KST 날짜가 바뀌면 다시 센다', () {
    for (int i = 0; i < 3; i++) {
      ledger.award(PointsRule.dietEntry, 'diet-$i');
    }
    expect(ledger.award(PointsRule.dietEntry, 'diet-3').awarded, 0);

    now = DateTime(2026, 9, 16, 0, 5);
    expect(ledger.award(PointsRule.dietEntry, 'diet-4').awarded, 50);
  });

  test('같은 기록은 한 번만 쌓고, 다시 부르면 처음 받은 값을 돌려준다', () {
    final PointsAward first = ledger.award(PointsRule.dietEntry, 'diet-1');
    final PointsAward again = ledger.award(PointsRule.dietEntry, 'diet-1');

    expect(first.awarded, 50);
    expect(again.awarded, 50);
    expect(again.balance, first.balance);
    expect(ledger.awardedFor(PointsRule.dietEntry, 'diet-1').awarded, 50);
    expect(ledger.awardedFor(PointsRule.dietEntry, 'unknown').awarded, 0);
  });

  test('기록을 지우면 회수하고 그날 한도에서 빠진다', () {
    for (int i = 0; i < 3; i++) {
      ledger.award(PointsRule.dietEntry, 'diet-$i');
    }

    expect(ledger.revoke(PointsRule.dietEntry.sourceType, 'diet-0'), 50);
    expect(ledger.balance, 1240 + 100);
    // 두 번 지워도 한 번만 회수한다.
    expect(ledger.revoke(PointsRule.dietEntry.sourceType, 'diet-0'), 0);
    expect(ledger.awardedFor(PointsRule.dietEntry, 'diet-0').awarded, 0);
    // 다시 올린 끼니는 새 기록이다.
    expect(ledger.award(PointsRule.dietEntry, 'diet-3').awarded, 50);
    expect(ledger.award(PointsRule.dietEntry, 'diet-4').awarded, 0);
  });

  test('적립을 받지 않은 기록을 지우면 아무것도 회수하지 않는다', () {
    expect(ledger.revoke(PointsRule.dietEntry.sourceType, 'nothing'), 0);
    expect(ledger.balance, 1240);
  });

  test('회수해도 잔액은 0 아래로 내려가지 않는다', () {
    // 적립보다 잔액이 적은 상황은 사용처가 생기면 온다(그사이 포인트를 씀).
    // 시작 잔액을 음수로 두어 적립 뒤 잔액(10)이 적립액(50)보다 적게 만든다.
    final DemoPointsLedger low = DemoPointsLedger(
      openingBalance: -40,
      now: () => now,
    );
    low.award(PointsRule.dietEntry, 'diet-1');
    expect(low.balance, 10);
    expect(low.revoke(PointsRule.dietEntry.sourceType, 'diet-1'), 10);
    expect(low.balance, 0);
  });

  test('응답의 points 를 읽는다 — 없거나 모양이 다르면 null', () {
    final PointsAward? award = PointsAward.fromJson(<String, Object?>{
      'awarded': 20,
      'balance': 1260,
    });
    expect(award?.awarded, 20);
    expect(award?.balance, 1260);
    expect(award?.hasReward, isTrue);
    expect(
      PointsAward.fromJson(<String, Object?>{
        'awarded': 0,
        'balance': 1,
      })?.hasReward,
      isFalse,
    );
    expect(PointsAward.fromJson(null), isNull);
    expect(PointsAward.fromJson(<String, Object?>{'awarded': 'x'}), isNull);
  });
}
