/// 데모의 채팅 이모티콘 — 서버와 같이 하나씩 사서 7일 동안 쓴다. (#2153)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/points/demo_coupon_book.dart';
import 'package:oncare/core/points/demo_emote_book.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/features/member_coach/domain/entities/emote_state.dart';

void main() {
  DateTime now = DateTime(2026, 9, 22, 10);
  late DemoPointsLedger ledger;
  late DemoEmoteBook book;

  setUp(() {
    now = DateTime(2026, 9, 22, 10);
    ledger = DemoPointsLedger(openingBalance: 120, now: () => now);
    book = DemoEmoteBook(ledger: ledger, now: () => now);
  });

  test('하나를 사면 그 이모티콘만 7일 동안 열린다', () {
    final DemoCouponResult r = book.unlock('oni_owoon');

    expect(r.statusCode, 200);
    final EmoteState state = EmoteState.fromJson(
      r.body! as Map<String, Object?>,
    );
    expect(state.unlocked.keys, <String>['oni_owoon']);
    expect(state.unlocked['oni_owoon'], const Duration(days: 7));
    expect(state.balance, 70);
  });

  test('쓰는 중에는 다시 사지 못하고, 끝나면 다시 산다', () {
    book.unlock('oni_owoon');
    expect(book.unlock('oni_owoon').statusCode, 409);

    now = now.add(const Duration(days: 7, seconds: 1));
    expect(book.unlocked, isEmpty);
    expect(book.unlock('oni_owoon').statusCode, 200);
    expect(ledger.balance, 20);
  });

  test('모르는 이모티콘은 404, 포인트가 모자라면 400', () {
    expect(book.unlock('made_up').statusCode, 404);
    book.unlock('oni_owoon');
    book.unlock('oni_gains');
    expect(book.unlock('dog_love').statusCode, 400);
    expect(ledger.balance, 20);
  });
}
