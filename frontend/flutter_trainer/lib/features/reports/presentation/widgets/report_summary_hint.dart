import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/reports/presentation/widgets/report_ai_card.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 요약 자리에 아직 내용이 없을 때 — 그 자리에 **무엇이 뜨는지**만 적는다.
///
/// 빈 칸으로 두면 왼쪽 열이 목록 아래로 그냥 잘린 것처럼 보이고, 고객을 고르면
/// 무엇을 얻는지도 알 수 없다. 카드 껍데기는 [ReportAiCard] 와 같게 두어,
/// 내용이 채워질 때 자리가 흔들리지 않는다.
class ReportSummaryHint extends StatelessWidget {
  const ReportSummaryHint({
    super.key,
    required this.message,
    this.loading = false,
    this.fill = false,
  });

  final String message;

  /// 요약을 읽는 중인가. 안내문 앞에 작은 스피너를 둔다.
  final bool loading;

  /// 남은 세로 자리를 채우는가. [ReportAiCard] 와 같은 자리에 놓이므로 같은
  /// 규칙을 쓴다 — 칸이 안내문보다 짧으면 카드 안에서 스크롤한다.
  ///
  /// 이 값이 없던 때에는 리포트를 읽는 동안 칸이 잠깐 얇아지는 순간마다
  /// 렌더 오버플로가 났다. 채우는 자리에서만 스크롤을 붙이는 이유는, 좁은
  /// 화면에서는 이 카드가 **스스로 스크롤하는 열 안에** 놓여 높이가 무한하기
  /// 때문이다(#1177).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final Widget text = Text(
      message,
      style: tokens
          .text(OnCareTypography.bodySmall)
          .copyWith(color: OnCareColors.textSecondary),
    );
    final Widget body = loading
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: OnCareSpacing.s2),
                child: AppLoading.inline(),
              ),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(child: text),
            ],
          )
        : text;
    return AppCard(
      key: const ValueKey<String>('reports-summary-hint'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: <Widget>[
          AppSectionHeader(
            title: l.reportsAiTitle,
            icon: Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          if (fill)
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey<String>('reports-summary-hint-scroll'),
                child: body,
              ),
            )
          else
            body,
        ],
      ),
    );
  }
}
