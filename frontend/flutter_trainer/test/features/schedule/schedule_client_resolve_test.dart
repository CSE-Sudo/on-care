/// 일정 카드 → 코칭 탭 진입의 회원 특정. (#2864)
///
/// 이름은 표시 전용이다. 같은 이름의 회원이 둘이면 이름으로 고른 첫 회원이
/// 엉뚱한 사람일 수 있어, 일정에 실린 회원 id 로 찾고, id 가 없는 예전
/// 일정은 이름이 정확히 한 명과 일치할 때만 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/schedule/data/repositories/schedule_repository.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/features/schedule/domain/session_client_resolver.dart';
import 'package:oncare_trainer/features/schedule/presentation/widgets/schedule_week_timetable.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/client_factory.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

ScheduleSession _session({
  String? clientId,
  String clientName = '김민지',
  String type = SessionType.personalTraining,
}) => ScheduleSession(
  id: 'sched-dup',
  // [kMidWeekKst](2026-08-20 목) 다음 날 — 아직 오지 않은 PT 다.
  date: '2026-08-21',
  time: '10:00',
  clientId: clientId,
  clientName: clientName,
  type: type,
  durationMinutes: 50,
  status: ScheduleStatus.upcoming,
  note: '',
  program: const [],
);

const List<ScheduleClientKey> _twins = <ScheduleClientKey>[
  (id: 'member-a', name: '김민지'),
  (id: 'member-b', name: '김민지'),
  (id: 'member-c', name: '박성호'),
];

/// 주간 조회만 고정 목록을 돌려주는 데모 저장소 — 나머지는 데모 그대로다.
class _FixedWeekRepository extends DriftScheduleRepository {
  _FixedWeekRepository(super.db, this.sessions);

  final List<ScheduleSession> sessions;

  @override
  Stream<List<ScheduleSession>> watchRange(String fromDate, String toDate) =>
      Stream<List<ScheduleSession>>.value(sessions);
}

void main() {
  group('resolveSessionClientId', () {
    test('일정의 회원 id 가 이름보다 먼저다', () {
      expect(
        resolveSessionClientId(_session(clientId: 'member-b'), _twins),
        'member-b',
      );
    });

    test('명단에 없는 id 는 쓰지 않는다', () {
      expect(
        resolveSessionClientId(_session(clientId: 'gone'), _twins),
        isNull,
      );
    });

    test('명단을 아직 못 읽었으면 일정의 id 를 믿는다', () {
      expect(
        resolveSessionClientId(_session(clientId: 'member-b'), null),
        'member-b',
      );
    });

    test('id 없는 예전 일정 + 동명이인이면 고르지 않는다', () {
      expect(resolveSessionClientId(_session(), _twins), isNull);
    });

    test('id 없는 예전 일정 + 이름이 한 명만 일치하면 그 회원이다', () {
      expect(
        resolveSessionClientId(_session(clientName: '박성호'), _twins),
        'member-c',
      );
    });

    test('일치하는 이름이 없으면 null', () {
      expect(
        resolveSessionClientId(_session(clientName: '없음'), _twins),
        isNull,
      );
    });

    test('빈 이름은 찾지 않는다', () {
      expect(uniqueRosterIdByName(const [(id: 'x', name: '')], ''), isNull);
    });
  });

  group('스케줄 화면의 프로그램 추가', () {
    Future<void> openWith(
      WidgetTester tester,
      ScheduleSession session, {
      Locale locale = const Locale('ko'),
    }) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.schedule,
        seedClock: kMidWeekKst,
        locale: locale,
        extraOverrides: <Override>[
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(<TrainerClient>[
              for (final c in _twins) makeClient(id: c.id, name: c.name),
            ]),
          ),
          scheduleRepositoryProvider.overrideWith(
            (ref) => _FixedWeekRepository(
              ref.watch(appDatabaseProvider),
              <ScheduleSession>[session],
            ),
          ),
        ],
      );
      final block = find
          .descendant(
            of: find.byType(ScheduleWeekTimetable),
            matching: find.textContaining(session.clientName),
          )
          .first;
      await tester.ensureVisible(block);
      await tester.pump();
      await tester.tap(block);
      await settle(tester);
    }

    Future<void> tapAddProgram(WidgetTester tester) async {
      final Finder add = find.byKey(
        const ValueKey<String>('session-add-program-chip'),
      );
      await tester.ensureVisible(add);
      await tester.pump();
      await tester.tap(add);
      // 안내 토스트는 2초 머문다 — 전부 가라앉히면(settle) 사라진 뒤를 본다.
      // 경로 이동과 토스트가 그려질 만큼만 넘긴다.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('동명이인이어도 일정의 회원 id 로 코칭 탭을 연다', (tester) async {
      await openWith(tester, _session(clientId: 'member-b'));
      await tapAddProgram(tester);

      // 명단 앞쪽의 member-a 가 아니라 이 일정의 회원이다.
      expect(currentLocation(tester), AppRoutes.coachingFor('member-b'));
    });

    testWidgets('id 없는 예전 일정 + 동명이인이면 목록으로 가고 안내한다', (tester) async {
      await openWith(tester, _session());
      await tapAddProgram(tester);

      expect(currentLocation(tester), AppRoutes.clients);
      expect(find.text('이 일정의 회원을 특정할 수 없어요. 회원을 골라 주세요.'), findsOneWidget);
    });

    testWidgets('이름이 한 명만 일치하면 예전처럼 그 회원으로 간다', (tester) async {
      await openWith(tester, _session(clientName: '박성호'));
      await tapAddProgram(tester);

      expect(currentLocation(tester), AppRoutes.coachingFor('member-c'));
    });

    testWidgets('영어 화면은 영어 안내다', (tester) async {
      await openWith(tester, _session(), locale: const Locale('en'));
      await tapAddProgram(tester);

      expect(find.textContaining("Couldn't tell which member"), findsOneWidget);
    });
  });
}
