import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/features/benefits/presentation/controllers/activity_calendar_providers.dart';
import 'package:oncare/features/benefits/presentation/controllers/challenge_providers.dart';
import 'package:oncare/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/streak_shield_providers.dart';
import 'package:oncare/features/my_health/presentation/controllers/my_health_controller.dart';
import 'package:oncare/shared/services/record_span_provider.dart';

/// provider 하나를 비우는 함수 — `WidgetRef.invalidate`·`Ref.invalidate`·
/// `ProviderContainer.invalidate` 를 그대로 넘긴다.
typedef ProviderInvalidator = void Function(ProviderOrFamily provider);

/// 운동 기록이 바뀐 뒤 함께 달라지는 것들. (#2629, #2631, #2634)
///
/// 테스트가 대상 목록을 그대로 확인할 수 있도록 밖에 둔다.
final List<ProviderOrFamily> kExerciseChangeRefreshTargets = <ProviderOrFamily>[
  // 이번 주 — 목록·통계·그래프. `전체` 그래프도 이 값을 watch 한다.
  exerciseWeekProvider,
  // 지난 주 — 지난 주 하루 화면과 주간 리포트의 지난 주 집계(#2629).
  // 수정은 옛 날짜와 새 날짜가 다른 주일 수 있어 family 전체를 비운다.
  // 화면에 붙어 있는 주만 다시 읽히고, 나머지는 다음에 볼 때 읽힌다.
  exercisePastWeekProvider,
  // AI 맞춤 조언 — 기간마다 따로 선 값 전부(#2631).
  exerciseAdviceProvider,
  // MY 기록 달력과 연속 기록 보호권(#1788, #2075, #2634).
  activityCalendarProvider,
  myStreakShieldsProvider,
  // 포인트 잔액(#1786)과 주간 챌린지 진행 — 운동한 날 수(#1789, #2634).
  myHealthStateProvider,
  weeklyChallengeProvider,
  // 첫 기록일 — 더 이른 날짜로 적거나 첫 기록을 지우면 `전체` 가 달라진다.
  recordSpanProvider,
];

/// 운동 기록을 **저장·수정·삭제**하거나 추천 개인운동을 **완료·완료 취소**한
/// 뒤에 부른다. (#2634)
///
/// 예전에는 경로마다 비울 목록을 따로 적어, 저장은 활동 달력을 비우는데 삭제는
/// 빠지고, 새 추가만 주간 챌린지를 비우고 날짜를 옮긴 수정은 빠지는 식으로
/// 한쪽씩 어긋났다. 다섯 경로가 이 함수 하나를 부르면 빠지는 자리가 없다.
///
/// 보고 있는 화면이 없는 provider 는 비워도 요청이 나가지 않는다 — 한 번에
/// 비워도 왕복이 늘지 않는다.
void refreshAfterExerciseChange(ProviderInvalidator invalidate) {
  for (final ProviderOrFamily target in kExerciseChangeRefreshTargets) {
    invalidate(target);
  }
}

/// 운동 기록을 바꾸는 요청을 보내고 [refreshAfterExerciseChange] 까지 하는 곳.
/// (#2879, #3096)
///
/// 기록 시트가 저장 뒤에 직접 비우면, 저장 중에 시트를 내렸을 때 `mounted` 가
/// 거짓이 되어 비우기를 건너뛰었다 — 서버에는 기록이 있는데 주간 그래프·AI
/// 조언·주간 챌린지는 옛 값이었다. 비우기를 시트가 아니라 앱 수명의 provider 가
/// 하게 해 시트 생명주기와 떼어 둔다.
class ExerciseChangeRunner {
  ExerciseChangeRunner(this._ref);

  final Ref _ref;

  /// [change] 를 보내고, 성공하든 실패하든 운동 기록에 딸린 캐시를 비운다.
  /// 결과는 그대로 돌려주고 예외는 그대로 올린다. (#3096)
  ///
  /// 실패해도 비우는 까닭: 한 [change] 안에서 여러 건을 고치다(날짜 옮기기·
  /// 여러 상자 저장) 두 번째에서 실패하면 첫 번째 수정은 이미 서버에 있다.
  /// 단건이 실패한 경우는 비워도 같은 값을 다시 읽을 뿐이라 해가 없다.
  Future<T> run<T>(
    Future<T> Function(ExerciseRepository repository) change,
  ) async {
    try {
      return await change(_ref.read(exerciseRepositoryProvider));
    } finally {
      refreshAfterExerciseChange(_ref.invalidate);
    }
  }
}

final Provider<ExerciseChangeRunner> exerciseChangeRunnerProvider =
    Provider<ExerciseChangeRunner>(
      ExerciseChangeRunner.new,
      name: 'exerciseChangeRunner',
    );

/// 운동 탭 헬스장 영역이 들고 있는 서버 값. (#2856)
///
/// 넷 다 autoDispose 가 아니라서 앱을 켠 뒤 처음 읽은 값이 계속 남는다.
/// 트레이너가 웹에서 예약을 취소하거나 다른 회원이 자리를 잡거나 연결이
/// 해제돼도 회원 앱은 옛 값을 보여 줬다. 운동 탭에 다시 들어올 때와 앱이
/// 복귀할 때 [refreshGymTabData] 로 함께 비운다.
///
/// [trainerSlotsProvider] 는 family 전체를 비운다 — 화면에 붙은 트레이너의
/// 자리만 다시 읽히고 나머지는 다음에 볼 때 읽힌다.
///
/// 테스트가 대상 목록을 그대로 확인할 수 있도록 밖에 둔다.
final List<ProviderOrFamily> kGymTabRefreshTargets = <ProviderOrFamily>[
  myGymProvider,
  myTrainerProvider,
  // `다음 PT` 태그는 이 값과 코치 일정을 합쳐 계산한다 — 셸이 코치 일정과
  // 같은 자리에서 함께 비워야 둘이 엇갈리지 않는다.
  myReservationsProvider,
  trainerSlotsProvider,
];

/// 운동 탭 재진입·앱 복귀 때 헬스장 영역을 다시 읽게 한다. (#2856)
///
/// 비워도 이전 값은 남아 있어(재조회 중 `valueOrNull`), 카드가 비었다가
/// 다시 그려지는 깜빡임은 없다. 보고 있는 화면이 없는 provider 는 요청도
/// 나가지 않는다.
void refreshGymTabData(ProviderInvalidator invalidate) {
  for (final ProviderOrFamily target in kGymTabRefreshTargets) {
    invalidate(target);
  }
}
