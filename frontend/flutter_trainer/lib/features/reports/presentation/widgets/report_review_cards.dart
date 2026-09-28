import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_card_header.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_exercise_trend.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_macro_bars.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 편집기 ① 확인 단계의 카드 묶음 — 회원의 답 · 한 주 격자 · 운동 추세.
///
/// 편집기와 보낸 리포트 화면, 회원에게 나가는 PDF 가 **이 위젯 하나**를 그린다
/// (#2425, #2424). 같은 한 주를 자리마다 다른 그림으로 되짚으면 "그때 이걸 보고
/// 이렇게 썼다" 를 확인할 수 없다. 모양을 흉내 낸 사본을 두면 한쪽만 고쳐지는
/// 날이 오므로, 그림 자체를 나눠 쓴다.
///
/// 입력이 없다 — 읽는 단계의 카드라 어디에 얹어도 그대로 읽기 전용이다.
///
/// 확인 단계에는 요약을 두지 않는다. AI 가 내린 결론을 먼저 읽으면 자료를 보는
/// 일이 **그 결론이 맞는지 확인하는 일**로 바뀌어, 요약이 짚지 않은 것은
/// 트레이너도 짚지 않게 된다. 요약은 글을 쓰는 자리의 출발점이므로 ② 작성에
/// 선다. (#2232)
class ReportReviewCards extends StatelessWidget {
  /// Creates the review-stage cards of [report].
  const ReportReviewCards({
    super.key,
    required this.report,
    this.calorieBaseline,
    this.weekNav,
    this.sections = ReportReviewSection.values,
  });

  final WeeklyReport report;

  /// 직전 넉 주의 하루 평균 섭취 칼로리 — ① 칼로리 줄이 견주는 `평소`.
  /// 아직 안 읽혔거나 견줄 기록이 없으면 null 이다.
  final double? calorieBaseline;

  /// 한 주 카드 제목 줄에 놓을 주 이동. 편집기만 둔다 — 보낸 리포트와 PDF 는
  /// 이미 정해진 한 주라 옮겨 갈 곳이 없다.
  final Widget? weekNav;

  /// 그릴 카드와 차례. 화면은 셋을 다 그린다. PDF 는 쪽을 카드 경계에서
  /// 나누려고 카드를 하나씩 따로 굽는다(#2424) — 같은 위젯에서 한 장씩
  /// 떼어 내므로 모양은 화면과 같다.
  final List<ReportReviewSection> sections;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final List<Widget> cards = <Widget>[
      for (final ReportReviewSection section in sections)
        switch (section) {
          ReportReviewSection.member => _member(),
          ReportReviewSection.week => _week(l),
          ReportReviewSection.trend => _trend(l),
        },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < cards.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: OnCareSpacing.s16),
          cards[i],
        ],
      ],
    );
  }

  Widget _member() =>
      // ① 회원이 낸 답. 수치만으로는 같은 한 주가 `게으름` 으로도
      // `과부하` 로도 읽히는데, 그 둘은 다음 주 처방이 정반대다.
      MemberFeedbackCard(feedback: report.memberFeedback);

  Widget _week(AppLocalizations l) => ReportSectionCard(
    key: const ValueKey<String>('report-review-week'),
    number: 2,
    title: l.reportsCardWeekTitle,
    subtitle: l.reportsCardWeekSubtitle,
    // 고객 이름·나이는 적지 않는다 — 카드 제목이 이미 누구의 리포트인지
    // 말하고, 왼쪽 목록에서 방금 고른 고객이다(#1177). 그 자리를 주
    // 이동이 가져간다: 옮기는 것은 이 카드의 내용이다.
    trailing: weekNav,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ① 격자 — 요일마다 무엇이 있었는지. 칼로리·나트륨·당류를
        // 나란히 세우던 예전 비교 표를 대신한다(#2232). 지표를 나열하면
        // 트레이너가 어느 줄부터 읽어야 할지를 매번 다시 정해야 했다.
        ReportWeekGrid(report: report, calorieBaseline: calorieBaseline),
        const SizedBox(height: OnCareSpacing.s16),
        // 총량이 말하지 않는 것 — 같은 칼로리가 무엇으로 채워졌는가.
        ReportMacroBars(report: report),
      ],
    ),
  );

  // ③ 유형별 주간 목표 달성률. 분·세트·분으로 재는 셋을 각자의
  // 목표에 대한 비율로 바꿔야 한 화면에서 견줄 수 있다. 이번 주가
  // 흐름의 어디쯤인지는 이 카드에서만 보인다 — 앞의 둘은 한 주만
  // 말한다.
  Widget _trend(AppLocalizations l) => ReportSectionCard(
    key: const ValueKey<String>('report-review-trend'),
    number: 3,
    title: l.reportsExerciseTrend,
    subtitle: l.reportsTrendSubtitle(kReportTrendWeeks),
    child: ReportExerciseTrend(report: report),
  );
}

/// ① 확인의 카드 하나. 선언 차례가 화면의 차례다.
enum ReportReviewSection {
  /// 회원이 낸 이번 주 답.
  member,

  /// 요일 격자와 영양 막대.
  week,

  /// 운동 유형별 추세.
  trend,
}

/// 제목 줄(+ 오른쪽 동작)과 내용을 담는 리포트 카드.
///
/// ① 확인의 카드와 ② 작성의 피드백 카드가 함께 쓴다 — 편집기와 보낸 리포트,
/// PDF 가 같은 틀에 담겨야 셋이 같은 문서로 읽힌다(#2425).
class ReportSectionCard extends StatelessWidget {
  /// Creates a report card titled [title].
  const ReportSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.number,
    this.subtitle = '',
    this.trailing,
  });

  final String title;

  /// 카드 번호. 읽는 차례가 있는 카드만 갖는다.
  final int? number;

  /// 제목 옆 곁말.
  final String subtitle;

  final Widget? trailing;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget? end = trailing;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 고정 폭 오른쪽 동작(주 이동)은 큰 글자 배율에서 카드 폭을 넘칠 수
          // 있다 — 모자랄 때만 통째로 줄여 그린다.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: <Widget>[
                Expanded(
                  child: ReportCardHeader(
                    number: number,
                    title: title,
                    subtitle: subtitle,
                  ),
                ),
                if (end != null) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  ConstrainedBox(
                    // 앞 간격만큼 뺀다 — 그대로 두면 그 간격만큼 넘친다.
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth - OnCareSpacing.s8,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: end,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          child,
        ],
      ),
    );
  }
}
