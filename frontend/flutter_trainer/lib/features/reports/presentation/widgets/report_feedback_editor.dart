import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 고객에게 보낼 주간 피드백 초안 입력창.
class ReportFeedbackEditor extends StatefulWidget {
  const ReportFeedbackEditor({
    super.key,
    required this.initialText,
    required this.onChanged,
    this.undoController,
    this.replaceEpoch = 0,
  });

  final String initialText;

  /// 바뀌면 입력창을 [initialText] 로 바꿔 쓴다. 입력창을 새로 만들지 않고
  /// 고쳐 쓰므로 편집 기록에 한 단계로 남는다 — 요약을 가져온 뒤에도
  /// 되돌리기로 쓰던 글에 돌아갈 수 있다(#2187).
  final int replaceEpoch;

  /// 카드 제목 줄의 되돌리기·다시 실행 버튼이 이 입력창의 편집 기록을 한
  /// 단계씩 오간다(#2187). 기록은 입력창이 들고 있으므로 입력창이 새로
  /// 만들어지면(다른 주·요약 옮기기) 처음부터 쌓인다.
  final UndoHistoryController? undoController;

  /// 전송은 헤더의 공유 메뉴가 한다 — 이 위젯은 문구만 들고 올려 준다.
  final ValueChanged<String> onChanged;

  @override
  State<ReportFeedbackEditor> createState() => _ReportFeedbackEditorState();
}

class _ReportFeedbackEditorState extends State<ReportFeedbackEditor> {
  // 커서를 글 끝에 둔 채로 연다. 커서 자리가 없는 값은 편집 기록에 쌓이지
  // 않아, 처음 연 글로 되돌아갈 단계가 사라진다(#2187).
  late final TextEditingController _controller =
      TextEditingController.fromValue(_valueOf(widget.initialText));

  static TextEditingValue _valueOf(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  /// 마지막으로 올려 준 문구.
  late String _reported = widget.initialText;

  @override
  void initState() {
    super.initState();
    // `onChanged` 는 손으로 친 글자에만 불린다. 되돌리기·다시 실행은 입력창
    // 값을 코드로 바꾸므로, 컨트롤러를 지켜봐야 저장·전송이 화면에 보이는
    // 글을 쓴다(#2187).
    _controller.addListener(_report);
  }

  void _report() {
    final String text = _controller.text;
    if (text == _reported) return;
    _reported = text;
    widget.onChanged(text);
  }

  @override
  void didUpdateWidget(ReportFeedbackEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replaceEpoch == oldWidget.replaceEpoch) return;
    // 부모는 이미 새 문구를 알고 있다 — 빌드 도중 되돌려 알리지 않는다.
    _reported = widget.initialText;
    _controller.value = _valueOf(widget.initialText);
  }

  @override
  void dispose() {
    _controller.removeListener(_report);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppTextField(
          controller: _controller,
          undoController: widget.undoController,
          hint: l.reportsFeedbackHint,
          minLines: 4,
          // 내용에 맞춰 자란다. 초안이 문단 글이 되면서 7줄에서 잘려, 트레이너가
          // 보낼 글을 스크롤해야만 다 읽을 수 있었다 — 손보기 전에 전체를 읽는
          // 것이 이 입력창의 용도다(#755).
          maxLines: null,
        ),
        const SizedBox(height: OnCareSpacing.s4),
        // 이 글은 회원에게 그대로 나간다. 무엇이 이미 채워져 있는지와 보내기
        // 전에 할 일을 그 자리에서 말해 준다 — 'AI' 라고 하지 않는 이유는
        // 이 초안이 수치에서 조립한 템플릿이지 생성된 문장이 아니어서다.
        // 본문과 같은 톤이면 초안의 일부처럼 읽힌다 — 안내는 한 단계 연하게.
        Text(
          l.reportsFeedbackDraftNote,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tokens
              .text(OnCareTypography.caption)
              .copyWith(color: OnCareColors.textTertiary),
        ),
      ],
    );
  }
}
