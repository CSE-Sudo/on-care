import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/weekly_report.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 리포트를 내보내는 두 경로를 한 메뉴로 모은 헤더 액션. (#735)
///
/// 전에는 동작하는 `고객에게 전송` 이 피드백 입력창 아래에, 눌리지 않는
/// `PDF 내보내기` 가 헤더에 따로 있어서 "이 리포트를 어떻게 내보내지"의 답이
/// 화면 두 곳에 나뉘어 있었다.
///
/// 항목에 고객 이름을 함께 적는다 — 헤더는 본문보다 위에 있어 어느 리포트가
/// 열려 있는지 눈으로 잇기 어렵고, 잘못된 고객에게 보내는 실수가 되돌릴 수
/// 없는 종류이기 때문이다.
class ReportShareMenu extends ConsumerWidget {
  const ReportShareMenu({
    super.key,
    required this.client,
    required this.weekStart,
    required this.sent,
    required this.sending,
    required this.feedbackBlank,
    required this.onSend,
    required this.generatingPdf,
    required this.onPdf,
  });

  /// 리포트를 보고 있는 고객. 로스터가 비어 있으면 null.
  final TrainerClient? client;

  /// 화면이 보고 있는 주. 헤더의 주 이동과 같은 값을 써야 다른 주의 리포트를
  /// 보내는 일이 없다.
  final DateTime weekStart;
  final bool sent;
  final bool sending;

  /// 피드백 입력창이 비었는가. 리포트 수치만 덩그러니 보내면 회원은 무슨 뜻인지
  /// 알 수 없어, 전에도 빈 피드백은 보낼 수 없었다.
  final bool feedbackBlank;

  final Future<void> Function(WeeklyReport report) onSend;
  final bool generatingPdf;
  final Future<void> Function(WeeklyReport report) onPdf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final target = client;
    return AppMenu(
      items: <AppMenuItem>[
        AppMenuItem(
          icon: sent ? Icons.check_rounded : Icons.send_rounded,
          label: target == null
              ? l.reportsShareNoClient
              : (sent
                    ? l.reportsSendStateSent
                    : (sending
                          ? l.reportsSendStateSending
                          : l.reportsShareSendTo(target.name))),
          onSelected: target == null || sent || sending || feedbackBlank
              ? null
              : () => _send(context, ref, target),
        ),
        AppMenuItem(
          icon: Icons.picture_as_pdf_rounded,
          label: generatingPdf ? l.reportsPdfGenerating : l.reportsPdfLabel,
          onSelected: target == null || generatingPdf
              ? null
              : () => _pdf(ref, target),
        ),
      ],
      triggerBuilder: (context, toggle) {
        final Widget trigger = AppButton(
          key: const ValueKey<String>('reports-share-action'),
          label: l.reportsShare,
          leadingIcon: Icons.ios_share_rounded,
          variant: AppButtonVariant.secondary,
          // 전송 중에는 메뉴를 다시 열 이유가 없다 — 같은 리포트가 두 번 나가지
          // 않게 버튼 자리에서 진행을 보여 준다. PDF 생성은 메뉴 항목이 스스로
          // `생성 중` 을 말한다.
          loading: sending,
          onPressed: toggle,
        );
        // 메뉴 항목에는 툴팁을 달 수 없어, 전송이 잠긴 이유는 트리거가 말한다.
        return feedbackBlank && target != null && !sent && !sending
            ? Tooltip(message: l.reportsShareNeedsFeedback, child: trigger)
            : trigger;
      },
    );
  }

  /// 화면에 떠 있는 그 주의 리포트를 읽어 전송한다.
  ///
  /// 아직 로딩 중이면 보낼 내용이 없으므로 아무 일도 하지 않는다 — 빈 리포트를
  /// 보내는 것보다 낫다.
  void _send(BuildContext context, WidgetRef ref, TrainerClient target) {
    final report = ref
        .read(weeklyReportProvider((client: target, weekStart: weekStart)))
        .valueOrNull;
    if (report == null) return;
    onSend(report);
  }

  void _pdf(WidgetRef ref, TrainerClient target) {
    final report = ref
        .read(weeklyReportProvider((client: target, weekStart: weekStart)))
        .valueOrNull;
    if (report != null) onPdf(report);
  }
}
