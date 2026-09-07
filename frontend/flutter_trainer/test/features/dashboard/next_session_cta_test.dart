import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 대시보드 `오늘의 일정` 의 다음 일정 CTA. (#1422)
///
/// 상담의 `메모 남기기` 는 날짜만 실어 보내 그날 첫 일정이 열렸다 — 정작 메모를
/// 남기려던 상담이 아닌 다른 회원의 일정이 선택될 수 있었다. 1:1 PT 의
/// `PT 준비하기` 는 처음부터 회원 ID 를 실어 보내 그 회원이 선택된다.
void main() {
  /// 오늘 날짜의 `YYYY-MM-DD`. 카드는 오늘 일정만 받는다.
  final String today =
      '${nowKst().year.toString().padLeft(4, '0')}-'
      '${nowKst().month.toString().padLeft(2, '0')}-'
      '${nowKst().day.toString().padLeft(2, '0')}';

  ScheduleSession session({
    required String id,
    required String time,
    required String type,
    String? clientId,
    required String clientName,
  }) => ScheduleSession(
    id: id,
    date: today,
    time: time,
    clientId: clientId,
    clientName: clientName,
    type: type,
    durationMinutes: 50,
    status: ScheduleStatus.upcoming,
    note: '',
    program: const <ProgramItem>[],
  );

  final List<TrainerClient> roster = <TrainerClient>[
    makeClient(id: 'client-pt', name: '피티회원'),
  ];

  /// 같은 날 세 일정 — 시간순 첫 일정은 다른 회원의 PT 다. 상담 CTA 가 날짜만
  /// 실어 보내면 이 첫 일정이 대신 열린다.
  final List<ScheduleSession> consultationFirst = <ScheduleSession>[
    session(
      id: 'sess-pt-early',
      time: '23:50',
      type: '1:1 PT',
      clientId: 'client-pt',
      clientName: '피티회원',
    ),
    session(id: 'sess-consult', time: '23:55', type: '상담', clientName: '상담회원'),
  ];

  Future<void> openDashboard(
    WidgetTester tester,
    List<ScheduleSession> sessions,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
        todayScheduleProvider.overrideWith(
          (ref) => Stream<List<ScheduleSession>>.value(sessions),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  String currentLocation(WidgetTester tester) {
    final ctx = tester.element(find.byType(Navigator).first);
    return GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.toString();
  }

  Future<void> tapCta(WidgetTester tester) async {
    final cta = find.byKey(
      const ValueKey<String>('dashboard-next-session-cta'),
    );
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();
  }

  testWidgets('상담 CTA 는 날짜와 그 상담 일정 ID 를 함께 보낸다', (tester) async {
    // 다음 일정이 상담이 되도록 상담을 앞에 둔다.
    await openDashboard(tester, <ScheduleSession>[
      consultationFirst[1],
      consultationFirst[0],
    ]);

    expect(find.text('메모 남기기'), findsOneWidget);
    await tapCta(tester);

    final String location = currentLocation(tester);
    expect(location, contains('/schedule'));
    expect(location, contains('session=sess-consult'));
    // 같은 날 다른 일정이 대신 열리지 않는다.
    expect(location, isNot(contains('sess-pt-early')));
  });

  testWidgets('로스터에 없는 상담 회원도 일정 ID 로 이동한다', (tester) async {
    // 상담으로 잡힌 가망 회원은 로스터에 자리가 없어 표시 이름만 있다.
    await openDashboard(tester, <ScheduleSession>[
      session(id: 'sess-prospect', time: '23:59', type: '상담', clientName: '신규'),
    ]);

    await tapCta(tester);
    expect(currentLocation(tester), contains('session=sess-prospect'));
  });

  testWidgets('1:1 PT CTA 는 그 회원의 프로그램 탭으로 간다', (tester) async {
    await openDashboard(tester, <ScheduleSession>[consultationFirst[0]]);

    expect(find.text('PT 준비하기'), findsOneWidget);
    await tapCta(tester);

    final String location = currentLocation(tester);
    expect(location, contains('/coaching'));
    expect(location, contains('client=client-pt'));
  });
}
