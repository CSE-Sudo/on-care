/// 회원이 담당 트레이너에게 내는 주간 피드백과, 트레이너가 보낸 리포트 목록.
/// (#2232)
///
/// 둘 다 **담당 트레이너가 있는 회원**의 기능이다. 트레이너 없이 보는 주간
/// 리포트(포인트 교환, #2022)와는 다른 길이므로 그 provider 를 재사용하지
/// 않는다 — 받는 사람이 다르면 같은 이름의 화면이라도 다른 기능이다.
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
final lastWeekFeedbackProvider = FutureProvider<MemberWeeklyFeedback>((ref) {
  return ref.watch(memberWeeklyFeedbackProvider(manualFeedbackWeek()).future);
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

/// 트레이너가 보낸 리포트 한 건 — 대화에 남은 안내에서 읽는다. (#2232)
///
/// 리포트에는 따로 목록 엔드포인트가 없다. 트레이너가 보낼 때 대화에 안내
/// 메시지 한 건이 남고([CoachMessage.reportWeekStart]), 그것이 곧 보낸 기록이다.
/// 파일명이나 본문으로 추측하지 않는다 — 서버가 실어 보낸 주(월요일)만 본다.
class SentReportNotice {
  /// Creates a notice.
  const SentReportNotice({required this.message, required this.weekStart});

  /// 안내가 실려 온 대화 메시지. 첨부가 있으면 그 PDF 를 연다.
  final CoachMessage message;

  /// 리포트가 가리키는 주의 월요일.
  final DateTime weekStart;

  /// 트레이너가 보낸 시각.
  DateTime get sentAt => message.createdAt;
}

/// 트레이너가 보낸 리포트 목록(최신 → 오래된). (#2232)
///
/// 같은 주 리포트를 두 번 보냈으면 **마지막 것 하나만** 남긴다. 회원이 받은
/// 것은 마지막 글이고, 목록에 같은 주가 두 줄로 서면 어느 것을 열어야 하는지
/// 알 수 없다.
final sentReportNoticesProvider = FutureProvider<List<SentReportNotice>>((
  ref,
) async {
  final List<CoachMessage> chat = await ref
      .watch(memberCoachRepositoryProvider)
      .fetchChat();
  final Map<String, SentReportNotice> latest = <String, SentReportNotice>{};
  for (final CoachMessage message in chat) {
    final DateTime? week = message.reportWeekStart;
    if (week == null) continue;
    final DateTime monday = DateTime(week.year, week.month, week.day);
    final String key = '${monday.year}-${monday.month}-${monday.day}';
    final SentReportNotice? seen = latest[key];
    if (seen != null && seen.sentAt.isAfter(message.createdAt)) continue;
    latest[key] = SentReportNotice(message: message, weekStart: monday);
  }
  final List<SentReportNotice> notices = latest.values.toList()
    ..sort(
      (SentReportNotice a, SentReportNotice b) =>
          b.weekStart.compareTo(a.weekStart),
    );
  return notices;
}, name: 'sentReportNotices');
