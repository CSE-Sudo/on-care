import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/domain/report_trend.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/member_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_ai_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_card_header.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_exercise_trend.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_editor.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_macro_bars.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_week_grid.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 주간 리포트 편집기의 단계.
///
/// 한 화면에 전부 쌓아 두면 트레이너는 스크롤 어디쯤에서 "다 봤다"고 판단할
/// 뿐, 무엇을 끝냈는지 알 수 없다. 읽기 → 정하기 → 보내기로 끊어, 각
/// 단계에서 할 일 하나만 화면에 둔다. (#2232)
enum ReportEditorStage {
  /// ① 확인 — 자료를 읽는 단계. 입력이 없다.
  review,

  /// ② 작성 — 회원에게 보낼 글을 쓴다. 요약에서 출발할 수 있고, 다음 주에
  /// 바꿀 것을 함께 고른다. 예전에는 `다음 주 목표` 만 하는 단계였는데,
  /// 목표를 고르는 일과 글을 쓰는 일은 트레이너 머릿속에서 한 번에 일어난다.
  goals,

  /// ③ 전송 — 다 쓴 글을 회원에게 내보낸다.
  send,
}

/// One client's week, ready to send.
class ClientReportView extends StatefulWidget {
  const ClientReportView({
    super.key,
    required this.report,
    this.stage,
    required this.showSummary,
    required this.draftEpoch,
    required this.summaryEpoch,
    required this.initialFeedback,
    required this.onUseSummaryAsDraft,
    required this.onFeedbackChanged,
    required this.savingFeedback,
    required this.onSaveFeedback,
    required this.weekNav,
    this.calorieBaseline,
  });

  final WeeklyReport report;

  /// 직전 넉 주의 하루 평균 섭취 칼로리 — ① 칼로리 줄이 견주는 `평소`.
  /// 아직 안 읽혔거나 견줄 기록이 없으면 null 이다.
  final double? calorieBaseline;

  /// 어느 단계를 그릴 것인가. null 이면 예전처럼 전부 한 흐름에 쌓는다 —
  /// 좁은 화면과 PDF 미리보기가 그 형태를 쓴다.
  final ReportEditorStage? stage;

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
    final ReportEditorStage? stage = widget.stage;
    final bool showReview = stage == null || stage == ReportEditorStage.review;
    final bool showGoals = stage == null || stage == ReportEditorStage.goals;
    final bool showSend = stage == null || stage == ReportEditorStage.send;
    // 단계가 있는 편집기인지. 없으면 한 화면에 전부 펼치던 예전 흐름이다.
    final bool staged = stage != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 확인 단계에는 요약을 두지 않는다. AI 가 내린 결론을 먼저 읽으면
        // 자료를 보는 일이 **그 결론이 맞는지 확인하는 일**로 바뀌어, 요약이
        // 짚지 않은 것은 트레이너도 짚지 않게 된다. 요약은 글을 쓰는 자리의
        // 출발점이므로 ② 작성에 선다. (#2232)
        // ① 회원이 낸 답. 수치만으로는 같은 한 주가 `게으름` 으로도
        // `과부하` 로도 읽히는데, 그 둘은 다음 주 처방이 정반대다.
        if (showReview) ...<Widget>[
          MemberFeedbackCard(feedback: widget.report.memberFeedback),
          const SizedBox(height: OnCareSpacing.s16),
        ],
        if (showReview)
          _SectionCard(
            number: 2,
            title: l.reportsCardWeekTitle,
            subtitle: l.reportsCardWeekSubtitle,
            // 고객 이름·나이는 적지 않는다 — 카드 제목이 이미 누구의 리포트인지
            // 말하고, 왼쪽 목록에서 방금 고른 고객이다(#1177). 그 자리를 주
            // 이동이 가져간다: 옮기는 것은 이 카드의 내용이다.
            trailing: widget.weekNav,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ① 격자 — 요일마다 무엇이 있었는지. 칼로리·나트륨·당류를
                // 나란히 세우던 예전 비교 표를 대신한다(#2232). 지표를 나열하면
                // 트레이너가 어느 줄부터 읽어야 할지를 매번 다시 정해야 했다.
                ReportWeekGrid(
                  report: widget.report,
                  calorieBaseline: widget.calorieBaseline,
                ),
                const SizedBox(height: OnCareSpacing.s16),
                // 총량이 말하지 않는 것 — 같은 칼로리가 무엇으로 채워졌는가.
                ReportMacroBars(report: widget.report),
              ],
            ),
          ),
        // 요약 카드는 ② 다음 주 목표와 ③ 전송 두 단계에 선다. ②에서는
        // `다음 주 코칭 제안` 이 목표를 고르는 재료이고, ③에서는 같은 카드의
        // `피드백으로 가져오기` 가 보낼 글의 출발점이다 — 두 단계에서 쓰임이
        // 달라 한쪽에만 둘 수 없다.
        if ((showGoals || (showSend && staged)) &&
            (widget.showSummary || staged)) ...<Widget>[
          if (stage == null) const SizedBox(height: OnCareSpacing.s16),
          ReportAiCard(
            report: widget.report,
            onUseAsDraft: widget.onUseSummaryAsDraft,
          ),
        ],
        // 입력창은 **작성** 단계에 선다. 단계 이름이 `작성` 인데 글 쓰는
        // 자리가 다음 단계에 있으면, 트레이너는 목표만 고르고 넘어간 뒤
        // 전송 단계에서 처음 글을 만나게 된다. 전송 단계에도 남겨 두어
        // 보내기 직전에 고칠 수 있다. (#2232)
        if (showGoals || showSend) ...<Widget>[
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
                      // 자동으로 채워진 초안이 늘 맞는 것은 아니다. 지우고
                      // 처음부터 쓰려면 입력창을 통째로 비워야 하는데, 손으로
                      // 지우면 되돌리기 기록이 그만큼 어지러워진다 — 요약을
                      // 가져오는 것과 **같은 길**로 비워, 한 번에 되돌아간다.
                      AppButton(
                        key: const ValueKey<String>('report-feedback-scratch'),
                        label: l.reportsWriteFromScratch,
                        leadingIcon: Icons.edit_note_rounded,
                        variant: AppButtonVariant.text,
                        size: OnCareButtonSize.small,
                        onPressed: () => widget.onUseSummaryAsDraft(''),
                      ),
                      const SizedBox(width: OnCareSpacing.buttonGap),
                      ValueListenableBuilder<UndoHistoryValue>(
                        valueListenable: _undo,
                        builder: (context, history, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            AppIconButton(
                              key: const ValueKey<String>(
                                'report-feedback-undo',
                              ),
                              icon: Icons.undo_rounded,
                              tooltip: l.reportsFeedbackUndo,
                              size: AppIconButtonSize.small,
                              onPressed: history.canUndo ? _undo.undo : null,
                            ),
                            AppIconButton(
                              key: const ValueKey<String>(
                                'report-feedback-redo',
                              ),
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
        ],
        if (showReview) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s16),
          // ③ 유형별 주간 목표 달성률. 분·세트·분으로 재는 셋을 각자의
          // 목표에 대한 비율로 바꿔야 한 화면에서 견줄 수 있다. 이번 주가
          // 흐름의 어디쯤인지는 이 카드에서만 보인다 — 앞의 둘은 한 주만
          // 말한다.
          _SectionCard(
            number: 3,
            title: l.reportsExerciseTrend,
            subtitle: l.reportsTrendSubtitle(kReportTrendWeeks),
            child: ReportExerciseTrend(report: widget.report),
          ),
        ],
      ],
    );
  }
}

/// 제목 줄(+ 오른쪽 동작)과 내용을 담는 리포트 카드.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
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
