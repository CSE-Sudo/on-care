/// 오늘 할 일 — 상담 미션의 갱신과 부제. (#2887)
///
/// 상담 미션은 대기 목록을 한 번만 읽는다. 승인·거절 뒤에도, 새 요청이 와도
/// 다시 읽지 않아 처리한 요청이 남고 새 요청이 빠졌다. 부제는 희망일을
/// "{월}/{일} 상담 요청" 으로 적어 요청이 접수된 날처럼 읽혔다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/consultations/data/repositories/consultation_repository.dart';
import 'package:oncare_trainer/features/consultations/domain/entities/consultation_request.dart';
import 'package:oncare_trainer/features/dashboard/presentation/widgets/today_tasks_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/pump_app.dart';

ConsultationRequest _request(
  String id,
  String name, {
  String timeCode = '18:00',
  DateTime? slotStartsAt,
}) => ConsultationRequest(
  id: id,
  memberId: 'user-$id',
  memberName: name,
  goalCode: 'weight_loss',
  purposeCode: 'chronic',
  preferredDate: DateTime(2026, 8, 25),
  preferredTimeCode: timeCode,
  slotStartsAt: slotStartsAt,
  slotDurationMinutes: slotStartsAt == null ? null : 30,
  status: 'pending',
);

/// 서버처럼 대기 목록을 들고 있는 상담 저장소. 대기 수는 [counts] 로 직접
/// 흘려 배지 폴링을 흉내 낸다.
class _InboxRepository implements ConsultationRepository {
  _InboxRepository(this.pending);

  List<ConsultationRequest> pending;
  final StreamController<int> counts = StreamController<int>.broadcast();
  int fetches = 0;

  /// 테스트가 끝나면 닫는다.
  Future<void> dispose() => counts.close();

  @override
  bool get supportsInbox => true;

  @override
  Future<List<ConsultationRequest>> fetch({
    String status = 'pending',
    int limit = consultationPageSize,
    DateTime? before,
    String? beforeId,
  }) async {
    fetches += 1;
    return List<ConsultationRequest>.of(pending);
  }

  @override
  Stream<List<ConsultationRequest>> watch({
    String status = 'pending',
    int limit = consultationPageSize,
  }) => Stream<List<ConsultationRequest>>.value(pending);

  @override
  Future<int> pendingCount() async => pending.length;

  @override
  Stream<int> watchPendingCount() async* {
    yield pending.length;
    yield* counts.stream;
  }

  @override
  Future<ConsultationAcceptResult> accept(String id) =>
      throw UnimplementedError();

  @override
  Future<void> reject(String id, {String? note}) async {
    pending = pending.where((ConsultationRequest r) => r.id != id).toList();
  }
}

void main() {
  group('consultationMissionWhen', () {
    setUp(useFixedKstDate);

    final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    test('자리를 고른 요청은 그 자리의 날짜·시각', () {
      final String when = consultationMissionWhen(
        ko,
        _request(
          'c1',
          '회원',
          timeCode: 'flexible',
          slotStartsAt: DateTime(2026, 8, 27, 19, 30),
        ),
      );
      expect(when, contains('8/27 ('));
      expect(when, contains('19:30'));
      expect(when, isNot(contains('8/25 (')));
    });

    test('자리가 없으면 희망 날짜와 희망 시각', () {
      final String when = consultationMissionWhen(
        ko,
        _request('c1', '회원', timeCode: '18:00-19:00'),
      );
      expect(when, contains('8/25 ('));
      expect(when, contains('18:00–19:00'));
    });

    test('희망 시각이 조율 가능이면 그렇게 적는다', () {
      expect(
        consultationMissionWhen(ko, _request('c1', '회원', timeCode: 'flexible')),
        contains('조율 가능'),
      );
      expect(
        consultationMissionWhen(en, _request('c1', '회원', timeCode: 'flexible')),
        contains('Flexible'),
      );
    });

    test('부제는 희망 일시로 읽히고 요청이라고 적지 않는다', () {
      final String when = consultationMissionWhen(ko, _request('c1', '회원'));
      expect(ko.dashTodoConsultationSubtitle(when), startsWith('희망 '));
      expect(ko.dashTodoConsultationSubtitle(when), isNot(contains('요청')));
      expect(en.dashTodoConsultationSubtitle(when), startsWith('Preferred'));
      expect(en.dashTodoConsultationSubtitle(when), isNot(contains('request')));
    });
  });

  test('상담 결정 뒤 대시보드 상담 미션도 다시 읽는다', () {
    expect(
      consultationDecisionRefreshTargets,
      containsAll(<ProviderOrFamily>[
        consultationsProvider,
        consultationPendingCountProvider,
        pendingConsultationsOnceProvider,
      ]),
    );
  });

  group('TodayTasksCard 상담 미션', () {
    Future<void> openDashboard(
      WidgetTester tester,
      _InboxRepository repo,
    ) async {
      useFixedKstDate();
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(repo.dispose);
      await pumpTrainerApp(
        tester,
        token: 'demo-trainer-token',
        at: AppRoutes.dashboard,
        extraOverrides: <Override>[
          consultationRepositoryProvider.overrideWithValue(repo),
          clientsProvider.overrideWith(
            (ref) => Stream<List<TrainerClient>>.value(const <TrainerClient>[]),
          ),
        ],
      );
      await settle(tester);
    }

    Finder toggle(String title) =>
        find.byKey(ValueKey<String>('dashboard-category-toggle-$title'));

    Finder missionOf(String id) =>
        find.byKey(ValueKey<String>('dashboard-mission-consultation-$id'));

    Future<void> expandConsultations(WidgetTester tester) async {
      if (toggle('상담').evaluate().isEmpty) return;
      if (missionOf('c1').evaluate().isNotEmpty ||
          missionOf('c2').evaluate().isNotEmpty) {
        return;
      }
      await tester.ensureVisible(toggle('상담'));
      await tester.tap(toggle('상담'));
      await settle(tester);
    }

    testWidgets('거절하면 그 미션이 바로 사라진다', (tester) async {
      final _InboxRepository repo = _InboxRepository(<ConsultationRequest>[
        _request('c1', '상담 회원 1'),
        _request('c2', '상담 회원 2'),
      ]);
      await openDashboard(tester, repo);
      await expandConsultations(tester);
      expect(missionOf('c1'), findsOneWidget);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(TodayTasksCard)),
        listen: false,
      );
      await rejectConsultation(container, 'c1');
      await settle(tester);
      await expandConsultations(tester);

      expect(missionOf('c1'), findsNothing);
      expect(missionOf('c2'), findsOneWidget);
    });

    testWidgets('대기 수가 바뀌면 새 요청이 미션으로 나타난다', (tester) async {
      final _InboxRepository repo = _InboxRepository(<ConsultationRequest>[
        _request('c1', '상담 회원 1'),
      ]);
      await openDashboard(tester, repo);
      await expandConsultations(tester);
      expect(missionOf('c2'), findsNothing);
      final int fetchesBefore = repo.fetches;

      repo.pending = <ConsultationRequest>[
        ...repo.pending,
        _request('c2', '새 상담 회원'),
      ];
      repo.counts.add(2);
      await settle(tester);
      await expandConsultations(tester);

      expect(repo.fetches, fetchesBefore + 1);
      expect(missionOf('c2'), findsOneWidget);
    });

    testWidgets('대기 수가 그대로면 다시 읽지 않는다', (tester) async {
      final _InboxRepository repo = _InboxRepository(<ConsultationRequest>[
        _request('c1', '상담 회원 1'),
      ]);
      await openDashboard(tester, repo);
      final int fetchesBefore = repo.fetches;

      repo.counts.add(1);
      await settle(tester);

      expect(repo.fetches, fetchesBefore);
    });

    testWidgets('부제는 고른 자리의 일시를 희망으로 적는다', (tester) async {
      final _InboxRepository repo = _InboxRepository(<ConsultationRequest>[
        _request(
          'c1',
          '상담 회원 1',
          timeCode: 'flexible',
          slotStartsAt: DateTime(2026, 8, 27, 19, 30),
        ),
      ]);
      await openDashboard(tester, repo);
      await expandConsultations(tester);

      expect(
        find.descendant(
          of: missionOf('c1'),
          matching: find.textContaining('희망 '),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: missionOf('c1'),
          matching: find.textContaining('19:30'),
        ),
        findsOneWidget,
      );
    });
  });
}
