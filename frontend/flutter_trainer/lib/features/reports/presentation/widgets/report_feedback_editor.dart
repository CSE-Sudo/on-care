import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 고객에게 보낼 주간 피드백 초안 입력창.
class ReportFeedbackEditor extends StatefulWidget {
  const ReportFeedbackEditor({
    super.key,
    required this.initialText,
    required this.onChanged,
  });

  final String initialText;

  /// 전송은 헤더의 공유 메뉴가 한다 — 이 위젯은 문구만 들고 올려 준다.
  final ValueChanged<String> onChanged;

  @override
  State<ReportFeedbackEditor> createState() => _ReportFeedbackEditorState();
}

class _ReportFeedbackEditorState extends State<ReportFeedbackEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
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
          onChanged: widget.onChanged,
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
