import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';

/// Reads and reviews the AI personal-exercise suggestions for one member.
///
/// 담당 트레이너가 있는 회원에게 AI 개인운동을 그대로 노출하면, 트레이너가 알고
/// 있는 부상·회복 상태가 반영되지 않은 운동이 회원 화면에 뜬다. 그래서 후보는
/// 검토 대기(pending)로 준비되고, **승인한 것만** 회원에게 간다(#790).
///
/// 두 구현이 이 계약 뒤에 있다([trainerRoutineSuggestionRepositoryProvider] 가
/// [AppConfig.useMockApi] 로 고른다):
///  * [MockTrainerRoutineSuggestionRepository] — 데모 / `USE_MOCK_API=true`;
///  * [DioTrainerRoutineSuggestionRepository] — 실제 FastAPI 백엔드.
abstract interface class TrainerRoutineSuggestionRepository {
  /// 검토를 기다리는 제안(GET /trainer/clients/{id}/routine-suggestions).
  ///
  /// 서버가 이 조회 자리에서 그날 후보를 준비한다(멱등) — 트레이너가 생성을
  /// 요청하지 않아도 프로그램 탭을 열면 검토할 것이 있다.
  Future<List<RoutineSuggestion>> pending(String memberId);

  /// 제안을 승인해 회원에게 배정한다.
  ///
  /// 값을 주면 그것으로 고쳐서 승인한다(수정 후 추천). 아무 값도 주지 않으면
  /// 그대로 승인이다. 이미 승인·거절된 제안이면
  /// [RoutineSuggestionAlreadyReviewed] — 두 번 눌렀거나 다른 창에서 이미
  /// 처리한 경우다.
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  });

  /// 제안을 추천하지 않기로 한다. 회원 배정도 알림도 생기지 않는다.
  Future<void> dismiss(String suggestionId);
}

/// 이미 검토된 제안을 다시 검토하려 했다(서버 409).
///
/// '없음'과 나누는 이유: 사라진 것으로 보이면 트레이너는 자기 판단이 반영되지
/// 않았다고 읽는다. 실제로는 이미 반영돼 있다.
class RoutineSuggestionAlreadyReviewed implements Exception {
  /// Creates the marker for an already-reviewed suggestion.
  const RoutineSuggestionAlreadyReviewed(this.suggestionId);

  /// The suggestion that was already approved or dismissed.
  final String suggestionId;

  @override
  String toString() => 'suggestion already reviewed: $suggestionId';
}

/// Demo suggestions the trainer can review without a backend.
///
/// 데모에는 후보를 준비해 줄 서버가 없다. 빈 목록을 돌려주면 이 기능이 데모에서
/// 아예 보이지 않으므로, 회원마다 같은 후보 두 건을 들고 시작하고 승인·거절한
/// 것은 목록에서 지운다 — 실서버와 같은 순서로 화면이 움직인다.
class MockTrainerRoutineSuggestionRepository
    implements TrainerRoutineSuggestionRepository {
  /// Creates the demo repository.
  MockTrainerRoutineSuggestionRepository();

  /// 회원별 검토 대기 목록. 처음 조회할 때 시드한다.
  final Map<String, List<RoutineSuggestion>> _pending =
      <String, List<RoutineSuggestion>>{};

  /// 아직 검토하지 않은 **후보**다 — 이미 배정된 개인 운동
  /// (`shared/demo_fixture` 의 `routines`)과 겹치지 않는 것으로 둔다 (#1170).
  ///
  /// 예전에는 `어깨 관절 보호 스트레칭`·`저강도 걷기` 였는데, 그 둘은 배정
  /// 목록에도 있는 운동이라 같은 화면에서 "아직 안 보낸 후보" 와 "이미 보낸
  /// 것" 으로 두 번 나왔다. 같은 운동이 두 상태를 동시에 가질 수는 없다.
  static const List<RoutineSuggestion> _seed = <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-interval',
      name: '가벼운 인터벌 러닝',
      minutes: 30,
      type: '유산소',
      reason: '빠르게 걷다 천천히 걷기를 번갈아 하는 회복 목적 유산소예요. 숨이 차면 속도를 낮추세요.',
      evidence: <String>['혈압 관리 목표', '최근 근력운동 비중 높음'],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-thoracic',
      name: '흉추 회전 스트레칭',
      minutes: 10,
      type: '스트레칭',
      reason: '등 위쪽을 돌려 어깨 부담을 줄이는 스트레칭이에요. 통증이 있으면 멈추세요.',
      evidence: <String>['최근 PT 피드백 반영'],
    ),
    // 근력 후보를 하나 둔다 — 세트·횟수·중량을 묻는 자리가 데모에서도 보여야
    // 그 칸이 실제로 동작하는지 시연에서 확인할 수 있다. (#1321)
    RoutineSuggestion(
      id: 'demo-suggestion-hip-bridge',
      name: '힙 브리지',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 15,
      weight: 0,
      reason: '누워서 엉덩이를 들어 올리는 하체 근력 운동이에요. 허리가 아프면 범위를 줄이세요.',
      evidence: <String>['최근 근력운동 비중 높음'],
    ),
  ];

  List<RoutineSuggestion> _listFor(String memberId) =>
      _pending.putIfAbsent(memberId, () => List<RoutineSuggestion>.of(_seed));

  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async =>
      List<RoutineSuggestion>.unmodifiable(_listFor(memberId));

  @override
  Future<void> approve(
    String suggestionId, {
    String? name,
    int? minutes,
    String? type,
    int? sets,
    int? reps,
    int? holdSeconds,
    double? weight,
    String? reason,
  }) async => _review(suggestionId);

  @override
  Future<void> dismiss(String suggestionId) async => _review(suggestionId);

  /// 검토한 제안을 목록에서 뺀다. 없으면 실서버의 409 와 같은 예외 —
  /// 데모에서도 두 번 누르면 같은 문구가 나와야 한다.
  void _review(String suggestionId) {
    for (final entry in _pending.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((s) => s.id == suggestionId);
      if (entry.value.length != before) return;
    }
    throw RoutineSuggestionAlreadyReviewed(suggestionId);
  }
}

/// Picks the Dio-backed repository, or the demo one for `USE_MOCK_API=true`.
final trainerRoutineSuggestionRepositoryProvider =
    Provider<TrainerRoutineSuggestionRepository>((ref) {
      final config = ref.watch(appConfigProvider);
      if (config.useMockApi) {
        return MockTrainerRoutineSuggestionRepository();
      }
      return DioTrainerRoutineSuggestionRepository(ref.watch(dioProvider));
    }, name: 'trainerRoutineSuggestionRepository');

/// 선택한 회원의 검토 대기 제안.
///
/// 회원별로 갈라 둔다(`family`) — 회원을 바꾸면 그 회원의 목록으로 갱신돼야
/// 하고, 승인·거절 뒤에는 이 provider 를 invalidate 해 다시 읽는다.
final routineSuggestionsProvider =
    FutureProvider.family<List<RoutineSuggestion>, String>((ref, memberId) {
      return ref
          .watch(trainerRoutineSuggestionRepositoryProvider)
          .pending(memberId);
    }, name: 'routineSuggestions');
