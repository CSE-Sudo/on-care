import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/clients/domain/entities/client_exercise_week.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/shared/exercise_burn_goals.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';
import 'package:oncare_trainer/shared/services/member_health_profile_provider.dart';

/// ④ 운동 추세가 읽는 키 — 누구의, 어느 주로 끝나는 여덟 주인가.
typedef ReportTrendKey = ({String clientId, DateTime weekStart});

/// [ReportTrendKey] 로 끝나는 [kReportTrendWeeks] 주치 운동 실적. (#2232)
///
/// 주를 **한꺼번에** 부른다. 하나씩 기다리면 왕복이 여덟 번 줄줄이 이어져,
/// 카드가 늦게 서는 만큼 트레이너는 아래 절반이 비어 있는 화면을 본다.
///
/// `autoDispose` 인 까닭은 다른 리포트 provider 와 같다 — 고객·주를 옮겨
/// 다니는 화면이라 남겨 두면 본 적 있는 모든 주가 메모리에 쌓인다.
final reportTrendProvider = FutureProvider.autoDispose
    .family<ReportTrend, ReportTrendKey>((ref, key) async {
      final ClientRepository repository = ref.watch(clientRepositoryProvider);
      // 목표는 회원이 MY 에서 정한 값이다 — 읽는 중이거나 실패하면 회원 앱과
      // 같은 기본값으로 그린다. 목표 때문에 추세가 막히지는 않게 한다.
      //
      // **await 앞에서** 읽는다. 뒤로 미루면 의존이 늦게 걸려 provider 가
      // 다시 계산되고, 그 계산이 또 늦게 의존을 걸어 화면이 멎지 않는다.
      final ExerciseBurnGoals goals = ExerciseBurnGoals.fromProfile(
        ref.watch(memberHealthProfileProvider(key.clientId)).valueOrNull,
      );
      final List<DateTime> mondays = <DateTime>[
        for (int back = kReportTrendWeeks - 1; back >= 0; back--)
          DateTime(
            key.weekStart.year,
            key.weekStart.month,
            key.weekStart.day - back * 7,
          ),
      ];
      final List<ClientExerciseWeek> weeks =
          await Future.wait(<Future<ClientExerciseWeek>>[
            for (final DateTime monday in mondays)
              repository.fetchExerciseWeek(key.clientId, weekStart: monday),
          ]);
      return ReportTrend(weeks: reportTrendWeeks(mondays, weeks), goals: goals);
    });
