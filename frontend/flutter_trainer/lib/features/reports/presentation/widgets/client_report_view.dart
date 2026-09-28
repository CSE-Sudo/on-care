import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_ai_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_card.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_feedback_editor.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_review_cards.dart';
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

  /// ② 작성 — 회원에게 보낼 글을 쓴다. 요약에서 출발할 수 있다.
  write,

  /// ③ 전송 — 회원이 받을 PDF 를 확인하고 내보낸다. 이 위젯이 아니라
  /// 전송 미리보기(`ReportSendPreview`)가 그린다(#2402).
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
    final bool showWrite = stage == null || stage == ReportEditorStage.write;
    // 단계가 있는 편집기인지. 없으면 한 화면에 전부 펼치던 예전 흐름이다.
    final bool staged = stage != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ① 확인의 카드는 보낸 리포트 화면·회원이 받는 PDF 와 같은 위젯이다
        // (#2425, #2424) — 트레이너가 읽은 그림과 회원이 받은 그림이 같아야
        // 한다.
        if (showReview)
          ReportReviewCards(
            report: widget.report,
            calorieBaseline: widget.calorieBaseline,
            weekNav: widget.weekNav,
          ),
        // 요약 카드는 ② 작성에 선다. `피드백으로 가져오기` 가 글을 쓰기
        // 시작하는 출발점이다. ③ 전송은 회원이 받을 PDF 만 보여 준다(#2402).
        if (showWrite && (widget.showSummary || staged)) ...<Widget>[
          if (stage == null) const SizedBox(height: OnCareSpacing.s16),
          ReportAiCard(
            report: widget.report,
            onUseAsDraft: widget.onUseSummaryAsDraft,
          ),
        ],
        // 입력창은 **작성** 단계에만 선다. ③ 전송에서 글을 고치려면 `이전` 으로
        // 돌아온다 — 보내기 직전의 화면이 회원이 받을 모습과 달라지지 않게
        // (#2232, #2402).
        if (showWrite) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s16),
          ReportFeedbackCard(
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
                        leadingIcon: AppIcons.write,
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
                              icon: AppIcons.undo,
                              tooltip: l.reportsFeedbackUndo,
                              size: AppIconButtonSize.small,
                              onPressed: history.canUndo ? _undo.undo : null,
                            ),
                            AppIconButton(
                              key: const ValueKey<String>(
                                'report-feedback-redo',
                              ),
                              icon: AppIcons.redo,
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
                        leadingIcon: AppIcons.save,
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
      ],
    );
  }
}
