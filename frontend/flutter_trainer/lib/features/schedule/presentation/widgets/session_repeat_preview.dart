import 'package:flutter/material.dart';
import 'package:oncare_trainer/core/utils/date_format.dart';
import 'package:oncare_trainer/features/schedule/domain/entities/schedule_session.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 저장하면 만들어질 회차 요약 — "총 8회 · 8/24 ~ 10/12". (#870)
///
/// 반복은 한 번에 여러 건을 만든다. 요일이나 종료일을 잘못 골랐을 때 되돌리는
/// 비용이 한 건씩 지우는 일이라, 만들기 전에 몇 회차인지 말해 준다.
///
/// 아이콘 없는 한 줄 요약이라 [AppTile] 로 그린다. 글자는 한 [Text] 뿐이다 —
/// 테스트가 이 문구를 그대로 읽어 회차 수를 되짚는다.
class SessionRepeatPreview extends StatelessWidget {
  const SessionRepeatPreview({super.key, required this.dates});

  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return SizedBox(
      key: const ValueKey<String>('repeat-preview'),
      width: double.infinity,
      child: AppTile(
        child: Text(
          dates.isEmpty
              ? l.schedRepeatNeedsDays
              : l.schedRepeatPreview(
                  dates.length,
                  ymd(dates.first),
                  ymd(dates.last),
                ),
          style: tokens
              .text(OnCareTypography.label)
              .copyWith(color: tokens.brand.primary),
        ),
      ),
    );
  }
}

/// 겹치는 회차 — 어느 주가 문제인지 짚어 준다. (#870)
///
/// 목록을 보여 주는 까닭은 "겹칩니다" 만으로는 트레이너가 무엇을 고쳐야 할지
/// 모르기 때문이다. 이 상태에서는 **아무 일정도 만들어지지 않았다.**
///
/// 경고 아이콘 + 제목 + 본문 구조라 [AppBanner] 로 그린다. 겹치는 회차(최대
/// 다섯 줄)와 안내 문장은 본문 한 덩어리에 줄을 바꿔 담는다.
class SessionRepeatConflicts extends StatelessWidget {
  const SessionRepeatConflicts({
    super.key,
    required this.total,
    required this.conflicts,
  });

  final int total;
  final List<ScheduleSession> conflicts;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String message = <String>[
      for (final conflict in conflicts.take(5))
        l.schedRepeatConflictRow(
          conflict.date,
          conflict.time,
          conflict.clientName,
        ),
      l.schedRepeatConflictHint,
    ].join('\n');
    return SizedBox(
      key: const ValueKey<String>('repeat-conflicts'),
      width: double.infinity,
      child: AppBanner(
        tone: AppBannerTone.caution,
        title: l.schedRepeatConflictTitle(conflicts.length, total),
        message: message,
      ),
    );
  }
}
