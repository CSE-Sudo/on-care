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

  test('같은 키로 다시 사면 다시 쓰지 않고 200 과 지금 상태를 준다 (#2845)', () {
    expect(book.unlock('oni_owoon', clientRequestId: 'k1').statusCode, 200);
    final DemoCouponResult retry = book.unlock(
      'oni_owoon',
      clientRequestId: 'k1',
    );

    expect(retry.statusCode, 200);
    expect(ledger.balance, 70);
    // 다른 키는 서버처럼 409 와 이유 코드다.
    final DemoCouponResult other = book.unlock(
      'oni_owoon',
      clientRequestId: 'k2',
    );
    expect(other.statusCode, 409);
    expect(
      ((other.body! as Map<String, Object?>)['detail']!
          as Map<String, Object?>)['code'],
      'already_unlocked',
    );
  });

  test('구매 키는 저장·복원 뒤에도 기억한다', () {
    book.unlock('oni_owoon', clientRequestId: 'k1');
    final DemoEmoteBook restored = DemoEmoteBook(ledger: ledger, now: () => now)
      ..restore(book.toJson());

    expect(restored.unlock('oni_owoon', clientRequestId: 'k1').statusCode, 200);
    expect(ledger.balance, 70);
  });

  test('잔액 부족은 insufficient_points 코드다', () {
    book.unlock('oni_owoon');
    book.unlock('oni_gains');
    final DemoCouponResult r = book.unlock('dog_love');
    expect(
      ((r.body! as Map<String, Object?>)['detail']!
          as Map<String, Object?>)['code'],
      'insufficient_points',
    );
  });
}
