import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/trainer_slot.dart';
import 'package:oncare/features/exercise/domain/repositories/consultation_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

/// 데모는 서버로 나가지 않는다 — `LocalApiInterceptor` 에 `/consultations` 핸들러가
/// 없다. 실 API 모드에서만 접수가 백엔드로 간다(#327).
final consultationRepositoryProvider = Provider<ConsultationRepository>((ref) {
  if (ref.watch(appConfigProvider).useMockApi) {
    // 자리는 목 헬스장 저장소가 들고 있다 — 헬스장 탭과 상담 폼이 같은 자리를
    // 봐야 데모가 앞뒤로 맞는다(#1873).
    return MockConsultationRepository(ref.watch(gymRepositoryProvider));
  }
  return DioConsultationRepository(ref.watch(dioProvider));
}, name: 'consultationRepository');

class ConsultationRequestController
    extends StateNotifier<List<ConsultationRequest>> {
  ConsultationRequestController(this._repository)
    : super(const <ConsultationRequest>[]) {
    // 앱을 다시 열면 목록이 비어 hasPending 이 false 가 되고, 사용자는 이미 낸
    // 신청을 또 눌러 409 를 받는다. 기동 시 서버 상태로 채운다(#327).
    unawaited(restore());
  }

  final ConsultationRepository _repository;

  /// 서버에 남은 내 신청으로 목록을 채운다. 실패는 삼킨다 — 복원이 안 됐다고
  /// 화면을 오류로 덮을 이유가 없고, 중복은 서버가 409 로 막는다.
  Future<void> restore() async {
    try {
      final List<ConsultationRequest> mine = await _repository.fetchMine();
      if (mine.isNotEmpty) state = mine;
    } on Object {
      // 무시
    }
  }

  /// 대기 중인 요청은 **트레이너별**로 본다 — 한 헬스장에 트레이너가 여럿이라,
  /// 한 명에게 낸 요청이 다른 트레이너까지 막으면 안 된다.
  bool hasPending({required String? trainerId}) {
    if (trainerId == null || trainerId.isEmpty) return false;
    return state.any(
      (ConsultationRequest request) =>
          request.trainerId == trainerId &&
          request.status == ConsultationStatus.pending,
    );
  }

  /// 서버에 접수하고 목록에 넣는다. 접수되면 서버가 준 id 를 쓴 요청을 돌려주고,
  /// 이미 대기 중이면 null 을 돌려준다.
  ///
  /// 예전에는 메모리에만 쌓아 새로고침하면 사라지고 트레이너 앱에도 전달되지
  /// 않았다(#327 no-op).
  Future<ConsultationRequest?> submit({
    required ConsultationDraft draft,
    required ConsultationRequest display,
  }) async {
    if (hasPending(trainerId: display.trainerId)) {
      return null;
    }

    final String id;
    try {
      id = await _repository.create(draft);
    } on DuplicatePendingConsultation {
      // 다른 기기에서 이미 신청했다는 뜻이다. 그냥 null 만 돌려주면 목록이 비어 있어
      // hasPending 이 계속 false 이고, 사용자는 같은 대상에 다시 눌러 409 를 반복해서
      // 받는다. 서버가 알려 준 '대기 중' 사실을 목록에 반영해 화면이 안내를 띄우게
      // 한다(리뷰 지적).
      state = <ConsultationRequest>[display, ...state];
      return null;
    }

    // 서버 id 가 있을 때만 갈아끼운다. 빈 값(데모)에서 copyWith 를 부르면 값이 같아도
    // 새 인스턴스가 되어, 넣은 객체와 같은지 보는 쪽이 어긋난다.
    final ConsultationRequest saved = id.isEmpty
        ? display
        : display.copyWith(id: id);
    state = <ConsultationRequest>[saved, ...state];
    return saved;
  }

  Future<void> cancel(String id) async {
    await _repository.cancel(id);
    state = <ConsultationRequest>[
      for (final request in state)
        request.id == id
            ? request.copyWith(status: ConsultationStatus.cancelled)
            : request,
    ];
  }
}

final consultationRequestControllerProvider =
    StateNotifierProvider<
      ConsultationRequestController,
      List<ConsultationRequest>
    >(
      (ref) => ConsultationRequestController(
        ref.watch(consultationRepositoryProvider),
      ),
      name: 'consultationRequests',
    );

/// 상담 신청 폼이 보여 줄 그 트레이너의 빈 자리. (#1873)
///
/// 화면마다 다시 읽는다 — 자리는 다른 회원이 먼저 가져갈 수 있어, 폼을 열 때의
/// 목록이 곧 지금 고를 수 있는 자리여야 한다.
final consultationSlotsProvider =
    FutureProvider.family<List<TrainerSlot>, String>((ref, trainerId) {
      if (trainerId.isEmpty) {
        return Future<List<TrainerSlot>>.value(const <TrainerSlot>[]);
      }
      return ref.watch(consultationRepositoryProvider).fetchSlots(trainerId);
    }, name: 'consultationSlots');
