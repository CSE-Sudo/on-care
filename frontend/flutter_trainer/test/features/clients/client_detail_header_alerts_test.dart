import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/design_system/tokens/spacing.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/alert_badge.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 회원 상세 헤더의 주의사항 배지는 **프로필 줄**에 산다. (#926)
///
/// 활성/휴면 배지와 같이 "이 사람이 어떤 상태인가" 를 말하는 값이라, 혼자 한
/// 줄을 쓸 이유가 없었다. 배지가 하나뿐인 경우가 대부분이라 그 줄은 거의 언제나
/// 배지 한 개와 빈 여백이었고, 그만큼 아래 식단·운동이 밀렸다.
void main() {
  const String flagged = 'seed-client-1';

  Future<void> open(WidgetTester tester, List<TrainerClient> roster) async {
    tester.view.devicePixelRatio = 1;
    // 좁은 화면이면 목록 없이 상세만 뜬다 — 이름이 로스터 카드와 헤더에
    // 두 번 그려지지 않아 자리를 잴 수 있다.
    tester.view.physicalSize = const Size(620, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.clientDetail(flagged),
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// 나트륨이 목표를 넘겨 주의 배지가 붙는 회원.
  TrainerClient over() =>
      makeClient(id: flagged, name: '주의회원', sodiumMg: sodiumTargetMg + 900);

  /// 아무 경고도 없는 회원.
  TrainerClient calm() => makeClient(id: flagged, name: '무난회원', sodiumMg: 900);

  Finder quickActions() =>
      find.byKey(const ValueKey<String>('client-detail-quick-actions'));

  /// 프로필 줄 안의 주의사항 배지. 헤더 어딘가가 아니라 **이 줄에** 있어야 한다.
  Finder headerAlerts() => find.descendant(
    of: find.byKey(const ValueKey<String>('client-detail-identity')),
    matching: find.byType(AlertBadge),
  );

  testWidgets('주의사항 배지가 이름·상태와 같은 줄에 보인다', (tester) async {
    await open(tester, <TrainerClient>[over()]);

    expect(headerAlerts(), findsWidgets);

    // 이름과 세로로 겹친다 = 같은 줄이다. 예전에는 이름 줄 **아래**의 자기
    // 줄에 있었다.
    final Rect name = tester.getRect(find.text('주의회원'));
    final Rect badge = tester.getRect(headerAlerts().first);
    expect(badge.top, lessThan(name.bottom));
    expect(badge.bottom, greaterThan(name.top));
    // 상태 배지 오른쪽에 붙는다.
    final Rect status = tester.getRect(
      find.byKey(const ValueKey<String>('client-status-toggle')),
    );
    expect(badge.left, greaterThanOrEqualTo(status.right - 0.5));
  });

  /// 프로필 줄 바로 다음이 빠른 버튼 줄인가. 사이에 주의사항 줄이 끼어 있으면
  /// 간격이 그만큼 벌어진다.
  double gapUnderIdentity(WidgetTester tester) =>
      tester.getRect(quickActions()).top -
      tester
          .getRect(find.byKey(const ValueKey<String>('client-detail-identity')))
          .bottom;

  testWidgets('경고가 있는 회원도 프로필 줄 바로 다음이 빠른 버튼 줄이다', (tester) async {
    await open(tester, <TrainerClient>[over()]);

    expect(headerAlerts(), findsWidgets);
    // 주의사항만 있던 줄이 사라졌으므로, 남는 것은 원래의 한 칸 간격뿐이다.
    expect(gapUnderIdentity(tester), closeTo(AppSpacing.md, 0.5));
  });

  testWidgets('경고가 없는 회원의 간격도 같다', (tester) async {
    await open(tester, <TrainerClient>[calm()]);

    expect(headerAlerts(), findsNothing);
    // 회원을 옮겨 다녀도 빠른 버튼 줄의 세로 위치가 흔들리지 않는다.
    expect(gapUnderIdentity(tester), closeTo(AppSpacing.md, 0.5));
  });

  testWidgets('빠른 버튼 줄이 #1024 정리 이후의 구성이다', (tester) async {
    await open(tester, <TrainerClient>[over()]);

    // 신체·목표 관리와 후속 관리는 이 줄을 떠났다 — 전자는 메모와 한
    // 대화상자로 합쳐졌고, 후자는 걷어냈다. 리포트가 새로 생겼다.
    expect(find.text('메시지'), findsOneWidget);
    expect(find.text('프로그램'), findsOneWidget);
    expect(find.text('리포트'), findsOneWidget);
    expect(find.text('회원 신체·목표 관리'), findsNothing);
    expect(find.text('후속 관리'), findsNothing);
    // 메모도 이 줄을 떠나 프로필 줄의 아이콘 버튼이 되었다 — 텍스트가 아니라
    // 키로 찾고, 빠른 동작 줄 밖(위)에 있는지까지 확인한다.
    expect(find.text('메모'), findsNothing);
    final memoButton = find.byKey(
      const ValueKey<String>('client-detail-open-memo'),
    );
    expect(memoButton, findsOneWidget);
    expect(
      tester.getRect(memoButton).bottom,
      lessThanOrEqualTo(tester.getRect(quickActions()).top),
    );
    expect(tester.takeException(), isNull);
  });
}
