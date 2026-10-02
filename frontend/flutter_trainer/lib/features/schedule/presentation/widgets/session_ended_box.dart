import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/core/utils/clock.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 취소·노쇼로 마무리된 세션의 기록 — 언제, 누가, (있으면) 왜. (#871)
///
/// 데모와 실 API 가 같은 값을 저장하므로 두 경로가 같은 줄을 보여 준다(#906).
class SessionEndedBox extends StatelessWidget {
  const SessionEndedBox({super.key, required this.session});

  final ScheduleSession session;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 처리 날짜는 KST 로 읽는다 — 브라우저 시간대로 읽으면 KST 오전 0~9시에
    // 처리한 세션이 해외 브라우저에서 전날로 보였다(#2893).
    final DateTime? at = session.isCancelled
        ? session.cancelledAt
        : session.noShowAt;
    final String head = scheduleStatusLabel(l, session.status);
    final String detail =
        session.isCancelled && session.cancellationSource.isNotEmpty
        ? l.schedCancelledBy(
            cancellationSourceLabel(l, session.cancellationSource),
            at == null ? '' : ymd(kstDateOf(at)),
          )
        : (at == null ? '' : ymd(kstDateOf(at)));
    return SizedBox(
      key: ValueKey<String>('session-ended-${session.id}'),
      width: double.infinity,
      child: AppBanner(
        tone: AppBannerTone.caution,
        icon: session.isCancelled
            ? AppIcons.eventBusy
            : AppIcons.personOff,
        title: detail.isEmpty ? head : '$head · $detail',
        message: session.cancellationReason.isEmpty
            ? null
            : session.cancellationReason,
      ),
    );
  }
}
