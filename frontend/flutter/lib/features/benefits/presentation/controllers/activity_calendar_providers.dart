import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/core/points/demo_streak_shields.dart';
import 'package:oncare/features/benefits/data/repositories/dio_activity_calendar_repository.dart';
import 'package:oncare/features/benefits/data/repositories/mock_activity_calendar_repository.dart';
import 'package:oncare/features/benefits/domain/entities/activity_calendar.dart';
import 'package:oncare/features/benefits/domain/repositories/activity_calendar_repository.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';

/// 기록 그래프 저장소. (#2075, #2076)
///
/// 데모 모드는 목업 운동 저장소·목업 식단과 같은 기록, 같은 보호권·그래프 색 원장을
/// 본다 — 교환한 색이 바로 그래프에 보이고 보호한 날이 칸에 뜬다.
final activityCalendarRepositoryProvider = Provider<ActivityCalendarRepository>(
  (ref) {
    if (ref.watch(appConfigProvider).useMockApi) {
      // 식단·색·보호권은 목업 API 가 답하고(운동만 목업 저장소에 있다), 그
      // 답에 운동을 덧씌운다.
      return MockActivityCalendarRepository(
        base: DioActivityCalendarRepository(ref.watch(dioProvider)),
        shields: ref.watch(demoStreakShieldBookProvider),
        exercise: ref.watch(exerciseRepositoryProvider),
      );
    }
    return DioActivityCalendarRepository(ref.watch(dioProvider));
  },
  name: 'activityCalendarRepository',
);

/// 포인트 화면의 기록 그래프 — 최근 1년.
///
/// 구간을 주지 않는다: 서버 기본이 곧 화면이 그리는 격자(오늘로 끝나는 371일 =
/// 53주)다. 앱이 날 수를 따로 들고 있으면 서버가 눈금을 바꿀 때 화면만 옛 길이로
/// 남는다.
///
/// auto-dispose 가 아니다: 데모에서 이 값을 만들려면 한 해치 기록을 읽어야 해서,
/// 화면을 나갔다 들어올 때마다 버리면 그 순회를 매번 다시 한다. 바뀌는 계기는
/// 정해져 있고(교환·보호권 사용·색 바꾸기·기록 추가·세션 전환) 그때마다 부르는
/// 쪽이 `invalidate` 하므로, 들고 있어도 낡은 값을 보여 주지 않는다 — 보호권
/// (`myStreakShields`)과 같은 규약이다.
final activityCalendarProvider = FutureProvider<ActivityCalendar>(
  (ref) => ref.watch(activityCalendarRepositoryProvider).fetch(),
  name: 'activityCalendar',
);
