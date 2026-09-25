import 'package:oncare_trainer/features/dashboard/domain/churn_risk.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// A kind of bullet on the "활동 피드백" card's 트레이너 활동 피드백 list.
enum ActivityFeedbackKind {
  /// 운동 목표 미달·배정 루틴 미수행 회원의 난이도 조정 안내(#2244).
  difficultyReview,

  /// 기록이 끊긴 회원에게 먼저 연락하라는 안내(`기록 끊김` 신호).
  inactiveSevenDays,

  /// 식단 신호(칼로리 이탈·단백질 부족)가 있는데 피드백을 받지 못한 회원.
  dietFeedbackPending;

  /// Short headline shown next to the leading icon.
  String title(AppLocalizations l) => switch (this) {
    ActivityFeedbackKind.difficultyReview => l.dashActivityDifficultyTitle,
    ActivityFeedbackKind.inactiveSevenDays => l.dashActivityInactiveTitle,
    ActivityFeedbackKind.dietFeedbackPending => l.dashActivityDietFeedbackTitle,
  };

  /// The full explanatory sentence — [names] woven in naturally ("{names}
  /// 고객이 ~해요") rather than tacked on as a separate "대상:" line.
  String description(AppLocalizations l, String names) => switch (this) {
    ActivityFeedbackKind.difficultyReview => l.dashActivityDifficultyDesc(
      names,
    ),
    ActivityFeedbackKind.inactiveSevenDays => l.dashActivityInactiveDesc(names),
    ActivityFeedbackKind.dietFeedbackPending => l.dashActivityDietFeedbackDesc(
      names,
    ),
  };

  /// A short clause telling the trainer *where* to act — woven into the
  /// end of [description] so the recommendation reads as part of the same
  /// sentence, not a separate instruction.
  String recommendation(AppLocalizations l) => switch (this) {
    ActivityFeedbackKind.difficultyReview => l.dashActivityRecommendRoutine,
    ActivityFeedbackKind.inactiveSevenDays => l.dashActivityRecommendChat,
    ActivityFeedbackKind.dietFeedbackPending => l.dashActivityRecommendDiet,
  };

  /// The destination tab's own name — the CTA is a short "프로그램 >" link,
  /// not a full sentence like "AI 루틴 만들러 가기". 이행률/이탈 위험은
  /// 각각 프로그램·메시지라는 독립된 탭으로 가서 그 탭 이름을 그대로
  /// 쓰지만, 식단 피드백 미완료는 고객 상세(식단 섹션)로 가므로 "식단"이
  /// 아니라 "고객"이 실제 목적지다.
  String tabLabel(AppLocalizations l) => switch (this) {
    ActivityFeedbackKind.difficultyReview => l.dashActivityTabProgram,
    ActivityFeedbackKind.inactiveSevenDays => l.dashActivityTabChat,
    ActivityFeedbackKind.dietFeedbackPending => l.dashActivityTabClient,
  };
}

/// One bullet on the "활동 피드백" card's 트레이너 활동 피드백 list.
class ActivityFeedbackItem {
  /// Creates a feedback bullet.
  const ActivityFeedbackItem({
    required this.kind,
    required this.clientNames,
    required this.clientIds,
  });

  /// What this bullet is about.
  final ActivityFeedbackKind kind;

  /// Who triggered it — an empty list is a valid "none right now".
  final List<String> clientNames;

  /// Same order as [clientNames] — the CTA jumps to [clientIds].first, the
  /// client most worth checking first (`buildActivityFeedback`'s 로스터
  /// 순서 그대로).
  final List<String> clientIds;

  /// How many clients triggered this bullet.
  int get count => clientNames.length;
}

/// Builds the "활동 피드백" card's activity-feedback bullets.
///
/// 무엇이 문제인지는 회원 목록 배지와 같은 PT 관리 신호가 정한다(#2244) —
/// 목록에서 `운동 목표 28%` 인 회원이 여기서 다른 기준으로 불리지 않게.
/// "최근 7일 트레이너 피드백 없음" 만 [computeChurnSignals] 에서 가져온다 —
/// 트레이너 자신의 활동이라 서버 신호에 없는 값이다.
List<ActivityFeedbackItem> buildActivityFeedback({
  required List<TrainerClient> clients,
  required Map<String, List<ScheduleSession>> recentSessionsByClient,
  required Map<String, int> unread,
  required DateTime now,
}) {
  final difficultyReview = <TrainerClient>[];
  final inactiveSevenDays = <TrainerClient>[];
  final dietFeedbackPending = <TrainerClient>[];

  for (final client in clients.where((c) => c.active)) {
    final signals = computeChurnSignals(
      client,
      recentSessions:
          recentSessionsByClient[client.id] ?? const <ScheduleSession>[],
      unreadCount: unread[client.id] ?? 0,
      now: now,
    );

    final kinds = <ClientSignalKind>{for (final s in client.signals) s.kind};

    if (kinds.contains(ClientSignalKind.exerciseGoalLow) ||
        kinds.contains(ClientSignalKind.routineMissed)) {
      difficultyReview.add(client);
    }

    if (kinds.contains(ClientSignalKind.recordGap)) {
      inactiveSevenDays.add(client);
    }

    if (kinds.any((k) => k.isDiet) &&
        signals.contains(ChurnSignal.noRecentFeedback)) {
      dietFeedbackPending.add(client);
    }
  }

  return <ActivityFeedbackItem>[
    _item(ActivityFeedbackKind.difficultyReview, difficultyReview),
    _item(ActivityFeedbackKind.inactiveSevenDays, inactiveSevenDays),
    _item(ActivityFeedbackKind.dietFeedbackPending, dietFeedbackPending),
  ];
}

ActivityFeedbackItem _item(
  ActivityFeedbackKind kind,
  List<TrainerClient> clients,
) => ActivityFeedbackItem(
  kind: kind,
  clientNames: <String>[for (final c in clients) c.name],
  clientIds: <String>[for (final c in clients) c.id],
);
