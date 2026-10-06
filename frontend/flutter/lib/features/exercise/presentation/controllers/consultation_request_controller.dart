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

  /// 이 기기에서 목록을 바꾼 횟수(신청·취소). [restore] 가 받는 사이에 바뀌었는지
  /// 가린다.
  int _localEdits = 0;

  /// 409(이미 대기 중)를 받았는데 서버 목록에서 실제 요청을 찾지 못해 화면용
  /// 요청을 그대로 넣은 임시 카드의 id. 서버에 없는 id 다(#2858).
  final Set<String> _provisionalIds = <String>{};

  /// 마지막 [restore] 를 실패하게 한 오류(#3140). 받았으면 null 이다 — 내역
  /// 화면의 오류 안내가 원인(연결·서버·권한)을 말하는 근거다.
  Object? get lastRestoreError => _lastRestoreError;
  Object? _lastRestoreError;

  /// 서버에 남은 내 신청으로 목록을 채운다. 실패해도 예외를 던지지 않는다 —
  /// 복원이 안 됐다고 다른 화면을 오류로 덮을 이유가 없고, 중복은 서버가 409 로
  /// 막는다. 대신 받았는지를 돌려줘, 내역 화면이 처음 열 때 로딩·오류·빈 상태를
  /// 가를 수 있게 한다(#2858). 버려진 컨트롤러이거나 받는 사이 이 기기에서
  /// 바뀌어 받은 목록을 버린 경우도 실패는 아니다(`true`).
  ///
  /// 받는 사이에 이 기기에서 신청·취소가 있었으면 받은 목록을 버린다. 그 목록은
  /// 방금 한 일을 모르므로, 덮어쓰면 방금 낸 신청이 사라진다. 다음 갱신이 맞춘다.
  ///
  /// 빈 목록으로는 덮지 않는다 — 서버는 낸 신청을 지우지 않으므로(탈퇴 제외) 빈
  /// 답은 아직 받은 것이 없다는 뜻이고, 실 API 에서 잃는 것은 없다. 데모 저장소도
  /// 이제 낸 신청을 메모리에 들고 있다가 돌려준다(#2659).
  Future<bool> restore() async {
    final int edits = _localEdits;
    final List<ConsultationRequest> mine;
    try {
      mine = await _repository.fetchMine();
    } on Object catch (error) {
      _lastRestoreError = error;
      return false;
    }
    _lastRestoreError = null;
    // 받는 사이에 세션이 바뀌어 이 컨트롤러가 버려졌을 수 있다.
    if (!mounted || edits != _localEdits) return true;
    if (mine.isNotEmpty) {
      // 서버 목록이 들어오면 임시 카드는 그 목록에 자리를 내준다.
      _provisionalIds.clear();
      state = mine;
    }
    return true;
  }

  /// 트레이너의 결정을 따라온다(#2067).
  ///
  /// 승인·거절·만료는 서버에서 일어난다. 처음 한 번만 받아 두면 알림은 "반려되었어요"
  /// 인데 화면은 계속 "확인 대기" 이고, 그 옛 대기 표시([hasPending])가 같은
  /// 트레이너에게 다시 신청하는 것까지 막는다 — 서버는 이미 자리를 풀었는데도.
  ///
  /// 부르는 곳: 미읽음 알림 수가 늘 때(하단 탭 틀), 내 상담 요청·상담 신청 화면을
  /// 열 때, 상담 결과 알림을 눌렀을 때.
  Future<bool> refresh() => restore();

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
      //
      // 화면용 요청(`display`)의 id 는 폼이 만든 임시값이라 서버에 없다 — 그대로
      // 넣으면 그 카드의 취소가 404 로 실패한다. 서버 목록을 곧바로 받아 실제 대기
      // 요청을 넣는다(#2858). 목록을 받지 못했거나 거기 없으면 임시 카드를 넣되,
      // 취소할 때 서버 목록에서 실제 id 를 찾는다([cancel]).
      await _adoptServerPending(display);
      return null;
    }

    // 서버 id 가 있을 때만 갈아끼운다. 빈 값(데모)에서 copyWith 를 부르면 값이 같아도
    // 새 인스턴스가 되어, 넣은 객체와 같은지 보는 쪽이 어긋난다.
    final ConsultationRequest saved = id.isEmpty
        ? display
        : display.copyWith(id: id);
    _localEdits++;
    // 접수 응답을 기다리는 사이 [refresh] 가 서버에서 이 요청을 이미 받아 왔을 수
    // 있다 — 같은 요청이 두 줄로 서지 않게 먼저 뺀다.
    state = <ConsultationRequest>[
      saved,
      for (final ConsultationRequest request in state)
        if (saved.id.isEmpty || request.id != saved.id) request,
    ];
    return saved;
  }

  /// 409(이미 대기 중) 뒤에 서버의 실제 대기 요청을 목록에 넣는다. (#2858)
  Future<void> _adoptServerPending(ConsultationRequest display) async {
    List<ConsultationRequest>? mine;
    try {
      mine = await _repository.fetchMine();
    } on Object {
      mine = null;
    }
    if (!mounted) return;
    _localEdits++;
    if (mine != null && _pendingFor(mine, display.trainerId) != null) {
      _provisionalIds.clear();
      state = mine;
      return;
    }
    _provisionalIds.add(display.id);
    state = <ConsultationRequest>[display, ...state];
  }

  static ConsultationRequest? _pendingFor(
    List<ConsultationRequest> requests,
    String? trainerId,
  ) {
    for (final ConsultationRequest request in requests) {
      if (request.trainerId == trainerId &&
          request.status == ConsultationStatus.pending) {
        return request;
      }
    }
    return null;
  }

  /// 대기 중인 요청을 취소한다.
  ///
  /// 실패하면 예외를 그대로 올리고 목록은 바꾸지 않는다 — 화면이 안내를 띄운다
  /// (#2858). 저장소는 이미 결정된 요청이면 [ConsultationNoLongerPending], 없는
  /// 요청이면 [ConsultationNotFound] 를 던지고, 화면은 그때 [refresh] 로 실제
  /// 상태를 받는다.
  ///
  /// 임시 카드([_adoptServerPending])는 서버 목록에서 같은 트레이너의 실제 대기
  /// 요청을 찾아 그 id 로 취소한다. 없으면 [ConsultationNotFound] 다.
  Future<void> cancel(String id) async {
    String target = id;
    if (_provisionalIds.contains(id)) {
      final ConsultationRequest? display = state
          .where((ConsultationRequest r) => r.id == id)
          .firstOrNull;
      final List<ConsultationRequest> mine = await _repository.fetchMine();
      if (!mounted) return;
      final ConsultationRequest? real = _pendingFor(mine, display?.trainerId);
      _provisionalIds.remove(id);
      _localEdits++;
      state = mine.isNotEmpty
          ? mine
          : <ConsultationRequest>[
              for (final ConsultationRequest r in state)
                if (r.id != id) r,
            ];
      if (real == null) throw const ConsultationNotFound();
      target = real.id;
    }
    await _repository.cancel(target);
    if (!mounted) return;
    _localEdits++;
    state = <ConsultationRequest>[
      for (final request in state)
        request.id == target
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
/// 목록이 곧 지금 고를 수 있는 자리여야 한다. 그래서 폼을 닫으면 놓는다 — 붙들고
/// 있으면 한 번 받은 빈 목록이 앱을 다시 켤 때까지 남아 신청할 길이 없었다(#3244).
final consultationSlotsProvider = FutureProvider.autoDispose
    .family<List<TrainerSlot>, String>((ref, trainerId) {
      if (trainerId.isEmpty) {
        return Future<List<TrainerSlot>>.value(const <TrainerSlot>[]);
      }
      return ref.watch(consultationRepositoryProvider).fetchSlots(trainerId);
    }, name: 'consultationSlots');
