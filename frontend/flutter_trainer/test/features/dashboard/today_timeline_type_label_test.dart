/// 대시보드 `오늘 일정` 의 세션 종류 태그는 화면 언어로 나온다. (#2867)
///
/// 태그가 저장된 계약값(`상담`)을 그대로 적어, 영어 화면에서도 대시보드만
/// `상담` 이 남았다. 스케줄 탭 카드·주간 표는 `sessionTypeLabel` 로 옮겨 적는다.
/// 상담 판정도 문자열 부분 일치가 아니라 계약 상수 비교다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

/// [kMidWeekKst](목 13:00) 의 날짜.
const String _today = '2026-08-20';

ScheduleSession _session({
  required String id,
  required String time,
  required String type,
  String? clientId,
  required String clientName,
}) => ScheduleSession(
  id: id,
  date: _today,
  time: time,
  clientId: clientId,
  clientName: clientName,
  type: type,
  durationMinutes: 50,
  status: ScheduleStatus.upcoming,
  note: '',
  program: const <ProgramItem>[],
);

void main() {
  final List<TrainerClient> roster = <TrainerClient>[
    makeClient(id: 'client-pt', name: '피티회원'),
  ];

  Future<void> openDashboard(
    WidgetTester tester,
    List<ScheduleSession> sessions, {
    Locale locale = const Locale('ko'),
  }) async {
    useFixedKstDate();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpTrainerApp(
      tester,
      token: 'demo-trainer-token',
      at: AppRoutes.dashboard,
      locale: locale,
      extraOverrides: <Override>[
        clientsProvider.overrideWith(
          (ref) => Stream<List<TrainerClient>>.value(roster),
        ),
        todayScheduleProvider.overrideWith(
          (ref) => Stream<List<ScheduleSession>>.value(sessions),
        ),
      ],
    );
    await settle(tester);
  }

  Finder rowTag(String sessionId, String label) => find.descendant(
    of: find.byKey(ValueKey<String>('dashboard-schedule-$sessionId')),
    matching: find.text(label),
  );

  final List<ScheduleSession> day = <ScheduleSession>[
    _session(
      id: 'sess-consult',
      time: '15:00',
      type: SessionType.consultation,
      clientName: '상담회원',
    ),
    _session(
      id: 'sess-pt',
      time: '17:00',
      type: SessionType.personalTraining,
      clientId: 'client-pt',
      clientName: '피티회원',
    ),
  ];

  group('ScheduleSession.isConsultation', () {
    test('계약값 상담만 상담이다', () {
      expect(day[0].isConsultation, isTrue);
      expect(day[1].isConsultation, isFalse);
    });

    test('화면 문구나 부분 일치로는 상담이 되지 않는다', () {
      ScheduleSession typed(String type) => _session(
        id: 'x',
        time: '10:00',
        type: type,
        clientName: '누군가',
      );
      expect(typed('Consultation').isConsultation, isFalse);
      expect(typed('상담 후 PT').isConsultation, isFalse);
      expect(typed('').isConsultation, isFalse);
    });
  });

  testWidgets('영어 화면에서 상담 줄의 종류 태그가 Consultation 이다', (tester) async {
    await openDashboard(tester, day, locale: const Locale('en'));

    expect(rowTag('sess-consult', 'Consultation'), findsOneWidget);
    expect(rowTag('sess-consult', '상담'), findsNothing);
  });

  testWidgets('영어 화면의 PT 줄 태그도 화면 문구로 나온다', (tester) async {
    await openDashboard(tester, day, locale: const Locale('en'));

    expect(rowTag('sess-pt', '1:1 PT'), findsOneWidget);
  });

  testWidgets('한국어 화면의 상담 태그는 그대로 상담이다', (tester) async {
    await openDashboard(tester, day);

    expect(rowTag('sess-consult', '상담'), findsOneWidget);
    expect(rowTag('sess-pt', '1:1 PT'), findsOneWidget);
  });

  testWidgets('다음 일정이 상담이면 배너 버튼은 메모 남기기다', (tester) async {
    await openDashboard(tester, day);

    expect(find.text('메모 남기기'), findsOneWidget);
    expect(find.text('PT 준비하기'), findsNothing);
  });

  testWidgets('영어 화면에서도 상담 배너 버튼은 메모 쪽이다', (tester) async {
    await openDashboard(tester, day, locale: const Locale('en'));

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('dashboard-next-session-cta')),
        matching: find.text('Leave a memo'),
      ),
      findsOneWidget,
    );
  });
}
