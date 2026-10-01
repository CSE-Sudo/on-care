import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/member_report_sheet_repository.dart';
import 'package:oncare_report/oncare_report.dart';

/// 결과지 자료를 어디서 읽는가 — 실서버 또는 데모. (#2652)
///
/// 다른 회원 코치 저장소와 같은 스위치(`useMockApi`)를 쓴다.
final memberReportSheetRepositoryProvider =
    Provider<MemberReportSheetRepository>((ref) {
      if (ref.watch(appConfigProvider).useMockApi) {
        return DemoMemberReportSheetRepository();
      }
      return DioMemberReportSheetRepository(
        ref.watch(dioProvider),
        exercise: ref.watch(exerciseRepositoryProvider),
      );
    }, name: 'memberReportSheetRepository');

/// `WidgetRef.read` 와 `ProviderContainer.read` 를 함께 받는 모양.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// 트레이너가 보낸 리포트가 가리키는 주의 결과지 자료. (#1600, #2652)
///
/// 예전에는 운동 탭·식단 탭·PT 일정의 값을 모아 회원 앱만의 문서를 세웠다. 그
/// 문서는 트레이너 웹 결과지와 구성·수치가 달라, 같은 주를 두 앱이 다르게
/// 말했다. 지금은 트레이너 웹과 같은 자료를 같은 규칙으로 읽는다.
///
/// provider 로 캐시하지 않는다 — 누를 때마다 한 번 읽는 값이고, 캐시하면 오늘
/// 더한 기록이 이번 주 리포트에 늦게 닿는다.
Future<ReportSheetInputs> loadMemberReportSheet(
  ProviderRead read, {
  required DateTime weekStart,
  required String languageCode,
}) async {
  // 목표를 못 읽어도 결과지는 선다 — 트레이너 웹과 같은 기본값으로 견준다.
  final UserProfile? profile = await read(
    profileProvider.future,
  ).then<UserProfile?>((UserProfile p) => p, onError: (Object _) => null);
  return read(memberReportSheetRepositoryProvider).fetch(
    weekStart: weekStart,
    languageCode: languageCode,
    goals: reportSheetGoalsOf(profile),
  );
}

/// 회원이 MY 에서 정한 주간 운동 목표. 비어 있는 칸은 권장값이다.
///
/// 트레이너 웹 `ExerciseBurnGoals.fromProfile` 과 같은 규칙이다 — 같은 회원의
/// 목표를 두 앱이 다른 값으로 읽으면 추이의 달성률이 어긋난다.
ReportSheetGoals reportSheetGoalsOf(UserProfile? profile) => ReportSheetGoals(
  weeklyCardioMinutes:
      profile?.weeklyCardioMinutes?.toDouble() ?? kReportWeeklyCardioMinutes,
  weeklyStrengthSets:
      profile?.weeklyStrengthSets?.toDouble() ?? kReportWeeklyStrengthSets,
  weeklyStretchingMinutes:
      profile?.weeklyFlexibilityMinutes?.toDouble() ??
      kReportWeeklyStretchingMinutes,
);
