import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/benefits/domain/entities/weekly_report_purchase.dart';
import 'package:oncare/features/benefits/presentation/controllers/benefits_providers.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/member_report_sheet_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/repositories/member_coach_repository.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';
import 'package:oncare_report/oncare_report.dart';

/// 결과지 자료를 어디서 읽는가 — 실서버 또는 데모. (#2652)
///
/// 다른 회원 코치 저장소와 같은 스위치(`useMockApi`)를 쓴다.
final memberReportSheetRepositoryProvider =
    Provider<MemberReportSheetRepository>((ref) {
      if (ref.watch(appConfigProvider).useMockApi) {
        return DemoMemberReportSheetRepository(
          canOpen: (DateTime monday) => demoReportWeekOpens(
            monday,
            coach: ref.read(memberCoachRepositoryProvider),
            purchases: ref.read(benefitsRepositoryProvider).fetchWeeklyReports,
          ),
        );
      }
      return DioMemberReportSheetRepository(
        ref.watch(dioProvider),
        exercise: ref.watch(exerciseRepositoryProvider),
      );
    }, name: 'memberReportSheetRepository');

/// 데모에서 [monday] 주 리포트를 열 수 있는가 — 서버 판정의 대역. (#3366)
///
/// 서버와 같은 두 근거를 본다. **받은 주**는 데모 저장소의 받은 리포트 목록
/// ([MemberCoachRepository.fetchReceivedReports], #3348)이고, **산 주**는 목업
/// 인터셉터의 데모 원장이 답하는 `GET /me/weekly-reports` 다. 한쪽을 읽지 못하면
/// 그쪽은 없는 것으로 본다. 받은 주는 담당이 해제된 뒤에도 남는다.
Future<bool> demoReportWeekOpens(
  DateTime monday, {
  required MemberCoachRepository coach,
  required Future<WeeklyReportPurchases> Function() purchases,
}) async {
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  try {
    final WeeklyReportPurchases bought = await purchases();
    if (bought.weeks.any((DateTime week) => sameDay(week, monday))) return true;
  } catch (_) {
    // 산 주를 읽지 못했다 — 받은 주로 넘어간다.
  }
  try {
    // 받은 리포트 목록을 쪽마다 넘겨 본다 — 그 주에 닿았거나 지나쳤으면 멈춘다.
    DateTime? before;
    do {
      final ReceivedReportsPage page = await coach.fetchReceivedReports(
        before: before,
      );
      if (page.reports.any(
        (ReceivedReport r) => sameDay(r.weekStart, monday),
      )) {
        return true;
      }
      final DateTime? next = page.nextBefore;
      // 커서가 앞으로 나가지 않는 대역을 만나도 멈춘다.
      if (next == null || (before != null && !next.isBefore(before))) break;
      before = next;
    } while (before.isAfter(monday));
    return false;
  } catch (_) {
    return false;
  }
}

/// `WidgetRef.read` 와 `ProviderContainer.read` 를 함께 받는 모양.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// 트레이너가 보낸 리포트가 가리키는 주의 결과지 자료. (#1600, #2652)
///
/// 예전에는 운동 탭·식단 탭·PT 일정의 값을 모아 회원 앱만의 문서를 세웠다. 그
/// 문서는 트레이너 웹 결과지와 구성·수치가 달라, 같은 주를 두 앱이 다르게
/// 말했다. 지금은 트레이너 웹과 같은 자료를 같은 규칙으로 읽는다.
///
/// provider 로 캐시하지 않는다 — 누를 때마다 한 번 읽는 값이다.
///
/// [messageId] 는 그 리포트를 실어 온 전송 메시지다(#3349). 서버가 보낼 때 굳힌
/// 값을 그 메시지로 찾는다. 포인트로 받은 리포트는 주만으로 찾으니 비운다.
Future<ReportSheetInputs> loadMemberReportSheet(
  ProviderRead read, {
  required DateTime weekStart,
  required String languageCode,
  String? messageId,
}) async {
  // 목표를 못 읽어도 결과지는 선다 — 트레이너 웹과 같은 기본값으로 견준다.
  final UserProfile? profile = await read(
    profileProvider.future,
  ).then<UserProfile?>((UserProfile p) => p, onError: (Object _) => null);
  return read(memberReportSheetRepositoryProvider).fetch(
    weekStart: weekStart,
    languageCode: languageCode,
    goals: reportSheetGoalsOf(profile),
    messageId: messageId,
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
