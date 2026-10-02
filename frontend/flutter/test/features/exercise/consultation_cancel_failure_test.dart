/// 상담 요청 취소 실패·중복 신청 임시 카드·복원 결과 (#2858).
///
/// 예전에는 취소가 실패해도 예외가 화면 밖으로 새고 카드는 그대로였으며, 409
/// (이미 대기 중) 뒤 목록에 넣은 카드는 폼이 만든 임시 id 라 취소가 404 로
/// 실패했다. 컨트롤러가 실패를 그대로 올려 화면이 안내하게 하고, 409 뒤에는
/// 서버의 실제 대기 요청을 쓰는지 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';

import '../../support/consultation_test_support.dart';

ConsultationRequest _request({
  required String id,
  String trainerId = 'trainer-a',
  ConsultationStatus status = ConsultationStatus.pending,
}) => ConsultationRequest(
  id: id,
  trainerId: trainerId,
  trainerName: '김상담',
  trainerRole: '전담 트레이너',
  exerciseGoal: ExerciseGoal.fitness,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  // KST 고정 날짜.
  preferredDate: DateTime(2026, 9, 30),
  preferredTimeSlot: const PreferredTime.at(TimeOfDay(hour: 10, minute: 0)),
  message: null,
  status: status,
  createdAt: DateTime(2026, 9, 28),
);

/// 응답을 테스트가 정하는 대역.
class _ScriptedRepository implements ConsultationRepository {
  /// `fetchMine` 이 돌려줄 목록. null 이면 실패한다.
  List<ConsultationRequest>? mine = const <ConsultationRequest>[];

  /// `create` 가 던질 예외. null 이면 [createdId] 를 돌려준다.
  Object? createError;
  String createdId = 'server-new';

  /// `cancel` 이 던질 예외. null 이면 성공한다.
  Object? cancelError;
  final List<String> cancelled = <String>[];
  int fetchCalls = 0;

  @override
  Future<String> create(ConsultationDraft draft) async {
    final Object? error = createError;
    if (error != null) throw error;
    return createdId;
  }

  @override
  Future<List<ConsultationRequest>> fetchMine({
    int limit = consultationPageSize,
  }) async {
    fetchCalls++;
    final List<ConsultationRequest>? list = mine;
    if (list == null) throw StateError('network down');
    return List<ConsultationRequest>.of(list);
  }

  @override
  Future<void> cancel(String consultationId) async {
    cancelled.add(consultationId);
    final Object? error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<List<TrainerSlot>> fetchSlots(String trainerId) async =>
      const <TrainerSlot>[];
}

/// 기동 시 [ConsultationRequestController.restore] 가 끝날 때까지 기다린다.
Future<ConsultationRequestController> _controller(
  _ScriptedRepository repo,
) async {
  final ConsultationRequestController c = ConsultationRequestController(repo);
  addTearDown(c.dispose);
  await pumpEventQueue();
  return c;
}

void main() {
  group('restore 결과', () {
    test('목록을 받으면 true 이고 상태를 채운다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request(id: 'server-1')];
      final ConsultationRequestController c = await _controller(repo);

      expect(await c.refresh(), isTrue);
      expect(c.state.single.id, 'server-1');
    });

    test('받지 못하면 false 이고 들고 있던 목록은 그대로다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request(id: 'server-1')];
      final ConsultationRequestController c = await _controller(repo);

      repo.mine = null;
      expect(await c.refresh(), isFalse);
      expect(c.state.single.id, 'server-1');
    });

    test('빈 목록도 받은 것이다', () async {
      final ConsultationRequestController c = await _controller(
        _ScriptedRepository(),
      );

      expect(await c.refresh(), isTrue);
      expect(c.state, isEmpty);
    });
  });

  group('취소 실패', () {
    test('네트워크 오류는 그대로 올라가고 카드는 대기로 남는다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request(id: 'server-1')];
      final ConsultationRequestController c = await _controller(repo);

      repo.cancelError = StateError('offline');
      await expectLater(c.cancel('server-1'), throwsA(isA<StateError>()));
      expect(c.state.single.status, ConsultationStatus.pending);
    });

    test('이미 결정된 요청은 ConsultationNoLongerPending 으로 올라간다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[_request(id: 'server-1')];
      final ConsultationRequestController c = await _controller(repo);

      repo.cancelError = const ConsultationNoLongerPending();
      await expectLater(
        c.cancel('server-1'),
        throwsA(isA<ConsultationNoLongerPending>()),
      );
      // 상태는 화면이 refresh 로 서버 값을 받아 바꾼다.
      repo.mine = <ConsultationRequest>[
        _request(id: 'server-1', status: ConsultationStatus.accepted),
      ];
      expect(await c.refresh(), isTrue);
      expect(c.state.single.status, ConsultationStatus.accepted);
    });

    test('성공하면 그 요청만 취소 상태가 된다', () async {
      final _ScriptedRepository repo = _ScriptedRepository()
        ..mine = <ConsultationRequest>[
          _request(id: 'server-1'),
          _request(id: 'server-2', trainerId: 'trainer-b'),
        ];
      final ConsultationRequestController c = await _controller(repo);

      await c.cancel('server-1');

      expect(repo.cancelled, <String>['server-1']);
      expect(
        c.state.map((ConsultationRequest r) => r.status),
        <ConsultationStatus>[
          ConsultationStatus.cancelled,
          ConsultationStatus.pending,
        ],
      );
    });
  });

  group('409(이미 대기 중) 뒤의 카드', () {
    test('서버에 대기 요청이 있으면 그 요청으로 목록을 바꾼다', () async {
      final _ScriptedRepository repo = _ScriptedRepository();
      final ConsultationRequestController c = await _controller(repo);

      // 다른 기기에서 이미 낸 요청이 서버에 있다.
      repo
        ..createError = const DuplicatePendingConsultation()
        ..mine = <ConsultationRequest>[_request(id: 'server-real')];
      final ConsultationRequest display = _request(id: 'local-temp');

      expect(await seedPending(c, display), isFalse);
      expect(c.state.single.id, 'server-real');
      expect(c.hasPending(trainerId: 'trainer-a'), isTrue);

      // 카드의 취소는 서버 id 로 나간다.
      await c.cancel('server-real');
      expect(repo.cancelled, <String>['server-real']);
      expect(c.state.single.status, ConsultationStatus.cancelled);
    });

    test('목록을 받지 못하면 임시 카드를 넣어 대기로 보인다', () async {
      final _ScriptedRepository repo = _ScriptedRepository();
      final ConsultationRequestController c = await _controller(repo);

      repo
        ..createError = const DuplicatePendingConsultation()
        ..mine = null;
      expect(await seedPending(c, _request(id: 'local-temp')), isFalse);

      expect(c.state.single.id, 'local-temp');
      expect(c.hasPending(trainerId: 'trainer-a'), isTrue);
    });

    test('임시 카드를 취소하면 서버의 실제 id 로 취소한다', () async {
      final _ScriptedRepository repo = _ScriptedRepository();
      final ConsultationRequestController c = await _controller(repo);

      repo
        ..createError = const DuplicatePendingConsultation()
        ..mine = null;
      await seedPending(c, _request(id: 'local-temp'));

      // 다시 연결됐다 — 서버에는 실제 대기 요청이 있다.
      repo.mine = <ConsultationRequest>[_request(id: 'server-real')];
      await c.cancel('local-temp');

      expect(repo.cancelled, <String>['server-real']);
      expect(c.state.single.id, 'server-real');
      expect(c.state.single.status, ConsultationStatus.cancelled);
    });

    test('임시 카드의 실제 요청이 서버에 없으면 ConsultationNotFound 다', () async {
      final _ScriptedRepository repo = _ScriptedRepository();
      final ConsultationRequestController c = await _controller(repo);

      repo
        ..createError = const DuplicatePendingConsultation()
        ..mine = null;
      await seedPending(c, _request(id: 'local-temp'));

      // 그 사이 트레이너가 결정해 대기 요청이 없다.
      repo.mine = <ConsultationRequest>[
        _request(id: 'server-real', status: ConsultationStatus.rejected),
      ];
      await expectLater(
        c.cancel('local-temp'),
        throwsA(isA<ConsultationNotFound>()),
      );

      // 서버에 없는 id 로는 취소를 보내지 않고, 목록은 서버 값으로 바뀐다.
      expect(repo.cancelled, isEmpty);
      expect(c.state.single.id, 'server-real');
      expect(c.state.single.status, ConsultationStatus.rejected);
    });

    test('서버 목록이 들어오면 임시 카드는 자리를 내준다', () async {
      final _ScriptedRepository repo = _ScriptedRepository();
      final ConsultationRequestController c = await _controller(repo);

      repo
        ..createError = const DuplicatePendingConsultation()
        ..mine = null;
      await seedPending(c, _request(id: 'local-temp'));

      repo.mine = <ConsultationRequest>[_request(id: 'server-real')];
      expect(await c.refresh(), isTrue);

      expect(c.state.single.id, 'server-real');
      // 서버 id 는 임시 카드로 취급하지 않는다 — 곧바로 취소가 나간다.
      final int fetchesBefore = repo.fetchCalls;
      await c.cancel('server-real');
      expect(repo.fetchCalls, fetchesBefore);
      expect(repo.cancelled, <String>['server-real']);
    });
  });
}
