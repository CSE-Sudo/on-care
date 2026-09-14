import 'package:flutter/material.dart';
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
    final DateTime? at = session.isCancelled
        ? session.cancelledAt
        : session.noShowAt;
    final String head = scheduleStatusLabel(l, session.status);
    final String detail =
        session.isCancelled && session.cancellationSource.isNotEmpty
        ? l.schedCancelledBy(
            cancellationSourceLabel(l, session.cancellationSource),
            at == null ? '' : ymd(at.toLocal()),
          )
        : (at == null ? '' : ymd(at.toLocal()));
    return SizedBox(
      key: ValueKey<String>('session-ended-${session.id}'),
      width: double.infinity,
      child: AppBanner(
        tone: AppBannerTone.caution,
        icon: session.isCancelled
            ? Icons.event_busy_rounded
            : Icons.person_off_rounded,
        title: detail.isEmpty ? head : '$head · $detail',
        message: session.cancellationReason.isEmpty
            ? null
            : session.cancellationReason,
      ),
    );
  }
}
