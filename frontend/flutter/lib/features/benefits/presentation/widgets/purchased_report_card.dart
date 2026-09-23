import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare/app/app_icons.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/features/ai_coach/domain/entities/chat_insight.dart';
import 'package:oncare/features/ai_coach/presentation/controllers/ai_coach_controller.dart';
import 'package:oncare/features/ai_coach/presentation/widgets/insight_history_sheet.dart';
import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/features/benefits/presentation/widgets/benefit_cards.dart';
import 'package:oncare/features/member_coach/domain/entities/member_weekly_report.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_report_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_chat_sheet.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 포인트로 받은 주간 리포트 한 주 — 내 혜택의 카드. (#2022)
///
/// 보는 자리를 새로 만들지 않는다. 트레이너가 채팅으로 등록한 리포트와 **같은
/// 문서**(회원 기록으로 세운 리포트)를 같은 PDF 미리보기로 연다. 다른 점은 하나다 —
/// 트레이너가 쓴 것이 아니라 트레이너 메시지가 없고, 그 자리에 그 주의 감지 기록을
/// 싣는다(`MemberReportSource.points`).
class PurchasedReportCard extends ConsumerStatefulWidget {
  const PurchasedReportCard({super.key, required this.weekStart});

  /// 리포트가 가리키는 주의 월요일.
  final DateTime weekStart;

  @override
  ConsumerState<PurchasedReportCard> createState() =>
      _PurchasedReportCardState();
}

class _PurchasedReportCardState extends ConsumerState<PurchasedReportCard> {
  /// 문서를 만드는 동안 다시 누르지 못하게 한다 — 미리보기가 두 겹으로 열린다.
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    // 내 혜택의 다른 카드(쿠폰·보호권)와 같은 줄 모양이다. 채팅의 리포트 안내는
    // 대화 가운데 서는 배너라 목록에 두면 폭이 들쭉날쭉하다.
    return AppCard(
      key: ValueKey<String>('purchased-report-${_ymd(widget.weekStart)}'),
      child: Row(
        children: <Widget>[
          const BenefitIconTile(icon: AppIcons.document),
          const SizedBox(width: OnCareSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  reportWeekRange(l, widget.weekStart),
                  style: tokens
                      .text(OnCareTypography.titleSmall)
                      .copyWith(color: OnCareColors.textPrimary),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                Text(
                  l.myWeeklyReportCardTitle,
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          AppButton(
            label: l.coachChatReportPreviewPdf,
            size: OnCareButtonSize.small,
            loading: _opening,
            onPressed: _opening ? null : _open,
          ),
        ],
      ),
    );
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final AppLocalizations l = AppLocalizations.of(context);
    final AppToastHost toast = AppToastHost.of(context);
    try {
      final MemberWeeklyReport report = await ref.read(
        memberWeeklyReportProvider(widget.weekStart).future,
      );
      final List<String>? insights = await _insightLines(l);
      final Uint8List bytes = await ref
          .read(memberReportPdfGeneratorProvider)
          .generate(
            l: l,
            report: report,
            source: MemberReportSource.points,
            insightLines: insights,
          );
      if (!mounted) return;
      await openPdfPreviewPage(
        context,
        bytes,
        l.coachReportPdfFileName(_ymd(widget.weekStart)),
      );
    } catch (_) {
      toast.show(l.coachChatPdfOpenFailed, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// 그 주의 감지 기록 줄. 읽지 못하면 null 이고 문서에서 구역을 뺀다 — 감지를
  /// 못 읽었다고 "감지된 것이 없어요" 라고 적으면 사실이 아니다.
  Future<List<String>?> _insightLines(AppLocalizations l) async {
    try {
      final ChatInsightHistory history = await ref
          .read(aiCoachRepositoryProvider)
          .fetchInsights();
      return weeklyInsightLines(l, history.records, widget.weekStart);
    } catch (_) {
      return null;
    }
  }
}

/// 감지 기록 요약에 이름을 적는 종류 수. 나머지는 `외 N건` 으로 묶는다.
const int _insightKindsShown = 3;

/// [weekStart] 주(KST 월~일)에 든 감지 기록을 **종류별 횟수** 한 줄로 적는다. (#2022)
///
/// `무릎 통증 감지 2회 · 부정적 반응 감지 1회` 처럼 많은 종류가 앞이고, 세 종류를
/// 넘으면 나머지를 `외 N건` 으로 묶는다. 감지마다 한 줄씩(날짜·문장까지) 적으면 두세
/// 건만으로 문서가 두 장이 된다 — 리포트는 한 장에 담는다(#1619). 언제 무슨 말을
/// 했는지는 AI 코치의 감지 기록 창에서 본다.
///
/// 감지 시각은 KST 로 옮겨 날짜를 판정한다 — 기기 시간대로 자르면 월요일 새벽에
/// 쓴 말이 지난주로 넘어간다. 그 주에 감지가 없으면 빈 목록이다.
List<String> weeklyInsightLines(
  AppLocalizations l,
  List<ChatInsightRecord> records,
  DateTime weekStart,
) {
  final DateTime monday = DateTime(
    weekStart.year,
    weekStart.month,
    weekStart.day,
  );
  final DateTime nextMonday = DateTime(
    monday.year,
    monday.month,
    monday.day + 7,
  );
  // 종류 이름 → 횟수. 같은 횟수면 먼저 나온 종류가 앞이다(삽입 순서).
  final Map<String, int> counts = <String, int>{};
  final List<(DateTime, ChatInsightRecord)> inWeek =
      <(DateTime, ChatInsightRecord)>[
        for (final ChatInsightRecord r in records)
          if (_kst(r.createdAt) case final DateTime at
              when !at.isBefore(monday) && at.isBefore(nextMonday))
            (at, r),
      ]..sort(
        ((DateTime, ChatInsightRecord) a, (DateTime, ChatInsightRecord) b) =>
            a.$1.compareTo(b.$1),
      );
  for (final (DateTime _, ChatInsightRecord r) in inWeek) {
    counts.update(
      insightLabel(l, r.insight),
      (int n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  if (counts.isEmpty) return const <String>[];
  final List<MapEntry<String, int>> ranked = counts.entries.toList()
    ..sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value),
    );
  final int rest = ranked
      .skip(_insightKindsShown)
      .fold<int>(0, (int sum, MapEntry<String, int> e) => sum + e.value);
  return <String>[
    <String>[
      for (final MapEntry<String, int> e in ranked.take(_insightKindsShown))
        l.coachReportPdfInsightSummary(e.key, e.value),
      if (rest > 0) l.coachReportPdfInsightMore(rest),
    ].join(' · '),
  ];
}

DateTime _kst(DateTime at) {
  final DateTime seoul = at.toUtc().add(kstOffset);
  return DateTime(
    seoul.year,
    seoul.month,
    seoul.day,
    seoul.hour,
    seoul.minute,
    seoul.second,
  );
}

String _ymd(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
