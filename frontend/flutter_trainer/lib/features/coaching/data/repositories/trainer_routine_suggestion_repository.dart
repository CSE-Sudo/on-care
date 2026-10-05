import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/core/config/app_config.dart';
import 'package:oncare_trainer/core/network/dio_client.dart';
import 'package:oncare_trainer/core/session/account_scope.dart';
import 'package:oncare_trainer/core/storage/app_database.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_store.dart';
import 'package:oncare_trainer/features/coaching/data/demo_routine_suggestions.dart';
import 'package:oncare_trainer/features/coaching/data/dtos/routine_suggestion_dtos.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/dio_trainer_routine_suggestion_repository.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_routine_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/assigned_routine.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';
import 'package:oncare_trainer/shared/services/locale_provider.dart';

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
/// 아예 보이지 않으므로, 회원마다 후보를 들고 시작하고 승인·거절한 것은
/// 목록에서 지운다 — 실서버와 같은 순서로 화면이 움직인다.
///
/// 시드 회원은 회원마다 다른 후보를 갖는다([forMember], #2668). 예전에는 모든
/// 회원이 같은 세 건·같은 근거 문구였다.
class MockTrainerRoutineSuggestionRepository
    implements TrainerRoutineSuggestionRepository {
  /// Creates the demo repository.
  ///
  /// [languageCode] 는 후보를 **처음 준비하는 순간의** 화면 언어다(#2301).
  /// 실서버가 준비하는 요청의 언어로 이름·사유를 만들어 저장하는 것과 같다 —
  /// 한 번 준비한 후보의 문장은 언어를 바꿔도 그대로이고, 근거는 코드라
  /// 화면 언어를 따른다. 생략하면 한국어다.
  ///
  /// [assignTo] 를 주면 승인한 제안이 그 회원의 배정이 된다 — 실서버에서
  /// 승인하면 배정되는 것과 같다(#2668). [db] 를 주면 검토한 제안이 drift 에
  /// 남아 새로고침해도 다시 나오지 않는다.
  MockTrainerRoutineSuggestionRepository({
    String Function()? languageCode,
    TrainerRoutineRepository? assignTo,
    AppDatabase? db,
  }) : _languageCode = languageCode ?? _korean,
       _routines = assignTo,
       _store = db == null ? null : DemoRoutineStore(db);

  final String Function() _languageCode;
  final TrainerRoutineRepository? _routines;
  final DemoRoutineStore? _store;

  static String _korean() => 'ko';

  /// 회원별 검토 대기 목록. 처음 조회할 때 시드한다.
  final Map<String, List<RoutineSuggestion>> _pending =
      <String, List<RoutineSuggestion>>{};

  /// 아직 검토하지 않은 **후보**다 — 이미 배정된 개인 운동
  /// (`shared/demo_fixture` 의 `routines`)과 겹치지 않는 것으로 둔다 (#1170).
  ///
  /// 예전에는 `어깨 관절 보호 스트레칭`·`저강도 걷기` 였는데, 그 둘은 배정
  /// 목록에도 있는 운동이라 같은 화면에서 "아직 안 보낸 후보" 와 "이미 보낸
  /// 것" 으로 두 번 나왔다. 같은 운동이 두 상태를 동시에 가질 수는 없다.
  ///
  /// 사유는 트레이너가 읽는 판단 재료다 — 이 회원의 어떤 기록 때문에 올라왔나를
  /// 기록 숫자로 말한다(#2579). 서버 `routine_suggestion_service` 와 같은 말투다.
  static const List<RoutineSuggestion> _seed = <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-interval',
      name: '가벼운 인터벌 러닝',
      minutes: 30,
      type: '유산소',
      reason:
          '혈압 관리가 목표인데 최근 2주 운동 240분 중 190분(79%)이 근력이에요. '
          '강도를 오르내리는 유산소로 균형을 맞추기 좋아요.',
      evidence: <String>[
        RoutineEvidence.bloodPressureGoal,
        RoutineEvidence.strengthHeavy,
      ],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-thoracic',
      name: '흉추 회전 스트레칭',
      minutes: 10,
      type: '스트레칭',
      reason: '2일 전 PT 가 있었어요. 다음 수업 전까지 등 위쪽을 풀어 어깨 부담을 덜어 두기 좋아요.',
      evidence: <String>[RoutineEvidence.recentPtFeedback],
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
      reason: '최근 2주 근력 190분이 대부분 기구 운동이에요. 하체는 맨몸으로 가볍게만 이어 가기 좋아요.',
      evidence: <String>[RoutineEvidence.strengthHeavy],
    ),
  ];

  /// [_seed] 의 영어판(#2301). id·시간·유형·근거는 같고 이름·사유만 다르다.
  static const List<RoutineSuggestion> _seedEn = <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-interval',
      name: 'Light interval run',
      minutes: 30,
      type: '유산소',
      reason:
          'Blood pressure is a goal, but 190 of 240 min (79%) in the last '
          '2 weeks was strength. Cardio that varies intensity rebalances it.',
      evidence: <String>[
        RoutineEvidence.bloodPressureGoal,
        RoutineEvidence.strengthHeavy,
      ],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-thoracic',
      name: 'Thoracic rotation stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'There was a PT 2 days ago. Loosening the upper back '
          'eases the shoulders before the next PT.',
      evidence: <String>[RoutineEvidence.recentPtFeedback],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-hip-bridge',
      name: 'Hip bridge',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 15,
      weight: 0,
      reason:
          'Most of the 190 min of strength in the last 2 weeks was on '
          'machines. Keep the lower body light with a bodyweight move.',
      evidence: <String>[RoutineEvidence.strengthHeavy],
    ),
  ];

  /// 이 언어의 데모 후보(김민수의 것). 영어가 아니면 한국어다.
  static List<RoutineSuggestion> seedFor(String languageCode) =>
      languageCode == 'en' ? _seedEn : _seed;

  /// 이 회원의 데모 후보. 시드 회원은 회원별 후보([demoMemberSuggestionsKo])
  /// 를, 그 밖의 회원(김민수·테스트 회원)은 [seedFor] 를 쓴다.
  static List<RoutineSuggestion> forMember(
    String memberId,
    String languageCode,
  ) =>
      (languageCode == 'en'
          ? demoMemberSuggestionsEn
          : demoMemberSuggestionsKo)[memberId] ??
      seedFor(languageCode);

  Future<List<RoutineSuggestion>> _listFor(String memberId) async {
    final Set<String> reviewed =
        await _store?.readReviewedSuggestions() ?? const <String>{};
    final List<RoutineSuggestion>? cached = _pending[memberId];
    if (cached != null) {
      // 전송이 닫은 제안은 이 저장소를 거치지 않고 기억에 남는다(#2747) —
      // 읽을 때마다 걸러야 보낸 제안이 다음 위저드에 다시 뜨지 않는다.
      cached.removeWhere((RoutineSuggestion s) => reviewed.contains(s.id));
      return cached;
    }
    return _pending.putIfAbsent(
      memberId,
      () => <RoutineSuggestion>[
        for (final RoutineSuggestion s in forMember(memberId, _languageCode()))
          if (!reviewed.contains(s.id)) s,
      ],
    );
  }

  @override
  Future<List<RoutineSuggestion>> pending(String memberId) async =>
      List<RoutineSuggestion>.unmodifiable(await _listFor(memberId));

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
  }) async {
    final (String memberId, RoutineSuggestion s) = await _review(suggestionId);
    // 승인한 것은 그 회원의 배정이 된다 — 고친 값이 있으면 고친 대로(#2668).
    // 아무것도 하지 않던 동안에는 목록에서 빠질 뿐 배정 루틴에 들어가지 않았다.
    await _routines?.assignRoutine(
      memberId,
      AssignedRoutine(
        id: '',
        name: name ?? s.name,
        minutes: minutes ?? s.minutes,
        type: type ?? s.type,
        reason: reason ?? s.reason,
        source: 'ai',
        sets: sets ?? s.sets,
        reps: reps ?? s.reps,
        holdSeconds: holdSeconds ?? s.holdSeconds,
        weight: weight ?? s.weight,
      ),
    );
  }

  @override
  Future<void> dismiss(String suggestionId) async {
    await _review(suggestionId);
  }

  /// 검토한 제안을 목록에서 빼고, 그 회원과 제안을 돌려준다. 없으면 실서버의
  /// 409 와 같은 예외 — 데모에서도 두 번 누르면 같은 문구가 나와야 한다.
  Future<(String, RoutineSuggestion)> _review(String suggestionId) async {
    for (final entry in _pending.entries) {
      final int at = entry.value.indexWhere((s) => s.id == suggestionId);
      if (at < 0) continue;
      final RoutineSuggestion s = entry.value.removeAt(at);
      await _store?.addReviewedSuggestion(suggestionId);
      return (entry.key, s);
    }
    throw RoutineSuggestionAlreadyReviewed(suggestionId);
  }
}

/// Picks the Dio-backed repository, or the demo one for `USE_MOCK_API=true`.
final trainerRoutineSuggestionRepositoryProvider =
    Provider<TrainerRoutineSuggestionRepository>((ref) {
      ref.watch(accountScopeProvider); // 계정이 바뀌면 새로 만든다(#2285).
      final config = ref.watch(appConfigProvider);
      if (config.useMockApi) {
        return MockTrainerRoutineSuggestionRepository(
          languageCode: () =>
              ref.read(trainerResolvedLocaleProvider).languageCode,
          assignTo: ref.watch(trainerRoutineRepositoryProvider),
          db: ref.watch(appDatabaseProvider),
        );
      }
      return DioTrainerRoutineSuggestionRepository(ref.watch(dioProvider));
    }, name: 'trainerRoutineSuggestionRepository');

/// 선택한 회원의 검토 대기 제안.
///
/// 회원별로 갈라 둔다(`family`) — 회원을 바꾸면 그 회원의 목록으로 갱신돼야
/// 하고, 승인·거절 뒤에는 이 provider 를 invalidate 해 다시 읽는다.
final routineSuggestionsProvider = FutureProvider.autoDispose
    .family<List<RoutineSuggestion>, String>((ref, memberId) {
      keepAliveForAccount(ref);
      return ref
          .watch(trainerRoutineSuggestionRepositoryProvider)
          .pending(memberId);
    }, name: 'routineSuggestions');
