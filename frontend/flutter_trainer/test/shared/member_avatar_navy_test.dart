import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/app/shell/app_sidebar.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/widgets/client_avatar.dart';
import 'package:oncare_ui/oncare_ui.dart';

import '../helpers/client_avatar_expect.dart';
import '../helpers/client_factory.dart';
import '../helpers/pump_app.dart';

/// 트레이너 웹 전 탭의 회원 프로필 원은 남색 원 + 흰 이니셜 한 벌이다(#2448).
///
/// 리포트 탭 `전송 완료` 목록만 남색이고 나머지 탭은 옅은 하늘색 채움 +
/// 남색 글씨라, 같은 회원이 탭을 옮길 때마다 다른 원으로 보였다.
void main() {
  final List<TrainerClient> roster = <TrainerClient>[
    makeClient(id: 'navy-a', name: '가회원'),
    makeClient(id: 'navy-b', name: '나회원'),
  ];

  Future<void> openAt(WidgetTester tester, String at) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: at,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  for (final (String tab, String at) in <(String, String)>[
    ('고객 관리 목록', AppRoutes.clients),
    ('고객 상세 머리', AppRoutes.clientDetail('navy-a')),
    ('메시지', AppRoutes.messagesFor('navy-a')),
    ('스케줄', AppRoutes.schedule),
    ('프로그램', AppRoutes.coaching),
    ('리포트', AppRoutes.reports),
  ]) {
    testWidgets('$tab 탭의 회원 원은 남색 원 + 흰 이니셜이다', (tester) async {
      await openAt(tester, at);
      expectAllMemberAvatarsNavy(tester);
    });
  }

  testWidgets('트레이너 본인 원(사이드바)은 그대로 공용 AppAvatar 다', (tester) async {
    await openAt(tester, AppRoutes.clients);
    final Finder own = find.descendant(
      of: find.byType(AppSidebar),
      matching: find.byType(AppAvatar),
    );
    expect(own, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.byType(ClientAvatar),
      ),
      findsNothing,
    );
  });

  testWidgets('같은 회원은 목록과 상세 머리에서 같은 이니셜을 쓴다', (tester) async {
    await openAt(tester, AppRoutes.clientDetail('navy-a'));
    final Iterable<ClientAvatar> avatars = tester.widgetList<ClientAvatar>(
      find.byType(ClientAvatar),
    );
    expect(avatars.map((ClientAvatar a) => a.initials), contains('가'));
  });
}
