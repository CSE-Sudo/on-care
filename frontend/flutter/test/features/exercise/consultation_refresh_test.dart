/// 회원 앱의 상담 목록이 트레이너의 결정을 따라온다 (#2067).
///
/// 목록을 처음 한 번만 받던 때는 트레이너가 거절해도 화면이 "확인 대기" 로
/// 남았고, 그 옛 대기 표시가 같은 트레이너에게 다시 신청하는 것까지 막았다 —
/// 서버는 이미 자리를 풀었는데도. 앱을 재시작해야 풀렸다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/app/app_theme.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/pages/consultation_history_page.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

const AppConfig _config = AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'https://dev.api.test',
  useMockApi: true,
);

const String _trainerId = 'trainer-demo';
const String _note = '이번 주는 일정이 가득 찼어요';

/// `GET /consultations/me` 한 줄.
ConsultationRequest _row({
  String id = 'consult-1',
  String trainerId = _trainerId,
  String status = 'pending',
  String? note,
}) => consultationFromJson(<String, Object?>{
  'id': id,
  'member_id': 'user-1',
  'target_type': 'trainer',
  'trainer_id': trainerId,
  'trainer_name': '김태오',
  'exercise_goal': 'strength',
  'health_purpose_type': 'general',
  'preferred_date': '2026-09-20',
  'preferred_time_slot': '19:30',
  'slot_id': 'slot-1',
  'slot_starts_at': '2026-09-20T10:30:00Z',
  'slot_duration_minutes': 60,
  'status': status,
  'decision_note': note,
  'created_at': '2026-09-18T10:00:00Z',
  'updated_at': '2026-09-18T10:00:00Z',
});

/// 서버 대역. [rows] 를 바꿔 트레이너의 결정을 흉내 내고, 게이트로 응답을 붙잡아
/// "받는 사이" 를 만든다.
class _ServerRepository implements ConsultationRepository {
  _ServerRepository(this.rows);

  List<ConsultationRequest> rows;
  int fetchCalls = 0;

  /// 채워 두면 목록 응답이 이것이 끝날 때까지 늦게 온다.
  Completer<void>? fetchGate;

  /// 채워 두면 접수 응답이 이것이 끝날 때까지 늦게 온다.
  Completer<void>? createGate;
  String createdId = 'consult-new';

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async {
    fetchCalls++;
    // 요청을 보낸 순간의 서버 상태다 — 응답이 늦게 와도 그 뒤의 변화는 모른다.
    final List<ConsultationRequest> snapshot = List.of(rows);
    await fetchGate?.future;
    return snapshot;
  }

  @override
  Future<String> create(ConsultationDraft draft) async {
    await createGate?.future;
    return createdId;
  }

  @override
  Future<void> cancel(String consultationId) async {}

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

ConsultationDraft _draft(String trainerId) => ConsultationDraft(
  trainerId: trainerId,
  exerciseGoal: ExerciseGoal.strength,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  slotId: 'slot-2',
  message: null,
  dataSharingConsent: true,
);

Future<ConsultationRequestController> _restored(
  _ServerRepository server,
) async {
  final ConsultationRequestController controller =
      ConsultationRequestController(server);
  // 생성자가 부른 복원이 끝나기를 기다린다.
  await pumpEventQueue();
  return controller;
}

void main() {
  for (final (String status, ConsultationStatus expected)
      in <(String, ConsultationStatus)>[
        ('rejected', ConsultationStatus.rejected),
        ('expired', ConsultationStatus.expired),
      ]) {
    test('$status 가 되면 refresh 뒤 대기가 풀려 다시 신청할 수 있다', () async {
      final _ServerRepository server = _ServerRepository(<ConsultationRequest>[
        _row(),
      ]);
      final ConsultationRequestController controller = await _restored(server);
      expect(controller.hasPending(trainerId: _trainerId), isTrue);

      // 트레이너가 결정했다(또는 요청이 만료됐다) — 서버만 안다.
      server.rows = <ConsultationRequest>[_row(status: status, note: _note)];
      await controller.refresh();

      expect(controller.state.single.status, expected);
      expect(
        controller.hasPending(trainerId: _trainerId),
        isFalse,
        reason: '옛 대기 표시가 같은 트레이너에게 다시 신청하는 것을 막는다.',
      );
      controller.dispose();
    });
  }

  test('받는 사이에 낸 신청을 덮어쓰지 않는다', () async {
    final _ServerRepository server = _ServerRepository(<ConsultationRequest>[
      _row(status: 'rejected', note: _note),
    ]);
    final ConsultationRequestController controller = await _restored(server);

    server.fetchGate = Completer<void>();
    final Future<void> refreshing = controller.refresh();
    // 목록 응답이 오기 전에 다른 트레이너에게 새로 신청했다.
    final ConsultationRequest? saved = await controller.submit(
      draft: _draft('trainer-park'),
      display: _row(id: '', trainerId: 'trainer-park'),
    );
    server.fetchGate!.complete();
    await refreshing;

    // 늦게 온 목록은 방금 낸 신청을 모른다 — 그걸로 덮으면 신청이 사라진다.
    expect(saved, isNotNull);
    expect(controller.state.first.id, 'consult-new');
    expect(controller.hasPending(trainerId: 'trainer-park'), isTrue);
    controller.dispose();
  });

  test('접수를 기다리는 사이 받아 온 같은 요청이 두 줄로 서지 않는다', () async {
    final _ServerRepository server = _ServerRepository(<ConsultationRequest>[]);
    final ConsultationRequestController controller = await _restored(server);

    server.createGate = Completer<void>();
    final Future<ConsultationRequest?> submitting = controller.submit(
      draft: _draft(_trainerId),
      display: _row(id: ''),
    );
    // 서버에는 이미 접수됐고, 응답보다 목록 갱신이 먼저 도착했다.
    server.rows = <ConsultationRequest>[_row(id: 'consult-new')];
    await controller.refresh();
    server.createGate!.complete();
    await submitting;

    expect(controller.state.map((ConsultationRequest r) => r.id), <String>[
      'consult-new',
    ]);
    controller.dispose();
  });

  test('세션이 바뀌어 버려진 뒤 도착한 목록은 무시한다', () async {
    final _ServerRepository server = _ServerRepository(<ConsultationRequest>[]);
    final ConsultationRequestController controller = await _restored(server);

    server
      ..fetchGate = Completer<void>()
      ..rows = <ConsultationRequest>[_row()];
    final Future<void> refreshing = controller.refresh();
    controller.dispose();
    server.fetchGate!.complete();

    // 버려진 컨트롤러에 값을 넣으면 StateError 가 난다.
    await expectLater(refreshing, completes);
  });

  testWidgets('내 상담 요청을 열면 목록을 다시 받아 거절과 사유를 보여 준다', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final _ServerRepository server = _ServerRepository(<ConsultationRequest>[
      _row(),
    ]);
    // 가짜 시간대라 [_restored] 의 `pumpEventQueue` 는 쓰지 않는다 — 요청은
    // 부르는 순간 세어지고, 응답은 아래 펌프가 흘려보낸다.
    final ConsultationRequestController controller =
        ConsultationRequestController(server);
    final int before = server.fetchCalls;
    // 앱이 목록을 받은 뒤 트레이너가 거절했다.
    server.rows = <ConsultationRequest>[_row(status: 'rejected', note: _note)];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config),
          consultationRequestControllerProvider.overrideWith((_) => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ConsultationHistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(server.fetchCalls, greaterThan(before));
    expect(find.byKey(const Key('consult-outcome-rejected')), findsOneWidget);
    expect(find.textContaining(_note), findsWidgets);
  });
}
