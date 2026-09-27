import 'package:flutter/material.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_status.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 저장하려던 시간이 다른 일정과 겹쳐 아무것도 바뀌지 않았다는 안내. (#2284)
///
/// 일정 추가·수정, 예약 자리 열기, 상담 승인이 같은 모양으로 쓴다 — 반복
/// 회차 겹침(`SessionRepeatConflicts`)과 같은 주의 배너에, 겹친 일정을
/// "날짜 시각 · 회원" 줄로 짚어 준다. 무엇을 옮겨야 하는지 알아야 다음
/// 행동을 할 수 있기 때문이다. 서버가 목록을 싣지 않은 경우엔 안내만 남는다.
class ScheduleOverlapBanner extends StatelessWidget {
  const ScheduleOverlapBanner({super.key, required this.conflicts, this.hint});

  /// 겹친 일정. 다섯 건까지만 줄로 보인다.
  final List<ScheduleSession> conflicts;

  /// 마지막 줄 안내. 비우면 일정 저장용 안내(`schedOverlapHint`)다.
  final String? hint;

  static const int _maxRows = 5;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String message = <String>[
      for (final conflict in conflicts.take(_maxRows))
        l.schedRepeatConflictRow(
          conflict.date,
          conflict.time,
          conflict.clientName.isNotEmpty
              ? conflict.clientName
              : sessionTypeLabel(l, conflict.type),
        ),
      hint ?? l.schedOverlapHint,
    ].join('\n');
    return SizedBox(
      key: const ValueKey<String>('schedule-overlap'),
      width: double.infinity,
      child: AppBanner(
        tone: AppBannerTone.caution,
        title: l.schedOverlapTitle,
        message: message,
      ),
    );
  }
}
