/// 회원이 담당 트레이너에게 내는 주간 피드백과, 트레이너에게 받은 리포트 목록.
/// (#2232)
///
/// 피드백은 **담당 트레이너가 있는 회원**의 기능이다. 받은 리포트는 담당이
/// 없어진 뒤에도 남는다(#3348). 트레이너 없이 보는 주간 리포트(포인트 교환,
/// #2022)와는 다른 길이므로 그 provider 를 재사용하지 않는다 — 받는 사람이
/// 다르면 같은 이름의 화면이라도 다른 기능이다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/domain/entities/weekly_feedback.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_coach_providers.dart';

/// 그 주에 내가 낸 답. 아직 안 냈으면 `submitted == false` 인 빈 답이다.
final memberWeeklyFeedbackProvider =
    FutureProvider.family<MemberWeeklyFeedback, DateTime>((
      ref,
      DateTime weekStart,
    ) {
      return ref
          .watch(memberCoachRepositoryProvider)
          .fetchWeeklyFeedback(weekStart: weekStart);
    }, name: 'memberWeeklyFeedback');

/// MY 탭이 보여 주는 한 주 — **직전 주**뿐이다. (#2232)
///
/// 더 옛 주를 쌓아 보여 줄 수도 있지만, 회원이 되돌아볼 이유가 있는 것은 방금
/// 낸 답 하나다. 그보다 옛 답은 트레이너가 이미 읽고 다음 주 처방에 썼으니,
/// 회원 화면에서 그것은 목록이 아니라 지나간 일이다.
///
/// 화면을 닫으면 놓는다 — 붙들고 있으면 처음 읽은 주에 머물러, 주가 바뀐 뒤
/// `지금 피드백 보내기` 가 지난 주를 연다(#3244). 주마다의 답은
/// [memberWeeklyFeedbackProvider] 가 따로 들고 있어 다시 열어도 새로 받지 않는다.
final lastWeekFeedbackProvider =
    FutureProvider.autoDispose<MemberWeeklyFeedback>((ref) {
      return ref.watch(
        memberWeeklyFeedbackProvider(manualFeedbackWeek()).future,
      );
    }, name: 'lastWeekFeedback');

/// 이번에 들어왔을 때 물어볼 주 — 물을 것이 없으면 null. (#2232)
///
/// 조건은 셋이 모두 맞아야 한다.
///  1. 담당 트레이너가 있다 — 받는 사람이 없는 피드백은 아무 데도 닿지 않는다.
///  2. 오늘이 묻는 날이다([askableWeek]: 일요일, 그리고 월요일 한 번 더).
///  3. 그 주에 아직 답하지 않았다.
///
/// 이 세션에서 `나중에` 를 누른 뒤에는 묻지 않는다. 같은 날 앱을 몇 번 열어도
/// 매번 창이 뜨면, 회원은 답하기보다 닫는 법을 먼저 익힌다.
final weeklyFeedbackPromptProvider = FutureProvider<DateTime?>((ref) async {
  if (ref.watch(weeklyFeedbackDismissedProvider)) return null;
  final DateTime? week = askableWeek();
  if (week == null) return null;
  final MemberCoach? coach = await ref.watch(memberCoachProvider.future);
  if (coach == null) return null;
  final MemberWeeklyFeedback feedback = await ref.watch(
    memberWeeklyFeedbackProvider(week).future,
  );
  return feedback.submitted ? null : week;
}, name: 'weeklyFeedbackPrompt');

/// 이 세션에서 물음을 한 번 물렸는가. 앱을 다시 켜면 또 묻는다 — 일요일 하루
/// 안에 마음이 바뀔 수 있고, 안 낸 주는 트레이너에게 그대로 빈칸이다.
final weeklyFeedbackDismissedProvider = StateProvider<bool>(
  (ref) => false,
  name: 'weeklyFeedbackDismissed',
);

/// 답을 보낸다. 성공하면 그 주와 MY 탭이 함께 다시 읽힌다.
class WeeklyFeedbackSender {
  /// Creates a sender.
  const WeeklyFeedbackSender(this._ref);

  final Ref _ref;

  /// [weekStart] 주의 답을 보낸다. 같은 주에 다시 보내면 덮어쓴다.
  Future<MemberWeeklyFeedback> send({
    required DateTime weekStart,
    required WeekCondition condition,
    required WeekIntensity intensity,
    String painArea = '',
    DateTime? painOn,
    String note = '',
  }) async {
    final MemberWeeklyFeedback saved = await _ref
        .read(memberCoachRepositoryProvider)
        .saveWeeklyFeedback(
          weekStart: weekStart,
          condition: condition,
          intensity: intensity,
          painArea: painArea,
          painOn: painOn,
          note: note,
        );
    // 보낸 주, MY 탭의 직전 주, 그리고 물음 자체를 다시 읽는다 — 보내고 나서도
    // 같은 물음이 남아 있으면 보낸 것이 맞는지 알 수 없다.
    _ref
      ..invalidate(memberWeeklyFeedbackProvider)
      ..invalidate(lastWeekFeedbackProvider)
      ..invalidate(weeklyFeedbackPromptProvider);
    return saved;
  }
}

final weeklyFeedbackSenderProvider = Provider<WeeklyFeedbackSender>(
  WeeklyFeedbackSender.new,
  name: 'weeklyFeedbackSender',
);

/// 받은 리포트 목록의 지금 모습 — 받아 둔 줄과, 더 있는지. (#3348)
class ReceivedReportsState {
  /// Creates a state.
  const ReceivedReportsState({
    required this.reports,
    this.nextBefore,
    this.loadingMore = false,
  });

  /// 받아 둔 리포트(최신 주 → 오래된 주).
  final List<ReceivedReport> reports;

  /// 더 앞선 주가 있으면 그 커서. 없으면 null — 끝까지 받았다.
  final DateTime? nextBefore;

  /// 앞 쪽을 받는 중인가.
  final bool loadingMore;

  /// 더 받을 것이 남았는가.
  bool get hasMore => nextBefore != null;
}

/// 트레이너에게 받은 리포트 목록(최신 주 → 오래된 주). (#2232, #3348)
///
/// 서버의 받은 리포트 목록 하나를 읽는다. 예전에는 대화를 **끝까지** 읽어 그 안의
/// 안내를 골랐다(#2643) — 대화가 길수록 요청이 늘었고, 담당이 해제되면 대화를
/// 읽을 수 없어 받은 리포트가 통째로 사라졌다. 받은 리포트는 대화가 아니라
/// 회원에게 남는 기록이라, 담당이 없어도 그대로 선다.
///
/// autoDispose 다. 화면에 들어올 때마다 새로 읽고, 채팅이 폴링으로 새 리포트
/// 안내를 받으면 다시 읽는다(`TrainerChatPage`).
class ReceivedReportsController
    extends AutoDisposeAsyncNotifier<ReceivedReportsState> {
  @override
  Future<ReceivedReportsState> build() async {
    final ReceivedReportsPage page = await ref
        .watch(memberCoachRepositoryProvider)
        .fetchReceivedReports();
    return ReceivedReportsState(
      reports: page.reports,
      nextBefore: page.nextBefore,
    );
  }

  /// 더 앞선 주를 한 쪽 더 받아 뒤에 잇는다.
  ///
  /// 실패해도 받아 둔 줄은 그대로 둔다 — 한 해 전 리포트를 못 읽었다고 방금
  /// 보던 목록까지 오류 화면으로 바꿀 이유가 없다. `더 보기` 가 남아 다시 누를
  /// 수 있다.
  Future<void> loadMore() async {
    final ReceivedReportsState? current = state.valueOrNull;
    final DateTime? cursor = current?.nextBefore;
    if (current == null || cursor == null || current.loadingMore) return;
    state = AsyncData<ReceivedReportsState>(
      ReceivedReportsState(
        reports: current.reports,
        nextBefore: cursor,
        loadingMore: true,
      ),
    );
    try {
      final ReceivedReportsPage page = await ref
          .read(memberCoachRepositoryProvider)
          .fetchReceivedReports(before: cursor);
      final Set<String> seen = <String>{
        for (final ReceivedReport report in current.reports) report.id,
      };
      state = AsyncData<ReceivedReportsState>(
        ReceivedReportsState(
          reports: <ReceivedReport>[
            ...current.reports,
            for (final ReceivedReport report in page.reports)
              if (seen.add(report.id)) report,
          ],
          nextBefore: page.nextBefore,
        ),
      );
    } catch (_) {
      state = AsyncData<ReceivedReportsState>(
        ReceivedReportsState(reports: current.reports, nextBefore: cursor),
      );
    }
  }
}

final receivedReportsProvider =
    AsyncNotifierProvider.autoDispose<
      ReceivedReportsController,
      ReceivedReportsState
    >(ReceivedReportsController.new, name: 'receivedReports');
