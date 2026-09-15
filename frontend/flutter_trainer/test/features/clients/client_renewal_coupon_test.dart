// 회원 상세 머리줄의 `재등록 쿠폰` 배지와 사용 처리 확인창. (#1787)
//
// 배지는 회원이 사용 가능한 PT 재등록 쿠폰을 가졌을 때만 선다. 누르면 혜택·교환일·
// 만료일(D-n)과 `사용 후 되돌릴 수 없어요` 경고, `취소 / 사용 완료` 2열 버튼이 뜬다.
// 코드 입력 단계는 없다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_coupon_repository.dart';
import 'package:oncare_trainer/features/clients/domain/entities/renewal_coupon.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../../helpers/pump_app.dart';

class _FakeCouponRepository implements ClientCouponRepository {
  _FakeCouponRepository(this.coupons);

  final Map<String, List<RenewalCoupon>> coupons;
  int redeemCalls = 0;

  /// 주면 사용 처리 응답이 이 값이 풀릴 때까지 끝나지 않는다.
  Future<void>? gate;

  @override
  Future<List<RenewalCoupon>> fetchRenewalCoupons(String clientId) async => <RenewalCoupon>[
    for (final RenewalCoupon c in coupons[clientId] ?? const <RenewalCoupon>[])
      if (c.usable) c,
  ];

  @override
  Future<RenewalCoupon> redeem(String clientId, String couponId) async {
    redeemCalls++;
    await gate;
    final List<RenewalCoupon> list = coupons[clientId]!;
    final int index = list.indexWhere((RenewalCoupon c) => c.id == couponId);
    list[index] = list[index].copyWith(status: 'used');
    return list[index];
  }
}

RenewalCoupon _coupon() => RenewalCoupon(
  id: 'cpn-1',
  item: 'pt_renewal',
  benefit: 'PT 재등록 10,000원 할인',
  status: 'issued',
  issuedOn: DateTime(2026, 9, 12),
  expiresOn: DateTime(2026, 10, 12),
  daysLeft: 27,
);

Finder get _badge =>
    find.byKey(const ValueKey<String>('client-renewal-coupon-badge'));

void main() {
  const String clientId = 'seed-client-1';

  Future<_FakeCouponRepository> open(
    WidgetTester tester, {
    List<RenewalCoupon> coupons = const <RenewalCoupon>[],
  }) async {
    final _FakeCouponRepository repo = _FakeCouponRepository(
      <String, List<RenewalCoupon>>{clientId: <RenewalCoupon>[...coupons]},
    );
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(clientId),
      extraOverrides: <Override>[
        clientCouponRepositoryProvider.overrideWithValue(repo),
      ],
    );
    return repo;
  }

  testWidgets('쿠폰이 없으면 배지가 없다', (tester) async {
    await open(tester);

    expect(find.byKey(const ValueKey<String>('client-detail-identity')), findsOneWidget);
    expect(_badge, findsNothing);
    expect(find.text('재등록 쿠폰'), findsNothing);
  });

  testWidgets('사용 가능한 쿠폰이 있으면 프로필 줄에 배지가 선다', (tester) async {
    await open(tester, coupons: <RenewalCoupon>[_coupon()]);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('client-detail-identity')),
        matching: _badge,
      ),
      findsOneWidget,
    );
    final AppTag tag = tester.widget<AppTag>(
      find.descendant(of: _badge, matching: find.byType(AppTag)),
    );
    expect(tag.label, '재등록 쿠폰');
  });

  testWidgets('배지를 누르면 쿠폰 확인창이 뜨고 취소하면 처리하지 않는다', (tester) async {
    final _FakeCouponRepository repo = await open(
      tester,
      coupons: <RenewalCoupon>[_coupon()],
    );

    await tester.tap(_badge);
    await settle(tester);

    expect(find.byKey(const ValueKey<String>('renewal-coupon-dialog')), findsOneWidget);
    expect(find.text('PT 재등록 10,000원 할인'), findsOneWidget);
    expect(find.text('2026.09.12'), findsOneWidget);
    expect(find.text('2026.10.12 (D-27)'), findsOneWidget);
    expect(find.text('사용 후 되돌릴 수 없어요'), findsOneWidget);
    // 코드 입력 단계는 없다.
    expect(find.byType(AppTextField), findsNothing);
    final AppButtonPair pair = tester.widget<AppButtonPair>(
      find.byType(AppButtonPair),
    );
    expect(pair.cancelLabel, '취소');
    expect(pair.confirmLabel, '사용 완료');

    await tester.tap(find.text('취소'));
    await settle(tester);

    expect(find.byKey(const ValueKey<String>('renewal-coupon-dialog')), findsNothing);
    expect(repo.redeemCalls, 0);
    expect(_badge, findsOneWidget);
  });

  testWidgets('사용 완료를 누르면 한 번 처리되고 배지가 사라진다', (tester) async {
    final _FakeCouponRepository repo = await open(
      tester,
      coupons: <RenewalCoupon>[_coupon()],
    );
    final Completer<void> gate = Completer<void>();
    repo.gate = gate.future;

    await tester.tap(_badge);
    await settle(tester);
    final Finder confirm = find.descendant(
      of: find.byType(AppButtonPair),
      matching: find.text('사용 완료'),
    );
    await tester.tap(confirm);
    await tester.pump();
    // 응답을 기다리는 동안 다시 눌러도 요청은 하나다.
    await tester.tap(find.byType(AppButtonPair), warnIfMissed: false);
    await tester.pump();
    expect(repo.redeemCalls, 1);

    gate.complete();
    await settle(tester);

    expect(repo.redeemCalls, 1);
    expect(find.byKey(const ValueKey<String>('renewal-coupon-dialog')), findsNothing);
    expect(_badge, findsNothing);
    expect(find.text('재등록 쿠폰을 사용 처리했어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('데모에서는 이지수 회원만 재등록 쿠폰을 갖고 있다', (tester) async {
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(DemoClientCouponRepository.demoCouponClientId),
    );
    expect(_badge, findsOneWidget);

    await goTo(tester, AppRoutes.clientDetail(clientId));
    expect(_badge, findsNothing);
  });
}
