/// 예약·취소 실 API E2E — 회원 앱 단계 (#637).
///
/// 트레이너 웹 단계와 번갈아 실행된다. 순서와 실행 방법은
/// `scripts/run_reservation_e2e.sh` 와 `docs/local_fullstack.md` 참고.
///
///  1. (트레이너) `create-slot`
///  2. `reserve`     — 회원이 그 자리를 보고 예약한다. 재시작·재로그인 뒤에도 유지.
///  3. (트레이너) `verify-schedule`
///  4. `cancel`      — 회원이 취소한다. 좌석이 돌아오고 다시 고를 수 있다.
///  5. (트레이너) `verify-schedule-cancelled`
///  6. `edge-cases`  — 중복·마감·마지막 좌석 경쟁이 초과 예약을 만들지 않는지.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oncare_ui/oncare_ui.dart';

import 'support/e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installPluginFakes);

  testWidgets('회원 단계: $e2ePhase', (WidgetTester tester) async {
    final E2eApi api = await E2eApi.login(memberEmail);
    final E2eState state = E2eState.read();

    switch (e2ePhase) {
      case 'reserve':
        final String slotId = state.require('slotId');
        final int capacity = state.requireInt('slotCapacity');

        // 트레이너가 만든 자리가 담당 회원에게 실제로 보이는가.
        final Map<String, dynamic>? before = await api.slotById(slotId);
        expect(before, isNotNull, reason: '트레이너가 연 슬롯이 회원 조회에 나오지 않습니다.');
        expect(before!['remaining'], capacity);

        await bootSignedOut(tester);
        await loginAsMember(tester);
        await openGymTab(tester);

        await pumpUntil(
          tester,
          find.byKey(ValueKey<String>('slot-chip-$slotId')),
          step: '담당 트레이너의 슬롯이 회원 화면에 표시',
        );
        final Finder confirm = await selectSlotForReserve(tester, slotId);
        await tester.ensureVisible(confirm);
        await tester.pump();
        await tester.tap(confirm);

        // 서버에 예약이 남고 좌석이 하나 줄었는가. 화면 문구가 아니라 서버가 근거다.
        // 손으로 쓰던 폴링 루프를 하네스의 [pumpUntilServer] 로 옮겼다 — 취소
        // 단계가 같은 규칙을 쓰지 않아 깜빡였다(#910).
        final Map<String, dynamic>? reservation = await pumpUntilServer(
          tester,
          () => api.reservationForSlot(slotId),
          isNotNull,
          step: '예약 UI 가 만든 예약',
        );

        await pumpUntilServer(
          tester,
          () async => (await api.slotById(slotId))!['remaining'],
          equals(capacity - 1),
          step: '예약 후 줄어든 잔여 좌석',
        );

        final String reservationId = reservation!['id'] as String;
        // '내 예약' 에 나타나야 취소를 걸 수 있다.
        await pumpUntil(
          tester,
          find.byKey(ValueKey<String>('cancel-reservation-$reservationId')),
          step: '내 예약 목록에 방금 잡은 자리 표시',
        );

        // 재시작 + 재로그인 후에도 같은 서버 상태를 보는가.
        await bootSignedOut(tester);
        await loginAsMember(tester);
        await openGymTab(tester);
        await pumpUntil(
          tester,
          find.byKey(ValueKey<String>('cancel-reservation-$reservationId')),
          step: '재로그인 후 내 예약 유지',
        );
        expect(
          (await api.slotById(slotId))!['remaining'],
          capacity - 1,
          reason: '재로그인 후 잔여 좌석이 서버와 어긋납니다.',
        );

        E2eState.merge(<String, Object?>{'reservationId': reservationId});

      case 'cancel':
        final String slotId = state.require('slotId');
        final int capacity = state.requireInt('slotCapacity');
        final String reservationId = state.require('reservationId');

        await bootSignedOut(tester);
        await loginAsMember(tester);
        await openGymTab(tester);

        final Finder cancel = find.byKey(
          ValueKey<String>('cancel-reservation-$reservationId'),
        );
        await pumpUntil(tester, cancel, step: '취소 버튼');
        await tester.ensureVisible(cancel);
        await tester.pump();
        await tester.tap(cancel);
        await tester.pump();

        // 되돌릴 수 없는 동작이라 앱이 확인을 한 번 받는다. 그 확인을 눌러야 진행된다.
        // 문구가 아니라 모양으로 찾는다 — 이 스위트는 로케일 기본값이 무엇이든
        // 돌아야 한다. 확인창의 빨간 채움 버튼이 확정이다(#1701).
        final Finder confirmCancel = find.descendant(
          of: find.byType(AppDialog),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is AppButton && w.variant == AppButtonVariant.destructive,
          ),
        );
        await pumpUntil(tester, confirmCancel, step: '취소 확인 다이얼로그');
        await tester.tap(confirmCancel);

        await pumpUntilAbsent(tester, cancel, step: '취소한 예약이 목록에서 사라짐');

        // 화면에서 사라진 것과 서버가 지운 것은 다른 일이다. 목록이 먼저
        // 정리되면 DELETE 왕복이 아직 끝나지 않았을 수 있어, 한 번만 조회하면
        // 취소가 멀쩡한 날에도 예약이 남아 있는 것으로 읽혔다(#910).
        await pumpUntilServer(
          tester,
          () => api.reservationForSlot(slotId),
          isNull,
          step: '취소한 예약이 서버에서 사라짐',
        );
        await pumpUntilServer(
          tester,
          () async => (await api.slotById(slotId))!['remaining'],
          equals(capacity),
          step: '취소 후 복구된 좌석',
        );

        // 좌석이 돌아왔으니 다시 고를 수 있어야 한다 — 취소가 자리를 죽이면 안 된다.
        await selectSlotForReserve(tester, slotId);

      case 'edge-cases':
        // 여기는 화면이 아니라 계약을 본다. 초과 예약은 UI 를 거치지 않는 요청에서도
        // 막혀야 하고, 동시 요청은 UI 로는 재현할 수 없다. 슬롯은 늘 정원 1이라
        // (#1012) 모든 자리가 마지막 좌석 경쟁 시나리오다.
        final String slotId = state.require('slotId');
        final int capacity = state.requireInt('slotCapacity');

        final E2eApi other = await E2eApi.login(otherMemberEmail);
        final E2eApi trainer = await E2eApi.login(trainerEmail);

        // 1) 같은 회원이 같은 자리를 두 번 잡으면 좌석이 두 번 빠진다. 화면이
        //    만든 슬롯(정원 1, #1012)으로 충분하다 — 정원 크기와 무관한 계약이다.
        expect((await api.reserveRaw(slotId)).statusCode, 201);
        expect(
          (await api.reserveRaw(slotId)).statusCode,
          409,
          reason: '같은 슬롯을 두 번 예약할 수 있으면 좌석이 두 번 빠집니다.',
        );
        expect((await api.slotById(slotId))!['remaining'], capacity - 1);

        // 2) 마지막 좌석 경쟁 — 슬롯은 늘 정원 1이라(#1012) 모든 슬롯이 이
        //    시나리오다. 동시 요청 중 하나만 성공해야 한다.
        final Map<String, dynamic> raceSlot = await trainer.createSlotAsTrainer(
          startsAt: DateTime.now().add(const Duration(days: 3)),
        );
        final String raceSlotId = raceSlot['id'] as String;

        final List<Response<Object?>> raced =
            await Future.wait<Response<Object?>>(<Future<Response<Object?>>>[
              api.reserveRaw(raceSlotId),
              other.reserveRaw(raceSlotId),
            ]);
        expect(
          raced.where((Response<Object?> r) => r.statusCode == 201).length,
          1,
          reason: '마지막 한 자리에 동시 요청이 들어왔는데 성공이 하나가 아닙니다.',
        );
        expect(
          (await api.slotById(raceSlotId))!['remaining'],
          0,
          reason: '경쟁 후 잔여 좌석이 0 이 아닙니다.',
        );

        // 3) 정리 — 이 단계가 만든 예약을 모두 되돌리고 임시 슬롯을 닫는다.
        for (final E2eApi client in <E2eApi>[api, other]) {
          for (final String id in <String>[slotId, raceSlotId]) {
            final Map<String, dynamic>? row = await client.reservationForSlot(
              id,
            );
            if (row != null) {
              expect(
                (await client.cancelRaw(row['id'] as String)).statusCode,
                200,
              );
            }
          }
        }
        expect(
          (await api.slotById(slotId))!['remaining'],
          capacity,
          reason: '정리 후 좌석이 정원까지 복구되지 않았습니다.',
        );
        await trainer.closeSlotAsTrainer(raceSlotId);

        // 4) 없는(이미 취소된) 예약의 취소는 존재조차 드러내지 않는다.
        expect(
          (await api.cancelRaw('res-does-not-exist')).statusCode,
          404,
          reason: '없는 예약의 취소가 404 가 아닙니다.',
        );

      default:
        fail('알 수 없는 E2E_PHASE: "$e2ePhase"');
    }
  });
}
