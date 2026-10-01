import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_workbench.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/pump_app.dart';

/// 명단 밖 회원 주소로 편집기에 들어온 경우(#2862).
///
/// 예전에는 `client` 가 명단에 없으면 편집기가 **명단의 첫 회원**을 대신 골라
/// 그 회원의 리포트를 그렸다. 주소에는 원래 id 가 남아 트레이너는 바뀐 줄 모르고,
/// 전송 버튼은 화면의 리포트(첫 회원)로 PDF 를 보내 다른 회원 채팅방에 그 회원의
/// 건강 기록이 나갔다. 초안도 첫 회원 기준으로 읽고 저장됐다.
void main() {
  final TrainerClient first = makeClient(id: 'roster-first', name: '첫회원');
  final TrainerClient second = makeClient(id: 'roster-second', name: '둘째회원');

  final Finder sendButton = find.byKey(
    const ValueKey<String>('report-step-send'),
  );
  final Finder editorHeader = find.byKey(
    const ValueKey<String>('reports-back-to-list'),
  );

  /// 명단을 손으로 흘려보낼 수 있는 앱. 명단 로딩 중을 재현하려고 첫 값을
  /// 늦게 보낸다.
  Future<(ProviderContainer, StreamController<List<TrainerClient>>)> pumpWith(
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final StreamController<List<TrainerClient>> roster =
        StreamController<List<TrainerClient>>.broadcast();
    addTearDown(roster.close);
    final ProviderContainer container = await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      extraOverrides: <Override>[
        clientsProvider.overrideWith((ref) => roster.stream),
      ],
    );
    return (container, roster);
  }

  /// [location] 으로 옮기고 몇 프레임만 넘긴다 — 토스트(2초)가 사라지기 전에
  /// 보려고 [settle] 을 쓰지 않는다.
  Future<void> goShort(WidgetTester tester, String location) async {
    final BuildContext context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).go(location);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  ReportKey keyOf(TrainerClient client) =>
      ReportKey(client: client, weekStart: weekStartOf(nowKst()));

  testWidgets('명단에 없는 회원 주소로 들어오면 첫 회원 리포트 대신 작업대로 돌아간다', (tester) async {
    final (ProviderContainer container, roster) = await pumpWith(tester);
    await goShort(tester, AppRoutes.reportFor('gone-member'));
    roster.add(<TrainerClient>[first, second]);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 안내가 한 번 뜬다.
    expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
    // 다른 회원의 리포트가 그려지지 않는다.
    expect(find.text('첫회원님 주간 리포트'), findsNothing);
    expect(find.text('둘째회원님 주간 리포트'), findsNothing);
    expect(editorHeader, findsNothing);
    expect(sendButton, findsNothing);

    await settle(tester);
    // `client` 없는 작업대 주소로 되돌아왔다.
    expect(currentLocation(tester), AppRoutes.reports);
    expect(find.byType(ReportWorkbench), findsOneWidget);
    // 첫 회원의 초안을 읽지 않았다 — 엉뚱한 회원 초안에 글이 남을 길이 없다.
    expect(
      container.exists(reportFeedbackDraftProvider(keyOf(first))),
      isFalse,
    );
  });

  testWidgets('명단 로딩 중에는 아무 회원도 대신 고르지 않고 기다린다', (tester) async {
    final (ProviderContainer container, roster) = await pumpWith(tester);
    await goShort(tester, AppRoutes.reportFor(second.id));

    // 명단이 아직 오지 않았다 — 편집기도, 안내도, 작업대 이동도 없다.
    expect(editorHeader, findsNothing);
    expect(sendButton, findsNothing);
    expect(find.text('회원을 찾을 수 없어요'), findsNothing);
    expect(
      currentLocation(tester),
      AppRoutes.reportFor(second.id),
      reason: '로딩을 "명단에 없음" 으로 읽으면 주소를 잃는다',
    );
    expect(
      container.exists(reportFeedbackDraftProvider(keyOf(first))),
      isFalse,
    );

    // 명단이 오면 주소의 그 회원으로 연다 — 첫 회원이 아니다.
    roster.add(<TrainerClient>[first, second]);
    await settle(tester);
    expect(find.text('둘째회원님 주간 리포트'), findsOneWidget);
    expect(find.text('첫회원님 주간 리포트'), findsNothing);
    expect(find.text('회원을 찾을 수 없어요'), findsNothing);
  });

  testWidgets('명단에 있는 회원 주소는 지금처럼 그 회원 편집기를 연다', (tester) async {
    final (_, roster) = await pumpWith(tester);
    roster.add(<TrainerClient>[first, second]);
    await settle(tester);
    await goShort(tester, AppRoutes.reportFor(second.id));
    roster.add(<TrainerClient>[first, second]);
    await settle(tester);

    expect(find.text('둘째회원님 주간 리포트'), findsOneWidget);
    expect(currentLocation(tester), AppRoutes.reportFor(second.id));
    expect(find.text('회원을 찾을 수 없어요'), findsNothing);
  });

  testWidgets('편집 중인 회원이 명단에서 빠지면 그 자리에서 작업대로 돌아간다', (tester) async {
    final (_, roster) = await pumpWith(tester);
    roster.add(<TrainerClient>[first, second]);
    await settle(tester);
    await goShort(tester, AppRoutes.reportFor(second.id));
    await settle(tester);
    expect(find.text('둘째회원님 주간 리포트'), findsOneWidget);

    // 담당 해제·동의 철회로 다음 명단에서 빠졌다.
    roster.add(<TrainerClient>[first]);
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
    expect(find.text('첫회원님 주간 리포트'), findsNothing);
    expect(sendButton, findsNothing);

    await settle(tester);
    expect(currentLocation(tester), AppRoutes.reports);
  });

  testWidgets('같은 주소로 다시 들어오면 안내가 다시 뜬다', (tester) async {
    final (_, roster) = await pumpWith(tester);
    roster.add(<TrainerClient>[first]);
    await settle(tester);

    await goShort(tester, AppRoutes.reportFor('gone-member'));
    expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
    await settle(tester);
    await settle(tester);
    expect(find.text('회원을 찾을 수 없어요'), findsNothing);

    await goShort(tester, AppRoutes.reportFor('gone-member'));
    expect(find.text('회원을 찾을 수 없어요'), findsOneWidget);
  });
}
