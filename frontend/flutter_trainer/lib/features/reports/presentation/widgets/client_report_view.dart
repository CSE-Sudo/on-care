import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/dashboard/domain/dashboard_summary.dart'
    show weekdayCount;
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/four_week_compliance_trend.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/metric_comparison_section.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/metric_trend_section.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_ai_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_daily_detail.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_editor.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/weekly_completion_chart.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/weekly_exercise_minutes.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// One client's week, ready to send.
class ClientReportView extends StatefulWidget {
  const ClientReportView({
    super.key,
    required this.report,
    required this.showSummary,
    required this.draftEpoch,
    required this.summaryEpoch,
    required this.initialFeedback,
    required this.onUseSummaryAsDraft,
    required this.onFeedbackChanged,
    required this.savingFeedback,
    required this.onSaveFeedback,
    required this.weekNav,
  });

  final WeeklyReport report;

  /// 요약 카드를 이 흐름 안에 그릴 것인가. 넓은 화면에서는 왼쪽 고객 열이
  /// 가져가므로 `false` 다.
  final bool showSummary;

  /// 입력창에 채워 둘 문구. 트레이너가 고치던 중이면 그 내용이다.
  /// 바뀌면 입력창을 새 문구로 다시 만든다.
  final int draftEpoch;

  /// 요약을 초안으로 가져올 때 올린다. [draftEpoch] 와 달리 입력창을 새로
  /// 만들지 않고 그 안의 글을 바꿔, 가져오기 전 글로 되돌릴 수 있다(#2187).
  final int summaryEpoch;

  final String initialFeedback;

  /// 요약을 피드백 초안으로 옮긴다.
  final ValueChanged<String> onUseSummaryAsDraft;

  /// 입력창이 바뀔 때마다 현재 문구를 올려 준다 — 전송은 헤더 공유 메뉴가 한다.
  final ValueChanged<String> onFeedbackChanged;

  /// 초안을 서버에 저장하는 중이다. (#821)
  final bool savingFeedback;

  /// 입력창의 현재 문구를 그 주의 초안으로 저장한다. (#821)
  final VoidCallback onSaveFeedback;

  /// 카드 제목 줄에 놓을 주 이동. 리포트를 못 읽은 화면에도 같은 것이 놓여야
  /// 해서 페이지가 만들어 넘긴다 — 실패한 주에 갇히면 나갈 길이 없다. (#1177)
  final Widget weekNav;

  @override
  State<ClientReportView> createState() => _ClientReportViewState();
}

class _ClientReportViewState extends State<ClientReportView> {
  /// 피드백 입력창의 편집 기록을 제목 줄 버튼과 잇는다(#2187).
  ///
  /// `초안으로 되돌리기` 는 고친 내용을 한 번에 전부 버렸다. 문서 편집기처럼
  /// 한 단계씩 앞뒤로 오가게 한다. 입력창이 새로 만들어지면(키가 바뀌면)
  /// 기록도 새로 시작하므로 컨트롤러도 새로 둔다 — 지난 입력창이 남긴
  /// `되돌릴 수 있음` 이 새 입력창의 버튼을 켜 두지 않게.
  UndoHistoryController _undo = UndoHistoryController();

  String get _editorKey =>
      'feedback-${widget.report.client.id}-'
      '${widget.report.weekStart.toIso8601String()}-${widget.draftEpoch}';

  late String _undoFor = _editorKey;

  @override
  void didUpdateWidget(ClientReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editorKey == _undoFor) return;
    _undoFor = _editorKey;
    // 지난 입력창은 이번 프레임이 끝나야 떨어져 나가며 컨트롤러에서 손을
    // 뗀다. 그 전에 치우면 이미 치운 것을 건드린다.
    final UndoHistoryController old = _undo;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _undo = UndoHistoryController();
  }

  @override
  void dispose() {
    _undo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool hasWeek = widget.report.weekCompletion.length == weekdayCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionCard(
          title: l.reportsClientWeekly(widget.report.client.name),
          icon: Icons.description_rounded,
          // 고객 이름·나이는 적지 않는다 — 카드 제목이 이미 누구의 리포트인지
          // 말하고, 왼쪽 목록에서 방금 고른 고객이다(#1177). 그 자리를 주
          // 이동이 가져간다: 옮기는 것은 이 카드의 내용이다.
          trailing: widget.weekNav,
          child: MetricComparisonSection(report: widget.report),
        ),
        if (widget.showSummary) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s16),
          ReportAiCard(
            report: widget.report,
            onUseAsDraft: widget.onUseSummaryAsDraft,
          ),
        ],
        const SizedBox(height: OnCareSpacing.s16),
        _SectionCard(
          title: l.reportsFeedbackTitle,
          // 저장 버튼을 제목 행에 둔다 — 입력창 위에 버튼만 있는 줄이 따로
          // 있으면 카드가 그만큼 세로로 늘어난다.
          // 되돌리기·다시 실행을 저장 옆에 둔다 — 입력창을 되돌릴 수단이 그
          // 입력창 바로 위에 있어야 한다. 되돌릴 것이 없으면 꺼 둔다(#2187).
          //
          // 지난 주에는 모두 없다. 트레이너가 손볼 것은 이번 주에 보낼 글이고,
          // 이미 지나간 주의 초안을 저장해 둘 자리는 없다(#1177).
          trailing: widget.report.isCurrentWeek
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ValueListenableBuilder<UndoHistoryValue>(
                      valueListenable: _undo,
                      builder: (context, history, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          AppIconButton(
                            key: const ValueKey<String>('report-feedback-undo'),
                            icon: Icons.undo_rounded,
                            tooltip: l.reportsFeedbackUndo,
                            size: AppIconButtonSize.small,
                            onPressed: history.canUndo ? _undo.undo : null,
                          ),
                          AppIconButton(
                            key: const ValueKey<String>('report-feedback-redo'),
                            icon: Icons.redo_rounded,
                            tooltip: l.reportsFeedbackRedo,
                            size: AppIconButtonSize.small,
                            onPressed: history.canRedo ? _undo.redo : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: OnCareSpacing.buttonGap),
                    AppButton(
                      key: const ValueKey<String>('report-feedback-save'),
                      label: widget.savingFeedback
                          ? l.reportsFeedbackSaving
                          : l.reportsFeedbackSave,
                      leadingIcon: Icons.save_rounded,
                      variant: AppButtonVariant.secondary,
                      size: OnCareButtonSize.small,
                      onPressed: widget.savingFeedback
                          ? null
                          : widget.onSaveFeedback,
                    ),
                  ],
                )
              : null,
          child: ReportFeedbackEditor(
            key: ValueKey<String>(_editorKey),
            initialText: widget.initialFeedback,
            undoController: _undo,
            replaceEpoch: widget.summaryEpoch,
            onChanged: widget.onFeedbackChanged,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s16),
        // 운동과 식단을 카드로 나눈다. 예전에는 나트륨 추이 그래프가 '요일별
        // 운동 이행률' 카드 안에 있어 제목과 내용이 서로 다른 말을 했다(#754).
        _SectionCard(
          // 막대가 이행률에서 소모 칼로리로 바뀌면서 제목도 따라간다(#1289).
          // 이행률은 사라지지 않고 제목 줄의 요약 칩과 4주 추이로 남는다.
          title: l.reportsBurnByDay,
          // 한 주를 요약하는 세 값은 제목 줄에 둔다. 카드 안에서 큰 숫자로
          // 다시 보여 주면 그래프가 아래로 밀린다(#754 의 반복).
          trailing: _WeekSummaryChips(report: widget.report),
          trailingFlexible: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 계열은 리포트가 자기 주의 것을 들고 온다 — 보고 있는 주가
              // 어디든 같은 규칙으로 그린다(#752).
              if (hasWeek)
                WeeklyCompletionChart(report: widget.report)
              else
                AppEmptyState(
                  title: l.reportsNoWorkoutsThisWeek,
                  icon: Icons.fitness_center_rounded,
                  placement: AppStatePlacement.card,
                ),
              if (hasWeek) ...<Widget>[
                const SizedBox(height: OnCareSpacing.s12),
                // 막대 바로 아래에 그날의 운동 내역. 67% 가 어디서 나온
                // 값인지 같은 카드 안에서 답이 난다(#754).
                ReportDailyDetail(report: widget.report),
                const _SectionDivider(),
                // 이행률이 말하지 않는 값 — 그 주에 실제로 움직인 시간이다.
                WeeklyExerciseMinutes(report: widget.report),
              ],
              if (widget.report.completionAvg != null) ...<Widget>[
                const _SectionDivider(),
                // 마지막 줄에 보고 있는 주를 앞선 세 주 옆에 놓는다. 며칠을
                // 나눈 값인지는 따로 적지 않는다 — 값이 있는 막대를 세면
                // 나온다(#754).
                FourWeekComplianceTrend(report: widget.report),
              ],
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s16),
        _SectionCard(
          // `나트륨 초과 n일` 은 적지 않는다 — 카드 제목은 식단 전체를 말하는데
          // 그 옆에 지표 하나의 수치만 붙어 있었고, 같은 값은 요약 카드의 근거
          // 줄과 4주 막대의 빨강이 이미 말한다(#1177).
          title: l.reportsDietTrend,
          child: MetricTrendSection(report: widget.report),
        ),
      ],
    );
  }
}

/// 제목 줄(+ 오른쪽 동작)과 내용을 담는 리포트 카드.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.trailingFlexible = false,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  /// 오른쪽 내용이 줄을 접을 수 있으면(칩 묶음) 제목과 폭을 나눈다.
  final bool trailingFlexible;
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
                  child: AppSectionHeader(title: title, icon: icon),
                ),
                if (end != null) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s8),
                  if (trailingFlexible)
                    // 칩 묶음은 제 폭만 차지해 칸 왼쪽에 떠 있었다 — 칸을
                    // 채우고 오른쪽 끝에 붙인다.
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: end,
                      ),
                    )
                  else
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

/// 한 카드 안의 구획 사이 선.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: OnCareSpacing.s12),
    child: AppDivider(),
  );
}

/// 평균 이행률 · 기록한 날 수 · PT 진행 — 그래프가 답하지 않는 세 값.
class _WeekSummaryChips extends StatelessWidget {
  const _WeekSummaryChips({required this.report});

  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // PT 진행 횟수는 적지 않는다 — 이 카드가 말하는 것은 회원이 루틴을 얼마나
    // 따라왔나이고, 세션 수는 스케줄 탭이 답한다(#1177).
    final int? avg = report.completionAvg;
    final int logged = report.weekCompletion.where((v) => v > 0).length;
    return Wrap(
      spacing: OnCareSpacing.s4,
      runSpacing: OnCareSpacing.s4,
      alignment: WrapAlignment.end,
      children: <Widget>[
        // 카드 제목이 소모 칼로리를 말하게 됐으므로(#1289) 이 칩이 무엇의
        // 평균인지 스스로 밝힌다 — `평균 87%` 만으로는 칼로리의 평균으로 읽힌다.
        // 영어·큰 글자 배율에서는 태그 하나가 칸보다 길다 — 넘치지 않게 줄여 그린다.
        if (avg != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AppTag(label: l.reportsAdherenceChip('$avg%')),
          ),
        if (logged > 0)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AppTag(label: l.reportsRecordedDays(logged)),
          ),
      ],
    );
  }
}
